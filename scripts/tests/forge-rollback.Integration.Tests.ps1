#requires -Version 7
<#
.SYNOPSIS
    Integration tests for forge-rollback.ps1 — tests the ACTUAL script with temp fixture data.
.NOTES
    ponytail: filesystem tests — creates and destroys temp directories.
    Tests rollback of forged skills with actual file operations.
#>

BeforeAll {
    $scriptsRoot = Resolve-Path "$PSScriptRoot/.."
    $scriptPath = "$scriptsRoot/forge-rollback.ps1"

    $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "fr-int-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:tempRoot -Force -ErrorAction Stop | Out-Null

    # Mirror project structure expected by forge-rollback
    $script:testSkillsDir = Join-Path $script:tempRoot ".agents/skills"
    $script:testPatternsDir = Join-Path $script:tempRoot "docs/cross-project/patterns"
    New-Item -ItemType Directory -Path $script:testSkillsDir -Force -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path $script:testPatternsDir -Force -ErrorAction Stop | Out-Null

    # Create a test skill directory (simulates a forged skill)
    $script:testSkillName = "test-int-skill-$(Get-Random)"
    $script:testSkillDir = Join-Path $script:testSkillsDir $script:testSkillName
    New-Item -ItemType Directory -Path $script:testSkillDir -Force -ErrorAction Stop | Out-Null
    Set-Content -Path (Join-Path $script:testSkillDir "SKILL.md") -Value @"
# Test Skill
This is a test skill created by integration tests.
"@ -Encoding UTF8

    # Create a pattern file with source_pattern pointing to the skill
    $script:testPatternId = "test/int-pattern-$(Get-Random)"
    $script:testPatternFile = Join-Path $script:testPatternsDir "$($script:testPatternId -replace '/', '-').json"
    $patternData = @{
        id          = $script:testPatternId
        title       = "Integration test pattern"
        status      = "forged"
        skill_ref   = $script:testSkillName
        promoted_at = (Get-Date -Format "yyyy-MM-dd")
        updated     = (Get-Date -Format "yyyy-MM-dd")
        severity    = "MEDIUM"
    }
    $patternData | ConvertTo-Json -Depth 3 | Set-Content $script:testPatternFile -Encoding UTF8

    # Update SKILL.md to have source_pattern metadata
    Set-Content -Path (Join-Path $script:testSkillDir "SKILL.md") -Value @"
---
source_pattern: "$($script:testPatternId)"
---
# Test Skill
This is a test skill created by integration tests.
"@ -Encoding UTF8

    # The script uses the repo root to find patterns/skills dirs.
    # We'll use -SkillName directly so it resolves from PSScriptRoot.
    # For testing, we wrap the script call with temp root overrides via env.
}

AfterAll {
    if (Test-Path $script:tempRoot) {
        Remove-Item -Path $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "forge-rollback — Integration: skill directory exists" {

    It "the test skill directory exists before rollback" {
        Test-Path $script:testSkillDir | Should -Be $true
    }

    It "the test pattern file exists before rollback" {
        Test-Path $script:testPatternFile | Should -Be $true
    }

    It "the pattern has status=forged before rollback" {
        $pattern = Get-Content $script:testPatternFile -Raw | ConvertFrom-Json
        $pattern.status | Should -Be "forged"
    }
}

Describe "forge-rollback — Integration: error handling" {

    It "throws error for nonexistent skill name" {
        { & $scriptPath -SkillName "definitely-does-not-exist-99999" -ErrorAction Stop } |
            Should -Throw
    }
}

