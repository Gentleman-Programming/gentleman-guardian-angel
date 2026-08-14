#requires -Version 7
<#
.SYNOPSIS
    E2E testing wrapper — simple interactive tests with Playwright

.DESCRIPTION
    Like analyze-page.ps1 but with interactive actions (click, fill, type, etc.)

.PARAMETER Url
    URL to test

.PARAMETER Actions
    Comma-separated actions: click:#selector,fill:#selector=value,wait:#selector

.PARAMETER Analyze
    Run Ollama analysis on final screenshot

.PARAMETER Model
    Ollama model for analysis (default: moondream:latest)

.PARAMETER Screenshot
    Filename for final screenshot (default: e2e-final.png)

.PARAMETER Headed
    Open browser visually (not headless)

.EXAMPLE
    .\e2e-test.ps1 -Url "http://localhost:3000" -Actions "click:#login,fill:#email=user@test.com"

.EXAMPLE
    .\e2e-test.ps1 -Url "http://localhost:3000" -Actions "click:#login" -Analyze

.EXAMPLE
    .\e2e-test.ps1 -Url "http://localhost:3000" -Actions "click:#login" -Headed
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [Parameter(Mandatory = $false)]
    [string]$Actions = '',

    [switch]$Analyze,

    [string]$Model = 'moondream:latest',

    [string]$Screenshot = 'e2e-final.png',

    [int]$Timeout = 30000,

    [switch]$Headed
)
Set-StrictMode -Version Latest

# Make native (node) non-zero exits observable as terminating errors in PS 7.3+,
# and always propagate node's real exit code (see exit at the bottom).
$PSNativeCommandUseErrorActionPreference = $true

$ErrorActionPreference = 'Stop'

# Resolve script path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$jsScript = Join-Path $scriptDir 'e2e-test.js'

if (-not (Test-Path $jsScript)) {
    Write-Error "e2e-test.js not found at: $jsScript"
    exit 1
}

# Build arguments
$nodeArgs = @($jsScript, '--url', $Url)

if ($Actions) {
    $nodeArgs += '--actions'
    $nodeArgs += $Actions
}

if ($Analyze) {
    $nodeArgs += '--analyze'
    $nodeArgs += '--model'
    $nodeArgs += $Model
}

if ($Screenshot) {
    $nodeArgs += '--screenshot'
    $nodeArgs += $Screenshot
}

if ($Timeout) {
    $nodeArgs += '--timeout'
    $nodeArgs += $Timeout.ToString()
}

if ($Headed) {
    $nodeArgs += '--headed'
}

# Execute
Write-Host "=== E2E Test ===" -ForegroundColor Cyan
Write-Host "URL: $Url"
Write-Host "Actions: $Actions"
Write-Host ""

try {
    & node @nodeArgs
} catch {
    Write-Error "E2E test failed: $_"
    exit 1
}

# Belt and suspenders: propagate node's real exit code (PS 5.1 has no
# $PSNativeCommandUseErrorActionPreference, so a non-zero node exit falls
# through to here instead of the catch).
exit $LASTEXITCODE
