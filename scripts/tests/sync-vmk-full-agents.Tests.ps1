#requires -Version 7
<#
.SYNOPSIS
    Pester tests for sync-vmk.ps1 — G3 full agent sync.
    Verifies Sync-Config propagates the COMPLETE canonical agent section:
    gentleman-*, sdd-* AND gentle-orchestrator (full replace, no merge).
.NOTES
    ADR-029 — sync-vmk full agent sync (G3).
    Pattern mirrors sync-vmk.Tests.ps1: PESTER_TEST=1 + dot-source + temp targets.
    Canonical agent set (2026-08-13): 50 = 39 gentleman + 10 sdd + 1 gentle-orchestrator.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    $script:oldPesterTest = $env:PESTER_TEST
    $env:PESTER_TEST = '1'

    # Dot-source the script — sets up $canonical, $results, Sync-Config, Get-DeepClone
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'sync-vmk.ps1')

    $script:canonicalAgentCount = @($canonical.agent.PSObject.Properties.Name).Count
    $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pester-syncvmk-fullagents-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
}

AfterAll {
    if ($null -eq $script:oldPesterTest) {
        Remove-Item Env:PESTER_TEST -ErrorAction SilentlyContinue
    } else {
        $env:PESTER_TEST = $script:oldPesterTest
    }
    if (Test-Path $script:tempRoot) {
        Remove-Item -Path $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Sync-Config full agent sync (G3 — ADR-029)' {
    BeforeAll {
        # Helper: build a target config whose agent section contains ONLY gentleman-* agents
        # (drops sdd-* and gentle-orchestrator) — simulates the pre-G3 global config (39 agents).
        function New-PartialTarget {
            param([string]$Path, [switch]$AddLegacy)
            $partial = Get-DeepClone $canonical
            @($partial.agent.PSObject.Properties.Name) | Where-Object {
                $_ -notlike 'gentleman*'
            } | ForEach-Object {
                $partial.agent.PSObject.Properties.Remove($_)
            }
            if ($AddLegacy) {
                # A stale agent that exists in the target but NOT in canonical
                $partial.agent | Add-Member -NotePropertyName 'legacy-stale-agent' -NotePropertyValue @{
                    mode = 'primary'
                    description = 'stale agent — should be removed by full replace'
                }
            }
            $partial | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
        }

        $script:syncedTarget = Join-Path $script:tempRoot "synced.json"
        New-PartialTarget -Path $script:syncedTarget
        Sync-Config -TargetPath $script:syncedTarget -Label "full-agents" -PreserveMCP $false

        $script:syncedConfig = Get-Content -LiteralPath $script:syncedTarget -Raw | ConvertFrom-Json
        $script:syncedNames = @($script:syncedConfig.agent.PSObject.Properties.Name)
    }

    It 'syncs gentle-orchestrator (not just gentleman-*)' {
        $script:syncedNames | Should -Contain 'gentle-orchestrator'
        # And its definition is a real agent object, not empty
        $script:syncedConfig.agent.'gentle-orchestrator' | Should -Not -Be $null
    }

    It 'syncs all 10 sdd-* agents' {
        $sddAgents = @($script:syncedNames | Where-Object { $_ -like 'sdd*' })
        $sddAgents.Count | Should -Be 10
        $sddAgents | Should -Contain 'sdd-orchestrator'
        $sddAgents | Should -Contain 'sdd-propose'
    }

    It 'uses full replace ($target.agent = $canonical.agent), preserving agent count and removing stale agents' {
        # A stale agent (present in target, absent in canonical) must be REMOVED — merge would keep it
        $legacyTarget = Join-Path $script:tempRoot "legacy.json"
        New-PartialTarget -Path $legacyTarget -AddLegacy
        Sync-Config -TargetPath $legacyTarget -Label "legacy" -PreserveMCP $false

        $legacyConfig = Get-Content -LiteralPath $legacyTarget -Raw | ConvertFrom-Json
        $legacyNames = @($legacyConfig.agent.PSObject.Properties.Name)

        # Full replace: stale agent gone, count equals canonical count exactly
        $legacyNames | Should -Not -Contain 'legacy-stale-agent'
        $legacyNames.Count | Should -Be $script:canonicalAgentCount
    }
}
