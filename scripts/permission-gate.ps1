#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Gentleman Agent — Runtime Permission Gate
.DESCRIPTION
    Classifies a command as allow/ask/deny based on current mode (.gentleman-mode).
    Works as a behavioral gate — the orchestrator calls this BEFORE running
    any command to check if it's permitted in the current mode.

    Modes:
      manual → Everything asks (except built-in denials: network, interpreters, destructive)
      semi   → Safe commands (read-only git, filesystem, search, test) auto-allow
      auto   → Everything auto-allows except push + deletes (ask) + network (deny)

.PARAMETER Command
    The full command string to check (e.g. "git push origin main")

.PARAMETER Mode
    Override mode (default: read from .gentleman-mode)

.PARAMETER ModeFilePath
    Override the mode file path (default: <repo>\.gentleman-mode)

.PARAMETER ListModes
    Show mode summaries

.EXAMPLE
    .\scripts\permission-gate.ps1 -Command "git status"
    .\scripts\permission-gate.ps1 -Command "rm -rf node_modules"
    .\scripts\permission-gate.ps1 -Command "git push" -Mode auto
#>

param(
    [string]$Command = "",
    [ValidateSet('manual','semi','auto')][string]$Mode = "",
    [switch]$ListModes,
    [switch]$Json,
    [switch]$Force,
    [switch]$DryRun,
    [string]$ModeFilePath
)
Set-StrictMode -Version Latest

# --- Dot-source shared classification logic (single source of truth) ---
. (Join-Path (Join-Path $PSScriptRoot "lib") "permission-gate-lib.ps1")

# --- Resolve paths ---
$repoRoot = Split-Path -Path $PSScriptRoot -Parent

# --- Resolve current mode (-Mode override wins; else read mode file) ---
$Mode = Get-ConfiguredMode -Mode $Mode -ModeFilePath $ModeFilePath -RepoRoot $repoRoot

# =====================================================================
# CROSS-REFERENCE MIRROR — DO NOT EDIT THE PATTERNS HERE.
# Runtime source of truth: scripts/lib/permission-gate-lib.ps1
# scripts/cross-ref-check.ps1 [10/9] TEXT-SCANS this file for the single-quoted
# caret-anchored pattern literals below to keep semi-agents.json in sync with
# the gate. When you
# edit the arrays in the lib, mirror them here (verbatim) so the scan output
# stays unchanged. Each line is a comment; nothing here executes.
#   deny:  '^curl\s', '^wget\s', '^Invoke-WebRequest', '^Invoke-RestMethod',
#          '^irm\s', '^iwr\s', '^iex\s', '^icm\s', '^Invoke-Expression', '^wsl\s', '^Start-BitsTransfer',
#          '^ssh\s', '^docker\s', '^docker-compose\s', '^docker compose',
#          '^telnet\s', '^ncat\s', '^nc\s', '^Test-NetConnection',
#          '^python\s', '^python3\s', '^node\s', '^ruby\s', '^perl\s', '^php\s', '^npx\s',
#          '^certutil\s', '^bitsadmin\s', '^schtasks\s', '^reg\s', '^sc\s', '^icacls\s',
#          '^cmd /c', '^cmd\.exe', '^powershell\s-c\s', '^powershell\s-command\s',
#          '^powershell\s-enc\s', '^powershell\s-File\s', '^powershell\.exe',
#          '^pwsh\s', '^pwsh\.exe',
#          '^Start-Process', '^Invoke-Command', '^Register-ScheduledTask', '^New-Service',
#          '^net user', '^net localgroup', '^net share', '^net use', '^net session',
#          '^Add-MpPreference', '^Set-MpPreference',
#          '^saps\s', '^start\s',
#          '^git push --force', '^git push -f'
#   destructive (deny in manual/semi, ask in auto):
#          '^rm\s', '^rm -rf', '^Remove-Item', '^git clean\s', '^git rm\s'
#   semi:  '^git status', '^git log', '^git diff', '^git show', '^git branch',
#          '^git stash list', '^git stash show',
#          '^ls$', '^ls\s', '^dir$', '^dir\s', '^Get-ChildItem', '^Test-Path',
#          '^pwd$', '^Get-Location', '^cat\s', '^Get-Content', '^type\s',
#          '^echo\s', '^Write-Output',
#          '^grep\s', '^rg\s', '^Select-String', '^findstr\s',
#          '^which\s', '^Get-Command', '^Get-Help', '^Get-Alias',
#          '^npm test', '^pytest\s', '^go test', '^Invoke-Pester',
#          '^dotnet test', '^cargo test', '^npm run', '^npm ci',
#          '^pip (freeze|list|show|install --user)(\s|$)',
#          '^git stash list$', '^git status$', '^git diff$', '^git log$'
#   auto:  '^git push$', '^git push\s', '^git push --delete'
# =====================================================================

# ===== OUTPUT =====
if ($ListModes) {
    $summaries = @{
        manual = "Manual: Everything asks (with built-in denials for network/interpreters/destructive)"
        semi   = "Semi:   Read-only git/filesystem/search/test auto-approve, writes ask, destructive denied"
        auto   = "Auto:   Everything auto-approves except git push + deletes (ask) and network (deny)"
    }
    if ($Json) {
        $summaries | ConvertTo-Json
    } else {
        $summaries.Values | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }
    }
    return
}

try {
    $verdict = Get-CommandClass -cmd $Command -mode $Mode

    # -Force: override 'ask' -> 'allow' for headless automation that already vetted the command.
    # -DryRun: pure evaluation mode — never applies the -Force override.
    if ($verdict -eq 'ask' -and $Force -and -not $DryRun) {
        $verdict = 'allow'
    }

    if ($Json) {
        @{
            action  = 'permission-gate'
            command = $Command
            mode    = $Mode
            verdict = $verdict
            dry_run = $DryRun.IsPresent
            rule    = switch ($verdict) {
                'deny'  { 'Built-in security restriction' }
                'allow' { "Allowed in $Mode mode" }
                'ask'   { "Requires confirmation in $Mode mode" }
                'help'  { 'No command provided' }
            }
        } | ConvertTo-Json
    } else {
        $icon = switch ($verdict) {
            'allow' { '✅' }
            'ask'   { '⏸️' }
            'deny'  { '❌' }
            'help'  { 'ℹ️' }
        }
        $modeLabel = $Mode.ToUpper().PadRight(8)
        Write-Host "$icon [$modeLabel] $Command" -NoNewline
        switch ($verdict) {
            'allow' { Write-Host " → ALLOW" -ForegroundColor Green }
            'ask'   { Write-Host " → ASK"  -ForegroundColor Yellow }
            'deny'  { Write-Host " → DENY" -ForegroundColor Red }
            'help'  { Write-Host "Usage: permission-gate.ps1 -Command '<cmd>' [-Mode manual|semi|auto]" }
        }
    }
} catch {
    Write-Error "Permission gate error: $_"
    exit 1
}
