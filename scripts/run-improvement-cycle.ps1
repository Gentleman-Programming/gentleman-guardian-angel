#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Continuous Improvement Cycle — measure, compress, validate, log, repeat.
#>
param([string]$RepoRoot="",[switch]$AutoCompress,[switch]$Quiet)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
if(!$RepoRoot){$RepoRoot=Split-Path $PSScriptRoot -Parent}
$cdir=Join-Path $RepoRoot ".agents\skills"
if(!(Test-Path $cdir)){Write-Host "[FATAL] Repo root not found: $RepoRoot" -ForegroundColor Red;exit 1}
$agp=Join-Path $RepoRoot "AGENTS.md"
$lp=Join-Path $RepoRoot ".learnings\LEARNINGS.md"
$agsz=0
if(Test-Path $agp){$agsz=(Get-Item $agp).Length}
$agkb=[math]::Round($agsz/1024.0,1)
Write-Host "AG: $agkb KB ($agsz bytes)" -ForegroundColor Yellow
$sf=New-Object System.Collections.ArrayList
if(Test-Path $cdir){
  Get-ChildItem $cdir -Directory | ForEach-Object {
    $mp=Join-Path $_.FullName "SKILL.md"
    if(Test-Path $mp){$null=$sf.Add((Get-Item $mp))}
  }
}
$sc=$sf.Count
$tsz=0.0
$sf | ForEach-Object {$tsz+=$_.Length}
$tkb=[math]::Round($tsz/1024.0,1)
Write-Host "Skills: $sc files, $tkb KB total" -ForegroundColor Yellow
$big5=$sf | Sort-Object Length -Descending | Select-Object -First 5
Write-Host "Largest:" -ForegroundColor Gray
$big5 | ForEach-Object {$r=$_.FullName.Replace($RepoRoot,"").TrimStart("\");$k=[math]::Round($_.Length/1024.0,1);Write-Host "  $r : $k KB" -ForegroundColor DarkYellow}
$vb=New-Object System.Collections.ArrayList
$tvb=0.0
$sf | ForEach-Object {if($_.Length -gt 3072){$null=$vb.Add($_);$tvb+=$_.Length}}
$vc=$vb.Count
$vkb=[math]::Round($tvb/1024.0,1)
if($vc -gt 0){Write-Host "Verbose (>3KB): $vc files, $vkb KB" -ForegroundColor Magenta;if($AutoCompress){Write-Host "  Auto-compress on" -ForegroundColor Green}}else{Write-Host "No verbose skills" -ForegroundColor Green}
Write-Host "Cross-ref..." -ForegroundColor Cyan
$cre=0;$crw=0;$crc=$true
$crs=Join-Path $PSScriptRoot "cross-ref-check.ps1"
if(Test-Path $crs){$cro=& $crs -Json 2>$null;$crj=$cro-join"`n";try{$crp=$crj | ConvertFrom-Json;$cre=$crp.errors.Count;$crw=$crp.warnings.Count;if($cre -gt 0){Write-Host "Xref: $cre ERROR(S)" -ForegroundColor Red;$crp.errors | ForEach-Object {Write-Host "  $_" -ForegroundColor Red};$crc=$false}else{Write-Host "Xref: OK ($crw warn)" -ForegroundColor Green}}catch{Write-Host "Xref: parse error" -ForegroundColor Red;$cre=1}}else{Write-Host "Xref: script not found" -ForegroundColor Yellow}
$estk=[math]::Round($tsz/4.0);$esta=[math]::Round($agsz/3.0);$estt=$estk+$esta
Write-Host "Tokens: ~$estt (skills ~$estk, AGENTS.md ~$esta)" -ForegroundColor Yellow
$ds=Join-Path $PSScriptRoot "run-dreaming.ps1"
if(Test-Path $ds){Write-Host "Dreaming scan..." -ForegroundColor Cyan;& $ds -Mode report}else{Write-Host "Dreaming script not found" -ForegroundColor Yellow}
$d=(Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$id="CYC-"+(Get-Date -Format "yyyyMMdd")+"-"+(Get-Random -Minimum 100 -Maximum 999)
$nl="`r`n"
$le=$nl
$le+=$nl+"## "+$id+" improvement_cycle"+$nl
$le+=$nl+"**Logged**: "+$d+$nl
$le+="**Priority**: medium"+$nl
$le+="**Status**: completed"+$nl
$le+="**Area**: system"+$nl
$le+=$nl+"### Summary"+$nl
$le+="Cycle: "+$sc+" skills ("+$tkb+" KB), AGENTS.md ("+$agkb+" KB), xref check."+$nl
$le+=$nl+"### Details"+$nl
$le+="- AGENTS.md: "+$agkb+" KB ("+$agsz+" bytes)"+$nl
$le+="- Skills: "+$sc+" files, "+$tkb+" KB total"+$nl
$le+="- Verbose (>3KB): "+$vc+" files, "+$vkb+" KB"+$nl
$le+="- Tokens: ~"+$estt+" (skills ~"+$estk+", AGENTS.md ~"+$esta+")"+$nl
$le+="- Cross-ref errors: "+$cre+$nl
$le+=$nl+"### Suggested Action"+$nl
$le+="Review and trim files >3KB."+$nl
$le+=$nl+"### Metadata"+$nl
$le+="- **Source**: run-improvement-cycle.ps1"+$nl
$le+="- **Related-Files**: AGENTS.md, .agents/skills/*/SKILL.md"+$nl
$le+="- **Tags**: improvement-cycle, automation"+$nl
$le+="- **See-Also**: run-improvement-cycle.ps1"+$nl
$le+="- **Pattern-Key**: improvement/cycle"+$nl
if(Test-Path $lp){Add-Content $lp -Value $le -Encoding UTF8;Write-Host "Logged as $id" -ForegroundColor Green}else{Write-Host "WARNING: .learnings not found" -ForegroundColor Yellow}
$r=New-Object PSObject
$r | Add-Member NoteProperty "cycleId" $id
$r | Add-Member NoteProperty "timestamp" $d
$m=New-Object PSObject
$m | Add-Member NoteProperty "agSizeKB" $agkb
$m | Add-Member NoteProperty "skillCount" $sc
$m | Add-Member NoteProperty "totalSkillKB" $tkb
$m | Add-Member NoteProperty "verboseOver3KB" $vc
$m | Add-Member NoteProperty "estTokenTotal" $estt
$r | Add-Member NoteProperty "metrics" $m
$x=New-Object PSObject
$x | Add-Member NoteProperty "errors" $cre
$x | Add-Member NoteProperty "warnings" $crw
$x | Add-Member NoteProperty "allClean" $crc
$r | Add-Member NoteProperty "crossRef" $x
if($Quiet){$r | ConvertTo-Json -Depth 3}
$r
exit 0
