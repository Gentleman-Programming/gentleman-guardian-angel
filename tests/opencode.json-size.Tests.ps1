#requires -Version 7
<#
.SYNOPSIS ADR-007 — opencode.json size budget (INFRA-2)
.DESCRIPTION Verifies the 65,536 B size-budget logic enforced by pre-commit
  gate check [17/17] and the "Config size budget" CI step. Pure logic tests
  against temp files only — the live opencode.json is never read or mutated.
#>
param(
    [int]$budget = 65536
)

Describe 'opencode.json size budget (ADR-007)' {
    It 'passes when config is under budget' {
        $path = Join-Path $TestDrive 'config-under.json'
        [System.IO.File]::WriteAllBytes($path, [byte[]]::new(60000))
        $size = (Get-Item -LiteralPath $path).Length
        ($size -le $budget) | Should -BeTrue
    }

    It 'fails when config exceeds budget' {
        $path = Join-Path $TestDrive 'config-over.json'
        [System.IO.File]::WriteAllBytes($path, [byte[]]::new(66000))
        $size = (Get-Item -LiteralPath $path).Length
        ($size -le $budget) | Should -BeFalse
    }
}