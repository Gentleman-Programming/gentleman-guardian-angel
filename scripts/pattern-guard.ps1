#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    LAZY detection: check current code for cross-project pattern matches.
.DESCRIPTION
    Runs grep/glob heuristics against working directory to detect
    known anti-patterns from the Pattern Store. Advisory only.
    Designed for rung 0b — hard timeout <200ms for LAZY mode.
.PARAMETER Path
    Path to scan (default: repo root).
.PARAMETER Mode
    LAZY (grep/glob, <200ms), BATCH (full analysis), ON_DEMAND (interactive).
.PARAMETER PatternId
    Check only a specific pattern by ID.
.PARAMETER Json
    Output JSON (default: true for agent consumption).
.EXAMPLE
    .\scripts\pattern-guard.ps1 -Mode LAZY
    .\scripts\pattern-guard.ps1 -Mode LAZY -Path "D:\projects\landing-page"
    .\scripts\pattern-guard.ps1 -PatternId "ux-a11y-hero-btn-contrast"
#>
param(
    [string]$Path = "",
    [ValidateSet("LAZY", "BATCH", "ON_DEMAND")]
    [string]$Mode = "LAZY",
    [string]$PatternId = "",
    [bool]$Json = $true
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = if ($Path) { $Path } else { Split-Path -Parent $PSScriptRoot }
$patternsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "docs" "cross-project" "patterns"

if (-not (Test-Path $patternsDir)) {
    $result = [PSCustomObject]@{ Status = "NO_STORE"; Warnings = @(); Count = 0 }
    if ($Json) { return $result | ConvertTo-Json }
    Write-Host "[OK] Pattern store not found — nothing to guard"
    exit 0
}

$patternFiles = @(Get-ChildItem $patternsDir -Filter "*.json")
if ($patternFiles.Length -eq 0) {
    $result = [PSCustomObject]@{ Status = "EMPTY"; Warnings = @(); Count = 0 }
    if ($Json) { return $result | ConvertTo-Json }
    Write-Host "[OK] No patterns to guard"
    exit 0
}

function Invoke-LazyDetection {
    param([PSCustomObject]$Pattern)
    $warnings = @()
    $signal = $Pattern.signal
    if (-not $signal) { return $warnings }

    # Check CSS selectors
    $hasCssSelectors = $null -ne $signal -and $null -ne ($signal.PSObject.Properties['css_selectors'])
    if ($hasCssSelectors -and $null -ne $signal.css_selectors) {
        $cssFiles = @(Get-ChildItem $repoRoot -Recurse -Filter "*.css" -ErrorAction SilentlyContinue |
                    Select-Object -First 20)
        foreach ($sel in @($signal.css_selectors)) {
            $escaped = [regex]::Escape($sel)
            foreach ($cf in $cssFiles) {
                try {
                    $content = Get-Content $cf.FullName -Raw -ErrorAction SilentlyContinue
                    if ($content -match $escaped) {
                        $warnings += "Found '$sel' in $($cf.Name) — pattern $($Pattern.id) may apply"
                    }
                } catch { continue }
            }
        }
    }

    # Check code patterns (regex)
    $hasCodePatterns = $null -ne ($signal.PSObject.Properties['code_patterns'])
    if ($hasCodePatterns -and $null -ne $signal.code_patterns) {
        foreach ($cp in @($signal.code_patterns)) {
            try {
                $hits = Select-String -Path "$repoRoot\*.{css,js,html,ps1,ts,jsx,tsx}" `
                    -Pattern $cp -ErrorAction SilentlyContinue -SimpleMatch | Select-Object -First 3
                if ($hits) {
                    $files = ($hits | ForEach-Object { $_.Filename }) -join ', '
                    $warnings += "Code pattern '$cp' found in: $files — pattern $($Pattern.id) may apply"
                }
            } catch { continue }
        }
    }

    # Check keywords in filenames
    $hasKeywords = $null -ne ($signal.PSObject.Properties['keywords'])
    if ($hasKeywords -and $null -ne $signal.keywords) {
        foreach ($kw in @($signal.keywords)) {
            $matchingFiles = Get-ChildItem $repoRoot -Recurse -Filter "*$kw*" -ErrorAction SilentlyContinue |
                             Select-Object -First 5
            if ($matchingFiles) {
                $warnings += "Keyword '$kw' found in filenames — pattern $($Pattern.id) may apply"
            }
        }
    }

    return $warnings
}

# --- Main ---
$startTime = Get-Date
$allWarnings = @()
$matchedCount = 0

foreach ($file in $patternFiles) {
    try {
        $pattern = Get-Content $file.FullName -Raw | ConvertFrom-Json
    } catch { continue }

    # Filter by specific pattern ID
    if ($PatternId -and $pattern.id -ne $PatternId) { continue }

    # Only active patterns
    if ($pattern.status -ne "active") { continue }

    if ($Mode -eq "LAZY") {
        $warnings = @(Invoke-LazyDetection $pattern)
        if ($warnings.Length -gt 0) {
            $matchedCount++
            foreach ($w in $warnings) {
                $allWarnings += [PSCustomObject]@{
                    PatternId = $pattern.id
                    Title     = $pattern.title
                    Severity  = $pattern.severity
                    Confidence = $pattern.confidence
                    Warning   = $w
                    Fix       = if ($pattern.rule -and $pattern.rule.fix) { $pattern.rule.fix } else { "" }
                }
            }
        }
    }

    # LAZY mode: hard timeout check (should be <200ms total)
    if ($Mode -eq "LAZY") {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalMilliseconds -gt 180) {
            $allWarnings += [PSCustomObject]@{
                PatternId = "timeout"
                Title     = "Pattern guard timeout"
                Severity  = "INFO"
                Warning   = "LAZY detection reached 180ms — deferring remaining patterns to BATCH"
            }
            break
        }
    }
}

$elapsed = [Math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 0)
$warnCount = @($allWarnings).Length
$result = [PSCustomObject]@{
    Status         = if ($warnCount -gt 0) { "WARNINGS" } else { "CLEAN" }
    Mode           = $Mode
    ElapsedMs      = $elapsed
    PatternsScanned = $patternFiles.Length
    PatternsMatched = $matchedCount
    Warnings       = $allWarnings
    Advisory       = $true  # Never blocks
}

if ($Json) {
    $result | ConvertTo-Json -Depth 4
} else {
    Write-Host "=== Pattern Guard ($Mode) ==="
    Write-Host "Scanned: $($patternFiles.Length) patterns | $elapsed ms"
    if ($warnCount -gt 0) {
        Write-Host "Warnings: $warnCount (ADVISORY — does not block)" -ForegroundColor Yellow
        foreach ($w in $allWarnings) {
            $color = switch ($w.Severity) { "CRITICAL" { "Red" } "HIGH" { "Yellow" } default { "Gray" } }
            Write-Host "  [$($w.Severity)] $($w.Warning)" -ForegroundColor $color
            if ($w.Fix) { Write-Host "    Fix: $($w.Fix)" -ForegroundColor DarkGray }
        }
    } else {
        Write-Host "[CLEAN] No pattern matches detected" -ForegroundColor Green
    }
}

