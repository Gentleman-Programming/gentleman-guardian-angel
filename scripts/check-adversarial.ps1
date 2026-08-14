#!/usr/bin/env pwsh
#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Lightweight adversarial-breaker profile scan — commit-time gate.

.DESCRIPTION
  Scans staged files against language-specific attack profiles (JSON rules).
  Acts as a first-line defense — the full adversarial-breaker skill runs
  deep analysis via sub-agents. This catches obvious patterns at commit time.

  Profiles live in: scripts/adversarial-rules/<lang>.json

.PARAMETER Quiet
  Suppress console output, return results as JSON.

.PARAMETER UseStaged
  Only scan staged files (default: scan all files in -Path).

.EXAMPLE
  .githooks/pre-commit-gate.ps1 calls this internally for [22/22].
#>
param(
    [string]$RepoRoot = (git rev-parse --show-toplevel 2>$null) ?? '.',
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rulesDir = Join-Path $RepoRoot 'scripts\adversarial-rules'

# Files in this list are infrastructure (contain rule patterns as strings), not
# attack surfaces — exclude self and rules directory to avoid false positives.
$infraExclusions = @(
    'scripts/check-adversarial.ps1',
    'scripts/adversarial-rules/'
)

$stagedItems = git diff --cached --name-only --diff-filter=ACM
$stagedFiles = @()
foreach ($f in $stagedItems) {
    # Skip infrastructure files (contain rule patterns as string literals)
    $skip = $false
    foreach ($excl in $infraExclusions) {
        if ($f -like $excl) { $skip = $true; break }
    }
    if ($skip) { continue }

    $full = Join-Path $RepoRoot $f
    if (-not (Test-Path $full -PathType Leaf)) { continue }
    $ext = [System.IO.Path]::GetExtension($f).ToLower()
    $extKey = $ext.TrimStart('.')
    # Map .ps1/.psm1/.psd1 → powershell profile, or use ext name directly
    if (Test-Path (Join-Path $rulesDir "$extKey.json")) {
        $langProfile = $extKey
    }     elseif ((Test-Path -LiteralPath (Join-Path $rulesDir "powershell.json")) -and @('ps1','psm1','psd1') -contains $extKey) {
        $langProfile = 'powershell'
    } else {
        continue
    }
    $rulesFile = Join-Path $rulesDir "$langProfile.json"
    if (Test-Path $rulesFile) {
        $stagedFiles += [PSCustomObject]@{
            RelativePath = $f
            FullPath     = $full
            Profile      = $langProfile
            RulesFile    = $rulesFile
        }
    }
}

if (-not $stagedFiles -and -not $Quiet) {
    Write-Host "  (no profile-matched files staged)" -ForegroundColor Gray
}

$allIssues = @()
$forceShip = [bool]$env:FORCE_SHIP

foreach ($sf in $stagedFiles) {
    # Check .breaker-cleared marker
    $clearedMarker = "$RepoRoot\.breaker-cleared\" + ($sf.RelativePath.Replace('/','_').Replace('\','_'))
    if (Test-Path $clearedMarker -PathType Leaf) {
        if (-not $Quiet) { Write-Host "  $($sf.RelativePath) — .breaker-cleared" -ForegroundColor Gray }
        continue
    }

    $rules = (Get-Content $sf.RulesFile -Raw -Encoding UTF8 | ConvertFrom-Json).rules
    $lines = @(Get-Content $sf.FullPath)

    if ($lines.Count -eq 0) { continue }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNum = $i + 1
        $line = $lines[$i]

        foreach ($rule in $rules) {
            if ($line -match $rule.pattern) {
                $issue = [PSCustomObject]@{
                    File     = $sf.RelativePath
                    Line     = $lineNum
                    RuleId   = $rule.id
                    Severity = $rule.severity
                    Name     = $rule.name
                    Match    = $line.Trim()
                    Description = $rule.description
                    Remediation = $rule.remediation
                }

                if (-not $Quiet) {
                    $color = if ($rule.severity -eq 'block') { 'Red' } else { 'Yellow' }
                    Write-Host "    $($sf.RelativePath):$lineNum [$($rule.id)] $($rule.name)" -ForegroundColor $color
                    Write-Host "      $($line.Trim())"
                    Write-Host "      Remediation: $($rule.remediation)"
                }

                $allIssues += $issue
            }
        }
    }
}

$blockCount = @($allIssues | Where-Object { $_.Severity -eq 'block' }).Count
$warnCount  = @($allIssues | Where-Object { $_.Severity -eq 'warn' }).Count

if ($forceShip -and $allIssues) {
    if (-not $Quiet) {
        Write-Host "  FORCE_SHIP set — $($allIssues.Count) issue(s) bypassed" -ForegroundColor Yellow
    }
}

if ($Quiet) {
    $result = [PSCustomObject]@{
        passed = ($blockCount -eq 0)
        blocks = $blockCount
        warns  = $warnCount
        issues = $allIssues
    }
    $result | ConvertTo-Json -Depth 5
}

exit $(if ($forceShip) { 0 } elseif ($blockCount -gt 0) { 1 } else { 0 })
