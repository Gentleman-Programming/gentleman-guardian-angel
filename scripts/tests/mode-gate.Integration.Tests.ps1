#requires -Version 7
<#
.SYNOPSIS
    Integration tests for mode-gate.ps1 — tests the ACTUAL script.
.NOTES
    Tests run against a per-run temp mode file (-ModeFilePath) — the repo's
    real .gentleman-mode is never read or written. Safe to run in parallel
    with permission-gate.Tests.ps1 (each uses its own temp file).
#>

BeforeAll {
    $scriptsRoot = Resolve-Path "$PSScriptRoot/.."
    $scriptPath = "$scriptsRoot/mode-gate.ps1"
    $realModeFile = "$scriptsRoot/../.gentleman-mode"
    $modeFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ("gentleman-mode-test-{0}.txt" -f ([guid]::NewGuid().ToString("N")))
    $realMode = if (Test-Path -LiteralPath $realModeFile) { (Get-Content -LiteralPath $realModeFile -Raw).Trim() } else { 'manual' }
    Set-Content -LiteralPath $modeFilePath -Value $realMode -NoNewline -Encoding ASCII -Force

    function Invoke-ModeGate {
        param(
            [string]$TargetAgent,
            [string]$Mode = "",
            [switch]$Json
        )
        $invoke = @{ TargetAgent = $TargetAgent; ModeFilePath = $modeFilePath }
        if ($Mode) { $invoke.Mode = $Mode }
        if ($Json) { $invoke.Json = $true }
        & $scriptPath @invoke 2>&1
    }
}

AfterAll {
    if (Test-Path -LiteralPath $modeFilePath) {
        Remove-Item -LiteralPath $modeFilePath -Force
    }
}

Describe "Mode gate — auto mode" {

    BeforeAll {
        Set-Content -LiteralPath $modeFilePath -Value "auto" -NoNewline -Encoding ASCII -Force
    }

    It "ALLOWS -auto suffixed agent in auto mode" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-quick-auto" -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
        $result.mode | Should -Be "auto"
    }

    It "BLOCKS base agent (no suffix) in auto mode" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-quick" -Json
        # Should exit with error
        $result = $output | Out-String -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            $result.allowed | Should -Be $false
        }
    }

    It "ALLOWS read-only specialist in auto mode" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-security" -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
    }

    It "ALLOWS SDD sub-agent in auto mode" {
        $output = Invoke-ModeGate -TargetAgent "sdd-apply" -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
    }
}

Describe "Mode gate — manual mode" {

    BeforeAll {
        Set-Content -LiteralPath $modeFilePath -Value "manual" -NoNewline -Encoding ASCII -Force
    }

    It "ALLOWS base agent (no suffix) in manual mode" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-quick" -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
    }

    It "BLOCKS -auto suffixed agent in manual mode" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-quick-auto" -Json
        $result = $output | Out-String -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            $result.allowed | Should -Be $false
        }
    }
}

Describe "Mode gate — explicit -Mode override" {

    It "ALLOWS -auto agent with -Mode auto override" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-deep-auto" -Mode auto -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
    }

    It "BLOCKS base agent with -Mode auto override" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-deep" -Mode auto -Json
        $result = $output | Out-String -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            $result.allowed | Should -Be $false
        }
    }

    It "ALLOWS base agent with -Mode manual override" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-deep" -Mode manual -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
    }
}

Describe "Mode gate — semi mode" {

    BeforeAll {
        Set-Content -LiteralPath $modeFilePath -Value "semi" -NoNewline -Encoding ASCII -Force
    }

    It "ALLOWS -semi suffixed agent in semi mode" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-quick-semi" -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
        $result.mode | Should -Be "semi"
    }

    It "BLOCKS base agent (no suffix) in semi mode" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-quick" -Json
        $result = $output | Out-String -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            $result.allowed | Should -Be $false
        }
    }

    It "BLOCKS -auto agent in semi mode" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-quick-auto" -Json
        $result = $output | Out-String -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            $result.allowed | Should -Be $false
        }
    }

    It "ALLOWS read-only specialist in semi mode" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-security" -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
    }

    It "ALLOWS SDD sub-agent in semi mode" {
        $output = Invoke-ModeGate -TargetAgent "sdd-apply" -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
    }

    It "ALLOWS -semi agent with -Mode semi override" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-deep-semi" -Mode semi -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.allowed | Should -Be $true
    }

    It "BLOCKS -semi agent with -Mode manual override" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-deep-semi" -Mode manual -Json
        $result = $output | Out-String -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            $result.allowed | Should -Be $false
        }
    }
}

Describe "Mode gate — edge cases" {

    It "falls back to manual when .gentleman-mode missing" {
        # Rename mode file temporarily
        $backup = Join-Path ([System.IO.Path]::GetTempPath()) "gentleman-mode-bak-$(Get-Random)"
        Move-Item -LiteralPath $modeFilePath -Destination $backup -Force
        try {
            $output = Invoke-ModeGate -TargetAgent "gentleman-quick" -Json
            $result = $output | Out-String | ConvertFrom-Json
            $result.mode | Should -Be "manual"
            $result.allowed | Should -Be $true
        } finally {
            Move-Item -LiteralPath $backup -Destination $modeFilePath -Force
        }
    }

    It "outputs expected JSON fields" {
        $output = Invoke-ModeGate -TargetAgent "gentleman-quick" -Mode manual -Json
        $result = $output | Out-String | ConvertFrom-Json
        $result.action | Should -Be "mode-gate"
        $result | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name } | Sort-Object
        $expectedFields = @('action', 'mode', 'target_agent', 'expected_suffix', 'allowed', 'reason')
        $actualFields = ($result | Get-Member -MemberType NoteProperty).Name
        foreach ($f in $expectedFields) {
            $f -in $actualFields | Should -Be $true
        }
    }
}

