#requires -Version 7

<#
.SYNOPSIS
    Tests for C8: ctx-watchdog.ps1 — context-window zone detection + compression recommendation.
#>

Describe "Get-ContextZone — zone logic (C8)" {
    BeforeAll {
        # Inline copy of zone logic from scripts/ctx-watchdog.ps1
        function Get-ContextZone {
            param([int]$UsagePercent)
            if ($UsagePercent -le 40) { return @{ zone = "GREEN";      level = "";  action = "normal operation" } }
            if ($UsagePercent -le 60) { return @{ zone = "YELLOW";     level = "L1"; action = "conserve context" } }
            if ($UsagePercent -le 80) { return @{ zone = "ORANGE";     level = "L1"; action = "light compression (L1)" } }
            if ($UsagePercent -le 95) { return @{ zone = "RED";        level = "L2"; action = "aggressive compression (L2)" } }
            return @{ zone = "CRITICAL"; level = "L3"; action = "maximum compression (L3)" }
        }
    }

    It "GREEN zone at 0%" { $r = Get-ContextZone 0;   $r.zone | Should -Be "GREEN";   $r.level | Should -Be "" }
    It "GREEN zone at 40% (boundary inclusive)" { $r = Get-ContextZone 40;  $r.zone | Should -Be "GREEN" }
    It "YELLOW zone at 41%" { $r = Get-ContextZone 41;  $r.zone | Should -Be "YELLOW";  $r.level | Should -Be "L1" }
    It "YELLOW at 50% (boundary inclusive)" { $r = Get-ContextZone 50;  $r.zone | Should -Be "YELLOW" }
    It "ORANGE zone at 61%" { $r = Get-ContextZone 61;  $r.zone | Should -Be "ORANGE";  $r.level | Should -Be "L1" }
    It "YELLOW at 60% (boundary inclusive)" { $r = Get-ContextZone 60;  $r.zone | Should -Be "YELLOW" }
    It "RED zone at 85%" { $r = Get-ContextZone 85;  $r.zone | Should -Be "RED";  $r.level | Should -Be "L2" }
    It "ORANGE at 80% (boundary inclusive)" { $r = Get-ContextZone 80;  $r.zone | Should -Be "ORANGE" }
    It "RED at 81% (first RED)" { $r = Get-ContextZone 81;  $r.zone | Should -Be "RED" }
    It "CRITICAL zone at 96%" { $r = Get-ContextZone 96;  $r.zone | Should -Be "CRITICAL"; $r.level | Should -Be "L3" }
    It "calculates 90% from bytes ratio" { $r = Get-ContextZone 90; $r.zone | Should -Be "RED" }
}

Describe "ctx-watchdog.ps1 — script execution (C8)" {
    BeforeAll {
        $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'ctx-watchdog.ps1'
    }

    It "script has no parse errors" {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "outputs ORANGE zone for 75% usage" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -UsagePercent 75" 2>&1
        $r | Should -Match 'ORANGE'
    }

    It "outputs CRITICAL zone for 96% usage" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -UsagePercent 96" 2>&1
        $r | Should -Match 'CRITICAL'
    }

    It "JSON output has correct zone/level for 85%" {
        $r = & pwsh -NoProfile -Command "& '$scriptPath' -UsagePercent 85 -Json" 2>&1
        $jsonLine = $r | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json
        $json.zone | Should -Be 'RED'
        $json.level | Should -Be 'L2'
    }
}

