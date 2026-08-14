#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Downstream validation of CYCLE-3 skills: delivery-harness, chained-pr, subagent-isolation.
#>
param([switch]$Json)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ec=0;$r=@()
function AR($s,$c,$st,$d){$script:r+=[PSCustomObject]@{Section=$s;Check=$c;Status=$st;Detail=$d};if($st-ne"PASS"){$script:ec=1}}
function TSF($n){$sr=Split-Path -Par $PSCommandPath;$p=Join-Path $sr "..\.agents\skills\$n\SKILL.md";if(!(Test-Path $p)){AR Structure "Skill: $n" FAIL "Not found";return $null};return $p}
function GSC{param([string]$p);try{return Get-Content -Raw -Lit $p -EA Stop}catch{Write-Warning "Can't read ${p}: $_";return $null}}
try{
$dhp=TSF delivery-harness;$cpp=TSF chained-pr;$sip=TSF subagent-isolation
if(!$dhp -or !$cpp){AR Structure "Core skills" FAIL "Missing core SKILL.md"}else{
$dh=GSC $dhp;if(!$dh){$dh=""}
$steps=@('Analyze','Break down','Map deps','Delegate','Collect','Reconcile','Report')
$fs=0;foreach($s in $steps){if($dh-match"\*{1,2}$s"){$fs++}else{AR Delivery-Harness "Step: $s" WARN "Missing"}}
AR Delivery-Harness "7-step workflow" $(if($fs-eq7){"PASS"}else{"FAIL"}) "Found $fs/7"
$ets=@('Subagent timeout','Wrong output','Dependency fail','Merge conflict')
$fe=0;foreach($e in $ets){if($dh-match[regex]::Escape($e)){$fe++}}
AR Delivery-Harness "Error table" $(if($fe-eq4){"PASS"}else{"FAIL"}) "Found $fe/4"
AR Delivery-Harness "Dep: subagent-isolation" $(if($dh-match'subagent-isolation'){"PASS"}else{"FAIL"}) ""
AR Delivery-Harness "Dep: work-unit-commits" $(if($dh-match'work-unit-commits'){"PASS"}else{"FAIL"}) ""
AR Delivery-Harness "Dep: command-wrapper" $(if($dh-match'command-wrapper'){"PASS"}else{"FAIL"}) ""
$cp=GSC $cpp;if(!$cp){$cp=""}
AR Chained-PR "Chain structure diagram" $(if($cp-match'main ── PR#1'){"PASS"}else{"FAIL"}) "main--PR#1--PR#2--PR#3"
AR Chained-PR "Branch naming convention" $(if($cp-match'feat/{prefix}-{n}-{slug}'){"PASS"}else{"FAIL"}) "feat/{prefix}-{n}-{slug}"
AR Chained-PR "Rebase cascade" $(if($cp-match'REBASE CASCADE'){"PASS"}else{"FAIL"}) ""
AR Chained-PR "Rollback procedure" $(if($cp-match'ROLLBACK'){"PASS"}else{"FAIL"}) ""
AR Chained-PR "Max chain: 5" $(if($cp-match'Max chain length: 5'){"PASS"}else{"FAIL"}) ""
AR Chained-PR "Dep: work-unit-commits" $(if($cp-match'work-unit-commits'){"PASS"}else{"FAIL"}) ""
AR Chained-PR "Dep: command-wrapper" $(if($cp-match'command-wrapper'){"PASS"}else{"FAIL"}) ""
if($sip){$si=GSC $sip;if(!$si){$si=""}
$ir=@('Fresh context per delegation','No cross-contamination','Dependency declaration','Result isolation','Context cleanup','Error boundaries')
$fr=0;foreach($rule in $ir){if($si-match[regex]::Escape($rule)){$fr++}else{AR "Subagent-Isolation" "Rule: $rule" WARN "Not found"}}
AR Subagent-Isolation "6 isolation rules" $(if($fr-eq6){"PASS"}else{"FAIL"}) "Found $fr/6"}
$dd=@();if($dh-match'subagent-isolation'){$dd+='subagent-isolation'};if($dh-match'work-unit-commits'){$dd+='work-unit-commits'};if($dh-match'command-wrapper'){$dd+='command-wrapper'}
AR Cross-Ref "DH dependencies resolved" PASS "$($dd.Count) deps: $($dd-join', ')"
AR Size "delivery-harness" PASS "$((Get-Item $dhp).Length) bytes"
AR Size "chained-pr" PASS "$((Get-Item $cpp).Length) bytes"
if($sip){AR Size "subagent-isolation" PASS "$((Get-Item $sip).Length) bytes"}}
}catch{AR Fatal Execution FAIL "Unhandled exception: $_"}
if($Json){$r | ConvertTo-Json -D 3}else{
$pass=@($r | Where-Object {$_.Status -eq "PASS"}).Count;$fail=@($r | Where-Object {$_.Status -eq "FAIL"}).Count;$warn=@($r | Where-Object {$_.Status -eq "WARN"}).Count
$r | Group-Object Section | ForEach-Object {$_.Group | Format-Table Check,Status,Detail -Auto}
Write-Output "=== Summary: $pass PASS, $fail FAIL, $warn WARN ==="}
exit $ec
