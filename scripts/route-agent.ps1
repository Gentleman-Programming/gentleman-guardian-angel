#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Mode-aware agent routing — resolves the correct agent variant for delegation.

.DESCRIPTION
    Reads .gentleman-mode (manual|semi|auto) and appends the routing suffix
    to the base agent name per the Mode-Aware Routing protocol in AGENTS.md:

      manual → no suffix  (e.g. gentleman-quick)
      semi   → -semi      (e.g. gentleman-quick-semi)
      auto   → -auto      (e.g. gentleman-quick-auto)

    Read-only specialists and SDD phase subagents never get a suffix —
    they always execute directly. Agents without a -semi/-auto variant
    fall back to the base name automatically.

    This is the single source of truth invoked BEFORE every subagent
    delegation, so the orchestrator always announces the routing decision
    consistent with the current mode.

.PARAMETER BaseAgent
    Base agent name without mode suffix (e.g. gentleman-quick, gentleman-deep-sub).

.PARAMETER Mode
    Override mode instead of reading .gentleman-mode. If empty, reads the
    nearest .gentleman-mode file (walking up from cwd, stopping at project root).
    Defaults to 'manual' when no mode file is found.

.PARAMETER Json
    Emit machine-readable JSON (baseAgent, mode, targetAgent, suffix, note).

.EXAMPLE
    .\scripts\route-agent.ps1 -BaseAgent gentleman-quick
    .\scripts\route-agent.ps1 -BaseAgent gentleman-security-sub  # → no suffix
    .\scripts\route-agent.ps1 -BaseAgent gentleman-quick -Mode auto -Json
#>
param(
    [Parameter(Mandatory)]
    [string]$BaseAgent,

    [ValidateSet('manual', 'semi', 'auto')]
    [string]$Mode = "",

    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\platform.ps1")

# --- Agents that have -semi / -auto variants (per README + use-gentleman.ps1) ---
# Only these 5 core agent families support mode-aware routing.
$ModeAwareAgents = @('gentleman-vMK', 'gentleman-deep', 'gentleman-quick', 'gentleman-codex', 'gentleman-implementer')

# --- Read-only specialists: NO suffix ever (per AGENTS.md: "always execute") ---
$ReadOnlySpecialists = @(
    'gentleman-security-sub', 'gentleman-seo-sub', 'gentleman-infra-sub',
    'gentleman-frontend-sub', 'gentleman-performance-sub',
    'gentleman-datascience-sub', 'gentleman-docs-sub', 'gentleman-reviewer'
)

# --- Resolve mode ---
if (-not $Mode) {
    $projectRoot = if (Get-Command Get-GentlemanProjectRoot -ErrorAction SilentlyContinue) {
        Get-GentlemanProjectRoot
    } else {
        (Get-Location).Path
    }
    $modeFile = Join-Path $projectRoot '.gentleman-mode'
    if (Test-Path -LiteralPath $modeFile) {
        $Mode = (Get-Content -LiteralPath $modeFile -Raw).Trim()
    } else {
        $Mode = 'manual'   # protocol default
    }
}

# --- Routing logic ---
$note = ""
if ($ReadOnlySpecialists -contains $BaseAgent) {
    $TargetAgent = $BaseAgent
    $suffix      = ""
    $note        = "read-only specialist — no suffix"
}
elseif ($ModeAwareAgents -contains $BaseAgent) {
    switch ($Mode) {
        'manual' { $suffix = "" ; $note = "manual mode — no suffix" }
        'semi'   { $suffix = "-semi"; $note = "semi mode — suffixed -semi" }
        'auto'   { $suffix = "-auto"; $note = "auto mode — suffixed -auto" }
    }
    $TargetAgent = $BaseAgent + $suffix
}
else {
    # SDD phase agents (sdd-*) and non-mode-aware subagent twins (gentleman-*-sub): no suffix
    $TargetAgent = $BaseAgent
    $suffix      = ""
    # Warn for truly unknown agents (not sdd-* or *-sub variants)
    if ('sdd', '-sub' | Where-Object { $BaseAgent.Contains($_) }) {
        $note = "non-mode-aware agent — no suffix"
    } else {
        Write-Warning "route-agent: '$BaseAgent' is not a recognized agent — no suffix applied"
        $note = "unknown agent — no suffix (WARNING)"
    }
}

if ($Json) {
    return [PSCustomObject]@{
        baseAgent    = $BaseAgent
        mode         = $Mode
        targetAgent  = $TargetAgent
        suffix       = $suffix
        note         = $note
    } | ConvertTo-Json -Compress
}

# Human-readable output for direct invocation
Write-Output "🔀 → $TargetAgent | $note"

    return $TargetAgent

