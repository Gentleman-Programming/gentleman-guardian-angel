#requires -Version 7

<#
.SYNOPSIS
    Tests for C9: check-token-budget.ps1 — token budget monitor.
#>

Describe "check-token-budget.ps1 — budget logic (C9)" {
    BeforeAll {
        $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'check-token-budget.ps1'

        # Inline copy of the budget evaluation logic
        function Test-BudgetPass {
            param([int]$AvgBytes, [int]$BudgetBytes = 2000)
            return $AvgBytes -le $BudgetBytes
        }
    }

    It "script has no parse errors" {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "budget 2000 rejects avg 2491" {
        Test-BudgetPass -AvgBytes 2491 -BudgetBytes 2000 | Should -BeFalse
    }

    It "budget 2000 accepts avg 1891" {
        Test-BudgetPass -AvgBytes 1891 -BudgetBytes 2000 | Should -BeTrue
    }

    It "budget 5000 accepts avg 2491" {
        Test-BudgetPass -AvgBytes 2491 -BudgetBytes 5000 | Should -BeTrue
    }

    It "script emits JSON with default budget" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
        $json | Should -Not -BeNull
        $json.stats.skills.count | Should -BeGreaterThan 0
        $json.stats.skills.budget | Should -Be 2000
    }

    It "JSON includes prompts stats with overBudgetFiles (regression guard)" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
        $json | Should -Not -BeNull
        $json.stats.prompts | Should -Not -BeNull
        $json.stats.prompts.overBudgetFiles | Should -Not -BeNullOrEmpty
        $json.stats.prompts.passed | Should -BeOfType [bool]
        $json.stats.prompts.budget | Should -Be 2000
    }

    It "exits code 1 when budget exceeded (current repo state)" {
        & pwsh -NoProfile -Command "& '$scriptPath' -Json > `$null" 2>&1 | Out-Null
        $global:LASTEXITCODE | Should -Be 1
    }
}

