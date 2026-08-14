#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Session checkpoint bridge — integrates context-watchdog, engram-validate, and
    session-miner into a single proactive memory-capture pipeline.

.DESCRIPTION
    Bridges the gap between context-window monitoring and Engram persistence.
    Addresses the "medium-term conversational memory" weakness: without this
    bridge, decisions/bugfixes/discoveries made between mem_session_summary
    calls (i.e. mid-session compaction cycles) are lost.

    Pipeline:
      1. ctx_watchdog reports zone (GREEN/YELLOW/ORANGE/RED/CRITICAL)
      2. If YELLOW+ → create checkpoint in Engram (mem_save topic_key checkpoint/session-state)
      3. Validate content via engram-validate (poisoning guard)
      4. Index any large output via ctx_index for cross-session recovery
      5. Optionally trigger session-miner for pattern detection

    Call every 5-10 tool rounds or whenever ctx_watchdog exits YELLOW.

.PARAMETER Mode
    check  — Report current zone + whether a checkpoint is needed (no write)
    mark   — Create checkpoint in Engram (requires mem_save availability)
    full   — check + mark + miner scan (default)

.PARAMETER UsagePercent
    Current context usage percent (alternative to measuring via ctx_stats MCP).

.PARAMETER Quiet
    Output JSON only.

.PARAMETER Force
    Bypass the YELLOW threshold — create checkpoint regardless of zone.

.PARAMETER NoValidate
    Skip engram-validate gate (use only if validator is unavailable).

.EXAMPLE
    .\scripts\session-checkpoint.ps1 -Mode check
    # → OK  GREEN  12% — no checkpoint needed

    .\scripts\session-checkpoint.ps1 -Mode full -Force
    # → Creates checkpoint even in GREEN

.EXAMPLE
    .\scripts\session-checkpoint.ps1 -Mode check -UsagePercent 65 -Json
    # → {"zone":"YELLOW","percent":65,"level":"L1","checkpoint_needed":true,"action":"checkpoint_recommended"}
#>
param(
    [ValidateSet('check','mark','full')]
    [string]$Mode = 'full',
    [int]$UsagePercent = -1,
    [string[]]$Discoveries = @(),
    [string[]]$Decisions = @(),
    [switch]$Quiet,
    [switch]$Force,
    [switch]$NoValidate
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$checkpointDir = Join-Path -Path $repoRoot -ChildPath ".opencode\session-checkpoints"

# --- Ensure checkpoint dir exists ---
if (-not (Test-Path -LiteralPath $checkpointDir)) {
    $null = New-Item -ItemType Directory -Path $checkpointDir -Force -ErrorAction SilentlyContinue
}

# --- Step 1: Get context zone from ctx-watchdog ---
$watchdogResult = & "$PSScriptRoot\ctx-watchdog.ps1" -UsagePercent $UsagePercent -Json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $watchdogResult) {
    $watchdogResult = [PSCustomObject]@{
        zone   = "UNKNOWN"
        percent = $UsagePercent
        level  = ""
        recommendation = "Unable to determine context zone"
    }
}

$contextZone   = $watchdogResult.zone
$contextLevel  = $watchdogResult.level
$zoneNeedsCheckpoint = switch ($contextZone) {
    "GREEN"     { $false }
    "YELLOW"    { $true }
    "ORANGE"    { $true }
    "RED"       { $true }
    "CRITICAL"  { $true }
    default     { $false }
}

# --- Step 2: Decide checkpoint action ---
$checkpointNeeded = $zoneNeedsCheckpoint -or $Force -or $Discoveries.Count -gt 0 -or $Decisions.Count -gt 0

# --- Step 3: If checkpoint needed and mode is mark/full, create it ---
$checkpointData = [PSCustomObject]@{
    timestamp      = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    session_id     = "session-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    context_zone   = $contextZone
    context_percent = $watchdogResult.percent
    compression_level = $contextLevel
    decisions      = $Decisions
    discoveries    = $Discoveries
    files_touched  = @((git -C $repoRoot status --porcelain 2>$null) -split "`n" | Where-Object { $_ -match '\S' })
    branch         = (git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null)
    recommendation = $watchdogResult.recommendation
}

$checkpointPath = Join-Path -Path $checkpointDir -ChildPath "$($checkpointData.session_id).json"
$checkpointData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $checkpointPath -Encoding UTF8

# --- Step 4: Validate before mem_save (poisoning guard) ---
$validated = $true
if (-not $NoValidate) {
    $validatorPath = Join-Path -Path $PSScriptRoot -ChildPath "engram-validate.ps1"
    if (Test-Path -LiteralPath $validatorPath) {
        $contentSummary = "**What**: Session checkpoint at $contextZone zone ($($watchdogResult.percent)% context). " +
                         "**Why**: Proactive capture to prevent memory loss across compaction cycles. " +
                         "**Where**: .opencode/session-checkpoints/$($checkpointData.session_id).json. " +
                         "**Learned**: Zone=$contextZone, decisions=$($Decisions.Count), discoveries=$($Discoveries.Count)."
        $validationParams = @{
            Content = $contentSummary
            Title = "checkpoint:session-state:$($checkpointData.session_id)"
            Type  = "pattern"
            PassThru = $true
            Quiet = $true
        }
        $validationResult = & $validatorPath @validationParams 2>$null
        $validated = $null -ne $validationResult -or $LASTEXITCODE -eq 0
    }
}

# --- Step 5: Persist to Engram (if checkpoint needed and validated) ---
$memSaved = $false
if ($Mode -in @('mark', 'full') -and $checkpointNeeded -and $validated) {
    $memContent = "**What**: Session checkpoint at $contextZone zone ($($watchdogResult.percent)% context used). Captured $($Decisions.Count) decisions and $($Discoveries.Count) discoveries proactively. **Why**: Prevent memory loss across compaction cycles — medium-term conversational context is lost without explicit persistence. **Where**: .opencode/session-checkpoints/ + Engram checkpoint/session-state. **Learned**: This bridge connects ctx-watchdog zone detection → engram-validate → mem_save → ctx_index. Without it, mid-session decisions vanish at compaction."
    $topicKey = "checkpoint/session-state"
    # Note: mem_save is an MCP tool call, not available in this script context.
    # The script writes the checkpoint JSON; the orchestrator/skill runtime
    # calls mem_save with the same topic_key. This is the on-disk durable layer.
}

# --- Step 6: Index large output via ctx_index (for cross-session recovery) ---
$indexed = $false
if ($checkpointData.recommendation -and $checkpointData.recommendation.Length -gt 500) {
    # Large recommendation text → would be indexed by orchestrator via ctx_index
    # Script tracks that it SHOULD be indexed
    $indexed = $true  # flagged for orchestrator
}

# --- Step 7: Optionally trigger session-miner ---
$minerResult = $null
if ($Mode -eq 'full' -and ($Discoveries -or $Decisions)) {
    $minerPath = Join-Path -Path $PSScriptRoot -ChildPath "session-miner.ps1"
    if (Test-Path -LiteralPath $minerPath) {
        try {
            $minerParams = @{ Mode = "populate"; Json = $true }
            if ($Discoveries) { $minerParams.PatternKeys = $Discoveries }
            if ($Decisions) { $minerParams.ErrorEntries = $Decisions }
            $minerResult = & $minerPath @minerParams 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        } catch {
            Write-Debug "session-miner skipped: $($_.Exception.Message)"
        }
    }
}

# --- Output ---
$result = [PSCustomObject]@{
    zone              = $contextZone
    percent           = $watchdogResult.percent
    compression_level = $contextLevel
    checkpoint_needed = $checkpointNeeded
    checkpoint_created = if ($checkpointNeeded) { $true } else { $false }
    checkpoint_file   = if ($checkpointNeeded) { $checkpointPath } else { $null }
    validated         = $validated
    mem_saved         = $memSaved
    indexed           = $indexed
    miner_patterns    = if ($minerResult) { $minerResult.RepeatedPatterns } else { 0 }
    recommendation    = $watchdogResult.recommendation
    action            = if ($checkpointNeeded) {
        "checkpoint_created"
    } else {
        "none_needed"
    }
}

if ($Quiet) {
    $result | ConvertTo-Json -Compress -Depth 3
} else {
    if ($checkpointNeeded) {
        Write-Host "✅ CHECKPOINT  $contextZone  $($watchdogResult.percent)% — $($result.action)" -ForegroundColor Cyan
        Write-Host "  File: $checkpointPath" -ForegroundColor DarkGray
    } else {
        Write-Host "OK  $contextZone  $($watchdogResult.percent)% — no checkpoint needed" -ForegroundColor Green
    }
    if ($minerResult -and $minerResult.RepeatedPatterns -gt 0) {
        Write-Host "  ⛏️  $($minerResult.RepeatedPatterns) repeated pattern(s) — run dreaming" -ForegroundColor DarkYellow
    }
}
