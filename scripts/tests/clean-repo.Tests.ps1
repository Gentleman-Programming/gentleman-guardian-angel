#requires -Version 7

<#
.SYNOPSIS
    Tests for scripts/clean-repo.ps1 — uses a THROWAWAY temp git repo,
    never touches the real repository state.
#>
BeforeAll {
    $script:script = Join-Path $PSScriptRoot '..\clean-repo.ps1'
    $script:testDir = Join-Path $env:TEMP "clean-repo-test-$PID"
    $script:repoDir = Join-Path $testDir 'repo'
    New-Item -ItemType Directory -Path $script:repoDir -Force | Out-Null
    Push-Location $script:repoDir
    git init -q 2>$null
    # committed baseline file
    Set-Content -LiteralPath (Join-Path $script:repoDir 'tracked.txt') -Value 'tracked' -Encoding Ascii
    git add tracked.txt 2>$null
    git -c user.email=test@test -c user.name=test commit -q -m 'baseline' 2>$null
    # untracked (non-junk) + junk + dangling junction
    Set-Content -LiteralPath (Join-Path $script:repoDir 'wip-notes.md') -Value 'x' -Encoding Ascii
    Set-Content -LiteralPath (Join-Path $script:repoDir 'leftover.bak') -Value 'x' -Encoding Ascii
}

AfterAll {
    Pop-Location
    Remove-Item -LiteralPath $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'clean-repo.ps1 — dry-run is non-destructive' {
    It 'fails cleanly outside a git repo' {
        $out = & $script:script -RepoRoot (Join-Path $env:TEMP 'no-such-dir-xyz') -Quiet 2>$null
        $LASTEXITCODE | Should -Be 2
        ($out | ConvertFrom-Json).ok | Should -Be $false
    }

    It 'reports untracked and junk without deleting in dry-run' {
        $out = & $script:script -RepoRoot $script:repoDir -Quiet
        $LASTEXITCODE | Should -Be 0
        $r = $out | ConvertFrom-Json
        $r.mode | Should -Be 'dry-run'
        @($r.untracked).Count | Should -BeGreaterOrEqual 1
        @($r.junk).Count | Should -BeGreaterOrEqual 1
        # files still exist
        (Test-Path -LiteralPath (Join-Path $script:repoDir 'wip-notes.md')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:repoDir 'leftover.bak')) | Should -Be $true
    }
}

Describe 'clean-repo.ps1 — apply path' {
    It 'preserves untracked files with -Yes alone (safety default)' {
        # fresh repo state: wip-notes.md (untracked, non-junk) + leftover.bak (junk)
        $out = & $script:script -RepoRoot $script:repoDir -Yes -Quiet
        $LASTEXITCODE | Should -Be 0
        $r = $out | ConvertFrom-Json
        $r.mode | Should -Be 'apply'
        # junk removed, untracked preserved
        (Test-Path -LiteralPath (Join-Path $script:repoDir 'leftover.bak')) | Should -Be $false
        (Test-Path -LiteralPath (Join-Path $script:repoDir 'wip-notes.md')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:repoDir 'tracked.txt')) | Should -Be $true
    }

    It 'removes untracked only with -Yes -RemoveUntracked' {
        $out = & $script:script -RepoRoot $script:repoDir -Yes -RemoveUntracked -Quiet
        $LASTEXITCODE | Should -Be 0
        $r = $out | ConvertFrom-Json
        $r.mode | Should -Be 'apply'
        (Test-Path -LiteralPath (Join-Path $script:repoDir 'wip-notes.md')) | Should -Be $false
        (Test-Path -LiteralPath (Join-Path $script:repoDir 'tracked.txt')) | Should -Be $true
    }
}

