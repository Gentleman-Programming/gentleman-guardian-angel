#requires -Version 7
<#
.SYNOPSIS
    Save or migrate a cross-project pattern to the Pattern Store + Engram.
.DESCRIPTION
    Validates pattern fields, writes to docs/cross-project/patterns/,
    and returns the Engram-ready payload for the agent to mem_save.
    Supports bulk migration from backlog/ directory.
.PARAMETER PatternFile
    Single JSON file to migrate (from backlog/ or manual create).
.PARAMETER MigrateBacklog
    Migrate ALL .json files from backlog/ to patterns/ with auto-ID.
.PARAMETER Category
    Override category for migrated patterns (domain/subdomain).
.PARAMETER DryRun
    Preview actions without modifying any files.
.PARAMETER Force
    Skip confirmation prompts during migration.
.PARAMETER Quiet
    Output JSON only (machine-readable).
.EXAMPLE
    .\scripts\wisdom-store.ps1 -PatternFile "docs/cross-project/backlog/my-pattern.json" -DryRun
.EXAMPLE
    .\scripts\wisdom-store.ps1 -MigrateBacklog
.EXAMPLE
    Get-ChildItem "docs/cross-project/backlog/*.json" | ForEach-Object {
        .\scripts\wisdom-store.ps1 -PatternFile $_.FullName
    }
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PatternFile = "",
    [switch]$MigrateBacklog,
    [string]$Category = "",
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Quiet
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$patternsDir = Join-Path (Join-Path (Join-Path $repoRoot "docs") "cross-project") "patterns"
$backlogDir = Join-Path (Join-Path (Join-Path $repoRoot "docs") "cross-project") "backlog"

# Ensure patterns dir exists
if (-not (Test-Path $patternsDir)) {
    if (-not $Quiet) { Write-Warning "Patterns directory not found: $patternsDir" }
    exit 1
}

# Pre-build pattern index for O(1) duplicate lookups (avoids N+1)
$script:patternIndex = @{}
if (Test-Path $patternsDir) {
    foreach ($ixf in @(Get-ChildItem $patternsDir -Filter "*.json")) {
        try { $ixp = Get-Content $ixf.FullName -Raw | ConvertFrom-Json; if ($ixp.title) { $script:patternIndex[$ixp.title.ToLower()] = $ixf.FullName } } catch { Write-Debug "wisdom-store: $($_.Exception.Message)" }
    }
}

function New-PatternId {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Domain, [string]$Subdomain, [string]$Title)
    $slug = ($Title -replace '[^a-zA-Z0-9\s-]', '' -replace '\s+', '-' -replace '--+', '-').ToLower()
    $slug = $slug.Substring(0, [Math]::Min(40, $slug.Length)) -replace '-+$', ''
    $patternId = "$Domain-$Subdomain-$slug"
    if ($PSCmdlet.ShouldProcess($patternId, 'Generate pattern id')) {
        return $patternId
    }
    return $null
}

function Test-Pattern {
    param([PSCustomObject]$Pattern)
    $errors = @()
    if (-not $Pattern.title) { $errors += "Missing 'title'" }
    if (-not $Pattern.domain) { $errors += "Missing 'domain'" }
    if (-not $Pattern.rule) { $errors += "Missing 'rule'" }
    if (-not $Pattern.rule.summary) { $errors += "Missing 'rule.summary'" }
    return $errors
}

function Save-Pattern {
    param([PSCustomObject]$Pattern)
    $domain = $Pattern.domain
    $subdomain = $Pattern.subdomain
    $id = New-PatternId -Domain $domain -Subdomain $subdomain -Title $Pattern.title
    $Pattern | Add-Member -NotePropertyName "id" -NotePropertyValue $id -Force
    $Pattern | Add-Member -NotePropertyName "status" -NotePropertyValue "active" -Force
    $hasCreated = $null -ne ($Pattern.PSObject.Properties['created'])
    if (-not $hasCreated) {
        $Pattern | Add-Member -NotePropertyName "created" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    }
    $Pattern | Add-Member -NotePropertyName "updated" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    $filename = "$id.json"
    $filepath = Join-Path $patternsDir $filename
    # Check for duplicate by title (O(1) hash lookup vs N+1 scan)
    $titleKey = "$($Pattern.title)".ToLower()
    if ([string]::IsNullOrWhiteSpace($titleKey)) { $titleKey = $id.ToLower() }
    $existingPath = $script:patternIndex[$titleKey]
    if (-not $existingPath) {
        # Fallback: fuzzy match against full index (catches near-duplicates)
        foreach ($ek in $script:patternIndex.Keys) {
            if ($ek -match [regex]::Escape($titleKey) -or $titleKey -match [regex]::Escape($ek)) {
                $existingPath = $script:patternIndex[$ek]; break
            }
        }
    }
    if ($existingPath -and (Test-Path $existingPath)) {
        if (-not $Quiet) { Write-Warning "Pattern already exists: $existingPath (same title)" }
        $oldContent = Get-Content $existingPath -Raw | ConvertFrom-Json
        $oldContent.updated = (Get-Date -Format "yyyy-MM-dd")
        $hasHits = $null -ne ($Pattern.PSObject.Properties['hits'])
        if ($hasHits -and $Pattern.hits) { $oldContent.hits = [int]$oldContent.hits + [int]$Pattern.hits }
        $oldContent | ConvertTo-Json -Depth 6 | Set-Content $existingPath -Encoding UTF8
        return @{ Action = "updated"; Path = $existingPath; Id = $id }
    }
    # New pattern
    $Pattern | ConvertTo-Json -Depth 6 | Set-Content $filepath -Encoding UTF8
    # Update index for backlog migration (prevents stale index overwrites)
    $script:patternIndex[$titleKey] = $filepath
    foreach ($altKey in @($id.ToLower(), $filename)) { $script:patternIndex[$altKey] = $filepath }
    return @{ Action = "created"; Path = $filepath; Id = $id }
}

# --- Main ---
$results = @()
if ($MigrateBacklog) {
    if (-not (Test-Path $backlogDir)) {
        if (-not $Quiet) { Write-Warning "Backlog directory not found: $backlogDir" }
        exit 1
    }
    $backlogFiles = @(Get-ChildItem $backlogDir -Filter "*.json")
    if ($backlogFiles.Length -eq 0) {
        if (-not $Quiet) { Write-Host "[OK] No backlog files to migrate" }
        exit 0
    }
    foreach ($file in $backlogFiles) {
        try {
            $pattern = Get-Content $file.FullName -Raw | ConvertFrom-Json
            if ($Category) {
                $parts = $Category -split '/'
                if (@($parts).Length -ge 2) {
                    $pattern | Add-Member -NotePropertyName "domain" -NotePropertyValue $parts[0] -Force
                    $pattern | Add-Member -NotePropertyName "subdomain" -NotePropertyValue $parts[1] -Force
                }
            }
            $errors = @(Test-Pattern $pattern)
            if ($errors.Length -gt 0) {
                $results += @{ File = $file.Name; Status = "invalid"; Errors = $errors }
                if (-not $Quiet) { Write-Warning "Skipping $($file.Name): $($errors -join '; ')" }
                continue
            }
            $result = Save-Pattern $pattern
            # Compute save outcome BEFORE any destructive step (avoids stale $result across iterations)
            $rAction = if ($result -and $result.ContainsKey('Action')) { $result.Action } else { "unknown" }
            $rId = if ($result -and $result.ContainsKey('Id')) { $result.Id } else { "" }
            $rPath = if ($result -and $result.ContainsKey('Path')) { $result.Path } else { "" }
            # Remove from backlog — only if save fully succeeded, or user forced (-Force)
            if ($DryRun) {
                Write-Output "[DryRun] Would delete: $($file.FullName)"
            } elseif ($rAction -in @("created", "updated")) {
                Remove-Item $file.FullName -Force
            } elseif ($Force) {
                Remove-Item $file.FullName -Force
                if (-not $Quiet) { Write-Warning "[Force] Deleted backlog despite failed save: $($file.Name)" }
            } else {
                if (-not $Quiet) { Write-Warning "Backlog preserved (save failed): $($file.Name) — retry or use -Force to delete anyway" }
                $results += @{ File = $file.Name; Status = "preserved"; Id = $rId; Path = $rPath }
                continue
            }
            $results += @{ File = $file.Name; Status = $rAction; Id = $rId; Path = $rPath }
            if (-not $Quiet) { Write-Host "[$($result.Action)] $($result.Id)" }
        } catch {
            $results += @{ File = $file.Name; Status = "error"; Error = $_.Exception.Message }
            if (-not $Quiet) { Write-Warning "Error processing $($file.Name): $_" }
        }
    }
} elseif ($PatternFile) {
    if (-not (Test-Path $PatternFile)) { Write-Error "Pattern file not found: $PatternFile"; exit 1 }
    try {
        $pattern = Get-Content $PatternFile -Raw | ConvertFrom-Json
        $errors = @(Test-Pattern $pattern)
        if ($errors.Length -gt 0) { Write-Error "Validation: $($errors -join '; ')"; exit 1 }
        $result = Save-Pattern $pattern
        $results += $result
        if (-not $Quiet) { Write-Host "[$($result.Action)] $($result.Id)" }
    } catch { Write-Error "Error: $_"; exit 1 }
} else {
    # Read from pipeline - accept JSON via stdin
    try {
        $inputJson = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($inputJson)) {
            Write-Error "Usage: wisdom-store.ps1 -PatternFile <path> | -MigrateBacklog | pipe JSON"
            exit 1
        }
        $pattern = $inputJson | ConvertFrom-Json
        $errors = @(Test-Pattern $pattern)
        if ($errors.Length -gt 0) { Write-Error "Validation: $($errors -join '; ')"; exit 1 }
        $result = Save-Pattern $pattern
        if ($result) { $results += $result }
        if (-not $Quiet) { Write-Host "[$($result.Action)] $($result.Id)" }
    } catch { Write-Error "Error: $_"; exit 1 }
}

$resultsArray = @($results)
$output = [PSCustomObject]@{
    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    Script    = "wisdom-store"
    Total     = $resultsArray.Length
    Results   = $resultsArray
}
$output | ConvertTo-Json -Depth 4
