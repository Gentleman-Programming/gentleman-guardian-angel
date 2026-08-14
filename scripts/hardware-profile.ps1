#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Detects system hardware and recommends an optimal OpenCode resource profile.

.DESCRIPTION
    Profiles the system's CPU, RAM, and GPU capabilities, then outputs
    a recommended OpenCode configuration profile optimized for the
    detected hardware tier.

    Hardware tiers (based on VN research, Reddit, HN discussions):

    LOW    (<=4GB RAM, <=2 cores, no dedicated GPU)
      - Disable watcher, no MCP servers, shallow subagent depth,
        aggressive compaction, small_model for lightweight tasks

    MEDIUM (4-8GB RAM, 4 cores, integrated GPU)
      - Reduced watcher scope, limited MCP, depth=2,
        medium compaction settings

    HIGH   (8GB+ RAM, 6+ cores, dedicated GPU or cloud LLM)
      - Full features with monitoring, generous context, depth=3

    Research sources:
      - HN item?id=47460525: OpenCode uses 1GB+ RAM vs Codex at 80MB
      - Reddit r/LocalLLaMA: CPU-only i5-8500 + KoboldCPP viable
      - VPS comparison: 2GB RAM for Cursor, 4GB+ for Claude Code
      - OpenCode issue #20695: memory leaks at high RSS
      - OpenCode issue #21470: file watcher 100% CPU on large repos

.PARAMETER OutputProfile
    Which profile to output: "detect" (auto), "low", "medium", "high", or "all".

.PARAMETER Json
    Emit machine-readable JSON.

.PARAMETER WriteProfile
    Write the profile to scripts/opencode-configs/.

.EXAMPLE
    .\scripts\hardware-profile.ps1
    .\scripts\hardware-profile.ps1 -OutputProfile all
    .\scripts\hardware-profile.ps1 -OutputProfile low -Json
#>
param(
    [ValidateSet("detect","low","medium","high","all")]
    [string]$OutputProfile = "detect",

    [switch]$Json,

    [switch]$WriteProfile,

    [string]$CurrentConfig = ""
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Constants ---
$ByteMB = 1048576

# --- Hardware detection ---
function Get-CPUInfo {
    $cores = 0
    $model = "Unknown"

    if ($IsLinux -or ($env:OS -ne 'Windows_NT' -and $PSVersionTable.Platform -ne 'Win32NT')) {
        try {
            $cpuinfo = [System.IO.File]::ReadAllText("/proc/cpuinfo") 2>$null
            if ($cpuinfo) {
                $model = ($cpuinfo | Select-String "model name" -First 1).ToString()
                if ($model -match "model name.*: (.+)") { $model = $matches[1] }
                $cores = ($cpuinfo | Select-String "processor" | Measure-Object).Count
            }
        } catch {}
    }
    elseif ($IsMacOS) {
        $model = (sysctl -n machdep.cpu.brand_string 2>$null)
        $cores = (sysctl -n hw.ncpu 2>$null)
    }
    else {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $model = $cpu.Name
        $cores = $cpu.NumberOfCores
    }

    return [PSCustomObject]@{ Model = $model; Cores = [int]$cores }
}

function Get-RAMInfo {
    $ramGB = 0
    if (Test-Path "/proc/meminfo") {
        $meminfo = [System.IO.File]::ReadAllText("/proc/meminfo")
        $match = [regex]::Match($meminfo, "MemTotal:\s+(\d+)")
        if ($match.Success) { $ramGB = [math]::Round([int64]$match.Groups[1].Value / $ByteMB, 0) }
    }
    elseif ($IsMacOS) {
        $bytes = (sysctl -n hw.memsize 2>$null)
        if ($bytes) { $ramGB = [math]::Round($bytes / 1073741824, 0) }
    }
    else {
        $bytes = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory
        if ($bytes) { $ramGB = [math]::Round($bytes / 1073741824, 0) }
    }
    return $ramGB
}

function Get-GPUInfo {
    $hasGPU = $false
    $gpuModel = "None detected"
    if (Test-Path "/proc/cpuinfo") {
        $lspci = & lspci 2>$null
        $gpuLine = $lspci | Select-String -Pattern "VGA|3D|Display" -First 1
        if ($gpuLine) { $hasGPU = $true; $gpuModel = $gpuLine.ToString().Trim() }
    }
    elseif ($IsMacOS) {
        $hasGPU = $true
        $gpuModel = (system_profiler SPDisplaysDataType 2>$null | Select-String "Chipset Model" -First 1).ToString()
    }
    else {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gpu) { $hasGPU = $true; $gpuModel = $gpu.Name }
    }
    return [PSCustomObject]@{ HasGPU = $hasGPU; Model = $gpuModel }
}

# --- Profile definitions ---
function Get-ProfileLow {
    return [PSCustomObject]@{
        name        = "low-resource"
        description = "For systems with <=4GB RAM, <=2 CPU cores, no dedicated GPU"
        compaction  = @{ auto=$true; prune=$true; reserved=4000; keep=@{tokens=8000} }
        model       = "opencode/big-pickle"
        small_model = "opencode/free"
        agent       = @{ default = @{ depth = 1 } }
        watcher     = @{ enabled = $false }
        mcp         = @{}
        tools       = @{ file = @{ maxBytes = 65536; maxLines = 100 } }
        snapshot    = @{ enabled = $false }
        memory_monitoring = @{ OPENCODE_DIAGNOSTICS = "1"; OPENCODE_MEMORY_LIMIT = "2" }
        notes = @(
            "1. Disables file watcher to eliminate 100% CPU scans on large repos (issue #21470)",
            "2. No MCP servers loaded - each adds context tokens + subprocess overhead",
            "3. subagent_depth=1 prevents recursive delegation stack growth",
            "4. compaction.prune=true removes old tool outputs to save memory",
            "5. snapshot.enabled=false prevents indexing overhead on large repos",
            "6. OPENCODE_DIAGNOSTICS=1 enables 2GB warning + 4GB auto-kill",
            "7. Based on: HN report of 1GB+ RAM for OpenCode TUI baseline"
        )
        _tier_source = "research"
    }
}

function Get-ProfileMedium {
    return [PSCustomObject]@{
        name        = "medium-resource"
        description = "For systems with 4-8GB RAM, 4 cores, integrated GPU"
        compaction  = @{ auto=$true; prune=$true; reserved=6000; keep=@{tokens=12000} }
        model       = "opencode/big-pickle"
        small_model = "opencode/free"
        agent       = @{ default = @{ depth = 2 } }
        watcher     = @{ enabled = $false; ignore = @( "node_modules", ".git", "dist", "temp" ) }
        mcp         = @{}
        tools       = @{ file = @{ maxBytes = 131072; maxLines = 200 } }
        snapshot    = @{ enabled = $true }
        memory_monitoring = @{ OPENCODE_DIAGNOSTICS = "1" }
        notes = @(
            "1. File watcher disabled but with ignore patterns for noise directories",
            "2. subagent_depth=2 allows limited parallel work",
            "3. Medium compaction settings balance context vs memory",
            "4. small_model for lightweight tasks (title generation)",
            "5. Tool output limits prevent large blob accumulation",
            "6. Based on: VPS comparison - 4GB RAM for Claude Code minimum"
        )
    }
}

function Get-ProfileHigh {
    return [PSCustomObject]@{
        name        = "high-resource"
        description = "For systems with 8GB+ RAM, 6+ cores, dedicated GPU or cloud LLM"
        compaction  = @{ auto=$true; prune=$true; reserved=8000; keep=@{tokens=15000} }
        model       = "opencode/big-pickle"
        small_model = "opencode/free"
        agent       = @{ default = @{ depth = 3 } }
        watcher     = @{ enabled = $true; ignore = @( "node_modules", ".git", "dist" ) }
        mcp         = @{}
        tools       = @{ file = @{ maxBytes = 262144; maxLines = 500 } }
        snapshot    = @{ enabled = $true }
        memory_monitoring = @{ OPENCODE_DIAGNOSTICS = "1"; OPENCODE_MEMORY_LIMIT = "0" }
        notes = @(
            "1. File watcher enabled with smart ignore patterns",
            "2. subagent_depth=3 allows deeper agent hierarchies",
            "3. Full compaction with generous reserved buffer",
            "4. All MCP servers available",
            "5. OPENCODE_MEMORY_LIMIT=0 uses default formula: max(2GB, min(25% total RAM, 4GB))"
        )
    }
}

# --- Detect and recommend ---
$cpu = Get-CPUInfo
$ram = Get-RAMInfo
$gpu = Get-GPUInfo

$detectedTier = "medium"
if ($ram -le 4 -or $cpu.Cores -le 2) { $detectedTier = "low" }
elseif ($ram -le 8 -or $cpu.Cores -le 4) { $detectedTier = "medium" }
else { $detectedTier = "high" }

if ($OutputProfile -eq "detect") { $OutputProfile = $detectedTier }

# --- Build profile registry ---
$profiles = @{
    low    = Get-ProfileLow
    medium = Get-ProfileMedium
    high   = Get-ProfileHigh
}

if ($OutputProfile -eq "all") {
    $result = [PSCustomObject]@{
        hardware = [PSCustomObject]@{
            cpu_model    = $cpu.Model
            cpu_cores    = $cpu.Cores
            ram_gb       = $ram
            gpu_detected = $gpu.HasGPU
            gpu_model    = $gpu.Model
            recommended_tier = $detectedTier
        }
        profiles = $profiles
    }

    if ($WriteProfile) {
        $configDir = Join-Path $PSScriptRoot "opencode-configs"
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
        foreach ($tier in @("low","medium","high")) {
            $profilePath = Join-Path $configDir "$tier-resource.json"
            $profiles[$tier] | ConvertTo-Json -Depth 10 | Set-Content -Path $profilePath -Encoding utf8
        }
    }

    if ($Json) {
        $result | ConvertTo-Json -Depth 10 -Compress
    }
    else {
        Write-Output "=== Hardware Detection ==="
        Write-Output "CPU: $($cpu.Model) ($($cpu.Cores) cores)"
        Write-Output "RAM: $($ram)GB"
        Write-Output "GPU: $($gpu.Model)"
        Write-Output ""
        Write-Output "=== Recommended Tier: $detectedTier ==="
        Write-Output ""
        foreach ($tier in @("low","medium","high")) {
            $p = $profiles[$tier]
            Write-Output "--- $tier ($($p.description)) ---"
            Write-Output "  compaction.reserved: $($p.compaction.reserved)"
            Write-Output "  subagent_depth: $($p.agent.default.depth)"
            Write-Output "  watcher: $($p.watcher.enabled)"
            Write-Output "  mcp: $(if ($p.mcp.Count -eq 0) { 'disabled' } else { 'enabled' })"
            Write-Output "  snapshot: $($p.snapshot.enabled)"
            Write-Output "  diagnostics: $($p.memory_monitoring.OPENCODE_DIAGNOSTICS)"
            Write-Output ""
        }
    }
    exit 0
}

# Single profile output
$profile = $profiles[$OutputProfile]
if (-not $profile) {
    Write-Error "Unknown profile: $OutputProfile. Available: low, medium, high, all, detect"
    exit 1
}

if ($WriteProfile) {
    $configDir = Join-Path $PSScriptRoot "opencode-configs"
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    $profilePath = Join-Path $configDir "$OutputProfile-resource.json"
    $profile | ConvertTo-Json -Depth 10 | Set-Content -Path $profilePath -Encoding utf8
    if (-not $Json) { Write-Output "Profile written to: $profilePath" }
}

if ($Json) {
    $profile | ConvertTo-Json -Depth 10 -Compress
}
else {
    Write-Output "=== Profile: $($profile.name) ==="
    Write-Output "Description: $($profile.description)"
    Write-Output ""
    Write-Output "Compaction:"
    Write-Output "  auto: $($profile.compaction.auto)"
    Write-Output "  prune: $($profile.compaction.prune)"
    Write-Output "  reserved: $($profile.compaction.reserved)"
    Write-Output "  keep.tokens: $($profile.compaction.keep.tokens)"
    Write-Output ""
    Write-Output "Agent:"
    Write-Output "  subagent_depth: $($profile.agent.subagent_depth)"
    Write-Output "  small_model: $($profile.model.small_model)"
    Write-Output ""
    Write-Output "Watcher:"
    Write-Output "  enabled: $($profile.watcher.enabled)"
    Write-Output ""
    Write-Output "Tools:"
    Write-Output "  file.maxBytes: $($profile.tools.file.maxBytes)"
    Write-Output "  file.maxLines: $($profile.tools.file.maxLines)"
    Write-Output ""
    Write-Output "Monitoring:"
    Write-Output "  diagnostics: $($profile.memory_monitoring.OPENCODE_DIAGNOSTICS)"
    Write-Output "  snapshot: $($profile.snapshot.enabled)"
    Write-Output ""
    Write-Output "Notes:"
    $profile.notes | % { Write-Output "  $_" }
}
exit 0