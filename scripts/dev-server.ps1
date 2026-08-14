#requires -Version 7
<#
.SYNOPSIS
    Manage long-lived dev servers in the background
.DESCRIPTION
    Start, check, and kill long-running processes (npm run dev, python server.py, etc.)
    without blocking the agent. Uses .NET Process with async event-based output capture.

    Output is accumulated in memory and can be read at any time.
    The process runs in the same window (no new console popup).

.PARAMETER Action
    Action to perform: Start, Status, Logs, Kill, List, Cleanup
.PARAMETER Name
    Friendly name for the server (e.g. "frontend", "api", "docs")
.PARAMETER Command
    The executable to run (e.g. "npm", "python", "dotnet")
.PARAMETER Arguments
    Arguments for the command (e.g. "run dev", "server.py")
.PARAMETER WorkingDir
    Working directory for the process (default: current dir)
.PARAMETER Tail
    Number of recent lines to show (default: 5)

.EXAMPLE
    # Start a dev server
    .\scripts\dev-server.ps1 -Action Start -Name frontend -Command npm -Arguments "run dev"

    # Check if it's running
    .\scripts\dev-server.ps1 -Action Status -Name frontend

    # See recent output
    .\scripts\dev-server.ps1 -Action Logs -Name frontend -Tail 10

    # Kill it
    .\scripts\dev-server.ps1 -Action Kill -Name frontend

    # List all running servers
    .\scripts\dev-server.ps1 -Action List

    # Cleanup all dead servers from registry
    .\scripts\dev-server.ps1 -Action Cleanup
#>
param(
    [switch]$Quiet,
    [ValidateSet("Start", "Status", "Logs", "Kill", "List", "Cleanup")]
    [string]$Action = "List",

    [string]$Name = "",

    [string]$Command = "",

    [string]$Arguments = "",

    [string]$WorkingDir = "",

    [int]$Tail = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# ── Registry: persisted in script scope ─────────────────────────────
# Servers are stored in a module-level hashtable. Since this script is
# invoked fresh each time (not dot-sourced), we use a JSON file as
# lightweight IPC so actions in the same session can find each other.
$RegistryPath = Join-Path $env:TEMP "gentleman-dev-servers.json"

function Get-Registry {
    if (Test-Path $RegistryPath) {
        try { return Get-Content $RegistryPath -Raw | ConvertFrom-Json -AsHashtable }
        catch { return @{} }
    }
    return @{}
}

function Save-Registry {
    param($Registry)
    $Registry | ConvertTo-Json | Set-Content $RegistryPath
}

function Get-ServerDir {
    $dir = Join-Path $env:TEMP "gentleman-dev-servers"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

# ── Actions ─────────────────────────────────────────────────────────
function Start-Server {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$N, [string]$Cmd, [string]$ArgStr, [string]$Dir)
    if (-not $N) { Write-Error "Name is required"; return }
    if (-not $Cmd) { Write-Error "Command is required"; return }

    $reg = Get-Registry
    if ($reg.ContainsKey($N)) {
        $existing = $reg[$N]
        if ($existing.pid -and (Get-Process -Id $existing.pid -ErrorAction SilentlyContinue)) {
            Write-Warning "Server '$N' is already running (PID $($existing.pid)). Use Kill first."
            return
        }
        # Dead entry — remove it
        $reg.Remove($N)
    }

    if (-not $Dir) { $Dir = (Get-Location).Path }
    if (-not (Test-Path $Dir)) { Write-Error "Working directory not found: $Dir"; return }

    $outFile = Join-Path (Get-ServerDir) "$N-out.log"
    $errFile = Join-Path (Get-ServerDir) "$N-err.log"

    if ($PSCmdlet.ShouldProcess($N, 'Start dev server')) {
        # Start process with async output capture
        $psi = [System.Diagnostics.ProcessStartInfo]@{
            FileName               = $Cmd
            Arguments              = $ArgStr
            RedirectStandardOutput = $true
            RedirectStandardError  = $true
            UseShellExecute        = $false
            WorkingDirectory       = $Dir
            CreateNoWindow         = $true
        }
        try {
            $p = [System.Diagnostics.Process]::Start($psi)
        } catch {
            Write-Error "Failed to start '$Cmd $ArgStr': $_"
            return
        }

        # Async output → files (avoids deadlock, persists beyond agent session)
        $outStream = [System.IO.StreamWriter]::new($outFile, $false, [System.Text.UTF8Encoding]::new($false))
        $errStream = [System.IO.StreamWriter]::new($errFile, $false, [System.Text.UTF8Encoding]::new($false))
        # Use Register-ObjectEvent: PowerShell .NET events aren't directly callable
        Register-ObjectEvent -InputObject $p -EventName OutputDataReceived -MessageData $outStream -Action {
            $d = $Event.SourceEventArgs.Data
            if ($d) { $Event.MessageData.WriteLine($d); $Event.MessageData.Flush() }
        }
        Register-ObjectEvent -InputObject $p -EventName ErrorDataReceived -MessageData $errStream -Action {
            $d = $Event.SourceEventArgs.Data
            if ($d) { $Event.MessageData.WriteLine($d); $Event.MessageData.Flush() }
        }
        $p.BeginOutputReadLine()
        $p.BeginErrorReadLine()

        # Register
        $entry = @{
            name      = $N
            pid       = $p.Id
            cmd       = $Cmd
            args      = $ArgStr
            dir       = $Dir
            started   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            outFile   = $outFile
            errFile   = $errFile
        }
        $reg[$N] = $entry
        Save-Registry $reg

        # Wait briefly, capture first output lines
        Start-Sleep -Milliseconds 1500
        $initialOut = if (Test-Path $outFile) { Get-Content $outFile -Tail $Tail } else { @() }

        Write-Host "[dev-server] ✅ Started '$N' (PID $($p.Id))" -ForegroundColor Green
        Write-Host "[dev-server]   Cmd: $Cmd $ArgStr" -ForegroundColor DarkGray
        Write-Host "[dev-server]   Dir: $Dir" -ForegroundColor DarkGray
        Write-Host "[dev-server]   Logs: $outFile" -ForegroundColor DarkGray
        if ($initialOut) {
            Write-Host "[dev-server]   Initial output:" -ForegroundColor DarkGray
            $initialOut | ForEach-Object { Write-Host "     $_" }
        }
    }
}

function Get-Status {
    param([string]$N)
    $reg = Get-Registry
    if (-not $N) {
        # Status for all
        if ($reg.Count -eq 0) { Write-Host "No servers registered."; return }
        foreach ($entry in $reg.Values) {
            Get-Status -N $entry.name
        }
        return
    }
    if (-not $reg.ContainsKey($N)) { Write-Warning "Server '$N' not found"; return }
    $e = $reg[$N]
    $proc = Get-Process -Id $e.pid -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "[dev-server] 🟢 '$N' — RUNNING (PID $($e.pid), started $($e.started))" -ForegroundColor Green
    } else {
        Write-Host "[dev-server] 🔴 '$N' — STOPPED (was PID $($e.pid), started $($e.started))" -ForegroundColor Red
    }
}

function Get-Log {
    param([string]$N)
    $reg = Get-Registry
    if (-not $reg.ContainsKey($N)) { Write-Warning "Server '$N' not found"; return }
    $e = $reg[$N]
    $outLines = if (Test-Path $e.outFile) { Get-Content $e.outFile -Tail $Tail } else { @() }
    $errLines = if (Test-Path $e.errFile) { Get-Content $e.errFile -Tail $Tail } else { @() }

    Write-Host "[dev-server] 📋 Logs for '$N' (tail $Tail):" -ForegroundColor Cyan
    if ($outLines) {
        Write-Host "  --- stdout ---" -ForegroundColor DarkGray
        $outLines | ForEach-Object { Write-Host "  $_" }
    }
    if ($errLines) {
        Write-Host "  --- stderr ---" -ForegroundColor DarkYellow
        $errLines | ForEach-Object { Write-Host "  $_" }
    }
    if (-not $outLines -and -not $errLines) {
        Write-Host "  (no output yet)"
    }
}

function Stop-Server {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$N)
    $reg = Get-Registry
    if (-not $reg.ContainsKey($N)) { Write-Warning "Server '$N' not found"; return }
    $e = $reg[$N]
    $proc = Get-Process -Id $e.pid -ErrorAction SilentlyContinue
    if ($PSCmdlet.ShouldProcess($N, 'Stop dev server')) {
        if ($proc) {
            $proc.Kill()
            Write-Host "[dev-server] 🛑 Killed '$N' (PID $($e.pid))" -ForegroundColor Yellow
        } else {
            Write-Host "[dev-server] ⚠️  '$N' was already stopped" -ForegroundColor DarkGray
        }
        $reg.Remove($N)
        Save-Registry $reg
    }
}

function Get-List {
    $reg = Get-Registry
    if ($reg.Count -eq 0) { Write-Host "No servers registered."; return }
    Write-Host "[dev-server] Registered servers:" -ForegroundColor Cyan
    foreach ($entry in $reg.Values) {
        $proc = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
        $status = if ($proc) { "🟢 RUNNING" } else { "🔴 STOPPED" }
        Write-Host "  $($entry.name) — $status (PID $($entry.pid), $($entry.cmd) $($entry.args))"
    }
}

function Invoke-Cleanup {
    $reg = Get-Registry
    $changed = $false
    $deadNames = @()
    foreach ($entry in $reg.Values) {
        $proc = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
        if (-not $proc) { $deadNames += $entry.name }
    }
    foreach ($n in $deadNames) {
        $reg.Remove($n); $changed = $true
        Write-Host "[dev-server] 🧹 Removed dead entry '$n'" -ForegroundColor DarkGray
    }
    if ($changed) { Save-Registry $reg }
    if (-not $deadNames) { Write-Host "[dev-server] No stale entries found" -ForegroundColor Green }
}

# ── Dispatch ────────────────────────────────────────────────────────
switch ($Action) {
    "Start"   { Start-Server -N $Name -Cmd $Command -Args $Arguments -Dir $WorkingDir }
    "Status"  { Get-Status -N $Name }
    "Logs"    { Get-Log -N $Name }
    "Kill"    { Stop-Server -N $Name }
    "List"    { Get-List }
    "Cleanup" { Invoke-Cleanup }
}
