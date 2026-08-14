#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  2-way config drift detection between gentleman-agent-gh (canonical)
  and opencode-global (~/.config/opencode/).
  Part of P3b — Autonomous Integration Plan.
  NOTE: the mcp section is machine-specific (local servers, credentials,
  absolute paths) and is intentionally excluded from comparison and -Fix.
#>
param(
  [switch]$Json,
  [switch]$Quiet,
  [switch]$Fix     # Sync vmk config from canonical (not global)
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")

$gentlemanRoot = Get-GentlemanRoot

# ── Config paths ─────────────────────────────────────────────────────────
$canonicalPath = "$gentlemanRoot/opencode.json"
$globalPath    = Join-Path (Get-GlobalConfigDir) "opencode.json"
# Fallback: setups that sync via sync-global.ps1 store the global config as opencode.jsonc
if (-not (Test-Path -LiteralPath $globalPath)) {
  $globalJsonc = Join-Path (Get-GlobalConfigDir) "opencode.jsonc"
  if (Test-Path -LiteralPath $globalJsonc) { $globalPath = $globalJsonc }
}

$results = [System.Collections.Generic.List[object]]::new()

# ── Helper: hash a JSON section ──────────────────────────────────────────
function Get-SectionHash {
  param([string]$Path, [string[]]$SectionKeys)
  if (-not (Test-Path $Path)) { return @{path = $Path; sections = @{}; error = "File not found"} }
  try {
    $parsed = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $hashes = @{}
    foreach ($key in $SectionKeys) {
      # StrictMode-safe property access: missing property => null section
      $prop = $parsed.PSObject.Properties[$key]
      $section = if ($null -ne $prop) { $prop.Value } else { $null }
      if ($null -ne $section) {
        $json = ($section | ConvertTo-Json -Depth 10 -Compress)
        $hashes[$key] = [System.BitConverter]::ToString(
          [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($json)
          )
        ).Replace("-", "").Substring(0, 12).ToLower()
      } else {
        $hashes[$key] = $null
      }
    }
    return @{path = $Path; sections = $hashes; error = $null}
  } catch {
    return @{path = $Path; sections = @{}; error = $_.Exception.Message}
  }
}

# mcp is machine-specific (local MCP servers, credentials, absolute paths)
# and is deliberately NOT compared or synced — -Fix never touches it.
$sectionKeys = @("agent", "skills", "permission")
$canonical = Get-SectionHash -Path $canonicalPath -SectionKeys $sectionKeys
$global    = Get-SectionHash -Path $globalPath -SectionKeys $sectionKeys

# ── Compare ──────────────────────────────────────────────────────────────
$totalDrift = 0
foreach ($key in $sectionKeys) {
  $cHash = $canonical.sections[$key]
  $gHash = $global.sections[$key]

  $c_g = ($cHash -eq $gHash) -or ($null -eq $cHash -and $null -eq $gHash)

  $drift = @()
  if (-not $c_g) { $drift += "canonical≠global"; $totalDrift++ }

  $status = if ($drift.Count -eq 0) { "OK" } else { "DRIFT" }
  $results.Add(@{
    section   = $key
    status    = $status
    canonical = $cHash
    global    = $gHash
    drift     = $drift
  })
}

# ── Fix mode: sync global from canonical ─────────────────────────────────
if ($Fix -and $totalDrift -gt 0) {
  if (-not $Quiet) { Write-Output "[fix] Syncing global config from canonical..." }
  $canonicalContent = Get-Content -LiteralPath $canonicalPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $globalContent = Get-Content -LiteralPath $globalPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $globalContent.default_agent = "gentleman-vMK"
  $globalContent.agent = $canonicalContent.agent
  $globalContent.permission = $canonicalContent.permission
  $globalContent.skills = $canonicalContent.skills
  $globalContent | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $globalPath -Encoding UTF8
  if (-not $Quiet) { Write-Output "[fix] global config updated → $globalPath" }
}

# ── Output ──────────────────────────────────────────────────────────────
if ($Json -or $Quiet) {
  ConvertTo-Json @{
    timestamp = (Get-Date -Format "o")
    version   = "1.0.0"
    excludedSections = @("mcp")
    files     = @{
      canonical = $canonicalPath
      global    = $globalPath
    }
    sections  = $results
    totalDrift = $totalDrift
    exitCode  = [Math]::Min($totalDrift, 2)
  } -Depth 4
} else {
  Write-Output "`n═══════════════════════════════════════════"
  Write-Output "  CONFIG DRIFT CHECK — 2-way Comparison"
  Write-Output "═══════════════════════════════════════════"
  $results | ForEach-Object {
    $icon = if ($_.status -eq "OK") { "✅" } else { "🔴" }
    Write-Output "$icon $($_.section): $($_.status)"
    if ($_.drift.Count -gt 0) {
      $_.drift | ForEach-Object { Write-Output "   └─ $_" }
    }
    Write-Output "   canonical: $($_.canonical)"
    Write-Output "   global:    $($_.global)"
  }
  Write-Output "───────────────────────────────────────────"
  Write-Output "ℹ️  mcp: skipped — machine-specific section (not compared/synced)"
  Write-Output "Total drifts: $totalDrift"
}
exit [Math]::Min($totalDrift, 2)
