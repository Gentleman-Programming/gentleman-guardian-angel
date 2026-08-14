#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

<#
.SYNOPSIS
  Run all automation claim smoke tests for CYCLE.md metrics.
  Cachea resultados por hash de contenido + git HEAD.
.PARAMETER Json
  JSON output for agent consumption.
.PARAMETER Force
  Bypass cache y forzar ejecución de todos los tests.
#>

param([switch]$Json, [switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-platform config dir
$globalConfig = if ($IsLinux -or $IsMacOS) { Join-Path (Join-Path $HOME ".config") "opencode" } else { Join-Path (Join-Path $env:USERPROFILE ".config") "opencode" }
. (Join-Path (Join-Path $globalConfig "scripts") "bash-safe.ps1")

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:passed = 0
$script:failed = 0
$script:smokeResults = @()
$CachePath = "$env:TEMP\gentleman-smoke-cache.json"

function Add-SmokeResult {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $script:smokeResults += @{ name = $Name; passed = $Passed; detail = $Detail }
    if ($Passed) { $script:passed++ } else { $script:failed++ }
    $color = if ($Passed) { 'Green' } else { 'Red' }
    $symbol = if ($Passed) { 'PASS' } else { 'FAIL' }
    Write-Host "[$symbol] $Name" -ForegroundColor $color
    if (-not $Passed -and $Detail) { Write-Host "  -> $Detail" -ForegroundColor DarkGray }
}

$smokeDir = Join-Path $RepoRoot 'scripts\smoke'
$smokeScripts = @(
    @{ name = 'Backlog Integrity auto-check'; file = 'smoke-backlog-integrity.ps1' }
    @{ name = 'Upstream check auto';          file = 'smoke-upstream-check.ps1' }
    @{ name = 'Dreaming auto-trigger (session-miner)'; file = 'smoke-dreaming.ps1' }
    @{ name = 'Score freshness warning';       file = 'smoke-score-freshness.ps1' }
    @{ name = 'Cycle LOOP step 3 freshness check'; file = 'smoke-cycle-loop.ps1' }
    @{ name = 'JsonFast serialization module'; file = 'smoke-jsonfast.ps1' }
    @{ name = 'Wisdom Store — parse + migration'; file = 'smoke-wisdom-store.ps1' }
    @{ name = 'Wisdom Loader — pattern retrieval'; file = 'smoke-wisdom-loader.ps1' }
    @{ name = 'Wisdom Forge — dry-run promotion'; file = 'smoke-wisdom-forge.ps1' }
    @{ name = 'Wisdom Demote — stale cleanup dry-run'; file = 'smoke-wisdom-demote.ps1' }
    @{ name = 'Wisdom Stats — metrics output'; file = 'smoke-wisdom-stats.ps1' }
)

# ── Cache check ────────────────────────────────────────────────────────
function Get-SmokeHash {
    $gitHead = & git rev-parse HEAD 2>$null
    if (-not $gitHead) { $gitHead = "no-git" }
    $content = Get-ChildItem $smokeDir -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
        "$($_.Name):$(Get-Content $_.FullName -Raw)"
    }
    $combined = "$gitHead|$($content -join '|')"
    $bytes = [Text.Encoding]::UTF8.GetBytes($combined)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return [Convert]::ToBase64String($hash)
}

$currentHash = Get-SmokeHash
$cached = $null
if (-not $Force -and (Test-Path $CachePath)) {
    try { $cached = Get-Content $CachePath -Raw | ConvertFrom-Json } catch { Write-Debug "Cache read failed: $_" }
}

if ($cached -and $cached.hash -eq $currentHash) {
    Write-Host "[cache] No changes detected — usando resultados anteriores" -ForegroundColor Cyan
    $script:passed = $cached.passed
    $script:failed = $cached.failed
    $script:smokeResults = $cached.results
    foreach ($r in $script:smokeResults) {
        $color = if ($r.passed) { 'Green' } else { 'Red' }
        $symbol = if ($r.passed) { 'PASS' } else { 'FAIL' }
        Write-Host "[$symbol] $($r.name) (cached)" -ForegroundColor $color
        if (-not $r.passed -and $r.detail) { Write-Host "  -> $($r.detail)" -ForegroundColor DarkGray }
    }
} else {
    # ── Parallel execution ────────────────────────────────────────────────
    $parallelResults = $smokeScripts | ForEach-Object -ThrottleLimit 4 {
        $path = Join-Path $using:smokeDir $_.file
        if (-not (Test-Path $path)) {
            @{ name = $_.name; passed = $false; detail = "script not found: $($_.file)" }
        } else {
            $null = & $path *>&1
            @{ name = $_.name; passed = ($LASTEXITCODE -eq 0); detail = "exit $LASTEXITCODE" }
        }
    }

    # Serialize results (parallel block can't modify script scope)
    foreach ($r in $parallelResults) {
        Add-SmokeResult -Name $r.name -Passed $r.passed -Detail $r.detail
    }

    # ── Save cache ────────────────────────────────────────────────────────
    $cache = @{
        hash      = $currentHash
        timestamp = (Get-Date -Format "o")
        passed    = $script:passed
        failed    = $script:failed
        results   = $script:smokeResults
    }
    $cache | ConvertTo-Json -Depth 2 | Set-Content $CachePath
}

# --- Summary ---
$allPassed = ($script:failed -eq 0)
$summary = @{
    smoke     = $script:smokeResults
    passed    = $script:passed
    failed    = $script:failed
    allPassed = $allPassed
}

$color = if ($allPassed) { 'Green' } else { 'Red' }
Write-Host "`n=== Smoke Results: $($script:passed) passed, $($script:failed) failed ===" -ForegroundColor $color

if ($Json) { Write-Output ($summary | ConvertTo-Json -Depth 2) }
if ($allPassed) { exit 0 } else { exit 1 }
