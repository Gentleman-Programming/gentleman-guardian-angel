#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Universal Pester test runner — auto-detects Pester version,
  runs test files from scripts/tests/ with parallel support.

.PARAMETER Quiet    Suppress verbose output
.PARAMETER PassThru Return Pester run results object (default: exit code only)
.PARAMETER Path     One or more test file paths (default: scripts/tests/*.Tests.ps1)
.PARAMETER NoParallel  Disable parallel file execution (Pester 6 only)
.PARAMETER CodeCoverage Collect code coverage metrics (Pester 5/6 only; < 50% -> exit 10)
.PARAMETER IncludeE2E Also run -Tag E2E tests (slow integration/coverage runs); excluded by default
.EXAMPLE
  .\scripts\run-tests.ps1                      # run all, exit 0/1
  .\scripts\run-tests.ps1 -PassThru            # get results object
  .\scripts\run-tests.ps1 -Path .\tests\foo.Tests.ps1  # single file
#>
param(
    [switch]$Quiet,
    [switch]$PassThru,
    [string[]]$Path,
    [switch]$NoParallel,
    [switch]$CodeCoverage,
    [switch]$IncludeE2E
)

Set-StrictMode -Version Latest

# --- discover test files ---
if (-not $Path) {
    $testDir = Join-Path $PSScriptRoot 'tests'
    if (-not (Test-Path $testDir)) {
        Write-Error "Test directory not found: $testDir"
        exit 2
    }
    $Path = @(Get-ChildItem -Path $testDir -Filter '*.Tests.ps1' -Recurse | Select-Object -ExpandProperty FullName)
    if ($Path.Count -eq 0) {
        Write-Warning "No test files found in $testDir"
        if (-not $PassThru) { exit 0 }
        return @{ TotalCount = 0; PassedCount = 0; FailedCount = 0 }
    }
}

if (-not $Quiet) {
    Write-Host "Found $($Path.Count) test file(s):" -ForegroundColor Cyan
    $Path | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
}

# --- detect Pester (fast path: filter by name to avoid listing all modules) ---
$pester = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    Write-Error "Pester module not found. Install: Install-Module Pester -Force -Scope CurrentUser"
    exit 3
}

if (-not $Quiet) {
    Write-Host "Pester v$($pester.Version) detected" -ForegroundColor Cyan
}

# --- run ---
$useParallel = (-not $NoParallel) -and ($Path.Count -gt 1) -and ($pester.Version.Major -ge 5)

if ($pester.Version.Major -ge 5) {
    # Pester 5/6 style
    Import-Module Pester -MinimumVersion 5.0.0 -Force -PassThru | Out-Null

    $cfg = [PesterConfiguration]@{
        Run    = @{
            Path     = $Path
            Exit     = $false
            PassThru = $true
        }
        Output = @{
            Verbosity = if ($Quiet) { 'None' } else { 'Normal' }
        }
    }

    if ($useParallel) {
        $cfg.Run.Parallel = $true
        if (-not $Quiet) {
            Write-Host "Parallel mode: $($Path.Count) files" -ForegroundColor Yellow
        }
    }

    if ($CodeCoverage) {
        $coverageFiles = Get-ChildItem -Path "$PSScriptRoot/*.ps1" -Recurse | Select-Object -ExpandProperty FullName
        if ($coverageFiles) {
            $cfg.CodeCoverage = @{
                Enabled = $true
                Path    = $coverageFiles
            }
        } elseif (-not $Quiet) {
            Write-Warning "No .ps1 files found for code coverage in $PSScriptRoot"
        }
    }

    if (-not $IncludeE2E) {
        if ($cfg.PSObject.Properties['Filter']) {
            $cfg.Filter.ExcludeTag = 'E2E'
            if (-not $Quiet) {
                Write-Host "Excluding -Tag 'E2E' tests (use -IncludeE2E to run them)" -ForegroundColor Yellow
            }
        }
    }

    $result = Invoke-Pester -Configuration $cfg
} else {
    # Pester 3/4 fallback
    if ($CodeCoverage -and -not $Quiet) {
        Write-Warning "-CodeCoverage requires Pester 5+; skipping coverage"
    }
    $result = $Path | ForEach-Object {
        Invoke-Pester -Script $_ -PassThru
    } | Select-Object -Last 1
}

# --- output ---
$total   = $result.TotalCount
$passed  = $result.PassedCount
$failed  = $result.FailedCount
$skipped = $result.SkippedCount

if (-not $Quiet) {
    Write-Host "`n=== Results ===" -ForegroundColor Cyan
    Write-Host "Total: $total | Passed: $passed | Failed: $failed | Skipped: $skipped" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
}

# --- code coverage ---
if ($CodeCoverage -and $result.CodeCoverage) {
    $cc = $result.CodeCoverage
    $totalCmds  = $cc.CommandsAnalyzedCount
    $executed   = $cc.CommandsExecutedCount
    $pct        = if ($totalCmds -gt 0) { [math]::Round(($executed / $totalCmds) * 100, 1) } else { 100.0 }
    $threshold  = 50

    if (-not $Quiet) {
        Write-Host "`n=== Code Coverage ===" -ForegroundColor Cyan
        Write-Host "Commands: $totalCmds | Executed: $executed | Coverage: $pct%" -ForegroundColor $(if ($pct -ge $threshold) { 'Green' } else { 'Red' })
    }

    if ($pct -lt $threshold) {
        if (-not $Quiet) { Write-Host "Coverage below $threshold% threshold — failing" -ForegroundColor Red }
        if ($PassThru) { return $result }
        exit 10
    }
}

if ($PassThru) { return $result }
exit $(if ($failed -gt 0) { 1 } else { 0 })
