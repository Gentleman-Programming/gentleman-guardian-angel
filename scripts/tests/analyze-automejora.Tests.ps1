#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Quiet)

Set-StrictMode -Version Latest

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'analyze-automejora.ps1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

    function Get-JsonResult {
        param([string]$Root)
        $out = & $script:ScriptPath -Path $Root -Json
        return (($out -join "`n") | ConvertFrom-Json)
    }
}

Describe 'Tier detection' {
    It 'T1: tiny fixture (1-2 files, 1 lang, no tests) -> Tier T1' {
        $fixture = Join-Path $TestDrive 'tiny-project'
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixture 'main.py') -Value 'print(1)' -Encoding UTF8
        $json = Get-JsonResult -Root $fixture
        $json.tier | Should -Be 'T1'
        $json.tierLevel | Should -Be 1
        $json.fileCount | Should -Be 1
        $json.languages | Should -Contain 'Python'
        $json.tests.present | Should -BeFalse
    }

    It 'T2/T3: this repo (100+ files, PS+JS, tests present, CI) -> Tier T2 or T3' {
        $json = Get-JsonResult -Root $script:RepoRoot
        $json.tier | Should -BeIn @('T2', 'T3')
        $json.fileCount | Should -BeGreaterThan 100
        $json.languages | Should -Contain 'PowerShell'
        $json.tests.present | Should -BeTrue
        $json.ci.present | Should -BeTrue
    }
}

Describe 'Capability probe' {
    It 'Detects PS + Pester on this repo -> testRunner present' {
        $json = Get-JsonResult -Root $script:RepoRoot
        $json.capabilities.testRunner.available | Should -BeTrue
        @($json.capabilities.testRunner.tools) | Should -Contain 'Pester'
    }

    It 'JSON output preserves single-element arrays (ADR-003, plan G1)' {
        $out = & $script:ScriptPath -Path $script:RepoRoot -Json
        $raw = ($out -join "`n")
        $json = $raw | ConvertFrom-Json
        $tools = @($json.capabilities.testRunner.tools)
        if ($tools.Count -eq 1) {
            # raw JSON must serialize the single tool as an array, not a bare string
            $raw | Should -Match '"tools"\s*:\s*\[' 
            $raw | Should -Not -Match '"tools"\s*:\s*"'
        }
        $tools.Count | Should -BeGreaterThan 0
    }
}

Describe 'PCI JSON schema' {
    It 'Has required keys: projectName, tier, fileCount, capabilities' {
        $fixture = Join-Path $TestDrive 'schema-project'
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixture 'app.js') -Value 'console.log(1)' -Encoding UTF8
        $json = Get-JsonResult -Root $fixture
        foreach ($key in @('projectName', 'tier', 'fileCount', 'capabilities')) {
            $json.PSObject.Properties.Name | Should -Contain $key
        }
    }
}