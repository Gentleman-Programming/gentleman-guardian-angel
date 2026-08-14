#requires -Version 7
<#
.SYNOPSIS
    Contract tests for scripts/lib/template-detection.ps1 — Detect-Template() function,
    $TemplateMap SSoT parity with generate-opencode-config.js, and fail-closed behavior.

    Dot-sources ONLY the template-detection module (no side effects from use-gentleman.ps1
    which executes full config generation on source).

.DESCRIPTION
    This is the PowerShell mirror of the R10 describe block in generate-config.Tests.ps1.
    Validates that:
      1. $TemplateMap has all agents from the chain (opencode-base.json)
      2. $TemplateMap matches TEMPLATE_MAP in generate-opencode-config.js (no drift)
      3. Detect-Template() produces correct results for explicit + auto-registered agents
      4. -sub-auto maps to auto-sub (not auto) — the drift bug
      5. Role keyword auto-registration works
      6. Fail-closed on truly unknown agents
#>
using namespace System.Management.Automation

BeforeAll {
    # Dot-source ONLY the template-detection module — no config generation side effects
    $script:modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'lib/template-detection.ps1'
    . $script:modulePath

    # Load the JS TEMPLATE_MAP for parity check
    $script:jsPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'lib/generate-opencode-config.js'
    $script:jsContent = Get-Content $script:jsPath -Raw
}

Describe 'Detect-Template — $TemplateMap parity with generate-opencode-config.js' {
    It 'every explicit $TemplateMap entry exists in JS TEMPLATE_MAP with same value' {
        # Extract JS TEMPLATE_MAP entries by matching 'agent-name': 'template' pattern
        $jsEntries = @{}
        foreach ($line in $jsContent -split "`n") {
            if ($line -match "^\s+'([^']+)':\s+'([^']+)',?\s*(//.*)?$") {
                $jsEntries[$matches[1]] = $matches[2]
            }
        }

        $drift = @()
        foreach ($kvp in $TemplateMap.GetEnumerator()) {
            $agent = $kvp.Key
            $psTemplate = $kvp.Value
            if (-not $jsEntries.ContainsKey($agent)) {
                $drift += "${agent}: in PS map but NOT in JS TEMPLATE_MAP"
            } elseif ($jsEntries[$agent] -ne $psTemplate) {
                $drift += "${agent}: PS=$psTemplate vs JS=$jsEntries[$agent]"
            }
        }
        $drift.Count | Should -Be 0
        if ($drift.Count -gt 0) { $drift | Write-Host }
    }

    It 'every JS TEMPLATE_MAP entry exists in $TemplateMap with same value' {
        $jsEntries = @{}
        foreach ($line in $jsContent -split "`n") {
            if ($line -match "^\s+'([^']+)':\s+'([^']+)',?\s*(//.*)?$") {
                $jsEntries[$matches[1]] = $matches[2]
            }
        }

        $drift = @()
        foreach ($kvp in $jsEntries.GetEnumerator()) {
            $agent = $kvp.Key
            $jsTemplate = $kvp.Value
            if (-not $TemplateMap.ContainsKey($agent)) {
                $drift += "${agent}: in JS TEMPLATE_MAP but NOT in PS $TemplateMap"
            } elseif ($TemplateMap[$agent] -ne $jsTemplate) {
                $drift += "${agent}: JS=$jsTemplate vs PS=$TemplateMap[$agent]"
            }
        }
        $drift.Count | Should -Be 0
        if ($drift.Count -gt 0) { $drift | Write-Host }
    }
}

Describe 'Detect-Template — explicit map entries' {
    It 'gentleman-vMK maps to orchestrator' {
        Detect-Template -AgentName 'gentleman-vMK' | Should -Be 'orchestrator'
    }

    It 'gentleman-codex-sub maps to readwrite (was missing from PS map — drift fix)' {
        Detect-Template -AgentName 'gentleman-codex-sub' | Should -Be 'readwrite'
    }

    It 'gentleman-reviewer-sub maps to reviewer (was missing from PS map — drift fix)' {
        Detect-Template -AgentName 'gentleman-reviewer-sub' | Should -Be 'reviewer'
    }

    It 'all 4 -sub-auto agents map to auto-sub (not auto — the drift bug)' {
        Detect-Template -AgentName 'gentleman-deep-sub-auto'       | Should -Be 'auto-sub'
        Detect-Template -AgentName 'gentleman-quick-sub-auto'      | Should -Be 'auto-sub'
        Detect-Template -AgentName 'gentleman-codex-sub-auto'      | Should -Be 'auto-sub'
        Detect-Template -AgentName 'gentleman-implementer-sub-auto'| Should -Be 'auto-sub'
    }

    It 'role-based agents map to correct templates' {
        Detect-Template -AgentName 'gentleman-security'      | Should -Be 'readonly'
        Detect-Template -AgentName 'gentleman-infra'         | Should -Be 'readonly'
        Detect-Template -AgentName 'gentleman-reviewer'      | Should -Be 'reviewer'
        Detect-Template -AgentName 'gentleman-deep'          | Should -Be 'readwrite'
    }
}

Describe 'Detect-Template — auto-registration (Gap A — naming conventions)' {
    It 'gentleman-security-sub-auto auto-detected via -sub-auto suffix (NOT in explicit map)' {
        # This agent follows naming conventions but is NOT in $TemplateMap
        $result = Detect-Template -AgentName 'gentleman-security-sub-auto'
        $result | Should -Be 'auto-sub'
    }

    It 'gentleman-foo-auto auto-detected via -auto suffix (NOT in explicit map)' {
        $result = Detect-Template -AgentName 'gentleman-foo-auto'
        $result | Should -Be 'auto'
    }

    It 'gentleman-foo-semi auto-detected via -semi suffix (NOT in explicit map)' {
        $result = Detect-Template -AgentName 'gentleman-foo-semi'
        $result | Should -Be 'semi'
    }

    It 'gentleman-security-analyst-sub recurses: -sub stripped → gentleman-security-analyst → keyword match' {
        $result = Detect-Template -AgentName 'gentleman-security-analyst-sub'
        $result | Should -Be 'readonly'
    }

    It 'gentleman-custom-sub recurses: -sub stripped → gentleman-custom → fail-closed (no keyword)' {
        { Detect-Template -AgentName 'gentleman-custom-sub' } | Should -Throw
    }
}

Describe 'Detect-Template — role keyword matching' {
    It 'infra keyword → readonly' {
        Detect-Template -AgentName 'gentleman-monitoring-infra' | Should -Be 'readonly'
    }

    It 'docs keyword → readonly' {
        Detect-Template -AgentName 'my-docs-agent' | Should -Be 'readonly'
    }

    It 'reviewer keyword → reviewer' {
        Detect-Template -AgentName 'gentleman-code-reviewer' | Should -Be 'reviewer'
    }

    It 'vMK keyword → orchestrator' {
        Detect-Template -AgentName 'gentleman-vMK-clone' | Should -Be 'orchestrator'
    }
}

Describe 'Detect-Template — fail-closed (Gap B — unknown agents)' {
    It 'gentleman-biz throws (no suffix, no role keyword, not in map)' {
        { Detect-Template -AgentName 'gentleman-biz' } | Should -Throw
    }

    It 'gentleman-foo throws (no suffix, no role keyword, not in map)' {
        { Detect-Template -AgentName 'gentleman-foo' } | Should -Throw
    }

    It 'throws with descriptive error message containing agent name' {
        try {
            Detect-Template -AgentName 'gentleman-unknown-xyz'
        } catch {
            $_.Exception.Message | Should -Match 'gentleman-unknown-xyz'
        }
    }
}

Describe 'Detect-Template — chain coverage' {
    It 'every agent in opencode-base.json resolves to a valid template' {
        $basePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'lib/opencode-base.json'
        $base = Get-Content $basePath -Raw | ConvertFrom-Json

        $unresolved = @()
        foreach ($name in $base.agent.PSObject.Properties.Name) {
            try {
                $result = Detect-Template -AgentName $name
                if (-not $result) { $unresolved += $name }
            } catch {
                $unresolved += $name
            }
        }
        $unresolved.Count | Should -Be 0
        if ($unresolved.Count -gt 0) { $unresolved | Write-Host }
    }
}

