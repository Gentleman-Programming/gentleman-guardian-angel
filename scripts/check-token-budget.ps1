#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Token budget monitor — checks average SKILL.md + prompt file sizes
    against the 2,000-byte target (ADR-007 compliance, C9).

.DESCRIPTION
    Scans .agents/skills/*/SKILL.md and prompts/shared/*.md for file
    sizes, computes averages, and reports violations. Designed to run
    as part of the improvement cycle / quality gate.

    Target: average ≤ 2,000 bytes per skill/prompt file.

.PARAMETER SkillsPath
    Root directory containing skill subdirectories (default: .agents/skills).

.PARAMETER PromptsPath
    Directory containing prompt files (default: prompts/shared).

.PARAMETER BudgetBytes
    Maximum average file size in bytes (default: 2000).

.PARAMETER Json
    Emit machine-readable JSON.

.EXAMPLE
    .\scripts\check-token-budget.ps1
    .\scripts\check-token-budget.ps1 -BudgetBytes 2000 -Json
#>
param(
    [string]$SkillsPath = (Join-Path $PSScriptRoot "..\.agents\skills"),
    [string]$PromptsPath = (Join-Path $PSScriptRoot "..\prompts\shared"),
    [int]$BudgetBytes = 2000,
    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$violations = @()
$stats = @{}

# --- Scan skill SKILL.md files ---
    $skillFiles = @()
    if (Test-Path $SkillsPath) {
        $skillFiles = @(Get-ChildItem -Path $SkillsPath -Filter "SKILL.md" -Recurse -File)
    }
    if ($skillFiles.Count -gt 0) {
    $avgSkill = [math]::Round(($skillFiles | Measure-Object -Property Length -Average).Average, 0)
    $overBudget = $skillFiles | Where-Object { $_.Length -gt $BudgetBytes }
    $stats.skills = [PSCustomObject]@{
        count      = $skillFiles.Count
        average    = $avgSkill
        budget     = $BudgetBytes
        underBudget = ($skillFiles | Where-Object { $_.Length -le $BudgetBytes }).Count
        overBudgetFiles = $overBudget.Count
        passed     = $avgSkill -le $BudgetBytes
    }
    if ($avgSkill -gt $BudgetBytes) {
        $violations += "skills avg $($avgSkill)B exceeds $BudgetBytes B budget ($($overBudget.Count) files over)"
    }
}

# --- Scan prompt files ---
$promptFiles = @()
if (Test-Path $PromptsPath) {
    $promptFiles = @(Get-ChildItem -Path $PromptsPath -File -Include "*.md", "*.prompt" -Recurse)
}
if ($promptFiles.Count -gt 0) {
    $avgPrompt = [math]::Round(($promptFiles | Measure-Object -Property Length -Average).Average, 0)
    $overBudgetPrompt = $promptFiles | Where-Object { $_.Length -gt $BudgetBytes }
    $stats.prompts = [PSCustomObject]@{
        count      = $promptFiles.Count
        average    = $avgPrompt
        budget     = $BudgetBytes
        underBudget = ($promptFiles | Where-Object { $_.Length -le $BudgetBytes }).Count
        overBudgetFiles = $overBudgetPrompt.Count
        passed     = $avgPrompt -le $BudgetBytes
    }
    if ($avgPrompt -gt $BudgetBytes) {
        $violations += "prompts avg $($avgPrompt)B exceeds $BudgetBytes B budget ($($overBudgetPrompt.Count) files over)"
    }
}

$passed = $violations.Count -eq 0

if ($Json) {
    [PSCustomObject]@{
        passed    = $passed
        budget    = $BudgetBytes
        violations = $violations
        stats     = $stats
    } | ConvertTo-Json -Compress
    $ec = if ($passed) { 0 } else { 1 }
    exit $ec
}

# Human-readable
if ($passed) {
    $s = $stats.skills
    $p = $stats.prompts
    Write-Output "OK   Token budget: skills $($s.average)B/$BudgetBytes (avg), prompts $($p.average)B/$BudgetBytes (avg)"
} else {
    Write-Output "FAIL Token budget exceeded ($BudgetBytes B target):"
    $violations | ForEach-Object { Write-Output "   X  $_" }
}

$ec = if ($passed) { 0 } else { 1 }
exit $ec
