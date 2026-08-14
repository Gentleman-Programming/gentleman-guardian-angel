#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Resource monitor for OpenCode processes - tracks CPU, RAM usage.

.DESCRIPTION
    Cross-platform resource monitor for OpenCode/Bun processes.
    Uses /proc/<pid>/statm on Linux for accurate RSS (Bun's
    process.memoryUsage().rss underreports by ~60x due to bmalloc
    mmap regions - see OpenCode issue #20695).

.PARAMETER Interval
    Polling interval in seconds (default: 3).

.PARAMETER Threshold
    Memory warning threshold as percentage of total system RAM (default: 15).

.PARAMETER MaxSamples
    Maximum number of samples to collect (default: 0 = unlimited).

.PARAMETER Json
    Emit machine-readable JSON after each sample.

.PARAMETER HeapSnapshotMb
    If set, attempts heap snapshot when any process exceeds this RSS in MB.

.PARAMETER Quiet
    Only exit code indicates if memory exceeded threshold (0 = OK, 1 = exceeded).

.EXAMPLE
    .\scripts\monitor-opencode.ps1
    .\scripts\monitor-opencode.ps1 -Interval 5 -Threshold 10
    .\scripts\monitor-opencode.ps1 -MaxSamples 10 -Json
#>
param(
    [int]$Interval = 3,
    [int]$Threshold = 15,
    [int]$MaxSamples = 0,
    [switch]$Json,
    [int]$HeapSnapshotMb = 0,
    [switch]$Quiet
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Constants ---
$ByteMB = 1048576
$ByteGB = 1073741824

# --- Platform detection ---
$isLinux = $IsLinux -or ($env:OS -ne 'Windows_NT' -and $PSVersionTable.Platform -ne 'Win32NT')
$isMacOS = $IsMacOS -or ($PSVersionTable.Platform -eq 'Unix' -and (uname -s) -eq 'Darwin')
$isWindows = $IsWindows -or ($env:OS -eq 'Windows_NT')

# --- Accurate RSS via /proc/<pid>/statm (Linux only, Bun bmalloc workaround) ---
function Get-AccurateRSS {
    param([int]$Pid)

    if ($isLinux) {
        $statmPath = "/proc/$Pid/statm"
        if (Test-Path $statmPath) {
            $statm = [System.IO.File]::ReadAllText($statmPath).Trim().Split(" ")
            # Page 2 (index 1) = RSS in pages, multiply by 4096 (standard page size)
            return [int64]$statm[1] * 4096
        }
    }

    # macOS fallback
    if ($isMacOS) {
        $result = ps -o rss= -p $Pid 2>$null
        if ($result) { return [int64]$result.Trim() * 1024 }
    }

    # Windows fallback
    if ($isWindows) {
        $proc = Get-Process -Id $Pid -ErrorAction SilentlyContinue
        if ($proc) { return [int64]$proc.WorkingSet64 }
    }

    return 0
}

# --- Get total system memory ---
function Get-TotalMemory {
    if ($isLinux -and (Test-Path "/proc/meminfo")) {
        $meminfo = [System.IO.File]::ReadAllText("/proc/meminfo")
        $match = [regex]::Match($meminfo, "MemTotal:\s+(\d+)")
        if ($match.Success) { return [int64]$match.Groups[1].Value * 1024 }
    }
    if ($isMacOS) {
        $result = sysctl -n hw.memsize 2>$null
        if ($result) { return [int64]$result }
    }
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs) { return [int64]$cs.TotalPhysicalMemory }
    return 0
}

# --- Find OpenCode/Bun processes ---
function Get-OpenCodeProcesses {
    $procs = @()

    if ($isLinux -or $isMacOS) {
        $raw = ps aux 2>$null | Select-String "opencode" | Where-Object { $_ -notmatch "grep" }
        foreach ($line in $raw) {
            $parts = $line -split '\s+'
            if ($parts.Count -ge 11) {
                $cmd = ($parts[10..($parts.Count-1)] -join " ")
                if ($cmd.Length -gt 60) { $cmd = $cmd.Substring(0, 60) }
                $procs += [PSCustomObject]@{
                    Pid     = [int]$parts[1]
                    CpuPct  = [double]$parts[2]
                    MemPct  = [double]$parts[3]
                    Rss     = [int64]$parts[5] * 1024
                    Command = $cmd
                }
            }
        }
    }
    else {
        $procs = Get-Process -Name "opencode" -ErrorAction SilentlyContinue | % {
            [PSCustomObject]@{
                Pid     = $_.Id
                CpuPct  = 0
                MemPct  = [math]::Round(($_.WorkingSet64 / (Get-TotalMemory)) * 100, 1)
                Rss     = [int64]$_.WorkingSet64
                Command = $_.ProcessName
            }
        }
    }

    return $procs
}

# --- Trigger heap snapshot ---
function Invoke-HeapSnapshot {
    param([int]$Pid, [string]$LogDir)

    if ($env:OPENCODE_AUTO_HEAP_SNAPSHOT -eq "1") {
        Write-Warning "OPENCODE_AUTO_HEAP_SNAPSHOT=1 set - OpenCode handles snapshots internally"
        return
    }

    if ($env:OPENCODE_DIAGNOSTICS -eq "1") {
        # Send SIGUSR1 to trigger diagnostic capture
        if ($isLinux -or $isMacOS) {
            try {
                & kill -USR1 $Pid 2>$null
                Write-Output "Sent SIGUSR1 to PID $Pid for heap snapshot capture"
            } catch {
                Write-Warning "Could not send SIGUSR1: $_"
            }
        }
    }
}

# --- Main monitoring loop ---
$totalMem = Get-TotalMemory
$samples = 0
$exceeded = $false
$ByteGB = 1073741824
$ByteMB = 1048576

while ($true) {
    $procs = Get-OpenCodeProcesses

    if ($procs.Count -eq 0) {
        if ($Json -and -not $Quiet) {
            [PSCustomObject]@{
                timestamp  = (Get-Date).ToString("o")
                processes  = @()
                totalRss   = 0
                totalPct   = 0
                threshold  = $Threshold
                exceeded   = $false
                totalMemMB = [math]::Round($totalMem / $ByteMB, 0)
            } | ConvertTo-Json -Compress
        }
        Start-Sleep -Seconds $Interval
        $samples++
        if ($MaxSamples -gt 0 -and $samples -ge $MaxSamples) { break }
        continue
    }

    # Recalculate RSS using accurate method
    foreach ($p in $procs) {
        $p.Rss = Get-AccurateRSS -Pid $p.Pid
        $p.MemPct = if ($totalMem -gt 0) { [math]::Round(($p.Rss / $totalMem) * 100, 1) } else { 0 }
    }

    $totalRss = ($procs | Measure-Object -Property Rss -Sum).Sum
    $totalPct = if ($totalMem -gt 0) { [math]::Round(($totalRss / $totalMem) * 100, 1) } else { 0 }
    $exceeded = $totalPct -gt $Threshold

    if ($Json) {
        $procData = $procs | % {
            [PSCustomObject]@{
                pid  = $_.Pid
                cpu  = $_.CpuPct
                mem  = $_.MemPct
                rss_mb = [math]::Round($_.Rss / $ByteMB, 1)
                cmd  = $_.Command
            }
        }
        [PSCustomObject]@{
            timestamp   = (Get-Date).ToString("o")
            processes   = $procData
            totalRssMB  = [math]::Round($totalRss / $ByteMB, 1)
            totalPct    = $totalPct
            threshold   = $Threshold
            exceeded    = $exceeded
            totalMemMB  = [math]::Round($totalMem / $ByteMB, 0)
        } | ConvertTo-Json -Compress
    }
    elseif (-not $Quiet) {
        $header = "=== OpenCode Resource Monitor ($(Get-Date -Format 'HH:mm:ss')) ==="
        Write-Output $header
        $procs | % {
            $rssMB = [math]::Round($_.Rss / $ByteMB, 0)
            Write-Output ("PID: {0} CPU: {1:N1}%  MEM: {2:N1}%  RSS: {3}MB  {4}" -f $_.Pid, $_.CpuPct, $_.MemPct, $rssMB, $_.Command)
        }
        $totalMB = [math]::Round($totalRss / $ByteMB, 0)
        $totalMB_sys = [math]::Round($totalMem / $ByteMB, 0)
        Write-Output ("Total RSS: {0:N0}MB  ({1:N1}% of {2:N0}MB system)" -f $totalMB, $totalPct, $totalMB_sys)
        if ($exceeded) {
            Write-Warning "Memory usage exceeds $Threshold% threshold"
        }
    }

    # Trigger heap snapshot if threshold exceeded
    if ($HeapSnapshotMb -gt 0 -and ($procs | Measure-Object -Property Rss -Maximum).Maximum -gt ($HeapSnapshotMb * $ByteMB)) {
        $logDir = Join-Path $env:LOCALAPPDATA "opencode\logs"
        if (-not (Test-Path $logDir)) { $logDir = $env:TEMP }
        Invoke-HeapSnapshot -Pid $procs[0].Pid -LogDir $logDir
    }

    Start-Sleep -Seconds $Interval
    $samples++
    if ($MaxSamples -gt 0 -and $samples -ge $MaxSamples) { break }
}

if ($exceeded -and $Quiet) { exit 1 }
exit 0