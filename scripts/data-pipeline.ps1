#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Data pipeline orchestrator — connects scoring, metrics, and learning systems.
.DESCRIPTION
    Chains the data pipeline stages:
    1. Score computation (score-auto.ps1)
    2. Error capture (capture-errors.ps1)
    3. Metrics snapshot (snapshot to docs/metricas/)
    4. Learning extraction (Engram mem_save)

    Modes:
      - score    : compute score only
      - errors   : capture errors only
      - full     : all stages (default)
      - report   : generate summary report
.PARAMETER Mode
    Pipeline mode: score, errors, full, report
.PARAMETER Json
    Output results as JSON
.EXAMPLE
    .\scripts\data-pipeline.ps1
    .\scripts\data-pipeline.ps1 -Mode score -Json
#>

param(
    [switch]$Quiet,
    [ValidateSet('score', 'errors', 'full', 'report')]
    [string]$Mode = 'full',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")
$repoRoot = Get-GentlemanRoot

Push-Location $repoRoot

$results = @{
    timestamp = (Get-Date -Format "o")
    mode      = $Mode
    stages    = [ordered]@{}
}

# ============================================================
# Stage 1: Score Computation
# ============================================================

if ($Mode -in @('score', 'full')) {
    try {
        $scoreResult = & "$repoRoot\scripts\score-auto.ps1" -Json -Quiet 2>&1
        $scoreData = $null
        try { $scoreData = $scoreResult | ConvertFrom-Json } catch { Write-Debug "data-pipeline: $($_.Exception.Message)" }
        if ($scoreData -and $scoreData.score) {
            $results.stages.score = @{
                status = 'ok'
                score  = $scoreData.score.current
                trend  = $scoreData.score.trend
            }
        } else {
            $results.stages.score = @{
                status = 'error'
                error  = 'score-auto.ps1 returned invalid JSON'
            }
        }
    } catch {
        $results.stages.score = @{
            status = 'error'
            error  = $_.Exception.Message
        }
    }
}

# ============================================================
# Stage 2: Error Capture
# ============================================================

if ($Mode -in @('errors', 'full')) {
    try {
        # Capture current error state
        & "$repoRoot\scripts\capture-errors.ps1" -Snapshot -Quiet 2>&1 | Out-Null
        $results.stages.errors = @{
            status = 'ok'
            action = 'snapshot captured'
        }
    } catch {
        $results.stages.errors = @{
            status = 'error'
            error  = $_.Exception.Message
        }
    }
}

# ============================================================
# Stage 3: Metrics Snapshot
# ============================================================

if ($Mode -eq 'full') {
    try {
        $metricsDir = Join-Path $repoRoot "docs\metricas"
        if (-not (Test-Path $metricsDir)) {
            New-Item -ItemType Directory -Path $metricsDir -Force | Out-Null
        }

        # Copy LATEST_error.json to timestamped snapshot (with uniqueness)
        $latestError = Join-Path $metricsDir "errors\LATEST_error.json"
        if (Test-Path $latestError) {
            $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
            $snapshot = Join-Path $metricsDir "errors\${timestamp}_error.json"
            Copy-Item $latestError $snapshot -Force
        }

        $results.stages.metrics = @{
            status = 'ok'
            action = 'snapshot saved'
        }
    } catch {
        $results.stages.metrics = @{
            status = 'error'
            error  = $_.Exception.Message
        }
    }
}

# ============================================================
# Stage 4: Learning Extraction
# ============================================================

if ($Mode -eq 'full') {
    try {
# Check for new anti-patterns (match ### Anti-Pattern: specifically)
$antiPatternFile = Join-Path $repoRoot "ANTI-PATTERN-CATALOG.md"
$content = Get-Content $antiPatternFile -Raw -ErrorAction SilentlyContinue
$patternCount = ([regex]::Matches($content, '(?m)^###\s+Anti-Pattern:', 'Multiline')).Count

        $results.stages.learning = @{
            status        = 'ok'
            anti_patterns = $patternCount
        }
    } catch {
        $results.stages.learning = @{
            status = 'error'
            error  = $_.Exception.Message
        }
    }
}

Pop-Location

# ============================================================
# Output
# ============================================================

if ($Json) {
    $results | ConvertTo-Json -Depth 5
} elseif (-not $Quiet) {
    Write-Host "Data Pipeline — $($results.mode)" -ForegroundColor Cyan
    Write-Host "=" * 40

    foreach ($stage in $results.stages.PSObject.Properties) {
        $status = if ($stage.Value.status -eq 'ok') { "✓" } else { "✗" }
        $color = if ($stage.Value.status -eq 'ok') { "Green" } else { "Red" }
        Write-Host " $status $($stage.Name)" -ForegroundColor $color
        if ($stage.Value.error) {
            Write-Host "   Error: $($stage.Value.error)" -ForegroundColor Yellow
        }
    }
}
