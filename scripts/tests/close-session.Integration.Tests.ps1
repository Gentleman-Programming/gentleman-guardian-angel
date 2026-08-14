#requires -Version 7

<#
.SYNOPSIS
    Non-destructive integration tests for close-session.ps1.
.NOTES
    Tests output format, parameter passthrough, and JSON contract without
    modifying real project state. BITACORA writes are redirected to a per-run
    temp file via -BitacoraPath. The script's internal logic (needsAudit,
    bloat detection, session-miner) is covered by 43 unit tests in
    close-session.Tests.ps1 — this file tests the integration surface:
    parameter binding, JSON contract, and error paths.
#>

BeforeAll {
    $scriptsRoot = Resolve-Path "$PSScriptRoot/.."
    $scriptPath = "$scriptsRoot/close-session.ps1"

    # Isolated temp BITACORA — session entries are written there via -BitacoraPath,
    # so the repo's real BITACORA.md is never read or modified. The remaining
    # paths resolved from $PSScriptRoot (git status, .agents/skills/*, AGENTS.md
    # bloat, session-miner check) are read-only in these tests.
    $bitacoraPath = Join-Path ([System.IO.Path]::GetTempPath()) ("close-session-bitacora-{0}.md" -f ([guid]::NewGuid().ToString("N")))
    if (Test-Path -LiteralPath "$scriptsRoot/../BITACORA.md") {
        Copy-Item -LiteralPath "$scriptsRoot/../BITACORA.md" -Destination $bitacoraPath -Force
    } else {
        Set-Content -LiteralPath $bitacoraPath -Value "" -Encoding UTF8
    }
}

AfterAll {
    if (Test-Path -LiteralPath $bitacoraPath) {
        Remove-Item -LiteralPath $bitacoraPath -Force
    }
}

Describe "close-session — Integration: JSON contract" {

    It "returns valid JSON in -Quiet mode with expected fields" {
        $output = & $scriptPath -Goal "IntTestGoal" -Description "Int test" -BitacoraPath $bitacoraPath -Quiet 2>&1
        $result = $output | Out-String | ConvertFrom-Json

        # Contract: all expected fields must exist
        $result.action | Should -Be "close-session"
        $result.timestamp | Should -Not -BeNullOrEmpty
        $result.branch | Should -Not -BeNullOrEmpty
        $result.hasChanges | Should -Not -BeNullOrEmpty
        $result.goal | Should -Be "IntTestGoal"
        $result.needsAudit | Should -Not -BeNullOrEmpty
        $result.auditGatePassed | Should -Not -BeNullOrEmpty
    }

    It "changeCount is a valid number" {
        $output = & $scriptPath -Goal "Test" -Description "Int test" -BitacoraPath $bitacoraPath -Quiet 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        $result.changeCount -is [ValueType] | Should -Be $true
        $result.changeCount | Should -BeGreaterOrEqual 0
    }

    It "includes protectedTouched as array when protected files changed" {
        # This test runs against the real project's git status
        # If there are any modified protected files, it will flag them
        # If not, protectedTouched will be empty — both are valid
        $output = & $scriptPath -Goal "Test" -Description "Protected check" -BitacoraPath $bitacoraPath -Quiet 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        $result.protectedTouched -is [System.Array] | Should -Be $true
    }

    It "auditGatePassed is boolean" {
        $output = & $scriptPath -Goal "Test" -Description "Gate check" -BitacoraPath $bitacoraPath -Quiet 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        ($result.auditGatePassed -is [bool]) | Should -Be $true
    }
}

Describe "close-session — Integration: parameter binding" {

    It "accepts -Goal parameter" {
        $output = & $scriptPath -Goal "Integrate auth middleware" -Description "Test" -BitacoraPath $bitacoraPath -Quiet 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        $result.goal | Should -Be "Integrate auth middleware"
    }

    It "accepts -Description parameter" {
        $output = & $scriptPath -Goal "Test" -Description "Added RBAC support" -BitacoraPath $bitacoraPath -Quiet 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        # Description is not in JSON output (it's only in BITACORA), but we can verify no error
        $result | Should -Not -BeNullOrEmpty
    }

    It "accepts -DryRun flag" {
        $output = & $scriptPath -Goal "Test" -Description "Dry run" -BitacoraPath $bitacoraPath -DryRun -Quiet 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        $result.action | Should -Be "close-session"
    }

    It "accepts -CompactPrompt flag" {
        $output = & $scriptPath -Goal "Test" -Description "Compact" -BitacoraPath $bitacoraPath -CompactPrompt 2>&1
        $outputString = $output | Out-String
        $outputString | Should -Match "COMPACT PROMPT FOR NEXT SESSION"
    }
}

Describe "close-session — Integration: non-Quiet output format" {

    It "outputs compact prompt or session header in non-Quiet mode" {
        # Header is emitted via Write-Host (information stream #6) — capture it
        $output = & $scriptPath -Goal "Test" -Description "Non-quiet test" -BitacoraPath $bitacoraPath 6>&1
        $outputString = $output | Out-String
        # When changes exist, compact prompt takes priority; when clean, SESSION CLOSE shows
        $hasSessionHeader = $outputString -match "SESSION CLOSE"
        $hasCompactPrompt = $outputString -match "COMPACT PROMPT FOR NEXT SESSION"
        ($hasSessionHeader -or $hasCompactPrompt) | Should -Be $true
    }

    It "includes branch and goal in output" {
        # Header is emitted via Write-Host (information stream #6) — capture it
        $output = & $scriptPath -Goal "TestBranchGoal" -Description "Branch test" -BitacoraPath $bitacoraPath 6>&1
        $outputString = $output | Out-String
        $outputString | Should -Match "Branch|COMPACT PROMPT"
        # The goal only appears in the compact prompt when changes exist (clean
        # tree → SESSION CLOSE header without goal). Assert the state-independent
        # contract: goal is always present in the -Quiet JSON output.
        $jsonOut = & $scriptPath -Goal "TestBranchGoal" -Description "Branch test" -BitacoraPath $bitacoraPath -Quiet 2>&1 | Out-String | ConvertFrom-Json
        $jsonOut.goal | Should -Be "TestBranchGoal"
    }
}

