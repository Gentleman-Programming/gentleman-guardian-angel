#requires -Version 7
<#
.SYNOPSIS
    Cross-platform helpers for PowerShell 7 scripts — Windows, Linux, macOS.
.DESCRIPTION
    Dot-sourced by sync-all.ps1, global-setup.ps1, sync-vmk.ps1.
    Provides: Get-GentlemanRoot, Get-GentlemanProjectRoot, Get-GlobalConfigDir,
    New-CrossPlatLink, Find-Pwsh.
.NOTES
    This file is NOT meant to be invoked directly.
#>

function Get-GentlemanRoot {
    <#
    .SYNOPSIS
        Returns the canonical gentleman-agent-gh repo root.
    .DESCRIPTION
        The script's own repo is ALWAYS canonical when platform.ps1 lives inside
        the real repo: repo root is derived from $PSScriptRoot (scripts/lib → root)
        and validated with a REAL repo marker (.git). From a global copy
        (~/.config/opencode/scripts) the marker is absent, so the guard fails and
        control falls back to $env:GENTLEMAN_AGENT_ROOT — never the global config
        dir. NOTE: this resolves the SCRIPT'S repo, NOT the current project. For
        the project's root (mode file, audit log) use Get-GentlemanProjectRoot.
    #>
    $libDir = $PSScriptRoot                    # scripts/lib
    $repoRoot = Split-Path (Split-Path $libDir -Parent) -Parent
    if (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) { return $repoRoot }
    return $env:GENTLEMAN_AGENT_ROOT           # global-copy / shim fallback
}

function Get-GentlemanProjectRoot {
    <#
    .SYNOPSIS
        Returns the root of the CURRENT project (walk-up from cwd to git root).
    .DESCRIPTION
        Starts at (Get-Location).Path and walks UP looking for the first .git
        marker (project boundary). If found → that directory is the project root.
        If NO .git is found → returns cwd (deterministic default). NEVER walks
        past the found .git (cut line — prevents inheriting a mode or audit
        target from HOME or other unrelated ancestors). Read-only: does not read
        or write anything.
    .EXAMPLE
        Get-GentlemanProjectRoot   # D:\some\git\repo when cwd is inside it
    #>
    $dir = (Get-Location).Path
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) { return $dir }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { return (Get-Location).Path }
        $dir = $parent
    }
}

function Get-GlobalConfigDir {
    <#
    .SYNOPSIS
        Returns the opencode global config directory for the current OS.
        Windows: $env:USERPROFILE\.config\opencode
        Linux/macOS: $HOME/.config/opencode
    #>
    if ($IsLinux -or $IsMacOS) {
        return Join-Path (Join-Path $HOME ".config") "opencode"
    }
    return Join-Path (Join-Path $env:USERPROFILE ".config") "opencode"
}

function New-CrossPlatLink {
    <#
    .SYNOPSIS
        Creates a directory link: Junction on Windows, Symlink on Linux/macOS.
    .PARAMETER Path
        The link path to create.
    .PARAMETER Target
        The existing directory to link to.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path, [string]$Target)
    if ($PSCmdlet.ShouldProcess($Path, 'Create cross-platform link')) {
        if ($IsLinux -or $IsMacOS) {
            New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null
        } else {
            New-Item -ItemType Junction -Path $Path -Target $Target -Force | Out-Null
        }
    }
}

function Find-Pwsh {
    <#
    .SYNOPSIS
        Finds PowerShell 7+ executable. Returns the CommandInfo or $null.
        Checks 'pwsh' first (Linux/macOS), then 'pwsh.exe' (Windows).
    #>
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd }
    return Get-Command pwsh.exe -ErrorAction SilentlyContinue
}
