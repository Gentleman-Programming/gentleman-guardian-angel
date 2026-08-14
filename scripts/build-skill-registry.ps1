#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Build skill registry — generates skill-registry.json from SKILL.md frontmatter. Idempotent.
.DESCRIPTION
    Scans all skill directories under .agents/skills/, parses SKILL.md frontmatter (name, description),
    and writes a consolidated JSON registry at scripts/skill-registry.json. Used by skill-resolver-fast.ps1.
.PARAMETER SkillsDir
    Directory containing skill subdirectories. Default: .agents/skills/
.PARAMETER OutputFile
    Path to write registry JSON. Default: scripts/skill-registry.json
#>
param(
    [switch]$Quiet,
    [string]$SkillsDir = "$PSScriptRoot\..\.agents\skills",
    [string]$OutputFile = "$PSScriptRoot\skill-registry.json"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Frontmatter {
    param([string]$Content)

    $result = @{
        name         = ""
        triggers     = @()
        tags         = @()
        dependencies = @()
    }

    # Extract frontmatter block between --- markers
    if ($Content -notmatch "(?s)^---\r?\n(.+?)\r?\n---") { return $result }
    $fm = $Matches[1]

    # Parse name
    if ($fm -match "name:\s*[""']?(.+?)[""']?\s*$") {
        $result.name = $Matches[1].Trim()
    }

    # Parse triggers — comma-separated string; quoted, bare, or YAML inline array ([a, b])
    if ($fm -match "(?m)^triggers:\s*(.+?)\s*$") {
        $raw = $Matches[1].Trim()
        # Strip surrounding quotes OR YAML inline-array brackets
        if ($raw -match '^["''](.+)["'']$') { $raw = $Matches[1] }
        elseif ($raw -match '^\[(.+)\]$')  { $raw = $Matches[1] }
        if ($raw -and $raw -notmatch '^\s*$' -and $raw -ne 'none') {
            $result.triggers = ($raw -split ",") | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
        }
    }

    # Parse tags — inline array [tag1, tag2] or YAML list
    if ($fm -match "tags:\s*\[(.+?)\]") {
        # Inline array: [engineering, security]
        $result.tags = ($Matches[1] -split ",") | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    }
    elseif ($fm -match "(?s)tags:\s*\r?\n((?:\s+-\s+.+\r?\n)+)") {
        # YAML list
        $result.tags = ($Matches[1] -split "\r?\n") |
            Where-Object { $_ -match "^\s+-\s+(.+)" } |
            ForEach-Object { $Matches[1].Trim().ToLower() }
    }

    # Parse dependencies — inline array or YAML list (in metadata or top-level)
    if ($fm -match "dependencies:\s*\[(.+?)\]") {
        $result.dependencies = ($Matches[1] -split ",") | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    }
    elseif ($fm -match "(?s)dependencies:\s*\r?\n((?:\s+-\s+.+\r?\n)+)") {
        $result.dependencies = ($Matches[1] -split "\r?\n") |
            Where-Object { $_ -match "^\s+-\s+(.+)" } |
            ForEach-Object { $Matches[1].Trim().ToLower() }
    }

    return $result
}

# --- Main ---
$skills = @{}
$triggerIndex = @{}

$skillDirs = Get-ChildItem -Path $SkillsDir -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "SKILL.md")
}

foreach ($dir in $skillDirs) {
    $skillMd = Join-Path $dir.FullName "SKILL.md"
    $content = Get-Content -Path $skillMd -Raw -Encoding UTF8
    $parsed = Get-Frontmatter $content

    $name = if ($parsed.name) { $parsed.name } else { $dir.Name }

    # Build relative path from repo root
    $relativePath = ".agents/skills/$($dir.Name)/SKILL.md"

    $skills[$name] = @{
        name         = [string]$name
        triggers     = @($parsed.triggers)
        tags         = @($parsed.tags)
        dependencies = @($parsed.dependencies)
        path         = [string]$relativePath
    }

    # Build trigger index
    foreach ($trigger in $parsed.triggers) {
        if (-not $triggerIndex.ContainsKey($trigger)) {
            $triggerIndex[$trigger] = @()
        }
        $triggerIndex[$trigger] += $name
    }
}

$registry = @{
    generated    = (Get-Date -Format "o")
    skills       = $skills
    trigger_index = $triggerIndex
}

# Compact output: strip tags and dependencies (not used by resolver)
$compact = @{
    generated    = $registry.generated
    trigger_index = $registry.trigger_index
    skills       = @{}
}
foreach ($name in $registry.skills.Keys) {
    $s = $registry.skills[$name]
    $compact.skills[$name] = @{
        name     = [string]$s.name
        triggers = @($s.triggers)
        path     = [string]$s.path
    }
}

$compact | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputFile -Encoding UTF8

if (-not $Quiet) { Write-Host "✓ Registry built: $($skills.Count) skills, $($triggerIndex.Count) triggers → $OutputFile" -ForegroundColor Green }
