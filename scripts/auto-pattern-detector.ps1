#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Auto-detect repeated patterns and propose new anti-patterns.
.DESCRIPTION
    Scans .learnings/LEARNINGS.md for repeated pattern keys,
    scans docs/metricas/errors/ for repeated error types,
    and proposes new anti-patterns when same error appears 3+ times.
    Outputs JSON for agent consumption.
.PARAMETER Threshold
    Minimum occurrences to flag a pattern (default: 3).
.PARAMETER Json
    Output JSON format (default: true for agent consumption).
.EXAMPLE
    . "$PSScriptRoot\auto-pattern-detector.ps1"
    . "$PSScriptRoot\auto-pattern-detector.ps1" -Threshold 2
#>
param(
    [int]$Threshold = 3,
    [bool]$Json = $true,
    [switch]$Quiet
)

# ponytail: self-learning
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$learningsDir = Join-Path $repoRoot '.learnings'
$learningsFile = Join-Path $learningsDir 'LEARNINGS.md'
$errorsDir = Join-Path (Join-Path (Join-Path $repoRoot 'docs') 'metricas') 'errors'
$catalogFile = Join-Path $repoRoot 'ANTI-PATTERN-CATALOG.md'
$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'

function Get-CatalogedPattern {
    if (-not (Test-Path $catalogFile)) { return @() }
    try {
        $content = Get-Content $catalogFile -Raw -ErrorAction Stop
    } catch {
        Write-Debug "auto-pattern-detector: cannot read catalog ($($_.Exception.Message))"
        return @()
    }
    $patterns = @()
    $rows = [regex]::Matches($content, '^\|\s*\d+\s*\|(?:.*?\|){6}', 'Multiline')
    foreach ($r in $rows) {
        $parts = $r.Value -split '\|' | ForEach-Object { $_.Trim() }
        if ($parts.Count -ge 5) {
            $patterns += $parts[3]
        }
    }
    return $patterns
}

function Get-LearningPatternKey {
    if (-not (Test-Path $learningsFile)) { return @() }
    try {
        $content = Get-Content $learningsFile -Raw -ErrorAction Stop
    } catch {
        Write-Debug "auto-pattern-detector: cannot read learnings ($($_.Exception.Message))"
        return @()
    }
    $keys = @()
    $patternMatches = [regex]::Matches($content, 'Pattern-Key:\s*([^\n\r]+)', 'Multiline')
    foreach ($m in $patternMatches) {
        $keys += $m.Groups[1].Value.Trim()
    }
    return $keys
}

function Get-ErrorEntry {
    $entries = @()
    if (-not (Test-Path $errorsDir)) { return $entries }
    $errorFiles = Get-ChildItem -Path $errorsDir -Filter '*.json' -ErrorAction SilentlyContinue
    foreach ($f in $errorFiles) {
        try {
            $data = Get-Content $f.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($data.errors) {
                foreach ($err in $data.errors) {
                    $entries += [PSCustomObject]@{
                        Source = $f.Name
                        Type   = if ($err.type) { $err.type } else { 'unknown' }
                        Message = if ($err.message) { $err.message } else { "$err" }
                        Timestamp = if ($data.timestamp) { $data.timestamp } else { $f.LastWriteTime.ToString('o') }
                    }
                }
            }
        } catch {
            Write-Debug "auto-pattern-detector: skip $($f.Name) ($($_.Exception.Message))"
        }
    }
    return $entries
}

function Get-LearningEntry {
    $entries = @()
    if (-not (Test-Path $learningsFile)) { return $entries }
    try {
        $lines = [System.IO.File]::ReadLines($learningsFile)
    } catch {
        return $entries
    }
    foreach ($line in $lines) {
        if ($line.StartsWith('|') -and -not $line.StartsWith('| Timestamp')) {
            $parts = $line.Split('|')
            if ($parts.Count -ge 4) {
                $entries += [PSCustomObject]@{
                    Timestamp = $parts[1].Trim()
                    Section   = $parts[2].Trim()
                    Message   = $parts[3].Trim()
                }
            }
        }
    }
    return $entries
}

# --- Main logic ---
$catalogedPatterns = Get-CatalogedPattern
$learningKeys = Get-LearningPatternKey
$errorEntries = Get-ErrorEntry

# Count pattern key occurrences
$keyCounts = @{}
foreach ($key in $learningKeys) {
    if ($keyCounts.ContainsKey($key)) {
        $keyCounts[$key]++
    } else {
        $keyCounts[$key] = 1
    }
}

# Count error type occurrences
$errorTypeCounts = @{}
foreach ($err in $errorEntries) {
    $typeKey = $err.Type
    if ($errorTypeCounts.ContainsKey($typeKey)) {
        $errorTypeCounts[$typeKey]++
    } else {
        $errorTypeCounts[$typeKey] = 1
    }
}

# Find repeated patterns not yet cataloged
$proposals = @()
foreach ($key in $keyCounts.Keys) {
    if ($keyCounts[$key] -ge $Threshold) {
        $isCataloged = $catalogedPatterns | Where-Object { $_ -cmatch [regex]::Escape($key) }
        if (-not $isCataloged) {
            $proposals += [PSCustomObject]@{
                Source      = 'learnings'
                PatternKey  = $key
                Count       = $keyCounts[$key]
                Cataloged   = $false
                Proposal    = "Add to ANTI-PATTERN-CATALOG.md: '$key' appeared $($keyCounts[$key]) times"
            }
        }
    }
}

# Find repeated errors not yet cataloged
foreach ($typeKey in $errorTypeCounts.Keys) {
    if ($errorTypeCounts[$typeKey] -ge $Threshold) {
        $isCataloged = $catalogedPatterns | Where-Object { $_ -cmatch [regex]::Escape($typeKey) }
        if (-not $isCataloged) {
            $proposals += [PSCustomObject]@{
                Source      = 'errors'
                PatternKey  = $typeKey
                Count       = $errorTypeCounts[$typeKey]
                Cataloged   = $false
                Proposal    = "Add to ANTI-PATTERN-CATALOG.md: error type '$typeKey' appeared $($errorTypeCounts[$typeKey]) times"
            }
        }
    }
}

# Build result
$result = [PSCustomObject]@{
    Version       = '1.0'
    Timestamp     = $timestamp
    Threshold     = $Threshold
    Summary       = [PSCustomObject]@{
        LearningKeys      = $keyCounts.Keys.Count
        ErrorTypes        = $errorTypeCounts.Keys.Count
        CatalogedPatterns = $catalogedPatterns.Count
        Proposals         = $proposals.Count
    }
    RepeatedPatterns = foreach ($key in $keyCounts.Keys) {
        if ($keyCounts[$key] -ge 2) {
            [PSCustomObject]@{
                Source     = 'learnings'
                Key        = $key
                Count      = $keyCounts[$key]
                Cataloged  = [bool]($catalogedPatterns | Where-Object { $_ -cmatch [regex]::Escape($key) })
            }
        }
    }
    RepeatedErrors = foreach ($typeKey in $errorTypeCounts.Keys) {
        if ($errorTypeCounts[$typeKey] -ge 2) {
            [PSCustomObject]@{
                Source    = 'errors'
                Type      = $typeKey
                Count     = $errorTypeCounts[$typeKey]
                Cataloged = [bool]($catalogedPatterns | Where-Object { $_ -cmatch [regex]::Escape($typeKey) })
            }
        }
    }
    Proposals = $proposals
    Status    = if ($proposals.Count -gt 0) { 'PATTERNS_FOUND' } else { 'CLEAN' }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 4
} else {
    if (-not $Quiet) {
        Write-Host "=== Auto-Pattern Detector ==="
        Write-Host "Learning keys: $($keyCounts.Keys.Count)"
        Write-Host "Error types: $($errorTypeCounts.Keys.Count)"
        Write-Host "Cataloged patterns: $($catalogedPatterns.Count)"
        Write-Host "Proposals: $($proposals.Count)"
        if ($proposals.Count -gt 0) {
            Write-Host ""
            Write-Host "Proposals:"
            foreach ($p in $proposals) {
                Write-Host "  [$($p.Source)] $($p.Proposal)"
            }
        }
    }
}

# Cleanup
$catalogedPatterns = $learningKeys = $errorEntries = $null
$keyCounts = $errorTypeCounts = $proposals = $null
[GC]::Collect()
