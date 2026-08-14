#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Verify backlog item status matches repo reality.

.DESCRIPTION
  Parses CYCLE.md backlog table and checks each item's status
  against verifiable repo state. Returns 0 = all match, 1 = mismatch.

.PARAMETER RepoRoot
  Root of the repo. Defaults to script parent dir.

.PARAMETER Json
  Output structured JSON for agent consumption.

.EXAMPLE
  .\scripts\check-backlog-integrity.ps1
  .\scripts\check-backlog-integrity.ps1 -Json
#>

param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$results = @{ checks = @(); passed = 0; failed = 0; errors = @() }

function Write-ErrorJson {
    param([string]$Message)
    if ($Json) {
        $results.errors += $Message
        $results.allPassed = $false
        $results.passed = 0
        $results.failed = 0
        $results.totalItems = 0
        $results.score = 0
        $results.timestamp = (Get-Date -Format 'o')
        Write-Output ($results | ConvertTo-Json -Depth 3)
    } else {
        Write-Host $Message
    }
    exit 1
}

function Add-Check {
    param([string]$Item, [bool]$Passed, [string]$Detail)
    $script:results.checks += @{ item = $Item; passed = $Passed; detail = $Detail }
    if ($Passed) { $script:results.passed++ } else { $script:results.failed++ }
}

function Test-CommitExistence {
    param([string]$CommitHash)
    Push-Location $RepoRoot
    try {
        $result = git cat-file -t $CommitHash 2>$null
        return ($result -eq 'commit')
    } finally {
        Pop-Location
    }
}

# Parse backlog table from CYCLE.md
$cyclePath = Join-Path $RepoRoot 'CYCLE.md'
if (-not (Test-Path $cyclePath)) { Write-ErrorJson 'CYCLE.md not found' }

$cycleContent = Get-Content $cyclePath -Raw -Encoding UTF8

# Find active cycle number from "### Status: Cycle N Active"
$activeCycle = if ($cycleContent -match '### Status: Cycle (\d+) Active') { [int]$Matches[1] } else { $null }

# Extract the full active cycle section (from "### Cycle N:" to next "### Cycle" heading)
$tableSection = ''
if ($activeCycle) {
    $start = $cycleContent.IndexOf("### Cycle $activeCycle")
    if ($start -ge 0) {
        # Look for next "### Cycle " heading (any cycle number)
        $nextStart = $cycleContent.IndexOf("### Cycle ", $start + 10)
        if ($nextStart -lt 0) { $nextStart = $cycleContent.Length }
        $tableSection = $cycleContent.Substring($start, $nextStart - $start)
    }
}
# Fallback: content between any "### Backlog" and next "###" heading
if (-not $tableSection) {
    $parts = $cycleContent -split '### Backlog'
    if ($parts.Count -ge 2) {
        $afterBacklog = $parts[1]
        # Clip at next "### " heading
        $clipIdx = $afterBacklog.IndexOf("`n### ")
        if ($clipIdx -ge 0) { $afterBacklog = $afterBacklog.Substring(0, $clipIdx) }
        $tableSection = "### Backlog$afterBacklog"
    }
}

if (-not $tableSection) { Write-ErrorJson 'Backlog table not found in CYCLE.md' }

# Parse pipe-delimited rows (skip header and separator lines)
$rows = $tableSection -split "`n" | Where-Object { $_ -match '^\|' -and $_ -notmatch '^\|[\s-]+\|' }
# Skip header row (contains "Item | Impact | Risk")
$rows = $rows | Where-Object { $_ -notmatch 'Item \| Impact \| Risk' }

$items = @()
foreach ($row in $rows) {
    $cols = $row -split '\|' | ForEach-Object { $_.Trim() }
    # Determine offset: if first col is empty (old format: | Item |... ) offset=1, else offset=2 (new: | # | Item |...)
    $offset = if ($cols.Count -ge 9 -and $cols[0] -eq '' -and $cols[1] -match '^\d+$') { 2 } else { 1 }
    if ($cols.Count -ge (6 + $offset)) {
        $items += @{
            raw          = $row
            description  = $cols[0 + $offset]
            impact       = $cols[1 + $offset]
            risk         = $cols[2 + $offset]
            ir           = $cols[3 + $offset]
            estInter     = $cols[4 + $offset]
            status       = $cols[5 + $offset]
            doneCriteria = if ($cols.Count -ge (7 + $offset)) { $cols[6 + $offset] } else { '' }
        }
    }
}

if ($items.Count -eq 0) { Write-ErrorJson 'No backlog items found' }

# --- Check each item ---
$allPassed = $true

foreach ($item in $items) {
    $desc = $item.description -replace '\s+', ' ' -replace '^\*{0,2}\s*', ''
    $status = $item.status -replace '\s+', ' '
    $criteria = $item.doneCriteria.Trim()

    if ($status -match 'Done|🟢|✅|✔') {
        # Item claims done — verify criteria
        if ($criteria -match 'commit\s+([a-f0-9]{7,})') {
            $commitHash = $Matches[1]
            if (Test-CommitExistence $commitHash) {
                Add-Check -Item $desc -Passed $true -Detail "Done -- commit $commitHash found"
            } else {
                Add-Check -Item $desc -Passed $false -Detail "Done claimed but commit $commitHash not found"
                $allPassed = $false
            }
        } elseif ($criteria -match 'script exists at (.+?)(?:[|]|$)') {
            $scriptPath = $Matches[1].Trim()
            $fullPath = Join-Path $RepoRoot $scriptPath
            if (Test-Path $fullPath) {
                Add-Check -Item $desc -Passed $true -Detail "Done -- script exists at $scriptPath"
            } else {
                Add-Check -Item $desc -Passed $false -Detail "Done claimed but $scriptPath not found"
                $allPassed = $false
            }
        } else {
            Add-Check -Item $desc -Passed $true -Detail "Done (no auto-verifiable criteria)"
        }
    } elseif ($status -match 'Pending|🔴|🟡|🟠') {
        # Item claims pending — verify it's NOT accidentally done
        if ($criteria -match 'script exists at (.+?)(?:[|]|$)') {
            $scriptPath = $Matches[1].Trim()
            $fullPath = Join-Path $RepoRoot $scriptPath
            if (Test-Path $fullPath) {
                Add-Check -Item $desc -Passed $false -Detail "Pending but $scriptPath already exists"
                $allPassed = $false
            } else {
                Add-Check -Item $desc -Passed $true -Detail "Pending -- no premature implementation"
            }
        } else {
            Add-Check -Item $desc -Passed $true -Detail "Pending (no auto-verifiable criteria)"
        }
    } else {
        Add-Check -Item $desc -Passed $false -Detail "Unknown status: $status"
        $allPassed = $false
    }
}

# --- Summary ---
$score = if ($results.passed + $results.failed -gt 0) {
    [math]::Round(($results.passed / ($results.passed + $results.failed)) * 10, 1)
} else { 0 }

$results.score = $score
$results.totalItems = $items.Count
$results.allPassed = $allPassed

if ($Json) {
    $results.timestamp = (Get-Date -Format 'o')
    Write-Output ($results | ConvertTo-Json -Depth 3)
} else {
    Write-Host "`n=== Backlog Integrity ===" -ForegroundColor Cyan
    foreach ($check in $results.checks) {
        $color = if ($check.passed) { 'Green' } else { 'Red' }
        $symbol = if ($check.passed) { 'PASS' } else { 'FAIL' }
        Write-Host "[$symbol] $($check.item)" -NoNewline
        Write-Host " -- $($check.detail)" -ForegroundColor $color
    }
    Write-Host "`nScore: $score/10 ($($results.passed)/$($results.totalItems) items correct)" -ForegroundColor $(if ($allPassed) { 'Green' } else { 'Yellow' })
}

exit $(if ($allPassed) { 0 } else { 1 })
