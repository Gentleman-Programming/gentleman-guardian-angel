#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Context-window watchdog — monitors context usage and recommends
    Recursive Summary Compression (L1/L2/L3) based on usage zone.

.DESCRIPTION
    Implements the Context-Window Protection protocol from the skill-graph:

    Zone thresholds (percentage of context window used):
      GREEN  (0–40%)  — Normal operation, no compression needed
      YELLOW (40–60%) — Conserve context, summarize completed outputs
      ORANGE (60–80%) — Light compression (L1), trim passive context
      RED    (80–100%)— Aggressive compression (L2/L3), prepare for session end

    Compression levels:
      L1 — Light:      Summarize completed tool outputs, keep active context
      L2 — Medium:     Recursive summary of completed sections, trim buffers
      L3 — Heavy:      Maximum compression, retain only critical instructions

    Call after each major reasoning round. Use ctx_stats MCP tool to get
    current usage, then pass it here for a zone recommendation.

.PARAMETER UsagePercent
    Current context usage as a percentage (0-100).

.PARAMETER UsedBytes
    Current bytes consumed (alternative to UsagePercent).

.PARAMETER TotalBytes
    Total context window size in bytes. Required if UsedBytes is provided.

.PARAMETER Json
    Emit machine-readable JSON.

.EXAMPLE
    .\scripts\ctx-watchdog.ps1 -UsagePercent 75
    # → "ORANGE  75% — L1 Light compression: summarize completed tool outputs"

    .\scripts\ctx-watchdog.ps1 -UsedBytes 120000 -TotalBytes 200000 -Json
#>
param(
    [int]$UsagePercent = -1,
    [int64]$UsedBytes = 0,
    [int64]$TotalBytes = 0,
    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Resolve usage percentage ---
if ($UsagePercent -lt 0) {
    if ($UsedBytes -gt 0 -and $TotalBytes -gt 0) {
        $UsagePercent = [math]::Round(($UsedBytes / $TotalBytes) * 100)
    } else {
        $UsagePercent = 0
    }
}

# --- Determine zone and compression level ---
$zone = ""
$compressionLevel = ""
$action = ""
$recommendation = ""

if ($UsagePercent -le 40) {
    $zone = "GREEN"
    $compressionLevel = ""
    $action = "normal operation"
    $recommendation = "No compression needed — continue working"
}
elseif ($UsagePercent -le 60) {
    $zone = "YELLOW"
    $compressionLevel = "L1"
    $action = "conserve context"
    $recommendation = "L1 Light compression: summarize completed tool outputs, trim buffers, keep active context"
}
elseif ($UsagePercent -le 80) {
    $zone = "ORANGE"
    $compressionLevel = "L1"
    $action = "light compression (L1)"
    $recommendation = "L1 Light compression: compress completed sections, keep only essential context"
}
elseif ($UsagePercent -le 95) {
    $zone = "RED"
    $compressionLevel = "L2"
    $action = "aggressive compression (L2)"
    $recommendation = "L2 Medium compression: recursive summary of completed sections, retain only critical instructions"
}
else {
    $zone = "CRITICAL"
    $compressionLevel = "L3"
    $action = "maximum compression (L3)"
    $recommendation = "L3 Heavy compression: compress everything, prepare for session end — consider calling mem_session_summary"
}

if ($Json) {
    [PSCustomObject]@{
        zone        = $zone
        percent     = $UsagePercent
        level       = $compressionLevel
        action      = $action
        recommendation = $recommendation
    } | ConvertTo-Json -Compress
    exit 0
}

# Human-readable
$icon = switch ($zone) {
    "GREEN"    { "OK  " }
    "YELLOW"   { "WARN" }
    "ORANGE"   { "WARN" }
    "RED"      { "X   " }
    "CRITICAL" { "XX  " }
    default    { "??  " }
}
Write-Output "$icon $zone  $UsagePercent% — $recommendation"
