#requires -Version 7


<#
.SYNOPSIS
  Smoke test: wisdom-forge.ps1 exists, parses, and dry-run with a seed pattern.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-platform config dir
$globalConfig = if ($IsLinux -or $IsMacOS) { Join-Path (Join-Path $HOME ".config") "opencode" } else { Join-Path (Join-Path $env:USERPROFILE ".config") "opencode" }
. (Join-Path (Join-Path $globalConfig "scripts") "bash-safe.ps1")

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script = Join-Path $RepoRoot 'scripts\wisdom-forge.ps1'

if (-not (Test-Path $Script)) {
    Write-Host '[FAIL] wisdom-forge.ps1 not found' -ForegroundColor Red
    exit 1
}

# Parse check
$null = Get-Command $Script -ErrorAction Stop

# Dry-run with a seed pattern (no side effects)
$PatternFile = Join-Path $RepoRoot 'docs\cross-project\patterns\ux-a11y-hero-btn-contrast.json'

if (-not (Test-Path $PatternFile)) {
    Write-Host '[SKIP] wisdom-forge.ps1 dry-run — no seed pattern to test' -ForegroundColor Yellow
    Write-Host '[PASS] wisdom-forge.ps1 parse check' -ForegroundColor Green
    exit 0
}

$output = & $Script -PatternFile $PatternFile -DryRun -Quiet *>&1 | Out-String

if ($LASTEXITCODE -eq 0) {
    # Verify JSON output
    try { $null = $output | ConvertFrom-Json -ErrorAction Stop } catch {
        Write-Host '[FAIL] wisdom-forge.ps1 output not valid JSON' -ForegroundColor Red
        exit 1
    }
    Write-Host '[PASS] wisdom-forge.ps1 dry-run' -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] wisdom-forge.ps1 exit $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

