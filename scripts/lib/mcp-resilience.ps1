#requires -Version 7
<#
.SYNOPSIS
    MCP server resilience library - health checks, circuit breaker, retry with exponential backoff.
.DESCRIPTION
    Provides:
    - Test-McpServer: probe MCP server connectivity
    - Invoke-McpWithRetry: retry wrapper with exponential backoff
    - Get-McpCircuitState: circuit breaker state machine (CLOSED/OPEN/HALF_OPEN)
    - Reset-McpCircuit: manually reset circuit breaker
    Part of the reliability hardening for gentleman-agent-gh.
.NOTES
    Dot-sourced by health-check-system.ps1 and other operational scripts.
    Circuit breaker state persisted in .learnings/mcp-circuit-state.json
    FIX: DateTime stored as ISO 8601 strings to prevent culture-dependent round-trip failures.
    FIX: File locking via mutex for concurrent write safety.
    FIX: Null checks on config.mcp, try/catch on ConvertFrom-Json.
    FIX: TcpClient disposed properly in all code paths.
#>

$script:CircuitStateFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ".learnings" | Join-Path -ChildPath "mcp-circuit-state.json"
$script:FileMutex = New-Object System.Threading.Mutex($false, "Global\GentlemanMcpCircuitLock")

# -- Helper: safe ISO 8601 timestamp --
function Get-IsoTimestamp {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

# -- Helper: parse ISO 8601 timestamp safely --
function ConvertFrom-IsoTimestamp {
    param([string]$Timestamp)
    if (-not $Timestamp) { return $null }
    try {
        return [datetime]::ParseExact($Timestamp, "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        try {
            return [datetime]::Parse($Timestamp, [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {
            return $null
        }
    }
}

# -- Circuit Breaker State Machine --
# States: CLOSED (normal) -> OPEN (failing) -> HALF_OPEN (testing) -> CLOSED
# Threshold: 3 consecutive failures -> OPEN
# Recovery: 60s cooldown -> HALF_OPEN -> 1 success -> CLOSED

function Get-McpCircuitState {
    <#
    .SYNOPSIS
        Returns the current circuit breaker state for an MCP server.
    .PARAMETER Server
        MCP server name (e.g., "engram", "context7", "codebase-memory-mcp").
    .OUTPUTS
        PSCustomObject with State, FailureCount, LastFailure, LastSuccess, OpenedAt.
    #>
    param([string]$Server)

    $default = @{
        State = "CLOSED"
        FailureCount = 0
        LastFailure = $null
        LastSuccess = $null
        OpenedAt = $null
    }

    if (-not (Test-Path $script:CircuitStateFile)) {
        return [PSCustomObject]$default
    }

    try {
        $raw = Get-Content $script:CircuitStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $entry = $raw.PSObject.Properties[$Server]
        if (-not $entry) { return [PSCustomObject]$default }

        $state = $entry.Value
        # Check if OPEN state has expired (60s cooldown)
        if ($state.State -eq "OPEN" -and $state.OpenedAt) {
            $openedAt = ConvertFrom-IsoTimestamp -Timestamp $state.OpenedAt
            if ($openedAt) {
                $elapsed = ((Get-Date).ToUniversalTime() - $openedAt).TotalSeconds
                if ($elapsed -ge 60) {
                    $state.State = "HALF_OPEN"
                }
            }
        }
        return [PSCustomObject]$state
    } catch {
        return [PSCustomObject]$default
    }
}

function Set-McpCircuitState {
    <#
    .SYNOPSIS
        Persists circuit breaker state for an MCP server. Thread-safe via mutex.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Server, [hashtable]$State)

    if ($PSCmdlet.ShouldProcess($Server, 'Set MCP circuit state')) {
        $dir = Split-Path $script:CircuitStateFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $acquired = $false
        try {
            $script:FileMutex.WaitOne(5000) | Out-Null
            $acquired = $true

            $cache = @{}
            if (Test-Path $script:CircuitStateFile) {
                try {
                    $raw = Get-Content $script:CircuitStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($raw) { $raw.PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }
                } catch { Write-Debug "mcp-resilience: $($_.Exception.Message)" }
            }
            $cache[$Server] = $State
            $cache | ConvertTo-Json -Depth 10 | Set-Content $script:CircuitStateFile -Encoding UTF8
        } finally {
            if ($acquired) { $script:FileMutex.ReleaseMutex() }
        }
    }
}

function Reset-McpCircuit {
    <#
    .SYNOPSIS
        Manually resets circuit breaker for an MCP server to CLOSED.
    .PARAMETER Server
        MCP server name.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Server)
    if ($PSCmdlet.ShouldProcess($Server, 'Reset MCP circuit breaker')) {
        Set-McpCircuitState -Server $Server -State @{
            State = "CLOSED"
            FailureCount = 0
            LastFailure = $null
            LastSuccess = (Get-IsoTimestamp)
            OpenedAt = $null
        }
    }
}

# -- MCP Server Health Probe --

function Test-McpServer {
    <#
    .SYNOPSIS
        Probes an MCP server for connectivity/health.
    .PARAMETER Server
        MCP server configuration object (from opencode.json mcp section).
    .PARAMETER ServerName
        Display name for logging.
    .PARAMETER TimeoutMs
        Probe timeout in milliseconds (default: 5000).
    .OUTPUTS
        PSCustomObject with Status (OK/WARN/FAIL/SKIP), Detail, LatencyMs.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Server,
        [string]$ServerName = "unknown",
        [int]$TimeoutMs = 5000
    )

    if ($Server.enabled -eq $false) {
        return [PSCustomObject]@{
            Status = "SKIP"
            Detail = "Disabled in config"
            LatencyMs = 0
        }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tcpClient = $null

    try {
        if ($Server.type -eq "remote" -and $Server.url) {
            $uri = [System.Uri]$Server.url
            $port = if ($uri.Port -gt 0) { $uri.Port } else { 443 }
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connectTask = $tcpClient.ConnectAsync($uri.Host, $port)
            if ($connectTask.Wait($TimeoutMs)) {
                $sw.Stop()
                return [PSCustomObject]@{
                    Status = "OK"
                    Detail = "Remote reachable: $ServerName ($($uri.Host))"
                    LatencyMs = $sw.ElapsedMilliseconds
                }
            } else {
                $sw.Stop()
                return [PSCustomObject]@{
                    Status = "FAIL"
                    Detail = "Remote timeout: $ServerName ($($uri.Host)) ($TimeoutMs ms)"
                    LatencyMs = $sw.ElapsedMilliseconds
                }
            }
        }
        elseif ($Server.type -eq "local" -and $Server.command) {
            # ConvertFrom-Json unwraps single-element arrays to a string; @() normalizes
            $cmd = @($Server.command)[0]
            $found = Get-Command $cmd -ErrorAction SilentlyContinue
            $sw.Stop()
            if ($found) {
                return [PSCustomObject]@{
                    Status = "OK"
                    Detail = "Command found: $cmd ($($found.Source))"
                    LatencyMs = $sw.ElapsedMilliseconds
                }
            } else {
                return [PSCustomObject]@{
                    Status = "FAIL"
                    Detail = "Command not found: $cmd"
                    LatencyMs = $sw.ElapsedMilliseconds
                }
            }
        }
        else {
            $sw.Stop()
            return [PSCustomObject]@{
                Status = "WARN"
                Detail = "Unknown MCP type: $($Server.type)"
                LatencyMs = 0
            }
        }
    } catch {
        $sw.Stop()
        return [PSCustomObject]@{
            Status = "FAIL"
            Detail = "Probe error: $($_.Exception.Message)"
            LatencyMs = $sw.ElapsedMilliseconds
        }
    } finally {
        if ($tcpClient) {
            try { $tcpClient.Close() } catch { Write-Debug "mcp-resilience: $($_.Exception.Message)" }
        }
    }
}

# -- Retry with Exponential Backoff --

function Invoke-McpWithRetry {
    <#
    .SYNOPSIS
        Executes a scriptblock with retry logic and exponential backoff.
        Integrates with circuit breaker - opens circuit after consecutive failures.
    .PARAMETER ScriptBlock
        The operation to execute (typically an MCP tool call).
    .PARAMETER Server
        MCP server name for circuit breaker tracking.
    .PARAMETER MaxRetries
        Maximum retry attempts (default: 3).
    .PARAMETER BaseDelayMs
        Base delay in ms for exponential backoff (default: 1000).
    .PARAMETER TimeoutMs
        Per-attempt timeout in ms (default: 30000).
    .OUTPUTS
        PSCustomObject with Success, Result, Attempts, TotalDelayMs, CircuitState.
    #>
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory)]
        [string]$Server,
        [int]$MaxRetries = 3,
        [int]$BaseDelayMs = 1000,
        [int]$TimeoutMs = 30000
    )

    if ($MaxRetries -lt 0) { $MaxRetries = 0 }
    if ($BaseDelayMs -lt 0) { $BaseDelayMs = 0 }

    $circuit = Get-McpCircuitState -Server $Server

    if ($circuit.State -eq "OPEN") {
        return [PSCustomObject]@{
            Success = $false
            Result = $null
            Attempts = 0
            TotalDelayMs = 0
            CircuitState = "OPEN"
            Error = "Circuit breaker OPEN for $Server - failing fast"
        }
    }

    $attempts = 0
    $totalDelay = 0
    $lastError = $null
    $consecutiveFailures = $circuit.FailureCount

    for ($i = 0; $i -le $MaxRetries; $i++) {
        $attempts++
        try {
            # Per-attempt timeout: run the scriptblock in a cancellable runspace
            # (native .NET, same-process) so a hanging MCP call is aborted instead of
            # blocking the retry loop. Unlike Start-Job, this preserves the caller's
            # closures and propagates scriptblock exceptions to the catch below.
            $ps = [System.Management.Automation.PowerShell]::Create()
            [void]$ps.AddScript($ScriptBlock)
            $async = $ps.BeginInvoke()
            if ($async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
                # EndInvoke wraps scriptblock errors in a .NET TargetInvocation wrapper;
                # re-throw the InnerException so the caller sees the real message ("boom").
                try {
                    $result = $ps.EndInvoke($async)
                } catch {
                    $inner = $_.Exception.InnerException
                    throw ($inner ? $inner : $_)
                }
            } else {
                $ps.Stop()
                $async.AsyncWaitHandle.WaitOne(500) | Out-Null
                throw "Timed out after $TimeoutMs ms"
            }
            $newState = @{
                State = "CLOSED"
                FailureCount = 0
                LastFailure = $circuit.LastFailure
                LastSuccess = (Get-IsoTimestamp)
                OpenedAt = $null
            }
            Set-McpCircuitState -Server $Server -State $newState

            return [PSCustomObject]@{
                Success = $true
                Result = $result
                Attempts = $attempts
                TotalDelayMs = $totalDelay
                CircuitState = "CLOSED"
                Error = $null
            }
        } catch {
            # Propagates either a scriptblock exception (via EndInvoke) or our
            # "Timed out after N ms" throw — both feed the retry/circuit-breaker.
            $lastError = $_.Exception.Message
            $consecutiveFailures++

            if ($i -lt $MaxRetries) {
                $delay = $BaseDelayMs * [math]::Pow(2, $i)
                $totalDelay += $delay
                Start-Sleep -Milliseconds $delay
            }
        } finally {
            if ($ps) {
                try { $ps.Runspace.Dispose() } catch { Write-Debug "mcp-resilience: $($_.Exception.Message)" }
                $ps.Dispose()
            }
        }
    }

    # All retries exhausted
    $newState = @{
        FailureCount = $consecutiveFailures
        LastFailure = (Get-IsoTimestamp)
        LastSuccess = $circuit.LastSuccess
    }
    if ($consecutiveFailures -ge 3) {
        $newState.State = "OPEN"
        if ($circuit.State -ne "OPEN") {
            $newState.OpenedAt = (Get-IsoTimestamp)
        } else {
            $newState.OpenedAt = $circuit.OpenedAt
        }
    } else {
        $newState.State = $circuit.State
        $newState.OpenedAt = $circuit.OpenedAt
    }
    Set-McpCircuitState -Server $Server -State $newState

    return [PSCustomObject]@{
        Success = $false
        Result = $null
        Attempts = $attempts
        TotalDelayMs = $totalDelay
        CircuitState = $newState.State
        Error = "All $attempts attempts failed. Last error: $lastError"
    }
}

# -- Aggregate Health Check --

function Get-McpHealthReport {
    <#
    .SYNOPSIS
        Runs health checks on all configured MCP servers and returns a report.
    .PARAMETER ConfigPath
        Path to opencode.json (default: opencode.json in project root).
    .OUTPUTS
        Array of PSCustomObject with Server, Status, Detail, LatencyMs, CircuitState.
    #>
    param(
        [string]$ConfigPath = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "opencode.json")
    )

    if (-not (Test-Path $ConfigPath)) {
        return @([PSCustomObject]@{
            Server = "config"
            Status = "FAIL"
            Detail = "opencode.json not found at $ConfigPath"
            LatencyMs = 0
            CircuitState = "N/A"
        })
    }

    try {
        $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return @([PSCustomObject]@{
            Server = "config"
            Status = "FAIL"
            Detail = "opencode.json parse error: $($_.Exception.Message)"
            LatencyMs = 0
            CircuitState = "N/A"
        })
    }

    if (-not $config.mcp) {
        return @([PSCustomObject]@{
            Server = "config"
            Status = "WARN"
            Detail = "No 'mcp' section in opencode.json"
            LatencyMs = 0
            CircuitState = "N/A"
        })
    }

    $results = @()

    foreach ($prop in $config.mcp.PSObject.Properties) {
        $serverName = $prop.Name
        $serverValue = $prop.Value
        $serverConfig = @{
            type = if ($serverValue.type) { $serverValue.type } else { "unknown" }
            enabled = $serverValue.enabled
            url = if ($serverValue.PSObject.Properties['url']) { $serverValue.url } else { $null }
            command = if ($serverValue.PSObject.Properties['command']) { $serverValue.command } else { $null }
            timeout = if ($serverValue.PSObject.Properties['timeout']) { $serverValue.timeout } else { $null }
        }

        $probe = Test-McpServer -Server $serverConfig -ServerName $serverName
        $circuit = Get-McpCircuitState -Server $serverName

        $results += [PSCustomObject]@{
            Server = $serverName
            Status = $probe.Status
            Detail = $probe.Detail
            LatencyMs = $probe.LatencyMs
            CircuitState = $circuit.State
            FailureCount = $circuit.FailureCount
        }
    }

    return $results
}
