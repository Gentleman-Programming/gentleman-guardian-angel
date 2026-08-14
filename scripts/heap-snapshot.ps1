#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Triggers and manages heap snapshots for OpenCode processes.

.DESCRIPTION
    Wrapper around OpenCode's built-in heap snapshot mechanism.
    Supports automatic snapshots (OPENCODE_AUTO_HEAP_SNAPSHOT=1) and
    manual triggering via SIGUSR1 signal (Linux/macOS).

    Environment variables:
      - OPENCODE_AUTO_HEAP_SNAPSHOT=1 - auto-snapshots at 2GB RSS
      - OPENCODE_DIAGNOSTICS=1 - enables 30s polling + 2GB warning + kill
      - OPENCODE_MEMORY_LIMIT=N - override kill threshold (in GB)

    NOTE: Bun's process.memoryUsage().rss underreports by ~60x (bmalloc).
    Use /proc/<pid>/statm for accurate RSS on Linux.

.PARAMETER Action
    "snapshot" (trigger), "status" (check memory), "kill-if-exceeded" (kill).

.PARAMETER Pid
    Target OpenCode process PID. If omitted, auto-detects.

.PARAMETER OutputDir
    Directory for heap snapshots (default: OpenCode log dir or $TEMP).

.PARAMETER MemoryLimitGB
    Override the kill threshold in GB (default: auto per OpenCode formula).

.PARAMETER Json
    Emit machine-readable JSON.

.EXAMPLE
    .\scripts\heap-snapshot.ps1 -Action snapshot
    .\scripts\heap-snapshot.ps1 -Action status -Json
    .\scripts\heap-snapshot.ps1 -Action kill-if-exceeded -MemoryLimitGB 4
#>
param(
    [ValidateSet("snapshot","status","kill-if-exceeded")]
    [string]$Action = "snapshot",

    [int]$Pid = 0,

    [string]$OutputDir = "",

    [int]$MemoryLimitGB = 0,

    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ByteMB = 1048576
$ByteGB = 1073741824
$isLinux = $IsLinux -or ($env:OS -ne 'Windows_NT' -and $PSVersionTable.Platform -ne 'Win32NT')

# --- Accurate RSS via /proc/<pid>/statm (Linux, Bun bmalloc workaround) ---
function Get-AccurateRSS {
    param([int]$ProcessId)
    if ($isLinux -and $ProcessId -gt 0) {
        $statmPath = "/proc/$ProcessId/statm"
        if (Test-Path $statmPath) {
            $statm = [System.IO.File]::ReadAllText($statmPath).Trim().Split(" ")
            return [int64]$statm[1] * 4096
        }
    }
    $result = ps -o rss= -p $ProcessId 2>$null
    if ($result) { return [int64]$result.Trim() * 1024 }
    return 0
}

function Get-TotalMemory {
    if ((Test-Path "/proc/meminfo")) {
        $meminfo = [System.IO.File]::ReadAllText("/proc/meminfo")
        $match = [regex]::Match($meminfo, "MemTotal:\s+(\d+)")
        if ($match.Success) { return [int64]$match.Groups[1].Value * 1024 }
    }
    $result = sysctl -n hw.memsize 2>$null
    if ($result) { return [int64]$result }
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs) { return [int64]$cs.TotalPhysicalMemory }
    return 0
}

function Find-OpenCodePids {
    if ($isLinux) {
        $lines = ps aux 2>$null | Select-String "opencode" | Where-Object { $_ -notmatch "grep" }
        return @($lines | % {
            $parts = $_ -split '\s+'
            if ($parts.Count -ge 2) { [int]$parts[1] }
        })
    }
    return @((Get-Process -Name "opencode" -ErrorAction SilentlyContinue).Id)
}

# --- Determine output directory ---
if (-not $OutputDir) {
    if ($isLinux -and (Test-Path "$env:HOME/.local/share/opencode/diagnostics")) {
        $OutputDir = "$env:HOME/.local/share/opencode/diagnostics"
    }
    elseif ($env:LOCALAPPDATA -and (Test-Path "$env:LOCALAPPDATA/opencode/logs")) {
        $OutputDir = "$env:LOCALAPPDATA/opencode/logs"
    }
    else {
        $OutputDir = $env:TEMP
    }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
}

# --- Find target PID ---
if ($Pid -eq 0) {
    $pids = Find-OpenCodePids
    if ($pids.Count -eq 0) {
        if ($Json) {
            [PSCustomObject]@{ status = "no_opencode_process_found"; pids = @() } | ConvertTo-Json -Compress
        }
        else { Write-Warning "No OpenCode process found" }
        exit 1
    }
    $Pid = $pids[0]
}

# --- Total system memory + kill threshold ---
$totalMem = Get-TotalMemory
$killThreshold = if ($MemoryLimitGB -gt 0) { $MemoryLimitGB * $ByteGB } else { [math]::Max(2 * $ByteGB, [math]::Min($totalMem * 0.25, 4 * $ByteGB)) }

# --- Execute action ---
if ($Action -eq "status") {
    $rss = Get-AccurateRSS -ProcessId $Pid
    $rssGB = $rss / $ByteGB
    $pct = if ($totalMem -gt 0) { ($rss / $totalMem) * 100 } else { 0 }

    if ($Json) {
        [PSCustomObject]@{
            pid      = $Pid
            rss_bytes = $rss
            rss_mb   = [math]::Round($rss / $ByteMB, 1)
            rss_gb   = [math]::Round($rssGB, 2)
            total_mem_gb = [math]::Round($totalMem / $ByteGB, 2)
            pct      = [math]::Round($pct, 1)
            kill_threshold_gb = [math]::Round($killThreshold / $ByteGB, 2)
            auto_snapshot = $env:OPENCODE_AUTO_HEAP_SNAPSHOT -eq "1"
            diagnostics = $env:OPENCODE_DIAGNOSTICS -eq "1"
            should_kill = $rss -gt $killThreshold
        } | ConvertTo-Json -Compress
    }
    else {
        Write-Output "PID: $Pid"
        Write-Output ("RSS: {0:N0} MB ({1:N2} GB)" -f ($rss / $ByteMB), $rssGB)
        Write-Output ("System Total: {0:N2} GB" -f ($totalMem / $ByteGB))
        Write-Output ("Usage: {0:N1}%" -f $pct)
        Write-Output ("Kill Threshold: {0:N2} GB" -f ($killThreshold / $ByteGB))
        Write-Output "Auto-Snapshot: $env:OPENCODE_AUTO_HEAP_SNAPSHOT"
        Write-Output "Diagnostics: $env:OPENCODE_DIAGNOSTICS"
        if ($rss -gt $killThreshold) {
            Write-Warning "RSS exceeds kill threshold - run with -Action kill-if-exceeded"
        }
    }
    exit 0
}

if ($Action -eq "kill-if-exceeded") {
    $rss = Get-AccurateRSS -ProcessId $Pid
    if ($rss -gt $killThreshold) {
        if ($Json) {
            [PSCustomObject]@{
                pid    = $Pid
                rss_gb = [math]::Round($rss / $ByteGB, 2)
                threshold_gb = [math]::Round($killThreshold / $ByteGB, 2)
                action = "killing"
            } | ConvertTo-Json -Compress
        }
        Write-Warning ("{0:N2}GB RSS exceeds threshold ({1:N2}GB) - killing PID {2}" -f ($rss / $ByteGB), ($killThreshold / $ByteGB), $Pid)
        if ($isLinux) {
            & kill -TERM $Pid 2>$null
            Start-Sleep -Seconds 2
            $alive = & kill -0 $Pid 2>$null
            if ($alive) { & kill -KILL $Pid 2>$null }
        }
        else {
            Stop-Process -Id $Pid -Force
        }
    }
    else {
        if ($Json) {
            [PSCustomObject]@{
                pid = $Pid
                rss_gb = [math]::Round($rss / $ByteGB, 2)
                threshold_gb = [math]::Round($killThreshold / $ByteGB, 2)
                action = "within_limits"
            } | ConvertTo-Json -Compress
        }
    }
    exit 0
}

if ($Action -eq "snapshot") {
    # Method 1: SIGUSR1 (Linux/macOS with diagnostics)
    if ($isLinux) {
        try {
            & kill -USR1 $Pid 2>$null
            if ($LASTEXITCODE -eq 0) {
                if ($Json) {
                    [PSCustomObject]@{ action="snapshot_triggered"; method="SIGUSR1"; pid=$Pid; output_dir=$OutputDir } | ConvertTo-Json -Compress
                }
                else { Write-Output "Sent SIGUSR1 to PID $Pid - snapshot should appear in $OutputDir" }
                exit 0
            }
        }
        catch { }
    }

    # Method 2: OPENCODE_AUTO_HEAP_SNAPSHOT env var
    if ($env:OPENCODE_AUTO_HEAP_SNAPSHOT -eq "1") {
        Write-Output "OPENCODE_AUTO_HEAP_SNAPSHOT=1 is set - OpenCode auto-snapshots at 2GB RSS"
        Write-Output "Output directory: $OutputDir"
        if ($Json) {
            [PSCustomObject]@{ action="auto_snapshot_configured"; method="OPENCODE_AUTO_HEAP_SNAPSHOT"; pid=$Pid; output_dir=$OutputDir } | ConvertTo-Json -Compress
        }
        exit 0
    }

    # Method 3: Manual info
    $snapshotScript = "import v8 from node:v8`nconst p = v8.writeHeapSnapshot()`nconsole.log(p)"
    $scriptPath = Join-Path $env:TEMP "heapsnap-manual.mjs"
    $snapshotScript | Set-Content -Path $scriptPath -Encoding utf8

    if ($Json) {
        [PSCustomObject]@{ action="manual_snapshot_ready"; method="bun_script"; script=$scriptPath; pid=$Pid } | ConvertTo-Json -Compress
    }
    else {
        Write-Output "Manual snapshot script written to: $scriptPath"
        Write-Output "Run: bun $scriptPath"
        Write-Output "Or set OPENCODE_AUTO_HEAP_SNAPSHOT=1 and restart OpenCode"
    }
    exit 0
}