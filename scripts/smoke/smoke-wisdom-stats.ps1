#requires -Version 7


<#
.SYNOPSIS
  Smoke test: wisdom-stats.ps1 exists and outputs JSON.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-platform config dir
$globalConfig = if ($IsLinux -or $IsMacOS) { Join-Path (Join-Path $HOME ".config") "opencode" } else { Join-Path (Join-Path $env:USERPROFILE ".config") "opencode" }
. (Join-Path (Join-Path $globalConfig "scripts") "bash-safe.ps1")

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script = Join-Path $RepoRoot 'scripts\wisdom-stats.ps1'

if (-not (Test-Path $Script)) {
    Write-Host '[FAIL] wisdom-stats.ps1 not found' -ForegroundColor Red
    exit 1
}

# Run with -Json (machine output, no side effects)
$output = & $Script -Json *>&1 | Out-String

if ($LASTEXITCODE -eq 0) {
    # Verify output is valid JSON
    try { $null = $output | ConvertFrom-Json -ErrorAction Stop } catch {
        Write-Host '[FAIL] wisdom-stats.ps1 output not valid JSON' -ForegroundColor Red
        exit 1
    }
    Write-Host '[PASS] wisdom-stats.ps1 JSON output' -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] wisdom-stats.ps1 exit $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

