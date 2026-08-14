#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

<#
.SYNOPSIS
  Check external repos for new commits since last check.

.DESCRIPTION
  Compares HEAD hashes of monitored upstream repos against a stored state
  file (.upstream-state.json in repo root). Reports NEW/UNCHANGED/ERROR.
  Used by CYCLE.md LOOP step 2 to automate external repo monitoring.

.PARAMETER Update
  Update stored hashes after check (for establishing new baseline).

.PARAMETER Json
  Output JSON (machine-readable).

.EXAMPLE
  .\scripts\check-upstream.ps1

.EXAMPLE
  .\scripts\check-upstream.ps1 -Update

.EXAMPLE
  .\scripts\check-upstream.ps1 -Json
#>

param(
    [switch]$Update,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$stateFile = Join-Path -Path $repoRoot -ChildPath ".upstream-state.json"

# Repos to monitor - same list as CYCLE.md External Repos
$repos = @(
    @{ Name = "karpathy/autoresearch"; Url = "https://github.com/karpathy/autoresearch.git"; What = "New program.md patterns, loop improvements" },
    @{ Name = "Gentleman-Programming/gentleman-guardian-angel"; Url = "https://github.com/Gentleman-Programming/gentleman-guardian-angel.git"; What = "New caching strategies, AGENTS.md compliance checks" },
    @{ Name = "gentle-ai"; Url = "https://github.com/Gentleman-Programming/gentle-ai.git"; What = "Skills, scripts, MCP servers, backup systems" },
    @{ Name = "engram (MCP)"; Url = "https://github.com/engramhq/engram.git"; What = "Cloud sync, new query types, performance" }
)

# --- Load previous state (array format for PS5.1 compat) ---
$previous = @{}
if (Test-Path -LiteralPath $stateFile) {
    try {
        $arr = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($entry in $arr) {
            $previous[$entry.name] = @{
                hash         = $entry.hash
                last_checked = $entry.last_checked
            }
        }
    } catch {
        Write-Warning "Could not parse $stateFile - starting fresh: $($_.Exception.Message)"
    }
}

# Guard: ensure previous entries exist for comparison
foreach ($repo in $repos) {
    if (-not $previous.ContainsKey($repo.Name)) {
        $previous[$repo.Name] = $null
    }
}

# --- Get bash for git ls-remote ---
# Prefer Git Bash over WSL bash stub (WSL relay fails on git ls-remote)
$bashPath = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
    "$env:SystemDrive\Program Files\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bashPath) {
    $bashPath = (Get-Command 'bash' -ErrorAction SilentlyContinue).Source
}
if (-not $bashPath) {
    Write-Error "Git Bash not found. Install Git for Windows or ensure 'bash' is in PATH."
    exit 1
}

$results = @()
$allOk = $true

foreach ($repo in $repos) {
    $name = $repo.Name
    $url = $repo.Url
    $prevEntry = $previous[$name]
    $prevHash = if ($prevEntry) { $prevEntry.hash } else { $null }
    $prevDate = if ($prevEntry) { $prevEntry.last_checked } else { $null }

    # Fetch HEAD via git ls-remote
    $remoteHash = ""
    $errorMsg = ""
    try {
        $output = & $bashPath -c "git ls-remote '$url' HEAD 2>/dev/null"
        if ($output -match '^([a-f0-9]{40})') {
            $remoteHash = $Matches[1]
        } else {
            $errorMsg = "No HEAD ref found"
            $allOk = $false
        }
    } catch {
        $errorMsg = "Fetch failed: $($_.Exception.Message)"
        $allOk = $false
    }

    # Determine status
    if ($errorMsg) {
        $status = "ERROR"
    } elseif (-not $prevHash) {
        $status = "NEW (first check)"
    } elseif ($remoteHash -eq $prevHash) {
        $status = "UNCHANGED"
    } else {
        $status = "NEW"
    }

    $results += [PSCustomObject]@{
        Name        = $name
        Url         = $url
        Status      = $status
        LastHash    = $remoteHash
        PrevHash    = $prevHash
        LastChecked = $prevDate
        What        = $repo.What
        Error       = $errorMsg
    }
}

# --- Update state if -Update (array format for PS5.1) ---
if ($Update) {
    $newState = @()
    foreach ($r in $results) {
        if ($r.Status -ne "ERROR" -and $r.LastHash) {
            $newState += [PSCustomObject]@{
                name         = $r.Name
                hash         = $r.LastHash
                last_checked = (Get-Date -Format "yyyy-MM-dd")
            }
        } elseif ($previous.ContainsKey($r.Name) -and $previous[$r.Name]) {
            $newState += [PSCustomObject]@{
                name         = $r.Name
                hash         = $previous[$r.Name].hash
                last_checked = $previous[$r.Name].last_checked
            }
        }
    }
    $newState | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $stateFile -Encoding UTF8 -Force
}

# --- Output ---
if ($Json) {
    Write-Output ($results | ConvertTo-Json -Depth 2)
} else {
    $changed   = @($results | Where-Object { $_.Status -eq "NEW" })
    $failed    = @($results | Where-Object { $_.Status -eq "ERROR" })
    $unchanged = @($results | Where-Object { $_.Status -eq "UNCHANGED" })
    $first     = @($results | Where-Object { $_.Status -eq "NEW (first check)" })

    Write-Output "=== Upstream Check ==="
    Write-Output "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    Write-Output ""

    if ($changed) {
        Write-Output "--- CHANGED ($($changed.Count)) ---"
        foreach ($r in $changed) {
            Write-Output "  NEW:      $($r.Name)"
            Write-Output "            $($r.What)"
            Write-Output             "            $(if ($r.PrevHash) { $r.PrevHash.Substring(0,12) } else { 'none' }) -> $($r.LastHash.Substring(0,12))"
            Write-Output ""
        }
    }

    if ($first) {
        Write-Output "--- FIRST CHECK ($($first.Count)) ---"
        foreach ($r in $first) {
            Write-Output "  NEW:      $($r.Name)"
            Write-Output "            hash: $($r.LastHash.Substring(0,12))"
            Write-Output ""
        }
    }

    if ($failed) {
        Write-Output "--- ERRORS ($($failed.Count)) ---"
        foreach ($r in $failed) {
            Write-Output "  ERROR:    $($r.Name) - $($r.Error)"
        }
        Write-Output ""
    }

    if ($unchanged) {
        Write-Output "--- UNCHANGED ($($unchanged.Count)) ---"
        foreach ($r in $unchanged) {
            Write-Output             "  OK:       $($r.Name) (since $(if ($r.LastChecked) { $r.LastChecked } else { 'first check' }))"
        }
    }

    if (-not $changed -and -not $failed -and -not $first) {
        Write-Output "  All $($results.Count) repos unchanged."
    }
    Write-Output "=========================="

    if ($Update) {
        Write-Output "State saved to .upstream-state.json"
    }

    exit $(if ($allOk) { 0 } else { 1 })
}
