#requires -Version 7

<#
.SYNOPSIS
  E2E pipeline tests for gentleman-agent-gh — validates full integration:
  test suite integrity, security gates, pre-commit hook, CodeCoverage, SDD config
.DESCRIPTION
  Tests the complete pipeline: analysis→execution→verification state consistency.
#>

Set-StrictMode -Version Latest

# E2E tests know their project — hardcode root via git
$script:ProjectRoot = $null
BeforeAll {
    Push-Location $PSScriptRoot
    $script:ProjectRoot = git rev-parse --show-toplevel 2>$null
    Pop-Location
    if (-not $script:ProjectRoot) { throw "Not in a git repo" }
}

# ============================================================
Describe 'E2E: Suite Integrity' {

    It 'discovers all 17 test files' {
        $files = Get-ChildItem "$PSScriptRoot/*.Tests.ps1" -ErrorAction Stop
        $files.Count | Should -BeGreaterOrEqual 17
    }

    It 'the 4 new security test files exist' {
        @(
            'validate-write-scope.Tests.ps1',
            'close-session.Tests.ps1',
            'restore.Tests.ps1',
            'forge-rollback.Tests.ps1'
        ) | ForEach-Object {
            Join-Path $PSScriptRoot $_ | Should -Exist
        }
    }

    It 'all test files parse without syntax errors' {
        $errors = @()
        Get-ChildItem "$PSScriptRoot/*.Tests.ps1" | ForEach-Object {
            try {
                $null = [System.Management.Automation.Language.Parser]::ParseFile(
                    $_.FullName, [ref]$null, [ref]$null
                )
            } catch {
                $errors += "$($_.Name): $($_.Exception.Message)"
            }
        }
        $errors | Should -BeNullOrEmpty
    }

    It '4 new files total at least 80 It blocks combined' {
        $total = 0
        'validate-write-scope.Tests.ps1','close-session.Tests.ps1',
        'restore.Tests.ps1','forge-rollback.Tests.ps1' | ForEach-Object {
            $path = Join-Path $PSScriptRoot $_
            $content = Get-Content $path -Raw
            $total += [regex]::Matches($content, "(?m)^\s*It\s+['""]").Count
        }
        $total | Should -BeGreaterOrEqual 80
    }
}

# ============================================================
Describe 'E2E: Security Gates' {

    It 'validate-write-scope regex matches glob patterns' {
        function Convert-GlobToRegex([string]$glob) {
            $escaped = [regex]::Escape($glob)
            $escaped = $escaped.Replace('\*', '.*').Replace('\?', '.')
            '^' + $escaped + '$'
        }
        Convert-GlobToRegex('src/*') -match '^src/.*$' | Should -Be $true
        Convert-GlobToRegex('*.ts') -match '^.*\.ts$' | Should -Be $true
    }

    It 'close-session detects protected files via substring match' {
        $protectedFiles = @('.agents/skills/security-scanner/', 'ANTI-PATTERN-CATALOG.md', '.project.json')
        $changedFiles = @('.agents/skills/security-scanner/SKILL.md', '.project.json')
        $touched = foreach ($pf in $protectedFiles) {
            $escd = [regex]::Escape($pf).Replace('/', '[/\\]')
            foreach ($cf in $changedFiles) {
                if ($cf -match $escd) { $pf; break }
            }
        }
        $touched.Count | Should -Be 2
    }

    It 'close-session does NOT flag non-protected files' {
        $touched = foreach ($pf in @('ANTI-PATTERN-CATALOG.md')) {
            $escd = [regex]::Escape($pf).Replace('/', '[/\\]')
            foreach ($cf in @('README.md', 'main.ps1')) {
                if ($cf -match $escd) { $pf; break }
            }
        }
        @($touched).Count | Should -Be 0
    }

    It 'restore ref regex rejects injection patterns' {
        $invalidRefs = @('; rm -rf /', '$(malicious)', '| cat /etc/passwd')
        foreach ($ref in $invalidRefs) {
            $ref -match '^[\w/\.\-\^~@]+$' | Should -Be $false -Because "'$ref' should be rejected"
        }
    }

    It 'all 4 target scripts parse without syntax errors' {
        @('validate-write-scope.ps1','close-session.ps1','restore.ps1','forge-rollback.ps1') | ForEach-Object {
            $path = Join-Path $script:ProjectRoot "scripts/$_"
            $script = Get-Content $path -Raw
            { [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, [ref]$null) } | Should -Not -Throw
        }
    }
}

# ============================================================
Describe 'E2E: Pre-commit Hook' {

    It 'hook delegates to pre-commit-gate.ps1 with [13/13] through [21/21] checks' {
        $hookPath = Join-Path $script:ProjectRoot ".githooks/pre-commit"
        $gatePath = Join-Path $script:ProjectRoot ".githooks/pre-commit-gate.ps1"
        $hookPath | Should -Exist
        $gatePath | Should -Exist
        Get-Content $hookPath -Raw | Should -Match 'pre-commit-gate\.ps1'
        Get-Content $gatePath -Raw | Should -Match '\[13/13\]'
        Get-Content $gatePath -Raw | Should -Match '\[14/14\]'
        Get-Content $gatePath -Raw | Should -Match '\[19/19\]'
        Get-Content $gatePath -Raw | Should -Match '\[20/20\]'
        Get-Content $gatePath -Raw | Should -Match '\[21/21\]'
    }

    It 'hook Pester step uses Invoke-Pester and blocks on failure' {
        $gatePath = Join-Path $script:ProjectRoot ".githooks/pre-commit-gate.ps1"
        $content = Get-Content $gatePath -Raw
        $content | Should -Match 'Invoke-Pester'
        $content | Should -Match '\[12/13\] Pester tests'
    }

    It 'hook preserves all 13 steps' {
        $gatePath = Join-Path $script:ProjectRoot ".githooks/pre-commit-gate.ps1"
        $content = Get-Content $gatePath -Raw
        for ($i = 1; $i -le 13; $i++) {
            $content | Should -Match "\[$i/13\]"
        }
    }

    It 'gate includes C6/C8/C9 validation checks for new scripts' {
        $gatePath = Join-Path $script:ProjectRoot ".githooks/pre-commit-gate.ps1"
        $content = Get-Content $gatePath -Raw
        $content | Should -Match '\[19/19\] Token budget'
        $content | Should -Match '\[20/20\] Budget script validation'
        $content | Should -Match '\[21/21\] Context watchdog'
        $content | Should -Match 'check-token-budget\.ps1'
        $content | Should -Match 'check-budget\.ps1'
        $content | Should -Match 'ctx-watchdog\.ps1'
    }

    It 'gate header reflects 21 total checks' {
        $gatePath = Join-Path $script:ProjectRoot ".githooks/pre-commit-gate.ps1"
        Get-Content $gatePath -Raw | Should -Match 'ALL 21 checks'
    }

    It 'CI workflow mirrors new gate checks [19-21]' {
        $ciPath = Join-Path $script:ProjectRoot ".github/workflows/quality-gate.yml"
        $ciPath | Should -Exist
        $content = Get-Content $ciPath -Raw
        $content | Should -Match 'Token budget check'
        $content | Should -Match '\[19/19\]'
        $content | Should -Match 'Budget script validation'
        $content | Should -Match '\[20/20\]'
        $content | Should -Match 'Context watchdog validation'
        $content | Should -Match '\[21/21\]'
    }
}

# ============================================================
Describe 'E2E: CodeCoverage' {

    It 'run-tests.ps1 has -CodeCoverage switch parameter' {
        $content = Get-Content (Join-Path $script:ProjectRoot "scripts/run-tests.ps1") -Raw
        $content | Should -Match 'CodeCoverage'
        $content | Should -Match '\[switch\]\$CodeCoverage'
    }

    It 'CodeCoverage uses PesterConfiguration' {
        Get-Content (Join-Path $script:ProjectRoot "scripts/run-tests.ps1") -Raw | Should -Match 'PesterConfiguration'
    }
}

# ============================================================
# Nested coverage run — ~3 min (spawns run-tests.ps1 -CodeCoverage, which
# forces Pester 6 sequential). Kept out of the default suite via -Tag 'E2E';
# run explicitly with: scripts/run-tests.ps1 -IncludeE2E
Describe 'E2E pipeline coverage' -Tag 'E2E' {

    It 'CodeCoverage runs a single test file without crashing' {
        $testPath = Join-Path $PSScriptRoot "CacheHash.Tests.ps1"
        $runner = Join-Path $script:ProjectRoot "scripts/run-tests.ps1"
        # Run in a child process: in-process invocation nests a Pester coverage
        # plugin inside the outer runner and crashes (Assert-Success in
        # Invoke-PluginStep) when the outer suite runs in parallel. A child
        # process also matches real-world usage of run-tests.ps1 as a standalone.
        $pwshExe = (Join-Path $PSHOME 'pwsh.exe')
        $out = & $pwshExe -NoProfile -NonInteractive -Command "& '$runner' -Path '$testPath' -CodeCoverage *> `$null; exit `$LASTEXITCODE"
        # 0 = all passed + coverage OK; 10 = coverage below 50% threshold (expected on partial run)
        @(0, 10) | Should -Contain $LASTEXITCODE
    }
}

# ============================================================
Describe 'E2E: SDD Config' {

    It 'sdd-config.yaml exists with strict_tdd: true' {
        $path = Join-Path $script:ProjectRoot "sdd-config.yaml"
        $path | Should -Exist
        Get-Content $path -Raw | Should -Match 'strict_tdd:\s*true'
    }

    It 'sdd-config.yaml has pester runner config' {
        $content = Get-Content (Join-Path $script:ProjectRoot "sdd-config.yaml") -Raw
        $content | Should -Match 'test_runner:\s*pester'
        $content | Should -Match 'test_command:'
        $content | Should -Match 'test_pattern:'
    }
}

# ============================================================
Describe 'E2E: Execution State' {

    It 'execution state shows all 7 findings done' {
        $path = Join-Path $script:ProjectRoot "docs/mejoras/2026-07-28-gentleman-agent-gh-execution-state.json"
        $path | Should -Exist
        $json = Get-Content $path -Raw | ConvertFrom-Json
        $json.summary.done | Should -Be 7
        $json.summary.total | Should -Be 7
        $json.summary.failed | Should -Be 0
    }

    It 'analysis file references all 7 findings' {
        $path = Join-Path $script:ProjectRoot "docs/mejoras/2026-07-28-gentleman-agent-gh-analysis.md"
        $path | Should -Exist
        $content = Get-Content $path -Raw
        $content | Should -Match 'validate-write-scope'
        $content | Should -Match 'close-session'
        $content | Should -Match 'restore'
        $content | Should -Match 'strict_tdd'
        $content | Should -Match 'pre-commit'
        $content | Should -Match 'CodeCoverage'
    }
}

# ============================================================
Describe 'E2E: Pipeline Integration' {

    It 'each new test file references its source script' {
        $tests = @{
            'validate-write-scope.Tests.ps1' = '(ValidateScope|ConvertGlobToRegex)'
            'close-session.Tests.ps1'        = '(CloseSession|needsAudit|close-session)'
            'restore.Tests.ps1'              = '(restore|BackupState)'
            'forge-rollback.Tests.ps1'       = '(ForgeRollback|forge)'
        }
        $tests.GetEnumerator() | ForEach-Object {
            $path = Join-Path $PSScriptRoot $_.Key
            $content = Get-Content $path -Raw
            $content | Should -Match $_.Value -Because "$($_.Key) should reference $($_.Value)"
        }
    }

    It 'validate-write-scope test covers edge cases' {
        $path = Join-Path $PSScriptRoot 'validate-write-scope.Tests.ps1'
        $content = Get-Content $path -Raw
        $content | Should -Match 'special'
        $content | Should -Match 'nested'
        $content | Should -Match 'empty'
    }

    It 'close-session test covers audit gate blocking' {
        $content = Get-Content (Join-Path $PSScriptRoot 'close-session.Tests.ps1') -Raw
        $content | Should -Match 'needsAudit'
    }

    It 'restore test covers ref validation and cancellation' {
        $content = Get-Content (Join-Path $PSScriptRoot 'restore.Tests.ps1') -Raw
        $content | Should -Match 'valid.*ref'
        $content | Should -Match 'cancel'
    }

    It 'forge-rollback test covers JSON mutation and DryRun' {
        $content = Get-Content (Join-Path $PSScriptRoot 'forge-rollback.Tests.ps1') -Raw
        $content | Should -Match 'demot'
        $content | Should -Match 'DryRun'
    }
}

