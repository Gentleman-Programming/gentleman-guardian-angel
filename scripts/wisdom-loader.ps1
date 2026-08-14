#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Load and rank cross-project patterns matching current task context.
.DESCRIPTION
    Reads all patterns from docs/cross-project/patterns/,
    ranks them by relevance to the given domain/technologies/keywords,
    and returns top N results with scores.
.PARAMETER Domain
    Filter by domain (ux, css, security, ps, etc.).
.PARAMETER Technology
    Filter by technology (comma-separated: gradient,playwright,theme).
.PARAMETER Keywords
    Search keywords (comma-separated: contrast,footer,btn).
.PARAMETER Severity
    Minimum severity filter (CRITICAL, HIGH, MEDIUM, LOW). Default: LOW.
.PARAMETER Limit
    Max patterns to return (default: 5).
.PARAMETER Json
    Output JSON (default for agent consumption).
.EXAMPLE
    .\scripts\wisdom-loader.ps1 -Domain ux
    .\scripts\wisdom-loader.ps1 -Technology "gradient,playwright" -Limit 3
    .\scripts\wisdom-loader.ps1 -Keywords "contrast,button" -Severity HIGH
#>
param(
    [string]$Domain = "",
    [string]$Technology = "",
    [string]$Keywords = "",
    [string]$Severity = "LOW",
    [int]$Limit = 5,
    [bool]$Json = $true
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$patternsDir = Join-Path (Join-Path $repoRoot "docs") "cross-project" "patterns"

if (-not (Test-Path $patternsDir)) {
    $result = [PSCustomObject]@{ Status = "NO_STORE"; Patterns = @(); Count = 0 }
    if ($Json) { return $result | ConvertTo-Json }
    Write-Host "Pattern store not found: $patternsDir"
    exit 0
}

$patternFiles = @(Get-ChildItem $patternsDir -Filter "*.json")
if ($patternFiles.Length -eq 0) {
    $result = [PSCustomObject]@{ Status = "EMPTY"; Patterns = @(); Count = 0 }
    if ($Json) { return $result | ConvertTo-Json }
    Write-Host "[OK] No patterns in store"
    exit 0
}

# Parse params
$techList = [string[]]@()
if ($Technology -and $Technology.Trim()) { $techList = @($Technology -split ',' | ForEach-Object { $_.Trim().ToLower() }) }
$keywordList = [string[]]@()
if ($Keywords -and $Keywords.Trim()) { $keywordList = @($Keywords -split ',' | ForEach-Object { $_.Trim().ToLower() }) }
$sevOrder = @{ "LOW" = 0; "MEDIUM" = 1; "HIGH" = 2; "CRITICAL" = 3 }
$minSev = if ($sevOrder.ContainsKey($Severity)) { $sevOrder[$Severity] } else { 0 }

$scoredPatterns = [System.Collections.ArrayList]@()

foreach ($file in $patternFiles) {
    try {
        $pattern = Get-Content $file.FullName -Raw | ConvertFrom-Json
    } catch { continue }

    $score = 0.0
    $matchReasons = @()

    # Domain match (weight: 0.35)
    if ($Domain -and $pattern.domain -eq $Domain) {
        $score += 0.35
        $matchReasons += "domain:$($pattern.domain)"
    } elseif ($Domain -and $pattern.domain -ne $Domain) {
        # Subdomain partial match
        if ($pattern.subdomain -and $pattern.subdomain -match $Domain) {
            $score += 0.15
            $matchReasons += "domain:substring"
        }
    }

    # Technology match (weight: 0.25)
    $hasTechList = $null -ne $techList -and $techList.Length -gt 0
    if ($hasTechList -and $null -ne $pattern.context -and $null -ne $pattern.context.technologies) {
        $techMatch = @($techList | Where-Object {
            $tc = $_; $found = $false
            foreach ($pt in $pattern.context.technologies) { if ($pt -match [regex]::Escape($tc)) { $found = $true; break } }
            $found
        })
        if ($techMatch.Length -gt 0) {
            $score += 0.25 * ([Math]::Min($techMatch.Length, 3) / 3)
            $matchReasons += "tech:$($techMatch -join ',')"
        }
    }

    # Keyword match in tags/title/signal (weight: 0.25)
    if ($keywordList.Length -gt 0) {
        $searchText = @(
            $pattern.title
            if ($pattern.tags) { $pattern.tags -join ' ' }
            if ($pattern.signal) { $pattern.signal.keywords -join ' ' }
            if ($pattern.rule -and $pattern.rule.summary) { $pattern.rule.summary }
        ) -join ' ' | ForEach-Object { $_.ToLower() }

        $kwMatch = $keywordList | Where-Object { $searchText -match [regex]::Escape($_) }
        if ($null -ne $kwMatch) {
            $matchCount = @($kwMatch).Length
            $score += 0.25 * ([Math]::Min($matchCount, 5) / 5)
            $matchReasons += "kw:$(@($kwMatch) -join ',')"
        }
    }

    # Confidence boost (weight: 0.1)
    if ($pattern.confidence) {
        $score += 0.10 * $pattern.confidence
    }

    # Severity boost (weight: 0.05)
    if ($pattern.severity -and $sevOrder.ContainsKey($pattern.severity)) {
        $sevScore = $sevOrder[$pattern.severity] / 3  # 0 to 1
        $score += 0.05 * $sevScore
    }

    # Filter by severity minimum
    $patternSev = if ($sevOrder.ContainsKey($pattern.severity)) { $sevOrder[$pattern.severity] } else { 0 }
    if ($patternSev -lt $minSev) { continue }

    $scoredPatterns += [PSCustomObject]@{
        Id        = $pattern.id
        Title     = $pattern.title
        Domain    = $pattern.domain
        Subdomain = $pattern.subdomain
        Severity  = $pattern.severity
        Confidence = if ($pattern.confidence) { $pattern.confidence } else { 0.0 }
        Score     = [Math]::Round($score, 3)
        MatchReasons = $matchReasons
        Summary   = if ($pattern.rule -and $pattern.rule.summary) { $pattern.rule.summary } else { "" }
        Fix       = if ($pattern.rule -and $pattern.rule.fix) { $pattern.rule.fix } else { "" }
        Check     = if ($pattern.rule -and $pattern.rule.check) { $pattern.rule.check } else { "" }
        File      = $file.Name
        Hits      = if ($pattern.hits) { $pattern.hits } else { 0 }
    }
}

# Sort by score descending, limit
$topPatternsArray = @($scoredPatterns | Sort-Object Score -Descending | Select-Object -First $Limit)
$topCount = $topPatternsArray.Length

$result = [PSCustomObject]@{
    Status      = if ($topCount -gt 0) { "MATCH" } else { "NO_MATCH" }
    TotalStore  = $patternFiles.Length
    TotalScored = @($scoredPatterns).Length
    Count       = $topCount
    Patterns    = $topPatternsArray
    Query       = [PSCustomObject]@{
        Domain     = $Domain
        Technology = $Technology
        Keywords   = $Keywords
        Severity   = $Severity
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} else {
    $patCount = @($scoredPatterns).Length
    Write-Host "=== Wisdom Loader ==="
    Write-Host "Store: $($patternFiles.Length) patterns | Scored: $patCount | Top: $topCount"
    if ($topCount -gt 0) {
        Write-Host ""
        Write-Host "Top patterns:"
        foreach ($p in $topPatternsArray) {
            Write-Host "  [$($p.Severity)] $($p.Title) (score: $($p.Score))"
            Write-Host "    $($p.Summary)"
            if ($null -ne $p.MatchReasons -and @($p.MatchReasons).Length -gt 0) {
                Write-Host "    matches: $($p.MatchReasons -join ', ')"
            }
        }
    } else {
        Write-Host "[INFO] No matching patterns found"
    }
}
