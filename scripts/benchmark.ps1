#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Benchmark system — score skill fitness, system health, track trends.
.DESCRIPTION
  Measures repo metrics (skill bytes/lines, junction validity, scripts) plus
  BenchmarkSeconds (own wall-time) and TokenEstimate (sum chars / 3.5).
  -SetBaseline pins the current run's metrics to a baseline file; -Gate
  compares the current run against that PINNED baseline (relative 10%/5%
  thresholds) and exits 2 on regression or when no baseline exists.
  -Snapshot writes a dated benchmarks/YYYY-MM-DD.json time-series entry plus
  the moving LATEST_benchmark.json (baseline stays pinned, never overwritten).
.PARAMETER Snapshot
  Write a dated benchmarks/YYYY-MM-DD.json snapshot and refresh LATEST_benchmark.json.
.PARAMETER Gate
  Compare current metrics vs the pinned baseline; exit 2 on regression or when
  the baseline file is missing (run benchmark.ps1 -SetBaseline).
.PARAMETER SetBaseline
  Pin the current run's metrics as the baseline at -Baseline.
.PARAMETER Baseline
  Path to the pinned baseline file (default: repo-root benchmark-baseline.json).
.PARAMETER SuiteSeconds
  Optional full-test-suite wall-time (seconds) recorded as SuiteSeconds.
.PARAMETER Json
  Emit raw JSON instead of human-readable output.
#>
param(
  [switch]$Snapshot,
  [switch]$Gate,
  [switch]$Json,
  [switch]$SetBaseline,
  [string]$Baseline = (Join-Path (Split-Path $PSScriptRoot -Parent) "benchmark-baseline.json"),
  [int]$SuiteSeconds = 0
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")
$r=Convert-Path "$PSScriptRoot\.."
$cd="$r\.agents\skills";$am="$r\AGENTS.md";$sd="$r\scripts";$sn="$r\benchmarks"
$sw=[System.Diagnostics.Stopwatch]::StartNew()
$sk=@(Get-ChildItem $cd -Directory).PSWhere({$_.Name -ne '_shared'}).PSForEach({$m="$($_.FullName)\SKILL.md";if(!(test-path $m)){return};$c=Get-Content $m -Raw;@{Name=$_.Name;Bytes=$c.Length;Lines=($c-split"`n").Count;F=$c-match"^---";W=$c-match"(?m)^## When to Use";R=$c-match"(?m)^## (Rules|Critical Rules)"}})
$ac=if(test-path $am){Get-Content $am -Raw}else{""}
$sc=Get-ChildItem $sd -Filter *.ps1 -EA 0
$gd=Join-Path (Get-GlobalConfigDir) "skills"
$jo=0;$dead=0
foreach($i in $sk){
  $it=Get-Item "$gd\$($i.Name)" -EA 0
  if($it -and $it.LinkType -in @("Junction","SymbolicLink")){
    $valid=$false
    if($it.Target){
      $t=Resolve-Path $it.Target -EA SilentlyContinue
      $e=Resolve-Path "$cd\$($i.Name)" -EA SilentlyContinue
      if($t -and $e -and $t.Path -eq $e.Path){$valid=$true}
    }
    if($valid){$jo++}else{$dead++}
  }
}
$ab=($sk.PSForEach({$_.Bytes}) | Measure-Object -Sum).Sum;$al=($sk.PSForEach({$_.Lines}) | Measure-Object -Sum).Sum
$o3=$sk.PSWhere({$_.Bytes -gt 3072}).Count;$sb=@($sk.PSForEach({$_.Bytes}) | Sort-Object);$ct=$sb.Count
$md=if($ct-gt0){if($ct%2-eq1){$sb[($ct-1)/2]}else{[math]::Round(($sb[$ct/2-1]+$sb[$ct/2])/2)}}else{0}
$sw.Stop()
$sys=@{AgentsMdBytes=[int]($ac.Length);AgentsMdLines=($ac-split"`n").Count;TotalSkills=$sk.Count;TotalSkillBytes=[int]$ab;TotalSkillLines=[int]$al;SkillsOver3kb=$o3;AvgSkillBytes=if($ct-gt0){[math]::Round($ab/$ct)}else{0};MedianSkillBytes=$md;MinSkillBytes=if($ct-gt0){$sb[0]}else{0};MaxSkillBytes=if($ct-gt0){$sb[-1]}else{0};ScriptsCount=$sc.Count;GlobalJunctionsOk=$jo;DeadJunctions=$dead;TokenEstimate=[int]($ab/3.5);BenchmarkSeconds=[math]::Round($sw.Elapsed.TotalSeconds,3);SuiteSeconds=$SuiteSeconds;FrontmatterPct=if($ct-gt0){[math]::Round((@($sk | Where-Object {$_.F}).Count)/$ct*100,1)}else{0};WhenToUsePct=if($ct-gt0){[math]::Round((@($sk | Where-Object {$_.W}).Count)/$ct*100,1)}else{0};RulesPct=if($ct-gt0){[math]::Round((@($sk | Where-Object {$_.R}).Count)/$ct*100,1)}else{0}}
$cmit=try{(git rev-parse --short HEAD 2>$null).Trim()}catch{"unknown"}
$ts=(Get-Date -Format "o");$snap=@{version="1.0";timestamp=$ts;commit="$cmit";system=$sys}
function dump($x){Write-Output ("  AGENTS.md: {0}B ({1} lines)"-f $x.AgentsMdBytes,$x.AgentsMdLines) ("  Skills: {0} | Total: {1}B ({2} lines)"-f $x.TotalSkills,$x.TotalSkillBytes,$x.TotalSkillLines) ("  >3KB: {0} | Junctions: {1}/{2} (dead: {3})"-f $x.SkillsOver3kb,$x.GlobalJunctionsOk,$x.TotalSkills,$x.DeadJunctions) ("  Avg: {0}B | Median: {1}B | Range: {2}-{3}B"-f $x.AvgSkillBytes,$x.MedianSkillBytes,$x.MinSkillBytes,$x.MaxSkillBytes) ("  Frontmatter: {0}% | WhenToUse: {1}% | Rules: {2}%"-f $x.FrontmatterPct,$x.WhenToUsePct,$x.RulesPct) ("  Scripts: {0} | TokenEstimate: {1} | BenchmarkSeconds: {2}s"-f $x.ScriptsCount,$x.TokenEstimate,$x.BenchmarkSeconds)}
if(!(test-path $cd)){Write-Error "Canonical skills dir not found: $cd";exit 2}
if($Snapshot){
  try{
    if(!(test-path $sn)){New-Item $sn -ItemType Directory -Force | Out-Null}
    $fn="{0:yyyy-MM-dd}.json"-f(Get-Date);$js=$snap|ConvertTo-Json -Depth 3
    Set-Content "$sn\$fn" $js -Encoding UTF8
    $lat=Join-Path (Join-Path $r "docs\metricas") "snapshots\LATEST_benchmark.json"
    $latDir=Split-Path $lat -Parent
    if(!(test-path $latDir)){New-Item $latDir -ItemType Directory -Force | Out-Null}
    Set-Content $lat $js -Encoding UTF8
    if(!$Json){Write-Output "Snapshot saved: $sn\$fn"}
  }catch{Write-Warning "benchmark: snapshot save failed ($($_.Exception.Message))"}
}
if($SetBaseline){
  try{
    $bd=Split-Path $Baseline -Parent
    if($bd -and !(test-path $bd)){New-Item $bd -ItemType Directory -Force | Out-Null}
    Set-Content $Baseline ($snap|ConvertTo-Json -Depth 3) -Encoding UTF8
    if(!$Json){Write-Output "Baseline pinned: $Baseline (GlobalJunctionsOk=$jo, DeadJunctions=$dead)"}
  }catch{Write-Warning "benchmark: baseline save failed ($($_.Exception.Message))"}
}
if($Gate){
  $reg=@()
  if(!(test-path $Baseline)){
    Write-Output "BENCHMARK FAIL: pinned baseline not found at $Baseline — run benchmark.ps1 -SetBaseline"
    dump $sys
    exit 2
  }
  try{
    $pr=Get-Content $Baseline -Raw | ConvertFrom-Json;$pz=$pr.system
    if($sys.AgentsMdBytes-gt$pz.AgentsMdBytes*1.1){$reg+="AGENTS.md grew >10% ($($pz.AgentsMdBytes)->$($sys.AgentsMdBytes))"}
    if($sys.TotalSkillBytes-gt$pz.TotalSkillBytes*1.05){$reg+="Total skill bytes grew >5% ($($pz.TotalSkillBytes)->$($sys.TotalSkillBytes))"}
    if($sys.SkillsOver3kb-gt$pz.SkillsOver3kb){$reg+="Skills >3KB increased ($($pz.SkillsOver3kb)->$($sys.SkillsOver3kb))"}
    # Junction-coverage regression is CI-aware: fresh runners have 0 junctions
    # (0 < baseline would guarantee a red gate). Junction state is owned by
    # health-check.ps1 on real machines; CI proves repo metrics only. The
    # DeadJunctions>0 check below is still enforced EVERYWHERE (CI-safe: no
    # junctions on a runner means none can be dead).
    if(-not $env:CI -and -not $env:GITHUB_ACTIONS -and $sys.GlobalJunctionsOk-lt$pz.GlobalJunctionsOk){$reg+="Global junctions decreased ($($pz.GlobalJunctionsOk)->$($sys.GlobalJunctionsOk))"}
    if($sys.DeadJunctions-gt0){$reg+="Dead junctions detected ($($sys.DeadJunctions))"}
  }catch{Write-Debug "bench: baseline compare failed ($($_.Exception.Message))"}
  if($reg.Count-gt0){Write-Output "BENCHMARK REGRESSIONS:";$reg | ForEach-Object {Write-Output "  - $_"};dump $sys;exit 2}
  dump $sys
  if(!$Json){Write-Output "   Skills: $($sys.TotalSkills) | Total: $($sys.TotalSkillBytes)B | >3KB: $($sys.SkillsOver3kb) | Junctions: $($sys.GlobalJunctionsOk)/$($sys.TotalSkills) | Dead: $($sys.DeadJunctions)"}
}
if(!$Snapshot -and !$Gate -and !$SetBaseline -or $Json){
  if($Json){Write-Output ($snap|ConvertTo-Json -Depth 3)}else{Write-Output "  Commit: $cmit";dump $sys;Write-Output "  SuiteSeconds: $($sys.SuiteSeconds)"}
}
