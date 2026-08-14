#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Tests for audit-log CSV formula-injection hardening (Gap 1, C3a security subset).
.DESCRIPTION
    Verifies that audit-log.ps1's append path escapes Detail through
    ConvertTo-SafeCsvField so that spreadsheet formula payloads are never
    written as live formulas and row structure cannot be broken.
    Runs E2E in-process against the real script, isolated to Pester's
    $TestDrive (no .git above it → Get-GentlemanProjectRoot resolves there),
    so the real repo's .gentleman/audit.log is never touched.

    Run: Invoke-Pester .\scripts\tests\audit-log.Tests.ps1
    Run quiet: Invoke-Pester .\scripts\tests\audit-log.Tests.ps1 -- -Quiet
#>
param([switch]$Quiet)

BeforeAll {
    $auditLog = Join-Path (Split-Path $PSScriptRoot -Parent) 'audit-log.ps1'
    $testLog  = Join-Path $TestDrive '.gentleman\audit.log'

    function Get-LastQuotedField {
        param([string]$Line)
        # The Detail field is the only quoted field and is always trailing.
        $m = [regex]::Match($Line, '"(?:[^"]|"")*"$')
        return $m
    }
}

Describe "CSV formula injection — append path escapes Detail" {
    It "writes the row and quotes the Detail field" {
        Push-Location 'TestDrive:\'
        try {
            & $auditLog append -agent 'testagent' -mode auto -action ALLOW -detail 'git status'
            $line = Get-Content -LiteralPath $testLog -Tail 1
            $m = Get-LastQuotedField -Line $line
            $m.Success | Should -BeTrue
            $m.Value.StartsWith('"') | Should -BeTrue
            $m.Value.EndsWith('"')   | Should -BeTrue
        } finally { Pop-Location }
    }

    It "neutralizes leading '=' payload: =2+5" {
        Push-Location 'TestDrive:\'
        try {
            & $auditLog append -agent 'testagent' -mode auto -action ALLOW -detail '=2+5'
            $line = Get-Content -LiteralPath $testLog -Tail 1
            $inner = ((Get-LastQuotedField -Line $line).Value).Trim('"') -replace '""', '"'
            $inner -notmatch '^[=+\-@]' | Should -BeTrue
        } finally { Pop-Location }
    }

    It "neutralizes leading '+' payload: +HYPERLINK()" {
        Push-Location 'TestDrive:\'
        try {
            & $auditLog append -agent 'testagent' -mode auto -action ALLOW -detail '+HYPERLINK("https://evil")'
            $line = Get-Content -LiteralPath $testLog -Tail 1
            $inner = ((Get-LastQuotedField -Line $line).Value).Trim('"') -replace '""', '"'
            $inner -notmatch '^[=+\-@]' | Should -BeTrue
        } finally { Pop-Location }
    }

    It "neutralizes leading '-' payload: -1+1" {
        Push-Location 'TestDrive:\'
        try {
            & $auditLog append -agent 'testagent' -mode auto -action ALLOW -detail '-1+1'
            $line = Get-Content -LiteralPath $testLog -Tail 1
            $inner = ((Get-LastQuotedField -Line $line).Value).Trim('"') -replace '""', '"'
            $inner -notmatch '^[=+\-@]' | Should -BeTrue
        } finally { Pop-Location }
    }

    It "neutralizes leading '@' payload: @SUM(A:A)" {
        Push-Location 'TestDrive:\'
        try {
            & $auditLog append -agent 'testagent' -mode auto -action ALLOW -detail '@SUM(A:A)'
            $line = Get-Content -LiteralPath $testLog -Tail 1
            $inner = ((Get-LastQuotedField -Line $line).Value).Trim('"') -replace '""', '"'
            $inner -notmatch '^[=+\-@]' | Should -BeTrue
        } finally { Pop-Location }
    }

    It 'neutralizes embedded-quote payload: ="cmd"' {
        Push-Location 'TestDrive:\'
        try {
            & $auditLog append -agent 'testagent' -mode auto -action ALLOW -detail '="cmd"'
            $line = Get-Content -LiteralPath $testLog -Tail 1
            $m = Get-LastQuotedField -Line $line
            $m.Success | Should -BeTrue
            # embedded quote must be RFC-4180 doubled inside the field
            $m.Value.Contains('""') | Should -BeTrue
            $inner = $m.Value.Trim('"') -replace '""', '"'
            $inner -notmatch '^[=+\-@]' | Should -BeTrue
        } finally { Pop-Location }
    }

    It "neutralizes tab-prefixed formula payload" {
        Push-Location 'TestDrive:\'
        try {
            & $auditLog append -agent 'testagent' -mode auto -action ALLOW -detail "`t=cmd"
            $line = Get-Content -LiteralPath $testLog -Tail 1
            $m = Get-LastQuotedField -Line $line
            $m.Success | Should -BeTrue
            $inner = $m.Value.Trim('"')
            $inner -notmatch '\t'           | Should -BeTrue   # tab collapsed
            $inner -notmatch '^[=+\-@]'     | Should -BeTrue   # no live formula trigger
        } finally { Pop-Location }
    }

    It "breaks up embedded CR/LF so the row stays single-line" {
        Push-Location 'TestDrive:\'
        try {
            $before = @(Get-Content -LiteralPath $testLog -ErrorAction SilentlyContinue).Count
            & $auditLog append -agent 'testagent' -mode auto -action ALLOW -detail "evil`r`n=1"
            $all = @(Get-Content -LiteralPath $testLog)
            $all.Count | Should -Be ($before + 1)     # exactly one new row, no spray
            $all[-1] -match '=1'                       | Should -BeTrue   # payload present...
            @($all | Where-Object { $_ -match '^=1' }).Count | Should -Be 0 # ...but never as its own row
            $all[-1] -notmatch '\r|\n'                 | Should -BeTrue   # no embedded newline survives
        } finally { Pop-Location }
    }
}

Describe "Audit log read/session mode — new quoted format still parses" {
    It "session's ', ALLOW,' counter regex still matches the quoted row" {
        Push-Location 'TestDrive:\'
        try {
            & $auditLog append -agent 'testagent' -mode auto -action ALLOW -detail 'git status'
            $line = Get-Content -LiteralPath $testLog -Tail 1
            # Same pattern the session block uses to tally ALLOW rows
            ($line -match ', ALLOW,')  | Should -BeTrue
            # Same boundary pattern the session/read blocks key on
            ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') | Should -BeTrue
        } finally { Pop-Location }
    }

    It "does not break filtering in read mode" {
        Push-Location 'TestDrive:\'
        try {
            & $auditLog append -agent 'testagent' -mode auto -action DENY -detail 'rm -rf /x'
            $lines = @(Get-Content -LiteralPath $testLog | Where-Object { $_ -match 'DENY' })
            $lines.Count | Should -BeGreaterThan 0
            $lines[0] -match 'DENY' | Should -BeTrue
        } finally { Pop-Location }
    }
}
