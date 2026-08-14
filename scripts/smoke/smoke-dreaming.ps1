#requires -Version 7


<#
.SYNOPSIS
  Smoke test: checks session-miner.ps1 exists.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-platform config dir
$globalConfig = if ($IsLinux -or $IsMacOS) { Join-Path (Join-Path $HOME ".config") "opencode" } else { Join-Path (Join-Path $env:USERPROFILE ".config") "opencode" }
. (Join-Path (Join-Path $globalConfig "scripts") "bash-safe.ps1")

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Target = Join-Path $RepoRoot 'scripts\session-miner.ps1'

if (Test-Path $Target) {
    Write-Host '[PASS] Dreaming auto-trigger (session-miner)' -ForegroundColor Green
    exit 0
} else {
    Write-Host '[FAIL] Dreaming auto-trigger (session-miner)' -ForegroundColor Red
    Write-Host "  -> not found: $Target" -ForegroundColor DarkGray
    exit 1
}

