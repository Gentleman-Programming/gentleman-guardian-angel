#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Gentleman Agent — Permission Mode Switcher
.DESCRIPTION
    Switches between MANUAL, SEMI, and AUTO permission modes.
    Reads the nearest .gentleman-mode walking up from the current directory,
    bounded by the project root (first .git — Get-GentlemanProjectRoot), so a
    global copy of this script still honors the external project's mode without
    inheriting a mode from HOME or unrelated ancestors.
    When no mode file exists, defaults to MANUAL; writes target the current
    directory (cwd) so a -Mode switch creates .gentleman-mode in the project.

    MANUAL (default): Every command asks for permission (*: ask)
    SEMI:            Safe commands auto-execute (read-only, test), rest ask
    AUTO:            Everything auto-executes except push + destructive ops

.PARAMETER Mode
    Target mode: manual, semi, auto

.PARAMETER Status
    Show current mode without changing

.PARAMETER Help
    Show help banner

.PARAMETER DryRun
    Reserved for parity with sibling scripts; accepted but not used
    by the switch logic.

.PARAMETER Force
    Reserved for parity with sibling scripts; accepted but not used
    by the switch logic.

.EXAMPLE
    ./switch-mode.ps1 -Mode semi
    ./switch-mode.ps1 -Status
    ./switch-mode.ps1
#>

param(
    [ValidateSet('manual','semi','auto')][string]$Mode,
    [switch]$Status,
    [switch]$Help,
    [switch]$Force,
    [switch]$DryRun
)
Set-StrictMode -Version Latest

# Normalize mode to lowercase BEFORE any use/validation (ValidateSet is
# case-insensitive and does NOT canonicalize: -Mode Semi would write 'Semi').
if ($Mode) { $Mode = $Mode.ToLower() }

# --- Resolve .gentleman-mode: nearest file walking up from cwd, bounded by the
#     project root (git root). Never past the project → no mode inheritance from
#     HOME or unrelated ancestors. Write targets cwd when absent. ---
$platformLib = Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1"
if (Test-Path -LiteralPath $platformLib) { . $platformLib }
$modeFile = $null
$dir = (Get-Location).Path
$projectRoot = if (Get-Command Get-GentlemanProjectRoot -ErrorAction SilentlyContinue) { Get-GentlemanProjectRoot } else { $dir }
while ($dir) {
    $candidate = Join-Path -Path $dir '.gentleman-mode'
    if (Test-Path -LiteralPath $candidate) { $modeFile = $candidate; break }
    if ($dir -eq $projectRoot) { break }
    $parent = Split-Path -Parent $dir
    if (-not $parent -or $parent -eq $dir) { break }
    $dir = $parent
}
if (-not $modeFile) { $modeFile = Join-Path -Path $projectRoot '.gentleman-mode' }

# --- Banner colors ---
$colors = @{
    manual = @{ fg = 'Yellow';  icon = '🟡' }
    semi   = @{ fg = 'Cyan';    icon = '🔵' }
    auto   = @{ fg = 'Green';   icon = '🟢' }
}

# --- Read current mode ---
function Get-CurrentMode {
    if (Test-Path -LiteralPath $modeFile) {
        return (Get-Content -LiteralPath $modeFile -Raw).Trim()
    }
    return 'manual'
}

# --- Show banner ---
function Show-Banner {
    $current = Get-CurrentMode
    $c = $colors[$current]
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor $c.fg
    Write-Host "║       Gentleman Agent Permission Mode    ║" -ForegroundColor $c.fg
    Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor $c.fg
    Write-Host "║                                            ║" -ForegroundColor $c.fg
    Write-Host "║  $($c.icon)  Current: $($current.ToUpper().PadRight(32))║" -ForegroundColor $c.fg
    Write-Host "║                                            ║" -ForegroundColor $c.fg
    Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor DarkGray
    Write-Host "║  Commands:                                 ║" -ForegroundColor DarkGray
    Write-Host "║  ./switch-mode.ps1 -Mode manual|semi|auto  ║" -ForegroundColor DarkGray
    Write-Host "║  ./switch-mode.ps1 -Status                 ║" -ForegroundColor DarkGray
    Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor DarkGray
    Write-Host "║  manual:  Everything asks permission       ║" -ForegroundColor Yellow
    Write-Host "║  semi:    Safe commands auto-approve       ║" -ForegroundColor Cyan
    Write-Host "║  auto:    All auto except push + deletes   ║" -ForegroundColor Green
    Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor DarkGray
    Write-Host "║  Tip: Use in OpenCode: !manual / !semi /  ║" -ForegroundColor DarkGray
    Write-Host "║       !auto / !mode                        ║" -ForegroundColor DarkGray
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor $c.fg
}

# --- Show summary of what each mode allows ---
function Show-ModeDetail {
    param([string]$targetMode)
    $N = [Environment]::NewLine
    $text = switch ($targetMode) {
        manual { "MANUAL MODE --- Maximum safety${N}  Git:              All operations ask${N}  File read:        Allowed but each command asks${N}  File write/edit:  Allowed but each command asks${N}  Scripts:          Each execution asks${N}  Network:          Denied (curl, ssh, docker, etc.)${N}  Destructive:      Denied (rm, Remove-Item, etc.)${N}  Interpreters:     Denied (python, node, ruby, etc.)${N}${N}  Best for: Exploration, learning, untrusted code" }
        semi   { "SEMI-AUTO MODE --- Balanced${N}  [OK] Git read:      status, log, diff, show, branch --- auto${N}  [OK] File read:     ls, pwd, cat, grep, Test-Path --- auto${N}  [OK] Build/test:    npm test, pytest, go test, Invoke-Pester --- auto${N}  [..] Git write:     commit, add, push --- ask${N}  [..] File create:   mkdir, New-Item --- ask${N}  [NO] Network:       Denied (curl, ssh, docker)${N}  [NO] Destructive:   Denied (rm, Remove-Item)${N}  [NO] Interpreters:  Denied (python, node)${N}${N}  Best for: Daily development with guardrails" }
        auto   { "AUTO MODE --- Maximum speed (autonomous on request)${N}  [OK] Git:           Everything auto except push${N}  [OK] File ops:      Read, write, edit --- auto${N}  [OK] Scripts:       Execute --- auto${N}  [OK] Commit:        Auto (no ask)${N}  [..] Git push:      Ask (unless --force, which is denied)${N}  [..] Deletes:       Ask (rm, Remove-Item, branch -D, stash drop)${N}  [NO] Network:       Denied (curl, ssh, docker, python, node)${N}${N}  Best for: Focused implementation, trusted environment" }
    }
    $text = $text -replace '\[OK\]', '✅' -replace '\[..\]', '⏸️ ' -replace '\[NO\]', '❌'
    Write-Host "${N}${text}" -ForegroundColor White
}

# ===== MAIN =====

if ($Help -or ($PSBoundParameters.Count -eq 0 -and -not $Status)) {
    Show-Banner
    Show-ModeDetail -targetMode (Get-CurrentMode)
    return
}

if ($Status) {
    $current = Get-CurrentMode
    Write-Output $current
    return
}

# --- Switching ---
$current = Get-CurrentMode

if ($Mode -eq $current) {
    $c = $colors[$Mode]
    Write-Host "`n$($c.icon)  Already in $Mode mode." -ForegroundColor $c.fg
    Show-ModeDetail -targetMode $Mode
    return
}

# Write the new mode
try {
    $Mode | Set-Content -LiteralPath $modeFile -NoNewline -Encoding ASCII -ErrorAction Stop
} catch {
    Write-Error "Failed to write mode file: $_"
    exit 1
}
$c = $colors[$Mode]

Write-Host "`n$($c.icon)  Switched to $Mode mode." -ForegroundColor $c.fg
Write-Host "" -ForegroundColor $c.fg

Show-ModeDetail -targetMode $Mode

Write-Host "`n⚠️  IMPORTANTE:" -ForegroundColor Yellow
Write-Host "   El cambio de modo requiere que el orquestador recargue la skill de routing." -ForegroundColor Yellow
Write-Host "   Los shortcuts !manual/!semi/!auto en OpenCode activan el modo completo." -ForegroundColor Yellow
Write-Host "   Para aplicar los permisos a nivel OpenCode runtime, se necesita:" -ForegroundColor Yellow
Write-Host "   1. Editar opencode.json con los agents -$Mode (ver docs adjuntos)" -ForegroundColor Yellow
Write-Host "   2. El orquestador usará agents con sufijo -$Mode en las delegaciones" -ForegroundColor Yellow
Write-Host "`n   Usa '!mode' en OpenCode para ver el modo actual." -ForegroundColor Cyan
