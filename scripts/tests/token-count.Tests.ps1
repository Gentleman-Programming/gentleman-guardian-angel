#requires -Version 7
<#
.SYNOPSIS
    Pester tests for token-count.ps1 — unified chars/3.5 heuristic divisor (R7).
.NOTES
    Uses a temp file and runs the real script (return value = grand total).
#>
Set-StrictMode -Version Latest

BeforeAll {
    $script:tc = Resolve-Path "$PSScriptRoot/../token-count.ps1"
    $script:tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pester-tokencount-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:tmpRoot -Force | Out-Null
    $content = "a" * 70
    Set-Content -Path (Join-Path $script:tmpRoot "sample.md") -Value $content -NoNewline
}

AfterAll {
    if (Test-Path $script:tmpRoot) {
        Remove-Item -Path $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'R7: heuristic divisor defaults to chars/3.5' {
    It 'estimates ~chars/3.5 tokens by default' {
        $out = & $script:tc -Path (Join-Path $script:tmpRoot "sample.md") -Quiet
        @($out)[0] | Should -Be ([int](70 / 3.5))
    }

    It 'honors an explicit -Divisor' {
        $out = & $script:tc -Path (Join-Path $script:tmpRoot "sample.md") -Quiet -Divisor 7
        @($out)[0] | Should -Be 10
    }
}

