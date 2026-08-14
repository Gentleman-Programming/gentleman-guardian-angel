#requires -Version 7

# Pester 5 tests for scripts/check-backlog-integrity.ps1
#
# Hermetic strategy: each test builds a crafted CYCLE.md inside a scratch
# directory that lives INSIDE the repo tree (scripts/tests/_scratch_backlog_*).
# That matters because Test-CommitExistence in the script Push-Location's to
# $RepoRoot and runs `git cat-file` — git finds the repo by walking up from
# the scratch dir, so real commit hashes of THIS repo resolve correctly.
# Scratch dirs are removed in AfterAll.

BeforeAll {
    $script:BacklogScript = Join-Path $PSScriptRoot '..\check-backlog-integrity.ps1'
    $script:RepoRoot      = if ($null -ne (git rev-parse --show-toplevel 2>$null)) { git rev-parse --show-toplevel 2>$null } else { $PSScriptRoot }
    $script:RealCommit    = (git rev-parse --short HEAD).Trim()
    $script:ScratchRoot   = Join-Path $PSScriptRoot ("_scratch_backlog_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:ScratchRoot -Force | Out-Null

    # Runs the script against a scratch root, returns $LASTEXITCODE.
    function Invoke-BacklogCheck {
        param([string]$Root)
        & $script:BacklogScript -RepoRoot $Root *> $null
        return $LASTEXITCODE
    }

    # Writes a crafted CYCLE.md (same table shape as the real repo CYCLE.md:
    # "| # | Item | Impact | Risk | IR | Est | Status | Done Criteria |")
    # into a fresh per-test scratch dir, returns the dir path.
    function New-ScratchCycle {
        param([string[]]$Rows)
        $dir = Join-Path $script:ScratchRoot ("case_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $header = @(
            '### Backlog',
            '',
            '| # | Item | Impact | Risk | IR | Est | Status | Done Criteria |',
            '|---|------|--------|------|----|-----|--------|---------------|'
        )
        $content = ($header + $Rows) -join "`n"
        Set-Content -LiteralPath (Join-Path $dir 'CYCLE.md') -Value $content -Encoding UTF8
        return $dir
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:ScratchRoot) {
        Remove-Item -LiteralPath $script:ScratchRoot -Recurse -Force
    }
}

Describe 'check-backlog-integrity.ps1' {

    It 'passes a valid backlog (Done with real commit + Pending item)' {
        $row1 = "| 1 | Valid done item | High | Low | 3 | 30m | ✅ Done | commit $script:RealCommit exists |"
        $row2 = "| 2 | Valid pending item | Medium | Low | 2 | 1h | 🔴 Pending | script exists at scripts/_never_exists.ps1 |"
        $dir = New-ScratchCycle -Rows @($row1, $row2)
        Invoke-BacklogCheck -Root $dir | Should -Be 0
    }

    It 'fails a Done item claiming a nonexistent commit hash' {
        $row = "| 1 | Done with fake commit | High | Low | 3 | 30m | ✅ Done | commit abcdef0 |"
        $dir = New-ScratchCycle -Rows @($row)
        Invoke-BacklogCheck -Root $dir | Should -Be 1
    }

    It 'fails a Pending item whose script already exists (premature implementation)' {
        $row = "| 1 | Pending but implemented | Medium | Low | 2 | 1h | 🔴 Pending | script exists at scripts/_scratch_dummy.ps1 |"
        $dir = New-ScratchCycle -Rows @($row)
        # Create the "already implemented" script inside the per-test root
        $dummyDir = Join-Path $dir 'scripts'
        New-Item -ItemType Directory -Path $dummyDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $dummyDir '_scratch_dummy.ps1') -Force | Out-Null
        Invoke-BacklogCheck -Root $dir | Should -Be 1
    }

    It 'fails on an unknown status not in the Done/Pending sets' {
        $row = "| 1 | Unknown status item | Medium | Low | 2 | 1h | 🚧 | whatever |"
        $dir = New-ScratchCycle -Rows @($row)
        Invoke-BacklogCheck -Root $dir | Should -Be 1
    }

    It 'fails when CYCLE.md is missing in the root' {
        $dir = Join-Path $script:ScratchRoot ("case_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-BacklogCheck -Root $dir | Should -Be 1
    }

    It 'emits valid JSON on error when -Json is passed (missing CYCLE.md)' {
        $dir = Join-Path $script:ScratchRoot ("case_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $json = & $script:BacklogScript -RepoRoot $dir -Json 2>$null
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 1
        { $json | ConvertFrom-Json } | Should -Not -Throw
        $parsed = $json | ConvertFrom-Json
        $parsed.allPassed | Should -Be $false
        $parsed.errors | Should -Contain 'CYCLE.md not found'
        $parsed.score | Should -Be 0
        $parsed.totalItems | Should -Be 0
        $parsed.timestamp | Should -Not -BeNullOrEmpty
    }
}

