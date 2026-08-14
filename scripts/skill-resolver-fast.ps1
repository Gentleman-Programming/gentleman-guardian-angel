#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Fast skill resolver — matches tasks to skills from pre-built registry JSON via keyword scoring.
.DESCRIPTION
    Loads skill-registry.json and scores each skill's description against the task string
    using token overlap (BFS keyword matching). Returns top-N results sorted by relevance.
    Much faster than skill-graph.ps1's full BFS resolution — use for CI/automation.
.PARAMETER Task
    Task description to match against skill descriptions. Required.
.PARAMETER Top
    Number of top matches to return. Default: 8.
.PARAMETER RegistryPath
    Path to skill-registry.json. Default: scripts/skill-registry.json
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [int]$Top = 8,
    [string]$RegistryPath = "$PSScriptRoot\skill-registry.json"
)
# ponytail: -Quiet is a no-op here — output is already JSON-only data via Write-Output
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $RegistryPath)) {
    Write-Error "Registry not found: $RegistryPath — Run build-skill-registry.ps1 first"
    exit 1
}

$registry = Get-Content -Path $RegistryPath -Raw | ConvertFrom-Json
$taskLower = $Task.ToLower()
# Token-split aligned with skill-graph.ps1 Resolve-Skill (C4a: dual resolution fix)
$taskTokens = $taskLower -split '\s+|[-_/.,!?;:()]' |
    Where-Object { $_.Length -gt 2 } | Select-Object -Unique

$scores = @{}

# Match algorithm aligned with skill-graph.ps1 (C4a: dual resolution fix)
# Uses [regex]::Escape + -match (trigger key contains token) instead of bidirectional -like
# Each task token contributes at most 1 match per skill (break after first trigger match)
foreach ($tk in $taskTokens) {
    $pattern = [regex]::Escape($tk)
    foreach ($trigger in $registry.trigger_index.PSObject.Properties) {
        $triggerKey = $trigger.Name.ToLower()
        if ($triggerKey -match $pattern) {
            foreach ($skillName in $trigger.Value) {
                if (-not $scores.ContainsKey($skillName)) {
                    $scores[$skillName] = 0
                }
                $scores[$skillName]++
            }
            break  # align with skill-graph: one count per token
        }
    }
}

# Also check skill names directly — aligned with skill-graph (regex match, +3 bonus)
foreach ($skill in $registry.skills.PSObject.Properties) {
    $name = $skill.Name.ToLower()
    foreach ($tk in $taskTokens) {
        $namePattern = [regex]::Escape($tk)
        if ($name -match $namePattern) {
            if (-not $scores.ContainsKey($skill.Name)) {
                $scores[$skill.Name] = 0
            }
            $scores[$skill.Name] += 3  # name match = high score (aligned with skill-graph)
            break
        }
    }
}

# Sort by score, return top N
$ranked = $scores.GetEnumerator() |
    Sort-Object -Property Value -Descending |
    Select-Object -First $Top

if ($ranked.Count -eq 0) {
    Write-Output "[]"
    exit 0
}

$result = $ranked | ForEach-Object {
    $skillData = $registry.skills.PSObject.Properties[$_.Name].Value
    [ordered]@{
        name     = $_.Name
        score    = $_.Value
        path     = $skillData.path
        triggers = $skillData.triggers
    }
}

$result | ConvertTo-Json -Depth 4
