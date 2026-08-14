#requires -Version 7


<#
.SYNOPSIS
  Smoke test: wisdom-loader.ps1 exists and runs with defaults.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-platform config dir
$globalConfig = if ($IsLinux -or $IsMacOS) { Join-Path (Join-Path $HOME ".config") "opencode" } else { Join-Path (Join-Path $env:USERPROFILE ".config") "opencode" }
. (Join-Path (Join-Path $globalConfig "scripts") "bash-safe.ps1")

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script = Join-Path $RepoRoot 'scripts\wisdom-loader.ps1'

if (-not (Test-Path $Script)) {
    Write-Host '[FAIL] wisdom-loader.ps1 not found' -ForegroundColor Red
    exit 1
}

# Parse + run with defaults (reads all patterns, no side effects)
& $Script *>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host '[PASS] wisdom-loader.ps1 run with defaults' -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] wisdom-loader.ps1 exit $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

