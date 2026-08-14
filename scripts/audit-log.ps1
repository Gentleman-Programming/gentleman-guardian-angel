#requires -Version 7
<#
.SYNOPSIS
  Audit trail for .gentleman agent actions — append-only log with read/filter/session.
.DESCRIPTION
  Manages .gentleman/audit.log — an append-only CSV tracking agent actions
  across all modes. Supports three commands: append, read, session.
.PARAMETER Command
  append | read | session
.PARAMETER Agent
  Agent name for append (e.g. gentleman-deep-auto)
.PARAMETER Mode
  Mode for append: manual | semi | auto
.PARAMETER Action
  Action type: ALLOW | DENY | ASK_ALLOW | ASK_DENY | WRITE | EDIT | ERROR
.PARAMETER Detail
  The command or detail being logged
.PARAMETER FilterAction
  Filter read/session by action type (accepts wildcard)
.PARAMETER FilterAgent
  Filter read/session by agent name (accepts wildcard)
.PARAMETER Last
  Show only last N entries (read mode)
.PARAMETER Since
  Show entries since this datetime (session mode)
.EXAMPLE
  .\scripts\audit-log.ps1 append -agent gentleman-deep-auto -mode auto -action ALLOW -detail "git status"
.EXAMPLE
  .\scripts\audit-log.ps1 read -filterAction DENY -last 20
.EXAMPLE
  .\scripts\audit-log.ps1 session -since "2026-07-29"
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Position=0, Mandatory)]
    [ValidateSet('append','read','session')]
    [string]$Command,

    [string]$Agent = "unknown",
    [ValidateSet('manual','semi','auto','unknown')]
    [string]$Mode = "unknown",
    [ValidateSet('ALLOW','DENY','ASK_ALLOW','ASK_DENY','WRITE','EDIT','ERROR','DECISION','INFO')]
    [string]$Action = "INFO",
    [string]$Detail = "",

    [string]$FilterAction = "*",
    [string]$FilterAgent = "*",
    [int]$Last = 50,
    [datetime]$Since
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Cross-platform helpers (Get-GentlemanProjectRoot; lib may be absent in a stale global copy)
$platformLib = Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1"
if (Test-Path -LiteralPath $platformLib) { . $platformLib }

<#
.SYNOPSIS
    RFC 4180 field escaping that also neutralizes CSV formula injection.
.DESCRIPTION
    Prepares an untrusted string (e.g. a Detail / command line) for a single
    quoted field of the audit CSV. Guarantees the field can never be
    interpreted by a spreadsheet program as a formula, and never corrupts the
    log row structure. It:
      1. collapses CR / LF / tab into a single space (kills multi-line row
         injection and tab-prefixed formula triggers);
      2. prefixes a single quote to a leading '=', '+', '-', '@' so Excel/Libre
         Calc read the cell as literal text, never a formula;
      3. doubles any embedded double quotes per RFC 4180;
      4. wraps the whole (possibly comma-bearing) field in double quotes.
.NOTES
    Only the Detail field is attacker-controlled; the other fields (timestamp,
    agent, mode, action) come from validated parameters and stay unquoted so
    the read/session parsers keep matching on ", ALLOW," / "^yyyy-MM-dd ...".
#>
function ConvertTo-SafeCsvField {
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Field)

    # (1) Collapse CR/LF/tab — kills row-spraying and tab-based formula triggers
    $safe = $Field -replace "[\t\r\n]+", ' '

    # (2) Neutralize a leading formula-trigger so Excel/LibreOffice won't eval it
    if ($safe -match '^[=+\-@]') {
        $safe = "'" + $safe
    }

    # (3) RFC 4180: double any embedded double quote
    $safe = $safe -replace '"', '""'

    # (4) Wrap the field in double quotes
    return '"' + $safe + '"'
}

# Audit log targets the CURRENT PROJECT root (walk-up from cwd to git root),
# NOT the script's repo — so a globalized copy logs into the external project.
$projectRoot = if (Get-Command Get-GentlemanProjectRoot -ErrorAction SilentlyContinue) { Get-GentlemanProjectRoot } else { $env:GENTLEMAN_AGENT_ROOT }
if (-not $projectRoot) { $projectRoot = (Get-Location).Path }
$logDir = Join-Path $projectRoot ".gentleman"
$logFile = Join-Path $logDir "audit.log"

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

switch ($Command) {
    'append' {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $safeDetail = ConvertTo-SafeCsvField -Field $Detail
        $line = "$timestamp, $Agent, $Mode, $Action, $safeDetail"
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
        Write-Verbose "audit: $line"
    }

    'read' {
        if (-not (Test-Path -LiteralPath $logFile)) {
            Write-Host "Audit log not found" -ForegroundColor Yellow
            return
        }
        [string[]]$allLines = Get-Content -LiteralPath $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($allLines.Count -le 1) {
            Write-Host "No entries found" -ForegroundColor Yellow
            return
        }
        [System.Collections.ArrayList]$filtered = @()
        foreach ($line in $allLines) {
            if ($line -match "^#") { continue }
            if ($FilterAction -ne "*" -and $line -notmatch $FilterAction) { continue }
            if ($FilterAgent -ne "*" -and $line -notmatch $FilterAgent) { continue }
            $null = $filtered.Add($line)
        }
        if ($filtered.Count -eq 0) {
            Write-Host "No matching entries" -ForegroundColor Yellow
            return
        }
        $start = [Math]::Max(0, $filtered.Count - $Last)
        for ($i = $start; $i -lt $filtered.Count; $i++) {
            Write-Host $filtered[$i]
        }
        [int]$shown = [Math]::Min($Last, $filtered.Count)
        Write-Host "($($filtered.Count) total, showing last $shown)" -ForegroundColor DarkGray
    }

    'session' {
        if (-not (Test-Path -LiteralPath $logFile)) {
            Write-Host "Audit log not found" -ForegroundColor Yellow
            return
        }
        [string[]]$allLines = Get-Content -LiteralPath $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $Since) {
            $Since = (Get-Date).AddHours(-8)
        }
        $sinceStr = $Since.ToString("yyyy-MM-dd HH:mm:ss")
        [System.Collections.ArrayList]$filtered = @()
        foreach ($line in $allLines) {
            if ($line -match "^#") { continue }
            if ($line -match "^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})") {
                $entryDate = $Matches[1]
                if ($entryDate -lt $sinceStr) { continue }
                if ($FilterAction -ne "*" -and $line -notmatch $FilterAction) { continue }
                if ($FilterAgent -ne "*" -and $line -notmatch $FilterAgent) { continue }
                $null = $filtered.Add($line)
            }
        }
        if ($filtered.Count -eq 0) {
            $sinceFmt = $Since.ToString("yyyy-MM-dd HH:mm")
            Write-Host "No entries since $sinceFmt" -ForegroundColor Yellow
            return
        }

        $total = $filtered.Count
        [int]$allowCount = @($filtered | Where-Object { $_ -match ', ALLOW,' }).Count
        [int]$denyCount = @($filtered | Where-Object { $_ -match ', DENY,' }).Count
        [int]$errorCount = @($filtered | Where-Object { $_ -match ', ERROR,' }).Count
        [int]$writeCount = @($filtered | Where-Object { $_ -match ', (WRITE|EDIT),' }).Count
        [int]$askDenyCount = @($filtered | Where-Object { $_ -match ', ASK_DENY,' }).Count
        $sinceFmt = $Since.ToString("yyyy-MM-dd HH:mm")

        Write-Host "=== Session Audit: $sinceFmt -> now ===" -ForegroundColor Cyan
        Write-Host "  Total:       $total entries"
        Write-Host "  ALLOW:       $allowCount" -ForegroundColor Green
        Write-Host "  DENY:        $denyCount" -ForegroundColor Red
        Write-Host "  ASK_DENY:    $askDenyCount" -ForegroundColor Yellow
        Write-Host "  WRITE/EDIT:  $writeCount" -ForegroundColor Magenta
        Write-Host "  ERRORS:      $errorCount" -ForegroundColor Red
        [int]$recent = [Math]::Min(10, $total)
        Write-Host "--- Recent entries (last $recent) ---" -ForegroundColor DarkGray
        $filtered | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" }
    }
}
