#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Leave a repository clean: untracked files, backup/temp junk, stale junctions, and optional git gc.
  DRY-RUN BY DEFAULT: with no -Yes, reports what would be removed without touching anything.

.DESCRIPTION
  Scans a git repo for:
    1. Untracked files (git status --porcelain, ??) and ignored junk candidates
    2. Temp/backup artifacts (*.bak, *.tmp, *.orig, *~, .bak.*)
    3. Dangling junctions in .agents/skills (broken links)
    4. Optional git gc --prune=now when -Gc is passed
  Deletes only with -Yes. Everything else is reported. Never touches committed or staged files.

.PARAMETER RepoRoot
  Repository to clean. Default: current directory (walks up to the git root).

.PARAMETER DryRun
  Report only. This is the default when -Yes is absent.

.PARAMETER Force
  Apply deletions. Alias: -Yes (kept for backward compatibility).
  By default removes ONLY junk artifacts + dangling junctions.
  Untracked files are NEVER removed unless -RemoveUntracked is also passed.

.PARAMETER RemoveUntracked
  Also remove untracked files (the risky category - may hold WIP/config/secrets).
  Requires -Force. Explicit opt-in by design.

.PARAMETER Gc
  Also run git gc --prune=now after cleanup.

.PARAMETER Quiet
  JSON-only summary.

.EXAMPLE
  & scripts/clean-repo.ps1                # dry-run report
  & scripts/clean-repo.ps1 -Force         # remove junk + dangling junctions only
  & scripts/clean-repo.ps1 -Force -RemoveUntracked   # + untracked (review dry-run first!)
  & scripts/clean-repo.ps1 -Force -Gc     # + git gc
#>
param(
  [string]$RepoRoot = (Get-Location).Path,
  [switch]$DryRun,
  [Alias('Yes')]
  [switch]$Force,
  [switch]$RemoveUntracked,
  [switch]$Gc,
  [switch]$Quiet
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apply = $Force -and (-not $DryRun)

# ---- resolve git root ----
$gitRoot = $null
$resolved = Resolve-Path -LiteralPath $RepoRoot -ErrorAction SilentlyContinue
if (-not $resolved) { if ($Quiet) { Write-Output (@{ ok = $false; error = "Path not found: $RepoRoot" } | ConvertTo-Json -Compress) } else { Write-Error "Path not found: $RepoRoot" }; exit 2 }
$dir = $resolved.Path
while ($dir) {
  if (Test-Path -LiteralPath (Join-Path $dir ".git")) { $gitRoot = $dir; break }
  $parent = Split-Path -Parent $dir
  if (-not $parent -or $parent -eq $dir) { break }
  $dir = $parent
}
if (-not $gitRoot) {
  if ($Quiet) { Write-Output (@{ ok = $false; error = "Not inside a git repository: $RepoRoot" } | ConvertTo-Json -Compress) }
  else { Write-Error "Not inside a git repository: $RepoRoot" }
  exit 2
}

$untracked = @(); $junk = @(); $dangling = @()
$gitBin = "git"

# ---- 1. untracked + ignored candidates ----
$porcelain = & $gitBin -C $gitRoot status --porcelain=v1 2>$null
foreach ($line in $porcelain) {
  if ($line.Length -ge 3 -and $line.Substring(0, 2) -eq '??') {
    $untracked += $line.Substring(3).Trim('"')
  }
}
# junk patterns anywhere in tree (tracked files are never matched by -File + Filter outside git control)
$junkPatterns = @('*.bak', '*.tmp', '*.orig', '*~', '*.bak.*', '*.swp')
foreach ($p in $junkPatterns) {
  Get-ChildItem -LiteralPath $gitRoot -Recurse -File -Filter $p -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\node_modules\\|\\\.git\\' } |
    ForEach-Object { $junk += $_.FullName }
}
$junk = @($junk | Select-Object -Unique)

# ---- 3. dangling junctions in .agents/skills ----
$skillsDir = Join-Path $gitRoot ".agents\skills"
if (Test-Path -LiteralPath $skillsDir) {
  Get-ChildItem -LiteralPath $skillsDir -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.LinkType -in @('Junction', 'SymbolicLink') } |
    ForEach-Object {
      if (-not (Test-Path -LiteralPath $_.FullName -ErrorAction SilentlyContinue)) { $dangling += $_.FullName }
    }
}

# ---- apply (must run BEFORE any quiet exit) ----
if ($apply) {
  if ($RemoveUntracked) {
    foreach ($f in $untracked) {
      $full = Join-Path $gitRoot $f
      if (Test-Path -LiteralPath $full) {
        try { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop }
        catch { Write-Warning "clean-repo: could not remove untracked '$full': $($_.Exception.Message)" }
      }
    }
  }
  foreach ($f in $junk) {
    try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop }
    catch { Write-Warning "clean-repo: could not remove junk '$f': $($_.Exception.Message)" }
  }
  foreach ($d in $dangling) {
    try { Remove-Item -LiteralPath $d -Force -ErrorAction Stop }
    catch { Write-Warning "clean-repo: could not remove dangling junction '$d': $($_.Exception.Message)" }
  }
  if ($Gc) { & $gitBin -C $gitRoot gc --prune=now 2>$null }
}

# ---- report ----
if ($Quiet) {
  $result = @{
    ok = $true
    mode = $(if ($apply) { 'apply' } else { 'dry-run' })
    repo = $gitRoot
    untracked = @($untracked)
    junk = @($junk)
    dangling_junctions = @($dangling)
    would_gc = [bool]$Gc
  }
  Write-Output ($result | ConvertTo-Json -Compress -Depth 3)
  exit 0
}

Write-Output "== clean-repo | mode: $(if ($apply) { 'APPLY' } else { 'DRY-RUN' }) | repo: $gitRoot =="
Write-Output ""
Write-Output ("Untracked files      : {0}" -f $untracked.Count)
$untracked | ForEach-Object { Write-Output "    $_" }
Write-Output ""
Write-Output ("Junk artifacts        : {0}" -f $junk.Count)
$junk | ForEach-Object { Write-Output "    $_" }
Write-Output ""
Write-Output ("Dangling junctions    : {0}" -f $dangling.Count)
$dangling | ForEach-Object { Write-Output "    $_" }

if ($apply) {
  Write-Output ""
  $removed = @($junk + $dangling).Count
  $untrackedNote = ''
  if ($RemoveUntracked) { $removed += $untracked.Count; $untrackedNote = " + $($untracked.Count) untracked" }
  Write-Output "Applied: removed $($junk.Count) junk + $($dangling.Count) dangling$untrackedNote."
} else {
  Write-Output ""
  $extra = ''
  if (-not $RemoveUntracked) { $extra = " (untracked NOT removed unless -RemoveUntracked)" }
  Write-Output "Dry-run: nothing removed. Re-run with -Yes to apply$($extra)$($(if ($Gc) { ' (add -Gc for git gc)' } else { '' }))."
}
