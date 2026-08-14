#requires -Version 7
<#
.SYNOPSIS
    Gentleman-ize any project — bootstrap opencode.json from the generation chain
    (opencode-base.json + permission-templates.json), NOT from the global config.

.DESCRIPTION
    Bootstraps a project directory with gentleman-vMK as default agent.
    The project's opencode.json is generated from the SSoT chain:
      scripts/lib/opencode-base.json          (agents, mcp, schema, base permissions)
      scripts/lib/permission-templates.json   (per-mode permission blocks)
      scripts/lib/agent-overrides.json        (hidden flags, extra perm keys)
      scripts/opencode-config/shared-deny-rules.json  (security deny floor)
    The generated config re-asserts the shared deny rules (security never degrades)
    and adds a write-deny to ~/.config/opencode/**.
    .gentleman-mode is written as 'manual' by default (never inherited from the
    gentleman repo); an existing .gentleman-mode is respected unless -Force.

    Call from any project directory:
      .\scripts\use-gentleman.ps1
      .\scripts\use-gentleman.ps1 -TargetDir ..\my-other-project -DefaultAgent gentleman-quick

.PARAMETER TargetDir
    Project directory to gentleman-ize. Defaults to the current project's git root
    (walk-up from cwd), or the current directory when no .git is found.

.PARAMETER DefaultAgent
    Agent to set as default. Default: gentleman-vMK. Options: gentleman-vMK, gentleman-deep,
    gentleman-codex, gentleman-quick.

.PARAMETER Json
    Output JSON report instead of human-readable text.

.PARAMETER Yes
    Non-interactive — skip confirmation prompts.

.PARAMETER Force
    Overwrite an existing .gentleman-mode (set it back to 'manual'). Without this,
    an existing mode file is respected.

.PARAMETER DryRun
    Report what would be written without writing any files (opencode.json and
    .gentleman-mode are not created or modified).

.EXAMPLE
    .\scripts\use-gentleman.ps1
    Gentleman-izes the current directory.

.EXAMPLE
    .\scripts\use-gentleman.ps1 -TargetDir ..\my-api -DefaultAgent gentleman-quick
    Sets up my-api with gentleman-quick as default.

.EXAMPLE
    .\scripts\use-gentleman.ps1 -Json -Yes
    Silent JSON output for CI/scripting.
#>
param(
    [string]$TargetDir,
    [ValidateSet("gentleman-vMK","gentleman-deep","gentleman-codex","gentleman-quick")]
    [string]$DefaultAgent = "gentleman-vMK",
    [switch]$Json,
    [switch]$Yes,
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")

# ── Load GENTLEMAN_AGENT_ROOT from User env if not in session ────────
if (-not $env:GENTLEMAN_AGENT_ROOT) {
    $userRoot = [Environment]::GetEnvironmentVariable("GENTLEMAN_AGENT_ROOT", "User")
    if ($userRoot) { $env:GENTLEMAN_AGENT_ROOT = $userRoot }
}

# FIX 3: default target = git project root (same root switch-mode/mode-gate resolve),
# not cwd — otherwise opencode.json/.gentleman-mode land in a subdir while the mode
# gate walks up to the .git root. Explicit -TargetDir always wins.
if (-not $PSBoundParameters.ContainsKey('TargetDir')) {
    $TargetDir = Get-GentlemanProjectRoot
}

# ── Paths ────────────────────────────────────────────────────────────
$globalCfgDir   = Get-GlobalConfigDir
$globalCfgFile  = "$globalCfgDir\opencode.json"
$globalSkills   = "$globalCfgDir\skills"
$projectCfgFile = "$TargetDir\opencode.json"
$repoRoot       = Split-Path -Path $PSScriptRoot -Parent

# Chain SSoT files live in the repo. Resolve robustly: prefer GENTLEMAN_AGENT_ROOT
# (works even when this script is executed from the global scripts copy).
$chainRoot = $repoRoot
if ($env:GENTLEMAN_AGENT_ROOT -and (Test-Path (Join-Path $env:GENTLEMAN_AGENT_ROOT 'scripts/lib/opencode-base.json'))) {
    $chainRoot = $env:GENTLEMAN_AGENT_ROOT
}

function Write-Step($name, $scriptBlock) {
    try { & $scriptBlock; return $true } catch { Write-Warning "  [FAIL] $name — $_"; return $false }
}

function Out-Message($msg, $color) {
    if (-not $Json) { Write-Host $msg -ForegroundColor $color }
}

function Merge-ProjectSection {
    param($ChainSection, $ProjectSection)
    $merged = [ordered]@{}
    if ($ChainSection) {
        foreach ($p in $ChainSection.PSObject.Properties) { $merged[$p.Name] = $p.Value }
    }
    if ($ProjectSection) {
        foreach ($p in $ProjectSection.PSObject.Properties) { $merged[$p.Name] = $p.Value }
    }
    [pscustomobject]$merged
}

# ── Template detection (shared module — SSoT mirror of generate-opencode-config.js) ──
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'template-detection.ps1')
. (Join-Path $PSScriptRoot 'lib' 'json-utils.ps1')

# ── Chain generation: opencode-base.json + permission-templates.json + agent-overrides.json ──
function Convert-FileRefsToAbsolute {
    <#
    .SYNOPSIS
        Rewrites relative {file:...} config refs to absolute paths rooted at $Root.
    .DESCRIPTION
        opencode resolves {file:...} relative to the config file's directory. In external
        projects that would point prompts/ at the project dir (where it doesn't exist →
        agent starts with NO prompt). Absolute refs pin the chain prompts to the chain root.
        Already-absolute refs (drive, /, ~/) are left untouched.
    #>
    param(
        [string]$Text,
        [System.Diagnostics.CodeAnalysis.SuppressMessage("PSReviewUnusedParameter", "Root", Justification="Used inside the -replace script-block closure (Join-Path `$Root) which PSSA does not trace")]
        [string]$Root
    )
    # PSEA PSReviewUnusedParameter: $Root is also referenced inside the -replace closure
    # below (Join-Path $Root), which PSEA does not trace. This top-level condition makes
    # the parameter statically counted as used without changing behavior.
    if ($null -ne $Root) { }
    [regex]::Replace($Text, '\{file:([^}]+)\}', {
        param($m)
        $p = $m.Groups[1].Value
        if ([System.IO.Path]::IsPathRooted($p) -or $p.StartsWith('~/') -or $p.StartsWith('/')) { return $m.Value }
        '{file:' + (Join-Path $Root $p) + '}'
    })
}

function Convert-ConfigFileRef {
    <#
    .SYNOPSIS
        Recursively rewrites relative {file:...} refs in every string of a parsed config value.
    #>
    param(
        $Value,
        [System.Diagnostics.CodeAnalysis.SuppressMessage("PSReviewUnusedParameter", "Root", Justification="Forwarded to Convert-FileRefsToAbsolute; PSSA false-positive on forward-only/forwarded parameter")]
        [string]$Root
    )
    # $Root is read in the boolean condition below AND forwarded to Convert-FileRefsToAbsolute.
    if ($Value -is [string] -and $Root) {
        return Convert-FileRefsToAbsolute $Value $Root
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $Value.PSObject.Properties) { $p.Value = Convert-ConfigFileRef $p.Value $Root }
        return $Value
    }
    if ($Value -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Value.Count; $i++) { $Value[$i] = Convert-ConfigFileRef $Value[$i] $Root }
        return $Value
    }
    return $Value
}

# ── Chain generation: opencode-base.json + permission-templates.json + agent-overrides.json ──
function Get-ChainConfig {
    param([string]$ChainRoot, [string]$TargetDir = '')
    $basePath = Join-Path $ChainRoot 'scripts/lib/opencode-base.json'
    $tplPath  = Join-Path $ChainRoot 'scripts/lib/permission-templates.json'
    $ovrPath  = Join-Path $ChainRoot 'scripts/lib/agent-overrides.json'
    if (-not (Test-Path $basePath)) { throw "Chain base not found: $basePath — run setup-machine.ps1 first." }
    if (-not (Test-Path $tplPath))  { throw "Permission templates not found: $tplPath" }

    $base      = Get-Content $basePath -Raw | ConvertFrom-Json
    $templates = Get-Content $tplPath  -Raw | ConvertFrom-Json
    $overrides = if (Test-Path $ovrPath) { Get-Content $ovrPath -Raw | ConvertFrom-Json } else { $null }

    # templateMap SSoT guard — every agent in opencode-base.json must resolve to a template
    # and every referenced template must exist. Fail-fast with a clear message.
    foreach ($name in $base.agent.PSObject.Properties.Name) {
        $mapped = Detect-Template -AgentName $name
        if (-not $mapped) {
            throw "Chain generation: cannot resolve template for agent '$name' in opencode-base.json. Add explicit entry to `$TemplateMap in template-detection.ps1 or follow naming conventions."
        }
        if (-not $templates.PSObject.Properties[$mapped]) {
            throw "Chain generation: template '$mapped' (mapped for agent '$name') missing from permission-templates.json."
        }
    }

    $agents = [ordered]@{}
    foreach ($p in $base.agent.PSObject.Properties) {
        $name    = $p.Name
        $def     = Get-DeepClone $p.Value
        $tplName = Detect-Template -AgentName $name
        if (-not $tplName) { throw "Chain generation: no permission template mapped for agent '$name'" }
        $tpl = Get-DeepClone $templates.$tplName
        if (-not $tpl) { throw "Chain generation: template '$tplName' missing from permission-templates.json" }

        if ($overrides -and $overrides.PSObject.Properties[$name]) {
            $ovr = $overrides.$name
            if ($ovr.PSObject.Properties['hidden']) { $def | Add-Member -NotePropertyName 'hidden' -NotePropertyValue $ovr.hidden -Force }
            if ($ovr.PSObject.Properties['extraPermKeys']) {
                foreach ($ek in $ovr.extraPermKeys.PSObject.Properties) {
                    $tpl | Add-Member -NotePropertyName $ek.Name -NotePropertyValue $ek.Value -Force
                }
            }
        }

        $agent = [ordered]@{}
        if ($def.PSObject.Properties['description']) { $agent['description'] = $def.description }
        if ($def.PSObject.Properties['model'])       { $agent['model'] = $def.model }
        if ($def.PSObject.Properties['hidden'])      { $agent['hidden'] = $def.hidden }
        if ($def.PSObject.Properties['mode'])        { $agent['mode'] = $def.mode }
        if ($def.PSObject.Properties['prompt'])      { $agent['prompt'] = $def.prompt }
        $agent['permission'] = $tpl
        if ($def.PSObject.Properties['tools'])       { $agent['tools'] = $def.tools }
        $agents[$name] = [pscustomobject]$agent
    }

    $config = Get-DeepClone $base
    $config.agent = [pscustomobject]$agents

    # FIX 1: in the chain repo itself relative {file:...} refs resolve (prompts/ lives
    # there); in any OTHER target they must be pinned to the chain root or the agents
    # lose their prompts. Sweep every string so future {file:} fields stay safe too.
    $targetFull    = if ($TargetDir) { [System.IO.Path]::GetFullPath($TargetDir).TrimEnd('\', '/') } else { '' }
    $chainRootFull = [System.IO.Path]::GetFullPath($ChainRoot).TrimEnd('\', '/')
    if (-not $targetFull -or -not ($targetFull -ieq $chainRootFull)) {
        $config = Convert-ConfigFileRef $config $ChainRoot
    }
    $config
}

# ── Security deny floor: shared-deny-rules.json can never be removed by project overrides ──
function Assert-SecurityFloor {
    param($Config, [string]$DenyPath)
    if (-not (Test-Path $DenyPath)) { throw "Shared deny rules not found: $DenyPath" }
    $deny = Get-Content $DenyPath -Raw | ConvertFrom-Json

    if (-not $Config.PSObject.Properties['permission']) {
        $Config | Add-Member -NotePropertyName 'permission' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $Config.permission.PSObject.Properties['bash']) {
        $Config.permission | Add-Member -NotePropertyName 'bash' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $bash = $Config.permission.bash
    foreach ($d in $deny.PSObject.Properties) {
        $bash | Add-Member -NotePropertyName $d.Name -NotePropertyValue 'deny' -Force
    }

    # write-deny to ~/.config/opencode/** (plan R3)
    foreach ($k in @('edit', 'write')) {
        if (-not $Config.permission.PSObject.Properties[$k]) {
            $Config.permission | Add-Member -NotePropertyName $k -NotePropertyValue ([pscustomobject]@{ '~/.config/opencode/**' = 'deny' }) -Force
        } else {
            $Config.permission.$k | Add-Member -NotePropertyName '~/.config/opencode/**' -NotePropertyValue 'deny' -Force
        }
    }

    # FIX 2: per-agent floor — a project's agent.<name>.permission overrides the chain
    # template WHOLESALE on merge, so the global floor alone can be silently bypassed
    # per agent. Re-assert the same denies on every agent that carries its own permission
    # (never invent permissions for agents that don't have them — opencode defaults apply).
    if ($Config.PSObject.Properties['agent'] -and $Config.agent -and $Config.agent -is [psobject]) {
        foreach ($ap in $Config.agent.PSObject.Properties) {
            $agent = $ap.Value
            if (-not $agent -or $agent -isnot [psobject]) { continue }
            if (-not $agent.PSObject.Properties['permission']) { continue }
            $perm = $agent.permission
            if ($perm.PSObject.Properties['bash']) {
                foreach ($d in $deny.PSObject.Properties) {
                    $perm.bash | Add-Member -NotePropertyName $d.Name -NotePropertyValue 'deny' -Force
                }
            }
            foreach ($k in @('edit', 'write')) {
                if ($perm.PSObject.Properties[$k]) {
                    $perm.$k | Add-Member -NotePropertyName '~/.config/opencode/**' -NotePropertyValue 'deny' -Force
                }
            }
        }
    }
}

# ── Resolve target dir ───────────────────────────────────────────────
$TargetDir = [System.IO.Path]::GetFullPath($TargetDir)
if (-not (Test-Path $TargetDir -PathType Container)) {
    if (-not $Yes) {
        $resp = Read-Host "Directory '$TargetDir' doesn't exist. Create it? [Y/n]"
        if ($resp -eq 'n' -or $resp -eq 'N') { throw "Aborted by user" }
    }
    New-Item -ItemType Directory -Path $TargetDir -ErrorAction Stop | Out-Null
    Out-Message "  Created $TargetDir" -color Green
}

# ── 1. Verify global config (runtime readiness — skills junction, agents) ──
Out-Message "==> Gentleman Portability — $TargetDir" -color Cyan

$globalOk = $true

$skillsJunction = Get-Item $globalSkills -ErrorAction SilentlyContinue
$skillsOk = $skillsJunction -and (
    ($skillsJunction.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
    (Test-Path "$globalSkills\_shared" -PathType Container)
)
if (-not $skillsOk) {
    Out-Message "  [warn] Global skills junction not found. Run setup-machine.ps1 first." -color Yellow
    $globalOk = $false
}

if (Test-Path $globalCfgFile -PathType Leaf) {
    try {
        $cfg = Get-Content $globalCfgFile -Raw | ConvertFrom-Json
        $hasGentleman = $null -ne ($cfg.agent.PSObject.Properties['gentleman-vMK'])
        if (-not $hasGentleman) {
            Out-Message "  [warn] gentleman-vMK not in global config. Run sync-vmk.ps1." -color Yellow
            $globalOk = $false
        }
    } catch {
        Out-Message "  [warn] Global config unreadable: $_" -color Yellow
        $globalOk = $false
    }
} else {
    Out-Message "  [warn] No global opencode.json. Run setup-machine.ps1." -color Yellow
    $globalOk = $false
}

if (-not $globalOk) {
    $repoSetup = Join-Path $repoRoot "scripts\setup-machine.ps1"
    if (Test-Path $repoSetup) {
        Out-Message "  -> Fixing by running setup-machine.ps1..." -color Cyan
        & $repoSetup -RepoDir $repoRoot -Yes:$Yes
        $globalOk = $true
    } else {
        throw "Global gentleman setup incomplete. Clone gentleman-agent-gh and run setup-machine.ps1 first."
    }
}

# ── 2. Generate project config FROM THE CHAIN (SSoT), then merge project overrides ──
$projectCfg = Get-ChainConfig -ChainRoot $chainRoot -TargetDir $TargetDir

if (Test-Path $projectCfgFile -PathType Leaf) {
    try {
        $existing = Get-Content $projectCfgFile -Raw | ConvertFrom-Json
        foreach ($section in @('mcp', 'permission', 'agent')) {
            if ($existing.PSObject.Properties[$section]) {
                $projectCfg.$section = Merge-ProjectSection $projectCfg.$section $existing.$section
            }
        }
        foreach ($section in @('compaction', 'tool_output', 'experimental', 'tools', 'plugin')) {
            if ($existing.PSObject.Properties[$section]) { $projectCfg.$section = $existing.$section }
        }
        Out-Message "  Merged existing project config (project wins)" -color DarkGray
    } catch {
        Out-Message "  [warn] Existing config unreadable, regenerating from chain" -color Yellow
    }
}

$projectCfg.default_agent = $DefaultAgent
if (-not $projectCfg.PSObject.Properties['$schema']) {
    $projectCfg | Add-Member -NotePropertyName '$schema' -NotePropertyValue 'https://opencode.ai/config.json' -Force
}

# Security floor — project can add/override rules but shared deny rules stay denied
Assert-SecurityFloor -Config $projectCfg -DenyPath (Join-Path $chainRoot 'scripts/opencode-config/shared-deny-rules.json')

# FIX 5: CBM scope — the chain base ships CBM_ALLOWED_ROOT={env:GENTLEMAN_AGENT_ROOT},
# which is only right when the target IS the gentleman repo. External projects get the
# project dir as CBM_ALLOWED_ROOT (codebase-memory-mcp then indexes the local project —
# matches the "full bootstrap" intent) instead of inheriting the gentleman repo scope or
# an empty "" when the env var is unset. Enabled stays true either way.
$chainRootFull = [System.IO.Path]::GetFullPath($chainRoot).TrimEnd('\', '/')
$targetFull    = [System.IO.Path]::GetFullPath($TargetDir).TrimEnd('\', '/')
$targetIsChainRepo = ($targetFull -ieq $chainRootFull)
if (-not $targetIsChainRepo) {
    $cbm = $projectCfg.mcp.PSObject.Properties['codebase-memory-mcp']
    if ($cbm) {
        if (-not $cbm.Value.PSObject.Properties['environment']) {
            $cbm.Value | Add-Member -NotePropertyName 'environment' -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $cbm.Value.environment | Add-Member -NotePropertyName 'CBM_ALLOWED_ROOT' -NotePropertyValue $TargetDir -Force
    }
}

if ($DryRun) {
    Out-Message "  [dry-run] WOULD create $projectCfgFile (generated from chain)" -color Yellow
} else {
    $projectCfg | ConvertTo-Json -Depth 20 | Set-Content $projectCfgFile -Encoding UTF8 -Force
    Out-Message "  Created $projectCfgFile" -color Green
}
Out-Message "    default_agent: $DefaultAgent" -color DarkGray
Out-Message "    generated from chain (opencode-base.json + permission-templates.json)" -color DarkGray

# ── 2b. .gentleman-mode: 'manual' by default, existing file respected unless -Force ──
$modeDst = Join-Path $TargetDir ".gentleman-mode"
if (Test-Path $modeDst -PathType Leaf) {
    $existingMode = (Get-Content -LiteralPath $modeDst -Raw).Trim()
    if ($Force) {
        if ($DryRun) {
            Out-Message "  [dry-run] WOULD overwrite .gentleman-mode '${existingMode}' -> 'manual' (-Force)" -color Yellow
        } else {
            Set-Content -LiteralPath $modeDst -Value "manual" -NoNewline -Encoding Ascii
            Out-Message "  .gentleman-mode: overwritten to 'manual' (-Force; was '$existingMode')" -color DarkGray
        }
    } else {
        Out-Message "  .gentleman-mode: '$existingMode' (existing, respected)" -color DarkGray
    }
} else {
    if ($DryRun) {
        Out-Message "  [dry-run] WOULD create .gentleman-mode='manual'" -color Yellow
    } else {
        Set-Content -LiteralPath $modeDst -Value "manual" -NoNewline -Encoding Ascii
        Out-Message "  .gentleman-mode: 'manual' (default for external projects)" -color Green
    }
}

# ── 3. Verify end-to-end ─────────────────────────────────────────────
$verifyOk = $true
$verifyNotes = [System.Collections.Generic.List[string]]::new()
try {
    $check = if ($DryRun) { $projectCfg } else { Get-Content $projectCfgFile -Raw | ConvertFrom-Json }
    if ($check.default_agent -ne $DefaultAgent) { throw "default_agent mismatch" }

    # Security denies must be present — derived at runtime from shared-deny-rules.json
    # (the SSoT), so new deny rules are always covered instead of a hardcoded subset.
    $denyRules = Get-Content (Join-Path $chainRoot 'scripts/opencode-config/shared-deny-rules.json') -Raw | ConvertFrom-Json
    $requiredDenies = @($denyRules.PSObject.Properties.Name)
    foreach ($rule in $requiredDenies) {
        if (-not $check.permission.bash.PSObject.Properties[$rule] -or $check.permission.bash.$rule -ne 'deny') {
            throw "security deny missing: $rule"
        }
    }

    # write-deny to ~/.config/opencode/**
    foreach ($k in @('edit', 'write')) {
        if (-not $check.permission.$k.PSObject.Properties['~/.config/opencode/**']) {
            $verifyNotes.Add("~/.config/opencode/** write-deny missing in permission.$k (add manually)")
        }
    }

    # MCPs present
    if (-not $check.mcp.PSObject.Properties['context7']) { throw "mcp.context7 missing" }
    if (-not $check.mcp.PSObject.Properties['engram'])   { throw "mcp.engram missing" }

    Out-Message "  [ok] Config valid, JSON parses correctly" -color Green
} catch {
    Out-Message "  [err] Config verification failed: $_" -color Red
    $verifyOk = $false
}

# Verify MCP tools are available
$mcpTools = @(
    @{ Name = "context7"; Cmd = { Get-Command "npx" -ErrorAction SilentlyContinue } },
    @{ Name = "engram"; Cmd = { Get-Command "engram" -ErrorAction SilentlyContinue } },
    @{ Name = "headroom"; Cmd = { Get-Command "headroom" -ErrorAction SilentlyContinue } }
)
$allMcpOk = $true
foreach ($mcp in $mcpTools) {
    if (& $mcp.Cmd) {
        Out-Message "  [ok] MCP '$($mcp.Name)' tool available" -color Green
    } else {
        Out-Message "  [warn] MCP '$($mcp.Name)' tool not in PATH — install globally" -color Yellow
        $allMcpOk = $false
    }
}
if (-not $allMcpOk) {
    Out-Message "  → Install missing MCPs: npm i -g @upstash/context7-mcp engram headroom" -color DarkGray
}

# ── Report ───────────────────────────────────────────────────────────
$report = @{
    status         = if ($verifyOk) { "ok" } else { "fail" }
    target_dir     = $TargetDir
    default_agent  = $DefaultAgent
    dry_run        = [bool]$DryRun
    project_config = $projectCfgFile
    global_ok      = $globalOk
    generated_from = "chain (opencode-base.json + permission-templates.json)"
    security_floor = "shared-deny-rules.json re-asserted"
    errors         = @()
    notes          = @($verifyNotes)
}

if (-not $verifyOk) { $report.errors += "Config verification failed" }

if ($Json) {
    $report | ConvertTo-Json -Depth 3
} else {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Gentleman Portability Report" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Target  : $TargetDir" -ForegroundColor White
    Write-Host "  Agent   : $DefaultAgent" -ForegroundColor White
    Write-Host "  Status  : $(if($verifyOk){'✅ OK'}else{'❌ FAIL'})" -ForegroundColor $(if($verifyOk){'Green'}else{'Red'})
    Write-Host ""
    Write-Host ("  To use: cd {0} {1}{1} opencode" -f $TargetDir, '&') -ForegroundColor Cyan
    Write-Host "  Skills : $globalSkills (junction, auto-synced)" -ForegroundColor DarkGray
    Write-Host "  Source : Generated from chain (not copied from global)" -ForegroundColor DarkGray
    Write-Host "  Secure : shared-deny-rules.json re-asserted (global + per-agent) + write-deny ~/.config/opencode/**" -ForegroundColor DarkGray
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
}

