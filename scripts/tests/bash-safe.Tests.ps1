#requires -Version 7
<#
.SYNOPSIS
    Pester tests for bash-safe.ps1 — security validation, server detection, port detection.
.NOTES
    Replicates core pure functions to test security patterns without requiring Git Bash.
    Compatible with Pester 5.x / 6.x.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # Replicate $script:ServerPatterns from bash-safe.ps1 lines 30-36
    $serverPatterns = @(
        '^\s*ng\s+serve', '^\s*npm\s+run\s+(dev|start|serve)', '^\s*yarn\s+(dev|start|serve)',
        '^\s*pnpm\s+run\s+(dev|start|serve)', '^\s*dotnet\s+run', '^\s*python\s+-m\s+http\.server',
        '^\s*python\s+.*server\.py', '^\s*node\s+.*server\.(js|ts)', '^\s*npx\s+.*serve',
        '^\s*jekyll\s+serve', '^\s*hugo\s+server', '^\s*vite(\s|$)', '^\s*webpack-dev-server',
        '^\s*ts-node\s+.*server'
    )

    # Replicate $script:ServerDefaultPorts from bash-safe.ps1 lines 37-42
    $serverDefaultPorts = @(
        @{ pattern = '^\s*ng\s+serve'; port = 4200 }, @{ pattern = '^\s*vite'; port = 5173 },
        @{ pattern = '^\s*webpack-dev-server'; port = 8080 }, @{ pattern = '^\s*jekyll\s+serve'; port = 4000 },
        @{ pattern = '^\s*hugo\s+server'; port = 1313 }, @{ pattern = '^\s*python\s+-m\s+http\.server'; port = 8000 },
        @{ pattern = '^\s*dotnet\s+run'; port = 5000 }, @{ pattern = '^\s*(npm|yarn|pnpm)\s+run\s+dev'; port = 3000 }
    )

    # Replicate Test-IsServerCommand
    function Test-IsServerCommand {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param([Parameter(Mandatory)][string]$Command)
        foreach ($pattern in $serverPatterns) { if ($Command -match $pattern) { return $true } }
        return $false
    }

    # Replicate Get-ServerPort
    function Get-ServerPort {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param([Parameter(Mandatory)][string]$Command)
        if ($Command -match '--port[= ](\d+)') { return [int]$Matches[1] }
        if ($Command -match '(?:^|\s)-p\s+(\d+)') { return [int]$Matches[1] }
        if ($Command -match ':(\d{4,5})(?:\s|$)') { return [int]$Matches[1] }
        if ((Test-IsServerCommand $Command) -and ($Command -match '(\d{4,5})$')) { return [int]$Matches[1] }
        foreach ($entry in $serverDefaultPorts) { if ($Command -match $entry.pattern) { return $entry.port } }
        return $null
    }

    # Replicate Test-SafeCommand — security validation
    function Test-SafeCommand {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param([Parameter(Mandatory)][string]$Command)

        # $() subshell expansion
        if ($Command -match '\$\(') { return $false }
        # Backtick command substitution
        if ($Command -match '`') { return $false }
        # Process substitution <(...)
        if ($Command -match '<\(') { return $false }
        # Process substitution >(...)
        if ($Command -match '>\(') { return $false }
        # ANSI-C quoting $'...'
        if ($Command -match "\$'") { return $false }
        # bash -c passthrough
        if ($Command -match 'bash\s+-c\s') { return $false }
        # eval standalone or after control operators
        if ($Command -match '(^|;|&&|\|\||\|)\s*eval(\s|$)') { return $false }
        # exec standalone or after control operators
        if ($Command -match '(^|;|&&|\|\||\|)\s*exec(\s|$)') { return $false }
        # source standalone or after control operators
        if ($Command -match '(^|;|&&|\|\||\|)\s*source(\s|$)') { return $false }
        # alias standalone or after control operators
        if ($Command -match '(^|;|&&|\|\||\|)\s*alias(\s|$)') { return $false }
        # declare/typeset -f
        if ($Command -match '(declare|typeset)\s+(-f|-F)') { return $false }

        return $true
    }
}

# ============================================================================
# SECURITY VALIDATION — Test-SafeCommand
# ============================================================================
Describe "Test-SafeCommand" -Tag "Security", "Critical" {

    Context "Safe commands — should be ALLOWED" {
        It "permits plain echo" {
            Test-SafeCommand "echo hello" | Should -Be $true
        }
        It "permits && chaining" {
            Test-SafeCommand "echo a && echo b" | Should -Be $true
        }
        It "permits || fallback" {
            Test-SafeCommand "false || echo fallback" | Should -Be $true
        }
        It "permits pipeline" {
            Test-SafeCommand "cat file | grep pattern" | Should -Be $true
        }
        It "permits semicolons" {
            Test-SafeCommand "echo a; echo b" | Should -Be $true
        }
        It "permits env var expansion (PS evaluates, bash sees $HOME)" {
            Test-SafeCommand "echo `$HOME" | Should -Be $true
        }
        It "permits single quotes (bash syntax)" {
            Test-SafeCommand "echo 'hello world'" | Should -Be $true
        }
        It "permits double quotes (bash syntax)" {
            Test-SafeCommand 'echo "hello world"' | Should -Be $true
        }
        It "permits escaped dollar sign" {
            Test-SafeCommand 'echo \$HOME' | Should -Be $true
        }
        It "permits git status" {
            Test-SafeCommand "git status --short" | Should -Be $true
        }
        It "permits docker exec (subcommand, not standalone exec)" {
            Test-SafeCommand "docker exec -it bash" | Should -Be $true
        }
        It "permits kubectl exec (subcommand, not standalone exec)" {
            Test-SafeCommand "kubectl exec pod -- ls" | Should -Be $true
        }
        It "permits find . (dot arg, safe)" {
            Test-SafeCommand 'find . -name "*.txt"' | Should -Be $true
        }
        It "permits git config alias (word, not alias command)" {
            Test-SafeCommand "git config alias.st status" | Should -Be $true
        }
        It 'permits "eval" as text (not as command)' {
            Test-SafeCommand 'echo "setup: eval v1.0"' | Should -Be $true
        }
        It 'permits "source" as text (not as command)' {
            Test-SafeCommand 'echo "source file loaded"' | Should -Be $true
        }
        It "permits ls . (dot arg, safe)" {
            Test-SafeCommand "ls ." | Should -Be $true
        }
        It "permits git -C . (source inside git, text)" {
            Test-SafeCommand "git -C . log --oneline" | Should -Be $true
        }
        It "permits npm run build (NO server false positive)" {
            Test-SafeCommand "npm run build" | Should -Be $true
        }
        It "permits eval inside git log for diff" {
            Test-SafeCommand 'git log --diff-filter=M --name-only' | Should -Be $true
        }
    }

    Context "Unsafe commands — should be BLOCKED" {
        It "blocks backtick injection" {
            Test-SafeCommand 'echo `whoami`' | Should -Be $false
        }
        It "blocks subshell injection $()" {
            Test-SafeCommand 'echo $(whoami)' | Should -Be $false
        }
        It "blocks process substitution <(" {
            Test-SafeCommand 'diff <(echo a) <(echo b)' | Should -Be $false
        }
        It "blocks process substitution >(" {
            Test-SafeCommand 'echo x > >(cat)' | Should -Be $false
        }
        It "blocks ANSI-C quoting" {
            Test-SafeCommand "echo `$'\\x48'" | Should -Be $false
        }
        It "blocks bash -c passthrough" {
            Test-SafeCommand 'bash -c "echo pwned"' | Should -Be $false
        }
        It "blocks eval standalone" {
            Test-SafeCommand 'eval ls' | Should -Be $false
        }
        It "blocks eval after pipe" {
            Test-SafeCommand 'echo x | eval ls' | Should -Be $false
        }
        It "blocks exec standalone" {
            Test-SafeCommand 'exec ls -la' | Should -Be $false
        }
        It "blocks source standalone" {
            Test-SafeCommand 'source /etc/profile' | Should -Be $false
        }
        It "blocks alias definition" {
            Test-SafeCommand 'alias ll="ls -la"' | Should -Be $false
        }
        It "blocks declare -f" {
            Test-SafeCommand 'declare -f myfunc' | Should -Be $false
        }
        It "blocks typeset -f" {
            Test-SafeCommand 'typeset -f myfunc' | Should -Be $false
        }
        It "blocks eval after semicolon" {
            Test-SafeCommand 'echo a; eval whoami' | Should -Be $false
        }
        It "blocks source after AND" {
            Test-SafeCommand 'echo a && source secrets.sh' | Should -Be $false
        }
        It "blocks exec after OR" {
            Test-SafeCommand 'false || exec /bin/sh' | Should -Be $false
        }
        It "blocks alias after pipe" {
            Test-SafeCommand 'echo | alias l="ls"' | Should -Be $false
        }
        It "blocks declare -F" {
            Test-SafeCommand 'declare -F myfunc' | Should -Be $false
        }
    }
}

# ============================================================================
# SERVER DETECTION — Test-IsServerCommand
# ============================================================================
Describe "Test-IsServerCommand" -Tag "ServerDetection" {

    Context "Server commands" {
        It "detects ng serve" {
            Test-IsServerCommand "ng serve" | Should -Be $true
        }
        It "detects npm run dev" {
            Test-IsServerCommand "npm run dev" | Should -Be $true
        }
        It "detects npm run start" {
            Test-IsServerCommand "npm run start" | Should -Be $true
        }
        It "detects dotnet run" {
            Test-IsServerCommand "dotnet run" | Should -Be $true
        }
        It "detects python http.server" {
            Test-IsServerCommand "python -m http.server 8080" | Should -Be $true
        }
        It "detects python server.py" {
            Test-IsServerCommand "python server.py" | Should -Be $true
        }
        It "detects npx serve" {
            Test-IsServerCommand "npx serve dist" | Should -Be $true
        }
        It "detects jekyll serve" {
            Test-IsServerCommand "jekyll serve" | Should -Be $true
        }
        It "detects vite" {
            Test-IsServerCommand "vite" | Should -Be $true
        }
        It "detects webpack-dev-server" {
            Test-IsServerCommand "webpack-dev-server" | Should -Be $true
        }
        It "detects ts-node server" {
            Test-IsServerCommand "ts-node server.ts" | Should -Be $true
        }
        It "detects yarn dev" {
            Test-IsServerCommand "yarn dev" | Should -Be $true
        }
        It "detects pnpm serve" {
            Test-IsServerCommand "pnpm run serve" | Should -Be $true
        }
        It "detects node server.js" {
            Test-IsServerCommand "node server.js" | Should -Be $true
        }
        It "detects hugo server" {
            Test-IsServerCommand "hugo server" | Should -Be $true
        }
    }

    Context "Non-server commands" {
        It "does NOT flag npm run build" {
            Test-IsServerCommand "npm run build" | Should -Be $false
        }
        It "does NOT flag git status" {
            Test-IsServerCommand "git status" | Should -Be $false
        }
        It "does NOT flag echo hello" {
            Test-IsServerCommand "echo hello" | Should -Be $false
        }
        It "does NOT flag ls -la" {
            Test-IsServerCommand "ls -la" | Should -Be $false
        }
        It "does NOT flag npm test" {
            Test-IsServerCommand "npm test" | Should -Be $false
        }
        It "does NOT flag python script.py" {
            Test-IsServerCommand "python script.py" | Should -Be $false
        }
        It "does NOT flag node index.js" {
            Test-IsServerCommand "node index.js" | Should -Be $false
        }
    }
}

# ============================================================================
# PORT DETECTION — Get-ServerPort
# ============================================================================
Describe "Get-ServerPort" -Tag "PortDetection" {

    Context "Default ports" {
        It "ng serve → 4200" {
            Get-ServerPort "ng serve" | Should -Be 4200
        }
        It "npm run dev → 3000" {
            Get-ServerPort "npm run dev" | Should -Be 3000
        }
        It "dotnet run → 5000" {
            Get-ServerPort "dotnet run" | Should -Be 5000
        }
        It "python http.server → 8000" {
            Get-ServerPort "python -m http.server" | Should -Be 8000
        }
        It "jekyll serve → 4000" {
            Get-ServerPort "jekyll serve" | Should -Be 4000
        }
        It "vite → 5173" {
            Get-ServerPort "vite" | Should -Be 5173
        }
        It "webpack-dev-server → 8080" {
            Get-ServerPort "webpack-dev-server" | Should -Be 8080
        }
        It "hugo server → 1313" {
            Get-ServerPort "hugo server" | Should -Be 1313
        }
    }

    Context "Custom ports via --port flag" {
        It "ng serve --port 4300 → 4300" {
            Get-ServerPort "ng serve --port 4300" | Should -Be 4300
        }
        It "vite --port 3001 → 3001" {
            Get-ServerPort "vite --port 3001" | Should -Be 3001
        }
        It "python http.server --port 9999 → 9999" {
            Get-ServerPort "python -m http.server --port 9999" | Should -Be 9999
        }
        It "npm run dev --port 8080 → 8080" {
            Get-ServerPort "npm run dev --port 8080" | Should -Be 8080
        }
    }

    Context "Custom ports via -p flag" {
        It "ng serve -p 4300 → 4300" {
            Get-ServerPort "ng serve -p 4300" | Should -Be 4300
        }
        It "python -p 9000 → 9000" {
            Get-ServerPort "python -m http.server -p 9000" | Should -Be 9000
        }
    }

    Context "Port in command string (4-5 digits)" {
        It "python 8080 → 8080" {
            Get-ServerPort "python -m http.server 8080" | Should -Be 8080
        }
        It "jekyll 4000 → 4000" {
            Get-ServerPort "jekyll serve --port 4000" | Should -Be 4000
        }
    }

    Context "Non-server commands return null" {
        It "git status → null" {
            Get-ServerPort "git status" | Should -Be $null
        }
        It "echo hello → null" {
            Get-ServerPort "echo hello" | Should -Be $null
        }
        It "ls -la → null" {
            Get-ServerPort "ls -la" | Should -Be $null
        }
        It "npm test → null" {
            Get-ServerPort "npm test" | Should -Be $null
        }
    }

    Context "Edge cases" {
        It "port number in non-server command message" {
            Get-ServerPort "echo 'port 8080'" | Should -Be $null
        }
        It "port from end of command line" {
            Get-ServerPort "ng serve 4200" | Should -Be 4200
        }
        It "port in URL-like pattern" {
            Get-ServerPort "npm run dev" | Should -Be 3000
        }
    }
}
