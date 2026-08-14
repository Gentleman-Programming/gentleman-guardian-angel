#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

<#
.SYNOPSIS
  Run cross-session pattern extraction via Engram
.DESCRIPTION
  Executes the dreaming process: searches Engram for error/bugfix patterns,
  consolidates learnings, and updates LEARNINGS.md / ERRORS.md.
.PARAMETER Mode
  Modo de ejecución: full (complete cycle), quick (summary only), report (default).
#>
param(
    [ValidateSet('full','quick','report','feed')]
    [string]$Mode = 'report',
    [switch]$Quiet,
    [string]$OutputPath = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot;trap{[GC]::Collect();break}
$learningsDir = Join-Path $repoRoot '.learnings'
$logFile = Join-Path $learningsDir 'LEARNINGS.md'
$errorFile = Join-Path $learningsDir 'ERRORS.md'
$catalogFile = Join-Path $repoRoot 'ANTI-PATTERN-CATALOG.md'
$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
$cycleId = "DRM-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

if (-not (Test-Path $learningsDir)) {
    New-Item -ItemType Directory -Path $learningsDir -Force | Out-Null
}

function Write-LogMessage {
    param([string]$Section, [string]$Message)
    $line = "| $timestamp | $cycleId | $Section | $Message |"
    try {
        Add-Content -Path $logFile -Value $line
    } catch {
        Write-Debug "dreaming: Write-LogMessage failed ($($_.Exception.Message))"
    }
}

function Test-ShouldSkipLine {
    param([string]$Line)
    return ($null -eq $Line) -or (-not $Line.StartsWith('|')) -or $Line.StartsWith('| Timestamp')
}

function Get-ErrorPattern {
    param([string]$Path)
    $errorCounts = @{}
    if (Test-Path $Path) {
        foreach ($line in [System.IO.File]::ReadLines($Path)) {
            if (-not (Test-ShouldSkipLine $line)) {
                $parts = $line.Split('|')
                if ($parts.Count -ge 4) {
                    $errText = $parts[3].Trim()
                    $key = $errText -replace '\[.*?\]',''
                    $key = $key -replace '\s+',' '
                    $key = $key -replace '^error[:\s]+',''
                    $key = $key -replace '^fix[:\s]+',''
                    if ($key.Length -gt 3) {
                        if ($errorCounts.ContainsKey($key)) {
                            $val = $errorCounts[$key]
                            $val.Count = $val.Count + 1
                            $val.Lines = $val.Lines + @($line)
                        } else {
                            $errorCounts[$key] = @{
                                Text = $errText
                                Count = 1
                                Lines = @($line)
                            }
                        }
                    }
                }
            }
        }
    }
    return $errorCounts
}

function Get-LearningPattern {
    param([string]$Path)
    $learningCounts = @{}
    if (Test-Path $Path) {
        foreach ($line in [System.IO.File]::ReadLines($Path)) {
            if (-not (Test-ShouldSkipLine $line)) {
                $parts = $line.Split('|')
                if ($parts.Count -ge 4) {
                    $section = $parts[2].Trim()
                    $msg = $parts[3].Trim()
                    $key = "$section/$msg"
                    if ($learningCounts.ContainsKey($key)) {
                        $val = $learningCounts[$key]
                        $val.Count = $val.Count + 1
                    } else {
                        $learningCounts[$key] = @{
                            Section = $section
                            Message = $msg
                            Count = 1
                        }
                    }
                }
            }
        }
    }
    return $learningCounts
}

function Get-RepeatedPattern {
    param($Counts, [int]$Threshold = 2)
    $result = @()
    foreach ($key in $Counts.Keys) {
        $entry = $Counts[$key]
        if ($entry.Count -ge $Threshold) {
            $result += $entry
        }
    }
    return $result
}

if(-not $Quiet){Write-Host "=== Dreaming Session: $cycleId ==="}
if(-not $Quiet){Write-Host "Mode: $Mode"}

# ---- Pre-initialize all mode-scoped variables (avoid Set-StrictMode crash) ----
$learningCounts = @{}; $workflowPatterns = @(); $feedPatterns = @(); $errorCounts = @{}; $repeated = @()

# ---- Quick scan (error pattern check) ----
if ($Mode -in 'quick','full','report') {
    if(-not $Quiet){Write-Host '[1/3] Scanning error patterns...'}

    $errorCounts = Get-ErrorPattern -Path $errorFile
    $repeated = @(Get-RepeatedPattern -Counts $errorCounts -Threshold 2)

    if ($repeated.Count -gt 0) {
        $msg = "$($repeated.Count) repeated error pattern(s) found"
        if(-not $Quiet){Write-Host "  WARNING: $($msg):"}
        foreach ($r in $repeated) {
            $severity = 'INFO'
            if ($r.Count -ge 3) { $severity = 'CRITICAL' }
            elseif ($r.Count -ge 2) { $severity = 'WARNING' }
            if(-not $Quiet){Write-Host "    [$severity] $($r.Text) appears $($r.Count) times"}
        }
    } else {
        if(-not $Quiet){Write-Host '  No repeated error patterns. Clean.'}
    }
}

# ---- Learning patterns scan ----
if ($Mode -in 'full','report') {
    if(-not $Quiet){Write-Host '[2/3] Scanning learning patterns...'}

    $learningCounts = Get-LearningPattern -Path $logFile
    $workflowPatterns = @(Get-RepeatedPattern -Counts $learningCounts -Threshold 3)

    $workflowCount = $workflowPatterns.Count
    if ($workflowCount -gt 0) {
        if(-not $Quiet){Write-Host "  Found $workflowCount recurring workflow pattern(s):"}
        foreach ($wp in $workflowPatterns) {
            if(-not $Quiet){Write-Host "    [$($wp.Section)] $($wp.Message) - $($wp.Count)x"}
        }
    } else {
        if(-not $Quiet){Write-Host '  No recurring workflow patterns (need 3+ for promotion).'}
    }
}

# ---- Anti-pattern catalog drift check ----
if ($Mode -in 'full','report') {
    if(-not $Quiet){Write-Host '[3/3] Checking catalog drift...'}
    if (Test-Path $catalogFile) {
        $catalogItem = Get-Item $catalogFile
        $catalogContent = Get-Content $catalogFile -Raw
        $age = (Get-Date) - $catalogItem.LastWriteTime
        if(-not $Quiet){Write-Host "  ANTI-PATTERN-CATALOG.md last updated: $($age.Days)d $($age.Hours)h ago"}

        $entryCount = 0
        $lines = $catalogContent -split "`n"
        foreach ($l in $lines) {
            if ($l -match '^## ') {
                $entryCount = $entryCount + 1
            }
        }
        if(-not $Quiet){Write-Host "  Catalog entries: $entryCount"}
    } else {
        if(-not $Quiet){Write-Host '  ANTI-PATTERN-CATALOG.md not found.'}
    }
}

# ---- Feed mode: output patterns for skill-graph ----
if ($Mode -eq 'feed') {
    if(-not $Quiet){Write-Host '[FEED] Running scans first...'}

    $errorCounts = Get-ErrorPattern -Path $errorFile
    $repeated = @(Get-RepeatedPattern -Counts $errorCounts -Threshold 2)
    $learningCounts = Get-LearningPattern -Path $logFile
    $workflowPatterns = @(Get-RepeatedPattern -Counts $learningCounts -Threshold 3)

    if(-not $Quiet){Write-Host '[FEED] Generating skill-graph patterns...'}

    $feedPatterns = @()

    # Convert repeated errors to skill-graph patterns
    if ($repeated.Count -gt 0) {
        foreach ($r in $repeated) {
            $keywords = @(($r.Text -replace '[^\w\s]','' -split '\s+' |
                Where-Object { $_.Length -gt 2 } |
                Select-Object -Unique))
            if ($keywords.Count -gt 0) {
                $feedPatterns += @{
                    keywords = @($keywords)
                    boost = if ($r.Count -ge 3) { "immune-system" } else { "recovery-protocol" }
                    reason = "Error repeated $($r.Count)x: $($r.Text)"
                    source = "dreaming-error"
                }
            }
        }
    }

    # Convert workflow patterns to skill-graph patterns
    if ($workflowPatterns.Count -gt 0) {
        foreach ($wp in $workflowPatterns) {
            $keywords = @(("$($wp.Section) $($wp.Message)" -replace '[^\w\s]','' -split '\s+' |
                Where-Object { $_.Length -gt 2 } |
                Select-Object -Unique))
            if ($keywords.Count -gt 0) {
                $feedPatterns += @{
                    keywords = @($keywords)
                    boost = $wp.Section
                    reason = "Workflow pattern $($wp.Count)x: $($wp.Message)"
                    source = "dreaming-workflow"
                }
            }
        }
    }

    # Output to file or stdout
    $feedOutput = @{ patterns = $feedPatterns; generated = $timestamp; cycleId = $cycleId }

    if ($OutputPath) {
        $feedOutput | ConvertTo-Json -Depth 3 | Set-Content -Path $OutputPath -Encoding UTF8
        if(-not $Quiet){Write-Host "  Patterns written to: $OutputPath"}
    } else {
        $feedOutput | ConvertTo-Json -Depth 3
    }

    if(-not $Quiet){Write-Host "  Generated $($feedPatterns.Count) pattern(s) for skill-graph"}
}

if(-not $Quiet){Write-Host ''}

if(-not $Quiet){Write-Host "=== Dreaming Complete: $cycleId ==="}
$finalRepeated = 0; $finalPatterns = 0
if ($repeated.Count -gt 0) { $finalRepeated = $repeated.Count }
if ($learningCounts.Count -gt 0) { $finalPatterns = $learningCounts.Keys.Count }
# ponytail: explicit GC at session boundary — regex+pattern processing may hold large strings
$errorCounts=$learningCounts=$repeated=$workflowPatterns=$feedPatterns=$null;[GC]::Collect()
$msg = "Mode=$Mode | Repeated=$finalRepeated | Patterns=$finalPatterns"
Write-LogMessage -Section 'Dreaming' -Message $msg
