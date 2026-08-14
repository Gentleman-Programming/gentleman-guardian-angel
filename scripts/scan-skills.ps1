#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

<#
.SYNOPSIS
    Detects drift between SKILL.md frontmatter and skill-graph.ps1 registry

.DESCRIPTION
    Scans all SKILL.md files in .agents/skills/, extracts frontmatter metadata,
    compares against Register-Skill calls in skill-graph.ps1, and reports:
    - Skills in SKILL.md but NOT in skill-graph.ps1 (unregistered)
    - Skills in skill-graph.ps1 but NOT in SKILL.md (orphaned)
    - Trigger mismatches between frontmatter and registry

.PARAMETER Fix
    Auto-generate missing Register-Skill lines (output to console, not file)

.PARAMETER Json
    Output as JSON instead of table
#>

param(
    [switch]$Fix,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# Paths
# ============================================================================

$scriptDir = Split-Path -Parent $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Get-Location }

$skillsDir = Join-Path $scriptDir ".agents\skills"
$skillGraphPath = Join-Path $scriptDir "scripts\skill-graph.ps1"

if (-not (Test-Path $skillsDir)) {
    Write-Error "Skills directory not found: $skillsDir"
    exit 1
}
if (-not (Test-Path $skillGraphPath)) {
    Write-Error "skill-graph.ps1 not found: $skillGraphPath"
    exit 1
}

# ============================================================================
# 1. Scan SKILL.md files — extract frontmatter
# ============================================================================

$skillFiles = Get-ChildItem -Path $skillsDir -Filter "SKILL.md" -Recurse -File |
    Where-Object { $_.DirectoryName -notmatch '_shared' }

$diskSkills = @{}

foreach ($file in $skillFiles) {
    $content = Get-Content -Path $file.FullName -Raw
    $skillDir = Split-Path -Leaf (Split-Path -Parent $file.FullName)

    # Extract YAML frontmatter between --- delimiters
    if ($content -match '(?s)^---\s*\r?\n(.*?)\r?\n---') {
        $yaml = $matches[1]

        $name = $null
        $triggers = $null
        $description = $null

        if ($yaml -match 'name:\s*(.+)') { $name = $matches[1].Trim() }
        if ($yaml -match 'description:\s*"?(.*?)"?\s*$') { $description = $matches[1].Trim('"') }
        if ($yaml -match 'triggers:\s*"?(.*?)"?\s*$') { $triggers = $matches[1].Trim('"') }

        if ($name) {
            $diskSkills[$name] = @{
                Path        = $file.FullName
                DirName     = $skillDir
                Name        = $name
                Triggers    = $triggers
                Description = $description
            }
        }
    }
}

# ============================================================================
# 2. Parse skill-graph.ps1 — extract Register-Skill calls
# ============================================================================

$graphContent = Get-Content -Path $skillGraphPath -Raw
$graphSkills = @{}

# Match: Register-Skill <name> "<triggers>" <category> <effort> ["<depends>"] ["<related>"] "<desc>"
# Depends and Related can be quoted or unquoted
$pattern = 'Register-Skill\s+(\S+)\s+"([^"]*)"\s+\S+\s+\S+\s+(?:"([^"]*)"|(\S+))\s+(?:"([^"]*)"|(\S+))'
$matches_found = [regex]::Matches($graphContent, $pattern)

foreach ($m in $matches_found) {
    $name = $m.Groups[1].Value
    $triggers = $m.Groups[2].Value
    $depends = if ($m.Groups[3].Success) { $m.Groups[3].Value } else { $m.Groups[4].Value }
    $related = if ($m.Groups[5].Success) { $m.Groups[5].Value } else { $m.Groups[6].Value }

    $graphSkills[$name] = @{
        Name     = $name
        Triggers = $triggers
        Depends  = $depends
        Related  = $related
    }
}

# ============================================================================
# 3. Compare
# ============================================================================

$diskNames = $diskSkills.Keys | Sort-Object
$graphNames = $graphSkills.Keys | Sort-Object

# Skills in disk but NOT in graph (unregistered)
$unregistered = @()
foreach ($name in $diskNames) {
    if (-not $graphSkills.ContainsKey($name)) {
        $unregistered += $diskSkills[$name]
    }
}

# Skills in graph but NOT in disk (orphaned)
$orphaned = @()
foreach ($name in $graphNames) {
    if (-not $diskSkills.ContainsKey($name)) {
        $orphaned += $graphSkills[$name]
    }
}

# Trigger mismatches
$mismatches = @()
foreach ($name in $diskNames) {
    if ($graphSkills.ContainsKey($name)) {
        $diskTriggers = ($diskSkills[$name].Triggers -split '\|') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ } | Sort-Object
        $graphTriggers = ($graphSkills[$name].Triggers -split '\|') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ } | Sort-Object

        $diskOnly = $diskTriggers | Where-Object { $_ -notin $graphTriggers }
        $graphOnly = $graphTriggers | Where-Object { $_ -notin $diskTriggers }

        if ($diskOnly -or $graphOnly) {
            $mismatches += @{
                Name      = $name
                DiskOnly  = $diskOnly
                GraphOnly = $graphOnly
            }
        }
    }
}

# ============================================================================
# 4. Output
# ============================================================================

if ($Json) {
    $result = @{
        Timestamp       = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        DiskSkillsCount = $diskSkills.Count
        GraphSkillsCount = $graphSkills.Count
        Unregistered    = $unregistered
        Orphaned        = $orphaned
        Mismatches      = $mismatches
    }
    $result | ConvertTo-Json -Depth 5
    return
}

# Human-readable output
Write-Host ""
Write-Host "=== Skill Registry Sync Report ===" -ForegroundColor Cyan
Write-Host "Disk: $($diskSkills.Count) skills | Graph: $($graphSkills.Count) skills"
Write-Host ""

# Unregistered
if ($unregistered.Count -gt 0) {
    Write-Host "UNREGISTERED (in SKILL.md, not in skill-graph.ps1):" -ForegroundColor Yellow
    foreach ($s in $unregistered) {
        Write-Host "  + $($s.Name)" -ForegroundColor Yellow
        Write-Host "    Triggers: $($s.Triggers)"
    }
    Write-Host ""
} else {
    Write-Host "All SKILL.md files are registered." -ForegroundColor Green
}

# Orphaned
if ($orphaned.Count -gt 0) {
    Write-Host "ORPHANED (in skill-graph.ps1, no SKILL.md found):" -ForegroundColor Red
    foreach ($s in $orphaned) {
        Write-Host "  - $($s.Name)" -ForegroundColor Red
    }
    Write-Host ""
} else {
    Write-Host "No orphaned entries in skill-graph.ps1." -ForegroundColor Green
}

# Mismatches
if ($mismatches.Count -gt 0) {
    Write-Host "TRIGGER MISMATCHES:" -ForegroundColor Magenta
    foreach ($m in $mismatches) {
        Write-Host "  ~ $($m.Name)" -ForegroundColor Magenta
        if ($m.DiskOnly) { Write-Host "    Only in SKILL.md: $($m.DiskOnly -join ', ')" }
        if ($m.GraphOnly) { Write-Host "    Only in skill-graph.ps1: $($m.GraphOnly -join ', ')" }
    }
    Write-Host ""
}

# Fix mode
if ($Fix -and $unregistered.Count -gt 0) {
    Write-Host "=== SUGGESTED Register-Skill LINES ===" -ForegroundColor Cyan
    foreach ($s in $unregistered) {
        $triggers = ($s.Triggers -split '\s*\|\s*') -join '|'
        $desc = if ($s.Description) { $s.Description } else { $s.Name }
        Write-Host "Register-Skill $($s.Name) `"$triggers`" unknown medium `"`" `"`" `"$desc`"" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Copy these lines into skill-graph.ps1 under the appropriate category." -ForegroundColor Gray
}

# Summary
$totalIssues = $unregistered.Count + $orphaned.Count + $mismatches.Count
if ($totalIssues -eq 0) {
    Write-Host "SYNC OK — no drift detected." -ForegroundColor Green
} else {
    Write-Host "DRIFT DETECTED — $totalIssues issue(s) found." -ForegroundColor Red
}
