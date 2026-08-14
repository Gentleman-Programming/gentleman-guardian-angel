#requires -Version 7
<#
.SYNOPSIS ADR-019 - check-subagent-output.ps1 empty-output detection
.DESCRIPTION Tests for the post-delegation empty-output detector.
  Uses isolated git repos in $TestDrive for hermetic testing.
#>
Describe 'check-subagent-output.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\scripts\check-subagent-output.ps1'
    }

    It 'T1 fails on empty diff (silent failure detection)' {
        # Isolated git repo with a commit, no changes since
        $repo = Join-Path $TestDrive 'repo-empty'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        git -C $repo init --quiet 2>&1
        Set-Content -Path (Join-Path $repo 'init.txt') -Value 'initial'
        git -C $repo add init.txt 2>&1
        git -C $repo commit -m 'init' --quiet 2>&1

        $r = & $scriptPath -RepoRoot $repo -BaseRef HEAD 2>&1
        $LASTEXITCODE | Should -Be 1
        ($r -join '`n') | Should -Match 'SILENT FAILURE'
    }

    It 'T2 passes on real changes' {
        $repo = Join-Path $TestDrive 'repo-changes'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        git -C $repo init --quiet 2>&1
        Set-Content -Path (Join-Path $repo 'init.txt') -Value 'initial'
        git -C $repo add init.txt 2>&1
        git -C $repo commit -m 'init' --quiet 2>&1

        Set-Content -Path (Join-Path $repo 'new.txt') -Value 'new file'
        $r = & $scriptPath -RepoRoot $repo -BaseRef HEAD 2>&1
        $LASTEXITCODE | Should -Be 0
        ($r -join '`n') | Should -Match 'file\(s\) changed'
    }

    It 'T3 detects missing expected files' {
        $repo = Join-Path $TestDrive 'repo-missing'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        git -C $repo init --quiet 2>&1
        Set-Content -Path (Join-Path $repo 'init.txt') -Value 'initial'
        git -C $repo add init.txt 2>&1
        git -C $repo commit -m 'init' --quiet 2>&1

        Set-Content -Path (Join-Path $repo 'new.txt') -Value 'new file'
        $r = & $scriptPath -RepoRoot $repo -BaseRef HEAD -ExpectedFiles 'nonexistent.ts' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($r -join '`n') | Should -Match 'Expected files NOT found'
    }

    It 'T4 JSON output mode on success' {
        $repo = Join-Path $TestDrive 'repo-json'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        git -C $repo init --quiet 2>&1
        Set-Content -Path (Join-Path $repo 'init.txt') -Value 'initial'
        git -C $repo add init.txt 2>&1
        git -C $repo commit -m 'init' --quiet 2>&1

        Set-Content -Path (Join-Path $repo 'new.txt') -Value 'new file'
        $r = & $scriptPath -RepoRoot $repo -BaseRef HEAD -Quiet 2>&1
        $LASTEXITCODE | Should -Be 0
        ($r -join '`n') | Should -Match 'OK'
    }
}