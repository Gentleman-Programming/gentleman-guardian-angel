#requires -Version 7
#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
param([switch]$Quiet,[string[]]$Args)
$ErrorActionPreference = 'Continue'
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")
<#
.SYNOPSIS
    Universal runner — discover GENTLEMAN_AGENT_ROOT and invoke a repo script.

.DESCRIPTION
    Resolves the repo root even when invoked from the global junction at
    ~/.config/opencode/scripts/. Sets $env:GENTLEMAN_AGENT_ROOT and delegates
    to the named script in the repo's scripts/ directory.

    Portable: works on any machine via $env:USERPROFILE (system env var).
    No PS Profile dependency.

.EXAMPLE
    & "~/.config/opencode/scripts/run.ps1" check-skill-drift.ps1 -Json
    & "~/.config/opencode/scripts/run.ps1" close-session.ps1
#>
$__dir = Split-Path $MyInvocation.MyCommand.Path -Parent
$__item = Get-Item $__dir

if ($__item.LinkType -eq "Junction" -and $__item.Target) {
    $env:GENTLEMAN_AGENT_ROOT = (Split-Path $__item.Target -Parent).Replace('\', '/')
} else {
    $env:GENTLEMAN_AGENT_ROOT = (Split-Path $__dir -Parent).Replace('\', '/')
}

if (-not $args -or $args.Count -eq 0) {
    Write-Error "Usage: run.ps1 <script.ps1> [args...]"
    exit 1
}

$__scriptName = $args[0]
$__scriptPath = Join-Path "$env:GENTLEMAN_AGENT_ROOT\scripts" $__scriptName

if (-not (Test-Path $__scriptPath)) {
    Write-Error "Script not found: $__scriptPath"
    exit 1
}

$__scriptArgs = @($args[1..$args.Length])
try {
    & $__scriptPath @__scriptArgs
    exit $LASTEXITCODE
} catch {
    Write-Error "Script execution failed: $_"
    exit 1
}


