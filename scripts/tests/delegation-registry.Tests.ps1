#requires -Version 7

<#
.SYNOPSIS
    Tests for delegation-registry.ps1 — async subagent delegation state manager.

    Run: Invoke-Pester .\scripts\tests\delegation-registry.Tests.ps1
#>
Describe "delegation-registry.ps1 — async delegation lifecycle (C8)" {
    BeforeAll {
        $script:scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'delegation-registry.ps1'
        $script:testRegistry = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.learnings' 'delegation-registry.json'
    }

    AfterAll {
        Remove-Item $script:testRegistry -ErrorAction SilentlyContinue
    }

    It "script has no syntax errors" {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "register stores entry with pending status" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -Action register -TaskId 'ut-register-001' -AllowedPaths 'src/*' -Quiet" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $j = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
        $j.status | Should -Be "registered"
        $j.task_id | Should -Be "ut-register-001"
    }

    It "poll transitions pending → running" {
        & pwsh -NoProfile -Command "& '$scriptPath' -Action register -TaskId 'ut-poll-001' -AllowedPaths 'src/*' -Quiet" > $null
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -Action poll -TaskId 'ut-poll-001' -Quiet" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $j = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
        $j.status | Should -Be "running"
    }

    It "poll on unknown task returns not_found" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -Action poll -TaskId 'does-not-exist' -Quiet" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $j = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
        $j.status | Should -Be "not_found"
    }

    It "register without AllowedPaths throws" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -Action register -TaskId 'ut-nopath-001' -Quiet" 2>&1
        ($r | Out-String) | Should -Match "AllowedPaths"
    }

    It "re-prompt writes prompt file" {
        & pwsh -NoProfile -Command "& '$scriptPath' -Action register -TaskId 'ut-repr-001' -AllowedPaths 'src/*' -Quiet" > $null
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -Action re-prompt -TaskId 'ut-repr-001' -NewPrompt 'Focus on tests' -Quiet" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $j = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
        $j.status | Should -Be "re-prompted"
        $j.prompt_file | Should -Not -BeNullOrEmpty
        Test-Path $j.prompt_file | Should -BeTrue
        # Cleanup
        if (Test-Path $j.prompt_file) { Remove-Item $j.prompt_file -ErrorAction SilentlyContinue }
    }

    It "list returns all entries as JSON" {
        $cmd = "& '$scriptPath' -Action register -TaskId 'ut-list-001' -AllowedPaths 'src/*' -Quiet; " +
               "& '$scriptPath' -Action register -TaskId 'ut-list-002' -AllowedPaths 'src/*' -Quiet; " +
               "& '$scriptPath' -Action list -Quiet"
        $r = & pwsh -NoProfile -Command $cmd 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $j = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
        ($j | Measure-Object).Count | Should -BeGreaterThan 0
    }
}

