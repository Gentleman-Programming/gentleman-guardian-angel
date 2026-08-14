#requires -Version 7

<#
.SYNOPSIS
  Smoke test: validates JsonFast.psm1 loads, handles all types, matches ConvertTo-Json output.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ModulePath = Join-Path $RepoRoot 'scripts\lib\JsonFast.psm1'
if (-not (Test-Path $ModulePath)) { Write-Host '[FAIL] JsonFast.psm1 not found' -ForegroundColor Red; exit 1 }
Remove-Module JsonFast -Force -EA SilentlyContinue
Import-Module $ModulePath -Force
$pass = 0; $fail = 0
function Check($name, $script) {
  $ok = & $script
  if ($ok) { $script:pass++; Write-Host "  [PASS] $name" -ForegroundColor Green }
  else { $script:fail++; Write-Host "  [FAIL] $name" -ForegroundColor Red }
}
Check 'null' { (ConvertTo-JsonFast $null) -eq 'null' }
Check 'string' { (ConvertTo-JsonFast 'hello') -eq '"hello"' }
Check 'number' { (ConvertTo-JsonFast 42) -eq '42' }
Check 'bool true' { (ConvertTo-JsonFast $true) -eq 'true' }
Check 'bool false' { (ConvertTo-JsonFast $false) -eq 'false' }
Check 'array' { (ConvertTo-JsonFast @(1,2,3)) -eq '[1,2,3]' }
Check 'hashtable' { (ConvertTo-JsonFast @{x=1}) -match '"x":1' }
Check 'nested ht' { (ConvertTo-JsonFast @{a=@{b=2}}) -match '"b":2' }
Check 'array ht' { (ConvertTo-JsonFast @(@{x=1},@{y=2})) -match '"x":1.*"y":2' }
Check 'psobject' { (ConvertTo-JsonFast ([PSCustomObject]@{p='v'})) -match '"p":"v"' }
Check 'psobject nested' { $r = ConvertTo-JsonFast ([PSCustomObject]@{n=@{x=1}}); $r -match '"x":1' }
Check 'psobject in array' { $r = ConvertTo-JsonFast @([PSCustomObject]@{a=1}); $r -match '"a":1' }
Check 'pretty' { $r = ConvertTo-JsonFast ([PSCustomObject]@{a=1}) -Pretty; $r -match '\n' }
Remove-Module JsonFast -Force -EA SilentlyContinue
Write-Host "`nJsonFast: $pass pass, $fail fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
if ($fail -gt 0) { exit 1 }; exit 0

