#requires -Version 7
<#
.SYNOPSIS
    Pester tests for session-checkpoint.ps1 — the proactive memory-capture bridge.
    Validates: ctx-watchdog integration, checkpoint JSON creation, engram-validate
    poisoning guard, check vs mark vs full modes, and YELLOW threshold behavior.

.NOTES
    Tests use inline function definitions (like health-check.Tests.ps1) to avoid
    executing main code on dot-source. Temp dirs cleaned up after.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    $script:repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:checkpointDir = Join-Path $repoRoot ".opencode\session-checkpoints"

    # Inline replica of the zone determination logic (mirrors ctx-watchdog.ps1)
    function Get-ContextZone {
        param([int]$UsagePercent)
        if ($UsagePercent -le 40) { return @{ zone="GREEN"; level=""; needsCheckpoint=$false } }
        elseif ($UsagePercent -le 60) { return @{ zone="YELLOW"; level="L1"; needsCheckpoint=$true } }
        elseif ($UsagePercent -le 80) { return @{ zone="ORANGE"; level="L1"; needsCheckpoint=$true } }
        elseif ($UsagePercent -le 95) { return @{ zone="RED"; level="L2"; needsCheckpoint=$true } }
        else { return @{ zone="CRITICAL"; level="L3"; needsCheckpoint=$true } }
    }

    # Helper: run session-checkpoint.ps1 in check mode and parse JSON output
    function Invoke-CheckpointCheck {
        param([int]$Percent, [string[]]$Discoveries = @(), [string[]]$Decisions = @())
        $params = @("-Mode", "check", "-UsagePercent", $Percent, "-Quiet")
        if ($Discoveries) { $params += "-Discoveries"; $params += $Discoveries }
        if ($Decisions) { $params += "-Decisions"; $params += $Decisions }
        $out = & (Join-Path $PSScriptRoot "..\session-checkpoint.ps1") @params 2>$null
        return $out | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
}

AfterAll {
    # Cleanup checkpoint dir between test runs
    if (Test-Path $script:checkpointDir) {
        Remove-Item -LiteralPath $script:checkpointDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Session Checkpoint Bridge — Zone Detection" {
    It "GREEN zone at 25% — no checkpoint needed" {
        $result = Invoke-CheckpointCheck -Percent 25
        $result.zone | Should -Be "GREEN"
        $result.checkpoint_needed | Should -Be $false
    }

    It "YELLOW zone at 45% — checkpoint recommended" {
        $result = Invoke-CheckpointCheck -Percent 45
        $result.zone | Should -Be "YELLOW"
        $result.checkpoint_needed | Should -Be $true
    }

    It "ORANGE zone at 65% — checkpoint recommended" {
        $result = Invoke-CheckpointCheck -Percent 65
        $result.zone | Should -Be "ORANGE"
        $result.checkpoint_needed | Should -Be $true
        $result.compression_level | Should -Be "L1"
    }

    It "RED zone at 85% — aggressive compression" {
        $result = Invoke-CheckpointCheck -Percent 85
        $result.zone | Should -Be "RED"
        $result.compression_level | Should -Be "L2"
        $result.checkpoint_needed | Should -Be $true
    }

    It "CRITICAL zone at 98% — max compression" {
        $result = Invoke-CheckpointCheck -Percent 98
        $result.zone | Should -Be "CRITICAL"
        $result.compression_level | Should -Be "L3"
    }
}

Describe "Session Checkpoint Bridge — Checkpoint Creation" {
    It "check mode does NOT create checkpoint file" {
        $result = Invoke-CheckpointCheck -Percent 25
        $result.checkpoint_created | Should -Be $false
        $result.checkpoint_file | Should -Be $null
    }

    It "mark mode with Force creates checkpoint JSON at 5%" {
        $before = (Get-ChildItem -LiteralPath $script:checkpointDir -ErrorAction SilentlyContinue | Measure-Object).Count
        $params = @("-Mode", "mark", "-UsagePercent", "5", "-Force", "-Quiet")
        $out = & (Join-Path $PSScriptRoot "..\session-checkpoint.ps1") @params 2>$null
        $result = $out | ConvertFrom-Json -ErrorAction SilentlyContinue
        $result.checkpoint_created | Should -Be $true
        $result.checkpoint_file | Should -Not -Be $null
        Test-Path -LiteralPath $result.checkpoint_file | Should -Be $true
    }

    It "checkpoint JSON has required fields" {
        $params = @("-Mode", "mark", "-UsagePercent", "50", "-Force", "-Quiet")
        $out = & (Join-Path $PSScriptRoot "..\session-checkpoint.ps1") @params 2>$null
        $result = $out | ConvertFrom-Json -ErrorAction SilentlyContinue
        $checkpointJson = Get-Content -LiteralPath $result.checkpoint_file -Raw | ConvertFrom-Json
        $checkpointJson.session_id | Should -Not -BeNullOrEmpty
        $checkpointJson.context_zone | Should -Be "YELLOW"
        $checkpointJson.timestamp | Should -Not -BeNullOrEmpty
        $checkpointJson.branch | Should -Not -BeNullOrEmpty
    }

    It "discoveries trigger checkpoint even in GREEN zone" {
        $result = Invoke-CheckpointCheck -Percent 10 -Discoveries @("found N+1 bug")
        $result.checkpoint_needed | Should -Be $true
    }
}

Describe "Session Checkpoint Bridge — Engram-Validate Gate" {
    It "validator path resolves correctly" {
        $validatorPath = Join-Path $PSScriptRoot "..\engram-validate.ps1"
        Test-Path -LiteralPath $validatorPath | Should -Be $true
    }

    It "checkpoint content passes poisoning guard format" {
        # The checkpoint mem_save content must include **What**: field
        $params = @("-Mode", "mark", "-UsagePercent", "50", "-Force", "-Quiet")
        $out = & (Join-Path $PSScriptRoot "..\session-checkpoint.ps1") @params 2>$null
        $result = $out | ConvertFrom-Json -ErrorAction SilentlyContinue
        $result.validated | Should -Be $true
    }
}

Describe "Session Checkpoint Bridge — Mode Behavior" {
    It "check mode outputs zone info only" {
        $result = Invoke-CheckpointCheck -Percent 30
        $result.zone | Should -Be "GREEN"
        $result.action | Should -Be "none_needed"
    }

    It "full mode with discoveries triggers miner" {
        $params = @("-Mode", "full", "-UsagePercent", "45", "-Discoveries", "N+1 query in UserList", "-Quiet")
        $out = & (Join-Path $PSScriptRoot "..\session-checkpoint.ps1") @params 2>$null
        $result = $out | ConvertFrom-Json -ErrorAction SilentlyContinue
        $result.checkpoint_created | Should -Be $true
    }
}
