#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Quick wrapper for analyze-page.js — capture and analyze web pages.
.DESCRIPTION
    Simplifies Playwright + Ollama analysis. Auto-detects dev server URL.
.PARAMETER Url
    Full URL to analyze. If omitted, tries common dev server ports.
.PARAMETER Mode
    Analysis mode: ui, error, design, accessibility, performance (default: ui)
.PARAMETER Route
    Route path to append to base URL (e.g., /catalogos)
.PARAMETER FullPage
    Capture full page instead of viewport only.
.PARAMETER NoAnalysis
    Capture screenshot only, skip Ollama analysis.
.PARAMETER Output
    Save screenshot to specific path.
.EXAMPLE
    .\analyze-page.ps1 http://localhost:3000/catalogos
    .\analyze-page.ps1 -Route /catalogos -Mode error
    .\analyze-page.ps1 http://localhost:5173 -FullPage
#>
param(
    [string]$Url,
    [ValidateSet("ui", "error", "design", "accessibility", "performance")]
    [string]$Mode = "ui",
    [string]$Route = "/",
    [switch]$FullPage,
    [switch]$NoAnalysis,
    [string]$Output
)
Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$analyzePage = Join-Path $scriptDir "analyze-page.js"

# --- Auto-detect URL if not provided ---
if (-not $Url) {
    $commonPorts = @(3000, 5173, 4200, 8080, 8000, 4000)
    $found = $false

    foreach ($port in $commonPorts) {
        try {
            $null = Invoke-WebRequest -Uri "http://localhost:$port" -Method Head -TimeoutSec 1 -ErrorAction Stop
            $Url = "http://localhost:$port"
            Write-Host "✅ Found dev server at $Url"
            $found = $true
            break
        } catch {
            Write-Debug "analyze-page: $($_.Exception.Message)"
            # Port not responding, try next
        }
    }

    if (-not $found) {
        Write-Warning "No dev server found on common ports (3000, 5173, 4200, 8080, 8000, 4000)"
        Write-Host "Provide URL explicitly: .\analyze-page.ps1 http://localhost:3000/catalogos"
        exit 1
    }
}

# --- Build full URL ---
if ($Route -ne "/") {
    $Url = $Url.TrimEnd('/') + $Route
}

# --- Build arguments ---
$nodeArgs = @($analyzePage, $Url, "--mode", $Mode, "--wait", "3000")

if ($FullPage) { $nodeArgs += "--full" }
if ($NoAnalysis) { $nodeArgs += "--no-analysis" }
if ($Output) { $nodeArgs += "--output", $Output }

# --- Run ---
Write-Host ""
Write-Host "🚀 Analyzing: $Url"
Write-Host "   Mode: $Mode | Full: $FullPage | Analysis: (-not $NoAnalysis)"
Write-Host ""

& node @nodeArgs
