#requires -Version 7
<#
.SYNOPSIS
  Unified pre-session health check for gentleman-vMK and opencode-ai ecosystem.
  Checks: skills junctions (vmk + global), prompts junction.
  Part of P1 — Autonomous Integration Plan.
.DESCRIPTION
  Validates environment health before starting a session:
  - Skills junctions (canonical + global config)
  - Prompts junction
  - Git status
  - Skill drift detection
  Junction checks bypass the 1h cache — always fresh, so degraded junctions
  surface immediately (WARN → exit 1, FAIL → exit 2).
.PARAMETER AutoRepair
  Auto-fix broken junctions instead of just reporting.
.PARAMETER Json
  Output results as JSON for agent consumption.
.PARAMETER Quiet
  Exit code only, minimal output (0=OK, 1=warnings, 2=failures).
.PARAMETER DryRun
  Report which junctions would be repaired without applying changes.
.PARAMETER Force
  Repair junctions even without -AutoRepair (same effect as -AutoRepair).
.EXAMPLE
  .\scripts\health-check.ps1              # interactive health check
  .\scripts\health-check.ps1 -Json        # JSON for agent
  .\scripts\health-check.ps1 -AutoRepair  # fix broken junctions
  .\scripts\health-check.ps1 -Quiet       # exit code only
#>
param(
  [switch]$AutoRepair,      # Auto-fix broken junctions
  [switch]$Json,            # JSON output for agent consumption
  [switch]$Quiet,           # Exit code only, minimal output
  [switch]$DryRun,
  [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")

$gentlemanRoot = Get-GentlemanRoot

$exitCode = 0
$checks = [System.Collections.Generic.List[object]]::new()

# ── Helper: junction check ───────────────────────────────────────────────
function Test-Junction {
  param([string]$Path, [string]$ExpectedTarget, [string]$Label)
  $result = @{check = $Label; status = "OK"; detail = ""}
  if (Test-Path $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LinkType -notin @("Junction", "SymbolicLink")) {
      $result.status = "WARN"
      $result.detail = "Exists but not a junction (real file/dir)"
      return $result
    }
    if (-not (Test-Path $item.Target)) {
      $result.status = "FAIL"
      $result.detail = "Target missing: $($item.Target)"
      return $result
    }
    if ($item.Target -ne (Resolve-Path $ExpectedTarget).Path) {
      $result.status = "WARN"
      $result.detail = "Target mismatch: $($item.Target) → expected $ExpectedTarget"
      return $result
    }
    $result.detail = "$($item.Target) ✅"
  } else {
    $result.status = "FAIL"
    $result.detail = "Missing"
  }
  return $result
}

function Set-Junction {
  [CmdletBinding(SupportsShouldProcess)]
  param([string]$Path, [string]$Target, [string]$Label)
  # ponytail: validate LinkType before destructive Remove-Item — avoid nuking real dirs
  if (Test-Path $Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -in @('Junction', 'SymbolicLink')) {
      if ($PSCmdlet.ShouldProcess($Path, 'Repair junction')) {
        try {
          Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction Stop
        } catch {
          Write-Warning "[repair] failed to remove $($Path): $($_.Exception.Message)"
        }
      }
    } elseif ($item -and $item.LinkType) {
      Write-Warning "[repair] skipping $($Path): existing LinkType $($item.LinkType) is not Junction"
      if (-not $Quiet) { Write-Output "[skipped] $Label (not a junction)" }
      return
    }
    # else: real dir/file — refuse remove to be safe
    elseif ($item) {
      Write-Warning "[repair] refusing to remove $($Path): real entry, not a junction"
      if (-not $Quiet) { Write-Output "[refused] $Label (real entry)" }
      return
    }
  }
  if ($PSCmdlet.ShouldProcess($Path, "Create junction to $Target")) {
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    New-CrossPlatLink -Path $Path -Target $Target
    if (-not $Quiet) { Write-Output "[repair] $Label → $Target" }
  }
}

# ── Wrapper: Test-Junction → Repair → Re-Test → Collect ──────────────────
function Repair-Junction {
  param([string]$Path, [string]$ExpectedTarget, [string]$Target, [string]$Label, [switch]$AutoRepair, [switch]$DryRun)
  $check = Test-Junction -Path $Path -ExpectedTarget $ExpectedTarget -Label $Label
  if ($check.status -ne "OK") {
    if ($DryRun) {
      if (-not $Quiet) { Write-Output "[dry-run] would repair $Label" }
    } elseif ($AutoRepair -or $Force) {
      Set-Junction -Path $Path -Target $Target -Label $Label
      $check = Test-Junction -Path $Path -ExpectedTarget $ExpectedTarget -Label $Label
    }
  }
  $script:checks.Add($check)
  # Prompts junction degradation escalates: FAIL → exit 2, WARN → exit 1
  if ($check.status -eq "FAIL") { $script:exitCode = 2 }
  elseif ($check.status -eq "WARN") { if ($script:exitCode -lt 1) { $script:exitCode = 1 } }
}

# ── Check 1: vmk skills junction (hybrid model) ─────────────────────────
# Model: global skills dir is a REAL dir containing one junction per repo
# skill, plus deliberate real dirs (_shared + global-only skills like sdd-*).
# Legacy check expected the WHOLE dir to be a junction — obsolete (false
# positives against the hybrid model).
$globalSkillsDir = Join-Path (Get-GlobalConfigDir) "skills"
$repoSkillsDir = Join-Path $gentlemanRoot ".agents/skills"
# Repo skills deliberately NOT junctioned (real dir in global, extra content)
$allowlistReal = @('_shared')

if (Test-Path $globalSkillsDir) {
  $globalEntries = @(Get-ChildItem -LiteralPath $globalSkillsDir -Force -Directory)
  $globalByName = @{}
  foreach ($e in $globalEntries) {
    $globalByName[$e.Name] = Get-Item $e.FullName -Force
  }
  $repoSkills = @(if (Test-Path $repoSkillsDir) { Get-ChildItem -LiteralPath $repoSkillsDir -Directory | ForEach-Object Name } else { @() })

  # Junction coverage: every repo skill (except allowlist) must be a live junction
  $missingJunction = @()
  $deadJunction = @()
  foreach ($s in $repoSkills) {
    if ($s -in $allowlistReal) { continue }
    if (-not $globalByName.ContainsKey($s)) {
      $missingJunction += $s
      continue
    }
    $item = $globalByName[$s]
    if ($item.LinkType -notin @('Junction', 'SymbolicLink')) {
      $missingJunction += $s   # real dir where junction expected
    } elseif (-not (Test-Path $item.Target)) {
      $deadJunction += $s
    }
  }

  if ($missingJunction.Count -eq 0 -and $deadJunction.Count -eq 0) {
    $checks.Add(@{check = "vmk-skills-junction"; status = "OK"; detail = "Hybrid model OK: $($repoSkills.Count) repo skills covered, $($globalEntries.Count) global entries"})
  } else {
    $problems = @()
    if ($missingJunction.Count) { $problems += "missing junction: $($missingJunction -join ', ')" }
    if ($deadJunction.Count) { $problems += "dead target: $($deadJunction -join ', ')" }
    $checks.Add(@{check = "vmk-skills-junction"; status = "WARN"; detail = $problems -join '; '})
    if ($exitCode -lt 1) { $exitCode = 1 }
  }
} else {
  $checks.Add(@{check = "vmk-skills-junction"; status = "WARN"; detail = "Global skills dir not found"})
  if ($exitCode -lt 1) { $exitCode = 1 }
}

# ── Check 3: global skills junction (hybrid model) ───────────────────────
# Deliberate real dirs in global: _shared + skills that do NOT exist in repo.
if (Test-Path $globalSkillsDir) {
  $repoSkillsSet = @(if (Test-Path $repoSkillsDir) { Get-ChildItem -LiteralPath $repoSkillsDir -Directory | ForEach-Object Name } else { @() })
  $unexpectedReal = @()
  foreach ($e in @(Get-ChildItem -LiteralPath $globalSkillsDir -Force -Directory)) {
    $item = Get-Item $e.FullName -Force
    if ($item.LinkType -notin @('Junction', 'SymbolicLink')) {
      # Real dir: allowed only if deliberately real or not a repo skill
      if ($e.Name -ne '_shared' -and $e.Name -in $repoSkillsSet) {
        $unexpectedReal += $e.Name
      }
    }
  }
  if ($unexpectedReal.Count -eq 0) {
    $checks.Add(@{check = "global-skills-junction"; status = "OK"; detail = "Hybrid OK: real dirs are deliberate only"})
  } else {
    $checks.Add(@{check = "global-skills-junction"; status = "WARN"; detail = "Repo skill as real dir (should be junction): $($unexpectedReal -join ', ')"})
    if ($exitCode -lt 1) { $exitCode = 1 }
  }
}

# ── Check 2: vmk prompts junction ───────────────────────────────────────
Repair-Junction -Path (Join-Path (Join-Path (Get-GlobalConfigDir) "prompts") "sdd") `
  -ExpectedTarget "$gentlemanRoot/prompts/sdd" `
  -Target "$gentlemanRoot/prompts/sdd" `
  -Label "vmk-prompts-junction" `
  -AutoRepair:$AutoRepair -DryRun:$DryRun -Force:$Force



# ── Write cache ────────────────────────────────────────────────────────
# ponytail: unified cache (read is bypassed — junction checks always fresh)
$cacheScript = Join-Path $PSScriptRoot "lib/cache.ps1"
$healthResult = @{
  timestamp = (Get-Date -Format "o")
  version   = "1.0.0"
  checks    = $checks
  exitCode  = $exitCode
}
& $cacheScript -Action set -Key "health-check" -Data $healthResult

# ── Output ──────────────────────────────────────────────────────────────
if ($Json) {
  $healthResult | ConvertTo-Json -Depth 3
} elseif ($Quiet) {
  $healthResult | ConvertTo-Json -Depth 3
} else {
  Write-Output "`n═══════════════════════════════════════════"
  Write-Output "  HEALTH CHECK — gentleman-vMK"
  Write-Output "═══════════════════════════════════════════"
  $checks | ForEach-Object {
    $icon = switch ($_.status) { "OK" { "✅" } "WARN" { "🟡" } "FAIL" { "🔴" } default { "❓" } }
    Write-Output "$icon $($_.check): $($_.detail)"
  }
  Write-Output "───────────────────────────────────────────"
  $exitLabel = switch ($exitCode) { 0 { "✅ ALL OK" } 1 { "🟡 WARNINGS" } 2 { "🔴 CRITICAL" } }
  Write-Output "Exit: $exitCode — $exitLabel"
}
exit $exitCode
