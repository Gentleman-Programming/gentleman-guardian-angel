#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

<#
.SYNOPSIS
  List skills with sizes, file counts, and quality scores.

.DESCRIPTION
  Scans .agents/skills/ and reports each skill's:
  - Size (KB) — total directory size
  - Files   — number of files
  - Lines   — lines in SKILL.md (0 if missing)
  - Refs    — has references/ directory
  - Score   — quality heuristic (0-10 based on size, docs, refs)

  Excludes _shared by default (use -IncludeShared to show it).

.PARAMETER IncludeShared
  Include the _shared reference skill in output.

.PARAMETER Json
  Output JSON array (machine-readable).

.PARAMETER MinScore
  Filter: only show skills with Score >= this value.

.EXAMPLE
  .\scripts\list-skills.ps1

.EXAMPLE
  .\scripts\list-skills.ps1 -Json

.EXAMPLE
  .\scripts\list-skills.ps1 -MinScore 9
#>

param(
    [switch]$IncludeShared,
    [switch]$Json,
    [int]$MinScore = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$skillsDir = Join-Path -Path $PSScriptRoot -ChildPath "..\.agents\skills"
if (-not (Test-Path -LiteralPath $skillsDir)) {
    Write-Error "Skills directory not found: $skillsDir"
    exit 1
}

try {
    $skills = Get-ChildItem -LiteralPath $skillsDir -Directory | Sort-Object -Property Name

$results = @()

foreach ($skill in $skills) {
    $name = $skill.Name

    # Skip _shared unless explicitly included
    if ($name -eq '_shared' -and -not $IncludeShared) {
        continue
    }

    try {
        $dir = $skill.FullName
        $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File)
        $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
        $sizeKB = [Math]::Round($totalBytes / 1KB, 1)
        $fileCount = $files.Count

        # SKILL.md stats
        $skillMd = @(Get-ChildItem -LiteralPath $dir -Filter "SKILL.md" -Recurse -File | Select-Object -First 1)
        if ($skillMd) {
            $skillMdLines = (Get-Content -LiteralPath $skillMd.FullName).Count
            $skillMdSizeKB = [Math]::Round($skillMd.Length / 1KB, 1)
        } else {
            $skillMdLines = 0
            $skillMdSizeKB = 0
        }

        $hasRefs = Test-Path -LiteralPath (Join-Path -Path $dir -ChildPath "references")

        # --- Quality score (heuristic, 0-10) ---
        $score = 5  # baseline

        # Size sweet spot: 1KB-15KB total
        if ($sizeKB -gt 1.0 -and $sizeKB -lt 15.0) { $score += 1 }
        # Has substantial doc (>30 lines)
        if ($skillMdLines -gt 30)  { $score += 1 }
        # Has substantial doc (>60 lines)
        if ($skillMdLines -gt 60)  { $score += 1 }
        # Has references dir
        if ($hasRefs)              { $score += 1 }
        # Has multiple files (beyond just SKILL.md)
        if ($fileCount -ge 2)      { $score += 1 }
        # Has 3+ files
        if ($fileCount -ge 3)      { $score += 1 }

        # Clamp
        if ($score -gt 10) { $score = 10 }
        if ($score -lt 0)  { $score = 0 }

        $results += [PSCustomObject]@{
            Name       = $name
            SizeKB     = $sizeKB
            Files      = $fileCount
            SkillMmLines = $skillMdLines
            SkillMdKB  = $skillMdSizeKB
            Refs       = if ($hasRefs) { "yes" } else { "no" }
            Score      = $score
        }
    } catch {
        Write-Warning "Could not process skill '$($skill.Name)': $_"
        continue
    }
}

# Filter by min score
if ($MinScore -gt 0) {
    $results = $results | Where-Object { $_.Score -ge $MinScore }
}

if ($Json) {
    Write-Output ($results | ConvertTo-Json -Depth 2)
} else {
    # Summary header
    $total = $results.Count
    $avgScore = [Math]::Round(($results | Measure-Object -Property Score -Average).Average, 1)
    $avgSize = [Math]::Round(($results | Measure-Object -Property SizeKB -Average).Average, 1)

    Write-Output "Skills: $total  |  Avg score: $avgScore/10  |  Avg size: ${avgSize}KB"
    Write-Output ""

    # Determine width for name column
    $maxNameLen = ($results | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $nameWidth = [Math]::Max($maxNameLen, 4) + 2

    # Header
    $fmt = "{0,-$nameWidth} {1,7} {2,5} {3,11} {4,5} {5,6}"
    Write-Output ($fmt -f "Name", "SizeKB", "Files", "SKILL.md#L", "Refs", "Score")
    Write-Output ($fmt -f "----", "------", "-----", "----------", "----", "-----")

    foreach ($r in $results) {
        Write-Output ($fmt -f $r.Name, $r.SizeKB, $r.Files, $r.SkillMmLines, $r.Refs, $r.Score)
    }
}
}
catch {
    Write-Error "Failed to list skills: $_"
    exit 1
}
