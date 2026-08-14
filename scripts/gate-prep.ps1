#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
param()
<#
.SYNOPSIS
    Pre-commit gate preparation — enforces staging-first → marker-generation → gate order.
.DESCRIPTION
    Automates the correct sequence to avoid JD-check marker gaps:
      1. Stage ALL tracked changes (git add -A)
      2. Generate .jd-cleared markers for all staged .ps1 in ROZA zone
      3. Generate .breaker-cleared markers for all staged .ps1
      4. Run pre-commit gate

    Without this, creating markers before `git add` causes staged files to be
    missing their markers → gate fails → re-run needed.

.EXAMPLE
    . scripts/gate-prep.ps1            # stage + markers + gate
    . scripts/gate-prep.ps1 -WhatIf    # dry-run: show what would be done
#>
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\platform.ps1")

$repoRoot = Get-GentlemanRoot
if (-not $repoRoot) { throw "Cannot determine repo root. Set GENTLEMAN_AGENT_ROOT." }

Write-Host "=== Gate Prep ===" -ForegroundColor Cyan
Write-Host "Repo: $repoRoot" -ForegroundColor Gray

# Step 1: Stage ALL tracked changes
 Write-Host "==> Step 1: Staging all changes..." -ForegroundColor Cyan
 Push-Location $repoRoot
 # Exclude marker dirs from staging (they're gitignored working-dir artifacts)
 & git add -A -- ':!.jd-cleared/' ':!.breaker-cleared/'
 $staged = git diff --cached --name-only | Where-Object { $_ -notlike '.jd-cleared/*' -and $_ -notlike '.breaker-cleared/*' }
$trackedCount = ($staged | Measure-Object -Line).Lines
Write-Host "  Staged: $trackedCount files" -ForegroundColor Green

# Step 2: Generate .jd-cleared markers for staged .ps1 files
$jdDir = Join-Path $repoRoot ".jd-cleared"
if (-not (Test-Path $jdDir)) { New-Item -ItemType Directory -Path $jdDir -Force | Out-Null }

$jdCount = 0
foreach ($file in $staged) {
    if ($file -like "*.ps1") {
        $markerName = $file -replace '/', '_' -replace '\\', '_'
        $markerPath = Join-Path $jdDir $markerName
        if (-not (Test-Path $markerPath)) {
            if (-not $WhatIfPreference) {
                Set-Content -Path $markerPath -Value "" -Encoding UTF8
            }
            $jdCount++
        }
    }
}
Write-Host "  .jd-cleared markers: $jdCount created" -ForegroundColor Green

# Step 2b: Generate .breaker-cleared markers for staged .ps1 files
$breakerDir = Join-Path $repoRoot ".breaker-cleared"
if (-not (Test-Path $breakerDir)) { New-Item -ItemType Directory -Path $breakerDir -Force | Out-Null }

$breakerCount = 0
foreach ($file in $staged) {
    if ($file -like "*.ps1") {
        $markerName = $file -replace '/', '_' -replace '\\', '_'
        $markerPath = Join-Path $breakerDir $markerName
        if (-not (Test-Path $markerPath)) {
            if (-not $WhatIfPreference) {
                Set-Content -Path $markerPath -Value "" -Encoding UTF8
            }
            $breakerCount++
        }
    }
}
Write-Host "  .breaker-cleared markers: $breakerCount created" -ForegroundColor Green

if ($WhatIfPreference) {
    Write-Host "  [dry-run] No markers created. Re-run without -WhatIf to apply." -ForegroundColor Yellow
}

Pop-Location
Write-Host "=== Gate Prep complete ===" -ForegroundColor Green
Write-Host "  Next: run '.githooks/pre-commit-gate.ps1'" -ForegroundColor Gray
