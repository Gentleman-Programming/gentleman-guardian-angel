#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Validates that subagent writes stayed within declared scope.
.DESCRIPTION
    After delegation, compares git diff against allowed glob patterns to detect scope violations.
    Part of the reliability hardening for gentleman-agent-gh.
.PARAMETER AllowedPaths
    Comma-separated list of allowed glob patterns (e.g., "src/auth/*,src/api/*").
    Supports: *, ? (single char). Does NOT support: **, {a,b}, regex syntax.
.PARAMETER BaseRef
    Git ref to compare against (default: HEAD).
.PARAMETER Staged
    Diff the index (staged changes) against BaseRef instead of the working tree.
    Used by the pre-commit gate to scope-check what is about to be committed.
.PARAMETER Json
    Output as JSON.
.EXAMPLE
    .\scripts\validate-write-scope.ps1 -AllowedPaths "src/auth/*,src/api/*"
    .\scripts\validate-write-scope.ps1 -AllowedPaths "scripts/*" -BaseRef "HEAD~1" -Json
    .\scripts\validate-write-scope.ps1 -AllowedPaths "scripts/*" -Staged
#>
param(
    [Parameter(Mandatory)]
    [System.Management.Automation.AllowEmptyCollection()]
    [string[]]$AllowedPaths,
    [string]$BaseRef = "HEAD",
    [switch]$Staged,
    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$violations = @()
$clean = @()

# Validate AllowedPaths is not empty
if (-not $AllowedPaths -or $AllowedPaths.Trim() -eq '') {
    $msg = "AllowedPaths cannot be empty - this would flag ALL files as violations"
    if ($Json) { @{ status = "error"; message = $msg } | ConvertTo-Json } else { Write-Output "ERROR: $msg" }
    exit 1
}

# Validate BaseRef is not empty
if (-not $BaseRef -or $BaseRef.Trim() -eq '') {
    $msg = "BaseRef cannot be empty"
    if ($Json) { @{ status = "error"; message = $msg } | ConvertTo-Json } else { Write-Output "ERROR: $msg" }
    exit 1
}

# Guard against BaseRef with spaces (would cause argument splitting)
if ($BaseRef -match '\s') {
    $msg = "BaseRef contains spaces - use a single ref (e.g., HEAD, main, abc123)"
    if ($Json) { @{ status = "error"; message = $msg } | ConvertTo-Json } else { Write-Output "ERROR: $msg" }
    exit 1
}

# Run git diff with error checking
$gitOutput = $null
try {
    if ($Staged) {
        $gitOutput = & git diff --cached --name-only $BaseRef 2>&1
    } else {
        $gitOutput = & git diff --name-only $BaseRef 2>&1
    }
    $exitCode = $LASTEXITCODE
} catch {
    $exitCode = 1
}

if ($exitCode -ne 0) {
    $detail = if ($gitOutput) { $gitOutput -join ' ' } else { "git diff returned exit code $exitCode" }
    $msg = "git diff failed (exit $exitCode): $detail"
    if ($Json) { @{ status = "error"; message = $msg } | ConvertTo-Json } else { Write-Output "ERROR: $msg" }
    exit 1
}

# Ensure $changedFiles is always an array (PS7 single-string quirk)
if ($null -eq $gitOutput) {
    $changedFiles = @()
} elseif ($gitOutput -is [string]) {
    $changedFiles = @($gitOutput)
} else {
    $changedFiles = @($gitOutput)
}

# Filter empty/whitespace entries: a clean tree makes `git diff --name-only` emit a
# single empty string, which would otherwise be scored as a false-VIOLATION.
# git stderr (e.g. CRLF normalization warnings) arrives as ErrorRecord via 2>&1 —
# keep only text lines so .Trim() can never hit a non-string.
$changedFiles = @($changedFiles | Where-Object { $_ -is [string] -and $_.Trim() })

# Runtime state files auto-update every session (score, mode, bitacora) — not real
# change units. Same allowlist as scripts/verify.ps1 Git Hygiene check (L77).
$runtimeFiles = @('\.gentleman-mode$', '\.project\.json$', 'BITACORA\.md$')
$changedFiles = @($changedFiles | Where-Object {
    $file = $_
    $skip = $false
    foreach ($p in $runtimeFiles) { if ($file -match $p) { $skip = $true; break } }
    -not $skip
})

if ($changedFiles.Count -eq 0) {
    if ($Json) {
        @{ status = "CLEAN"; violations = @(); clean = @(); totalChanged = 0; totalViolations = 0; message = "No changed files detected" } | ConvertTo-Json -Depth 3
    } else {
        Write-Output "[CLEAN] No changed files detected against $BaseRef"
    }
    exit 0
}

# Parse and validate patterns
$patterns = @($AllowedPaths -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

if ($patterns.Count -eq 0) {
    $msg = "No valid patterns after parsing AllowedPaths"
    if ($Json) { @{ status = "error"; message = $msg } | ConvertTo-Json } else { Write-Output "ERROR: $msg" }
    exit 1
}

# Convert glob patterns to regex (escape metacharacters first, then convert glob wildcards)
function Convert-GlobToRegex {
    param([string]$Glob)
    # Escape regex metacharacters (except * and ? which we handle as glob)
    $escaped = [regex]::Escape($Glob)
    # Un-escape * (glob wildcard -> regex .*)
    $escaped = $escaped -replace '\\\*', '.*'
    # Un-escape ? (glob single char -> regex .)
    $escaped = $escaped -replace '\\\?', '.'
    # Wrap in anchors
    return "^$escaped$"
}

foreach ($file in $changedFiles) {
    $matched = $false
    foreach ($pattern in $patterns) {
        try {
            $regex = Convert-GlobToRegex -Glob $pattern
            if ($file -match $regex) {
                $matched = $true
                break
            }
        } catch {
            # Invalid pattern -> fail CLOSED. A malformed pattern must never let a
            # violating file through as CLEAN (silent skip was a fails-open risk).
            $msg2 = "Invalid pattern '$pattern': $($_.Exception.Message)"
            if ($Json) { @{ status = 'error'; message = $msg2 } | ConvertTo-Json } else { Write-Output "ERROR: $msg2" }
            exit 1
        }
    }
    if ($matched) {
        $clean += $file
    } else {
        $violations += $file
    }
}

$hasViolations = $violations.Count -gt 0

if ($Json) {
    @{
        status = if ($hasViolations) { "VIOLATION" } else { "CLEAN" }
        violations = $violations
        clean = $clean
        totalChanged = $changedFiles.Count
        totalViolations = $violations.Count
        patterns = $patterns
    } | ConvertTo-Json -Depth 3
} else {
    if ($hasViolations) {
        Write-Output "[VIOLATION] $($violations.Count) file(s) outside allowed scope:"
        foreach ($v in $violations) {
            Write-Output "  - $v"
        }
        Write-Output ""
        Write-Output "Allowed patterns: $($patterns -join ', ')"
        Write-Output "Clean files: $($clean.Count)"
    } else {
        Write-Output "[CLEAN] All $($changedFiles.Count) changed file(s) within scope"
        Write-Output "Patterns: $($patterns -join ', ')"
    }
}

if ($hasViolations) { exit 1 }
