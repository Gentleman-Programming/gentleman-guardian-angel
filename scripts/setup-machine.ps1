#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Gentleman Agent — One-shot machine setup for portability
.DESCRIPTION
    Sets up a new machine after cloning gentleman-agent-gh:
    - Creates global shell shortcuts (gentleman-vmk)
    - Sets GENTLEMAN_AGENT_ROOT environment variable
    - Configures OpenCode env vars
    - Installs MCP server binaries (codebase-memory-mcp, engram, headroom)
    - Installs Ollama + moondream model for vision analysis
    - Creates skill junction in global config
    - Verifies everything works
.PARAMETER RepoDir
    Path to the cloned gentleman-agent-gh repo (default: current dir)
.PARAMETER SkipEnvVar
    Skip persistent env var registration (for containers/CI)
.PARAMETER SkipShortcuts
    Skip global shell shortcut creation
.PARAMETER SkipMcp
    Skip MCP server binary installation
.PARAMETER DryRun
    Report what would change without applying anything (no installs, no writes)
.PARAMETER Force
    Re-apply steps that are already in place (overrides 'already exists' skips)
.EXAMPLE
    .\scripts\setup-machine.ps1
    .\scripts\setup-machine.ps1 -RepoDir D:\gentleman-agent-gh
#>
param(
    [string]$RepoDir = (Get-Location).Path,
    [switch]$SkipEnvVar,
    [switch]$SkipShortcuts,
    [switch]$SkipMcp,
    [switch]$SkipVision,
    [switch]$DryRun,
    [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")

# Helpers
function info  { Write-Host "==> " -ForegroundColor Cyan -NoNewline; Write-Host "$args" }
function ok    { Write-Host "[ok] " -ForegroundColor Green -NoNewline; Write-Host "$args" }
function warn  { Write-Host "[warn] " -ForegroundColor Yellow -NoNewline; Write-Host "$args" }
function err   { Write-Host "[err] " -ForegroundColor Red -NoNewline; Write-Host "$args"; exit 1 }
function skip  { Write-Host "[skip] " -ForegroundColor DarkGray -NoNewline; Write-Host "$args" }

# Validate repo
info "Validating repo at $RepoDir"
foreach ($f in @("opencode.json", "AGENTS.md", ".agents/skills")) {
    if (-not (Test-Path (Join-Path $RepoDir $f))) { err "Missing $f — is $RepoDir the gentleman-agent-gh repo?" }
}
ok "Repo structure validated"

# Step 1: GENTLEMAN_AGENT_ROOT
$__rootDir = $RepoDir.Replace('\', '/')
if (-not $SkipEnvVar) {
    info "Setting GENTLEMAN_AGENT_ROOT → $__rootDir"
    $env:GENTLEMAN_AGENT_ROOT = $__rootDir
    if ($IsLinux -or $IsMacOS) {
        $profileFile = if ($IsMacOS) { "$HOME/.zshrc" } else { "$HOME/.bashrc" }
        $exportLine = "export GENTLEMAN_AGENT_ROOT=`"$__rootDir`""
        if (-not (Test-Path $profileFile) -or -not (Select-String -Path $profileFile -Pattern "GENTLEMAN_AGENT_ROOT" -Quiet)) {
            Add-Content -Path $profileFile -Value "`n# Gentleman Agent`n$exportLine"
            ok "GENTLEMAN_AGENT_ROOT added to $profileFile (restart shell to apply)"
        } else { skip "GENTLEMAN_AGENT_ROOT already in $profileFile" }
    } else {
        $current = [Environment]::GetEnvironmentVariable("GENTLEMAN_AGENT_ROOT", "User")
        if ($current -ne $__rootDir) {
            [Environment]::SetEnvironmentVariable("GENTLEMAN_AGENT_ROOT", $__rootDir, "User")
            ok "GENTLEMAN_AGENT_ROOT set (takes effect in new shells)"
        } else { skip "GENTLEMAN_AGENT_ROOT already set correctly" }
    }
} else { skip "GENTLEMAN_AGENT_ROOT (via -SkipEnvVar)" }

# Step 2: pre-commit hooks
info "Setting up pre-commit framework"
$pc = py -m pre_commit --version 2>$null
if ($pc) { ok "pre-commit $pc already installed" }
else {
    info "Installing pre-commit via pip..."
    py -m pip install pre-commit -q 2>$null
    if ($?) { ok "pre-commit installed" } else { warn "pre-commit install failed — CI can run it standalone" }
}
if ($pc) {
    if ($DryRun) {
        info "Would install pre-commit hooks"
    } else {
        $hooksPath = git config core.hooksPath 2>$null
        if ([string]::IsNullOrEmpty($hooksPath) -or $Force) {
            py -m pre_commit install 2>$null
            if ($?) { ok "pre-commit hooks installed" } else { warn "pre-commit hooks install failed" }
        } else { skip "pre-commit hooks (hooksPath=$hooksPath — managed by OpenCode)" }
    }
}

# Step 3: OpenCode env vars
info "Setting OpenCode environment variables"
$ocVars = @{
    "OPENCODE_DISABLE_EMBEDDED_WEB_UI" = "true"
    "OPENCODE_DISABLE_MODELS_FETCH"    = "true"
    "OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER" = "true"
}
foreach ($kv in $ocVars.GetEnumerator()) {
    $current = [Environment]::GetEnvironmentVariable($kv.Key, "User")
    if ($current -ne $kv.Value -or $Force) {
        if ($DryRun) { info "Would set $($kv.Key)=$($kv.Value)" }
        else {
            [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "User")
            Set-Item -Path "env:$($kv.Key)" -Value $kv.Value
            ok "$($kv.Key) set"
        }
    } else { skip "$($kv.Key) already set" }
}

# Step 4: Global shortcuts
if (-not $SkipShortcuts) {
    info "Creating global shell shortcuts"
    $npmDir = "$env:APPDATA\npm"
    if (-not (Test-Path $npmDir)) { New-Item -ItemType Directory -Path $npmDir -Force | Out-Null }
    $shortcuts = @(@{ Name = "gentleman-vmk"; Ps1Cmd = "opencode --agent gentleman-vMK @args"; CmdCmd = "opencode --agent gentleman-vMK %*" })
    foreach ($sc in $shortcuts) {
        $ps1Path = Join-Path $npmDir "$($sc.Name).ps1"
        $cmdPath = Join-Path $npmDir "$($sc.Name).cmd"
        if ($DryRun) {
            if (-not (Test-Path $ps1Path) -or $Force) { info "Would create $ps1Path" }
            if (-not (Test-Path $cmdPath) -or $Force) { info "Would create $cmdPath" }
            continue
        }
        if (-not (Test-Path $ps1Path) -or $Force) {
            Set-Content -Path $ps1Path -Value "# $($sc.Name).ps1`n$($sc.Ps1Cmd)`nif (`$LASTEXITCODE -and `$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }"
            ok "Created $ps1Path"
        } else { skip "$ps1Path already exists" }
        if (-not (Test-Path $cmdPath) -or $Force) {
            Set-Content -Path $cmdPath -Value "@echo off`n$($sc.CmdCmd)"
            ok "Created $cmdPath"
        } else { skip "$cmdPath already exists" }
    }
} else { skip "Global shortcuts (via -SkipShortcuts)" }

# Step 5: Global opencode config
info "Syncing global opencode config from repo"
$globalConfigPath = Join-Path (Get-GlobalConfigDir) "opencode.json"
$repoConfigPath = Join-Path $RepoDir "opencode.json"
if ((Test-Path $globalConfigPath) -and (Test-Path $repoConfigPath)) {
    if ($DryRun) {
        info "Would sync global opencode config from repo"
    } else {
        $globalConfig = Get-Content $globalConfigPath -Raw | ConvertFrom-Json
        $repoConfig = Get-Content $repoConfigPath -Raw | ConvertFrom-Json
        $synced = $Force
        if (-not $globalConfig.default_agent -or $globalConfig.default_agent -ne "gentleman-vMK") {
            $globalConfig | Add-Member -NotePropertyName "default_agent" -NotePropertyValue "gentleman-vMK" -Force
            $synced = $true
        }
        foreach ($section in @("mcp", "permission", "skills", "agent")) {
            $repoValue = $repoConfig.$section
            if ($repoValue) { $globalConfig | Add-Member -NotePropertyName $section -NotePropertyValue $repoValue -Force; $synced = $true }
        }
        if ($synced) { $globalConfig | ConvertTo-Json -Depth 10 | Set-Content $globalConfigPath; ok "Global config synced" }
        else { skip "Global config already up to date" }
    }
} else { warn "Global or repo config not found — sync manually" }

# Step 6: Global skill config + prompts junction + AGENTS.md
info "Setting up global skill config"
$globalSkillsDir = Join-Path (Get-GlobalConfigDir) "skills"
$repoSkillsDir = Join-Path $RepoDir ".agents\skills"
if (-not (Test-Path $globalSkillsDir)) { New-Item -ItemType Directory -Path $globalSkillsDir -Force | Out-Null }
if ($DryRun) {
    if (-not (Test-Path "$globalSkillsDir\_shared") -or $Force) { info "Would create skills junction at $globalSkillsDir" }
} elseif (-not (Test-Path "$globalSkillsDir\_shared") -or $Force) {
    New-CrossPlatLink -Path "$globalSkillsDir" -Target $repoSkillsDir
    if ($?) { ok "Skills junction created at $globalSkillsDir" }
    else { warn "Could not create junction (needs admin/elevation). Copy skills manually." }
} else { skip "Skills junction already exists" }

info "Setting up global prompts junction"
$globalPromptsDir = Join-Path (Get-GlobalConfigDir) "prompts"
$repoSddDir = Join-Path $RepoDir "prompts\sdd"
if (Test-Path $repoSddDir) {
    $sddJunction = "$globalPromptsDir\sdd"
    if ($DryRun) {
        if (-not (Test-Path $sddJunction) -or $Force) { info "Would create prompts junction at $sddJunction" }
    } elseif (-not (Test-Path $sddJunction) -or $Force) {
        if (-not (Test-Path $globalPromptsDir)) { New-Item -ItemType Directory -Path $globalPromptsDir -Force | Out-Null }
        New-CrossPlatLink -Path $sddJunction -Target $repoSddDir
        if ($?) { ok "Prompts junction created at $sddJunction" }
        else { warn "Could not create prompts junction. Copy prompts manually: Copy-Item '$repoSddDir' '$sddJunction' -Recurse" }
    } else { skip "Prompts junction already exists" }
} else { warn "Repo prompts/sdd not found at $repoSddDir" }

$globalAgentsMd = Join-Path (Get-GlobalConfigDir) "AGENTS.md"
$repoAgentsMd = Join-Path $RepoDir "AGENTS.md"
if (Test-Path $repoAgentsMd) {
    if ($DryRun) {
        if (-not (Test-Path $globalAgentsMd) -or $Force) { info "Would copy AGENTS.md to global config" }
    } elseif (-not (Test-Path $globalAgentsMd) -or $Force) { Copy-Item -Path $repoAgentsMd -Destination $globalAgentsMd -Force; ok "AGENTS.md copied to global config" }
    else { skip "AGENTS.md already exists in global config" }
} else { warn "Repo AGENTS.md not found at $repoAgentsMd" }

# Step 7: Install MCP server binaries
function Install-McpServer {
    param([string]$Name, [scriptblock]$Check, [scriptblock]$Install, [string]$ManualHint, [switch]$DoDryRun)
    if ((& $Check) -and -not $Force) { skip "$Name already installed"; return $false }
    if ($DoDryRun) { info "Would install $Name"; return $false }
    try { info "Installing $Name..."; $script:LASTEXITCODE = 0; & $Install; if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }; ok "$Name installed"; return $true }
    catch { warn "$Name install failed — $ManualHint"; return $false }
}

if (-not $SkipMcp) {
    info "Installing MCP server binaries"
    $anyMcp = $false
    $anyMcp = (Install-McpServer -Name "codebase-memory-mcp" -Check { Get-Command "codebase-memory-mcp" -EA SilentlyContinue } -Install { npm install -g codebase-memory-mcp --no-fund --no-audit --loglevel error 2>$null } -ManualHint "npm install -g codebase-memory-mcp" -DoDryRun:$DryRun) -or $anyMcp
    $anyMcp = (Install-McpServer -Name "headroom" -Check { Get-Command "headroom" -EA SilentlyContinue } -Install { pip install headroom-ai -q 2>$null } -ManualHint "pip install headroom-ai" -DoDryRun:$DryRun) -or $anyMcp

    # engram — GitHub releases (GoReleaser binary)
    if ((Get-Command "engram" -EA SilentlyContinue) -and -not $Force) { skip "engram already installed" }
    elseif ($DryRun) { info "Would install engram from GitHub releases" }
    else {
        info "Installing engram from GitHub releases..."
        try {
            $script:IsWindows = $env:OS -eq 'Windows_NT'
            $script:IsLinux   = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)
            $script:IsMacOS   = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
            $os = if ($script:IsWindows -or (-not $script:IsLinux -and -not $script:IsMacOS -and $env:OS -match "Windows")) { "windows" } elseif ($script:IsMacOS) { "darwin" } else { "linux" }
            $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "arm64" }
            $ext = if ($os -eq "windows") { "zip" } else { "tar.gz" }
            $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/Gentleman-Programming/engram/releases/latest" -EA SilentlyContinue -UseBasicParsing
            if (-not $latest) { throw "Could not fetch engram release info" }
            $version = $latest.tag_name.TrimStart('v')
            $url = "https://github.com/Gentleman-Programming/engram/releases/download/v$version/engram_${version}_${os}_${arch}.${ext}"
            $tmpDir = Join-Path $env:TEMP "engram-$(Get-Random)"
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
            $archive = Join-Path $tmpDir "engram.$ext"
            Write-Host "       Downloading v$version ($os/$arch)..."
            Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
            $fileInfo = Get-Item $archive
            if ($fileInfo.Length -lt 1MB) { throw "Downloaded file too small ($($fileInfo.Length) bytes) — likely corrupted" }
            if ($os -eq "windows") { Expand-Archive -Path $archive -DestinationPath $tmpDir -Force } else { tar -xzf $archive -C $tmpDir 2>$null }
            $exeName = if ($os -eq "windows") { "engram.exe" } else { "engram" }
            $binary = Get-ChildItem -Path $tmpDir -Recurse -Filter $exeName -EA SilentlyContinue | Select-Object -First 1
            if (-not $binary) { throw "Binary not found in archive" }
            $binDir = "$env:APPDATA\npm"
            if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
            Copy-Item -Path $binary.FullName -Destination (Join-Path $binDir $exeName) -Force
            Remove-Item -Path $tmpDir -Recurse -Force -EA SilentlyContinue
            ok "engram v$version installed"; $anyMcp = $true
        } catch { warn "engram install failed — download manually from https://github.com/Gentleman-Programming/engram/releases" }
    }
} else { skip "MCP server binaries (via -SkipMcp)" }

# Step 7b: Ollama (vision analysis)
if (-not $SkipVision) {
    info "Setting up Ollama for local vision analysis"
    if ($DryRun) {
        if (-not (Get-Command "ollama" -EA SilentlyContinue) -or $Force) { info "Would install Ollama" }
        if (-not (Get-Command "moondream" -EA SilentlyContinue)) { info "Would pull moondream:latest model" }
    } else {
        $ollamaCmd = Get-Command "ollama" -EA SilentlyContinue
        if (-not $ollamaCmd -or $Force) {
            $scoopCmd = Get-Command "scoop" -EA SilentlyContinue
            if ($scoopCmd) {
                info "Installing Ollama via scoop..."
                scoop install ollama 2>$null
                if ($?) { $ollamaCmd = Get-Command "ollama" -EA SilentlyContinue; ok "Ollama installed via scoop" } else { warn "Ollama scoop install failed — download from https://ollama.com/download" }
            } else { warn "scoop not found — install Ollama manually from https://ollama.com/download" }
        } else { skip "Ollama already installed" }
        $ollamaExe = if ($ollamaCmd) { $ollamaCmd.Source } else { Join-Path (Join-Path $HOME "scoop") "apps" "ollama" "current" "ollama.exe" }
        if (Test-Path $ollamaExe) {
            $models = & $ollamaExe list 2>$null
            if ($models -notmatch "moondream") {
                info "Pulling moondream:latest model (~1.7GB, vision analysis)..."
                & $ollamaExe pull moondream:latest 2>$null
                if ($?) { ok "moondream:latest pulled" } else { warn "moondream pull failed — run: ollama pull moondream:latest" }
            } else { skip "moondream:latest already pulled" }
        }
    }
} else { skip "Vision setup (via -SkipVision)" }

# Step 8: Verify
info "Verifying setup"
$verifyCmds = Get-Command gentleman-vmk, codebase-memory-mcp, headroom, engram, ollama -EA SilentlyContinue
$checks = @(
    @{ Label = "GENTLEMAN_AGENT_ROOT"; Test = { $env:GENTLEMAN_AGENT_ROOT -eq $__rootDir } },
    @{ Label = "opencode.json exists"; Test = { Test-Path (Join-Path $RepoDir "opencode.json") } },
    @{ Label = "Global shortcut: gentleman-vmk"; Test = { $verifyCmds.Name -contains "gentleman-vmk" } },
    @{ Label = "MCP: codebase-memory-mcp"; Test = { $verifyCmds.Name -contains "codebase-memory-mcp" } },
    @{ Label = "MCP: headroom"; Test = { $verifyCmds.Name -contains "headroom" } },
    @{ Label = "MCP: engram"; Test = { $verifyCmds.Name -contains "engram" } },
    @{ Label = "Vision: Ollama"; Test = { $verifyCmds.Name -contains "ollama" } },
    @{ Label = "Vision: moondream model"; Test = {
    $exe = (Get-Command "ollama" -EA SilentlyContinue)?.Source
    if (-not $exe) { $exe = Join-Path (Join-Path $HOME "scoop") "apps" "ollama" "current" "ollama.exe" }
    if ($exe -and (Test-Path $exe)) { (& $exe list 2>$null) -match "moondream" } else { $false }
} }
)
$allOk = $true
foreach ($c in $checks) {
    if (($SkipShortcuts -and $c.Label -like "Global shortcut*") -or `
        ($SkipMcp      -and $c.Label -like "MCP*") -or `
        ($SkipVision   -and $c.Label -like "Vision*")) {
        skip "$($c.Label) (via skip flag)"
        continue
    }
    if (& $c.Test) { ok $c.Label }
    else { warn "$($c.Label) — FAILED"; $allOk = $false }
}

if ($allOk) {
    Write-Host ""
    if ($DryRun) {
        Write-Host "✅ DRY-RUN — nothing was applied. Review steps above, then re-run without -DryRun." -ForegroundColor Cyan
    } else {
        Write-Host "✅ Machine setup COMPLETE" -ForegroundColor Green
        Write-Host "   → Run 'gentleman-vmk' to launch" -ForegroundColor Cyan
    }
} else {
    Write-Host ""
    Write-Host "⚠️  Setup PARTIAL — review warnings above" -ForegroundColor Yellow
}
