#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

<#
.SYNOPSIS
  Extract patterns from .learnings/ into reusable skills.
  Part of the self-improvement cycle.

.DESCRIPTION
  Scans .learnings/LEARNINGS.md for patterns with >=3 repetitions
  (identified by same Pattern-Key) and generates a skill skeleton
  in .agents/skills/{name}/SKILL.md.

.PARAMETER PatternKey
  Extract a specific pattern by key (e.g. "improvement/cycle").

.PARAMETER List
  List all patterns with repetition count >= threshold.

.PARAMETER Threshold
  Minimum repetitions to auto-extract (default: 3).

.PARAMETER DryRun
  Show what would be extracted without writing files.

.PARAMETER Quiet
  JSON output only.
#>

param(
    [string]$PatternKey = "",
    [switch]$List,
    [int]$Threshold = 3,
    [switch]$DryRun,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$learnPath = Join-Path -Path $repoRoot -ChildPath ".learnings\LEARNINGS.md"
$skillsDir = Join-Path -Path $repoRoot -ChildPath ".agents\skills"

$results = New-Object System.Collections.ArrayList

if (-not (Test-Path -LiteralPath $learnPath)) {
    Write-Host "[extract-skill] No .learnings/LEARNINGS.md found" -ForegroundColor Yellow
    exit 0
}

$content = Get-Content -LiteralPath $learnPath -Raw
$allKeys = New-Object System.Collections.ArrayList
$matchResults = [regex]::Matches($content, '- \*\*Pattern-Key\*\*: (\S+)')
foreach ($m in $matchResults) {
    $null = $allKeys.Add($m.Groups[1].Value)
}

if ($List) {
    $grouped = @($allKeys | Group-Object | Where-Object { $_.Count -ge $Threshold } | Sort-Object Count -Descending)
    if ($grouped.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host "[extract-skill] No patterns with >=$Threshold repetitions found" -ForegroundColor Yellow
        }
        exit 0
    }
    if (-not $Quiet) {
        Write-Host "Patterns with >=$Threshold repetitions:" -ForegroundColor Cyan
        foreach ($g in $grouped) {
            Write-Host "  $($g.Name) ($($g.Count)x)" -ForegroundColor Green
        }
    }
    if ($Quiet) {
        $grouped | Select-Object Name, Count | ConvertTo-Json
    }
    exit 0
}

if ($PatternKey -ne "") {
    $allKeys.Clear()
    $null = $allKeys.Add($PatternKey)
}

foreach ($key in $allKeys) {
    $safeName = $key -replace '/', '-'
    $skillPath = Join-Path -Path $skillsDir -ChildPath "$safeName\SKILL.md"

    if (Test-Path -LiteralPath $skillPath) {
        if (-not $Quiet) {
            Write-Host "[extract-skill] Skill already exists: $safeName" -ForegroundColor Yellow
        }
        continue
    }

    $rx = "(?s)## \[.*?\].*?\n.*?\*\*Pattern-Key\*\*: " + $key + ".*?\n(.*?)(?=\n## |\Z)"
    $entries = [regex]::Matches($content, $rx)
    $entryCount = $entries.Count

    if ($entryCount -lt $Threshold) {
        if (-not $Quiet) {
            Write-Host "[extract-skill] $key only $entryCount reps, skipping" -ForegroundColor DarkYellow
        }
        continue
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would create skill: $safeName ($entryCount entries)" -ForegroundColor Cyan
        $null = $results.Add([PSCustomObject]@{
            PatternKey = $key
            SkillName  = $safeName
            Entries    = $entryCount
            Path       = $skillPath
        })
        continue
    }

    try {
        $skillDir = Join-Path -Path $skillsDir -ChildPath $safeName
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null

        $desc = "Auto-extracted pattern: $key ($entryCount occurrences in .learnings)"

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("---")
    $null = $sb.AppendLine("name: $safeName")
    $null = $sb.AppendLine('description: "' + $desc + '"')
    $null = $sb.AppendLine('triggers: "' + $key + '"')
    $null = $sb.AppendLine("license: Apache-2.0")
    $null = $sb.AppendLine("metadata:")
    $null = $sb.AppendLine("  tags: [auto-extracted, pattern]")
    $null = $sb.AppendLine("  author: gentleman-vMK")
    $null = $sb.AppendLine('  version: "1.0"')
    $null = $sb.AppendLine("  source: extract-skill.ps1")
    $null = $sb.AppendLine("---")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("## When")
    $null = $sb.AppendLine("Pattern $key with $entryCount repetitions detected in .learnings.")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("## Critical Patterns")
    $null = $sb.AppendLine("- See .learnings/LEARNINGS.md entries with Pattern-Key: $key")
    $null = $sb.AppendLine("- Extracted automatically by scripts/extract-skill.ps1")
    $null = $sb.AppendLine("- Review and refine this skill on first use")
        Set-Content -LiteralPath $skillPath -Value $sb.ToString() -Encoding UTF8

        if (-not $Quiet) {
            Write-Host "[extract-skill] Created skill: $safeName ($entryCount entries)" -ForegroundColor Green
        }

        $null = $results.Add([PSCustomObject]@{
            PatternKey = $key
            SkillName  = $safeName
            Entries    = $entryCount
            Path       = $skillPath
            Status     = "created"
        })
    } catch {
        $errMsg = $_.Exception.Message
        Write-Warning ("[extract-skill] Failed to create skill {0}: {1}" -f $safeName, $errMsg)
    }
}

if ($results.Count -eq 0 -and -not $Quiet) {
    Write-Host "[extract-skill] No patterns extracted" -ForegroundColor Yellow
}

if ($Quiet) {
    $results | ConvertTo-Json -Depth 3
}
