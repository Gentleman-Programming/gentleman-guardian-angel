#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Pester tests for check-mcp-security.ps1 core logic.
    Tests: Test-ArchivedServer, Test-TrustedSource, Test-HardcodedToken,
           Get-ServerIdentifier, Get-EstimatedToolCount.
    Compatible with Pester 5.x / 6.x.
.NOTES
    Test fixtures construct fake token prefixes dynamically (char arrays)
    to avoid triggering secrets-scan false positives.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # Dot-sourcing the full script crashes on remote servers (context7 has no 'command'
    # property → PropertyNotFoundException under StrictMode). Extract functions + data only.
    $raw = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'check-mcp-security.ps1') -Raw

    # Extract data arrays
    if ($raw -match '(?s)(\$archivedServers\s*=\s*@\([^)]+\))') {
        . ([ScriptBlock]::Create($Matches[1]))
    }
    if ($raw -match '(?s)(\$trustedVendors\s*=\s*@\([^)]+\))') {
        . ([ScriptBlock]::Create($Matches[1]))
    }
    if ($raw -match '(?s)(\$knownToolCounts\s*=\s*@\{[^}]+\})') {
        . ([ScriptBlock]::Create($Matches[1]))
    }

    # Extract functions via line-based regex (avoids running main logic).
    # Uses (?ms) so ^ matches line starts — function closing braces are at column 0.
    foreach ($fn in @('Test-ArchivedServer', 'Test-TrustedSource', 'Test-HardcodedToken',
                      'Get-ServerIdentifier', 'Get-EstimatedToolCount')) {
        if ($raw -match "(?ms)(function\s+$fn\s*\{.*?^\})") {
            . ([ScriptBlock]::Create($Matches[1]))
        }
    }
}

# ============================================================
Describe 'Test-ArchivedServer' {
    It 'returns true for archived server name' {
        $result = Test-ArchivedServer -Name 'server-postgres' -Command @()
        $result | Should -Be $true
    }

    It 'returns true for archived server in command' {
        $result = Test-ArchivedServer -Name 'my-server' -Command @('npx', '-y', '@modelcontextprotocol/server-slack')
        $result | Should -Be $true
    }

    It 'returns false for non-archived server' {
        $result = Test-ArchivedServer -Name 'context7' -Command @('context7-mcp')
        $result | Should -Be $false
    }

    It 'returns false for empty inputs' {
        $result = Test-ArchivedServer -Name '' -Command @()
        $result | Should -Be $false
    }

    It 'detects partial name match' {
        $result = Test-ArchivedServer -Name 'server-filesystem-backup' -Command @()
        $result | Should -Be $true
    }
}

# ============================================================
Describe 'Test-TrustedSource' {
    It 'returns true for MCP Steering Group packages' {
        $result = Test-TrustedSource -Command @('npx', '-y', '@modelcontextprotocol/server-fetch')
        $result | Should -Be $true
    }

    It 'returns true for Upstash (Context7)' {
        $result = Test-TrustedSource -Command @('npx', '-y', '@upstash/context7-mcp')
        $result | Should -Be $true
    }

    It 'returns true for engram' {
        $result = Test-TrustedSource -Command @('engram', 'mcp', '--tools=mem_save,mem_search,mem_context,mem_session_summary,mem_get_observation,mem_save_prompt,mem_current_project,mem_judge')
        $result | Should -Be $true
    }

    It 'returns true for docker' {
        $result = Test-TrustedSource -Command @('docker', 'run', '--rm', 'mcp/server-brave-search')
        $result | Should -Be $true
    }

    It 'returns false for unknown source' {
        $result = Test-TrustedSource -Command @('npx', '-y', '@random-user/sketchy-mcp')
        $result | Should -Be $false
    }

    It 'returns false for empty command' {
        $result = Test-TrustedSource -Command @()
        $result | Should -Be $false
    }

    It 'is case-insensitive' {
        $result = Test-TrustedSource -Command @('NPX', '-Y', '@UPSTASH/CONTEXT7-MCP')
        $result | Should -Be $true
    }
}

# ============================================================
Describe 'Test-HardcodedToken' {
    BeforeAll {
        # Construct fake tokens dynamically to avoid secrets-scan false positives
        # ponytail: test fixtures — NOT real secrets
        # Build prefix strings char-by-char so no literal secret patterns appear in source
        $script:fakePrefix = [char[]]@(103,104,112,95) -join ''  # ghp + underscore
        $script:fakeSuffix = '1234567890'
        $script:fakePatPrefix = [char[]]@(103,105,116,104,117,98,95,112,97,116,95) -join ''  # github_pat + underscore
        $script:fakePatSuffix = 'abc123'
        $script:fakeApiKey = "$([char[]]@(115,107) -join '')-abc123def456"
    }

    It 'detects --api-key with literal value' {
        $result = Test-HardcodedToken -Command @('server', '--api-key', $script:fakeApiKey)
        $result | Should -Be $true
    }

    It 'detects --token with literal value' {
        $token = "$($script:fakePrefix)$($script:fakeSuffix)"
        $result = Test-HardcodedToken -Command @('server', '--token', $token)
        $result | Should -Be $true
    }

    It 'detects GH_TOKEN with literal value' {
        $token = "$($script:fakePrefix)$($script:fakeSuffix)"
        $result = Test-HardcodedToken -Command @('server', "GH_TOKEN=$token")
        $result | Should -Be $true
    }

    It 'allows {env:...} references' {
        $result = Test-HardcodedToken -Command @('server', '--api-key', '{env:API_KEY}')
        $result | Should -Be $false
    }

    It 'allows {env:CONTEXT7_API_KEY}' {
        $result = Test-HardcodedToken -Command @('context7-mcp', '--api-key', '{env:CONTEXT7_API_KEY}')
        $result | Should -Be $false
    }

    It 'returns false for clean commands' {
        $result = Test-HardcodedToken -Command @('npx', '-y', '@upstash/context7-mcp')
        $result | Should -Be $false
    }

    It 'detects PAT prefix' {
        $token = "$($script:fakePatPrefix)$($script:fakePatSuffix)"
        $result = Test-HardcodedToken -Command @('server', "GITHUB_TOKEN=$token")
        $result | Should -Be $true
    }
}

# ============================================================
Describe 'Get-ServerIdentifier' {
    It 'extracts scoped package name' {
        $result = Get-ServerIdentifier -Name 'my-server' -Command @('npx', '-y', '@upstash/context7-mcp@3.2.2')
        $result | Should -Be '@upstash/context7-mcp'
    }

    It 'extracts unscoped package name' {
        $result = Get-ServerIdentifier -Name 'engram' -Command @('engram', 'mcp', '--tools=mem_save,mem_search,mem_context,mem_session_summary,mem_get_observation,mem_save_prompt,mem_current_project,mem_judge')
        $result | Should -Be 'engram'
    }

    It 'falls back to name when no package pattern' {
        $result = Get-ServerIdentifier -Name 'my-custom-server' -Command @('/usr/local/bin/my-server')
        $result | Should -Be 'my-custom-server'
    }
}

# ============================================================
Describe 'Get-EstimatedToolCount' {
    It 'returns known count for context7' {
        $result = Get-EstimatedToolCount -Name 'context7'
        $result | Should -Be 2
    }

    It 'returns known count for engram' {
        $result = Get-EstimatedToolCount -Name 'engram'
        $result | Should -Be 18
    }

    It 'returns null for unknown server' {
        $result = Get-EstimatedToolCount -Name 'unknown-mcp-server'
        $result | Should -BeNullOrEmpty
    }

    It 'matches partial name' {
        $result = Get-EstimatedToolCount -Name 'my-context7-wrapper'
        $result | Should -Be 2
    }
}
