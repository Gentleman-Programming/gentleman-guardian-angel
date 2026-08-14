#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  One-shot health + tests + drift — semáforo verde/rojo del repo.

  Corrida completa:
    1. health-check.ps1      — junctions, skills, prompts
    2. run-tests.ps1 -Quiet  — todos los tests Pester
    3. check-skill-drift.ps1 — skills en sync
    4. check-config-drift.ps1— config en sync
    5. git status --short    — working tree limpio?

.PARAMETER Json    JSON output for agent consumption
.PARAMETER Quiet   Minimal output, exit code only
.PARAMETER NoTests Skip Pester tests (más rápido para check rápido)
.EXAMPLE
  scripts/check.ps1
  scripts/check.ps1 -NoTests
  scripts/check.ps1 -Json
#>
param(
    [switch]$Json,
    [switch]$Quiet,
    [switch]$NoTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$results = [System.Collections.Generic.List[object]]::new()
$exitCode = 0

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail)
    $results.Add(@{ check = $Name; status = $Status; detail = $Detail })
}

function Invoke-Script {
    param([string]$Name, [string]$Path, [string]$ScriptArgs = "")
    if (-not (Test-Path $Path)) {
        Add-Check -Name $Name -Status "SKIP" -Detail "Script not found: $Path"
        return 0
    }
    try {
        if ($ScriptArgs) { & $Path @($ScriptArgs -split ' ') 2>&1 }
        else       { & $Path 2>&1 }
        $ec = $LASTEXITCODE
        if ($ec -eq 0) {
            Add-Check -Name $Name -Status "OK" -Detail "Exit $ec"
        } elseif ($ec -eq 1) {
            Add-Check -Name $Name -Status "WARN" -Detail "Exit $ec"
            if ($script:exitCode -lt 1) { $script:exitCode = 1 }
        } else {
            Add-Check -Name $Name -Status "FAIL" -Detail "Exit $ec"
            $script:exitCode = [Math]::Max($script:exitCode, 2)
        }
        return $ec
    } catch {
        Add-Check -Name $Name -Status "FAIL" -Detail $_.Exception.Message
        $script:exitCode = [Math]::Max($script:exitCode, 2)
        return 2
    }
}

# ── 1. Health ──────────────────────────────────────────────────────────────
Invoke-Script -Name "health-check" -Path (Join-Path $PSScriptRoot "health-check.ps1")

# ── 2. Pester tests ───────────────────────────────────────────────────────
if (-not $NoTests) {
    Invoke-Script -Name "pester-tests" -Path (Join-Path $PSScriptRoot "run-tests.ps1") -Args "-Quiet"
}

# ── 3. Skill drift ────────────────────────────────────────────────────────
Invoke-Script -Name "skill-drift" -Path (Join-Path $PSScriptRoot "check-skill-drift.ps1") -Args "-Json"

# ── 4. Config drift ───────────────────────────────────────────────────────
Invoke-Script -Name "config-drift" -Path (Join-Path $PSScriptRoot "check-config-drift.ps1") -Args "-Json"

# ── 5. Git status ─────────────────────────────────────────────────────────
try {
    $gitOut = & git -C $RepoRoot status --short 2>&1
    if ($LASTEXITCODE -eq 0) {
        $changes = @($gitOut | Where-Object { $_ -is [string] -and $_.Trim() -ne '' })
        if ($changes.Count -eq 0) {
            Add-Check -Name "git-status" -Status "OK" -Detail "Working tree clean"
        } else {
            Add-Check -Name "git-status" -Status "WARN" -Detail "$($changes.Count) uncommitted change(s)"
            if ($exitCode -lt 1) { $exitCode = 1 }
        }
    } else {
        Add-Check -Name "git-status" -Status "FAIL" -Detail "git error: $($gitOut -join ' ')"
        if ($exitCode -lt 2) { $exitCode = 2 }
    }
} catch {
    Add-Check -Name "git-status" -Status "FAIL" -Detail $_.Exception.Message
    if ($exitCode -lt 2) { $exitCode = 2 }
}

# ── Output ─────────────────────────────────────────────────────────────────
$summary = @{
    timestamp = (Get-Date -Format "o")
    checks    = $results
    exitCode  = $exitCode
}

if ($Json -or $Quiet) {
    ConvertTo-Json $summary -Depth 3
} else {
    Write-Output "`n═══════════════════════════════════════════"
    Write-Output "  CHECK — gentleman-vMK"
    Write-Output "═══════════════════════════════════════════"
    $results | ForEach-Object {
        $icon = switch ($_.status) { "OK"   { "✅" } "WARN" { "🟡" } "FAIL" { "🔴" } "SKIP" { "⏭️" } default { "❓" } }
        Write-Output "$icon $($_.check): $($_.detail)"
    }
    Write-Output "───────────────────────────────────────────"
    $label = switch ($exitCode) { 0 { "✅ ALL OK" } 1 { "🟡 WARNINGS" } 2 { "🔴 FAILURES" } default { "❓" } }
    Write-Output "Exit: $exitCode — $label"
}

exit $exitCode
