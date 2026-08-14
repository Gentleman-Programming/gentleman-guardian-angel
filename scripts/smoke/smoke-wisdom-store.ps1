#requires -Version 7


<#
.SYNOPSIS
  Smoke test: wisdom-store.ps1 exists and parses cleanly.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-platform config dir
$globalConfig = if ($IsLinux -or $IsMacOS) { Join-Path (Join-Path $HOME ".config") "opencode" } else { Join-Path (Join-Path $env:USERPROFILE ".config") "opencode" }
. (Join-Path (Join-Path $globalConfig "scripts") "bash-safe.ps1")

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script = Join-Path $RepoRoot 'scripts\wisdom-store.ps1'

if (-not (Test-Path $Script)) {
    Write-Host '[FAIL] wisdom-store.ps1 not found' -ForegroundColor Red
    exit 1
}

# Parse check via Get-Command — throws on syntax errors
$null = Get-Command $Script -ErrorAction Stop

Write-Host '[PASS] wisdom-store.ps1 parse check' -ForegroundColor Green
exit 0

