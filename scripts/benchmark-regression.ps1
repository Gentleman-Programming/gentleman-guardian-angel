#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Statistical performance regression detection — benchmark with median + IQR,
    following protocolo_mejora_autonoma_v3.md §0.7 (5-10 runs, not single-value).

.DESCRIPTION
    Runs a baseline benchmark N times (default 10), computes median + IQR,
    and compares against a saved baseline JSON. If the new median exceeds the
    baseline median + 1.5×IQR (statistical regression), exits non-zero.

    This is the CI performance regression gate for Debilidad 3 Enfoque C.

.PARAMETER Command
    The benchmark command to run (e.g. "scripts/sync-vmk.ps1 -DryRun -Json").

.PARAMETER Runs
    Number of samples to collect (default: 10, minimum: 5 per protocol §0.7).

.PARAMETER Baseline
    Path to baseline JSON file (default: docs/mejoras/benchmark-baseline.json).
    If not present, generates a fresh baseline.

.PARAMETER Threshold
    Regression threshold as % above baseline median (default: 15 = 15% slower).

.PARAMETER Json
    Output machine-readable JSON.

.PARAMETER UpdateBaseline
    Write a new baseline from the current run.

.EXAMPLE
    .\scripts\benchmark-regression.ps1 -Command "sync-vmk.ps1 -DryRun" -Runs 10
    # → Runs 10x, compares median/IQR vs benchmark-baseline.json

    .\scripts\benchmark-regression.ps1 -Command "sync-vmk.ps1 -DryRun" -UpdateBaseline
    # → Generates fresh baseline with median + IQR

    .\scripts\benchmark-regression.ps1 -Command "sync-vmk.ps1 -DryRun" -Json
    # → {"median_ms": 763.2, "baseline_median_ms": 763.0, "regression": false, ...}
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Command,
    [ValidateRange(5, 50)]
    [int]$Runs = 10,
    [string]$Baseline = "",
    [double]$Threshold = 15.0,
    [switch]$Json,
    [switch]$UpdateBaseline
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent

# --- Resolve baseline path ---
if (-not $Baseline) {
    $Baseline = Join-Path $repoRoot "docs/mejoras/benchmark-baseline.json"
}

# --- Parse command: script path + args ---
$parts = $Command -split '\s+'
$scriptName = $parts[0]
$scriptArgs = if ($parts.Count -gt 1) { $parts[1..($parts.Count-1)] } else { @() }

# --- Resolve script path ---
if (-not $scriptName.StartsWith('-') -and (Test-Path (Join-Path $repoRoot "scripts/$scriptName"))) {
    $scriptPath = Join-Path $repoRoot "scripts/$scriptName"
} elseif (Test-Path $scriptName) {
    $scriptPath = $scriptName
} else {
    Write-Error "Script not found: $scriptName"
    exit 1
}

# --- Check for existing baseline ---
$baselineData = $null
if (Test-Path $Baseline) {
    try {
        $baselineData = Get-Content $Baseline -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    } catch { Write-Warning "Baseline JSON parse error: $_" }
}

# --- Run benchmark N times ---
$samples = @()
if (-not $Json -and -not $Quiet) {
    Write-Host "🏃 Running benchmark: $scriptName ($Runs samples)" -ForegroundColor Cyan
}

for ($i = 0; $i -lt $Runs; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $scriptPath @scriptArgs > $null 2>&1
    $sw.Stop()
    $elapsedMs = $sw.Elapsed.TotalMilliseconds
    $samples += $elapsedMs
    if (-not $Json) {
        Write-Progress -Activity "Benchmarking" -Status "Run $($i+1)/$Runs" -PercentComplete (($i+1)/$Runs*100)
    }
}

# --- Sort samples ---
$samples = $samples | Sort-Object

# --- Calculate median ---
$count = $samples.Count
$median = if ($count % 2 -eq 0) {
    ($samples[$count/2 - 1] + $samples[$count/2]) / 2
} else {
    $samples[[math]::Floor($count/2)]
}

# --- Calculate Q1, Q3, IQR ---
$q1 = $samples[[math]::Floor($count * 0.25)]
$q3 = $samples[[math]::Floor($count * 0.75)]
$iqr = $q3 - $q1
$mean = ($samples | Measure-Object -Average).Average
$stdev = if ($count -gt 1) {
    $variance = ($samples | ForEach-Object { [math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum / ($count - 1)
    [math]::Sqrt($variance)
} else { 0 }

# --- Compare against baseline ---
$regressionDetected = $false
$regressionPercent = 0
if ($baselineData -and $baselineData.median_ms) {
    $baselineMedian = $baselineData.median_ms
    $improvement = $median - $baselineMedian
    $regressionPercent = if ($baselineMedian -gt 0) { ($improvement / $baselineMedian) * 100 } else { 0 }
    # Regression: new median is Threshold% slower than baseline median
    $regressionDetected = $regressionPercent -gt $Threshold
}

# --- Update baseline if requested ---
if ($UpdateBaseline) {
    $baselineObj = [PSCustomObject]@{
        command         = $Command
        runs            = $Runs
        median_ms       = [math]::Round($median, 2)
        mean_ms         = [math]::Round($mean, 2)
        stdev_ms        = [math]::Round($stdev, 2)
        q1_ms           = [math]::Round($q1, 2)
        q3_ms           = [math]::Round($q3, 2)
        iqr_ms          = [math]::Round($iqr, 2)
        min_ms          = [math]::Round($samples[0], 2)
        max_ms          = [math]::Round($samples[-1], 2)
        timestamp       = (Get-Date).ToUniversalTime().ToString("o")
    }
    if (-not (Test-Path (Split-Path $Baseline -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $Baseline -Parent) -Force | Out-Null
    }
    $baselineObj | ConvertTo-Json | Set-Content -Path $Baseline -Encoding UTF8
    if (-not $Json) { Write-Host "✅ Baseline updated: $Baseline" -ForegroundColor Green }
}

# --- Output ---
$result = [PSCustomObject]@{
    command            = $Command
    runs               = $Runs
    median_ms          = [math]::Round($median, 2)
    mean_ms            = [math]::Round($mean, 2)
    stdev_ms           = [math]::Round($stdev, 2)
    q1_ms              = [math]::Round($q1, 2)
    q3_ms              = [math]::Round($q3, 2)
    iqr_ms             = [math]::Round($iqr, 2)
    baseline_median_ms = if ($baselineData) { $baselineData.median_ms } else { $null }
    regression_percent = [math]::Round($regressionPercent, 2)
    regression         = $regressionDetected
    threshold_percent  = $Threshold
    status             = if ($regressionDetected) { "REGRESSION" } elseif ($baselineData) { "OK" } else { "BASELINE_CREATED" }
}

if ($Json) {
    $result | ConvertTo-Json -Compress -Depth 3
} else {
    Write-Host "=== Benchmark Result ===" -ForegroundColor Cyan
    Write-Host "  Median: $($result.median_ms)ms (±IQR: $($result.iqr_ms)ms)" -ForegroundColor White
    Write-Host "  Mean:   $($result.mean_ms)ms (σ: $($result.stdev_ms)ms)" -ForegroundColor Gray
    Write-Host "  Q1-Q3:  $($result.q1_ms) — $($result.q3_ms)ms" -ForegroundColor Gray
    if ($baselineData) {
        Write-Host "  Baseline median: $($result.baseline_median_ms)ms" -ForegroundColor Gray
        if ($regressionDetected) {
            Write-Host "  ⚠️  REGRESSION DETECTED: $($result.regression_percent)% slower (threshold: $Threshold%)" -ForegroundColor Red
        } else {
            Write-Host "  ✅ No regression: $($result.regression_percent)% vs baseline" -ForegroundColor Green
        }
    } else {
        Write-Host "  ℹ️  No baseline — run with -UpdateBaseline to create one" -ForegroundColor Yellow
    }
}

exit $(if ($regressionDetected) { 1 } else { 0 })
