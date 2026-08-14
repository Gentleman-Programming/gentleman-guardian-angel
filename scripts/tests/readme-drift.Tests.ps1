#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Pester 6 tests for README.md count drift prevention.
.DESCRIPTION
  Ensures key stats in README.md stay in sync with the actual repository state.
.NOTES
  Run: pwsh -File scripts/tests/readme-drift.Tests.ps1
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    $RepoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
    $ReadmeContent = Get-Content (Join-Path $RepoRoot 'README.md') -Raw
}

Describe 'README.md count drift' -Tag 'docs', 'drift' {

    Context 'Agent count' {
        It 'README agent count matches opencode.json' {
            $configPath = Join-Path $RepoRoot 'opencode.json'
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            $actualAgentCount = $config.agent.PSObject.Properties.Count

            $match = [regex]::Match($ReadmeContent, '(\d+)\s+specialized agents')
            $readmeAgentCount = [int]$match.Groups[1].Value

            $readmeAgentCount | Should -Be $actualAgentCount
        }
    }

    Context 'Skill count' {
        It 'README skill count matches filesystem' {
            $actualSkillCount = (Get-ChildItem (Join-Path $RepoRoot '.agents\skills') -Recurse -Filter 'SKILL.md' |
                Where-Object { $_.Directory.Name -ne '_shared' } |
                Measure-Object).Count

            $match = [regex]::Match($ReadmeContent, '\*\*Skills\*\*:\s+(\d+)')
            $readmeSkillCount = [int]$match.Groups[1].Value

            $readmeSkillCount | Should -Be $actualSkillCount
        }
    }

    Context 'Script count' {
        It 'README script count matches filesystem' {
            $scriptsDir = Join-Path $RepoRoot 'scripts'
            $actualPsCount = (Get-ChildItem $scriptsDir -Filter '*.ps1' |
                Where-Object { $_.Directory.Name -eq 'scripts' } |
                Measure-Object).Count
            $actualShCount = (Get-ChildItem $scriptsDir -Filter '*.sh' |
                Where-Object { $_.Directory.Name -eq 'scripts' } |
                Measure-Object).Count
            $actualTotal = $actualPsCount + $actualShCount

            $match = [regex]::Match($ReadmeContent, '(\d+)\s+top-level scripts\s*\((\d+)\s+PowerShell\s+\+\s+(\d+)\s+shell\)')
            $readmeTotal = [int]$match.Groups[1].Value
            $readmePs = [int]$match.Groups[2].Value
            $readmeSh = [int]$match.Groups[3].Value

            $readmeTotal | Should -Be $actualTotal
            $readmePs | Should -Be $actualPsCount
            $readmeSh | Should -Be $actualShCount
        }
    }

    Context 'Score' {
        It 'README score dimension count matches .project.json' {
            $projectPath = Join-Path $RepoRoot '.project.json'
            $project = Get-Content $projectPath -Raw | ConvertFrom-Json
            $dimCount = ($project.dimensions_detail.PSObject.Properties | Measure-Object).Count

            $match = [regex]::Match($ReadmeContent, 'Score.*\d+\.\d+/10\s*\((\d+)\s+dimensions\)')
            $readmeScoreDim = [int]$match.Groups[1].Value

            $readmeScoreDim | Should -Be $dimCount
        }
    }
}
