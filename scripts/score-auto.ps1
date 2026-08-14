#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

<#
.SYNOPSIS
    Auto-score project metrics across 13 dimensions.
.DESCRIPTION
    Evaluates project health across 13 dimensions (PA, Sec, DC, CC, BP, Or, Bi, Me, SP, SE, CA, BI2, SD)
    with 38+ sub-dimensions. Caches results based on script + skill content hashes (git HEAD independent).
    Spawns parallel jobs for cross-ref-check, pssa-gate, and check-backlog-integrity.
.PARAMETER Json
    Output results as JSON (depth 5).
.PARAMETER Quiet
    Output minimal score summary (one line).
.NOTES
    Scores range 0-10 per dimension. Composite score averages all dimensions.
    Cache invalidated when script or skill content hashes change.
    Sub-dimensions in SD provide granular breakdown.
    Bias calibration warning shown in non-Json mode when calibration data exists (>=2 samples).
#>
param(
    [switch]$Json,
    [switch]$Quiet
)

Set-StrictMode -Version Latest

# ponytail: score cache — content-hash based composite key (no git HEAD), fast invalidation

# ============================================================
# 1. CACHE CHECK
# ============================================================

# Resolve repoRoot FIRST — needed by cache path and everything else
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")
$repoRoot = Get-GentlemanRoot

$cacheDir  = Join-Path $repoRoot ".learnings"
$cacheFile = Join-Path $cacheDir "score-cache.json"

# ponytail: init before try — ensures vars exist even if cache check throws
$scriptFiles  = @()
$skillMdFiles = @()
$skillDirs    = @()
$manifest     = @()

. "$repoRoot\scripts\lib\file-manifest.ps1"

try {
    $manifest = @(Get-FileManifest -Path $repoRoot)

    # ponytail: consolidated reads — single pass for cache hash + scoring
    $scriptFiles  = @(Get-ChildItem "$repoRoot\scripts\*.ps1" -EA SilentlyContinue)
    $skillMdFiles = @(Get-ChildItem "$repoRoot\.agents\skills\*\SKILL.md" -EA SilentlyContinue)
    $skillDirs    = @(Get-ChildItem -Directory "$repoRoot\.agents\skills" -EA SilentlyContinue | Select-Object -ExpandProperty Name)

    $scriptsHash = ($manifest | Where-Object { $_.group -eq 'script' } | ForEach-Object { "$($_.relpath):$($_.sha256)" } | Sort-Object) -join "|"
    $skillsHash  = ($manifest | Where-Object { $_.group -eq 'skill' }  | ForEach-Object { "$($_.relpath):$($_.sha256)" } | Sort-Object) -join "|"

    $manifestScriptCount = @($manifest | Where-Object { $_.group -eq 'script' }).Count
    $manifestSkillCount  = @($manifest | Where-Object { $_.group -eq 'skill' }).Count
    if ($manifestScriptCount -lt $scriptFiles.Count -or $manifestSkillCount -ne $skillMdFiles.Count) { $cacheHash = $null }

    $compositeKey = "$scriptsHash|$skillsHash"
    $cacheHash    = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($compositeKey))

    if (Test-Path $cacheFile) {
        $cached = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cached.hash -eq $cacheHash) {
            if ($Json) {
                $cached.result | ConvertTo-Json -Depth 5
            } elseif ($Quiet) {
                $cached.result | ConvertTo-Json -Depth 5
            } else {
                Write-Host "Score: $($cached.result.score.current)/10 (cached at $($cached.timestamp))" -ForegroundColor DarkGray
            }
            exit 0
        }
    }
} catch {
    Write-Debug "score-cache: $($_.Exception.Message)"
}

# ============================================================
# SETUP: Push-Location preserves caller CWD (AGENTS.md forbids Set-Location)
# ============================================================

Push-Location $repoRoot
# C4c: Single path definition — CWD-independent .project.json reference
$projectJsonPath = Join-Path $repoRoot ".project.json"

$math       = [math]
$dimensions = @{}

function Add-Dimension([string]$name, [double]$score, [hashtable]$evidence, [string]$rationale) {
    $dimensions[$name] = @{ s = $score; e = $evidence; r = $rationale }
}

# ============================================================
# BATCH FILE READS — reuse from cache section (consolidated)
# ============================================================

$skillDirCount = $skillDirs.PSWhere({ $_ -ne '_shared' }).Count

# ============================================================
# 2. PARALLEL SUB-SCRIPTS
# ============================================================

# Use repoRoot for script paths (more reliable than PSScriptRoot in pwsh -Command)
$scriptLibRoot = Join-Path $repoRoot "scripts"
$jobs          = @()

$jobs += Start-ThreadJob -Name "crossref" -ScriptBlock { & "$using:scriptLibRoot\cross-ref-check.ps1" -Json -Quiet }
if ($env:PESTER_TEST -eq '1') {
  # Test mode: skip the ~33s PSSA cold scan (pssa-gate.ps1 -Mode Check).
  # Keeps integration tests fast; normal invocations still run the gate.
  Write-Warning "PESTER_TEST=1 — skipping pssa-gate job (test mode)"
} else {
  $jobs += Start-ThreadJob -Name "pssa" -ScriptBlock { & "$using:scriptLibRoot\pssa-gate.ps1" -Mode Check -Quiet }
}
$jobs += Start-ThreadJob -Name "backlog"  -ScriptBlock { & "$using:scriptLibRoot\check-backlog-integrity.ps1" -Json }

$jobs | Wait-Job -Timeout 30 | Out-Null

# Receive each job by name — handle failures gracefully with defaults
$crossRefOutput = Receive-Job -Name "crossref" -ErrorAction SilentlyContinue
$pssaOutput     = Receive-Job -Name "pssa" -ErrorAction SilentlyContinue | Out-String
$backlogRaw     = Receive-Job -Name "backlog" -ErrorAction SilentlyContinue

$jobs | Remove-Job -Force 2>$null

# Parse parallel results with safe defaults on failure
$crossRefClean = try { ($crossRefOutput | ConvertFrom-Json -EA SilentlyContinue).allClean -eq $true } catch { $false }
$backlogData   = try { $backlogRaw | ConvertFrom-Json -EA SilentlyContinue } catch { $null }

$hasReadme      = Test-Path "README.md"
$hasProjectJson = Test-Path $projectJsonPath  # C4c: use single path definition

# ============================================================
# 3. DIMENSION SCORING
# ============================================================

. "$repoRoot\scripts\lib\score-dims.ps1"

# Bias calibration data (persist to .project.json, not just display)
$biasCalPath = ".learnings/bias-calibration.json"
$biasAdjusted = $null
$biasNote = $null
if (Test-Path $biasCalPath) {
    try {
        $biasCalData = Get-Content $biasCalPath -Raw | ConvertFrom-Json
        if ($biasCalData.samples -ge 2) {
            $biasAdjusted = $math::Round($finalScore - $biasCalData.avg_offset, 1)
            $biasNote = "Self-assessment inflation ~$($biasCalData.avg_offset)pt avg across $($biasCalData.samples) samples (bias-calibration.json). Real score estimated at $biasAdjusted/10."
            if (-not $Json -and -not $Quiet) {
                Write-Host "⚠️ Active bias offsets (auto-metrics):" -ForegroundColor DarkYellow
                $biasCalData.offsets.PSObject.Properties | Sort-Object Name | ForEach-Object {
                    Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor DarkYellow
                }
            }
        }
    } catch {
        Write-Debug "bias-cal read: $($_.Exception.Message)"
    }
}

# ============================================================
# 4. SCORE COMPOSITION
# ============================================================

$allScores   = $dimensions.Values.PSForEach({ $_.s })
$finalScore  = $math::Round(($allScores | Measure-Object -Average).Average, 1)

$dimNames = @{
    "PA"  = "Project Artifacts"
    "Sec" = "Security"
    "DC"  = "Dead Code"
    "CC"  = "Clean Code"
    "BP"  = "Best Practices"
    "Or"  = "Orthography"
    "Bi"  = "Bitacora"
    "Me"  = "Metrics"
    "SP"  = "Script Performance"
    "SE"  = "Skill Effectiveness"
    "CA"  = "Cycle Activity"
    "BI2" = "Backlog Integrity"
    "SD"  = "Score Depth"
}

$result = @{
    score = @{
        current      = $finalScore
        dimensions   = [ordered]@{}
        last_updated = (Get-Date -Format "yyyy-MM-dd")
        trend        = "stable"
    }
    dimensions_detail = $dimensions
}

# Persist bias calibration data if available
if ($null -ne $biasAdjusted) {
    $result.score.bias_adjusted = $biasAdjusted
    $result.score.bias_note = $biasNote
}

foreach ($key in $dimNames.Keys) {
    $result.score.dimensions[$dimNames[$key]] = $dimensions[$key].s
}

# Compare with existing .project.json for trend
if (Test-Path $projectJsonPath) {
    try {
        $prevProjectData = Get-Content $projectJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $prevScore = $prevProjectData.score.current

        if ($finalScore -gt $prevScore) {
            $result.score.trend = "up"
        } elseif ($finalScore -lt $prevScore) {
            $result.score.trend = "down"
        }

        $lastUpdated = $prevProjectData.score.last_updated
        if ($lastUpdated -and -not $Json -and -not $Quiet) {
            $daysSinceUpdate = [int]((Get-Date) - (Get-Date $lastUpdated)).TotalDays
            if ($daysSinceUpdate -ge 1) {
                Write-Host "WARNING: .project.json is $daysSinceUpdate day(s) stale (last: $lastUpdated)" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Warning "score-auto: .project.json parse failed ($($_.Exception.Message))"
    }
}

# ============================================================
# SAVE TO CACHE + SYNC .project.json
# ============================================================

try {
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $cacheObject = @{
        hash      = $cacheHash
        timestamp = (Get-Date -Format "o")
        result    = $result
    }
    $cacheObject | ConvertTo-Json -Depth 5 | Set-Content $cacheFile -Encoding UTF8
} catch {
    Write-Debug "score-cache save: $($_.Exception.Message)"
}

# --- Sync .project.json (single source of truth) ---
try {
    $pjPath = $projectJsonPath  # C4c: single path definition (no Join-Path + hardcoded string)
    $skipWorktreeRemoved = $false

    # Validation: ensure score is sane before writing (ported from restore-project-score.ps1)
    $dimCount = @($dimensions.Keys).Count
    if ($finalScore -lt 0 -or $finalScore -gt 10 -or $dimCount -lt 11) {
        Write-Debug "score-auto: validation failed — score=$finalScore, dims=$dimCount (expected: 0-10, >=11 dims). Skipping .project.json write."
    } else {
        if (Test-Path $pjPath) {
            & "git" "-C" $repoRoot "update-index", "--no-skip-worktree", ".project.json" 2>$null
            $skipWorktreeRemoved = $true
        }
        $result | ConvertTo-Json -Depth 5 | Set-Content $pjPath -Encoding UTF8
    }
} catch {
    Write-Debug "score-auto: .project.json sync failed ($($_.Exception.Message))"
} finally {
    # Always restore skip-worktree if we removed it
    if ($skipWorktreeRemoved) {
        try { & "git" "-C" $repoRoot "update-index", "--skip-worktree", ".project.json" 2>$null } catch { Write-Debug "score-auto: $($_.Exception.Message)" }
    }
}

Pop-Location

# ============================================================
# 5. OUTPUT
# ============================================================

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} elseif ($Quiet) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host "$($result.score.last_updated) | $finalScore/10 ($($result.score.trend))" -ForegroundColor Cyan
    Write-Host "Dimensions:" -ForegroundColor Yellow

    foreach ($key in $dimNames.Keys) {
        $dimData = $dimensions[$key]
        $color = if ($dimData.s -ge 9) {
            "Green"
        } elseif ($dimData.s -ge 7) {
            "Yellow"
        } else {
            "Red"
        }
        Write-Host " $($dimNames[$key].PadRight(16))$($dimData.s.ToString('F1').PadLeft(4))/10" -ForegroundColor $color
    }

    Write-Host $("-" * 32)
    Write-Host " TOTAL$(''.PadLeft(12))$($finalScore.ToString('F1').PadLeft(4))/10" -ForegroundColor White
}

# Explicit success exit — native calls inside (git update-index) may leave
# $LASTEXITCODE dirty; the contract is exit 0 on success (score-cache exit 0 parity)
exit 0
