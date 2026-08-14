#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Pester tests for ConfigValidator.psm1 (Cycle 3 — G2 CI quality gate).
    Enfoque A (Minimal): Test-SkillsPaths / Test-PromptRefs / Test-AgentDefinitions
    / Test-OpencodeConfig.
.NOTES
    Real opencode.json is the positive control; synthetic configs exercise
    each failure mode. ADR-028 (G1 array unwrapping) + ADR-029 (G3 50 agents)
    are the failure modes these tests guard against.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib' 'ConfigValidator.psm1') -Force
    # opencode.json lives at repo ROOT: scripts/tests/ -> scripts/ -> repo root
    $script:repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:realConfigPath = Join-Path $script:repoRoot 'opencode.json'
    $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pester-configvalidator-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:tempRoot) {
        Remove-Item -Path $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'ConfigValidator' {
    Context 'Test-OpencodeConfig (entry point)' {
        It 'returns 0 for the real opencode.json (pass)' {
            $code = Test-OpencodeConfig -Path $script:realConfigPath -Quiet
            $code | Should -Be 0
        }

        It 'returns 1 for a config with array-unwrapped skills.paths (G1 regression)' {
            $bad = [pscustomobject]@{
                agent  = [pscustomobject]@{ 'gentleman-vMK' = [pscustomobject]@{ mode = 'primary'; prompt = 'x' } }
                skills = [pscustomobject]@{ paths = '.agents/skills' }  # string, not array
            }
            $path = Join-Path $script:tempRoot 'unwrapped.json'
            $bad | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
            $code = Test-OpencodeConfig -Path $path -Quiet
            $code | Should -Be 1
        }
    }

    Context 'Test-SkillsPaths' {
        It 'fails when skills.paths is a string (single-element array unwrapping)' {
            $config = [pscustomobject]@{ skills = [pscustomobject]@{ paths = '.agents/skills' } }
            $result = Test-SkillsPaths -Config $config
            $result | Should -Not -BeNullOrEmpty
            @($result)[0] | Should -Match 'STRING'
        }

        It 'passes when skills.paths is an array' {
            $config = [pscustomobject]@{ skills = [pscustomobject]@{ paths = @('.agents/skills') } }
            $result = Test-SkillsPaths -Config $config
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Test-PromptRefs' {
        It 'fails when a {file:...} prompt ref does not resolve' {
            $config = [pscustomobject]@{
                agent = [pscustomobject]@{
                    'gentleman-vMK' = [pscustomobject]@{ prompt = '{file:prompts/does-not-exist.md}' }
                }
            }
            $result = Test-PromptRefs -Config $config -ConfigPath $script:realConfigPath
            $result | Should -Not -BeNullOrEmpty
            @($result)[0] | Should -Match 'not found'
        }

        It 'passes when all {file:...} refs resolve (real opencode.json)' {
            $config = Get-Content -LiteralPath $script:realConfigPath -Raw | ConvertFrom-Json
            $result = Test-PromptRefs -Config $config -ConfigPath $script:realConfigPath
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Test-AgentDefinitions' {
        It 'fails when gentle-orchestrator is missing (G3 regression)' {
            $config = [pscustomobject]@{
                agent = [pscustomobject]@{
                    'gentleman-vMK' = [pscustomobject]@{ mode = 'primary' }
                    'sdd-propose'   = [pscustomobject]@{ mode = 'primary' }
                }
            }
            $result = Test-AgentDefinitions -Config $config
            $result | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_ -match 'gentle-orchestrator' } | Should -Not -BeNullOrEmpty
        }

        It 'passes for the real 50-agent opencode.json' {
            $config = Get-Content -LiteralPath $script:realConfigPath -Raw | ConvertFrom-Json
            $result = Test-AgentDefinitions -Config $config
            $result | Should -BeNullOrEmpty
        }
    }
}