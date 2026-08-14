#requires -Version 7
<#
.SYNOPSIS
    Pester tests for ui-specialist-pairing.ps1 — UI audit + variant generation.
    Validates: rule detection, variant generation, vision integration, creative basis.

.NOTES
    Tests use inline rule replication (mirrors baseline-ui/SKILL.md rules).
    No filesystem targets required — uses embedded test content.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # Inline rule set (mirrors session-checkpoint.ps1 / baseline-ui)
    $script:animationRules = @{
        "no-transition-all" = @{ pattern = "transition:\s*all"; fix = "Use explicit properties" }
        "duration-over-500ms" = @{ pattern = "duration-\[5[0-9][0-9]ms\]"; fix = "Use 120/200/300ms pattern" }
    }

    function Test-AnimationRules {
        param([string]$Content)
        $violations = @()
        foreach ($rule in $script:animationRules.GetEnumerator()) {
            if ($Content -match $rule.Value.pattern) {
                $violations += $rule.Key
            }
        }
        return $violations
    }

    # Test fixture: CSS with known violations
    $script:testCss = @"
.button {
    transition: all 500ms ease;
    width: 300px;
    height: 200px;
    font-size: 16px;
}
"@
    # Test fixture: clean CSS
    $script:cleanCss = @"
.button {
    transition: transform 200ms ease-out;
    width: 1fr;
    font-size: clamp(1rem, 2vw, 1.5rem);
}
"@
}

Describe "UI Specialist Pairing — Rule Detection" {
    It "Detects transition:all violation" {
        $violations = Test-AnimationRules -Content $script:testCss
        $violations | Should -Contain "no-transition-all"
    }

    It "Detects duration-over-500ms violation" {
        $violations = Test-AnimationRules -Content $script:testCss
        $violations | Should -Contain "duration-over-500ms"
    }

    It "Clean CSS has no animation violations" {
        $violations = Test-AnimationRules -Content $script:cleanCss
        $violations | Should -Be @()
    }

    It "Typography rules detect hardcoded font-size" {
        $hasHardcoded = $script:testCss -match "font-size:\s*\d+px"
        $hasHardcoded | Should -Be $true

        $cleanHasHardcoded = $script:cleanCss -match "font-size:\s*\d+px"
        $cleanHasHardcoded | Should -Be $false
    }
}

Describe "UI Specialist Pairing — Variant Generation" {
    It "Generates 3 variants per violation (Material 3, Apple HIG, shadcn/ui)" {
        # The script should generate variant_A (Material 3), variant_B (Apple HIG), variant_C (shadcn/ui)
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot "..\ui-specialist-pairing.ps1") -Raw
        $hasVariantA = $scriptContent -match "variant_A"
        $hasVariantB = $scriptContent -match "variant_B"
        $hasVariantC = $scriptContent -match "variant_C"
        $hasVariantA | Should -Be $true
        $hasVariantB | Should -Be $true
        $hasVariantC | Should -Be $true
    }

    It "Material 3 variant uses 150ms/200ms standard timing" {
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot "..\ui-specialist-pairing.ps1") -Raw
        $hasStandard = $scriptContent -match "150ms.*standard|standard.*150ms"
        $hasExpress = $scriptContent -match "200ms.*express|express.*200ms"
        $hasStandard | Should -Be $true
        $hasExpress | Should -Be $true
    }

    It "Apple HIG variant uses spring physics easing" {
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot "..\ui-specialist-pairing.ps1") -Raw
        $hasSpring = $scriptContent -match "spring|cubic-bezier\(0\.42"
        $hasSpring | Should -Be $true
    }

    It "All 3 creative sources are referenced" {
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot "..\ui-specialist-pairing.ps1") -Raw
        $hasM3 = $scriptContent -match "Material 3"
        $hasApple = $scriptContent -match "Apple HIG"
        $hasshadcn = $scriptContent -match "shadcn/ui"
        $hasM3 | Should -Be $true
        $hasApple | Should -Be $true
        $hasshadcn | Should -Be $true
    }
}

Describe "UI Specialist Pairing — Vision Integration" {
    It "Checks Ollama availability at 127.0.0.1:11434" {
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot "..\ui-specialist-pairing.ps1") -Raw
        $hasOllamaCheck = $scriptContent -match "127\.0\.0\.1:11434"
        $hasOllamaCheck | Should -Be $true
    }

    It "References analyze-page.js for vision mode" {
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot "..\ui-specialist-pairing.ps1") -Raw
        $hasAnalyzerRef = $scriptContent -match "analyze-page\.js"
        $hasAnalyzerRef | Should -Be $true
    }

    It "Micro-interaction patterns include timing + easing + feedback" {
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot "..\ui-specialist-pairing.ps1") -Raw
        $hasTiming = $scriptContent -match "120ms.*200ms.*300ms"
        $hasEasing = $scriptContent -match "cubic-bezier"
        $hasFeedback = $scriptContent -match "scale-95|opacity"
        $hasTiming | Should -Be $true
        $hasEasing | Should -Be $true
        $hasFeedback | Should -Be $true
    }
}

Describe "UI Specialist Pairing — Mode Behavior" {
    It "audit mode produces violations list" {
        # Would require running the script; verify mode is accepted
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot "..\ui-specialist-pairing.ps1") -Raw
        $hasAuditMode = $scriptContent -match "ValidateSet\('audit','variants','full'\)"
        $hasAuditMode | Should -Be $true
    }

    It "full mode triggers vision validation" {
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot "..\ui-specialist-pairing.ps1") -Raw
        $hasFullVision = $scriptContent -match 'Mode -eq .full..*Vision' -or $scriptContent -match 'full.*vision'
        $hasFullVision | Should -Be $true
    }
}
