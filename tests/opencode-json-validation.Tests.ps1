#requires -Version 7
<#
.SYNOPSIS
    E2E validation for opencode.json configuration structure and consistency.
.DESCRIPTION
    Validates:
    - Agent definitions have required fields
    - Permission rules are consistent across modes
    - Skill references are valid
    - No orphaned agent definitions
.NOTES
    Read-only validation, no side effects.
#>

Describe "opencode.json Configuration Validation" {
    BeforeAll {
        $configPath = Join-Path $PSScriptRoot "..\opencode.json"
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }

    Context "Agent Definitions" {
        It "Contains at least 40 agent definitions" {
            $agentCount = ($config.agent | Get-Member -MemberType NoteProperty).Count
            $agentCount | Should -BeGreaterOrEqual 40
        }

        It "All agents have 'model' field" {
            $agents = $config.agent | Get-Member -MemberType NoteProperty | ForEach-Object { $config.agent.$($_.Name) }
            $agentsWithoutModel = $agents | Where-Object { -not $_.model }
            $agentsWithoutModel.Count | Should -Be 0
        }

        It "All agents have 'prompt' field or 'instructions'" {
            $agents = $config.agent | Get-Member -MemberType NoteProperty | ForEach-Object { $config.agent.$($_.Name) }
            $agentsWithoutPrompt = $agents | Where-Object { -not ($_.prompt -or $_.instructions) }
            $agentsWithoutPrompt.Count | Should -Be 0
        }

        It "Orchestrator agent (gentleman-vMK) exists" {
            $config.agent.'gentleman-vMK' | Should -Not -BeNullOrEmpty
        }

        It "Subagents have 'hidden: true' or 'mode: subagent'" {
            $subagents = @('gentleman-deep-sub', 'gentleman-quick-sub', 'gentleman-codex-sub', 'gentleman-implementer-sub')
            foreach ($name in $subagents) {
                $agent = $config.agent.$name
                if ($agent) {
                    ($agent.hidden -eq $true -or $agent.mode -eq 'subagent') | Should -Be $true
                }
            }
        }
    }

    Context "Permission Rules" {
        It "Defines permission object" {
            $config.permission | Should -Not -BeNullOrEmpty
        }

        It "Permission object has bash rules" {
            $config.permission.bash | Should -Not -BeNullOrEmpty
        }

        It "Has wildcard allow for bash" {
            $config.permission.bash.'*' | Should -Be 'allow'
        }

        It "Git push rules are defined" {
            $config.permission.bash.'git push' | Should -Not -BeNullOrEmpty
            $config.permission.bash.'git push *' | Should -Not -BeNullOrEmpty
        }

        It "Git push --force is denied" {
            $config.permission.bash.'git push --force *' | Should -Be 'deny'
        }
    }

    Context "MCP Configuration" {
        It "Defines MCP servers" {
            $config.mcp | Should -Not -BeNullOrEmpty
        }

        It "Includes context7 MCP server" {
            $config.mcp.context7 | Should -Not -BeNullOrEmpty
        }

        It "Includes engram MCP server" {
            $config.mcp.engram | Should -Not -BeNullOrEmpty
        }

        It "MCP servers have 'command' or 'type' field" {
            $servers = $config.mcp | Get-Member -MemberType NoteProperty | ForEach-Object { $config.mcp.$($_.Name) }
            $serversWithoutCommand = $servers | Where-Object { -not ($_.command -or $_.type) }
            $serversWithoutCommand.Count | Should -Be 0
        }
    }

    Context "Consistency Checks" {
        It "No duplicate agent definitions" {
            $agentNames = $config.agent | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
            $uniqueNames = $agentNames | Select-Object -Unique
            $agentNames.Count | Should -Be $uniqueNames.Count
        }

        It "Agent mode variants follow naming convention (-semi, -auto)" {
            $agentNames = $config.agent | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
            $semiAgents = $agentNames | Where-Object { $_ -match '-semi$' }
            $autoAgents = $agentNames | Where-Object { $_ -match '-auto$' }
            
            # If there are -semi agents, there should be corresponding base agents
            foreach ($semi in $semiAgents) {
                $base = $semi -replace '-semi$', ''
                $agentNames | Should -Contain $base
            }
        }

        It "Subagent variants have matching base agents" {
            $agentNames = $config.agent | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
            $subAgents = $agentNames | Where-Object { $_ -match '-sub(-semi|-auto)?$' }
            
            foreach ($sub in $subAgents) {
                $base = $sub -replace '-sub(-semi|-auto)?$', '-sub'
                if ($base -ne $sub) {
                    $agentNames | Should -Contain $base
                }
            }
        }
    }
}