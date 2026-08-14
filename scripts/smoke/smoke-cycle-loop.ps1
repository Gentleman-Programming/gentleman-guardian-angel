#requires -Version 7


<#
.SYNOPSIS
  Smoke test: checks CYCLE.md contains "freshness".
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-platform config dir
$globalConfig = if ($IsLinux -or $IsMacOS) { Join-Path (Join-Path $HOME ".config") "opencode" } else { Join-Path (Join-Path $env:USERPROFILE ".config") "opencode" }
. (Join-Path (Join-Path $globalConfig "scripts") "bash-safe.ps1")

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$CyclePath = Join-Path $RepoRoot 'CYCLE.md'

if (-not (Test-Path $CyclePath)) {
    Write-Host '[FAIL] Cycle LOOP step 3 freshness check' -ForegroundColor Red
    Write-Host "  -> CYCLE.md not found" -ForegroundColor DarkGray
    exit 1
}

$cycle = Get-Content $CyclePath -Raw -Encoding UTF8
$hasFreshness = $cycle -match 'freshness'

if ($hasFreshness) {
    Write-Host '[PASS] Cycle LOOP step 3 freshness check' -ForegroundColor Green
    exit 0
} else {
    Write-Host '[FAIL] Cycle LOOP step 3 freshness check' -ForegroundColor Red
    Write-Host '  -> "freshness" not found in CYCLE.md' -ForegroundColor DarkGray
    exit 1
}

