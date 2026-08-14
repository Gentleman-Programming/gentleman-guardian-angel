#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Check skill drift between canonical (.agents/skills/) and global config (~/.config/opencode/skills/). Optionally sync agent definitions.
  Includes adaptive polling cache: skips full scan if last check was <30s ago.
#>
param([switch]$Thorough,[switch]$AutoFix,[switch]$SyncAgents,[switch]$Json,[switch]$Quiet)
if($Quiet){$Json=$true}
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")

# ── Adaptive polling cache ─────────────────────────────────────────────
# ponytail: unified cache
$cacheScript=Join-Path $PSScriptRoot "lib/cache.ps1"
if ($env:SKILL_DRIFT_CACHE_TTL) { $cacheTtl=[int]$env:SKILL_DRIFT_CACHE_TTL } else { $cacheTtl=300 }  # seconds, configurable via env var (default 5min, was 30s)
$skipCache=$Thorough -or $AutoFix -or $SyncAgents
if(-not $skipCache){
  $cached=& $cacheScript -Action get -Key "skill-drift" -TtlSeconds $cacheTtl
  if($cached){
    if($Json -and $cached.lastJson){Write-Output $cached.lastJson;return}
    else{if(-not $Quiet){Write-Output "OK (cached) ALL $($cached.totalSkills) skills in sync! ($($cached.junctionSkills) junctions, $($cached.realFileSkills) real files)"};return}
  }
}

$cd=Join-Path $PSScriptRoot "..\.agents\skills"
$gd=Join-Path (Get-GlobalConfigDir) "skills"
$e=@();$w=@();$d=@()
if(-not (Test-Path $cd)){Write-Error "Canonical dir not found: $cd";exit 2}
if(-not (Test-Path $gd)){
  if($Json){
    @{timestamp=(Get-Date -Format "o");totalSkills=0;junctionSkills=0;realFileSkills=0;warnings=@();drifted=@();errors=@();allSynced=$true;skipped="No global config dir: $gd"} | ConvertTo-Json -Depth 3 | Write-Output
  }else{
    Write-Warning "SKIP: No global config dir ($gd) — drift check only applies on machines with global sync. $env:COMPUTERNAME"
  }
  return
}
$cs=(Get-ChildItem $cd -Directory).PSWhere({$_.Name -ne '_shared'})
foreach($s in $cs){
  $sn=$s.Name
  $cp=Join-Path $s.FullName "SKILL.md"
  if(-not (Test-Path $cp)){$e+=[PSCustomObject]@{Skill=$sn;Status="CANON_MISSING";Detail="No SKILL.md"};continue}
  $gi=Get-Item (Join-Path $gd $sn) -EA SilentlyContinue
  if(-not $gi){$e+=[PSCustomObject]@{Skill=$sn;Status="GLOBAL_MISSING";Detail="No global dir"};continue}
  if($gi.LinkType -notin @("Junction", "SymbolicLink")){$w+=[PSCustomObject]@{Skill=$sn;Status="GLOBAL_NOT_JUNCTION";Detail="Real file, not junction"}}
  if($gi.LinkType -notin @("Junction", "SymbolicLink")){
    if($Thorough){$m=(Get-FileHash $cp).Hash -eq (Get-FileHash (Join-Path $gd "$sn\SKILL.md")).Hash}
    else{$cl=([IO.File]::ReadAllText($cp) -split "`n").Count;$gl=([IO.File]::ReadAllText((Join-Path $gd "$sn\SKILL.md")) -split "`n").Count;$m=$cl -eq $gl}
    if(-not $m){$d+=[PSCustomObject]@{Skill=$sn;Status="DRIFT";Detail=if($Thorough){"Hash mismatch"}else{"Lines: canon=$cl glob=$gl"}}}
  }
}
if($AutoFix){
  $fix=$e.PSWhere({$_ -and $_.Status -eq "GLOBAL_MISSING"})
  if(@($fix).Count -gt 0){
    if(-not $Quiet){Write-Output "Creating $($fix.Count) junctions..."}
    foreach($x in $fix){
      $t=Join-Path $cd $x.Skill;$l=Join-Path $gd $x.Skill
      try{New-CrossPlatLink -Path $l -Target $t;if(-not $Quiet){Write-Output "  $l -> $t"}}catch{Write-Warning "FAIL $l ($($_.Exception.Message))"}
    }
    $e=$e.PSWhere({$_ -and $_.Status -ne "GLOBAL_MISSING"})
  }
  $gsd=Join-Path (Get-GlobalConfigDir) "scripts"
  $rsd=Join-Path $PSScriptRoot "."
  if(-not (Test-Path $gsd)){if(-not $Quiet){Write-Output "Creating scripts junction..."};try{New-CrossPlatLink -Path $gsd -Target $rsd;if(-not $Quiet){Write-Output "  $gsd -> $rsd"}}catch{Write-Warning "FAIL $gsd ($($_.Exception.Message))"}}
}
$junctionSkills=$cs.PSWhere({$g=Get-Item (Join-Path $gd $_.Name) -EA SilentlyContinue;$g -and $g.LinkType -in @("Junction", "SymbolicLink")}).Count
$realFileSkills=$cs.PSWhere({$g=Get-Item (Join-Path $gd $_.Name) -EA SilentlyContinue;$g -and $g.LinkType -notin @("Junction", "SymbolicLink")}).Count
$r=@{
  timestamp=(Get-Date -Format "o")
  totalSkills=$cs.Count
  junctionSkills=$junctionSkills
  realFileSkills=$realFileSkills
  warnings=$w;drifted=$d;errors=$e
  allSynced=($d.Count -eq 0 -and $e.Count -eq 0 -and $w.Count -eq 0)
}
# ── Write cache ──────────────────────────────────────────────────────────
# ponytail: unified cache
$jsonOut=$null
if($Json){$jsonOut=($r | ConvertTo-Json -Depth 3)}
$cacheEntry=@{
  totalSkills=$cs.Count;junctionSkills=$junctionSkills;realFileSkills=$realFileSkills
  allSynced=$r.allSynced
  lastJson=$jsonOut
}
& $cacheScript -Action set -Key "skill-drift" -Data $cacheEntry

if($Json){Write-Output $jsonOut}else{
  $wc=@($r.warnings);$dc=@($d);$ec=@($e)
  if($wc.Count -gt 0){if(-not $Quiet){Write-Output "WARNINGS: $($wc.Count)"};$r.warnings | Format-Table Skill,Status,Detail -AutoSize -EA SilentlyContinue}
  if($r.allSynced){if(-not $Quiet){Write-Output "OK ALL $($r.totalSkills) skills in sync! ($($r.junctionSkills) junctions, $($r.realFileSkills) real files)"}}else{
    if($dc.Count -gt 0){if(-not $Quiet){Write-Output "DRIFT: $($dc.Count)"};$d | Format-Table Skill,Status,Detail -AutoSize -EA SilentlyContinue}
    if($ec.Count -gt 0){if(-not $Quiet){Write-Output "ERRORS: $($ec.Count)"};$e | Format-Table Skill,Status,Detail -AutoSize -EA SilentlyContinue}
    exit 1
  }
}
function Sync-AgentDefinition{
<#
.SYNOPSIS
  Sync gentleman-* agent definitions + AGENTS.md from project to global config.
  Project opencode.json is canonical source; global config gets a copy for cross-project availability.
#>
  $pcp=Join-Path $PSScriptRoot "..\opencode.json";$gcp=Join-Path (Get-GlobalConfigDir) "opencode.json"
  $an=@("gentleman-vMK","gentleman-deep","gentleman-codex","gentleman-quick")
  $sr=@{synced=@();skipped=@()}
  if(-not $Quiet){Write-Output "--- Syncing agents (project -> global) ---"}
  if(-not (Test-Path $pcp)){Write-Warning "No project opencode.json at $pcp";return $sr}
  if(-not (Test-Path $gcp)){Write-Warning "No global opencode.json at $gcp";return $sr}
  $pj=(Get-Content $pcp -Raw) | ConvertFrom-Json;$gj=(Get-Content $gcp -Raw) | ConvertFrom-Json
  # Ensure agent section exists in global
  $gha=$gj.PSObject.Properties.Match('agent').Count -gt 0
  if(-not $gha){$gj | Add-Member -Name agent -Value @{} -MemberType NoteProperty -Force}
  # Sync each gentleman agent
  foreach($n in $an){
    $sp=$pj.agent.PSObject.Properties[$n]
    if($null -eq $sp){if(-not $Quiet){Write-Output "  [skipped] $n (not in project)"};$sr.skipped+=$n;continue}
    $gj.agent | Add-Member -Name $n -Value $sp.Value -MemberType NoteProperty -Force
    if(-not $Quiet){Write-Output "  [synced] $n"};$sr.synced+=$n
  }
  # Sync AGENTS.md for {file:AGENTS.md} reference
  $sa=Join-Path (Split-Path $pcp -Parent) "AGENTS.md"
  $da=Join-Path (Split-Path $gcp -Parent) "AGENTS.md"
  if(Test-Path $sa -PathType Leaf){Copy-Item -LiteralPath $sa -Destination $da -Force;if(-not $Quiet){Write-Output "  [synced] AGENTS.md"}}
  else{Write-Warning "  AGENTS.md not found at $sa"}
  # Write updated config
  $gj | ConvertTo-Json -Depth 10 | Set-Content $gcp -Encoding UTF8 -Force
  if(-not $Quiet){Write-Output "  -> Updated $gcp ($($sr.synced.Count) agents, AGENTS.md)"}
  return $sr
}
if($SyncAgents){Sync-AgentDefinition}
