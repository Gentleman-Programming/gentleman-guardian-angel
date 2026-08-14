#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Tests for permission-gate classification — command classification per mode.
.DESCRIPTION
    Verifies that commands are correctly classified as allow/ask/deny
    in manual, semi, and auto modes.
    Runs IN-PROCESS: dot-sources scripts/lib/permission-gate-lib.ps1 once in
    BeforeAll and calls Get-CommandClass directly (no per-It script spawn).

    Run: Invoke-Pester .\scripts\tests\permission-gate.Tests.ps1
    Run quiet: Invoke-Pester .\scripts\tests\permission-gate.Tests.ps1 -- -Quiet
#>
param([switch]$Quiet)

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\permission-gate-lib.ps1')

    function Invoke-Gate {
        param([string]$Command, [string]$Mode)
        $verdict = Get-CommandClass -cmd $Command -mode $Mode
        $rule = switch ($verdict) {
            'deny'  { 'Built-in security restriction' }
            'allow' { "Allowed in $Mode mode" }
            'ask'   { "Requires confirmation in $Mode mode" }
            'help'  { 'No command provided' }
        }
        [PSCustomObject]@{
            action  = 'permission-gate'
            command = $Command
            mode    = $Mode
            verdict = $verdict
            rule    = $rule
        }
    }
}

# ============================================================
# MANUAL MODE — everything asks (unless denied)
# ============================================================
Describe "Manual mode — default behaviour" {
    It "returns ask for git status [read]" {
        $r = Invoke-Gate -Command "git status" -Mode manual
        $r.verdict | Should -Be "ask"
    }
    It "returns ask for ls [read]" {
        $r = Invoke-Gate -Command "ls" -Mode manual
        $r.verdict | Should -Be "ask"
    }
    It "returns ask for cat file [read]" {
        $r = Invoke-Gate -Command "cat foo.txt" -Mode manual
        $r.verdict | Should -Be "ask"
    }
    It "returns deny for curl [network]" {
        $r = Invoke-Gate -Command "curl http://example.com" -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "returns deny for rm [destructive]" {
        $r = Invoke-Gate -Command "rm -rf node_modules" -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "returns deny for python [interpreter]" {
        $r = Invoke-Gate -Command "python script.py" -Mode manual
        $r.verdict | Should -Be "deny"
    }
}

# ============================================================
# SEMI MODE — safe commands auto-allow, writes ask
# ============================================================
Describe "Semi mode — allowlist" {
    It "ALLOWS git status [git read-only]" {
        $r = Invoke-Gate -Command "git status" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS git diff [git read-only]" {
        $r = Invoke-Gate -Command "git diff" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS git log --oneline -5 [git read-only]" {
        $r = Invoke-Gate -Command "git log --oneline -5" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS git branch [git read-only]" {
        $r = Invoke-Gate -Command "git branch" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS git stash list [git read-only]" {
        $r = Invoke-Gate -Command "git stash list" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS ls -la [filesystem]" {
        $r = Invoke-Gate -Command "ls -la" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS cat file.txt [read file]" {
        $r = Invoke-Gate -Command "cat file.txt" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS pwd [directory info]" {
        $r = Invoke-Gate -Command "pwd" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS grep pattern file [search]" {
        $r = Invoke-Gate -Command "grep 'foo' bar.txt" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS rg pattern [search]" {
        $r = Invoke-Gate -Command "rg 'TODO'" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS which git [query]" {
        $r = Invoke-Gate -Command "which git" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS npm test [build/test]" {
        $r = Invoke-Gate -Command "npm test" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS npm run build [build/test]" {
        $r = Invoke-Gate -Command "npm run build" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS npm ci [safe install from lockfile]" {
        $r = Invoke-Gate -Command "npm ci" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS pytest [test runner]" {
        $r = Invoke-Gate -Command "pytest tests/" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS go test [test runner]" {
        $r = Invoke-Gate -Command "go test ./..." -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS pip freeze [pip info]" {
        $r = Invoke-Gate -Command "pip freeze" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS pip list [pip info]" {
        $r = Invoke-Gate -Command "pip list" -Mode semi
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS pip show requests [pip info]" {
        $r = Invoke-Gate -Command "pip show requests" -Mode semi
        $r.verdict | Should -Be "allow"
    }
}

Describe "Semi mode — ask (not in allowlist)" {
    It "ASKS for git commit [write operation]" {
        $r = Invoke-Gate -Command "git commit -m 'fix'" -Mode semi
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for git push [write operation]" {
        $r = Invoke-Gate -Command "git push origin main" -Mode semi
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for mkdir [create dir]" {
        $r = Invoke-Gate -Command "mkdir newdir" -Mode semi
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for New-Item [create file]" {
        $r = Invoke-Gate -Command "New-Item -Path test.txt -ItemType File" -Mode semi
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for Set-Content [write file]" {
        $r = Invoke-Gate -Command "Set-Content -Path test.txt -Value 'hello'" -Mode semi
        $r.verdict | Should -Be "ask"
    }
    It "DENIES pip install [supply chain]" {
        $r = Invoke-Gate -Command "pip install requests" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "ASKS for npm install [supply chain — now ask not deny per C3b+Option-A]" {
        $r = Invoke-Gate -Command "npm install lodash" -Mode semi
        $r.verdict | Should -Be "ask"
    }
    It "DENIES npm uninstall [supply chain]" {
        $r = Invoke-Gate -Command "npm uninstall lodash" -Mode semi
        $r.verdict | Should -Be "deny"
    }
}

Describe "Semi mode — deny (all modes)" {
    It "DENIES curl [network]" {
        $r = Invoke-Gate -Command "curl http://evil.com" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES ssh [network]" {
        $r = Invoke-Gate -Command "ssh user@host" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES docker [network/system]" {
        $r = Invoke-Gate -Command "docker ps" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES rm -rf [destructive]" {
        $r = Invoke-Gate -Command "rm -rf /tmp/data" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES python [interpreter]" {
        $r = Invoke-Gate -Command "python -c 'print(1)'" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git push --force [forced push]" {
        $r = Invoke-Gate -Command "git push --force origin main" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git push -f [forced push shorthand]" {
        $r = Invoke-Gate -Command "git push -f origin main" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES icm [remote command execution alias]" {
        $r = Invoke-Gate -Command "icm -ComputerName server -ScriptBlock { whoami }" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES Invoke-Expression [code injection]" {
        $r = Invoke-Gate -Command "Invoke-Expression 'malicious'" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES wsl [system bridge]" {
        $r = Invoke-Gate -Command "wsl bash -c 'curl http://evil.com'" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git clean -fdx [destructive filesystem]" {
        $r = Invoke-Gate -Command "git clean -fdx" -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git rm -r [destructive filesystem]" {
        $r = Invoke-Gate -Command "git rm -r ." -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git checkout -- . [destructive filesystem]" {
        $r = Invoke-Gate -Command "git checkout -- ." -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git restore . [destructive filesystem]" {
        $r = Invoke-Gate -Command "git restore ." -Mode semi
        $r.verdict | Should -Be "deny"
    }
}

# ============================================================
# AUTO MODE — everything allowed except push/deletes
# ============================================================
Describe "Auto mode — allow behaviour" {
    It "ALLOWS git status [read]" {
        $r = Invoke-Gate -Command "git status" -Mode auto
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS git commit [write]" {
        $r = Invoke-Gate -Command "git commit -m 'fix'" -Mode auto
        $r.verdict | Should -Be "allow"
    }
    It "ALLOWS mkdir [create dir]" {
        $r = Invoke-Gate -Command "mkdir newdir" -Mode auto
        $r.verdict | Should -Be "allow"
    }
}

Describe "Auto mode — ask (push + deletes)" {
    It "ASKS for git push [in auto mode]" {
        $r = Invoke-Gate -Command "git push origin main" -Mode auto
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for rm [destructive, user confirms in auto]" {
        $r = Invoke-Gate -Command "rm -rf /tmp" -Mode auto
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for Remove-Item [destructive, user confirms in auto]" {
        $r = Invoke-Gate -Command "Remove-Item -Recurse -Force C:\tmp\data" -Mode auto
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for git branch -D [branch deletion]" {
        $r = Invoke-Gate -Command "git branch -D old-feature" -Mode auto
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for git stash drop [stash deletion]" {
        $r = Invoke-Gate -Command "git stash drop" -Mode auto
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for git reset --hard [destructive reset]" {
        $r = Invoke-Gate -Command "git reset --hard HEAD~2" -Mode auto
        $r.verdict | Should -Be "ask"
    }
}

Describe "Auto mode — deny (network + forced push)" {
    It "DENIES curl [network, even in auto]" {
        $r = Invoke-Gate -Command "curl http://example.com" -Mode auto
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git push --force [forced push, even in auto]" {
        $r = Invoke-Gate -Command "git push --force origin main" -Mode auto
        $r.verdict | Should -Be "deny"
    }
    It "DENIES icm [remote command, even in auto]" {
        $r = Invoke-Gate -Command "icm localhost { ls }" -Mode auto
        $r.verdict | Should -Be "deny"
    }
    It "DENIES Invoke-Expression [code injection, even in auto]" {
        $r = Invoke-Gate -Command "Invoke-Expression 'get-process'" -Mode auto
        $r.verdict | Should -Be "deny"
    }
    It "DENIES wsl [system bridge, even in auto]" {
        $r = Invoke-Gate -Command "wsl echo hi" -Mode auto
        $r.verdict | Should -Be "deny"
    }
    It "ASKS for git clean -fdx [destructive, user confirms in auto]" {
        $r = Invoke-Gate -Command "git clean -fdx" -Mode auto
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for git rm -r [destructive, user confirms in auto]" {
        $r = Invoke-Gate -Command "git rm -r src" -Mode auto
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for git checkout -- . [destructive, user confirms in auto]" {
        $r = Invoke-Gate -Command "git checkout -- ." -Mode auto
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for git restore . [destructive, user confirms in auto]" {
        $r = Invoke-Gate -Command "git restore ." -Mode auto
        $r.verdict | Should -Be "ask"
    }
}

# ============================================================
# Edge cases
# ============================================================
Describe "Edge cases" {
    It "returns help for empty command" {
        $r = Invoke-Gate -Command "" -Mode semi
        $r.verdict | Should -Be "help"
    }

    It "returns expected JSON fields" {
        $r = Invoke-Gate -Command "git status" -Mode semi
        $r.action | Should -Be "permission-gate"
        $r | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name } | Sort-Object
        $expectedFields = @('action', 'command', 'mode', 'verdict')
        $actualFields = ($r | Get-Member -MemberType NoteProperty).Name
        foreach ($f in $expectedFields) {
            $f -in $actualFields | Should -Be $true
        }
    }

    It "always returns a valid verdict for any command" {
        $r = Invoke-Gate -Command "obscure-command-that-should-ask" -Mode semi
        $r.verdict | Should -BeIn @("allow", "ask", "deny", "help")
    }
}

# ============================================================
# Whitespace evasion — anchored ^patterns must not be bypassed
# ============================================================
Describe "Whitespace normalization — no pattern evasion" {
    It "DENIES git clean with double space [evasion attempt]" {
        $r = Invoke-Gate -Command "git  clean  -fdx" -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git clean with leading space [evasion attempt]" {
        $r = Invoke-Gate -Command "  git clean -fdx" -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git clean with tab separator [evasion attempt]" {
        $r = Invoke-Gate -Command "git`tclean -fdx" -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git rm with double space [evasion attempt]" {
        $r = Invoke-Gate -Command "git  rm  -r ." -Mode auto
        $r.verdict | Should -Be "ask"
    }
    It "DENIES git push --force with double space [evasion attempt]" {
        $r = Invoke-Gate -Command "git push  --force origin main" -Mode auto
        $r.verdict | Should -Be "deny"
    }
    It "DENIES icm with double space [evasion attempt]" {
        $r = Invoke-Gate -Command "icm  localhost { ls }" -Mode auto
        $r.verdict | Should -Be "deny"
    }
    It "DENIES wsl with leading space [evasion attempt]" {
        $r = Invoke-Gate -Command "  wsl echo hi" -Mode auto
        $r.verdict | Should -Be "deny"
    }
    It "still ALLOWS git status with double space [no false positive]" {
        $r = Invoke-Gate -Command "git  status" -Mode auto
        $r.verdict | Should -Be "allow"
    }
    It "still ALLOWS ls with leading space [no false positive]" {
        $r = Invoke-Gate -Command "  ls" -Mode auto
        $r.verdict | Should -Be "allow"
    }
}

# ============================================================
# Unicode whitespace evasion — \p{Zs} separators + \p{Cf} format
# chars (U+200B ZWSP, U+00A0 NBSP, U+202F, U+180E) must not
# bypass anchored ^patterns
# ============================================================
Describe "Unicode whitespace normalization — no pattern evasion" {
    It "DENIES git clean with zero-width space U+200B [manual]" {
        $r = Invoke-Gate -Command ('git' + [char]0x200B + 'clean -fdx') -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git clean with zero-width space U+200B [semi]" {
        $r = Invoke-Gate -Command ('git' + [char]0x200B + 'clean -fdx') -Mode semi
        $r.verdict | Should -Be "deny"
    }
    It "ASKS git clean with zero-width space U+200B [auto — never allow]" {
        $r = Invoke-Gate -Command ('git' + [char]0x200B + 'clean -fdx') -Mode auto
        $r.verdict | Should -Not -Be "allow"
        $r.verdict | Should -Be "ask"
    }
    It "ASKS for npm install with no-break space U+00A0 [semi — whitespace evasion blocked, not allowed]" {
        $r = Invoke-Gate -Command ('npm' + [char]0x00A0 + 'install lodash') -Mode semi
        $r.verdict | Should -Not -Be "allow"
        $r.verdict | Should -Be "ask"
    }
    It "DENIES git clean with narrow no-break space U+202F [manual]" {
        $r = Invoke-Gate -Command ('git' + [char]0x202F + 'clean -fdx') -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git clean with Mongolian vowel separator U+180E [manual]" {
        $r = Invoke-Gate -Command ('git' + [char]0x180E + 'clean -fdx') -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git clean with triple space [evasion attempt]" {
        $r = Invoke-Gate -Command "git  clean  -fdx" -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "DENIES git clean with LEADING zero-width space U+200B [manual]" {
        $r = Invoke-Gate -Command ([char]0x200B + 'git clean -fdx') -Mode manual
        $r.verdict | Should -Be "deny"
    }
    It "still ALLOWS git status with U+200B [no false positive]" {
        $r = Invoke-Gate -Command ('git' + [char]0x200B + 'status') -Mode auto
        $r.verdict | Should -Be "allow"
    }
}

# ============================================================
# SSoT supply-chain deny floor — permission-templates.json
# (opencode agent config layer; C3b Gap 1: npm/pip/yarn/pnpm/bun
#  install vectors must DENY in auto+semi, legitimate run/test/ci
#  and pip read-only queries must stay ALLOW).
# NOTE: these assert the SSoT rules that generate opencode.json,
# NOT the runtime lib Get-CommandClass verdicts (separate layer).
# ============================================================
Describe "SSoT supply-chain deny floor (permission-templates.json)" {
    BeforeAll {
        $script:tpl = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\permission-templates.json') -Raw | ConvertFrom-Json

        function Get-SSoTRule {
            param([string]$Mode, [string]$Cmd)
            $rules = $script:tpl.$Mode.bash
            $toks = $Cmd -split '\s+'
            $bestScore = [int]::MinValue
            $bestVerdict = $rules.'*'
            foreach ($prop in $rules.PSObject.Properties) {
                $parts = $prop.Name -split '\s+'
                $wild = $parts[$parts.Count - 1] -eq '*'
                $n = if ($wild) { $parts.Count - 1 } else { $parts.Count }
                if ($toks.Count -lt $n) { continue }
                $ok = $true
                for ($i = 0; $i -lt $n; $i++) { if ($toks[$i] -ne $parts[$i]) { $ok = $false; break } }
                if (-not $ok) { continue }
                if (-not $wild -and $toks.Count -ne $n) { continue }
                $score = if ($wild) { $n + 1000 } else { $n + 10000 }
                if ($score -gt $bestScore) { $bestScore = $score; $bestVerdict = $prop.Value }
            }
            return $bestVerdict
        }
    }

    It "ASKS for npm install in auto [supply chain — now ask not deny per C3b+Option-A]" {
        Get-SSoTRule auto "npm install evil-pkg" | Should -Be "ask"
    }
    It "ASKS for npm i -g in auto [supply chain — now ask not deny per C3b+Option-A]" {
        Get-SSoTRule auto "npm i -g evil" | Should -Be "ask"
    }
    It "DENIES pip install in auto [supply chain]" {
        Get-SSoTRule auto "pip install numpy" | Should -Be "deny"
    }
    It "DENIES pip3 install in auto [supply chain]" {
        Get-SSoTRule auto "pip3 install evil" | Should -Be "deny"
    }
    It "DENIES yarn add in auto [supply chain]" {
        Get-SSoTRule auto "yarn add evil" | Should -Be "deny"
    }
    It "DENIES bun install in auto [supply chain]" {
        Get-SSoTRule auto "bun install evil" | Should -Be "deny"
    }
    It "ASKS for npx in auto [supply chain — now ask not deny per C3b+Option-A]" {
        Get-SSoTRule auto "npx evil" | Should -Be "ask"
    }
    It "ASKS for node in auto [RCE — now ask not deny per C3b+Option-A]" {
        Get-SSoTRule auto "node --version" | Should -Be "ask"
        Get-SSoTRule auto "node evil.js" | Should -Be "ask"
    }
    It "ASKS for npm add in auto [supply chain — now ask not deny per C3b+Option-A]" {
        Get-SSoTRule auto "npm add evil-pkg" | Should -Be "ask"
    }
    It "DENIES npm exec in auto [supply chain - arbitrary code]" {
        Get-SSoTRule auto "npm exec -y evil" | Should -Be "deny"
    }
    It "ALLOWS npm run build in auto [legitimate]" {
        Get-SSoTRule auto "npm run build" | Should -Be "allow"
    }
    It "ALLOWS npm test in auto [legitimate]" {
        Get-SSoTRule auto "npm test" | Should -Be "allow"
    }
    It "ALLOWS npm ci in auto [legitimate lockfile install]" {
        Get-SSoTRule auto "npm ci" | Should -Be "allow"
    }
    It "ASKS for npm install in semi [supply chain — now ask not deny per C3b+Option-A]" {
        Get-SSoTRule semi "npm install evil-pkg" | Should -Be "ask"
    }
    It "DENIES npm ci in semi [C3b gap fix]" {
        Get-SSoTRule semi "npm ci" | Should -Be "deny"
    }
    It "DENIES pip install in semi [supply chain]" {
        Get-SSoTRule semi "pip install evil" | Should -Be "deny"
    }
    It "ALLOWS npm run build in semi [legitimate]" {
        Get-SSoTRule semi "npm run build" | Should -Be "allow"
    }
    It "ALLOWS pip freeze in semi [read-only info]" {
        Get-SSoTRule semi "pip freeze" | Should -Be "allow"
    }
    It "ALLOWS pip show in semi [read-only info]" {
        Get-SSoTRule semi "pip show requests" | Should -Be "allow"
    }
}

# ============================================================
Describe 'C4b: Permission model consolidation (shared-deny-rules.json single source)' {

    It 'loads deny patterns from shared-deny-rules.json (not fallback)' {
        # C4b: patterns loaded from JSON, not embedded fallback (~75 patterns)
        $script:denyPatterns.Count | Should -BeGreaterThan 50
    }

    It 'denies curl from loaded JSON patterns [network]' {
        Get-CommandClass 'curl http://evil.com' 'manual' | Should -Be 'deny'
        Get-CommandClass 'curl http://evil.com' 'auto'    | Should -Be 'deny'
    }

    It 'does NOT pre-deny destructive patterns (git clean is ask-in-auto)' {
        # Destructive patterns excluded from denyPatterns — handled by destructivePatterns
        Get-CommandClass 'git clean -fdx' 'auto'    | Should -Be 'ask'
        Get-CommandClass 'git clean -fdx' 'manual'  | Should -Be 'deny'
    }

    It 'asks for npm install from loaded JSON patterns [supply chain — now ask not deny per C3b+Option-A]' {
        Get-CommandClass 'npm install evil-pkg' 'auto' | Should -Be 'ask'
    }

    It 'asks for npx from loaded JSON patterns [supply chain — now ask not deny per C3b+Option-A]' {
        Get-CommandClass 'npx create-next-app' 'auto' | Should -Be 'ask'
    }

    It 'asks for node from loaded JSON patterns [RCE — now ask not deny per C3b+Option-A]' {
        Get-CommandClass 'node --version' 'auto' | Should -Be 'ask'
    }

    It 'asks for npm install in semi from runtime gate [supply chain — now ask not deny]' {
        Get-CommandClass 'npm install lodash' 'semi' | Should -Be 'ask'
    }

    It 'allows npm ci from mode-specific allowlist [legitimate]' {
        Get-CommandClass 'npm ci' 'auto'  | Should -Be 'allow'
        Get-CommandClass 'npm ci' 'semi'  | Should -Be 'allow'
    }
}
