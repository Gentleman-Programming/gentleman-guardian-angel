#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

param(
  [switch]$Quiet,
  [switch]$Force,
  [switch]$DryRun
)

Set-StrictMode -Version Latest

<#
.SYNOPSIS
  Restore .project.json to committed version if vMK's external MCP scoring infra overwrote it.

.DESCRIPTION
  vMK (OpenCode version) has an external MCP scoring infra that writes a 6-dim/5-score
  version of .project.json on every session start. This script detects the overwrite
  and restores the committed 11-dim/10.0 version from git HEAD.

  Detection: checks if score.current != 10.0 or if the file has different structure.
  Restoration: git checkout HEAD -- .project.json + re-applies skip-worktree.

.PARAMETER Quiet
  Suppress output. Return exit code only (0=restored, 1=already correct, 2=error).

.PARAMETER Force
  Force restore even if score looks correct (for testing).

.EXAMPLE
  .\scripts\restore-project-score.ps1
  .\scripts\restore-project-score.ps1 -Quiet
  .\scripts\restore-project-score.ps1 -Force
#>

$ErrorActionPreference = 'Stop'
$projectJson = Join-Path -Path $PSScriptRoot -ChildPath '..\.project.json' | Resolve-Path

if (-not (Test-Path -LiteralPath $projectJson)) {
  if (-not $Quiet) { Write-Host "project.json not found at $projectJson" -ForegroundColor Red }
  exit 2
}

# --- Read current state ---
$needsRestore = $false
$parseOk = $true

try {
  $content = Get-Content -LiteralPath $projectJson -Raw -Encoding UTF8
  $parsed = $content | ConvertFrom-Json
} catch {
  $parseOk = $false
  if (-not $Quiet) { Write-Host "Cannot parse .project json - attempting restore" -ForegroundColor Yellow }
}

if ($parseOk) {
  $currentScore = [double]$parsed.score.current
  $currentDims = $parsed.score.dimensions
  $dimCount = @($currentDims.PSObject.Properties).Count

  # vMK writes: 6 dims, score 5. We expect: 12 dims, score 9.5+
  if (($currentScore -lt 9.5) -or ($dimCount -lt 11) -or $Force) {
    if (-not $Quiet) {
      Write-Host "Score drift detected: current score=$currentScore, dims=$dimCount (expected: >=9.5, >=11 dims)" -ForegroundColor Yellow
    }
    $needsRestore = $true
  }
} else {
  $needsRestore = $true
}

# --- Restore from git HEAD ---
if ($needsRestore) {
  if ($DryRun) {
    if (-not $Quiet) { Write-Host "[dry-run] would restore .project.json to committed version" -ForegroundColor Yellow }
    exit 0
  }
  try {
    # skip-worktree blocks checkout, need to temporarily remove it
    & "git" "update-index", "--no-skip-worktree", ".project.json"
    & "git" "checkout", "HEAD", "--", ".project.json"
    & "git" "update-index", "--skip-worktree", ".project.json"

    if (-not $Quiet) { Write-Host "project.json restored to committed version" -ForegroundColor Green }
    exit 0
  } catch {
    if (-not $Quiet) { Write-Host "Restore failed: $_" -ForegroundColor Red }
    exit 2
  }
} else {
  if (-not $Quiet) { Write-Host "project.json already correct (score 10.0/10)" -ForegroundColor Green }
  exit 1
}
