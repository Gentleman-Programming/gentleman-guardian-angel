#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Learning statistics — pattern occurrences and trends over time.
.DESCRIPTION
    Reads .learnings/ directory, counts pattern occurrences,
    shows learning trends, and outputs JSON stats for agent consumption.
.PARAMETER Json
    Output JSON format (default: true).
.EXAMPLE
    . "$PSScriptRoot\learning-stats.ps1"
#>
param(
    [bool]$Json = $true,
    [switch]$Quiet
)

# ponytail: self-learning
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$learningsDir = Join-Path $repoRoot '.learnings'
$learningsFile = Join-Path $learningsDir 'LEARNINGS.md'
$errorsFile = Join-Path $learningsDir 'ERRORS.md'
$catalogFile = Join-Path $repoRoot 'ANTI-PATTERN-CATALOG.md'
$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'

function Get-FileLineCount {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $count = 0
        foreach ($line in [System.IO.File]::ReadLines($Path)) { $count++ }
        return $count
    } catch { return 0 }
}

function Get-CatalogStat {
    if (-not (Test-Path $catalogFile)) {
        return [PSCustomObject]@{ Entries = 0; LastUpdated = $null; AgeDays = $null }
    }
    try {
        $item = Get-Item $catalogFile
        $content = Get-Content $catalogFile -Raw -ErrorAction Stop
        $entryCount = ([regex]::Matches($content, '^\|\s*\d+\s*\|', 'Multiline')).Count
        $age = (Get-Date) - $item.LastWriteTime
        return [PSCustomObject]@{
            Entries     = $entryCount
            LastUpdated = $item.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            AgeDays     = [math]::Round($age.TotalDays, 1)
        }
    } catch {
        return [PSCustomObject]@{ Entries = 0; LastUpdated = $null; AgeDays = $null }
    }
}

function Get-LearningEntry {
    $entries = @()
    if (-not (Test-Path $learningsFile)) { return $entries }
    try {
        $lines = [System.IO.File]::ReadLines($learningsFile)
    } catch { return $entries }
    foreach ($line in $lines) {
        if ($line.StartsWith('|') -and -not $line.StartsWith('| Timestamp')) {
            $parts = $line.Split('|')
            if ($parts.Count -ge 4) {
                $ts = $parts[1].Trim()
                $section = $parts[2].Trim()
                $msg = $parts[3].Trim()
                $date = $null
                if ($ts -match '^\d{4}-\d{2}-\d{2}') { $date = $Matches[0] }
                $entries += [PSCustomObject]@{
                    Timestamp = $ts
                    Date      = $date
                    Section   = $section
                    Message   = $msg
                }
            }
        }
    }
    return $entries
}

function Get-ErrorEntry {
    $entries = @()
    if (-not (Test-Path $errorsFile)) { return $entries }
    try {
        $lines = [System.IO.File]::ReadLines($errorsFile)
    } catch { return $entries }
    foreach ($line in $lines) {
        if ($line.StartsWith('|') -and -not $line.StartsWith('| Timestamp')) {
            $parts = $line.Split('|')
            if ($parts.Count -ge 4) {
                $ts = $parts[1].Trim()
                $errText = $parts[3].Trim()
                $date = $null
                if ($ts -match '^\d{4}-\d{2}-\d{2}') { $date = $Matches[0] }
                $entries += [PSCustomObject]@{
                    Timestamp = $ts
                    Date      = $date
                    Error     = $errText
                }
            }
        }
    }
    return $entries
}

# --- Main logic ---
$learningEntries = Get-LearningEntry
$errorEntries = Get-ErrorEntry
$catalogStats = Get-CatalogStat

# Section frequency
$sectionCounts = @{}
foreach ($e in $learningEntries) {
    $s = $e.Section
    if ($sectionCounts.ContainsKey($s)) { $sectionCounts[$s]++ } else { $sectionCounts[$s] = 1 }
}

# Date trend (group by date)
$dateTrend = @{}
foreach ($e in $learningEntries) {
    if ($e.Date) {
        $d = $e.Date
        if ($dateTrend.ContainsKey($d)) { $dateTrend[$d]++ } else { $dateTrend[$d] = 1 }
    }
}
foreach ($e in $errorEntries) {
    if ($e.Date) {
        $d = $e.Date
        if ($dateTrend.ContainsKey($d)) { $dateTrend[$d]++ } else { $dateTrend[$d] = 1 }
    }
}

# Pattern key frequency
$patternCounts = @{}
foreach ($e in $learningEntries) {
    if ($e.Message -match 'Pattern-Key:\s*(.+)') {
        $key = $Matches[1].Trim()
        if ($patternCounts.ContainsKey($key)) { $patternCounts[$key]++ } else { $patternCounts[$key] = 1 }
    }
}

# Top sections
$topSections = $sectionCounts.GetEnumerator() |
    Sort-Object Value -Descending |
    Select-Object -First 10 |
    ForEach-Object { [PSCustomObject]@{ Section = $_.Name; Count = $_.Value } }

# Top patterns
$topPatterns = $patternCounts.GetEnumerator() |
    Sort-Object Value -Descending |
    Select-Object -First 10 |
    ForEach-Object { [PSCustomObject]@{ PatternKey = $_.Name; Count = $_.Value } }

# Trend sorted by date
$trend = $dateTrend.GetEnumerator() |
    Sort-Object Name |
    ForEach-Object { [PSCustomObject]@{ Date = $_.Name; Count = $_.Value } }

# Build result
$result = [PSCustomObject]@{
    Version   = '1.0'
    Timestamp = $timestamp
    Summary   = [PSCustomObject]@{
        TotalLearnings = @($learningEntries).Count
        TotalErrors    = @($errorEntries).Count
        UniqueSections = @($sectionCounts.Keys).Count
        UniquePatterns = @($patternCounts.Keys).Count
        CatalogEntries = $catalogStats.Entries
        CatalogAgeDays = $catalogStats.AgeDays
    }
    TopSections = @($topSections)
    TopPatterns = @($topPatterns)
    Trend       = @($trend)
    Health      = [PSCustomObject]@{
        LearningsActive = @($learningEntries).Count -gt 0
        ErrorsActive    = @($errorEntries).Count -gt 0
        CatalogFresh    = $null -ne $catalogStats.AgeDays -and $catalogStats.AgeDays -lt 30
        PatternDrift    = @($patternCounts.GetEnumerator() | Where-Object { $_.Value -ge 3 }).Count
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 4
} else {
    if (-not $Quiet) {
        Write-Host "=== Learning Stats ==="
        Write-Host "Learnings: $($learningEntries.Count) entries"
        Write-Host "Errors: $($errorEntries.Count) entries"
        Write-Host "Sections: $($sectionCounts.Keys.Count) unique"
        Write-Host "Patterns: $($patternCounts.Keys.Count) unique"
        Write-Host "Catalog: $($catalogStats.Entries) entries (age: $($catalogStats.AgeDays)d)"
        if ($topPatterns.Count -gt 0) {
            Write-Host ""
            Write-Host "Top patterns:"
            foreach ($p in $topPatterns) {
                Write-Host "  $($p.PatternKey): $($p.Count)x"
            }
        }
    }
}

# Cleanup
$learningEntries = $errorEntries = $null
$sectionCounts = $dateTrend = $patternCounts = $null
[GC]::Collect()

