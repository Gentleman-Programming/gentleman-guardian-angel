#requires -Version 7
<#
.SYNOPSIS
    ConfigValidator — validates opencode.json structure against known failure
    patterns (G1 array unwrapping, G3 agent completeness) + file reference integrity.
.DESCRIPTION
    Enfoque A (Minimal) from plan-auto-mejora-v3-2026-08-13 §3 (Cycle 3 — G2).
    Three checks + one orchestrator entry point:
      - Test-SkillsPaths:       skills.paths must be an ARRAY (G1 regression prevention)
      - Test-PromptRefs:        {file:...} prompt refs must resolve to existing files
      - Test-AgentDefinitions:  agent section must include gentleman-*, sdd-* and
                                gentle-orchestrator (G3 regression prevention)
      - Test-OpencodeConfig:    runs all three, returns 0 (pass) / 1 (fail)
.NOTES
    CI usage (ubuntu-latest, relative paths only — no D:\...):
      Import-Module ./scripts/lib/ConfigValidator.psm1
      Test-OpencodeConfig -Path ./opencode.json
#>

function Test-SkillsPaths {
    <#
    .SYNOPSIS
        Validates that skills.paths is an array of strings (G1: ConvertTo-Json
        single-element array unwrapping would turn it into a bare string).
    .PARAMETER Config
        Parsed opencode.json (ConvertFrom-Json result).
    .OUTPUTS
        [string[]] — empty when valid; otherwise one message per failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )
    $failures = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $Config.skills -or $null -eq $Config.skills.paths) {
        $failures.Add('skills.paths is missing')
        return @($failures)
    }

    $paths = $Config.skills.paths
    if ($paths -is [string]) {
        $failures.Add("skills.paths is a STRING ('$paths') — array unwrapping (G1). Expected an array.")
    } elseif ($paths -isnot [System.Array] -and $paths -isnot [System.Collections.IList]) {
        $failures.Add("skills.paths is not an array (type: $($paths.GetType().Name))")
    } else {
        foreach ($p in $paths) {
            if ($p -isnot [string] -or [string]::IsNullOrWhiteSpace($p)) {
                $failures.Add("skills.paths contains non-string/empty entry: '$p'")
            }
        }
    }
    return @($failures)
}

function Test-PromptRefs {
    <#
    .SYNOPSIS
        Validates that every {file:...} reference in agent prompts (and agent
        descriptions) resolves to an existing file relative to the config's directory.
    .PARAMETER Config
        Parsed opencode.json (ConvertFrom-Json result).
    .PARAMETER ConfigPath
        Path to opencode.json (used to resolve relative file refs).
    .OUTPUTS
        [string[]] — empty when valid; otherwise one message per failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )
    $failures = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Config.agent) { return @($failures) }

    $configDir = Split-Path -Parent (Resolve-Path -LiteralPath $ConfigPath -ErrorAction SilentlyContinue)

    foreach ($agentName in $Config.agent.PSObject.Properties.Name) {
        $agent = $Config.agent.$agentName
        $texts = @()
        if ($agent.prompt) { $texts += $agent.prompt }
        if ($agent.description) { $texts += $agent.description }
        foreach ($t in $texts) {
            # Match {file:relative/path.md} — possibly with trailing modifiers
            $matches = [regex]::Matches([string]$t, '\{file:([^}]+)\}')
            foreach ($m in $matches) {
                $ref = $m.Groups[1].Value.Trim()
                if ([string]::IsNullOrWhiteSpace($ref)) { continue }
                $refPath = if ([System.IO.Path]::IsPathRooted($ref)) { $ref } else { Join-Path $configDir $ref }
                if (-not (Test-Path -LiteralPath $refPath -PathType Leaf)) {
                    $failures.Add("Agent '$agentName': prompt file ref '{file:$ref}' not found (resolved: $refPath)")
                }
            }
        }
    }
    return @($failures)
}

function Test-AgentDefinitions {
    <#
    .SYNOPSIS
        Validates the agent section contains the full expected set: gentleman-*,
        sdd-* and gentle-orchestrator (G3 regression prevention — 50 agents total).
    .PARAMETER Config
        Parsed opencode.json (ConvertFrom-Json result).
    .OUTPUTS
        [string[]] — empty when valid; otherwise one message per failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )
    $failures = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Config.agent) {
        $failures.Add('agent section is missing')
        return @($failures)
    }

    $names = @($Config.agent.PSObject.Properties.Name)
    $gentleman = @($names | Where-Object { $_ -like 'gentleman*' })
    $sdd       = @($names | Where-Object { $_ -like 'sdd*' })
    $orch      = @($names | Where-Object { $_ -eq 'gentle-orchestrator' })

    if ($gentleman.Count -eq 0) { $failures.Add('no gentleman-* agents found') }
    if ($sdd.Count -eq 0)       { $failures.Add('no sdd-* agents found (G3 regression — expected 10)') }
    if ($orch.Count -eq 0)      { $failures.Add('gentle-orchestrator agent missing (G3 regression)') }
    if ($names.Count -ne 50)    { $failures.Add("expected 50 agents, found $($names.Count)") }

    return @($failures)
}

function Test-OpencodeConfig {
    <#
    .SYNOPSIS
        Full config validation entry point. Runs all three checks.
    .PARAMETER Path
        Path to opencode.json (relative to workspace in CI — never D:\...).
    .PARAMETER Quiet
        Suppress failure messages (exit code still reliable).
    .OUTPUTS
        [int] — 0 (pass) / 1 (fail).
    .EXAMPLE
        Test-OpencodeConfig -Path ./opencode.json   # -> 0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$Quiet
    )
    $all = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path -LiteralPath $Path)) {
        if (-not $Quiet) { Write-Error "config file not found: $Path" }
        return 1
    }

    try {
        $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        if (-not $Quiet) { Write-Error "JSON parse error in $Path : $($_.Exception.Message)" }
        return 1
    }

    (Test-SkillsPaths -Config $config) | Where-Object { $_ } | ForEach-Object { $all.Add($_) }
    (Test-PromptRefs -Config $config -ConfigPath $Path) | Where-Object { $_ } | ForEach-Object { $all.Add($_) }
    (Test-AgentDefinitions -Config $config) | Where-Object { $_ } | ForEach-Object { $all.Add($_) }

    if ($all.Count -gt 0) {
        if (-not $Quiet) {
            Write-Output "ConfigValidator FAILED ($($all.Count) issue(s)):"
            $all | ForEach-Object { Write-Output "  - $_" }
        }
        return 1
    }
    if (-not $Quiet) { Write-Output "ConfigValidator OK — opencode.json valid (skills.paths array, prompt refs resolve, 50 agents)" }
    return 0
}

Export-ModuleMember -Function Test-SkillsPaths, Test-PromptRefs, Test-AgentDefinitions, Test-OpencodeConfig