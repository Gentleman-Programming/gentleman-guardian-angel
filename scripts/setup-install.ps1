#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Gentleman Agent — Windows environment setup
.DESCRIPTION
    Configures gentleman-agent-gh on Windows:
    - Sets GENTLEMAN_AGENT_ROOT and OpenCode environment variables
    - Creates global shell shortcuts (gentleman-vmk)
    - Links skills into OpenCode global config
    - Optionally installs gentle-ai CLI dependency
.EXAMPLE
    .\scripts\setup-install.ps1                 # interactive
    .\scripts\setup-install.ps1 -InstallGentleAI  # auto-install dep
#>
param(
    [switch]$InstallGentleAI
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoDir = Split-Path -Path $PSScriptRoot -Parent

# ── Bootstrap ────────────────────────────────────────────────────────
Write-Host "==> Gentleman Agent — Windows setup" -ForegroundColor Cyan
Write-Host "    Repo: $repoDir`n" -ForegroundColor DarkGray

# ── Step 1: Run setup-machine.ps1 for env + shortcuts + skill links ─
try {
    & "$PSScriptRoot\setup-machine.ps1" -RepoDir $repoDir
} catch {
    Write-Host "[err] setup-machine.ps1 failed: $_" -ForegroundColor Red
    Write-Host "       Continuing with partial setup..." -ForegroundColor Yellow
}

# ── Step 2: Optional gentle-ai CLI ──────────────────────────────────
# NOTE: This repo (gentleman-agent-gh) does NOT install gentle-ai by default.
# The -InstallGentleAI switch is deprecated and now throws an error to prevent
# accidentally shadowing the local environment with a different upstream tool.
if ($InstallGentleAI) {
    throw "-InstallGentleAI is no longer supported. If you need the gentle-ai CLI, install it separately from https://github.com/Gentleman-Programming/gentle-ai"
}

$hasGentleAI = [bool](Get-Command "gentle-ai" -ErrorAction SilentlyContinue)
if (-not $hasGentleAI) {
    Write-Host "[info] gentle-ai CLI not found. This is optional — gentleman-agent-gh works without it." -ForegroundColor Yellow
    Write-Host "       To install gentle-ai separately, visit: https://github.com/Gentleman-Programming/gentle-ai" -ForegroundColor DarkGray
} else {
    Write-Host "[ok] gentle-ai CLI detected (optional dependency)" -ForegroundColor Green
}

# ── Done ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "✅ gentleman-agent-gh setup complete" -ForegroundColor Green
Write-Host "   Run 'gentleman-vmk' to launch" -ForegroundColor Cyan
