#requires -Version 7

<#
.SYNOPSIS
    Tests for resource optimization tooling -- monitor-opencode.ps1,
    heap-snapshot.ps1, hardware-profile.ps1, and opencode.json config.

.DESCRIPTION
    Validates that resource optimization configs are properly set and
    that the monitoring scripts function correctly.
#>

Describe "Resource Optimization -- opencode.json Config" {
    BeforeAll {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $configPath = Join-Path $repoRoot "opencode.json"
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }

    It "has small_model configured for lightweight tasks" {
        $config.small_model | Should -Be "opencode/free"
    }

    It "has agent.default.depth set to 2" {
        $config.agent.default.depth | Should -Be 2
    }

    It "has compaction.auto enabled" {
        $config.compaction.auto | Should -BeTrue
    }

    It "has compaction.prune enabled" {
        $config.compaction.prune | Should -BeTrue
    }

    It "has compaction.reserved reduced to 6000" {
        $config.compaction.reserved | Should -Be 6000
    }

    It "has watcher disabled" {
        $config.watcher.enabled | Should -BeFalse
    }

    It "has watcher ignore patterns for noise directories" {
        $config.watcher.ignore | Should -Contain "node_modules"
        $config.watcher.ignore | Should -Contain ".git"
        $config.watcher.ignore | Should -Contain "dist"
    }

    It "has snapshot disabled" {
        $config.snapshot.enabled | Should -BeFalse
    }

    It "has resource profile marker" {
        $config._resource_profile | Should -Be "lightweight"
    }

    It "preserves all existing agents (>50)" {
        $config.agent.PSObject.Properties.Name.Count | Should -BeGreaterThan 50
    }
}

Describe "Resource Optimization -- Config Profile Files" {
    BeforeAll {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $profileDir = Join-Path $repoRoot "scripts/opencode-configs"
    }

    It "low-resource.json is valid JSON with correct tier" {
        $c = Get-Content (Join-Path $profileDir "low-resource.json") -Raw | ConvertFrom-Json
        $c._resource_tier | Should -Be "low"
        $c.small_model | Should -Be "opencode/free"
        $c.compaction.prune | Should -BeTrue
        $c.snapshot.enabled | Should -BeFalse
        $c.agent.default.depth | Should -Be 1
    }

    It "medium-resource.json is valid JSON with correct tier" {
        $c = Get-Content (Join-Path $profileDir "medium-resource.json") -Raw | ConvertFrom-Json
        $c._resource_tier | Should -Be "medium"
        $c.small_model | Should -Be "opencode/free"
        $c.compaction.prune | Should -BeTrue
        $c.snapshot.enabled | Should -BeTrue
        $c.agent.default.depth | Should -Be 2
    }

    It "high-resource.json is valid JSON with correct tier" {
        $c = Get-Content (Join-Path $profileDir "high-resource.json") -Raw | ConvertFrom-Json
        $c._resource_tier | Should -Be "high"
        $c.small_model | Should -Be "opencode/free"
        $c.compaction.prune | Should -BeTrue
        $c.snapshot.enabled | Should -BeTrue
        $c.agent.default.depth | Should -Be 3
    }

    It "low profile has watcher disabled" {
        $c = Get-Content (Join-Path $profileDir "low-resource.json") -Raw | ConvertFrom-Json
        $c.watcher.enabled | Should -BeFalse
    }

    It "high profile has watcher enabled" {
        $c = Get-Content (Join-Path $profileDir "high-resource.json") -Raw | ConvertFrom-Json
        $c.watcher.enabled | Should -BeTrue
    }
}

Describe "Resource Optimization -- Script Syntax" {
    BeforeAll {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    }

    It "monitor-opencode.ps1 has no parse errors" {
        $path = Join-Path $repoRoot "scripts/monitor-opencode.ps1"
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "heap-snapshot.ps1 has no parse errors" {
        $path = Join-Path $repoRoot "scripts/heap-snapshot.ps1"
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "hardware-profile.ps1 has no parse errors" {
        $path = Join-Path $repoRoot "scripts/hardware-profile.ps1"
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }
}

Describe "Resource Optimization -- Hardware Profile Script Execution" -Tag "ps7" {
    BeforeAll {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $repoRoot "scripts/hardware-profile.ps1"
    }

    It "outputs all profiles with -Json" {
        $result = & $scriptPath -OutputProfile all -Json 2>&1
        $jsonLine = $result | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        $json = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
        $json | Should -Not -BeNull
        $json.hardware | Should -Not -BeNull
        $json.profiles.low | Should -Not -BeNull
        $json.profiles.medium | Should -Not -BeNull
        $json.profiles.high | Should -Not -BeNull
    }

    It "low profile has subagent_depth=1" {
        $result = & $scriptPath -OutputProfile low -Json 2>&1
        $json = ($result | Where-Object { $_ -match '^\{' } | Select-Object -First 1) | ConvertFrom-Json -ErrorAction SilentlyContinue
        $json.agent.default.depth | Should -Be 1
    }

    It "medium profile has subagent_depth=2" {
        $result = & $scriptPath -OutputProfile medium -Json 2>&1
        $json = ($result | Where-Object { $_ -match '^\{' } | Select-Object -First 1) | ConvertFrom-Json -ErrorAction SilentlyContinue
        $json.agent.default.depth | Should -Be 2
    }

    It "high profile has subagent_depth=3" {
        $result = & $scriptPath -OutputProfile high -Json 2>&1
        $json = ($result | Where-Object { $_ -match '^\{' } | Select-Object -First 1) | ConvertFrom-Json -ErrorAction SilentlyContinue
        $json.agent.default.depth | Should -Be 3
    }
}

Describe "Resource Optimization -- Heap Snapshot Script" -Tag "ps7" {
    BeforeAll {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $repoRoot "scripts/heap-snapshot.ps1"
    }

    It "exits gracefully when no OpenCode process found" {
        & $scriptPath -Action status -Json 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}