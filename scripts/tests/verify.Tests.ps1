#requires -Version 7
<#
.SYNOPSIS
    Tests for scripts/verify.ps1 (E1/E2/E3 profiles) — uses THROWAWAY temp repos,
    never touches the real repository state.
#>
BeforeAll {
    $script:verify = Join-Path $PSScriptRoot '..\verify.ps1'
    $script:testDir = Join-Path $env:TEMP "verify-test-$PID"

    function New-VerifyRepo {
        param([string]$Name)
        $repo = Join-Path $script:testDir $Name
        New-Item -ItemType Directory -Path (Join-Path $repo 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repo '.agents\skills') -Force | Out-Null
        Push-Location $repo
        git init -q 2>$null
        git -c user.email=test@test -c user.name=test commit -q --allow-empty -m 'baseline' 2>$null
        Pop-Location
        return $repo
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'verify.ps1 — E1 syntax profile' {
    It 'flags invalid .ps1 syntax in target root' {
        $repo = New-VerifyRepo 'e1-invalid'
        Set-Content -LiteralPath (Join-Path $repo 'scripts\bad.ps1') -Value 'function {' -Encoding Ascii
        $out = & $script:verify -ProfileName E1 -Root $repo -Json -Quiet
        $r = $out | ConvertFrom-Json
        $r.allPassed | Should -Be $false
        ($r.checks | Where-Object name -eq 'PS Syntax').passed | Should -Be $false
    }

    It 'passes syntax with valid scripts' {
        $repo = New-VerifyRepo 'e1-valid'
        Set-Content -LiteralPath (Join-Path $repo 'scripts\ok.ps1') -Value 'Write-Output 1' -Encoding Ascii
        $out = & $script:verify -ProfileName E1 -Root $repo -Json -Quiet
        $r = $out | ConvertFrom-Json
        ($r.checks | Where-Object name -eq 'PS Syntax').passed | Should -Be $true
    }
}

Describe 'verify.ps1 — E2 secrets scan' {
    It 'detects secret patterns in target root' {
        $repo = New-VerifyRepo 'e2-secret'
        Set-Content -LiteralPath (Join-Path $repo 'scripts\leak.ps1') -Value 'password=supersecret123' -Encoding Ascii
        $out = & $script:verify -ProfileName E2 -Root $repo -Json -Quiet
        $r = $out | ConvertFrom-Json
        ($r.checks | Where-Object name -eq 'Secrets Scan').passed | Should -Be $false
    }

    It 'passes when no secret patterns present' {
        $repo = New-VerifyRepo 'e2-clean'
        Set-Content -LiteralPath (Join-Path $repo 'scripts\ok.ps1') -Value 'Write-Output "hello"' -Encoding Ascii
        $out = & $script:verify -ProfileName E2 -Root $repo -Json -Quiet
        $r = $out | ConvertFrom-Json
        ($r.checks | Where-Object name -eq 'Secrets Scan').passed | Should -Be $true
    }
}

Describe 'verify.ps1 — E3 structural checks' {
    It 'validates .project.json score structure' {
        $repo = New-VerifyRepo 'e3-score'
        $pj = @{
            score = @{
                dimensions = @{ a = 1; b = 2; c = 3; d = 4; e = 5; f = 6; g = 7 }
                current = 8.5
            }
        }
        $pj | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $repo '.project.json') -Encoding UTF8
        $out = & $script:verify -ProfileName E3 -Root $repo -Json -Quiet
        $r = $out | ConvertFrom-Json
        ($r.checks | Where-Object name -eq '.project.json').passed | Should -Be $true
    }

    It 'fails on malformed .project.json' {
        $repo = New-VerifyRepo 'e3-badscore'
        Set-Content -LiteralPath (Join-Path $repo '.project.json') -Value '{ not json' -Encoding Ascii
        $out = & $script:verify -ProfileName E3 -Root $repo -Json -Quiet
        $r = $out | ConvertFrom-Json
        ($r.checks | Where-Object name -eq '.project.json').passed | Should -Be $false
    }
}

Describe 'verify.ps1 — JSON contract' {
    It 'emits a stable JSON envelope with counts' {
        $repo = New-VerifyRepo 'e2-envelope'
        $out = & $script:verify -ProfileName E1 -Root $repo -Json -Quiet
        $r = $out | ConvertFrom-Json
        $r.checks.Count | Should -BeGreaterOrEqual 1
        $r.passed | Should -BeGreaterOrEqual 0
        $r.failed | Should -BeGreaterOrEqual 0
        $r.allPassed | Should -BeOfType [bool]
    }
}

