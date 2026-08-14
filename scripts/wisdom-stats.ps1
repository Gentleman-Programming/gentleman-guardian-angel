#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Wisdom store metrics: pattern count, severity distribution, hit rates.
.DESCRIPTION
    Analyzes the cross-project Pattern Store and outputs metrics.
    Reads all patterns from docs/cross-project/patterns/ and computes stats.
.PARAMETER Json
    Output JSON (default: true for agent consumption).
.PARAMETER Trend
    Compare with previous stats snapshot (if available).
.EXAMPLE
    .\scripts\wisdom-stats.ps1
    .\scripts\wisdom-stats.ps1 -Json
#>
param(
    [bool]$Json = $true,
    [switch]$Trend
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$patternsDir = Join-Path (Join-Path (Join-Path $repoRoot "docs") "cross-project") "patterns"

$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

if (-not (Test-Path $patternsDir)) {
    $result = [PSCustomObject]@{
        Timestamp = $timestamp
        Status    = "NO_STORE"
    }
    if ($Json) { return $result | ConvertTo-Json }
    Write-Host "Pattern store not found at $patternsDir"
    exit 0
}

$patternFiles = Get-ChildItem $patternsDir -Filter "*.json"
if ($patternFiles.Count -eq 0) {
    $result = [PSCustomObject]@{
        Timestamp = $timestamp
        Status    = "EMPTY"
        Total     = 0
    }
    if ($Json) { return $result | ConvertTo-Json }
    Write-Host "[OK] No patterns in store"
    exit 0
}

$patterns = @()
$errors = @()
foreach ($file in $patternFiles) {
    try {
        $p = Get-Content $file.FullName -Raw | ConvertFrom-Json
        $patterns += $p
    } catch {
        $errors += $file.Name
    }
}

# Severity distribution
$sevDist = @{}
foreach ($p in $patterns) {
    $s = if ($p.severity) { $p.severity.ToUpper() } else { "UNKNOWN" }
    if ($sevDist.ContainsKey($s)) { $sevDist[$s]++ } else { $sevDist[$s] = 1 }
}

# Domain distribution
$domainDist = @{}
foreach ($p in $patterns) {
    $d = if ($p.domain) { $p.domain } else { "unknown" }
    if ($domainDist.ContainsKey($d)) { $domainDist[$d]++ } else { $domainDist[$d] = 1 }
}

# Status distribution
$statusDist = @{}
foreach ($p in $patterns) {
    $s = if ($p.status) { $p.status } else { "unknown" }
    if ($statusDist.ContainsKey($s)) { $statusDist[$s]++ } else { $statusDist[$s] = 1 }
}

# Confidence stats
$confidences = $patterns | Where-Object { $_.confidence -ne $null } | ForEach-Object { [double]$_.confidence }
$avgConfidence = if ($confidences.Count -gt 0) { [Math]::Round(($confidences | Measure-Object -Average).Average, 3) } else { 0 }

# Hit stats
$hits = $patterns | Where-Object { $_.hits -ne $null } | ForEach-Object { [int]$_.hits }
$totalHits = if ($hits.Count -gt 0) { ($hits | Measure-Object -Sum).Sum } else { 0 }

# Age stats
$now = Get-Date
$ages = @()
foreach ($p in $patterns) {
    if ($p.created) {
        try {
            $created = [DateTime]::ParseExact($p.created, "yyyy-MM-dd", $null)
            $ageDays = ($now - $created).Days
            $ages += $ageDays
        } catch {
            Write-Debug "wisdom-stats: Could not parse date '$($p.created)' for pattern"
        }
    }
}
$avgAgeDays = if ($ages.Count -gt 0) { [Math]::Round(($ages | Measure-Object -Average).Average, 0) } else { 0 }

$result = [PSCustomObject]@{
    Timestamp = $timestamp
    Status    = "OK"
    Total     = $patterns.Count
    Errors    = $errors.Count
    ErrorFiles = $errors

    SeverityDistribution = $sevDist
    DomainDistribution   = $domainDist
    StatusDistribution   = $statusDist

    AvgConfidence   = $avgConfidence
    TotalHits       = $totalHits
    AvgAgeDays      = $avgAgeDays

    RecentlyUpdated = @($patterns | Where-Object {
        $_.updated -and (([DateTime]::Now - [DateTime]::ParseExact($_.updated, "yyyy-MM-dd", $null)).Days -le 7)
    }).Count
}

# Trend: compare with previous snapshot (if available), then persist current.
if ($Trend) {
    $snapDir = Join-Path (Join-Path $repoRoot "docs\metricas") "snapshots"
    $snapFile = Join-Path $snapDir "LATEST_wisdom_stats.json"
    $prev = $null
    if (Test-Path $snapFile) {
        try { $prev = Get-Content $snapFile -Raw | ConvertFrom-Json } catch { $prev = $null }
    }
    if ($prev -and $prev.Status -eq "OK") {
        $result | Add-Member -NotePropertyName Previous -NotePropertyValue $prev
        $result | Add-Member -NotePropertyName TotalDelta -NotePropertyValue ($result.Total - $prev.Total)
        $result | Add-Member -NotePropertyName HitsDelta -NotePropertyValue ($result.TotalHits - $prev.TotalHits)
    } else {
        $result | Add-Member -NotePropertyName Previous -NotePropertyValue $null
    }
    if (-not (Test-Path $snapDir)) { New-Item -ItemType Directory -Path $snapDir -Force | Out-Null }
    $result | ConvertTo-Json -Depth 4 | Set-Content -Path $snapFile -Encoding utf8
}

if ($Json) {
    $result | ConvertTo-Json -Depth 4
} else {
    Write-Host "=== Wisdom Store Stats ==="
    Write-Host "Total patterns: $($patterns.Count)"
    Write-Host "Severity: " -NoNewline
    foreach ($kv in $sevDist.GetEnumerator() | Sort-Object Name) {
        Write-Host "$($kv.Key)=$($kv.Value) " -NoNewline
    }
    Write-Host ""
    Write-Host "Domains: " -NoNewline
    foreach ($kv in $domainDist.GetEnumerator() | Sort-Object Name) {
        Write-Host "$($kv.Key)=$($kv.Value) " -NoNewline
    }
    Write-Host ""
    Write-Host "Avg confidence: $avgConfidence"
    Write-Host "Total hits: $totalHits"
    Write-Host "Avg age: $avgAgeDays days"
    Write-Host "Recently updated: $($result.RecentlyUpdated)"
    Write-Host "Errors: $($errors.Count)"
    if ($errors.Count -gt 0) {
        Write-Host "  Failed files: $($errors -join ', ')"
    }
}
