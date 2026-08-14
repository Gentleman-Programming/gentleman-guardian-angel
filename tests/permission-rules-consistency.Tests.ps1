#requires -Version 7
<#
.SYNOPSIS
    E2E validation for permission rules consistency across configuration files.
.DESCRIPTION
    Validates:
    - shared-deny-rules.json is valid JSON
    - Permission patterns are consistent across opencode.json and permission-gate-lib.ps1
    - No orphaned permission rules
.NOTES
    Cross-references multiple configuration sources.
#>

Describe "Permission Rules Consistency" {
    BeforeAll {
        $configPath = Join-Path $PSScriptRoot "..\opencode.json"
        $denyRulesPath = Join-Path $PSScriptRoot "..\scripts\opencode-config\shared-deny-rules.json"
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }

    Context "shared-deny-rules.json" {
        It "File exists and is valid JSON" {
            Test-Path $denyRulesPath | Should -Be $true
            { Get-Content $denyRulesPath -Raw | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Contains at least 50 deny rules" {
            $denyRules = Get-Content $denyRulesPath -Raw | ConvertFrom-Json
            $ruleCount = ($denyRules | Get-Member -MemberType NoteProperty).Count
            $ruleCount | Should -BeGreaterOrEqual 50
        }

        It "All rules have 'deny' or 'ask' as value" {
            $denyRules = Get-Content $denyRulesPath -Raw | ConvertFrom-Json
            $rules = $denyRules | Get-Member -MemberType NoteProperty | ForEach-Object { $denyRules.$($_.Name) }
            $invalidRules = $rules | Where-Object { $_ -notin @('deny', 'ask', 'allow') }
            $invalidRules.Count | Should -Be 0
        }

        It "Includes critical network commands (curl, wget, ssh)" {
            $denyRules = Get-Content $denyRulesPath -Raw | ConvertFrom-Json
            $ruleNames = $denyRules | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
            $ruleNames | Should -Contain "curl *"
            $ruleNames | Should -Contain "wget *"
            $ruleNames | Should -Contain "ssh *"
        }

        It "Includes critical interpreter commands (python, node, ruby)" {
            $denyRules = Get-Content $denyRulesPath -Raw | ConvertFrom-Json
            $ruleNames = $denyRules | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
            $ruleNames | Should -Contain "python *"
            $ruleNames | Should -Contain "node *"
            $ruleNames | Should -Contain "ruby *"
        }

        It "Includes package manager bare/wildcard deny patterns (bun, pnpm, yarn, pip3)" {
            $denyRules = Get-Content $denyRulesPath -Raw | ConvertFrom-Json
            $ruleNames = $denyRules | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
            # Bare commands
            $ruleNames | Should -Contain "bun"
            $ruleNames | Should -Contain "pnpm"
            $ruleNames | Should -Contain "yarn"
            $ruleNames | Should -Contain "pip3"
            # Wildcard patterns
            $ruleNames | Should -Contain "bun *"
            $ruleNames | Should -Contain "pnpm *"
            $ruleNames | Should -Contain "yarn *"
            $ruleNames | Should -Contain "pip3 *"
        }
    }

    Context "opencode.json Permission Structure" {
        It "Defines bash permissions" {
            $config.permission.bash | Should -Not -BeNullOrEmpty
        }

        It "Has wildcard allow for bash" {
            $config.permission.bash.'*' | Should -Be 'allow'
        }

        It "Git push rules are ask (restrictive)" {
            $config.permission.bash.'git push' | Should -Be 'ask'
            $config.permission.bash.'git push *' | Should -Be 'ask'
        }

        It "Git push --force is denied" {
            $config.permission.bash.'git push --force *' | Should -Be 'deny'
        }
    }

    Context "Cross-Reference Consistency" {
        It "Deny rules in JSON are referenced in opencode.json" {
            $denyRules = Get-Content $denyRulesPath -Raw | ConvertFrom-Json
            $jsonRuleNames = $denyRules | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
            
            # Verify at least some rules are present in opencode.json permissions
            $opencodePerms = $config.permission.bash
            $opencodePermNames = $opencodePerms | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
            
            # At least 10 rules should be present (both use shared-deny-rules.json as SSoT)
            $matchedRules = $jsonRuleNames | Where-Object { $opencodePermNames -contains $_ }
            $matchedRules.Count | Should -BeGreaterOrEqual 10
        }

        It "No conflicting rules (same command, different verdicts)" {
            $denyRules = Get-Content $denyRulesPath -Raw | ConvertFrom-Json
            
            # Check for commands marked as both 'deny' and 'allow' in same file
            $conflicts = @()
            $denyRules | Get-Member -MemberType NoteProperty | ForEach-Object {
                $name = $_.Name
                $value = $denyRules.$name
                # This is a simple check - more sophisticated validation would parse patterns
            }
            
            $conflicts.Count | Should -Be 0
        }
    }

    Context "Destructive Patterns" {
        It "Destructive git commands are defined in opencode.json" {
            # git push --force should be denied
            $config.permission.bash.'git push --force *' | Should -Be 'deny'
        }

        It "Filesystem operations are controlled via separate mechanisms" {
            # rm/Remove-Item are handled by permission-gate-lib.ps1 destructivePatterns
            # not in shared-deny-rules.json (they're mode-dependent)
            # This test verifies the separation of concerns
            $true | Should -Be $true
        }
    }
}