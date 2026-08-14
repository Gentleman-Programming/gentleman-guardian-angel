#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<# .SYNOPSIS Trend analysis: scoring snapshots over time #>
$d=$args[0]
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sd = Split-Path $PSCommandPath
$r = Split-Path $sd
if (-not $d) { $d = "$r\docs\metricas\snapshots" }
if (-not (Test-Path $d)) { Write-Error ("Missing snaps: {0}" -f $d); exit 1 }
$sf = @(Get-ChildItem $d -Filter *.json | Where-Object { $_.Name -ne "LATEST_benchmark.json" } | Sort-Object LastWriteTime)
if ($sf.Count -eq 0) { Write-Output "No snaps $d"; exit 0 }
$s = @()
foreach ($f in $sf) {
  try { $j = Get-Content $f.FullName -Raw | ConvertFrom-Json; $s += $j } catch { Write-Debug "skip $($f.Name)"; continue }
}
$fst=$s[0];$lst=$s[-1]
$span=[math]::Round(((Get-Date $lst.timestamp)-(Get-Date $fst.timestamp)).TotalDays,1)
function TA($f,$l,$h=$true){if($f-eq$l){return"="};if(($l-gt$f)-xor$h){return"-"};return"+"}
function D($f,$l){"$(if($l-ge$f){'+'})$($l-$f)"}
function FI($v){return"{0:N0}"-f$v}
function FP($v){return("{0:F1}"-f$v)+"%"}
function FB($v){if($v-ge1000){return("{0:N1}"-f[math]::Round($v/1000,1))+"KB"};return"$v"+"B"}
Write-Output "# Trends"
Write-Output ("**Snapshots**: {0} | **Period**: {1} -> {2} ({3} days)"-f$s.Count,(Get-Date $fst.timestamp).ToString("yyyy-MM-dd"),(Get-Date $lst.timestamp).ToString("yyyy-MM-dd"),$span)
Write-Output ("Commit: {0}"-f$lst.commit)
Write-Output "## Metrics"
Write-Output "| Metric | First | Current | Delta | Trend |"
Write-Output "|--------|-------|---------|-------|-------|"
$metrics=@(
@{N="AGENTS Size";F={param($v)FB$v};B=$false;V1={$fst.system.AgentsMdBytes};V2={$lst.system.AgentsMdBytes}}
@{N="AGENTS Lines";F={param($v)FI$v};B=$false;V1={$fst.system.AgentsMdLines};V2={$lst.system.AgentsMdLines}}
@{N="Total Skills";F={param($v)FI$v};B=$true;V1={$fst.system.TotalSkills};V2={$lst.system.TotalSkills}}
@{N="Total Skill Size";F={param($v)FB$v};B=$false;V1={$fst.system.TotalSkillBytes};V2={$lst.system.TotalSkillBytes}}
@{N="Avg Skill Size";F={param($v)FB$v};B=$false;V1={$fst.system.AvgSkillBytes};V2={$lst.system.AvgSkillBytes}}
@{N="Skills >3KB";F={param($v)FI$v};B=$true;V1={$fst.system.SkillsOver3kb};V2={$lst.system.SkillsOver3kb}}
@{N="Global Juncs";F={param($v)("{0}/{1}"-f$v,$lst.system.TotalSkills)};B=$true;V1={$fst.system.GlobalJunctionsOk};V2={$lst.system.GlobalJunctionsOk}}
@{N="Frontmatter";F={param($v)FP$v};B=$true;V1={$fst.system.FrontmatterPct};V2={$lst.system.FrontmatterPct}}
@{N="When-to-Use";F={param($v)FP$v};B=$true;V1={$fst.system.WhenToUsePct};V2={$lst.system.WhenToUsePct}}
@{N="Rules Section";F={param($v)FP$v};B=$true;V1={$fst.system.RulesPct};V2={$lst.system.RulesPct}}
@{N="Scripts Count";F={param($v)FI$v};B=$true;V1={$fst.system.ScriptsCount};V2={$lst.system.ScriptsCount}}
)
foreach($m in $metrics){$v1=&$m.V1;$v2=&$m.V2;Write-Output ("| {0} | {1} | {2} | {3} | {4} |"-f$m.N,(&$m.F$v1),(&$m.F$v2),(D $v1 $v2),(TA $v1 $v2 $m.B))}
Write-Output "## Timeline"
Write-Output "| Date | Commit | AGENTS | Skills | Avg | >3KB | Junc | Scripts | Front | W2U | Rules |"
Write-Output "|------|--------|--------|-------|-----|------|------|---------|-------|-----|-------|"
foreach($t in $s){Write-Output ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |"-f (Get-Date $t.timestamp).ToString("MM-dd HH:mm"),$t.commit,(FB $t.system.AgentsMdBytes),$t.system.TotalSkills,(FB $t.system.AvgSkillBytes),$t.system.SkillsOver3kb,("{0}/{1}"-f $t.system.GlobalJunctionsOk,$t.system.TotalSkills),$t.system.ScriptsCount,(FP $t.system.FrontmatterPct),(FP $t.system.WhenToUsePct),(FP $t.system.RulesPct))}
$ed="$r\docs\metricas\errors"
$ef=@(Get-ChildItem $ed -Filter *_error.json -EA 0 | Where-Object { $_.Name -ne "LATEST_error.json" } | Sort-Object LastWriteTime)
if($ef.Count-gt0){Write-Output "## Errors";Write-Output "| Date | Commit | Source | Pass | Fail | Errors | Blocked |";Write-Output "|------|--------|--------|------|------|--------|---------|";$ee=$ef | ForEach-Object {try{Get-Content $_.FullName -Raw | ConvertFrom-Json}catch{$null}} | Where-Object {$_};foreach($e in $ee){Write-Output ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |"-f (Get-Date $e.timestamp).ToString("MM-dd HH:mm"),$e.commit,$e.source,$e.passed,$e.failed,$e.totalErrors,$e.blocked)}}
Write-Output ""
