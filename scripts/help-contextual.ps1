#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Contextual help — shows relevant shortcuts based on current context.
.DESCRIPTION
    Analyzes git status, current phase, and session state to suggest relevant shortcuts.
.PARAMETER Context
    Optional context: "debugging", "after-change", "start", "general".
.EXAMPLE
    ./scripts/help-contextual.ps1
    ./scripts/help-contextual.ps1 -Context debugging
#>
param(
    [ValidateSet("debugging", "after-change", "start", "general")]
    [string]$Context = "general"
)
Set-StrictMode -Version Latest

# Detect context if not provided
if ($Context -eq "general") {
    try {
        $gitStatus = git status --porcelain 2>&1
        $hasChanges = ($gitStatus | Measure-Object).Count -gt 0
        if ($hasChanges) { $Context = "after-change" }
    } catch {
        $Context = "general"
    }
}

Write-Output "`n=== Gentleman Agent — Contextual Help ===`n"

# Core shortcuts (always shown)
$coreShortcuts = @(
    @{ Cmd = "!health"; Desc = "Full diagnostics (git, drift, cross-ref, score)" }
    @{ Cmd = "!close"; Desc = "Session close pipeline" }
    @{ Cmd = "!score"; Desc = "Score auto-update + docs sync" }
)

# Context-specific shortcuts
$contextShortcuts = switch ($Context) {
    "debugging" {
        @(
            @{ Cmd = "!ponytail off"; Desc = "Bypass all quality gates for debugging" }
            @{ Cmd = "!ponytail lite"; Desc = "Default mode — minimal ceremony" }
            @{ Cmd = "!health"; Desc = "Full diagnostic report" }
        )
    }
    "after-change" {
        @(
            @{ Cmd = "!score"; Desc = "Measure improvement after changes" }
            @{ Cmd = "!ship"; Desc = "Triple verify + auto-commit" }
            @{ Cmd = "!check"; Desc = "Verify without committing" }
            @{ Cmd = "!fast"; Desc = "Quality gate only, auto-commit" }
        )
    }
    "start" {
        @(
            @{ Cmd = "!analisis"; Desc = "Deep multi-agent analysis (6 specialists)" }
            @{ Cmd = "!wisdom"; Desc = "Load cross-project patterns" }
            @{ Cmd = "!manifest"; Desc = "Show current cycle + score" }
        )
    }
    default {
        @(
            @{ Cmd = "!analisis"; Desc = "Deep multi-agent analysis" }
            @{ Cmd = "!ponytail"; Desc = "Set intensity: lite|full|ultra|off" }
            @{ Cmd = "!manifest"; Desc = "Show current cycle + score" }
        )
    }
}

Write-Output "Context: $Context`n"

Write-Output "--- Core Shortcuts ---"
foreach ($s in $coreShortcuts) {
    Write-Output "  $($s.Cmd) — $($s.Desc)"
}

Write-Output "`n--- Context-Specific ---"
foreach ($s in $contextShortcuts) {
    Write-Output "  $($s.Cmd) — $($s.Desc)"
}

Write-Output "`n--- All Shortcuts ---"
Write-Output "  Full reference: SHORTCUTS.md"
Write-Output ""
