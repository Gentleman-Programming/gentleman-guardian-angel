# ============================================================================
# Gentleman Guardian Angel - Windows Installer
# ============================================================================
# Installs the gga CLI tool to your system
# ============================================================================

param(
    [string]$InstallDir = ""
)

$ErrorActionPreference = "Stop"

function Write-Color {
    param(
        [string]$Message = "",
        [string]$Color = "White",
        [switch]$Bold
    )
    Write-Host $Message -ForegroundColor $Color
}

Write-Color "" "Cyan"
Write-Color "============================================================" "Cyan"
Write-Color "  Gentleman Guardian Angel - Installer" "Cyan"
Write-Color "============================================================" "Cyan"
Write-Color "" "Cyan"

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Get-Location
}

$UserHome = [System.Environment]::GetFolderPath('UserProfile')
if ($InstallDir -eq "") {
    $InstallDir = Join-Path $UserHome "bin"
}

Write-Color "Install directory: $InstallDir" "Blue"
Write-Color "" "Blue"

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$ggaExe = Join-Path $InstallDir "gga.ps1"
$ggaCmd = Join-Path $InstallDir "gga.cmd"

if (Test-Path $ggaExe) {
    Write-Color "gga is already installed" "Yellow"
    $confirm = Read-Host "Reinstall? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Color "Aborted." "Yellow"
        exit 0
    }
}

$LibInstallDir = Join-Path $UserHome ".local\share\gga\lib"
if (-not (Test-Path $LibInstallDir)) {
    New-Item -ItemType Directory -Path $LibInstallDir -Force | Out-Null
}

$SourceFiles = @{
    Gga = Join-Path $ScriptDir "bin\gga.ps1"
    Providers = Join-Path $ScriptDir "lib\providers.ps1"
    Cache = Join-Path $ScriptDir "lib\cache.ps1"
    PrMode = Join-Path $ScriptDir "lib\pr_mode.ps1"
}

foreach ($entry in $SourceFiles.GetEnumerator()) {
    if (-not (Test-Path -Path $entry.Value -PathType Leaf)) {
        Write-Color "Error: Source file not found: $($entry.Value)" "Red"
        exit 1
    }
}

Copy-Item $SourceFiles.Gga $ggaExe -Force
Copy-Item $SourceFiles.Providers (Join-Path $LibInstallDir "providers.ps1") -Force
Copy-Item $SourceFiles.Cache (Join-Path $LibInstallDir "cache.ps1") -Force
Copy-Item $SourceFiles.PrMode (Join-Path $LibInstallDir "pr_mode.ps1") -Force

$ggaCmdPath = Join-Path $InstallDir "gga.cmd"
$cmdContent = "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gga.ps1`" %*"
Set-Content $ggaCmdPath -Value $cmdContent -Encoding ascii

Write-Color "Installed gga to $InstallDir" "Green"
Write-Color "" "Green"

$PathEnv = [System.Environment]::GetEnvironmentVariable("Path", "User")
$PathEntries = $PathEnv -split ';' | ForEach-Object { $_.Trim() }
$IsInPath = $PathEntries -contains $InstallDir

if (-not $IsInPath) {
    Write-Color "$InstallDir is not in your PATH" "Yellow"
    Write-Color "" "Yellow"
    Write-Color "Add this line to your PowerShell profile or run:" "Yellow"
    Write-Color "" "Yellow"
    Write-Color "  `$env:Path += `";$InstallDir`"" "Cyan"
    Write-Color "" "Yellow"
    Write-Color "Or permanently add to user PATH:" "Yellow"
    Write-Color "  [System.Environment]::SetEnvironmentVariable(`"Path`", `$env:Path + `";$InstallDir`" , `"User`")" "Cyan"
    Write-Color "" "Yellow"
}

Write-Color "Getting started:" -Bold
Write-Color "" -Bold
Write-Color "  1. Navigate to your project:"
Write-Color "     cd C:\path\to\your\project"
Write-Color "" -Bold
Write-Color "  2. Add to PATH (if not already):"
Write-Color "     `$env:Path += `";$InstallDir`""
Write-Color "" -Bold
Write-Color "  3. Initialize config:"
Write-Color "     gga init"
Write-Color "" -Bold
Write-Color "  4. Create your AGENTS.md with coding standards"
Write-Color "" -Bold
Write-Color "  5. Install the git hook:"
Write-Color "     gga install"
Write-Color "" -Bold
Write-Color "  6. You're ready! The hook will run on each commit."
Write-Color ""
