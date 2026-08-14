#requires -Version 7


<#
.SYNOPSIS
  Smoke test: runs score-auto.ps1 -Quiet, passes if exit code 0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-platform config dir
$globalConfig = if ($IsLinux -or $IsMacOS) { Join-Path (Join-Path $HOME ".config") "opencode" } else { Join-Path (Join-Path $env:USERPROFILE ".config") "opencode" }
. (Join-Path (Join-Path $globalConfig "scripts") "bash-safe.ps1")

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script = Join-Path $RepoRoot 'scripts\score-auto.ps1'

if (-not (Test-Path $Script)) {
    Write-Host '[FAIL] Score freshness warning' -ForegroundColor Red
    Write-Host "  -> script not found: $Script" -ForegroundColor DarkGray
    exit 1
}

& $Script -Quiet 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host '[PASS] Score freshness warning' -ForegroundColor Green
    exit 0
} else {
    Write-Host '[FAIL] Score freshness warning' -ForegroundColor Red
    Write-Host "  -> exit $LASTEXITCODE" -ForegroundColor DarkGray
    exit 1
}

