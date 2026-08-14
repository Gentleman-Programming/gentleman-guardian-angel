#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Health check for Gentleman Agent system.
.DESCRIPTION
    Checks: MCP servers, disk space, git status, Engram responsiveness, skill integrity.
.PARAMETER Json
    Output as JSON instead of human-readable text.
.EXAMPLE
    ./scripts/health-check.ps1
    ./scripts/health-check.ps1 -Json
#>
param(
    [switch]$Json
)
Set-StrictMode -Version Latest

$results = @()

# 1. Disk space
try {
    $disk = if ($IsWindows) {
        Get-PSDrive -Name ($env:SystemDrive[0]) | Select-Object -First 1
    } elseif ($IsLinux) {
        Get-PSDrive -Name / | Select-Object -First 1
    } else {
        Get-PSDrive | Where-Object { $_.Used -gt 0 } | Sort-Object Free -Descending | Select-Object -First 1
    }
    $freeGB = [math]::Round($disk.Free / 1GB, 2)
} catch {
    $disk = $null
    $freeGB = -1
}
$diskStatus = if ($freeGB -gt 1) { "OK" } elseif ($freeGB -gt 0.5) { "WARN" } elseif ($freeGB -ge 0) { "FAIL" } else { "FAIL" }
$diskDetail = if ($freeGB -ge 0) { "${freeGB}GB free" } else { "detection failed" }
$results += @{
    Check = "Disk Space"
    Status = $diskStatus
    Detail = $diskDetail
}

# 2. Git status
try {
    $gitStatus = git status --porcelain 2>&1
    $dirtyCount = ($gitStatus | Measure-Object).Count
    $results += @{
        Check = "Git Status"
        Status = if ($dirtyCount -eq 0) { "OK" } else { "WARN" }
        Detail = "$dirtyCount uncommitted changes"
    }
} catch {
    $results += @{
        Check = "Git Status"
        Status = "FAIL"
        Detail = "git not available"
    }
}

# 3. Node.js available
try {
    $nodeVersion = node --version 2>&1
    $results += @{
        Check = "Node.js"
        Status = "OK"
        Detail = $nodeVersion
    }
} catch {
    $results += @{
        Check = "Node.js"
        Status = "FAIL"
        Detail = "node not in PATH"
    }
}

# 4. Python available
try {
    $pyVersion = python3 --version 2>&1
    if (-not $pyVersion) { $pyVersion = python --version 2>&1 }
    $results += @{
        Check = "Python"
        Status = "OK"
        Detail = $pyVersion
    }
} catch {
    $results += @{
        Check = "Python"
        Status = "FAIL"
        Detail = "python not in PATH"
    }
}

# 5. Skill count consistency
try {
    $skillDirs = Get-ChildItem .agents/skills -Directory | Where-Object { $_.Name -ne '_shared' }
    $skillCount = $skillDirs.Count
    $results += @{
        Check = "Skill Count"
        Status = "OK"
        Detail = "$skillCount skills on disk"
    }
} catch {
    $results += @{
        Check = "Skill Count"
        Status = "FAIL"
        Detail = "Could not read skills directory"
    }
}

# 6. opencode.json valid JSON
try {
    $null = Get-Content 'opencode.json' -Raw | ConvertFrom-Json
    $results += @{
        Check = "opencode.json"
        Status = "OK"
        Detail = "Valid JSON"
    }
} catch {
    $results += @{
        Check = "opencode.json"
        Status = "FAIL"
        Detail = "Invalid JSON: $($_.Exception.Message)"
    }
}

# 7. Permission consistency (abbreviated)
try {
    $config = Get-Content 'opencode.json' -Raw | ConvertFrom-Json
    $readOnlyAgents = @('gentleman-security', 'gentleman-seo', 'gentleman-infra', 'gentleman-frontend', 'gentleman-performance', 'gentleman-datascience', 'gentleman-docs')
    $permFail = 0
    foreach ($agent in $readOnlyAgents) {
        $a = $config.agent.$agent
        if ($a -and $a.permission.bash.'*' -ne 'deny') { $permFail++ }
    }
    $results += @{
        Check = "Permissions"
        Status = if ($permFail -eq 0) { "OK" } else { "FAIL" }
        Detail = if ($permFail -eq 0) { "All read-only agents have bash:deny" } else { "$permFail agents with wrong bash permissions" }
    }
} catch {
    $results += @{
        Check = "Permissions"
        Status = "FAIL"
        Detail = "Could not parse opencode.json"
    }
}

# 8. MCP server health (via mcp-resilience library)
try {
    $mcpLib = Join-Path (Join-Path $PSScriptRoot "lib") "mcp-resilience.ps1"
    if (Test-Path $mcpLib) {
        . $mcpLib
        $mcpReport = Get-McpHealthReport
        foreach ($mcp in $mcpReport) {
            $results += @{
                Check = "MCP: $($mcp.Server)"
                Status = $mcp.Status
                Detail = "$($mcp.Detail) | Circuit: $($mcp.CircuitState)"
            }
        }
    } else {
        $results += @{
            Check = "MCP Servers"
            Status = "WARN"
            Detail = "mcp-resilience.ps1 not found - skipping MCP checks"
        }
    }
} catch {
    $results += @{
        Check = "MCP Servers"
        Status = "FAIL"
        Detail = "MCP health check error: $($_.Exception.Message)"
    }
}

# Output
if ($Json) {
    $results | ConvertTo-Json -Depth 3
} else {
    $failCount = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
    $warnCount = @($results | Where-Object { $_.Status -eq "WARN" }).Count

    Write-Output "`n=== Gentleman Agent Health Check ===`n"
    foreach ($r in $results) {
        $icon = switch ($r.Status) {
            "OK" { "[OK]" }
            "WARN" { "[!!]" }
            "FAIL" { "[X]" }
        }
        Write-Output "$icon $($r.Check): $($r.Detail)"
    }
    Write-Output "`n--- Summary: $($results.Count) checks, $failCount failures, $warnCount warnings ---`n"

    if ($failCount -gt 0) { exit 1 }
}
