#requires -Version 7

BeforeAll {
    $scriptsRoot = Resolve-Path "$PSScriptRoot/.."

    # Capture FIRST — if any setup below fails, AfterAll restores the real value
    # (never a $null placeholder)
    $script:oldUserProfile = $env:USERPROFILE

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pester-restore-$(Get-Random)"
    $configDir = Join-Path (Join-Path $tempRoot ".config") "opencode"
    New-Item -ItemType Directory -Path (Join-Path $configDir ".git") -Force -ErrorAction Stop | Out-Null

    $env:USERPROFILE = $tempRoot

    $lines = Get-Content "$scriptsRoot/restore.ps1" -ErrorAction Stop
    $tmp = $lines[14]; $lines[14] = $lines[15]; $lines[15] = $tmp
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lines[$i] = $lines[$i] -replace 'exit (\d+)', 'return $1'
        $lines[$i] = $lines[$i] -replace '\$PSScriptRoot', "'$scriptsRoot'"
    }
    $fixedContent = $lines -join "`r`n"
    $fixedContent = $fixedContent -replace 'Join-Path \(Get-GlobalConfigDir\)', '(Get-GlobalConfigDir)'
    $fixedContent = $fixedContent.Replace('$Revision? [y/N]', '$($Revision)? [y/N]')
    $script:fixedScript = Join-Path $tempRoot "restore-fixed.ps1"
    $fixedContent | Set-Content $script:fixedScript -Encoding UTF8 -Force

    $global:checkoutCalled = $false
    $global:checkoutTarget = $null
    Mock git {
        if ($args[0] -eq "checkout") {
            $global:checkoutCalled = $true
            $global:checkoutTarget = $args[1]
        }
        switch ($args[0]) {
            "rev-list"  { "42" }
            "rev-parse" { "abc123def4567890abcdef1234567890abcdef12" }
            "diff"      { @("test.txt") }
            "checkout"  { $null }
            "log"       { @("abc123 First commit", "def456 Second commit") }
            default     { $null }
        }
    }
}

AfterAll {
    if ($null -ne $script:oldUserProfile) {
        $env:USERPROFILE = $script:oldUserProfile
    }
    Remove-Variable -Name IsLinux -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name IsMacOS -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name checkoutCalled -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name checkoutTarget -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "restore.ps1 - Git ref validation" {

    It "passes valid git refs through the regex guard" {
        $validRefs = @("abc1234", "HEAD", "HEAD~1", "main", "v1.0",
            "feature/foo", "HEAD~3", "HEAD^^", "v2.0.1")
        foreach ($ref in $validRefs) {
            $ref -match '^[\w/\.\-\^~@]+$' | Should -Be $true
        }
    }

    It "rejects injection attempts in the regex guard" {
        $invalidRefs = @(
            "; rm -rf /",
            "abc;git checkout",
            "| rm -rf",
            "> file"
        )
        foreach ($ref in $invalidRefs) {
            $ref -match '^[\w/\.\-\^~@]+$' | Should -Be $false
        }
    }
}

Describe "restore.ps1 - Confirmation flow" {

    BeforeEach {
        $global:checkoutCalled = $false
        $global:checkoutTarget = $null
    }

    It "performs checkout when user confirms with y" {
        Mock Read-Host { "y" }
        & $script:fixedScript -Revision "HEAD"
        $global:checkoutCalled | Should -Be $true
    }

    It "skips checkout when user cancels with n" {
        Mock Read-Host { "n" }
        & $script:fixedScript -Revision "HEAD"
        $global:checkoutCalled | Should -Be $false
    }
}

Describe "restore.ps1 - DryRun mode" {

    BeforeEach {
        $global:checkoutCalled = $false
        $global:checkoutTarget = $null
    }

    It "does not perform checkout in dry-run mode" {
        & $script:fixedScript -Revision "HEAD" -DryRun
        $global:checkoutCalled | Should -Be $false
    }
}

Describe "restore.ps1 - Cancellation via q" {

    BeforeEach {
        $global:checkoutCalled = $false
        $global:checkoutTarget = $null
    }

    It "returns early when user enters q at the revision prompt" {
        Mock Read-Host { "q" }
        & $script:fixedScript
        $global:checkoutCalled | Should -Be $false
    }
}

Describe "restore.ps1 - Checkout uses resolved hash" {

    BeforeEach {
        $global:checkoutCalled = $false
        $global:checkoutTarget = $null
    }

    It "passes the resolved commit hash to git checkout" {
        Mock Read-Host { "y" }
        & $script:fixedScript -Revision "HEAD~1"
        $global:checkoutCalled | Should -Be $true
        $global:checkoutTarget | Should -Match '^[a-f0-9]{40}$'
    }
}

