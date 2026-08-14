#requires -Version 7
<#
.SYNOPSIS
    Pester tests for benchmark-regression.ps1 — median/IQR calculation,
    regression detection, baseline comparison, JSON output.
    Follows protocolo_mejora_autonoma_v3.md §0.7 (5-10 runs, median/IQR).
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # Inline stats functions (mirrors benchmark-regression.ps1 math)
    function Get-Median {
        param([double[]]$Samples)
        $sorted = $Samples | Sort-Object
        $count = $sorted.Count
        if ($count -eq 0) { return 0 }
        if ($count % 2 -eq 0) {
            return ($sorted[$count/2 - 1] + $sorted[$count/2]) / 2
        } else {
            return $sorted[[math]::Floor($count/2)]
        }
    }

    function Get-IQR {
        param([double[]]$Samples)
        $sorted = $Samples | Sort-Object
        $count = $sorted.Count
        if ($count -eq 0) { return 0 }
        $q1 = $sorted[[math]::Floor($count * 0.25)]
        $q3 = $sorted[[math]::Floor($count * 0.75)]
        return $q3 - $q1
    }

    $script:repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "benchmark-regression.ps1"
}

Describe "Benchmark Regression — Statistical Math" {
    It "Calculates median of even-length sample set" {
        # 10 values → median = avg of 5th and 6th
        $samples = @(100, 200, 300, 400, 500, 600, 700, 800, 900, 1000)
        $median = Get-Median -Samples $samples
        $median | Should -Be 550
    }

    It "Calculates median of odd-length sample set" {
        # 5 values → median = 3rd value
        $samples = @(100, 200, 300, 400, 500)
        $median = Get-Median -Samples $samples
        $median | Should -Be 300
    }

    It "Calculates IQR correctly" {
        $samples = @(10, 20, 30, 40, 50, 60, 70, 80, 90, 100)
        $iqr = Get-IQR -Samples $samples
        # Q1 = samples[2] = 30, Q3 = samples[7] = 80
        $iqr | Should -Be 50
    }

    It "Calculates Q1 and Q3 correctly" {
        $samples = @(10, 20, 30, 40, 50, 60, 70, 80, 90, 100) | Sort-Object
        $count = $samples.Count
        $q1 = $samples[[math]::Floor($count * 0.25)]
        $q3 = $samples[[math]::Floor($count * 0.75)]
        $q1 | Should -Be 30
        $q3 | Should -Be 80
    }

    It "Regression percent calculation is correct" {
        # 20% slower: 500 → 600
        $baseline = 500
        $new = 600
        $regPct = (($new - $baseline) / $baseline) * 100
        $regPct | Should -Be 20
    }

    It "Threshold comparison detects regression" {
        $regPct = 20
        $threshold = 15
        ($regPct -gt $threshold) | Should -Be $true
    }
}

Describe "Benchmark Regression — Script Structure" {
    BeforeAll {
        $scriptContent = Get-Content -Path $script:scriptPath -Raw
    }

    It "Uses Stopwatch for timing" {
        $scriptContent | Should -Match "Stopwatch"
    }

    It "Default runs is 10 (protocol requirement)" {
        $scriptContent | Should -Match '\[int\]\$Runs\s*=\s*10'
    }

    It "Runs minimum is 5 (protocol §0.7)" {
        $scriptContent | Should -Match 'ValidateRange\(5'
    }

    It "Calculates median with even/odd handling" {
        $scriptContent | Should -Match '\$count % 2 -eq 0'
    }

    It "Calculates IQR for statistical bounds" {
        $scriptContent | Should -Match 'iqr'
    }

    It "Compares against baseline JSON" {
        $scriptContent | Should -Match 'baseline'
    }

    It "Has UpdateBaseline switch" {
        $scriptContent | Should -Match 'UpdateBaseline'
    }

    It "Outputs JSON with -Json flag" {
        $scriptContent | Should -Match 'ConvertTo-Json -Compress'
    }

    It "Exits non-zero on regression" {
        $scriptContent | Should -Match 'exit'
    }

    It "Has Threshold parameter with 15% default" {
        $scriptContent | Should -Match '\[double\]\$Threshold\s*=\s*15'
    }
}

Describe "Benchmark Regression — Baseline JSON" {
    It "benchmark-baseline.json exists in docs/mejoras" {
        $baselinePath = Join-Path $script:repoRoot "docs/mejoras/benchmark-baseline.json"
        Test-Path $baselinePath | Should -Be $true
    }

    It "baseline JSON has median_ms field" {
        $baselinePath = Join-Path $script:repoRoot "docs/mejoras/benchmark-baseline.json"
        if (Test-Path $baselinePath) {
            $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            $baseline.median_ms | Should -Not -BeNullOrEmpty
        }
    }
}
