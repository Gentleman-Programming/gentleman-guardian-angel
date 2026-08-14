#requires -Version 7

<#
.SYNOPSIS
    Pester tests for benchmark.ps1 — R6 pinned-baseline gate + time-series
    snapshots, R8 dead-junction metric, R8b CI-aware junction coverage gate
    (skipped when $env:CI / $env:GITHUB_ACTIONS is set). Runs the REAL script
    in-process and asserts exit codes via $LASTEXITCODE.
.NOTES
    ponytail: the snapshot test writes benchmarks/YYYY-MM-DD.json and cleans up.
    Junction state is controlled by overriding $env:USERPROFILE INSIDE a child
    pwsh process (process-wide env mutation would race with parallel test files).
#>
Set-StrictMode -Version Latest

BeforeAll {
    $script:bench = Resolve-Path "$PSScriptRoot/../benchmark.ps1"
    $script:root = Resolve-Path "$PSScriptRoot/../.."
    $script:benchmarksDir = Join-Path $script:root "benchmarks"
    $script:latDir = Join-Path $script:root "docs\metricas\snapshots"
}

Describe 'R6: pinned baseline gate' {

    It 'fails the gate when no pinned baseline exists' {
        $missing = Join-Path ([System.IO.Path]::GetTempPath()) "bench-missing-$([guid]::NewGuid()).json"
        $out = & $script:bench -Gate -Baseline $missing 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 2
        $out | Should -Match "run benchmark.ps1 -SetBaseline"
    }

    It 'passes the gate when current metrics are at or above the baseline' {
        $bl = Join-Path ([System.IO.Path]::GetTempPath()) "bench-cur-$([guid]::NewGuid()).json"
        try {
            & $script:bench -Json | Out-File $bl -Encoding utf8
            $out = & $script:bench -Gate -Baseline $bl 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $out | Should -Not -Match "REGRESSIONS"
        } finally {
            Remove-Item $bl -Force -ErrorAction SilentlyContinue
        }
    }

    It 'pins the baseline with -SetBaseline' {
        $bl = Join-Path ([System.IO.Path]::GetTempPath()) "bench-pin-$([guid]::NewGuid()).json"
        try {
            & $script:bench -SetBaseline -Baseline $bl 2>&1 | Out-Null
            Test-Path $bl | Should -Be $true
            $b = Get-Content $bl -Raw | ConvertFrom-Json
            $b.system.DeadJunctions | Should -Not -Be $null
            $b.system.BenchmarkSeconds | Should -BeGreaterThan 0
            $b.system.TokenEstimate | Should -BeGreaterThan 0
        } finally {
            Remove-Item $bl -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes a dated benchmark snapshot plus LATEST' {
        $today = Get-Date -Format "yyyy-MM-dd"
        $snapFile = Join-Path $script:benchmarksDir "$today.json"
        $latFile = Join-Path $script:latDir "LATEST_benchmark.json"
        $pre = Test-Path $snapFile
        $backup = if ($pre) { Get-Content $snapFile -Raw } else { $null }
        if ($pre) { Remove-Item $snapFile -Force }
        try {
            & $script:bench -Snapshot 2>&1 | Out-Null
            Test-Path $snapFile | Should -Be $true
            Test-Path $latFile | Should -Be $true
            $s = Get-Content $snapFile -Raw | ConvertFrom-Json
            $s.system.DeadJunctions | Should -Not -Be $null
            $s.system.TokenEstimate | Should -BeGreaterThan 0
        } finally {
            if ($pre) { Set-Content $snapFile $backup -Encoding UTF8 -NoNewline }
            else { Remove-Item $snapFile -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'R8: junction validity (DeadJunctions)' {

    It 'counts a dead junction and fails the gate' {
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "bench-r8-$([guid]::NewGuid())"
        $fakeSkills = Join-Path $tmpRoot ".config\opencode\skills"
        New-Item -ItemType Directory -Path $fakeSkills -Force | Out-Null
        $skillName = @(Get-ChildItem (Join-Path $script:root ".agents\skills") -Directory | Where-Object { $_.Name -ne '_shared' })[0].Name
        $ghost = Join-Path $tmpRoot "ghost-target"
        New-Item -ItemType Directory -Path $ghost -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $fakeSkills $skillName) -Target $ghost -Force | Out-Null
        Remove-Item $ghost -Recurse -Force
        $bl = Join-Path $tmpRoot "baseline.json"
        try {
            # Run benchmark in a CHILD pwsh so $env:USERPROFILE is overridden only there —
            # process-wide env mutation would race with parallel test files (restore.Tests).
            $jsonRun = "`$env:USERPROFILE='$tmpRoot'; & '$($script:bench.Path)' -Json"
            & pwsh -NoProfile -Command $jsonRun | Out-File $bl -Encoding utf8
            $obj = Get-Content $bl -Raw | ConvertFrom-Json
            $obj.system.DeadJunctions | Should -BeGreaterThan 0
            # 'exit' inside a &-called script returns control (does NOT propagate the
            # code in pwsh -Command) — re-exit explicitly to surface the gate failure.
            $gateRun = "`$env:USERPROFILE='$tmpRoot'; & '$($script:bench.Path)' -Gate -Baseline '$bl'; if(`$LASTEXITCODE) { exit `$LASTEXITCODE }"
            $out = & pwsh -NoProfile -Command $gateRun 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 2
            $out | Should -Match "Dead junctions"
        } finally {
            Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'R8b: CI-aware junction coverage gate' {

    It 'fails on junction-coverage regression when not in CI' {
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "bench-r8b-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
        $bl = Join-Path $tmpRoot "baseline.json"
        try {
            # Baseline pinned in a junctioned env (simulates the repo baseline, jo=78).
            $jsonRun = "`$env:USERPROFILE='$tmpRoot'; & '$($script:bench.Path)' -Json"
            & pwsh -NoProfile -Command $jsonRun | Out-File $bl -Encoding utf8
            $obj = Get-Content $bl -Raw | ConvertFrom-Json
            $obj.system.GlobalJunctionsOk = 78
            $obj | ConvertTo-Json -Depth 3 | Out-File $bl -Encoding utf8
            # Same fake env WITHOUT junctions (jo=0 < 78) and CI vars explicitly cleared.
            $gateRun = "`$env:USERPROFILE='$tmpRoot'; `$env:CI=`$null; Remove-Item Env:GITHUB_ACTIONS -ErrorAction SilentlyContinue; & '$($script:bench.Path)' -Gate -Baseline '$bl'; if(`$LASTEXITCODE) { exit `$LASTEXITCODE }"
            $out = & pwsh -NoProfile -Command $gateRun 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 2
            $out | Should -Match "Global junctions decreased"
        } finally {
            Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'skips the junction-coverage regression when CI=1' {
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "bench-r8b-ci-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
        $bl = Join-Path $tmpRoot "baseline.json"
        try {
            $jsonRun = "`$env:USERPROFILE='$tmpRoot'; & '$($script:bench.Path)' -Json"
            & pwsh -NoProfile -Command $jsonRun | Out-File $bl -Encoding utf8
            $obj = Get-Content $bl -Raw | ConvertFrom-Json
            $obj.system.GlobalJunctionsOk = 78
            $obj | ConvertTo-Json -Depth 3 | Out-File $bl -Encoding utf8
            # Same 0-junction env, but CI=1 → coverage regression skipped → gate passes.
            $gateRun = "`$env:USERPROFILE='$tmpRoot'; `$env:CI='1'; Remove-Item Env:GITHUB_ACTIONS -ErrorAction SilentlyContinue; & '$($script:bench.Path)' -Gate -Baseline '$bl'; if(`$LASTEXITCODE) { exit `$LASTEXITCODE }"
            $out = & pwsh -NoProfile -Command $gateRun 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $out | Should -Not -Match "REGRESSIONS"
        } finally {
            Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

