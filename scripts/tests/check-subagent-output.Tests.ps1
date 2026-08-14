#requires -Version 7

<#
.SYNOPSIS
    Tests for C4d: 4-field return contract validation in check-subagent-output.ps1.
.DESCRIPTION
    Validates that Validate-AgentReturnContract correctly checks subagent output
    for all 4 required sections: Decision Taken, Files Changed, Key Findings, Nuance.
    Also tests end-to-end via pwsh invocation of the script with -AgentOutput.

    Run: Invoke-Pester .\scripts\tests\check-subagent-output.Tests.ps1
#>

Describe "Validate-AgentReturnContract — function logic (C4d)" {
    BeforeAll {
        # Inline copy of Validate-AgentReturnContract (C4d) — mirrors scripts/check-subagent-output.ps1
        function Validate-AgentReturnContract {
            param([string]$Output, [string]$AgentName = "unknown")
            $requiredHeaders = @('## Decision Taken', '## Files Changed', '## Key Findings', '## Nuance')
            $missing = @()
            $empty   = @()
            foreach ($h in $requiredHeaders) {
                if ($Output -notmatch [regex]::Escape($h)) { $missing += $h }
            }
            if ($missing.Count -eq 0) {
                $lines  = $Output -split '\r?\n'
                $current = ""
                $sections = @{}
                foreach ($line in $lines) {
                    if ($line -match '^## ') {
                        $current = $line
                        $sections[$current] = @()
                    } elseif ($current) {
                        $sections[$current] += $line
                    }
                }
                foreach ($h in $requiredHeaders) {
                    $content = $sections[$h]
                    if ($content) {
                        $hasContent = @($content | Where-Object { $_.Trim() })
                        if ($hasContent.Count -eq 0) { $empty += $h }
                    } else {
                        $empty += $h
                    }
                }
            }
            return [PSCustomObject]@{
                valid   = ($missing.Count -eq 0 -and $empty.Count -eq 0)
                agent   = $AgentName
                missing = $missing
                empty   = $empty
            }
        }
    }

    It "accepts valid 4-field output" {
        $out = @"
## Decision Taken
Implemented C4d fix
## Files Changed
src/utils.ts
## Key Findings
1. [HIGH] Finding — Evidence — Recommendation
## Nuance
Edge case noted
"@
        $r = Validate-AgentReturnContract -Output $out
        $r.valid   | Should -BeTrue
        $r.missing | Should -Be @()
        $r.empty   | Should -Be @()
    }

    It "detects missing Nuance section" {
        $out = @"
## Decision Taken
Done
## Files Changed
file.ts
## Key Findings
1. [HIGH] Finding
"@
        $r = Validate-AgentReturnContract -Output $out
        $r.valid   | Should -BeFalse
        $r.missing | Should -Contain '## Nuance'
    }

    It "detects empty Key Findings section (header present, no content)" {
        $out = @"
## Decision Taken
Done
## Files Changed
file.ts
## Key Findings

## Nuance
Note
"@
        $r = Validate-AgentReturnContract -Output $out
        $r.valid  | Should -BeFalse
        $r.empty  | Should -Contain '## Key Findings'
    }

    It "rejects completely empty output" {
        $r = Validate-AgentReturnContract -Output ""
        $r.valid   | Should -BeFalse
        $r.missing | Should -HaveCount 4
    }
}

Describe "check-subagent-output.ps1 — contract validation flag in Quiet mode (C4d)" {
    BeforeAll {
        $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'check-subagent-output.ps1'
    }

    It "reports contract_valid=true for well-formed output" {
        $valid = "## Decision Taken`nFix C4d`n## Files Changed`nsrc/x.ts`n## Key Findings`n1. [HIGH] f`n## Nuance`nok"
        $tmpFile = Join-Path $TestDrive 'agent_out.txt'
        Set-Content -Path $tmpFile -Value $valid -NoNewline
        # SAFE transport: read content in-process and pass as a real argument to the
        # child script via -File, instead of double-interpolating the agent output
        # inside a -Command string (which corrupts content containing quotes/`/'$').
        $content = Get-Content -Raw -Path $tmpFile
        $json = & pwsh -NoProfile -File $scriptPath -Quiet -AgentOutput $content | ConvertFrom-Json -ErrorAction SilentlyContinue
        $json.contract_valid | Should -BeTrue
    }

    It "reports contract_valid=false for missing Nuance" {
        $bad = "## Decision Taken`nFix`n## Files Changed`nsrc/x.ts`n## Key Findings`n1. [HIGH] f"
        $tmpFile = Join-Path $TestDrive 'agent_out_bad.txt'
        Set-Content -Path $tmpFile -Value $bad -NoNewline
        $content = Get-Content -Raw -Path $tmpFile
        # SAFE transport: see note in the well-formed test above.
        $json = & pwsh -NoProfile -File $scriptPath -Quiet -AgentOutput $content | ConvertFrom-Json -ErrorAction SilentlyContinue
        $json.contract_valid | Should -BeFalse
    }
}

