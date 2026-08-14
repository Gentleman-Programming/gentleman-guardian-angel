#requires -Version 7
<#
.SYNOPSIS
    Integration tests for validate-write-scope.ps1 — tests the ACTUAL script against temp git repos.
.NOTES
    ponytail: filesystem tests — creates and destroys temp git repos.
#>

BeforeAll {
    $scriptsRoot = Resolve-Path "$PSScriptRoot/.."
    $scriptPath = "$scriptsRoot/validate-write-scope.ps1"

    $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "vws-int-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:tempRoot -Force -ErrorAction Stop | Out-Null
    Push-Location $script:tempRoot

    git init -q
    git config core.autocrlf false
    git config user.email "test@gentleman.test"
    git config user.name "Gentleman Test"
    New-Item -ItemType File -Path "dummy.txt" -Force | Out-Null
    git add -A
    git commit -m "initial" -q
}

AfterAll {
    Pop-Location
    if (Test-Path $script:tempRoot) {
        Remove-Item -Path $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Clean state detection" {

    BeforeEach {
        Set-Location $script:tempRoot
        git checkout -- . -q 2>$null
        git clean -fd -q 2>$null
        # Remove any leftover new files created by previous tests
        Get-ChildItem -Path $script:tempRoot -File | Where-Object { $_.Name -ne "dummy.txt" } | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    It "reports CLEAN when no files changed" {
        $output = & $scriptPath -AllowedPaths "src/*" -BaseRef "HEAD" -Json 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        $result.status | Should -Be "CLEAN"
        $result.message | Should -Match "No changed files detected"
    }
}

Describe "Scope enforcement" {

    BeforeEach {
        Set-Location $script:tempRoot
        git checkout -- . -q 2>$null
        git clean -fd -q 2>$null
        Get-ChildItem -Path $script:tempRoot -File | Where-Object { $_.Name -ne "dummy.txt" } | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $script:tempRoot -Directory | Where-Object { $_.Name -ne ".git" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "CLEAN when modified file is inside allowed scope" {
        New-Item -ItemType Directory -Path "src/auth" -Force | Out-Null
        Set-Content -Path "src/auth/login.ts" -Value "original"
        git add -A
        git commit -m "add login.ts" -q

        Set-Content -Path "src/auth/login.ts" -Value "modified"
        $output = & $scriptPath -AllowedPaths "src/auth/*" -BaseRef "HEAD" -Json 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        $result.status | Should -Be "CLEAN"
        $result.totalChanged | Should -Be 1
    }

    It "VIOLATION when modified file is outside allowed scope" {
        New-Item -ItemType Directory -Path "config" -Force | Out-Null
        Set-Content -Path "config/deploy.yml" -Value "original"
        git add -A
        git commit -m "add config" -q

        Set-Content -Path "config/deploy.yml" -Value "modified"
        $output = & $scriptPath -AllowedPaths "src/*" -BaseRef "HEAD" -Json 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        $result.status | Should -Be "VIOLATION"
        $result.totalChanged | Should -Be 1
        $result.totalViolations | Should -Be 1
    }

    It "detects violations among mixed in-scope and out-of-scope changes" {
        New-Item -ItemType Directory -Path "src" -Force | Out-Null
        New-Item -ItemType Directory -Path "outside" -Force | Out-Null
        Set-Content -Path "src/ok.ts" -Value "original"
        Set-Content -Path "outside/leak.ts" -Value "leak"
        git add -A
        git commit -m "add both scoped and outside files" -q

        # Modify both — script's git diff only sees TRACKED files
        Set-Content -Path "src/ok.ts" -Value "changed"
        Set-Content -Path "outside/leak.ts" -Value "also changed"

        $output = & $scriptPath -AllowedPaths "src/*" -BaseRef "HEAD" -Json 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        $result.status | Should -Be "VIOLATION"
        $result.totalChanged | Should -Be 2
        $result.totalViolations | Should -Be 1
    }
}

Describe "Parameter validation" {

    BeforeEach {
        Set-Location $script:tempRoot
    }

    It "rejects empty AllowedPaths" {
        { & $scriptPath -AllowedPaths "" } | Should -Throw
    }

    It "rejects BaseRef with spaces" {
        $output = & $scriptPath -AllowedPaths "src/*" -BaseRef "HEAD HEAD~1" 2>&1
        $output | Out-String | Should -Match "ERROR: BaseRef contains spaces"
    }

    It "handles invalid BaseRef gracefully" {
        $output = & $scriptPath -AllowedPaths "src/*" -BaseRef "THISREFDOESNOTEXIST" -Json 2>&1
        $result = $output | Out-String | ConvertFrom-Json
        $result.status | Should -Match "CLEAN|error"
    }
}

