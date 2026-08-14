#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Mode Gate — pre-delegation validation. Verifies agent suffix matches current mode.
.DESCRIPTION
    Before delegating to a sub-agent, the orchestrator MUST call this gate.
    It reads .gentleman-mode and validates that the target agent name has the
    correct suffix for the current mode.

    Mode → Required suffix:
      auto   → -auto (e.g., gentleman-quick → gentleman-quick-auto)
      semi   → -semi (e.g., gentleman-quick → gentleman-quick-semi)
      manual → no suffix (e.g., gentleman-quick → gentleman-quick)

    If the suffix doesn't match, the gate BLOCKS the delegation with a clear error.

.PARAMETER TargetAgent
    The intended delegation target (e.g., "gentleman-quick").

.PARAMETER Mode
    Override mode check (default: read from .gentleman-mode).

.PARAMETER ModeFilePath
    Override the mode file path (default: nearest .gentleman-mode walking up from
    cwd, bounded by the project root — see Get-GentlemanProjectRoot).

.PARAMETER Json
    Output JSON instead of human-readable text.

.EXAMPLE
    .\scripts\mode-gate.ps1 -TargetAgent "gentleman-quick-auto"
    .\scripts\mode-gate.ps1 -TargetAgent "gentleman-quick" -Mode auto -Json
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetAgent,

    [ValidateSet('manual', 'semi', 'auto')]
    [string]$Mode,

    [switch]$Json,

    [string]$ModeFilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Cross-platform helpers (Get-GlobalConfigDir)
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")

$projectRoot = if (Get-Command Get-GentlemanProjectRoot -ErrorAction SilentlyContinue) { Get-GentlemanProjectRoot } else { (Get-Location).Path }

# --- Resolve .gentleman-mode: nearest file walking up from cwd, NEVER past the
#     project root (git root) — no repo fallback, so an external project without
#     its own mode file cannot inherit the repo's mode. Mirrors switch-mode. ---
$modeFile = if ($ModeFilePath) {
    $ModeFilePath
} else {
    $found = $null
    $dir = (Get-Location).Path
    while ($dir) {
        $candidate = Join-Path -Path $dir '.gentleman-mode'
        if (Test-Path -LiteralPath $candidate) { $found = $candidate; break }
        if ($dir -eq $projectRoot) { break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    if ($found) { $found } else { Join-Path -Path $projectRoot '.gentleman-mode' }
}

# --- Resolve current mode ---
if (-not $Mode) {
    if (Test-Path -LiteralPath $modeFile) {
        $Mode = (Get-Content -LiteralPath $modeFile -Raw).Trim()
    } else {
        $Mode = 'manual'  # default fallback
    }
}

# --- Determine expected suffix ---
$suffixMap = @{
    'auto'   = '-auto'
    'semi'   = '-semi'
    'manual' = ''
}
$expectedSuffix = $suffixMap[$Mode]

# --- Determine if agent is a read-only specialist (always exception) ---
$readOnlySpecialists = @(
    'gentleman-security',
    'gentleman-seo',
    'gentleman-infra',
    'gentleman-frontend',
    'gentleman-performance',
    'gentleman-datascience',
    'gentleman-docs',
    'gentleman-reviewer'
)
$isReadOnly = $TargetAgent -in $readOnlySpecialists

# --- Validate ---
$hasSuffix = $TargetAgent -match '-auto$|-semi$'
$modeOk = $false

if ($isReadOnly) {
    $modeOk = $true  # Read-only specialists always use base name
} elseif ($Mode -eq 'manual') {
    $modeOk = -not $hasSuffix  # No suffix allowed in manual
} elseif ($Mode -eq 'auto') {
    $modeOk = $TargetAgent -match '-auto$'
} elseif ($Mode -eq 'semi') {
    $modeOk = $TargetAgent -match '-semi$'
}

# --- Read-only and SDD sub-agents are always allowed ---
$alwaysAllowed = @(
    'gentleman-orchestrator',
    'sdd-init',
    'sdd-explore',
    'sdd-propose',
    'sdd-design',
    'sdd-spec',
    'sdd-tasks',
    'sdd-apply',
    'sdd-verify',
    'sdd-archive',
    'sdd-quick'
)
$isAlwaysAllowed = $TargetAgent -in $alwaysAllowed

# --- Fallback: does the suffixed agent exist in any resolvable config? ---
# In external projects the -auto/-semi variants may not be defined (pre-sync).
# If the suffixed agent does NOT exist anywhere, allow the base agent instead
# of dead-blocking the delegation.
function Test-SuffixedAgentPresence {
    param([string]$AgentName)
    $candidates = @(
        (Join-Path (Get-Location) 'opencode.json'),
        (Join-Path (Get-Location) 'opencode.jsonc'),
        (Join-Path (Get-GlobalConfigDir) 'opencode.json'),
        (Join-Path (Get-GlobalConfigDir) 'opencode.jsonc')
    ) | Where-Object { Test-Path -LiteralPath $_ }
    foreach ($cfg in $candidates) {
        try {
            $parsed = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
            $agentSection = $parsed.PSObject.Properties['agent']
            if ($null -ne $agentSection) {
                $prop = $agentSection.Value.PSObject.Properties[$AgentName]
                if ($null -ne $prop) { return $true }
            }
        } catch { continue }
    }
    return $false
}

if ($isAlwaysAllowed) {
    $modeOk = $true
}

# --- Fallback resolution (auto/semi): suffixed agent missing → allow base ---
$fallbackUsed = $false
if (-not $modeOk -and $Mode -ne 'manual' -and -not $isReadOnly -and -not $hasSuffix) {
    $suffixedAgent = "$TargetAgent$expectedSuffix"
    if (-not (Test-SuffixedAgentPresence -AgentName $suffixedAgent)) {
        $modeOk = $true
        $fallbackUsed = $true
    }
}

# --- Build result ---
$result = [PSCustomObject]@{
    action          = 'mode-gate'
    mode            = $Mode
    target_agent    = $TargetAgent
    expected_suffix = $expectedSuffix
    allowed         = $modeOk
    reason          = if ($modeOk) {
        if ($isAlwaysAllowed) { "Always-allowed agent: $TargetAgent" }
        elseif ($isReadOnly) { "Read-only specialist: $TargetAgent" }
        elseif ($fallbackUsed) { "FALLBACK: '$TargetAgent$expectedSuffix' not defined in configs — allowed base agent '$TargetAgent'" }
        elseif ($Mode -eq 'manual') { "Manual mode — no suffix required" }
        else { "Mode '$Mode' — suffix '$expectedSuffix' matches" }
    } else {
        if ($Mode -eq 'auto') { "AUTO mode requires -auto suffix (got: $TargetAgent, expected: $TargetAgent-auto)" }
        elseif ($Mode -eq 'semi') { "SEMI mode requires -semi suffix (got: $TargetAgent, expected: $TargetAgent-semi)" }
        else { "MANUAL mode requires NO suffix (got: $TargetAgent, expected: $TargetAgent without suffix)" }
    }
}

if ($Json) {
    Write-Output ($result | ConvertTo-Json)
    if (-not $modeOk) { exit 1 } else { exit 0 }
}

# --- Human-readable output ---
$fg = if ($modeOk) { 'Green' } else { 'Red' }
$icon = if ($modeOk) { '✅' } else { '❌' }
$status = if ($modeOk) { 'ALLOWED' } else { 'BLOCKED' }

Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor $fg
Write-Host "║         Mode Gate — Delegation Check    ║" -ForegroundColor $fg
Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor $fg
Write-Host "║  $icon  Mode:  $($Mode.ToUpper().PadRight(36))║" -ForegroundColor $fg
Write-Host "║  $icon  Agent: $($TargetAgent.PadRight(36))║" -ForegroundColor $fg
Write-Host "║  $icon  Suffix: $($expectedSuffix.PadRight(35))║" -ForegroundColor $fg
Write-Host "║                                            ║" -ForegroundColor $fg
Write-Host "║  ══ $status ══" -ForegroundColor $fg
if (-not $modeOk) {
    Write-Host "║                                            ║" -ForegroundColor $fg
    Write-Host "║  $($result.reason.PadRight(44))║" -ForegroundColor $fg
}
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor $fg

if (-not $modeOk) {
    exit 1
}
exit 0
