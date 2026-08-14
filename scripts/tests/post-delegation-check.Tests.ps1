#requires -Version 7
<#
.SYNOPSIS
    Tests for C7: post-delegation-check.ps1 — combines git-diff + write-scope + empty-output detection.

    Run: Invoke-Pester .\scripts\tests\post-delegation-check.Tests.ps1
#>

BeforeAll {
    $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'post-delegation-check.ps1'
}

Describe "post-delegation-check.ps1 — basic validation (C7)" {
    It "script has no syntax errors" {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "accepts -Quiet and emits JSON with passed field" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -BaseRef HEAD -Quiet" 2>&1
        # Filter for the JSON line (starts with {), ignoring git warnings
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
        $json | Should -Not -BeNull
        $json.PSObject.Properties.Name -contains 'passed' | Should -BeTrue
        $json.PSObject.Properties.Name -contains 'checks' | Should -BeTrue
    }
}

