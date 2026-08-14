#requires -Version 7
<#
.SYNOPSIS
  Expand $import markers in opencode.json — resolves shared deny rules inline
  and injects -semi agents from semi-agents.json.
.DESCRIPTION
  Reads opencode.json, finds all "$import" keys in permission.bash blocks,
  reads the referenced JSON files, merges their properties into the parent,
  and writes the expanded result back to opencode.json.
  Also checks if -semi agents exist and injects them from semi-agents.json
  if they are missing.
  Safe to run repeatedly — already-expanded files are left unchanged.
.EXAMPLE
  .\scripts\opencode-config\expand-config.ps1
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Quiet
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $repoRoot "opencode.json"

if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Error "opencode.json not found at $configPath"
    exit 1
}

$content = Get-Content -LiteralPath $configPath -Raw
$modified = $false

# --- Expand $import markers ---
$importPattern = [regex]::new('(?m)^(\s+)"\$import":\s*"([^"]+)"')

$match = $importPattern.Match($content)
while ($match.Success) {
    $importPath = $match.Groups[2].Value
    $indent = $match.Groups[1].Value

    $absPath = if ([System.IO.Path]::IsPathRooted($importPath)) {
        $importPath
    } else {
        Join-Path $repoRoot $importPath
    }

    if (-not (Test-Path -LiteralPath $absPath)) {
        Write-Warning "Import not found: $importPath (resolved: $absPath)"
        $match = $match.NextMatch()
        continue
    }

    $imported = Get-Content -LiteralPath $absPath -Raw | ConvertFrom-Json
    if (-not $imported) {
        Write-Warning "Empty or invalid import: $importPath"
        $match = $match.NextMatch()
        continue
    }

    $props = @($imported.PSObject.Properties)
    $ruleCount = $props.Count

    $ruleLines = @()
    for ($i = 0; $i -lt $ruleCount; $i++) {
        $prop = $props[$i]
        $comma = if ($i -lt $ruleCount - 1) { "," } else { "" }
        $ruleLines += "$indent`"$($prop.Name)`": `"$($prop.Value)`"$comma"
    }
    $replacement = $ruleLines -join "`r`n"

    $content = $content.Remove($match.Index, $match.Length).Insert($match.Index, $replacement)

    $modified = $true
    if (-not $Quiet) {
        Write-Host "  expanded: $importPath -> $ruleCount rules" -ForegroundColor Green
    }

    $match = $importPattern.Match($content)
}

# --- Inject -semi agents (if not already present) ---
$semiConfigPath = Join-Path $repoRoot "scripts\opencode-config\semi-agents.json"
$semiMarker = '"gentleman-vMK-semi"'

if (Test-Path -LiteralPath $semiConfigPath) {
    if ($content -notmatch [regex]::Escape($semiMarker)) {
        $semiRaw = Get-Content -LiteralPath $semiConfigPath -Raw

        # Find insertion point: at the line of "gentleman-reviewer"
        $afterPattern = [regex]::new('(?m)^    "gentleman-reviewer"')
        $afterMatch = $afterPattern.Match($content)

        if ($afterMatch.Success) {
            # Strip outer { } from semi-agents.json
            $innerSemi = $semiRaw -replace '(?s)^\s*\{\s*\r?\n', '' -replace '(?s)\r?\n\s*\}\s*$', ''
            # Re-indent from 2-space to 4-space (agents object indent level)
            $reindented = $innerSemi -replace '(?m)^(\s+)', '  $1'
            # Ensure last entry has trailing comma (it will be mid-object)
            $reindented = $reindented.TrimEnd() -replace '\}\s*$', '},'

            # Insert after the 4-space indent to avoid doubling it
            # $afterMatch.Index points to first space of indent
            $insertPoint = $afterMatch.Index + 4
            $insertion = "`r`n${reindented}`r`n    "
            $content = $content.Substring(0, $insertPoint) + $insertion + $content.Substring($insertPoint)
            $modified = $true

            if (-not $Quiet) {
                Write-Host "  injected: 5 -semi agents -> will expand imports below" -ForegroundColor Green
            }

            # Re-run expand loop for the newly injected $import markers
            $match = $importPattern.Match($content)
            while ($match.Success) {
                $importPath = $match.Groups[2].Value
                $indent = $match.Groups[1].Value

                $absPath = if ([System.IO.Path]::IsPathRooted($importPath)) {
                    $importPath
                } else {
                    Join-Path $repoRoot $importPath
                }

                if (-not (Test-Path -LiteralPath $absPath)) {
                    Write-Warning "Import not found: $importPath (resolved: $absPath)"
                    $match = $match.NextMatch()
                    continue
                }

                $imported = Get-Content -LiteralPath $absPath -Raw | ConvertFrom-Json
                if (-not $imported) {
                    $match = $match.NextMatch()
                    continue
                }

                $props = @($imported.PSObject.Properties)
                $ruleCount = $props.Count
                $ruleLines = @()
                for ($i = 0; $i -lt $ruleCount; $i++) {
                    $prop = $props[$i]
                    $comma = if ($i -lt $ruleCount - 1) { "," } else { "" }
                    $ruleLines += "$indent`"$($prop.Name)`": `"$($prop.Value)`"$comma"
                }
                $replacement = $ruleLines -join "`r`n"

                $content = $content.Remove($match.Index, $match.Length).Insert($match.Index, $replacement)
                $modified = $true
                if (-not $Quiet) {
                    Write-Host "  expanded: $importPath -> $ruleCount rules (semi agent)" -ForegroundColor Green
                }
                $match = $importPattern.Match($content)
            }
        } else {
            Write-Warning "Could not find insertion point for -semi agents"
        }
    } else {
        if (-not $Quiet) {
            Write-Host "`u{2139} -semi agents already present" -ForegroundColor Yellow
        }
    }
}

if ($modified) {
    # Validate JSON before writing
    try {
        $null = $content | ConvertFrom-Json
    } catch {
        Write-Error "Generated JSON is invalid -- not writing. Error: $_"
        exit 1
    }

    Set-Content -LiteralPath $configPath -Value $content -Encoding UTF8 -NoNewline
    if (-not $Quiet) {
        Write-Host "`n`u{2705} opencode.json expanded and validated" -ForegroundColor Green
    }
} else {
    if (-not $Quiet) {
        Write-Host "`u{2139} No imports found - opencode.json already expanded" -ForegroundColor Yellow
    }
}
