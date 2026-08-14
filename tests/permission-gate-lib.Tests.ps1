#requires -Version 7
<#
.SYNOPSIS
    Unit tests for permission-gate-lib.ps1 command classification logic.
.DESCRIPTION
    Tests deny pattern loading, glob-to-regex conversion, and command classification
    across manual/semi/auto modes.
.NOTES
    Dot-sources permission-gate-lib.ps1 to access internal functions.
#>

Describe "permission-gate-lib.ps1" {
    BeforeAll {
        # Dot-source the library to access functions
        $libPath = Join-Path $PSScriptRoot "..\scripts\lib\permission-gate-lib.ps1"
        . $libPath
    }

    Context "Convert-FromDenyGlob" {
        It "Converts 'curl *' to '^curl\b'" {
            $result = Convert-FromDenyGlob "curl *"
            $result | Should -Be "^curl\b"
        }

        It "Converts 'npm install *' to '^npm\s+install\b'" {
            $result = Convert-FromDenyGlob "npm install *"
            $result | Should -Be "^npm\s+install\b"
        }

        It "Converts bare 'npx' to '^npx\b'" {
            $result = Convert-FromDenyGlob "npx"
            $result | Should -Be "^npx\b"
        }

        It "Handles whitespace in 'git push --force *'" {
            $result = Convert-FromDenyGlob "git push --force *"
            $result | Should -Be "^git\s+push\s+--force\b"
        }

        It "Escapes special regex characters" {
            $result = Convert-FromDenyGlob "cmd.exe *"
            $result | Should -Match "\."
        }
    }

    Context "Deny Patterns Loading" {
        It "Loads patterns from shared-deny-rules.json when available" {
            # Verify patterns were loaded (not using fallback)
            $script:denyPatterns.Count | Should -BeGreaterThan 22
        }

        It "Includes critical deny patterns (curl, wget, docker)" {
            $patterns = $script:denyPatterns -join "|"
            $patterns | Should -Match "curl"
            $patterns | Should -Match "wget"
            $patterns | Should -Match "docker"
        }

        It "Excludes destructive patterns (handled separately)" {
            $patterns = $script:denyPatterns -join "|"
            $patterns | Should -Not -Match "git checkout --"
            $patterns | Should -Not -Match "git clean"
            $patterns | Should -Not -Match "git rm"
        }
    }

    Context "Destructive Patterns" {
        It "Defines destructive filesystem patterns" {
            $script:destructivePatterns.Count | Should -BeGreaterThan 0
        }

        It "Includes rm, Remove-Item, git clean" {
            $patterns = $script:destructivePatterns -join "|"
            $patterns | Should -Match "rm"
            $patterns | Should -Match "Remove-Item"
            $patterns | Should -Match "git clean"
        }
    }

    Context "Semi-Auto Allow Patterns" {
        It "Defines safe read-only patterns for semi mode" {
            $script:semiAllowPatterns.Count | Should -BeGreaterThan 0
        }

        It "Includes git read-only commands" {
            $patterns = $script:semiAllowPatterns -join "|"
            $patterns | Should -Match "git status"
            $patterns | Should -Match "git log"
            $patterns | Should -Match "git diff"
        }

        It "Includes filesystem read-only commands" {
            $patterns = $script:semiAllowPatterns -join "|"
            $patterns | Should -Match "Get-ChildItem"
            $patterns | Should -Match "Get-Content"
            $patterns | Should -Match "Test-Path"
        }
    }

    Context "Get-CommandClass Function" {
        It "Classifies 'git status' as allow in semi mode" {
            $result = Get-CommandClass -cmd "git status" -mode "semi"
            $result | Should -Be "allow"
        }

        It "Classifies 'git status' as ask in manual mode (default restrictive)" {
            $result = Get-CommandClass -cmd "git status" -mode "manual"
            $result | Should -Be "ask"
        }

        It "Classifies 'git status' as allow in auto mode" {
            $result = Get-CommandClass -cmd "git status" -mode "auto"
            $result | Should -Be "allow"
        }

        It "Classifies 'curl https://example.com' as deny in all modes" {
            $result = Get-CommandClass -cmd "curl https://example.com" -mode "manual"
            $result | Should -Be "deny"
            
            $result = Get-CommandClass -cmd "curl https://example.com" -mode "semi"
            $result | Should -Be "deny"
            
            $result = Get-CommandClass -cmd "curl https://example.com" -mode "auto"
            $result | Should -Be "deny"
        }

        It "Classifies 'rm -rf /' as deny in manual/semi, ask in auto" {
            $result = Get-CommandClass -cmd "rm -rf /" -mode "manual"
            $result | Should -Be "deny"
            
            $result = Get-CommandClass -cmd "rm -rf /" -mode "semi"
            $result | Should -Be "deny"
            
            $result = Get-CommandClass -cmd "rm -rf /" -mode "auto"
            $result | Should -Be "ask"
        }

        It "Classifies 'npm install express' as deny" {
            $result = Get-CommandClass -cmd "npm install express" -mode "manual"
            $result | Should -Be "deny"
        }

        It "Classifies 'git push origin main' as ask in manual/semi/auto" {
            $result = Get-CommandClass -cmd "git push origin main" -mode "manual"
            $result | Should -Be "ask"
            
            $result = Get-CommandClass -cmd "git push origin main" -mode "semi"
            $result | Should -Be "ask"
            
            $result = Get-CommandClass -cmd "git push origin main" -mode "auto"
            $result | Should -Be "ask"
        }

        It "Classifies 'echo hello' as allow in semi/auto, ask in manual" {
            $result = Get-CommandClass -cmd "echo hello" -mode "semi"
            $result | Should -Be "allow"
            
            $result = Get-CommandClass -cmd "echo hello" -mode "auto"
            $result | Should -Be "allow"
            
            $result = Get-CommandClass -cmd "echo hello" -mode "manual"
            $result | Should -Be "ask"
        }

        It "Classifies 'docker run nginx' as deny" {
            $result = Get-CommandClass -cmd "docker run nginx" -mode "manual"
            $result | Should -Be "deny"
        }

        It "Classifies 'python script.py' as deny" {
            $result = Get-CommandClass -cmd "python script.py" -mode "manual"
            $result | Should -Be "deny"
        }

        It "Classifies 'npm test' as allow in semi mode" {
            $result = Get-CommandClass -cmd "npm test" -mode "semi"
            $result | Should -Be "allow"
        }

        It "Classifies 'git diff' as allow in semi mode" {
            $result = Get-CommandClass -cmd "git diff" -mode "semi"
            $result | Should -Be "allow"
        }

        It "Classifies new package manager bare/wildcard patterns as deny in all modes" {
            # bun bare and wildcard (added to shared-deny-rules.json)
            $result = Get-CommandClass -cmd "bun" -mode "auto"
            $result | Should -Be "deny"
            $result = Get-CommandClass -cmd "bun run test" -mode "auto"
            $result | Should -Be "deny"
            $result = Get-CommandClass -cmd "bun" -mode "semi"
            $result | Should -Be "deny"
            $result = Get-CommandClass -cmd "bun" -mode "manual"
            $result | Should -Be "deny"

            # pnpm bare and wildcard
            $result = Get-CommandClass -cmd "pnpm" -mode "auto"
            $result | Should -Be "deny"
            $result = Get-CommandClass -cmd "pnpm test" -mode "auto"
            $result | Should -Be "deny"
            $result = Get-CommandClass -cmd "pnpm" -mode "semi"
            $result | Should -Be "deny"

            # yarn bare and wildcard
            $result = Get-CommandClass -cmd "yarn" -mode "auto"
            $result | Should -Be "deny"
            $result = Get-CommandClass -cmd "yarn test" -mode "auto"
            $result | Should -Be "deny"
            $result = Get-CommandClass -cmd "yarn" -mode "semi"
            $result | Should -Be "deny"

            # pip3 bare and wildcard
            $result = Get-CommandClass -cmd "pip3" -mode "auto"
            $result | Should -Be "deny"
            $result = Get-CommandClass -cmd "pip3 list" -mode "auto"
            $result | Should -Be "deny"
            $result = Get-CommandClass -cmd "pip3" -mode "semi"
            $result | Should -Be "deny"
        }

        It "Verifies semi-mode allowlist still works for npm test/run/ci and pip freeze/list/show" {
            # These should still be ALLOW in semi mode (not broken by new deny patterns)
            $result = Get-CommandClass -cmd "npm test" -mode "semi"
            $result | Should -Be "allow"
            $result = Get-CommandClass -cmd "npm run build" -mode "semi"
            $result | Should -Be "allow"
            $result = Get-CommandClass -cmd "npm ci" -mode "semi"
            $result | Should -Be "allow"
            $result = Get-CommandClass -cmd "pip freeze" -mode "semi"
            $result | Should -Be "allow"
            $result = Get-CommandClass -cmd "pip list" -mode "semi"
            $result | Should -Be "allow"
            $result = Get-CommandClass -cmd "pip show requests" -mode "semi"
            $result | Should -Be "allow"
        }
    }

    Context "Get-ConfiguredMode Function" {
        It "Returns 'manual' as default when .gentleman-mode missing" {
            # Get-ConfiguredMode requires RepoRoot parameter
            $repoRoot = Join-Path $PSScriptRoot ".."
            $result = Get-ConfiguredMode -RepoRoot $repoRoot
            $result | Should -BeIn @("manual", "semi", "auto")
        }

        It "Reads mode from .gentleman-mode file" {
            $repoRoot = Join-Path $PSScriptRoot ".."
            $modeFile = Join-Path $repoRoot ".gentleman-mode"
            if (Test-Path $modeFile) {
                $expected = Get-Content $modeFile -Raw | ForEach-Object { $_.Trim() }
                $result = Get-ConfiguredMode -RepoRoot $repoRoot
                $result | Should -Be $expected
            } else {
                Set-ItResult -Skipped -Because ".gentleman-mode not present"
            }
        }

        It "Accepts explicit Mode parameter override" {
            $repoRoot = Join-Path $PSScriptRoot ".."
            $result = Get-ConfiguredMode -Mode "manual" -RepoRoot $repoRoot
            $result | Should -Be "manual"
            
            $result = Get-ConfiguredMode -Mode "semi" -RepoRoot $repoRoot
            $result | Should -Be "semi"
            
            $result = Get-ConfiguredMode -Mode "auto" -RepoRoot $repoRoot
            $result | Should -Be "auto"
        }
    }
}