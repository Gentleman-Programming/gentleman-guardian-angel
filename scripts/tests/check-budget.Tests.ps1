#requires -Version 7

<#
.SYNOPSIS
    Tests for C6: check-budget.ps1 — budget constraint enforcement.
#>

BeforeAll {
    $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'check-budget.ps1'
}

Describe "check-budget.ps1 — within budget (C6)" {
    It "returns OK with healthy values" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -ToolCalls 12 -Steps 7 -ElapsedSeconds 90 -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json
        $json.passed | Should -BeTrue
        $json.violations.Count | Should -Be 0
        $json.loopDetected | Should -BeFalse
    }

    It "reports tool call violation at limit+1" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -ToolCalls 26 -Steps 5 -ElapsedSeconds 30 -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json
        $json.passed | Should -BeFalse
        $json.violations | Should -Contain "tool-calls: 26 exceeds limit 25"
    }

    It "reports step violation" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -ToolCalls 5 -Steps 16 -ElapsedSeconds 30 -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json
        $json.passed | Should -BeFalse
        $json.violations | Should -Contain "steps: 16 exceeds limit 15"
    }

    It "reports time violation" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -ToolCalls 5 -Steps 5 -ElapsedSeconds 301 -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json
        $json.passed | Should -BeFalse
        $json.violations | Should -Contain "time: 301 exceeds limit 300"
    }
}

Describe "check-budget.ps1 — syntax & structure (C6)" {
    It "script has no parse errors" {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "JSON includes all expected fields" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -ToolCalls 5 -Steps 3 -ElapsedSeconds 30 -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json
        $json.passed | Should -BeTrue
        $json.toolCalls | Should -Be 5
        $json.toolCallLimit | Should -Be 25
        $json.steps | Should -Be 3
        $json.stepLimit | Should -Be 15
        $json.elapsedSeconds | Should -Be 30
        $json.timeLimit | Should -Be 300
        $json.loopDetected | Should -BeFalse
    }
}

Describe "check-budget.ps1 — loop prevention (C6)" {
    It "detects repeated tool+args as loop" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -ToolName 'grep' -ToolArgs @{pattern='auth';path='.'} -LastToolName 'grep' -LastToolArgs @{pattern='auth';path='.'} -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json
        $json.loopDetected | Should -BeTrue
        $json.passed | Should -BeFalse
        $json.violations | Should -Contain "loop: repeated tool 'grep' with identical args"
    }

    It "does not flag different tools as loop" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -ToolName 'grep' -ToolArgs @{pattern='auth'} -LastToolName 'read' -LastToolArgs @{path='file.txt'} -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json
        $json.loopDetected | Should -BeFalse
    }
}

