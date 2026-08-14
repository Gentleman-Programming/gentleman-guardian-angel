#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Run global-setup + sync-vmk in sequence — full global sync in one shot.
.DESCRIPTION
  1. global-setup.ps1 -Force — AGENTS.md, prompts, scripts, MCPs, junctions, registry
  2. sync-vmk.ps1 -Force — opencode.json agent/permission/skills sections
  Compatible with PowerShell 7+. Auto-redirects from PS5 to pwsh if available.
.PARAMETER Json
  JSON output for agent consumption
.PARAMETER Quiet
  Minimal output
.EXAMPLE
  scripts\sync-all.ps1
  scripts\sync-all.bat
.EXAMPLE
  scripts\sync-all.ps1 -Json
#>
param([switch]$Json,[switch]$Quiet)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Cross-platform helpers ──────────────────────────────────────────────
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")

# ── PowerShell version check — graceful redirect ──────────────
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Find-Pwsh
    if ($pwsh) {
        Write-Warning "PowerShell $($PSVersionTable.PSVersion) no es compatible."
        Write-Warning "Redirigiendo a $($pwsh.Name)..."
        $params = @("-NoLogo", "-NoProfile", "-File", $PSCommandPath)
        if ($Json)  { $params += "-Json" }
        if ($Quiet) { $params += "-Quiet" }
        & $pwsh.Source $params
        exit $LASTEXITCODE
    }
    $installHint = if ($IsLinux -or $IsMacOS) {
        "  Instalá pwsh: https://docs.microsoft.com/powershell/scripting/install/installing-powershell"
    } else {
        "  winget install Microsoft.PowerShell"
    }
    Write-Error "╔══════════════════════════════════════════════════════╗"
    Write-Error "║  Requiere PowerShell 7+                              ║"
    Write-Error "║  Versión actual: $($PSVersionTable.PSVersion)                      ║"
    Write-Error "║  Usá sync-all.bat o instalá pwsh:                     ║"
    Write-Error $installHint
    Write-Error "╚══════════════════════════════════════════════════════╝"
    exit 1
}
if ($PSVersionTable.PSVersion -lt [Version]"7.6") {
    Write-Warning "PS $($PSVersionTable.PSVersion) puede tener limitaciones. "
    Write-Warning "Versión recomendada: 7.6+"
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$globalSetup = Join-Path (Join-Path $repoRoot "scripts") "global-setup.ps1"
$syncVmk    = Join-Path (Join-Path $repoRoot "scripts") "sync-vmk.ps1"
$results = [System.Collections.Generic.List[object]]::new()
$ok = $true

# ── Step 1: global-setup ──────────────────────────────────────────────────
if (Test-Path $globalSetup) {
    try {
        if ($Json) {
            & $globalSetup -Force -Json 2>&1
            $results.Add(@{step="global-setup"; status="OK"; detail="Completed"})
        } else {
            & $globalSetup -Force -Quiet:$Quiet
            $results.Add(@{step="global-setup"; status="OK"; detail="Completed"})
        }
    } catch {
        $results.Add(@{step="global-setup"; status="FAIL"; detail=$_.Exception.Message})
        $ok = $false
    }
} else {
    $results.Add(@{step="global-setup"; status="SKIP"; detail="Script not found"})
}

# ── Step 2: sync-vmk ──────────────────────────────────────────────────────
if (Test-Path $syncVmk) {
    try {
        & $syncVmk -Force -Quiet:$Quiet
        $results.Add(@{step="sync-vmk"; status="OK"; detail="Completed"})
    } catch {
        $results.Add(@{step="sync-vmk"; status="FAIL"; detail=$_.Exception.Message})
        $ok = $false
    }
} else {
    $results.Add(@{step="sync-vmk"; status="SKIP"; detail="Script not found"})
}

# ── Output ────────────────────────────────────────────────────────────────
if ($Json) {
    ConvertTo-Json @{
        timestamp = (Get-Date -Format "o")
        results   = $results
        success   = $ok
    } -Depth 3
} elseif (-not $Quiet) {
    Write-Output "`n═══════ SYNC-ALL COMPLETE ═══════"
    $results | ForEach-Object {
        $icon = switch ($_.status) { "OK" { "✅" } "SKIP" { "⏭️" } "FAIL" { "❌" } default { "❓" } }
        Write-Output "$icon $($_.step): $($_.detail)"
    }
    if (-not $ok) { Write-Output "⚠️  Some steps failed — check output above" }
}
exit $(if ($ok) { 0 } else { 1 })
