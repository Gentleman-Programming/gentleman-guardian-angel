#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Pester tests for sync-vmk.ps1 — Sync-Config function.
    Uses temp JSON files to test config comparison and sync logic.
.NOTES
    ponytail: file I/O tests — temp files, cleaned up after.
    sync-vmk.ps1 dot-sources and sets up $canonical + $results at script scope.
    We test Sync-Config by checking $results after each call.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # Test mode: prevents the dot-sourced sync-vmk.ps1 from applying its top-level
    # global config sync (writing real global opencode.json + AGENTS.md).
    $script:oldPesterTest = $env:PESTER_TEST
    $env:PESTER_TEST = '1'

    # Dot-source the script — runs main code, sets up $canonical, $results, $DryRun, etc.
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'sync-vmk.ps1')

    # Save the real canonical path for reference
    $script:realCanonicalPath = Join-Path (Split-Path $PSScriptRoot -Parent) "opencode.json"
}

AfterAll {
    if ($null -eq $script:oldPesterTest) {
        Remove-Item Env:PESTER_TEST -ErrorAction SilentlyContinue
    } else {
        $env:PESTER_TEST = $script:oldPesterTest
    }
}

# ============================================================
Describe 'Sync-Config' {
    BeforeAll {
        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pester-syncvmk-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:tempRoot) {
            Remove-Item -Path $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports SKIP when target file does not exist' {
        $missingPath = Join-Path $script:tempRoot "nonexistent.json"
        $beforeCount = $results.Count
        Sync-Config -TargetPath $missingPath -Label "missing" -PreserveMCP $false
        $results.Count | Should -Be ($beforeCount + 1)
        $results[-1].status | Should -Be "SKIP"
        $results[-1].detail | Should -Match "File not found"
    }

    It 'reports OK when target matches canonical (no changes)' {
        # Use the actual canonical file that was read during dot-source
        $targetPath = Join-Path $script:tempRoot "matching.json"
        $canonical | ConvertTo-Json -Depth 10 | Set-Content -Path $targetPath -Encoding UTF8

        $beforeCount = $results.Count
        Sync-Config -TargetPath $targetPath -Label "matching" -PreserveMCP $false
        $results.Count | Should -Be ($beforeCount + 1)
        $results[-1].status | Should -Be "OK"
    }

    It 'reports DRY-RUN when DryRun is set and changes exist' {
        $targetPath = Join-Path $script:tempRoot "dryrun.json"
        # Clone canonical and change agent section to trigger diff
        $fakeConfig = $canonical | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $fakeConfig.agent = @{ name = "old-version"; version = "0.1" }
        $fakeConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $targetPath -Encoding UTF8

        # Temporarily enable DryRun
        $savedDryRun = $DryRun
        $DryRun = $true
        $beforeCount = $results.Count

        Sync-Config -TargetPath $targetPath -Label "dryrun" -PreserveMCP $false

        $DryRun = $savedDryRun
        $results.Count | Should -Be ($beforeCount + 1)
        $results[-1].status | Should -Be "DRY-RUN"
        $results[-1].detail | Should -Match "Would update"
    }
}
