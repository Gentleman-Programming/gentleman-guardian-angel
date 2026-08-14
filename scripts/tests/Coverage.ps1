#requires -Version 5.1
<#
.SYNOPSIS
    Coverage-aware Pester runner for the gentleman-agent-gh repo.

.DESCRIPTION
    Runs the Pester suite with -CodeCoverage instrumentation over
    scripts/**/*.ps1 and emits a summary JSON + console report.

    Coverage is MEASURE-ONLY by default: a low baseline never breaks CI.
    Pass -Strict to promote the floor to a hard gate once a baseline exists
    (ratcheting upward, mirroring the deadcode-ratchet philosophy).

    Addresses AUDIT-gentleman-agent-gh.md Section 5.2 gap:
    "Coverage tracking (-coverprofile) -- ABSENT".
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$TestPath = './scripts/tests/*.Tests.ps1',
    [string]$CoverageRootPath = './scripts',
    [string]$ReportDir = './scripts/tests/_coverage',
    [int]$MinimumCoverage = 0,
    [switch]$Strict
)
$ErrorActionPreference = 'Stop'

# Scripts to instrument: root + lib, excluding tests and the coverage output.
$coverageFiles = Get-ChildItem -Path $CoverageRootPath -Filter '*.ps1' -Recurse -File |
    Where-Object { $_.FullName -notmatch 'tests' -and $_.FullName -notmatch '_coverage' }

$codeCoverage = @()
foreach ($f in $coverageFiles) { $codeCoverage += @{ Path = $f.FullName } }

# Ensure report dir exists
$null = New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction SilentlyContinue

Write-Output "`n=== Running Pester with code-coverage ==="
$results = Invoke-Pester -Path $TestPath -CodeCoverage $codeCoverage -PassThru -Output 'Normal'

# Test failures are a hard break (preserves existing CI behavior)
if ($results.FailedCount -gt 0) {
    Write-Error "Pester: $($results.FailedCount) test(s) failed"
    exit 1
}

# Coverage summary (measure-only unless -Strict)
$coveragePct = $null
if ($results.CodeCoverage -and $null -ne $results.CodeCoverage.CoveragePercent) {
    $coveragePct = [math]::Round($results.CodeCoverage.CoveragePercent, 2)
}

$summary = [ordered]@{
    timestamp    = (Get-Date).ToString('o')
    tests_passed = $results.PassedCount
    tests_failed = $results.FailedCount
    tests_total  = $results.TotalCount
    coverage_pct = $coveragePct
    threshold    = $MinimumCoverage
    strict       = [bool]$Strict
}
$summary | ConvertTo-Json -Compress |
    Set-Content -Path "$ReportDir/summary.json" -Encoding UTF8

if ($null -ne $coveragePct) {
    if ($coveragePct -lt $MinimumCoverage) {
        $msg = "COVERAGE: $($coveragePct)% is below the $MinimumCoverage% floor"
        if ($Strict) { Write-Error $msg; exit 1 }
        Write-Warning "$msg -- measure-only (pass -Strict to enforce)"
    }
    Write-Output "OK: $($results.PassedCount)/$($results.TotalCount) tests passed -- coverage $($coveragePct)%"
} else {
    Write-Output "OK: $($results.PassedCount)/$($results.TotalCount) tests passed -- coverage N/A (no instrumented files hit)"
}

exit 0
