#requires -Version 7
<#
.SYNOPSIS
  Fast pre-commit leak guard — blocks the commit if common secret patterns
  appear in staged files.
.DESCRIPTION
  Replaces the inline pwsh -Command secrets hook (which broke YAML parsing
  with invalid \$ escapes). Logic: git diff --cached --name-only → scan each
  staged file for known secret prefixes → exit 1 if any are found.
.EXAMPLE
  & scripts/leak-guard.ps1
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'

# Patterns are assembled at runtime so this file never contains a literal
# secret-shaped string (would trip the repo's own secrets scan).
$secretPatterns = @('ghp' + '_', 'gho' + '_', 'ghs' + '_', 'github_pat' + '_', 'ctx7sk' + '_', 'AK' + 'IA', 'sk' + '-')
$staged = git diff --cached --name-only
$found = @()

foreach ($f in $staged) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $content = Get-Content -LiteralPath $f -Raw
    foreach ($s in $secretPatterns) {
        if ($content -match [regex]::Escape($s)) {
            $found += $f
            break
        }
    }
}

if ($found.Count -gt 0) {
    Write-Host "SECRETS BLOCKED in: $($found -join ', ')" -ForegroundColor Red
    exit 1
}
if (-not $Quiet) {
    Write-Host "OK: no secrets in staged files" -ForegroundColor Green
}
exit 0
