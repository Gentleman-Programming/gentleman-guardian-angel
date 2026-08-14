#requires -Version 7
Set-StrictMode -Version Latest
<#
.SYNOPSIS
    Bash-syntax safe executor for PowerShell 5.1 environments.
.DESCRIPTION
    PowerShell 5.1 does NOT support &&, ||, or @{var} hash literals.
    Git Bash at "C:\Program Files\Git\bin\bash.exe" is the working interpreter.
    This script provides Invoke-Bash that delegates to Git Bash.
.EXAMPLE
    . "$PSScriptRoot\bash-safe.ps1"
    Invoke-Bash "git status --short && git log --oneline -5"
.NOTES
    Self-test: run Test-BashSafe after dot-sourcing.
#>

# Locate real bash interpreter — check 4 common locations + PATH fallback
$script:GitBash = $null
$bashCandidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe"
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    "$env:ChocolateyInstall\lib\git\tools\bin\bash.exe"
)
foreach ($c in $bashCandidates) { if (Test-Path $c) { $script:GitBash = $c; break } }
if (-not $script:GitBash) { $script:GitBash = (Get-Command bash -ErrorAction SilentlyContinue).Source }
if (-not $script:GitBash -or -not (Test-Path $script:GitBash)) { throw "No bash interpreter found. Install Git for Windows or WSL." }

# Server command patterns + default ports
$script:ServerPatterns = @(
    '^\s*ng\s+serve', '^\s*npm\s+run\s+(dev|start|serve)', '^\s*yarn\s+(dev|start|serve)',
    '^\s*pnpm\s+run\s+(dev|start|serve)', '^\s*dotnet\s+run', '^\s*python\s+-m\s+http\.server',
    '^\s*python\s+.*server\.py', '^\s*node\s+.*server\.(js|ts)', '^\s*npx\s+.*serve',
    '^\s*jekyll\s+serve', '^\s*hugo\s+server', '^\s*vite(\s|$)', '^\s*webpack-dev-server',
    '^\s*ts-node\s+.*server'
)
$script:ServerDefaultPorts = @(
    @{ pattern = '^\s*ng\s+serve'; port = 4200 }, @{ pattern = '^\s*vite'; port = 5173 },
    @{ pattern = '^\s*webpack-dev-server'; port = 8080 }, @{ pattern = '^\s*jekyll\s+serve'; port = 4000 },
    @{ pattern = '^\s*hugo\s+server'; port = 1313 }, @{ pattern = '^\s*python\s+-m\s+http\.server'; port = 8000 },
    @{ pattern = '^\s*dotnet\s+run'; port = 5000 }, @{ pattern = '^\s*(npm|yarn|pnpm)\s+run\s+dev'; port = 3000 }
)

# Detect if command matches known server patterns
function Test-IsServerCommand {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$Command)
    foreach ($pattern in $script:ServerPatterns) { if ($Command -match $pattern) { return $true } }
    return $false
}

# Extract port from server command, or return default
function Get-ServerPort {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$Command)
    if ($Command -match '--port[= ](\d+)') { return [int]$Matches[1] }
    if ($Command -match '(?:^|\s)-p\s+(\d+)') { return [int]$Matches[1] }
    if ($Command -match ':(\d{4,5})(?:\s|$)') { return [int]$Matches[1] }
    if ((Test-IsServerCommand $Command) -and ($Command -match '(\d{4,5})$')) { return [int]$Matches[1] }
    foreach ($entry in $script:ServerDefaultPorts) { if ($Command -match $entry.pattern) { return $entry.port } }
    return $null
}

# Check if TCP port is in use on localhost (uses TcpClient, no module dependency)
function Test-PortInUse {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][int]$Port)
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $ar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne(1000, $false)
        if ($ok) { $client.EndConnect($ar); $client.Close(); return $true }
        $client.Close(); return $false
    } catch { return $false }
}

# SECURITY: Validate that a command string contains no injection vectors.
# bash -c interprets the entire string — backticks and $() execute arbitrary
# code inside the bash invocation. This function rejects commands that contain
# bash command substitution patterns, which are the real injection risk.
# NOTE: quotes (single/double) are normal bash syntax and are NOT rejected.
# The background path escapes " to \" to prevent quote-breaking.
function Test-SafeCommand {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$Command)

    # Reject $() subshell expansion — executes arbitrary code inside bash.
    if ($Command -match '\$\(') {
        Write-Warning "[bash-safe] SECURITY: command contains $() subshell — refusing to execute."
        return $false
    }

    # Reject backtick command substitution — same risk as $().
    if ($Command -match '`') {
        Write-Warning "[bash-safe] SECURITY: command contains backtick — refusing to execute."
        return $false
    }

    # Reject process substitution <(...) — spawns subprocesses outside caller control.
    if ($Command -match '<\(') {
        Write-Warning "[bash-safe] SECURITY: command contains process substitution <(... ) — refusing to execute."
        return $false
    }

    # Reject process substitution >(...) — same risk.
    if ($Command -match '>\(') {
        Write-Warning "[bash-safe] SECURITY: command contains process substitution >(... ) — refusing to execute."
        return $false
    }

    # Reject ANSI-C quoting $'...' — can embed arbitrary escape sequences.
    if ($Command -match "\\\$'") {
        Write-Warning "[bash-safe] SECURITY: command contains ANSI-C quoting \$'...' — refusing to execute."
        return $false
    }

    # Reject bash -c passthrough — nested shell invocation bypasses this layer.
    if ($Command -match 'bash\s+-c\s') {
        Write-Warning "[bash-safe] SECURITY: command contains bash -c passthrough — refusing to execute."
        return $false
    }

    # Reject eval — arbitrary code execution. Block as standalone command or via control operators.
    if ($Command -match '(^|;|&&|\|\||\|)\s*eval(\s|$)') {
        Write-Warning "[bash-safe] SECURITY: command contains eval — refusing to execute."
        return $false
    }

    # Reject exec as standalone command (not subcommand like `docker exec` or `kubectl exec`).
    if ($Command -match '(^|;|&&|\|\||\|)\s*exec(\s|$)') {
        Write-Warning "[bash-safe] SECURITY: command contains exec — refusing to execute."
        return $false
    }

    # Reject source — loads arbitrary script into current shell.
    # NOTE: `. ` not blocked — too many false positives (find ., git -C ., ls .).
    if ($Command -match '(^|;|&&|\|\||\|)\s*source(\s|$)') {
        Write-Warning "[bash-safe] SECURITY: command contains source — refusing to execute."
        return $false
    }

    # Reject alias — can override builtins.
    if ($Command -match '(^|;|&&|\|\||\|)\s*alias(\s|$)') {
        Write-Warning "[bash-safe] SECURITY: command contains alias — refusing to execute."
        return $false
    }

    # Reject declare/typeset -f — can dump function source.
    if ($Command -match '(declare|typeset)\s+(-f|-F)') {
        Write-Warning "[bash-safe] SECURITY: command contains declare/typeset -f — refusing to execute."
        return $false
    }

    return $true
}

# Main entry point — invoke command via Git Bash
# SECURITY MODEL:
#   - The $Command parameter is passed to `bash -c` as a SINGLE argument.
#   - Sync paths (lines below) are safe: PowerShell passes $Command as a
#     single argv element to the bash process — no re-interpretation.
#   - The background path builds a ProcessStartInfo.Arguments string, which
#     IS vulnerable to quote-breaking if $Command contains double-quotes.
#     We escape " → \" to prevent this.
#   - Callers MUST NOT interpolate user input into $Command. Always use
#     string literals or pre-validated strings.
function Invoke-Bash {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory, Position=0)][string]$Command,
        [switch]$CaptureOutput,
        [switch]$Background
    )
    $ErrorActionPreference = 'Continue'

    # Input validation — reject commands that look like injection attempts
    if (-not (Test-SafeCommand $Command)) {
        if ($CaptureOutput) { return [PSCustomObject]@{ Output = @(); ExitCode = 126 } }
        throw "Invoke-Bash: command rejected by security validation. See warnings above."
    }

    # Server command detection — warn if launched without -Background
    $isServer = Test-IsServerCommand $Command
    if ($isServer -and -not $Background) {
        Write-Warning "[bash-safe] '$($Command -replace '^(.{55}).*', '$1…')' parece un SERVIDOR (nunca termina)."
        Write-Warning "[bash-safe]   Usá -Background: Invoke-Bash '$($Command -replace "'","''")' -Background"
        Write-Warning "[bash-safe]   O dev-server.ps1: .\scripts\dev-server.ps1 -Action Start -Name <name> -Command $($script:GitBash) -Arguments '-c ""$($Command -replace '"','""')""'"
    }
    if ($isServer) {
        $port = Get-ServerPort $Command
        if ($port) {
            $inUse = Test-PortInUse $port
            if ($inUse -eq $true) {
                Write-Warning "[bash-safe] Puerto $port ya está EN USO — otro servidor está corriendo ahí."
                Write-Warning "[bash-safe]   Descubrí quién: Get-Process -Id ((Get-NetTCPConnection -LocalPort $port).OwningProcess)"
                Write-Warning "[bash-safe]   O usá un puerto distinto: --port <otro>"
            } elseif ($null -eq $inUse) { Write-Warning "[bash-safe] No se pudo verificar si el puerto $port está ocupado." }
        }
    }

    if ($Background) {
        # SECURITY: Escape backslashes first, then double-quotes, then dollar
        # signs and backticks. Order matters: if we escaped quotes first, a
        # trailing \ before " would produce \" which bash interprets as an
        # escaped quote, not backslash+quote. Dollar signs and backticks are
        # special to Windows cmd.exe when passed through ProcessStartInfo.
        $escapedCommand = $Command -replace '\\', '\\\\' -replace '"', '\"' -replace '\$', '`$'
        $psi = [System.Diagnostics.ProcessStartInfo]@{
            FileName = $script:GitBash; Arguments = "-c `"$escapedCommand`""
            UseShellExecute = $false; CreateNoWindow = $true
        }
        try {
            $p = [System.Diagnostics.Process]::Start($psi)
            $msg = "[background] PID $($p.Id): $Command"
            if ($CaptureOutput) { return [PSCustomObject]@{ Output = @($msg); ExitCode = 0 } }
            Write-Host "[bash-safe] Background PID $($p.Id): $Command" -ForegroundColor Green
            return
        } catch {
            Write-Error "[bash-safe] Error starting background process: $_"
            if ($CaptureOutput) { return [PSCustomObject]@{ Output = @(); ExitCode = 1 } }
            return
        }
    }

    # Synchronous behavior — safe: PowerShell passes $Command as a single
    # argument to bash, no shell re-interpretation happens on the PS side.
    if ($CaptureOutput) {
        $output = & $script:GitBash -c $Command 2>&1
        return [PSCustomObject]@{ Output = $output; ExitCode = $LASTEXITCODE }
    } else {
        & $script:GitBash -c $Command
        if ($LASTEXITCODE -ne 0) { Write-Warning "Invoke-Bash exit=$LASTEXITCODE : $Command" }
    }
}

# Auto-discover GENTLEMAN_AGENT_ROOT on dot-source (via junction)
$__dir = Split-Path $MyInvocation.MyCommand.Path -Parent
$__item = Get-Item $__dir
if ($__item.LinkType -eq "Junction" -and $__item.Target) {
    $env:GENTLEMAN_AGENT_ROOT = (Split-Path $__item.Target -Parent).Replace('\', '/')
}
