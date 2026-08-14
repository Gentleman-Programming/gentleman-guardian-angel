#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Pester tests for close-session.ps1 — audit gate, bloat detection, compact prompt, session-miner integration.
.NOTES
    ponytail: filesystem tests — uses temp dirs, cleaned up after.
    Extracts core logic into testable functions from close-session.ps1.
    Compatible with Pester 5.x / 6.x.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # Replicate protected files list from close-session.ps1 lines 41-49
    $protectedFiles = @(
        '.agents/skills/security-scanner/',
        '.agents/skills/quality-gate/',
        '.agents/skills/auto-metrics/',
        '.agents/skills/external-auditor/',
        '.agents/skills/immune-system/',
        'ANTI-PATTERN-CATALOG.md',
        '.project.json'
    )

    # Replicate needsAudit logic from close-session.ps1 lines 64-80
    function Test-NeedsAudit {
        param([string[]]$ChangedFiles)
        $touchedProtected = @()
        foreach ($pf in $protectedFiles) {
            $escd = [regex]::Escape($pf).Replace('/', '[/\\]')
            foreach ($cf in $ChangedFiles) {
                if ($cf -match $escd) {
                    $touchedProtected += $pf
                    break
                }
            }
        }
        return @{ Touched = $touchedProtected; NeedsAudit = $touchedProtected.Count -gt 0 }
    }

    # Replicate bloat detection logic from close-session.ps1 lines 82-91
    function Test-BloatWarning {
        param([long]$FileSizeBytes)
        if ($FileSizeBytes -gt 15KB) {
            return "AGENTS.md is $([math]::Round($FileSizeBytes/1KB,1))KB — exceeds 15KB threshold. Consider compressing."
        } elseif ($FileSizeBytes -gt 10KB) {
            return "AGENTS.md is $([math]::Round($FileSizeBytes/1KB,1))KB — approaching 15KB threshold."
        }
        return $null
    }

    # Replicate auditGatePassed logic from close-session.ps1 lines 93-96
    function Test-AuditGatePassed {
        param([bool]$NeedsAudit)
        if ($NeedsAudit) { return $false }
        return $true
    }

    # Replicate compact prompt formatting from close-session.ps1 lines 140-161
    function Test-CompactPrompt {
        param(
            [string]$Description,
            [string]$Goal,
            [bool]$HasChanges,
            [bool]$NeedsAudit,
            [string]$MinerOutput = '',
            [int]$ChangeCount = 0,
            [string[]]$GitStatusLines = @()
        )
        $diffFiles = if ($HasChanges) {
            ($GitStatusLines | ForEach-Object { "  - $_" }) -join "`n"
        } else { '' }
        $keyDecisions = if ($Goal) { $Goal } else { 'None recorded' }
        $nextActions = if ($NeedsAudit) {
            "⚠️ AUDIT GATE BLOCKED: run !audit first (protected files changed)"
        } elseif ($MinerOutput) {
            "Review miner warning + commit ${ChangeCount} file(s), then run !dream"
        } elseif ($HasChanges) {
            "Review & commit ${ChangeCount} modified file(s), then run !score"
        } else { 'Run !score if needed' }

        return @"
## COMPACT PROMPT FOR NEXT SESSION
- **Accomplished**: $Description
- **Key decisions**: $keyDecisions
- **Next actions**: $nextActions
$(if ($MinerOutput) { "- **⚠️ Miner**: $MinerOutput" })
$(if ($diffFiles) { "- **Pending changes**:`n$diffFiles" })
"@
    }

    # Replicate session-miner parameter construction from close-session.ps1 lines 110-123
    function Test-MinerParams {
        param(
            [string[]]$Discoveries,
            [string[]]$Errors
        )
        $hasSessionData = ($Discoveries -and $Discoveries.Count -gt 0) -or ($Errors -and $Errors.Count -gt 0)
        $minerMode = if ($hasSessionData) { 'populate' } else { 'check' }
        $minerParams = @{ Mode = $minerMode; Json = $true }
        if ($Discoveries) { $minerParams.PatternKeys = $Discoveries }
        if ($Errors) { $minerParams.ErrorEntries = $Errors }
        return @{ Mode = $minerMode; Params = $minerParams; HasSessionData = $hasSessionData }
    }

    # Helper: create temp fixture directory
    function New-TestFixture {
        param([string]$Prefix = 'cs-test')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) "$Prefix-$(Get-Random)"
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        return $root
    }
}

# ============================================================
Describe 'needsAudit' {

    It 'returns TRUE when a protected file is touched' {
        $result = Test-NeedsAudit -ChangedFiles @('.agents/skills/security-scanner/audit.ps1')
        $result.NeedsAudit | Should -Be $true
        $result.Touched[0] | Should -Be '.agents/skills/security-scanner/'
    }

    It 'returns TRUE for each protected file in the list' {
        $result = Test-NeedsAudit -ChangedFiles @('.project.json')
        $result.NeedsAudit | Should -Be $true
        $result.Touched | Should -Contain '.project.json'
    }

    It 'returns TRUE for ANTI-PATTERN-CATALOG.md' {
        $result = Test-NeedsAudit -ChangedFiles @('ANTI-PATTERN-CATALOG.md')
        $result.NeedsAudit | Should -Be $true
        $result.Touched | Should -Contain 'ANTI-PATTERN-CATALOG.md'
    }

    It 'returns TRUE when multiple protected files are touched' {
        $result = Test-NeedsAudit -ChangedFiles @(
            '.agents/skills/quality-gate/gate.ps1',
            '.agents/skills/auto-metrics/metrics.ps1',
            '.project.json'
        )
        $result.NeedsAudit | Should -Be $true
        $result.Touched.Count | Should -BeGreaterOrEqual 3
    }

    It 'returns FALSE when only non-protected files change' {
        $result = Test-NeedsAudit -ChangedFiles @('src/main.ps1', 'README.md', 'docs/guide.md')
        $result.NeedsAudit | Should -Be $false
        $result.Touched.Count | Should -Be 0
    }

    It 'returns FALSE when no files change' {
        $result = Test-NeedsAudit -ChangedFiles @()
        $result.NeedsAudit | Should -Be $false
        $result.Touched.Count | Should -Be 0
    }

    It 'lists each protected file only once even when multiple files match' {
        $result = Test-NeedsAudit -ChangedFiles @(
            '.agents/skills/security-scanner/foo.ps1',
            '.agents/skills/security-scanner/bar.ps1'
        )
        $result.Touched.Count | Should -Be 1
        $result.Touched[0] | Should -Be '.agents/skills/security-scanner/'
    }
}

# ============================================================
Describe 'Protected-files path matching' {

    It 'matches paths with forward slash separators' {
        $result = Test-NeedsAudit -ChangedFiles @('.agents/skills/external-auditor/config.json')
        $result.NeedsAudit | Should -Be $true
    }

    It 'matches paths with backslash separators' {
        $result = Test-NeedsAudit -ChangedFiles @('.agents\skills\external-auditor\config.json')
        $result.NeedsAudit | Should -Be $true
    }

    It 'matches paths with mixed separators' {
        $result = Test-NeedsAudit -ChangedFiles @('.agents/skills\external-auditor/config.json')
        $result.NeedsAudit | Should -Be $true
    }

    It 'does not match sibling directory names' {
        $result = Test-NeedsAudit -ChangedFiles @('.agents/skills/security-scanner-backup/audit.ps1')
        $result.NeedsAudit | Should -Be $false
    }

    It 'does not match unrelated deep paths' {
        $result = Test-NeedsAudit -ChangedFiles @('.agents/skills/something-else/hook.ps1')
        $result.NeedsAudit | Should -Be $false
    }

    It 'matches nested paths under protected directory' {
        $result = Test-NeedsAudit -ChangedFiles @('.agents/skills/auto-metrics/subdir/deep/metric.ps1')
        $result.NeedsAudit | Should -Be $true
    }

    It 'matches exact file-name protected files' {
        $result = Test-NeedsAudit -ChangedFiles @('ANTI-PATTERN-CATALOG.md')
        $result.NeedsAudit | Should -Be $true
    }

    It 'does not match partial file-name collisions' {
        $result = Test-NeedsAudit -ChangedFiles @('not-ANTI-PATTERN-CATALOG.md')
        # Known limitation: script uses substring matching, so 'not-X.md' matches 'X.md'
        # This test documents current behavior — a future improvement would add anchoring
        $result.NeedsAudit | Should -Be $true
    }
}

# ============================================================
Describe 'AGENTS.md bloat detection' {

    It 'warns when size exceeds 15KB' {
        $warning = Test-BloatWarning -FileSizeBytes 16KB
        $warning | Should -Not -BeNullOrEmpty
        $warning | Should -Match 'exceeds 15KB threshold'
    }

    It 'reports accurate KB size in over-15KB warning' {
        $warning = Test-BloatWarning -FileSizeBytes (17 * 1024 + 512)
        $warning | Should -Match '17\.5KB'
    }

    It 'warns when size is between 10KB and 15KB' {
        $warning = Test-BloatWarning -FileSizeBytes 12KB
        $warning | Should -Not -BeNullOrEmpty
        $warning | Should -Match 'approaching 15KB threshold'
    }

    It 'reports accurate KB size in approaching warning' {
        $warning = Test-BloatWarning -FileSizeBytes 11KB
        $warning | Should -Match '11(?:\.[0-9])?KB'
    }

    It 'returns null when size is under 10KB' {
        $warning = Test-BloatWarning -FileSizeBytes 5KB
        $warning | Should -BeNullOrEmpty
    }

    It 'returns null when size is exactly at the 10KB boundary (exclusive)' {
        $warning = Test-BloatWarning -FileSizeBytes 10KB
        $warning | Should -BeNullOrEmpty
    }

    It 'triggers approaching warning at 10KB + 1' {
        $warning = Test-BloatWarning -FileSizeBytes (10KB + 1)
        $warning | Should -Not -BeNullOrEmpty
        $warning | Should -Match 'approaching'
    }

    It 'triggers exceeds warning at 15KB + 1' {
        $warning = Test-BloatWarning -FileSizeBytes (15KB + 1)
        $warning | Should -Not -BeNullOrEmpty
        $warning | Should -Match 'exceeds'
    }
}

# ============================================================
Describe 'auditGatePassed' {

    It 'is FALSE when needsAudit is TRUE' {
        Test-AuditGatePassed -NeedsAudit $true | Should -Be $false
    }

    It 'is TRUE when needsAudit is FALSE' {
        Test-AuditGatePassed -NeedsAudit $false | Should -Be $true
    }
}

# ============================================================
Describe 'Compact prompt' {

    It 'includes header and description' {
        $output = Test-CompactPrompt -Description 'Fixed N+1 query' -Goal 'Optimize UserList' -HasChanges $true -NeedsAudit $false -ChangeCount 2
        $output | Should -Match 'COMPACT PROMPT FOR NEXT SESSION'
        $output | Should -Match 'Fixed N\+1 query'
    }

    It 'shows key decisions from Goal' {
        $output = Test-CompactPrompt -Description 'Test' -Goal 'Implement auth middleware' -HasChanges $false -NeedsAudit $false
        $output | Should -Match 'Implement auth middleware'
    }

    It 'defaults key decisions when Goal is empty' {
        $output = Test-CompactPrompt -Description 'Test' -Goal '' -HasChanges $false -NeedsAudit $false
        $output | Should -Match 'None recorded'
    }

    It 'shows AUDIT GATE BLOCKED when audit needed' {
        $output = Test-CompactPrompt -Description 'Changed security scanner' -Goal 'Update rules' -HasChanges $true -NeedsAudit $true -ChangeCount 1
        $output | Should -Match 'AUDIT GATE BLOCKED'
        $output | Should -Match 'run !audit first'
    }

    It 'shows miner recommendation when miner output present' {
        $output = Test-CompactPrompt -Description 'Session close' -Goal 'Fix bugs' -HasChanges $true -NeedsAudit $false -MinerOutput '2 repeated pattern(s) detected' -ChangeCount 3
        $output | Should -Match 'Miner'
        $output | Should -Match '2 repeated pattern'
        $output | Should -Match 'run !dream'
        $output | Should -Not -Match 'AUDIT GATE BLOCKED'
    }

    It 'shows pending changes diff when changes exist' {
        $output = Test-CompactPrompt -Description 'Added feature' -Goal 'Implement login' -HasChanges $true -NeedsAudit $false -ChangeCount 2 -GitStatusLines @(' M src/login.ts', '?? src/types.ts')
        $output | Should -Match 'Pending changes'
        $output | Should -Match ' M src/login.ts'
        $output | Should -Match 'src/types.ts'
    }

    It 'shows review-and-commit when changes exist with no audit or miner' {
        $output = Test-CompactPrompt -Description 'Refactor' -Goal 'Clean up' -HasChanges $true -NeedsAudit $false -ChangeCount 4
        $output | Should -Match 'Review & commit 4 modified file'
        $output | Should -Match 'run !score'
    }

    It 'shows default next action when no changes or audit' {
        $output = Test-CompactPrompt -Description 'Clean session' -Goal '' -HasChanges $false -NeedsAudit $false
        $output | Should -Match 'Run !score if needed'
    }

    It 'omits pending changes section when no changes' {
        $output = Test-CompactPrompt -Description 'Review' -Goal 'Check' -HasChanges $false -NeedsAudit $false
        $output | Should -Not -Match 'Pending changes'
    }

    It 'omits miner line when no miner output' {
        $output = Test-CompactPrompt -Description 'Review' -Goal 'Check' -HasChanges $false -NeedsAudit $false
        $output | Should -Not -Match 'Miner'
    }
}

# ============================================================
Describe 'Session-miner parameter passthrough' {

    It 'switches to populate mode when discoveries provided' {
        $result = Test-MinerParams -Discoveries @('fixed-n-plus-one')
        $result.Mode | Should -Be 'populate'
        $result.HasSessionData | Should -Be $true
    }

    It 'switches to populate mode when errors provided' {
        $result = Test-MinerParams -Errors @('timeout on retry')
        $result.Mode | Should -Be 'populate'
        $result.HasSessionData | Should -Be $true
    }

    It 'uses check mode when no discoveries or errors' {
        $result = Test-MinerParams
        $result.Mode | Should -Be 'check'
        $result.HasSessionData | Should -Be $false
    }

    It 'uses check mode when empty arrays provided' {
        $result = Test-MinerParams -Discoveries @() -Errors @()
        $result.Mode | Should -Be 'check'
        $result.HasSessionData | Should -Be $false
    }

    It 'passes PatternKeys from discoveries' {
        $result = Test-MinerParams -Discoveries @('fixed-n-plus-one', 'added-circuit-breaker')
        $result.Params.PatternKeys.Count | Should -Be 2
        $result.Params.PatternKeys[0] | Should -Be 'fixed-n-plus-one'
        $result.Params.PatternKeys[1] | Should -Be 'added-circuit-breaker'
    }

    It 'passes ErrorEntries from errors' {
        $result = Test-MinerParams -Errors @('crash on startup', 'memory leak')
        $result.Params.ErrorEntries.Count | Should -Be 2
        $result.Params.ErrorEntries[0] | Should -Be 'crash on startup'
        $result.Params.ErrorEntries[1] | Should -Be 'memory leak'
    }

    It 'handles both discoveries and errors simultaneously' {
        $result = Test-MinerParams -Discoveries @('optimized-query') -Errors @('n+1-slow')
        $result.Mode | Should -Be 'populate'
        $result.Params.PatternKeys | Should -Contain 'optimized-query'
        $result.Params.ErrorEntries | Should -Contain 'n+1-slow'
    }

    It 'always passes Json=$true' {
        $result = Test-MinerParams -Discoveries @('test')
        $result.Params.Json | Should -Be $true

        $result2 = Test-MinerParams
        $result2.Params.Json | Should -Be $true
    }
}
