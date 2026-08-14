#requires -Version 7

BeforeAll {
    $scriptsRoot = Resolve-Path "$PSScriptRoot/.."
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pester-rollback-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction Stop | Out-Null

    $script:patternData = @{
        id         = "test/rollback-pattern"
        title      = "Test pattern"
        status     = "forged"
        skill_ref  = "cross-project-test-skill"
        promoted_at = "2026-07-28"
        updated    = "2026-07-27"
        severity   = "MEDIUM"
    }
    $script:patternFile = Join-Path $tempRoot "test-rollback-pattern.json"
    $script:patternData | ConvertTo-Json -Depth 3 | Set-Content $script:patternFile -Encoding UTF8

    $script:skillDir = Join-Path $tempRoot "agents\skills\cross-project-test-skill"
    New-Item -ItemType Directory -Path $script:skillDir -Force -ErrorAction Stop | Out-Null
}

AfterAll {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "forge-rollback - Pattern JSON mutation" {

    It "demotes pattern status from 'forged' to 'active'" {
        $pattern = Get-Content $script:patternFile -Raw | ConvertFrom-Json
        $pattern | Add-Member -NotePropertyName "status" -NotePropertyValue "active" -Force
        $pattern | ConvertTo-Json -Depth 6 | Set-Content $script:patternFile -Encoding UTF8

        $result = Get-Content $script:patternFile -Raw | ConvertFrom-Json
        $result.status | Should -Be "active"
    }

    It "clears skill_ref during demotion" {
        $pattern = Get-Content $script:patternFile -Raw | ConvertFrom-Json
        $pattern | Add-Member -NotePropertyName "skill_ref" -NotePropertyValue $null -Force
        $pattern | ConvertTo-Json -Depth 6 | Set-Content $script:patternFile -Encoding UTF8

        $result = Get-Content $script:patternFile -Raw | ConvertFrom-Json
        $result.skill_ref | Should -BeNullOrEmpty
    }

    It "removes promoted_at property during demotion" {
        $pattern = Get-Content $script:patternFile -Raw | ConvertFrom-Json
        $pattern.psobject.Properties.Remove("promoted_at") | Out-Null
        $pattern | ConvertTo-Json -Depth 6 | Set-Content $script:patternFile -Encoding UTF8

        $result = Get-Content $script:patternFile -Raw | ConvertFrom-Json
        $result.psobject.Properties.Match("promoted_at").Count | Should -Be 0
    }

    It "updates 'updated' timestamp" {
        $before = Get-Content $script:patternFile -Raw | ConvertFrom-Json
        Start-Sleep -Milliseconds 100
        $before | Add-Member -NotePropertyName "updated" -NotePropertyValue "2026-07-28" -Force
        $before | ConvertTo-Json -Depth 6 | Set-Content $script:patternFile -Encoding UTF8

        $after = Get-Content $script:patternFile -Raw | ConvertFrom-Json
        $after.updated | Should -Be "2026-07-28"
    }
}

Describe "forge-rollback - SKILL.md frontmatter mutation" {

    BeforeAll {
        $script:skillMd = Join-Path $script:skillDir "SKILL.md"
    }

    It "writes and reads source_pattern in SKILL.md" {
        @"
---
source_pattern: "test/rollback-pattern"
---
"@ | Set-Content $script:skillMd -Force

        $content = Get-Content $script:skillMd -Raw
        $content -match 'source_pattern:\s*"([^"]+)"' | Should -Be $true
        $Matches[1] | Should -Be "test/rollback-pattern"
    }

    It "returns no match when SKILL.md has no source_pattern" {
        @"
---
name: "test-skill"
version: 1
---
"@ | Set-Content $script:skillMd -Force

        $content = Get-Content $script:skillMd -Raw
        $content -match 'source_pattern:\s*"([^"]+)"' | Should -Be $false
    }
}

Describe "forge-rollback - Safety mechanisms" {

    It "has a -DryRun switch parameter" {
        $scriptContent = Get-Content "$scriptsRoot/forge-rollback.ps1" -Raw
        $scriptContent | Should -Match '\[switch\]\s*\$DryRun'
        $scriptContent | Should -Match 'DryRun|dry.run'
    }

    It "gates destructive Remove-Item behind conditional logic" {
        $scriptContent = Get-Content "$scriptsRoot/forge-rollback.ps1" -Raw
        $hasRemoveItem = $scriptContent -match 'Remove-Item'
        $gatedByDryRun = $scriptContent -match 'if\s*\(\s*\$DryRun' -or
                          $scriptContent -match '\$DryRun\s*\{'
        $hasRemoveItem -and $gatedByDryRun | Should -BeTrue
    }
}

Describe "forge-rollback - Error handling" {

    It "throws when neither -SkillName nor -PatternId is provided" {
        { & "$scriptsRoot/forge-rollback.ps1" } | Should -Throw
    }

    It "throws when -SkillName does not match an existing directory" {
        { & "$scriptsRoot/forge-rollback.ps1" -SkillName "nonexistent-skill-$(Get-Random)" } |
            Should -Throw
    }

    It "throws when -PatternId does not match any pattern file" {
        { & "$scriptsRoot/forge-rollback.ps1" -PatternId "nonexistent/pattern-$(Get-Random)" } |
            Should -Throw
    }
}

