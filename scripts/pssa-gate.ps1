#requires -Version 7
#Requires -Module @{ModuleName='PSScriptAnalyzer'; ModuleVersion='1.20.0'}
<#
.SYNOPSIS Self-Healing PSSA Gate.
.DESCRIPTION Check: scan+report. Fix: auto-fix BOM+switch defaults. Trend: compare vs baseline.
#>
[CmdletBinding(SupportsShouldProcess=$true)]param(
[Parameter(Position=0)][ValidateSet('Check','Fix','Trend','Incremental')][string]$Mode='Check',
[string]$Path=(Get-Location).Path,[switch]$Quiet,
[string]$BaselineFile=(Join-Path $Path 'docs/metricas/pssa-baseline.json'))
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
$xd=@('experiments','skills','node_modules');$xdAmp=$xd+'tests';$fr=@('PSUseBOMForUnicodeEncodedFile','PSAvoidDefaultValueSwitchParameter');$tr=@('PSAvoidUsingWriteHost')

function Write-Status { param([string]$Message) if (-not $Quiet) { Write-Host "  $Message" } }
function Get-PSSAViolation { param([string]$TargetPath,[string[]]$Files)
if($Files -and $Files.Count -gt 0){$all=@();foreach($f in $Files){if(Test-Path $f){$all+=@(Invoke-ScriptAnalyzer -Path $f -Severity Warning,Error 2>$null)}};return $all}
@(Invoke-ScriptAnalyzer -Path (Resolve-Path $TargetPath) -Recurse -Severity Warning,Error 2>$null) }
function Get-FullPath { param([string]$ScriptName,[string]$BasePath)
if ([System.IO.Path]::IsPathRooted($ScriptName)){return $ScriptName}
$j=Join-Path $BasePath $ScriptName;if(Test-Path $j){return (Resolve-Path $j).Path}
$j=Join-Path (Join-Path $BasePath 'scripts') $ScriptName;if(Test-Path $j){return (Resolve-Path $j).Path}
$j=Join-Path (Get-Location).Path $ScriptName;if(Test-Path $j){return (Resolve-Path $j).Path}
return $ScriptName }

function Get-PSSACacheKey { param([string]$TargetPath)
  "pssa-granular:$([IO.Path]::GetFullPath($TargetPath))" }
function Get-PSSACachePath { param([string]$Key)
  $dir=Join-Path ([IO.Path]::GetTempPath()) 'opencode'
  if(-not(Test-Path $dir)){try{New-Item -ItemType Directory -Path $dir -Force|Out-Null}catch{Write-Debug "pssa-cache dir: $($_.Exception.Message)"}}
  $sha=[Security.Cryptography.SHA256]::Create()
  $h=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Key)))).Replace('-','')
  Join-Path $dir "pssa-cache-$($h.Substring(0,24)).json" }
function Restore-PSSAViolation { param($Items)
  @($Items | ForEach-Object { [PSCustomObject]@{RuleName=[string]$_.RuleName;ScriptName=[string]$_.ScriptName;ScriptPath=[string]$_.ScriptPath;Line=[int]$_.Line;Severity=[string]$_.Severity;Message=[string]$_.Message} }) }
function Read-PSSACache { param([string]$CacheFile)
  $c=$null
  if(Test-Path -LiteralPath $CacheFile){
    try{
      $c=Get-Content -LiteralPath $CacheFile -Raw | ConvertFrom-Json
      if(-not $c -or -not $c.PSObject.Properties['perFile'] -or -not $c.PSObject.Properties['stamps']){$c=$null}
    }catch{$c=$null}
  }
  $c }
function Save-PSSACache { param([string]$CacheFile,[array]$Results,[array]$Manifest,[string]$Target)
  try{
    $perFile=@{}
    foreach($v in $Results){
      $sp=[string]$v.ScriptPath
      if($sp.Length -ge $Target.Length -and $sp.StartsWith($Target,[StringComparison]::OrdinalIgnoreCase)){
        $rp=$sp.Substring($Target.Length).TrimStart('\').Replace('\','/')
        if(-not $perFile.ContainsKey($rp)){$perFile[$rp]=@()}
        $perFile[$rp]+=$v
      }
    }
    $stamps=@{}
    foreach($m in $Manifest){$stamps[$m.relpath]=@{len=$m.length;mtime=$m.mtime;sha=$m.sha256}}
    @{generated=(Get-Date -Format 'o');perFile=$perFile;stamps=$stamps} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $CacheFile -Encoding UTF8
  }catch{Write-Debug "pssa-cache save: $($_.Exception.Message)"} }

function Resolve-BomEncoding { param([array]$Violations);$n=0;$s=@{}
foreach($v in $Violations){$fp=Get-FullPath -ScriptName $v.ScriptName -BasePath $target;if($s.ContainsKey($fp)){continue};$s[$fp]=$true
try{$raw=[System.IO.File]::ReadAllBytes($fp)}catch{Write-Warning "  BOM: no read $fp";continue}
$bom=$raw.Length-ge3-and$raw[0]-eq0xEF-and$raw[1]-eq0xBB-and$raw[2]-eq0xBF;if($bom){Write-Status "  BOM: present - $fp";continue}
$na=$false;foreach($b in $raw){if($b-gt127){$na=$true;break}};if(-not$na){Write-Status "  BOM: skip ASCII - $fp";continue}
try{$p=[System.Text.Encoding]::UTF8.GetPreamble();$t=[System.Text.Encoding]::UTF8.GetString($raw);[System.IO.File]::WriteAllBytes($fp,$p+[System.Text.Encoding]::UTF8.GetBytes($t));Write-Status "  BOM: FIXED - $fp";$n++}catch{Write-Warning "  BOM: ERR $fp - $_"}}
return $n }

function Resolve-SwitchDefault { param([array]$Violations);$n=0;$s=@{}
foreach($v in $Violations){$fp=Get-FullPath -ScriptName $v.ScriptName -BasePath $target;$k="$($fp):$($v.Line)";if($s.ContainsKey($k)){continue};$s[$k]=$true
try{$ln=Get-Content -LiteralPath $fp}catch{Write-Warning "  SWITCH: no read $fp";continue}
$idx=$v.Line-1;$o=$ln[$idx];$nw=$o-replace'(\[switch\]\s*\$\w+)\s*=\s*\$(?:false|true)','$1'
if($nw-ne$o){$ln[$idx]=$nw;try{Set-Content -LiteralPath $fp -Value $ln -Encoding UTF8;Write-Status "  SWITCH: FIXED - ${fp}:$($v.Line)";$n++}catch{Write-Warning "  SWITCH: ERR ${fp}:$($v.Line) - $_"}}}
return $n }

function Save-Baseline { param([array]$Results,[array]$ManualV,[int]$AmpersandCount)
$bl=@{timestamp=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss');total=$Results.Count;byRule=$Results | Group-Object RuleName | ForEach-Object {@{rule=$_.Name;count=$_.Count}};byFile=$Results | Group-Object ScriptName | ForEach-Object {@{file=$_.Name;count=$_.Count}};autoFixableCount=($Results | Where-Object {$_.RuleName -in $fr}).Count;trackedCount=($Results | Where-Object {$_.RuleName -in $tr}).Count;manualCount=$ManualV.Count;manualPairs=($ManualV | Group-Object {"$($_.RuleName)|$($_.ScriptName)"} | ForEach-Object {$p=$_.Name -split '\|';@{rule=$p[0];file=$p[1];count=$_.Count}});ampersandCount=$AmpersandCount}
$di=Split-Path $BaselineFile -Parent;if(-not(Test-Path $di)){New-Item -ItemType Directory -Path $di -Force | Out-Null}
$bl | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $BaselineFile -Encoding UTF8;return $bl}

$target=Resolve-Path $Path
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\lib\file-manifest.ps1')
$scanFiles=$null
if($Mode -eq 'Incremental'){
  $changed=@(git -C $target diff --cached --name-only --diff-filter=ACMR -- '*.ps1' 2>$null | Where-Object {$_} | ForEach-Object {Join-Path $target ($_.Replace('/','\'))} | Where-Object {Test-Path $_})
  if($changed.Count -gt 0){$scanFiles=$changed;Write-Status "Incremental: $($changed.Count) changed file(s)"}
  else{Write-Status "Incremental: no cached .ps1 changes — falling back to full scan"}
}
if(-not$Quiet){Write-Host "== PSSA Gate - $Mode ==";Write-Host "  Target: $target"}
$useCache = $Mode -in 'Check','Incremental' -and -not $scanFiles
$cacheFile = $null
$manifest = $null
$results = $null
if($useCache){
  $cacheFile=Get-PSSACachePath -Key (Get-PSSACacheKey -TargetPath $target.Path)
  $manifest=@(Get-FileManifest -Path $target.Path | Where-Object { $_.group -eq 'script' })
  $cached=Read-PSSACache -CacheFile $cacheFile
    if($cached){
      $stamps=@{};foreach($p in $cached.stamps.PSObject.Properties){$stamps[$p.Name]=$p.Value}
      $manifestSet=@{};foreach($m in $manifest){$manifestSet[$m.relpath]=$true}
      $changed=@();$hitCount=0
      foreach($m in $manifest){
        $s=$null
        if($stamps.ContainsKey($m.relpath)){$s=$stamps[$m.relpath]}
        if($s -and [int64]$s.len -eq $m.length -and [int64]$s.mtime -eq $m.mtime -and [string]$s.sha -eq $m.sha256){$hitCount++}
        else{$changed+=$m.relpath}
      }
      if($changed.Count -eq 0){
        $flat=@();foreach($p in $cached.perFile.PSObject.Properties){if($manifestSet.ContainsKey($p.Name)){$flat+=@(Restore-PSSAViolation $p.Value)}}
        $results=$flat
        Write-Status "PSSA cache hit: $($results.Count) violations ($hitCount files)"
      }else{
        Write-Status "PSSA granular: $($changed.Count) changed file(s), $hitCount cached"
        $changedSet=@{};foreach($rp in $changed){$changedSet[$rp]=$true}
        $cachedHits=@();foreach($p in $cached.perFile.PSObject.Properties){if(-not $changedSet.ContainsKey($p.Name) -and $manifestSet.ContainsKey($p.Name)){$cachedHits+=@(Restore-PSSAViolation $p.Value)}}
        $scanPaths=@($changed|ForEach-Object{Join-Path $target.Path ($_ -replace '/','\')}|Where-Object{Test-Path $_})
        $newV=@()
        if($scanPaths.Count -gt 0){$newV=@(Get-PSSAViolation -TargetPath $target.Path -Files $scanPaths)}
        $newV=@($newV|Where-Object{$_.ScriptPath -notmatch '[\\/]node_modules[\\/]'})
        $results=@($cachedHits)+@($newV)
      }
    }
}
if($null -eq $results){
  Write-Status "Scanning..."
  $results=@(Get-PSSAViolation -TargetPath $target.Path -Files $scanFiles)
  $results=@($results | Where-Object { $_.ScriptPath -notmatch '[\\/]node_modules[\\/]' })
}
if($useCache -and $cacheFile -and $null -ne $manifest){Save-PSSACache -CacheFile $cacheFile -Results $results -Manifest $manifest -Target $target.Path}

if($Mode -eq 'Fix'){Write-Host "`n-- Auto-fix --";$bf=Resolve-BomEncoding -Violations ($results | Where-Object {$_.RuleName -eq 'PSUseBOMForUnicodeEncodedFile'});$sf=Resolve-SwitchDefault -Violations ($results | Where-Object {$_.RuleName -eq 'PSAvoidDefaultValueSwitchParameter'});Write-Host "  BOM: $bf | Switch: $sf";Write-Status "Re-scanning...";$results=Get-PSSAViolation -TargetPath $target -Files $scanFiles}

$af=@($results | Where-Object {$_.RuleName -in $fr});$td=@($results | Where-Object {$_.RuleName -in $tr});$manual=@($results | Where-Object {$_.RuleName -notin ($fr+$tr)})
$ev=@($manual | Where-Object {$sp=$_.ScriptPath.Replace('\','/');$sk=$false;foreach($d in $xdAmp){if($sp-match"/$d/"){$sk=$true;break}};$sk})
$manual=@($manual | Where-Object {$sp=$_.ScriptPath.Replace('\','/');$sk=$false;foreach($d in $xdAmp){if($sp-match"/$d/"){$sk=$true;break}};-not$sk})

$kx=@('bash-safe.ps1','pssa-gate.ps1')
$av=[IO.Directory]::EnumerateFiles($target, '*.ps1', [IO.SearchOption]::AllDirectories) | ForEach-Object -Parallel {
    $rp=$_.Replace($using:target,'').TrimStart('\')
    $sk=$false
    foreach($ex in $using:kx){if($rp-match[regex]::Escape($ex)){$sk=$true}}
    foreach($d in $using:xdAmp){if($rp-match"(^|[\\/])$d[\\/]"){$sk=$true}}
    if($sk){return}
    try{$ln=[IO.File]::ReadAllText($_)}catch{return}
    $ln=$ln -split '\r?\n'
    $res=@()
    for($i=0;$i-lt$ln.Count;$i++){
        $t=$ln[$i].Trim()
        if($t-eq''-or$t.StartsWith('#')){continue}
        if($t-match'(^|[^""])&&([^""]|$)'){$res+=[PSCustomObject]@{ScriptName=$rp;Line=$i+1;Text=$t}}
    }
    $res
} -ThrottleLimit 4
$av=@($av|Where-Object{$_})
$ac=$av.Count

if(-not$Quiet){Write-Host "`n-- Summary --"
$modeLabel=if($Mode -eq 'Incremental' -and $scanFiles){" (incremental: $($scanFiles.Count) files)"}else{""}
Write-Host "  Total: $($results.Count)$modeLabel | &&: $ac | Auto: $($af.Count) | Tracked: $($td.Count) | Excluded: $(@($ev).Count) | Manual: $($manual.Count)"
if($ac-gt0){Write-Host "`n-- && violations (PS5.1) --";$av | Select-Object ScriptName,Line,Text | Format-Table -AutoSize | Out-String | Write-Host}
if($manual.Count-gt0){Write-Host "`n-- Manual review (PSSA) --";$manual | Group-Object RuleName | ForEach-Object {Write-Host "  $($_.Name): $($_.Count)"};$manual | Select-Object RuleName,Line,ScriptName | Format-Table -AutoSize | Out-String | Write-Host}}

$ec=0
switch($Mode){
'Trend'{$prior=if(Test-Path $BaselineFile){Get-Content -LiteralPath $BaselineFile -Raw | ConvertFrom-Json}else{$null};$bl=Save-Baseline -Results $results -ManualV $manual -AmpersandCount $ac
if($prior){$d=$results.Count-$prior.total;$s=if($d-gt0){'+'}else{''};$pa=if($prior.PSObject.Properties['ampersandCount']){($prior.ampersandCount -as[int])}else{0};$ad=$ac-$pa;$as=if($ad-gt0){'+'}else{''}
Write-Host "`n-- Trend --";Write-Host "  PSSA: $($prior.total)->$($results.Count)|D:$s$d";Write-Host "  &&: $($prior.ampersandCount)->$ac|D:$as$ad"
if($d-gt0-or$ad-gt0){Write-Warning "  Some INCREASED"}elseif($d-lt0-and$ad-le0){Write-Host "  DECREASED - good!"}else{Write-Host "  Steady."}}else{Write-Host "  No prior data."}}
{$_ -in 'Check','Incremental'}{
$bl=$null;if(Test-Path $BaselineFile){$bl=Get-Content -LiteralPath $BaselineFile -Raw | ConvertFrom-Json}
if(-not $bl -or -not $bl.PSObject.Properties['manualPairs']){
  if($Mode -eq 'Incremental' -and $scanFiles){Write-Warning "PSSA Gate: baseline obsoleto (sin manualPairs). Correr -Mode Check o -Mode Trend para regenerar con scan completo."}
  else{Save-Baseline -Results $results -ManualV $manual -AmpersandCount $ac | Out-Null;Write-Status "Baseline saved to $BaselineFile";$bl=Get-Content -LiteralPath $BaselineFile -Raw | ConvertFrom-Json}
}
$regr=@();$cur=@{}
if($bl.PSObject.Properties['manualPairs'] -and $manual.Count-gt0){
  foreach($v in $manual){$k="$($v.RuleName)|$($v.ScriptName.Replace('\','/'))";if($cur.ContainsKey($k)){$cur[$k]++}else{$cur[$k]=1}}
  $base=@{};foreach($p in $bl.manualPairs){$base["$($p.rule)|$($p.file.Replace('\','/'))"]=[int]$p.count}
  foreach($k in $cur.Keys){$bc=if($base.ContainsKey($k)){$base[$k]}else{0};if($cur[$k]-gt$bc){$regr+=@{key=$k;now=$cur[$k];base=$bc}}}
}
if($regr.Count-gt0){Write-Warning "PSSA Gate: $($regr.Count) REGRESSION(s) vs baseline: $($regr | ForEach-Object {"$($_.key) $($_.base)->$($_.now)"})";$ec=1}
}}

if($Mode -in 'Check','Incremental' -and $ec-eq0-and$manual.Count-gt0){Write-Host "  Deuda baselined: $($manual.Count) known violations (no regression)."}
if($ac-gt0-and$Mode-ne'Trend'){Write-Warning "PSSA Gate: $ac && violations. Use bash-safe.ps1.";$ec=1}
if($ec-eq0){Write-Host "`nPSSA Gate PASSED."}
exit $ec
