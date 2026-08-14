#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Pester tests for setup-machine.ps1 — Install-McpServer function.
    Tests the check/install pattern with mock scriptblocks (no real installs).
.NOTES
    ponytail: mock-only tests — no actual package installs.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # Define the helper functions inline (same as setup-machine.ps1)
    # These are simple Write-Host wrappers — safe to redefine.
    function info  { Write-Host "==> " -ForegroundColor Cyan -NoNewline; Write-Host "$args" }
    function ok    { Write-Host "[ok] " -ForegroundColor Green -NoNewline; Write-Host "$args" }
    function warn  { Write-Host "[warn] " -ForegroundColor Yellow -NoNewline; Write-Host "$args" }
    function err   { Write-Host "[err] " -ForegroundColor Red -NoNewline; Write-Host "$args"; exit 1 }
    function skip  { Write-Host "[skip] " -ForegroundColor DarkGray -NoNewline; Write-Host "$args" }

    # Define Install-McpServer — same logic as setup-machine.ps1 L240-253
    function Install-McpServer {
        param([string]$Name, [scriptblock]$Check, [scriptblock]$Install, [string]$ManualHint)
        if (& $Check) { skip "$Name already installed"; return $false }
        try {
            info "Installing $Name..."
            $script:LASTEXITCODE = 0
            $null = & $Install
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
            ok "$Name installed"
            return $true
        } catch {
            warn "$Name install failed — $ManualHint"
            return $false
        }
    }
}

# ============================================================
Describe 'Install-McpServer' {
    It 'returns false and skips when Check returns true (already installed)' {
        $check = { return $true }
        $install = { throw "should not run" }
        $result = Install-McpServer -Name "test-skip" -Check $check -Install $install -ManualHint "manual"
        $result | Should -Be $false
    }

    It 'returns true when Install succeeds' {
        $check = { return $false }
        $install = { Write-Output "installed" }
        $result = Install-McpServer -Name "test-ok" -Check $check -Install $install -ManualHint "manual"
        $result | Should -Be $true
    }

    It 'returns false when Install scriptblock throws' {
        $check = { return $false }
        $install = { throw "install failed" }
        $result = Install-McpServer -Name "test-fail" -Check $check -Install $install -ManualHint "manual hint"
        $result | Should -Be $false
    }

    It 'returns false when Install sets non-zero LASTEXITCODE' {
        $check = { return $false }
        $install = { $script:LASTEXITCODE = 1 }
        $result = Install-McpServer -Name "test-exit1" -Check $check -Install $install -ManualHint "manual"
        $result | Should -Be $false
    }
}
