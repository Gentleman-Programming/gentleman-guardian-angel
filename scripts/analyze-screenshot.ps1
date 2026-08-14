#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Capture screenshot and analyze via local Ollama multimodal model.
.DESCRIPTION
    Takes a screenshot (or uses existing image) and sends it to Ollama
    for UI/error/design/accessibility/performance analysis. Zero cost, 100% local.
.PARAMETER ImagePath
    Path to existing image. If not provided, captures full screen screenshot.
.PARAMETER Model
    Ollama model to use (default: moondream). Options: moondream, llava:7b, llava:13b
.PARAMETER Mode
    Analysis mode: ui, error, design, accessibility, performance (default: ui)
.PARAMETER Prompt
    Custom prompt. Overrides Mode if provided.
.PARAMETER OllamaUrl
    Ollama API URL (default: http://localhost:11434)
.PARAMETER OutputPath
    Save results to JSON file. Default: stdout only.
.PARAMETER Compare
    Second image path for before/after comparison.
#>
param(
    [string]$ImagePath,
    [string]$Model = "moondream:latest",
    [ValidateSet("ui", "error", "design", "accessibility", "performance")]
    [string]$Mode = "ui",
    [string]$Prompt,
    [string]$OllamaUrl = "http://localhost:11434",
    [string]$OutputPath,
    [string]$Compare
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Mode prompts ---
$modePrompts = @{
    ui = "Analyze this UI screenshot. Identify: layout issues, alignment problems, contrast failures, missing elements, broken components, accessibility concerns. Be specific about what's wrong and where. Rate severity: critical/major/minor for each finding."
    error = "What error or issue does this screenshot show? Identify the exact error message, affected component, and suggested fix. If no error is visible, describe what you see."
    design = "Compare this UI against best practices: spacing, typography hierarchy, color consistency, visual balance, whitespace usage, visual weight distribution. List specific improvements with references to visible elements."
    accessibility = "Analyze this screenshot for WCAG 2.2 issues: contrast ratios (minimum 4.5:1 for text), text size (minimum 16px body), touch targets (minimum 44x44px), focus indicators, semantic structure, color independence. Rate each: critical/major/minor."
    performance = "What performance issues can you infer from this screenshot? Look for: layout shift indicators, missing images, loading spinners, render blocking artifacts, CLS issues, slow-loading content patterns."
}

# --- Resolve prompt ---
$analysisPrompt = if ($Prompt) { $Prompt } else { $modePrompts[$Mode] }

if ($Compare) {
    $analysisPrompt = "Compare these two UI screenshots (before and after). Identify: what changed, what improved, what regressed, what still needs work. Be specific about visual differences and their impact on UX."
}

# --- Capture screenshot if no image provided ---
$tempDir = Join-Path $env:TEMP "opencode\vision"
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

if (-not $ImagePath -or -not (Test-Path $ImagePath)) {
    Write-Host "📸 Capturing screenshot..."
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ImagePath = Join-Path $tempDir "screenshot_$timestamp.png"

    if ($IsWindows) {
        # Use .NET Screen Capture (Windows only)
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $bounds = $screen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save($ImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
    } elseif ($IsLinux) {
        # Linux: try gnome-screenshot or scrot
        if (Get-Command gnome-screenshot -ErrorAction SilentlyContinue) {
            & gnome-screenshot -f $ImagePath 2>$null
        } elseif (Get-Command scrot -ErrorAction SilentlyContinue) {
            & scrot $ImagePath 2>$null
        } else {
            Write-Host "⚠️  No screenshot tool found. Install gnome-screenshot or scrot."
            Write-Host "   Or provide -ImagePath with an existing screenshot."
            exit 1
        }
    } elseif ($IsMacOS) {
        # macOS: use screencapture
        if (Get-Command screencapture -ErrorAction SilentlyContinue) {
            & screencapture -x $ImagePath 2>$null
        } else {
            Write-Host "⚠️  screencapture not found."
            Write-Host "   Or provide -ImagePath with an existing screenshot."
            exit 1
        }
    }

    Write-Host "   Saved: $ImagePath"
}

# --- Verify Ollama is running ---
Write-Host "🔍 Checking Ollama at $OllamaUrl..."
try {
    $health = Invoke-RestMethod -Uri "$OllamaUrl/api/tags" -Method Get -TimeoutSec 5
    $availableModels = $health.models.name
    if ($Model -notin $availableModels) {
        Write-Warning "Model '$Model' not found. Available: $($availableModels -join ', ')"
        Write-Host "   Pull it: ollama pull $Model"
        exit 1
    }
    Write-Host "   ✅ Ollama running, model '$Model' available"
} catch {
    Write-Warning "Ollama not responding at $OllamaUrl"
    Write-Host "   Start it: ollama serve"
    Write-Host "   Or install: https://ollama.com/download"
    Write-Host ""
    Write-Host "Falling back to visual analysis (Read tool)..."
    Write-Host "Image saved at: $ImagePath"
    Write-Host "Use the Read tool to view the image and analyze manually."
    exit 0
}

# --- Prepare images array ---
$images = @($ImagePath)
if ($Compare -and (Test-Path $Compare)) {
    $images = @($ImagePath, $Compare)
}

# --- Send to Ollama ---
Write-Host "🧠 Analyzing with $Model (mode: $Mode)..."

$imageBase64 = @()
foreach ($img in $images) {
    $bytes = [System.IO.File]::ReadAllBytes($img)
    $imageBase64 += [Convert]::ToBase64String($bytes)
}

$body = @{
    model = $Model
    messages = @(
        @{
            role = "user"
            content = $analysisPrompt
            images = $imageBase64
        }
    )
    stream = $false
} | ConvertTo-Json -Depth 5

$startTime = Get-Date
try {
    $response = Invoke-RestMethod -Uri "$OllamaUrl/api/chat" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 120
    $elapsed = ((Get-Date) - $startTime).TotalSeconds

    $result = $response.message.content

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════"
    Write-Host "  🔍 Vision Analysis ($Mode mode) — ${elapsed}s"
    Write-Host "═══════════════════════════════════════════════════"
    Write-Host ""
    Write-Host $result
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════"
    Write-Host "  Model: $Model | Image: $(Split-Path $ImagePath -Leaf)"
    Write-Host "═══════════════════════════════════════════════════"

    # --- Save to JSON if requested ---
    if ($OutputPath) {
        $output = [PSCustomObject]@{
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            mode = $Mode
            model = $Model
            image = $ImagePath
            compare = $Compare
            elapsed_seconds = [Math]::Round($elapsed, 2)
            analysis = $result
        }
        $output | ConvertTo-Json -Depth 3 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host ""
        Write-Host "📄 Results saved to: $OutputPath"
    }

} catch {
    Write-Warning "Ollama API error: $_"
    Write-Host "Falling back to visual analysis..."
    Write-Host "Image saved at: $ImagePath"
    exit 1
}
