#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Demote stale patterns and remove unused forged skills.
.DESCRIPTION
    Periodic maintenance for the Pattern Store:
    - Demotes patterns with 0 hits in 90+ days -> deprecated
    - Removes forged skills that haven't been resolved in 14+ days
    - Archives deprecated patterns older than 180 days
.PARAMETER All  Run all checks (demote + remove + archive).
.PARAMETER DemoteOnly  Only check for stale patterns (90d no hits).
.PARAMETER RemoveOnly  Only check for unused forged skills (14d).
.PARAMETER ArchiveOnly  Only archive patterns deprecated >180d.
.PARAMETER DryRun  Report what would change without making changes.
.PARAMETER Quiet  Output JSON only.
.EXAMPLE
    .\scripts\wisdom-demote.ps1 -All
    .\scripts\wisdom-demote.ps1 -DemoteOnly -DryRun
#>
param([switch]$All,[switch]$DemoteOnly,[switch]$RemoveOnly,[switch]$ArchiveOnly,[switch]$DryRun,[switch]$Force,[switch]$Quiet)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$patternsDir = Join-Path (Join-Path (Join-Path $repoRoot "docs") "cross-project") "patterns"
$skillsDir = Join-Path (Join-Path $repoRoot ".agents") "skills"
$archivedDir = Join-Path (Join-Path (Join-Path $repoRoot "docs") "cross-project") "archived"
$runAll = $All -or (-not $DemoteOnly -and -not $RemoveOnly -and -not $ArchiveOnly)
$changes = @()

# Pre-build pattern index for O(1) lookups (avoids N+1 full scans)
$patternIndex = @{}
if (Test-Path $patternsDir) {
    foreach ($pf in @(Get-ChildItem $patternsDir -Filter "*.json")) {
        try { $pp = Get-Content $pf.FullName -Raw | ConvertFrom-Json; if ($pp.id) { $patternIndex[$pp.id] = $pf.FullName } } catch { Write-Debug "wisdom-demote: $($_.Exception.Message)" }
    }
}

# 1. Demote stale patterns (90d no hits)
if ($runAll -or $DemoteOnly) {
    if (-not (Test-Path $patternsDir)) { if (-not $Quiet) { Write-Host "[SKIP] No patterns directory" } }
    else {
        $now = Get-Date
        foreach ($file in @(Get-ChildItem $patternsDir -Filter "*.json")) {
            try { $p = Get-Content $file.FullName -Raw | ConvertFrom-Json } catch { continue }
            $status = if ($p.status) { $p.status } else { "active" }
            if ($status -ne "active") { continue }
            $updatedStr = if ($p.updated) { $p.updated } else { $p.created }
            if (-not $updatedStr) { continue }
            $updatedDate = try { [DateTime]::ParseExact($updatedStr, "yyyy-MM-dd", $null) } catch { continue }
            $days = ($now - $updatedDate).Days
            $hits = if ($p.hits) { [int]$p.hits } else { 0 }
            if ($days -ge 90 -and $hits -eq 0) {
                if ($DryRun) { $changes += @{Action="DEMOTE_DRYRUN";Target=$p.id;Reason="No hits in $days days (>=90)"}; if (-not $Quiet) { Write-Host "  [DRY] Would demote: $($p.id)" } }
                else { $p|Add-Member -NotePropertyName "status" -NotePropertyValue "deprecated" -Force; $p|Add-Member -NotePropertyName "deprecated_at" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force; $p|ConvertTo-Json -Depth 6|Set-Content $file.FullName -Encoding UTF8; $changes += @{Action="DEMOTED";Target=$p.id;Reason="No hits in $days days (>=90)"}; if (-not $Quiet) { Write-Host "  [->] Demoted: $($p.id) -> deprecated" } }
            }
        }
        if (-not $Quiet) { $cnt = @($changes|Where-Object{$_.Action-like"DEMOT*"}).Length; Write-Host "[$cnt] stale pattern(s) processed" }
    }
}

# 2. Remove unused forged skills (14d no resolution)
if ($runAll -or $RemoveOnly) {
    $now = Get-Date
    foreach ($skillDir in @(Get-ChildItem $skillsDir -Directory|Where-Object{$_.Name-like"cross-project-*"})) {
        $skillFile = Join-Path $skillDir.FullName "SKILL.md"
        if (-not (Test-Path $skillFile)) { continue }
        $days = ($now - $skillDir.LastWriteTime).Days
        if ($days -lt 14) { continue }
        $src = ""; $sc = Get-Content $skillFile -Raw
        if ($sc -match 'source_pattern:\s*"([^"]+)"') { $src = $Matches[1] }
        if ($DryRun) { $changes += @{Action="REMOVE_DRYRUN";Target=$skillDir.Name;Reason="Not resolved in $days days (>=14)";SourcePattern=$src}; if (-not $Quiet) { Write-Host "  [DRY] Would remove: $($skillDir.Name)" } }
        else {
            # Safety guard: never delete a forged skill that an ACTIVE pattern still references,
            # unless the caller explicitly overrides with -Force (C4 gating real).
            if ($src -and $patternIndex.ContainsKey($src)) {
                $sp = Get-Content $patternIndex[$src] -Raw | ConvertFrom-Json
                if ($sp.status -eq 'active' -and -not $Force) {
                    $changes += @{Action="REMOVE_SKIPPED";Target=$skillDir.Name;Reason="Pattern active ($src) references this skill; use -Force to override"}
                    if (-not $Quiet) { Write-Host "  [SKIP] $($skillDir.Name): active pattern $src references it (use -Force)" }
                    continue
                }
            }
            Remove-Item -Recurse -Force $skillDir.FullName
            $changes += @{Action="REMOVED";Target=$skillDir.Name;Reason="Not resolved in $days days (>=14)";SourcePattern=$src}
            if ($src -and $patternIndex.ContainsKey($src)) {
                $sp = Get-Content $patternIndex[$src] -Raw | ConvertFrom-Json
                $sp | Add-Member -NotePropertyName "status" -NotePropertyValue "active" -Force
                $sp | Add-Member -NotePropertyName "skill_ref" -NotePropertyValue $null -Force
                $sp | Add-Member -NotePropertyName "updated" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
                $sp | ConvertTo-Json -Depth 6 | Set-Content $patternIndex[$src] -Encoding UTF8
                $changes += @{Action="DEMOTED";Target=$src;Reason="Rollback: forged skill removed (unused)"}
            }
            if (-not $Quiet) { Write-Host "  [X] Removed: $($skillDir.Name) (unused $days days)" }
        }
    }
    if (-not $Quiet) { $cnt = @($changes|Where-Object{$_.Action-like"REMOVE*"}).Length; Write-Host "[$cnt] unused forged skill(s) processed" }
}

# 3. Archive deprecated patterns >180d
if ($runAll -or $ArchiveOnly) {
    $now = Get-Date
    if (-not (Test-Path $archivedDir) -and -not $DryRun) { New-Item -ItemType Directory -Path $archivedDir -Force | Out-Null }
    $pFiles = if (Test-Path $patternsDir) { @(Get-ChildItem $patternsDir -Filter "*.json") } else { @() }
    foreach ($file in $pFiles) {
        try { $p = Get-Content $file.FullName -Raw | ConvertFrom-Json } catch { continue }
        $status = if ($p.status) { $p.status } else { "active" }
        if ($status -ne "deprecated") { continue }
        $depStr = if ($p.deprecated_at) { $p.deprecated_at } else { $p.updated }
        if (-not $depStr) { continue }
        $depDate = try { [DateTime]::ParseExact($depStr, "yyyy-MM-dd", $null) } catch { continue }
        $days = ($now - $depDate).Days
        if ($days -ge 180) {
            if ($DryRun) { $changes += @{Action="ARCHIVE_DRYRUN";Target=$p.id;Reason="Deprecated $days days (>=180)"}; if (-not $Quiet) { Write-Host "  [DRY] Would archive: $($p.id)" } }
            else { Move-Item -Path $file.FullName -Destination (Join-Path $archivedDir $file.Name) -Force; $changes += @{Action="ARCHIVED";Target=$p.id;Reason="Deprecated $days days (>=180)"}; if (-not $Quiet) { Write-Host "  [->] Archived: $($p.id) -> archived/" } }
        }
    }
    if (-not $Quiet) { $cnt = @($changes|Where-Object{$_.Action-like"ARCHIVE*"}).Length; Write-Host "[$cnt] archived pattern(s) processed" }
}

# Output
$result = [PSCustomObject]@{Status=if($changes.Length-gt 0){"CHANGES"}else{"CLEAN"};TotalChanges=@($changes).Length;Changes=@($changes);Timestamp=(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ");DryRun=$DryRun.IsPresent}
if ($Quiet -or $changes.Length -gt 0) { $result | ConvertTo-Json -Depth 3 }
elseif (-not $Quiet) { Write-Host "`n[OK] Store is clean -- no stale patterns or unused skills" }
