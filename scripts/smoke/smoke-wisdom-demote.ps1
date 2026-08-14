#requires -Version 7


<#
.SYNOPSIS
  Smoke test: wisdom-demote.ps1 exists and dry-run passes.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-platform config dir
$globalConfig = if ($IsLinux -or $IsMacOS) { Join-Path (Join-Path $HOME ".config") "opencode" } else { Join-Path (Join-Path $env:USERPROFILE ".config") "opencode" }
. (Join-Path (Join-Path $globalConfig "scripts") "bash-safe.ps1")

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script = Join-Path $RepoRoot 'scripts\wisdom-demote.ps1'

if (-not (Test-Path $Script)) {
    Write-Host '[FAIL] wisdom-demote.ps1 not found' -ForegroundColor Red
    exit 1
}

# Parse check
$null = Get-Command $Script -ErrorAction Stop

# Dry-run with -All (reports what would change, makes no changes)
& $Script -All -DryRun -Quiet *>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host '[PASS] wisdom-demote.ps1 dry-run' -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] wisdom-demote.ps1 exit $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

