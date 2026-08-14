#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

<#
.SYNOPSIS
  Capture error/warning snapshots from quality gates and scripts.
  Tracks error trends over time (commits, dates, sources).

.DESCRIPTION
  Three modes:
  - Direct capture: `-Source "quality-gate" -Passed 5 -Failed 1`
  - Error list:    `-Source "test" -Errors @(@{Check="x";Message="y";Severity="error"})`
  - Snapshot:      `-Snapshot` creates a timestamped snapshot in docs/metricas/errors/
  - Report:        `-Report` prints error stats over time

.PARAMETER Source
  Where the error came from: quality-gate, script, ci, benchmark

.PARAMETER Passed
  Number of passed checks (for quality gate)

.PARAMETER Failed
  Number of failed checks (for quality gate)

.PARAMETER Blocked
  Whether commit was blocked (yes/no)

.PARAMETER Errors
  Array of error objects: @(@{Check="..."; Message="..."; Severity="error|warn"})

.PARAMETER Snapshot
  Save current error state as a snapshot

.PARAMETER Report
  Print error trend report

.PARAMETER Json
  Output as JSON

.EXAMPLE
  .\scripts\capture-errors.ps1 -Source "quality-gate" -Passed 5 -Failed 0
  .\scripts\capture-errors.ps1 -Snapshot
  .\scripts\capture-errors.ps1 -Report
#>

param(
  [string]$Source = "",
  [int]$Passed = 0,
  [int]$Failed = 0,
  [string]$Blocked = "",
  [array]$Errors = @(),
  [switch]$Snapshot,
  [switch]$Report,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$errorDir = Join-Path -Path $repoRoot -ChildPath "docs\metricas\errors"
$latestPath = Join-Path $errorDir "LATEST_error.json"

# --- Get commit info ---
$commit = try { $c = (git rev-parse --short HEAD 2>$null); if ($c) { $c.Trim() } else { "unknown" } } catch { "unknown" }
$branch = try { $b = (git rev-parse --abbrev-ref HEAD 2>$null); if ($b) { $b.Trim() } else { "unknown" } } catch { "unknown" }

# --- Build error entry ---
$entry = [PSCustomObject]@{
  version = "1.0"
  timestamp = (Get-Date -Format "o")
  commit = $commit
  branch = $branch
  source = $Source
  passed = $Passed
  failed = $Failed
  blocked = $Blocked
  errors = $Errors
  totalErrors = @($Errors | Where-Object { $_.Severity -eq "error" }).Count
  totalWarnings = @($Errors | Where-Object { $_.Severity -eq "warn" }).Count
}

# --- Snapshot mode ---
if ($Snapshot) {
  if (-not (Test-Path $errorDir)) { New-Item -ItemType Directory -Path $errorDir -Force | Out-Null }
  $filename = "{0:yyyyMMdd-HHmmss}_error.json" -f (Get-Date)
  $filePath = Join-Path $errorDir $filename
  $entry | ConvertTo-Json -Depth 4 | Set-Content -Path $filePath -Encoding UTF8
  # Copy as LATEST
  $entry | ConvertTo-Json -Depth 4 | Set-Content -Path $latestPath -Encoding UTF8
  if (-not $Json) { Write-Output ("Error snapshot saved: {0}" -f $filePath) }
  exit 0
}

# --- Write current entry (not snapshot) ---
if (-not $Report) {
  if (-not (Test-Path $errorDir)) { New-Item -ItemType Directory -Path $errorDir -Force | Out-Null }
  $entry | ConvertTo-Json -Depth 4 | Set-Content -Path $latestPath -Encoding UTF8
  if (-not $Json) { Write-Output ("Error state updated: {0}" -f $latestPath) }
  exit 0
}

# --- Report mode ---
if ($Report) {
  $files = @(Get-ChildItem $errorDir -Filter "*_error.json" -ErrorAction SilentlyContinue)
  if ($files.Count -eq 0) { Write-Output "No error snapshots found."; exit 0 }

  $allEntries = $files | Sort-Object LastWriteTime | ForEach-Object {
    try { Get-Content $_.FullName -Raw | ConvertFrom-Json } catch { $null }
  } | Where-Object { $_ }

  if ($allEntries.Count -eq 0) { Write-Output "No valid error snapshots found."; exit 0 }

  $totalErrors = ($allEntries | ForEach-Object { $_.totalErrors } | Measure-Object -Sum).Sum
  $totalWarnings = ($allEntries | ForEach-Object { $_.totalWarnings } | Measure-Object -Sum).Sum
  $blockedCount = @($allEntries | Where-Object { $_.blocked -eq "yes" }).Count
  $firstDate = ($allEntries | Select-Object -First 1).timestamp
  $lastDate = ($allEntries | Select-Object -Last 1).timestamp

  $output = @{
    source = "error-trends"
    timestamp = (Get-Date -Format "o")
    snapshotsCount = $allEntries.Count
    firstSnapshot = $firstDate
    lastSnapshot = $lastDate
    totalErrors = $totalErrors
    totalWarnings = $totalWarnings
    blockedCommits = $blockedCount
    entries = $allEntries | Select-Object timestamp, commit, source, passed, failed, totalErrors, blocked, @{N="branch";E={$_.branch}}
  }

  if ($Json) {
    Write-Output ($output | ConvertTo-Json -Depth 4)
  } else {
    Write-Output ("=== Error Trend Report ===")
    Write-Output ("  Snapshots: {0}" -f $allEntries.Count)
    Write-Output ("  Period: {0} → {1}" -f $firstDate, $lastDate)
    Write-Output ("  Total errors across all snapshots: {0}" -f $totalErrors)
    Write-Output ("  Total warnings across all snapshots: {0}" -f $totalWarnings)
    Write-Output ("  Blocked commits: {0}" -f $blockedCount)
    Write-Output ("")
    Write-Output ("  Recent entries:")
    $allEntries | Select-Object -Last 5 | ForEach-Object {
      Write-Output ("    [{0}] {1} | source={2} | passed={3} failed={4} errors={5}" -f $_.timestamp.Substring(0,19), $_.commit, $_.source, $_.passed, $_.failed, $_.totalErrors)
    }
  }
  exit 0
}
