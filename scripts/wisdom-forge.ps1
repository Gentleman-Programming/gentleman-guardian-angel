#requires -Version 7
<#
.SYNOPSIS
    Auto-forge a skill from a pattern when it reaches its promotion threshold.
.DESCRIPTION
    Reads a pattern, checks severity-based thresholds, generates SKILL.md, runs 9 quality gates, registers as lazy-load skill.
.THRESHOLDS
    CRITICAL: >=1 hit/1 project | HIGH: >=2 hits/2 projects | MEDIUM: >=3 hits/2 projects | LOW: >=5 hits/3 projects
.PARAMETER PatternId
    Pattern ID (e.g. "ux/a11y/hero-btn-contrast").
.PARAMETER PatternFile
    Path to pattern JSON (alternative to PatternId).
.PARAMETER Force
    Skip threshold check.
.PARAMETER DryRun
    Run gates but don't write.
.PARAMETER Quiet
    Output JSON only.
#>
param(
    [string]$PatternId = "",
    [string]$PatternFile = "",
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Quiet
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$patternsDir = Join-Path (Join-Path (Join-Path $repoRoot "docs") "cross-project") "patterns"
$skillsDir = Join-Path (Join-Path $repoRoot ".agents") "skills"
$thresholds = @{
    CRITICAL = @{ Hits = 1; Projects = 1 }; HIGH = @{ Hits = 2; Projects = 2 }
    MEDIUM = @{ Hits = 3; Projects = 2 }; LOW = @{ Hits = 5; Projects = 3 }
}

# --- Helpers ---
function Import-Pattern {
    param([string]$Id, [string]$File)
    if ($Id) {
        $filePath = $patternIndex[$Id]
        if (-not $filePath) { Write-Error "Pattern not found: $Id"; exit 1 }
    } elseif ($File) {
        if (-not (Test-Path $File)) { Write-Error "File not found: $File"; exit 1 }
        $filePath = $File
    } else { Write-Error "Provide -PatternId or -PatternFile"; exit 1 }
    try { $pattern = Get-Content $filePath -Raw | ConvertFrom-Json } catch { Write-Error "Invalid JSON: $_"; exit 1 }
    return $pattern, $filePath
}

function Get-SkillSlug {
    param([string]$Id)
    $slug = ($Id -replace '[/\s]+', '-').ToLower()
    if ($slug -notlike "cross-project-*") { $slug = "cross-project-$slug" }
    return $slug -replace '-+$', ''
}

function Test-ForgeThreshold {
    param($Pattern)
    if ($Force) { return $true, "forced" }
    $severity = if ($Pattern.severity -and $thresholds.ContainsKey($Pattern.severity)) { $Pattern.severity } else { "MEDIUM" }
    $t = $thresholds[$severity]
    $hits = if ($Pattern.hits) { [int]$Pattern.hits } else { 0 }
    $projects = if ($Pattern.context -and $Pattern.context.files) { @($Pattern.context.files | Select-Object -Unique).Length } else { 1 }
    if ($projects -lt 1) { $projects = 1 }
    if ($hits -ge $t.Hits -and $projects -ge $t.Projects) { return $true, "met (${severity}: $($t.Hits)x$($t.Projects))" }
    return $false, "needs $([Math]::Max(0, $t.Hits - $hits)) hits, $([Math]::Max(0, $t.Projects - $projects)) projects"
}

function New-SkillContent {
    [CmdletBinding(SupportsShouldProcess)]
    param($Pattern)
    $slug = Get-SkillSlug $Pattern.id
    $description = if ($Pattern.rule -and $Pattern.rule.summary) {
        $desc = $Pattern.rule.summary -replace '[\u201c\u201d]', '"' -replace "'", "'"
        if ($desc.Length -gt 115) { $desc.Substring(0, 112) + "..." } else { $desc }
    } else { $Pattern.title }
    $triggerKeywords = @($Pattern.title)
    if ($Pattern.tags) { $triggerKeywords += $Pattern.tags }
    if ($Pattern.signal -and $Pattern.signal.keywords) { $triggerKeywords += $Pattern.signal.keywords }
    if ($Pattern.signal -and $Pattern.signal.css_selectors) { $triggerKeywords += $Pattern.signal.css_selectors }
    $triggerStr = ($triggerKeywords | Select-Object -Unique) -join ', '
    $details = if ($Pattern.rule -and $Pattern.rule.details) { $Pattern.rule.details } else { "" }
    $check = if ($Pattern.rule -and $Pattern.rule.check) { $Pattern.rule.check } else { "" }
    $fix = if ($Pattern.rule -and $Pattern.rule.fix) { $Pattern.rule.fix } else { "" }
    $skillContent = @"
---
name: $slug
description: "$description"
license: Apache-2.0
metadata:
  tags: [$($Pattern.tags -join ', ')]
  author: gentleman-vMK (auto-forged)
  version: "1.0"
  source_pattern: "$($Pattern.id)"
  source_severity: "$($Pattern.severity)"
triggers: "$triggerStr"
---

## Rule
$details

## Check
$check

## Fix
$fix

## Source Pattern
Forged from **$($Pattern.id)**. Updated: $($Pattern.updated). Confidence: $($Pattern.confidence).
"@
    if ($PSCmdlet.ShouldProcess("$($Pattern.id)", 'Generate skill content')) {
        return $skillContent
    }
    return $null
}

$gateResults = @()
function Add-Gate {
    param([string]$Name, [scriptblock]$Check)
    try { $passed = & $Check; $gateResults += [PSCustomObject]@{ Gate = $Name; Status = if ($passed) { "PASS" } else { "FAIL" } }; return $passed }
    catch { $gateResults += [PSCustomObject]@{ Gate = $Name; Status = "FAIL"; Error = $_.Exception.Message }; return $false }
}

function Test-YamlFrontmatter { param([string]$Content); $trimmed = $Content.TrimStart(); return $trimmed.StartsWith("---") -and ($Content -match '(?s)---\s*\n.*?\n---') }
$script:triggerCache = $null
function Get-TriggerCache {
    if ($script:triggerCache) { return $script:triggerCache }
    $set = @{}
    foreach ($f in @(Get-ChildItem $skillsDir -Filter 'SKILL.md' -Recurse -EA SilentlyContinue)) {
        try { $c = Get-Content $f.FullName -Raw; if ($c -match '(?s)triggers:\s*"([^"]+)"') { ($Matches[1] -split ',') | ForEach-Object { $set[$_.Trim().ToLower()] = $true } } } catch { continue }
    }
    $script:triggerCache = $set
    return $set
}
function Test-TriggerUnique { param([string[]]$Triggers); $existing = Get-TriggerCache; foreach ($t in $Triggers) { if ($t.Trim().ToLower() -ne '' -and $existing.ContainsKey($t.Trim().ToLower())) { return $false } }; return $true }
function Test-NoSecret { param([string]$Content); foreach ($p in @('-----BEGIN (RSA|OPENSSH|PRIVATE|EC) KEY-----', '(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*[''"][^''"]{8,}')) { if ($Content -match $p) { return $false } }; return $true }
function Test-NoConflict { param([string]$Name); return @(Get-ChildItem $skillsDir -Directory | Where-Object { $_.Name -eq $Name }).Length -eq 0 }

$patternIndex = @{}
foreach ($f in @(Get-ChildItem $patternsDir -Filter '*.json')) {
    try { $p = Get-Content $f.FullName -Raw | ConvertFrom-Json; if ($p.id) { $patternIndex[$p.id] = $f.FullName } } catch { Write-Debug "wisdom-forge: $($_.Exception.Message)" }
}

# --- Main ---
$pattern, $filePath = Import-Pattern -Id $PatternId -File $PatternFile
$severity = if ($pattern.severity) { $pattern.severity } else { "MEDIUM" }
$id = $pattern.id
$hits = if ($pattern.hits) { [int]$pattern.hits } else { 0 }

if (-not $Quiet) {
    Write-Host "=== Wisdom Forge | $id | $severity (hits: $hits) ===" -ForegroundColor Cyan
    if ($DryRun) { Write-Host "[DRY-RUN]" -ForegroundColor Yellow }
}

if (-not $Force) {
    $met, $reason = Test-ForgeThreshold $pattern
    if (-not $met) {
        if (-not $Quiet) { Write-Host "[X] $reason" -ForegroundColor Red }
        [PSCustomObject]@{ Status = "BLOCKED"; Reason = $reason; PatternId = $id; Gates = $gateResults } | ConvertTo-Json -Depth 3
        exit 0
    }
    if (-not $Quiet) { Write-Host "[OK] $reason" -ForegroundColor Green }
}

$slug = Get-SkillSlug $pattern.id
$skillDir = Join-Path $skillsDir $slug
$skillFile = Join-Path $skillDir "SKILL.md"
$skillContent = New-SkillContent $pattern
$skillSize = [System.Text.Encoding]::UTF8.GetByteCount($skillContent)
if (-not $Quiet) { Write-Host "[GEN] $slug ($skillSize bytes)" -ForegroundColor Cyan }

# Quality gates
$allPass = $true
$triggers = if ($pattern.tags) { @($pattern.tags) } else { @() }
$checks = @(
    @{ N = "yaml-frontmatter";  C = { Test-YamlFrontmatter $skillContent } },
    @{ N = "name-prefix";       C = { $slug -like "cross-project-*" } },
    @{ N = "desc-length";       C = { $d = if ($skillContent -match '(?m)^description:\s*"([^"]+)"') { $Matches[1] } else { "" }; $d.Length -le 120 } },
    @{ N = "triggers-nonempty"; C = { $triggers.Length -gt 0 } },
    @{ N = "triggers-unique";   C = { Test-TriggerUnique $triggers } },
    @{ N = "has-rules";         C = { $pattern.rule -and ($pattern.rule.check -or $pattern.rule.fix -or $pattern.rule.details) } },
    @{ N = "size-max-2kb";      C = { $skillSize -le 2048 } },
    @{ N = "no-conflict";       C = { Test-NoConflict $slug } },
    @{ N = "no-secrets";        C = { Test-NoSecret $skillContent } }
)
foreach ($check in $checks) { $ok = Add-Gate $check.N $check.C; if (-not $ok) { $allPass = $false } }

if (-not $Quiet) {
    Write-Host "`n--- Gates ---" -ForegroundColor Yellow
    foreach ($gate in $gateResults) { $icon = if ($gate.Status -eq 'PASS') { "[OK]" } else { "[X]" }; Write-Host "  $icon $($gate.Gate)" }
}

if (-not $allPass) {
    if (-not $Quiet) { Write-Host "`n[X] BLOCKED" -ForegroundColor Red }
    [PSCustomObject]@{ Status = "BLOCKED"; Reason = "Gates failed"; PatternId = $id; Gates = $gateResults } | ConvertTo-Json -Depth 4
    exit 0
}
if (-not $Quiet) { Write-Host "`n[OK] All gates PASSED" -ForegroundColor Green }

if ($DryRun) {
    if (-not $Quiet) { Write-Host "[DRY] Would create: $skillDir" -ForegroundColor Yellow }
    [PSCustomObject]@{ Status = "DRY_RUN"; PatternId = $id; SkillName = $slug; SkillPath = $skillDir; SkillSize = $skillSize; Gates = $gateResults } | ConvertTo-Json -Depth 4
    exit 0
}

# Write skill
if (-not (Test-Path $skillDir)) { New-Item -ItemType Directory -Path $skillDir -Force | Out-Null }
Set-Content -Path $skillFile -Value $skillContent -Encoding UTF8
if (-not $Quiet) { Write-Host "[WRITE] $skillFile" -ForegroundColor Green }

# Update pattern file
$pattern | Add-Member -NotePropertyName "skill_ref" -NotePropertyValue $slug -Force
$pattern | Add-Member -NotePropertyName "status" -NotePropertyValue "promoted" -Force
$pattern | Add-Member -NotePropertyName "promoted_at" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
$pattern | ConvertTo-Json -Depth 6 | Set-Content $filePath -Encoding UTF8
if (-not $Quiet) { Write-Host "[UPDATE] Pattern -> promoted" -ForegroundColor Green }

# Final output
$result = [PSCustomObject]@{
    Status = "FORGED"; PatternId = $id; SkillName = $slug; SkillPath = $skillDir; SkillFile = $skillFile; SkillSize = $skillSize; Gates = $gateResults
    EngramPayload = [PSCustomObject]@{ TopicKey = "forge/$slug"; Type = "architecture"; Title = "Forged: $slug"; Content = "**What**: Auto-forged from ``$id`` ($severity, $hits hits)`n**Where**: $skillFile`n**Learned**: 9 quality gates passed" }
}
if (-not $Quiet) { Write-Host "`n=== FORGED: $slug ===" -ForegroundColor Green }
$result | ConvertTo-Json -Depth 5
