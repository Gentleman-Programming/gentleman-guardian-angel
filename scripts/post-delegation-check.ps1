#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Post-delegation verification — combines git-diff + write-scope + empty-output
    detection into a single MANDATORY check run after every subagent delegation.

.DESCRIPTION
    Wraps three checks into one protocol-enforced gate:
      1. Empty-output detection (delegates to check-subagent-output.ps1)
      2. Write-scope validation (delegates to validate-write-scope.ps1)
      3. Git status summary

    Run after every subagent delegation BEFORE trusting its output.
    Detects silent failures (empty output, scope violations, unexpected files).

    JD Review fixes (C4-C9 cluster):
      - MEDIUM: Single-quote escaping on user-provided args (prevents cmd injection)
      - HIGH:   Timeout on pwsh subprocess calls (prevents indefinite hang)
      - LOW:    Warning when dependency scripts are missing

.PARAMETER BaseRef
    Git reference to diff against (default: HEAD).

.PARAMETER AllowedPaths
    Regex pattern(s) that modified files must match. REQUIRED for write-scope validation —
    if omitted, the check FAILS (fail-closed). Enforced by v3 Perm-4.

.PARAMETER ExpectedFiles
    Filenames that SHOULD appear in the diff (passed to check-subagent-output).

.PARAMETER RepoRoot
    Repository root (default: parent of script dir).

.PARAMETER TimeoutSeconds
    Timeout for subprocess calls (default: 30). Prevents indefinite hangs.

.PARAMETER Quiet
    JSON summary on stdout.

.EXAMPLE
    scripts\post-delegation-check.ps1                           # git diff + empty + scope
    scripts\post-delegation-check.ps1 -AllowedPaths "src/*" -ExpectedFiles "src/utils.ts"
#>
param(
    [string]$BaseRef        = "HEAD",
    [string[]]$AllowedPaths = @(),
    [string[]]$ExpectedFiles = @(),
    [string]$RepoRoot       = $(Split-Path -Parent $PSScriptRoot),
    [int]$TimeoutSeconds    = 30,
    [switch]$Quiet
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- C9/JD fix: escape single quotes to prevent command injection ---
function ConvertTo-SqlLiteral {
    param([string]$Value)
    $Value.Replace("'", "''")
}

# --- C9/JD fix: wrap pwsh subprocess with timeout to prevent indefinite hang ---
function Invoke-SubprocessWithTimeout {
    param([string]$CommandLine, [int]$TimeoutSec)
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new("pwsh", "-NoProfile -NoLogo -Command `"$CommandLine`"")
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute = $false
        $process = [System.Diagnostics.Process]::Start($psi)
        $completed = $process.WaitForExit($TimeoutSec * 1000)
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if (-not $completed) {
            $process.Kill()
            return [PSCustomObject]@{ output = @(); exitCode = -1; timedOut = $true; stderr = @($stderr) }
        }
        $lines = @()
        if ($stdout) { $lines += $stdout -split [char]10 }
        if ($stderr) { $lines += $stderr -split [char]10 }
        return [PSCustomObject]@{ output = $lines; exitCode = $process.ExitCode; timedOut = $false; stderr = @() }
    } catch {
        return [PSCustomObject]@{ output = @(); exitCode = -1; timedOut = $false; stderr = @($_ | Out-String) }
    }
}

$results = @{
    baseRef      = $BaseRef
    passed       = $true
    checks       = @()
}

# --- 1. Empty-output detection ---
$csoScript = Join-Path $RepoRoot 'scripts\check-subagent-output.ps1'
if (Test-Path $csoScript) {
    $escapedBase = ConvertTo-SqlLiteral $BaseRef
    $escapedRoot = ConvertTo-SqlLiteral $RepoRoot
    $csoCmd = "& '$csoScript' -BaseRef '$escapedBase' -RepoRoot '$escapedRoot' -Quiet"
    if ($ExpectedFiles) {
        $escapedFiles = ($ExpectedFiles | ForEach-Object { "'" + (ConvertTo-SqlLiteral $_) + "'" }) -join ' '
        $csoCmd += " -ExpectedFiles " + $escapedFiles
    }
    $csoSubproc = Invoke-SubprocessWithTimeout -CommandLine $csoCmd -TimeoutSec $TimeoutSeconds
    $csoResult = $csoSubproc.output | Where-Object { $_ -match '^\{' } | Select-Object -First 1 | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($csoSubproc.timedOut) {
        Write-Warning "check-subagent-output.ps1 timed out after $TimeoutSeconds s"
        $csoOk = $false
    } else {
        $csoOk = $csoResult -and $csoResult.status -ne 'FAIL'
    }
    $results.checks += [PSCustomObject]@{
        name   = "empty_output"
        passed = $csoOk
        detail = if ($csoSubproc.timedOut) { "TIMEOUT after $TimeoutSeconds s" }
                 elseif ($csoResult) { $csoResult.status } else { "no JSON returned" }
    }
    if (-not $csoOk) { $results.passed = $false }
} else {
    Write-Warning "check-subagent-output.ps1 not found at $csoScript — empty-output check skipped"
}

# --- 2. Write-scope validation ---
if ($AllowedPaths) {
    $wsScript = Join-Path $RepoRoot 'scripts\validate-write-scope.ps1'
    if (Test-Path $wsScript) {
        $escapedPaths = "'" + ((ConvertTo-SqlLiteral ($AllowedPaths -join ','))) + "'"
        $escapedBase  = ConvertTo-SqlLiteral $BaseRef
        $wsCmd = "& '$wsScript' -AllowedPaths $escapedPaths -BaseRef '$escapedBase'"
        $wsSubproc = Invoke-SubprocessWithTimeout -CommandLine $wsCmd -TimeoutSec $TimeoutSeconds
        if ($wsSubproc.timedOut) {
            Write-Warning "validate-write-scope.ps1 timed out after $TimeoutSeconds s"
            $wsOk = $false
        } else {
            $wsOutput = ($wsSubproc.output | Where-Object { $_ -match '\[CLEAN\]|\[VIOLATION\]' } | Select-Object -First 1)
            $wsOk = $wsOutput -match '\[CLEAN\]'
        }
        $results.checks += [PSCustomObject]@{
            name   = "write_scope"
            passed = $wsOk
            detail = if ($wsSubproc.timedOut) { "TIMEOUT after $TimeoutSeconds s" }
                     elseif ($wsOk) { "in scope" } else { "VIOLATION: files outside allowed paths" }
        }
        if (-not $wsOk) { $results.passed = $false }
    } else {
        Write-Warning "validate-write-scope.ps1 not found at $wsScript — write-scope check skipped"
    }
} else {
    $results.checks += [PSCustomObject]@{ name = "write_scope"; passed = $false; detail = "FAIL-CLOSED: AllowedPaths not provided — write-scope mandatory for all subagent delegations" }
    $results.passed = $false
}

# --- 3. Git status summary ---
$statusRaw = git -C $RepoRoot status --porcelain 2>&1
$changedFiles = @($statusRaw | Where-Object { $_ -and $_ -notmatch '^warning:' } |
    ForEach-Object { ($_ -replace '^\?\?\s+', '' -replace '^[MADRCU?!]+\s+', '').Trim() } |
    Where-Object { $_ })

$results.changed_files = $changedFiles
$results.file_count    = $changedFiles.Count

# --- Output ---
if ($Quiet) {
    $results | ConvertTo-Json -Compress
} else {
    $icon = if ($results.passed) { "OK  " } else { "FAIL" }
    Write-Output "$icon Post-delegation check ($($results.passed ? 'PASS' : 'FAIL')): $($results.file_count) file(s) changed"
    $results.checks | ForEach-Object {
        $c = if ($_.passed) { "  OK  " } else { "  FAIL" }
        Write-Output "$c $($_.name): $($_.detail)"
    }
    if ($results.changed_files) {
        Write-Output "  Files:"
        $results.changed_files | ForEach-Object { Write-Output "    $_" }
    }
    if (-not $results.passed) {
        Write-Output "`n  X  SILENT FAILURE RISK — review before proceeding"
        Write-Output "     See: mejora-log.md:571, RUNBOOK.md:26"
    }
}

$ec = if ($results.passed) { 0 } else { 1 }
exit $ec

