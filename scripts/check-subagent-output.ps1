#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Post-delegation empty-output detector for subagent delegations.

.DESCRIPTION
  Run after every subagent delegation to verify the subagent actually produced
  changes. Detects the "subagent completed but with no output" silent failure
  mode documented in mejora-log.md:571 and RUNBOOK.md:26.

  Root causes it catches:
    (a) Free-tier model hit output truncation
    (b) stdout truncated by verbose-verify
    (c) model fell back to general due to mode:primary not being delegable

.PARAMETER BaseRef
  Git reference to diff against (default: HEAD).

.PARAMETER RepoRoot
  Repository root. Default: parent of script dir. Allows isolated testing.

.PARAMETER ExpectedFiles
  Optional list of filenames that SHOULD appear in the diff.
  If provided and any are missing, exits 1 (partial completion).

.PARAMETER Quiet
  JSON summary on stdout.

.EXAMPLE
  scripts\check-subagent-output.ps1                           # check changes since HEAD
  scripts\check-subagent-output.ps1 -ExpectedFiles "src/utils.ts","src/types.ts"
  scripts\check-subagent-output.ps1 -BaseRef HEAD~1 -Quiet
#>
param(
    [string]$BaseRef    = "HEAD",
    [string]$RepoRoot   = $(Split-Path -Parent $PSScriptRoot),
    [string[]]$ExpectedFiles = @(),
    [string]$AgentOutput = "",   # C4d: subagent text output for 4-field contract validation
    [switch]$Quiet
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# C4d: Validate 4-field return contract (Decision Taken | Files Changed | Key Findings | Nuance)
function Validate-AgentReturnContract {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
    param([string]$Output, [string]$AgentName = "unknown")
    $requiredHeaders = @('## Decision Taken', '## Files Changed', '## Key Findings', '## Nuance')
    $missing = @()
    $empty   = @()
    # 1. Detect missing headers
    foreach ($h in $requiredHeaders) {
        if ($Output -notmatch [regex]::Escape($h)) { $missing += $h }
    }
    # 2. Parse sections by line and check for non-whitespace content
    if ($missing.Count -eq 0) {
        $lines  = $Output -split '\r?\n'
        $current = ""
        $sections = @{}
        foreach ($line in $lines) {
            if ($line -match '^## ') {
                $current = $line
                $sections[$current] = @()
            } elseif ($current) {
                $sections[$current] += $line
            }
        }
        foreach ($h in $requiredHeaders) {
            $content = $sections[$h]
            if ($content) {
                $hasContent = @($content | Where-Object { $_.Trim() })
                if ($hasContent.Count -eq 0) { $empty += $h }
            } else {
                $empty += $h
            }
        }
    }
    return [PSCustomObject]@{
        valid   = ($missing.Count -eq 0 -and $empty.Count -eq 0)
        agent   = $AgentName
        missing = $missing
        empty   = $empty
    }
}

if (-not (Test-Path (Join-Path $RepoRoot ".git"))) {
    if ($Quiet) { @{status="FAIL";reason="not-a-git-repo"} | ConvertTo-Json -Compress }
    else { Write-Error "Not a git repo: $RepoRoot" }
    exit 1
}

# --- Git changes: committed + staged + untracked ---
# 1. Committed changes (BaseRef..HEAD range) — detect subagent commits
$committed = @()
try {
    $committed = git -C $RepoRoot diff --name-only "$BaseRef..HEAD" 2>&1 |
        Where-Object { $_ -and $_ -notmatch "^warning:" -and $_ -notmatch "^\s*$" }
    } catch { Write-Debug "check-subagent-output: committed git diff failed (non-fatal) — $_" }

# 2. Working-tree changes incl. untracked (via status porcelain)
$statusRaw = @()
try {
    $statusRaw = git -C $RepoRoot status --porcelain 2>&1
    } catch { Write-Debug "check-subagent-output: git status failed (non-fatal) — $_" }
$wcFiles = @($statusRaw | Where-Object { $_ -and $_ -notmatch "^warning:" } |
    ForEach-Object {
        $path = ($_ -replace '^\?\?\s+', '' -replace '^[MADRCU?!]+\s+', '').Trim()
        if ($path) { $path }
    })

# Merge: committed + working-tree, unique
$files = @($committed + $wcFiles | Sort-Object -Unique)

# --- Empty diff = SILENT FAILURE ---
if ($files.Count -eq 0) {
    if ($Quiet) {
        @{status="FAIL";reason="empty-output";files=@()} | ConvertTo-Json -Compress
    } else {
        Write-Output "X  SILENT FAILURE: subagent produced NO file changes (empty output)"
        Write-Output "   BaseRef: $BaseRef"
        Write-Output "   Root cause: (a) model output truncation, (b) stdout truncated by verbose-verify, (c) fallback to general due to mode:primary"
        Write-Output "   See: mejora-log.md:571, RUNBOOK.md:26"
    }
    exit 1
}

# --- Optional: verify expected files ---
$missing = @()
if ($ExpectedFiles) {
    $missing = $ExpectedFiles | Where-Object { $files -notcontains $_ }
}

# --- C4d: Contract validation ---
$contractValid = $true
$contractDetail = ""
if ($AgentOutput) {
    $cr = Validate-AgentReturnContract -Output $AgentOutput
    $contractValid = $cr.valid
    if (-not $contractValid) {
        $contractDetail = "Contract violation: missing=[" + ($cr.missing -join ', ') + "] empty=[" + ($cr.empty -join ', ') + "]"
        if (-not $Quiet) { Write-Warning "X  $contractDetail" }
    }
}

# --- Output ---
if ($Quiet) {
    @{
        status = if ($missing) { "WARN" } else { "OK" }
        files = $files
        missing_expected = $missing
        contract_valid = $contractValid
        contract_detail = $contractDetail
    } | ConvertTo-Json -Compress
} else {
    Write-Output ("OK  " + $files.Count + " file(s) changed since " + $BaseRef + ":")
    $files | ForEach-Object { Write-Output "   $_" }
    if ($missing) {
        Write-Output "X  Expected files NOT found in diff:"
        $missing | ForEach-Object { Write-Output "   $_" }
        exit 1
    }
}
exit 0
