#requires -Version 7

Set-StrictMode -Version Latest
<#
.SYNOPSIS
    Debug script for intake-verify.ps1 — runs inline verification with verbose output.
.DESCRIPTION
    Invokes intake-verify checks directly for debugging. Not for production use.
#>
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -Command {
      Set-StrictMode -Version Latest
      $ErrorActionPreference = 'Stop'

    # Run the intake script with a wrapper that catches line numbers
    try {
        & 'scripts/intake-verify.ps1' -p '.' -f json
    } catch {
        $err = $_
        "=== FULL ERROR ==="
        $err | Format-List * -Force
        "=== STACK TRACE ==="
        $err.ScriptStackTrace
        "=== POSITION ==="
        if ($err.InvocationInfo) {
            "Line: $($err.InvocationInfo.ScriptLineNumber)"
            "Position: $($err.InvocationInfo.OffsetInLine)"
            "Script: $($err.InvocationInfo.ScriptName)"
        }
        $host.SetShouldExit(1)
    }
} 2>&1

