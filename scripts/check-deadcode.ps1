#requires -Version 5.1
<#
.SYNOPSIS
    Lightweight dead-code ratchet for PowerShell scripts.

.DESCRIPTION
    Flags functions DEFINED in scripts/**/*.ps1 that are never REFERENCED
    by name anywhere in the script tree. Conservative by design: a function
    whose name appears more than once across the corpus is considered live.
    This is false-positive-free for static calls (possible false negatives
    for dynamic invocation via the call operator with a variable -- acceptable
    for a read-only analysis gate; no dynamic execution of user input).

    Analog to the deadcode-ratchet.sh praised in
    docs/propuestas/AUDIT-gentleman-agent-gh.md Section 5.3, applied to
    this PowerShell/Node agent-config repo (which lacks a Go deadcode tool).

    Measure-only by default (prints findings, exit 0).
    Pass -FailOnDead to promote to a build breaker once baseline is clean.
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string[]]$ScanPaths = @('scripts', '.github'),
    [switch]$FailOnDead
)
$ErrorActionPreference = 'Stop'

# 1. Gather source files (exclude coverage output + this script's own dir noise).
$files = Get-ChildItem -Path $ScanPaths -Filter '*.ps1' -Recurse -File |
    Where-Object { $_.FullName -notmatch '_coverage' }

if (-not $files) {
    Write-Output 'OK: no PowerShell files scanned'
    exit 0
}

# 2. Build a single corpus for cross-file reference counting.
$corpusText = ($files | ForEach-Object { (Get-Content $_.FullName -Raw) + "`n" }) -join ''

# 3. Per file: extract function definitions and check corpus-wide references.
$dead = @()
foreach ($f in $files) {
    $src = Get-Content $f.FullName -Raw
    foreach ($m in [regex]::Matches($src, '(?m)^[ \t]*function[ \t]+([A-Za-z0-9_\-]+)')) {
        $name = $m.Groups[1].Value
        $occurrences = [regex]::Matches(
            $corpusText,
            '(?<![A-Za-z0-9_])' + [regex]::Escape($name) + '(?![A-Za-z0-9_])'
        ).Count
        # count == 1 means only the definition line itself matched -> never called
        if ($occurrences -le 1) {
            $dead += [pscustomobject]@{
                Function = $name
                File     = $f.FullName.Replace('\', '/')
            }
        }
    }
}

# 4. Report
if ($dead) {
    Write-Warning "deadcode-ratchet: $($dead.Count) unreferenced function(s) found:"
    $dead | ForEach-Object {
        Write-Warning "    $($_.Function) -> $($_.File)"
    }
    Write-Warning 'These may be live via dynamic invocation. Clean baseline then run with -FailOnDead.'
    if ($FailOnDead) {
        Write-Error "deadcode-ratchet: $($dead.Count) dead function(s) -- failing build (-FailOnDead)"
        exit 1
    }
} else {
    Write-Output 'OK: deadcode-ratchet -- no unreferenced functions found'
}

exit 0
