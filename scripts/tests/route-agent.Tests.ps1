#requires -Version 7
<#
.SYNOPSIS
    Tests for C5: route-agent.ps1 — mode-aware agent suffix routing.

    Run: Invoke-Pester .\scripts\tests\route-agent.Tests.ps1
#>

BeforeAll {
    $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'route-agent.ps1'
}

Describe "route-agent.ps1 — mode-aware suffix routing (C5)" {
    It "auto mode appends -auto to mode-aware agents" {
        $r = & "pwsh" -NoProfile -Command "& '$scriptPath' -BaseAgent gentleman-quick -Mode auto -Json"
        $json = $r | ConvertFrom-Json
        $json.targetAgent | Should -Be "gentleman-quick-auto"
        $json.suffix      | Should -Be "-auto"
        $json.mode        | Should -Be "auto"
    }

    It "semi mode appends -semi to mode-aware agents" {
        $r = & "pwsh" -NoProfile -Command "& '$scriptPath' -BaseAgent gentleman-deep -Mode semi -Json"
        $json = $r | ConvertFrom-Json
        $json.targetAgent | Should -Be "gentleman-deep-semi"
        $json.suffix      | Should -Be "-semi"
    }

    It "manual mode returns no suffix" {
        $r = & "pwsh" -NoProfile -Command "& '$scriptPath' -BaseAgent gentleman-vMK -Mode manual -Json"
        $json = $r | ConvertFrom-Json
        $json.targetAgent | Should -Be "gentleman-vMK"
        $json.suffix      | Should -Be ""
    }

    It "read-only specialist gets no suffix even in auto mode" {
        $r = & "pwsh" -NoProfile -Command "& '$scriptPath' -BaseAgent gentleman-security-sub -Mode auto -Json"
        $json = $r | ConvertFrom-Json
        $json.targetAgent | Should -Be "gentleman-security-sub"
        $json.suffix      | Should -Be ""
    }

    It "sdd phase agent gets no suffix regardless of mode" {
        $r = & "pwsh" -NoProfile -Command "& '$scriptPath' -BaseAgent sdd-apply -Mode auto -Json"
        $json = $r | ConvertFrom-Json
        $json.targetAgent | Should -Be "sdd-apply"
        $json.suffix      | Should -Be ""
    }

    It "all 5 mode-aware core agents route correctly in auto" {
        $cores = @('gentleman-vMK', 'gentleman-deep', 'gentleman-quick', 'gentleman-codex', 'gentleman-implementer')
        foreach ($c in $cores) {
            $r = & "pwsh" -NoProfile -Command "& '$scriptPath' -BaseAgent $c -Mode auto -Json"
            $json = $r | ConvertFrom-Json
            $json.targetAgent | Should -Be "$c-auto"
        }
    }

    It "all 8 read-only specialists get no suffix in auto mode" {
        $specialists = @('gentleman-security-sub', 'gentleman-seo-sub', 'gentleman-infra-sub',
            'gentleman-frontend-sub', 'gentleman-performance-sub',
            'gentleman-datascience-sub', 'gentleman-docs-sub', 'gentleman-reviewer')
        foreach ($s in $specialists) {
            $r = & "pwsh" -NoProfile -Command "& '$scriptPath' -BaseAgent $s -Mode auto -Json"
            $json = $r | ConvertFrom-Json
            $json.targetAgent | Should -Be $s
            $json.suffix      | Should -Be ""
        }
    }
}

