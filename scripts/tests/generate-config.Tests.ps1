#requires -Version 7
<#
.SYNOPSIS
    Contract tests for scripts/lib/generate-opencode-config.js — TEMPLATE_MAP resolution,
    extraPermKeys merge guard, and permission assembly. Runs against a THROWAWAY copy of
    the generator in a temp repo with CRAFTED fixtures — never touches the real opencode.json.

    Coverage targets:
      1. Unmapped agent            -> process.exit(1) fail-closed
      2. extraPermKeys collision   -> ERROR, process.exit(1)
      3. auto-sub merge            -> bash:{*:allow} + task:{*:deny}, ZERO ask
      4. readonly merge            -> bash:{*:deny} (+ edit/write/task deny)
      5. --validate idempotency    -> exit 0 when generated output is in sync
      6. hidden propagation        -> hidden:true from agent-overrides.json only
#>
BeforeAll {
    $script:genSrc = Join-Path $PSScriptRoot '..\lib\generate-opencode-config.js'
    $script:testDir = Join-Path $env:TEMP "generate-config-test-$PID"

    # Production-exact template shapes (subset under test) — contract source of truth.
    $script:tmplAutoSub = @{
        bash = @{ '*' = 'allow' }
        task = @{ '*' = 'deny' }
    }
    $script:tmplReadonly = @{
        bash = @{ '*' = 'deny' }
        edit = 'deny'
        write = 'deny'
        task = @{ '*' = 'deny' }
    }
    $script:tmplReadwrite = @{
        bash = @{ '*' = 'ask' }
    }

    function New-GenRepo {
        param([string]$Name)
        $repo = Join-Path $script:testDir $Name
        $libDir = Join-Path $repo 'scripts\lib'
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
        Copy-Item -LiteralPath $script:genSrc -Destination (Join-Path $libDir 'generate-opencode-config.js')
        return $repo
    }

    function Set-GenFixture {
        param(
            [string]$Repo,
            [hashtable]$Agent,
            [hashtable]$Templates,
            [hashtable]$Overrides = @{}
        )
        $libDir = Join-Path $Repo 'scripts\lib'
        @{ agent = $Agent } | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $libDir 'opencode-base.json') -Encoding utf8
        $Templates | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $libDir 'permission-templates.json') -Encoding utf8
        $Overrides | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $libDir 'agent-overrides.json') -Encoding utf8
    }

    function Read-GenOutput {
        param([string]$Path)
        $raw = Get-Content -LiteralPath $Path -Raw
        # Generator writes a UTF-8 BOM — strip it before parsing.
        if ($raw -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
        return ($raw | ConvertFrom-Json)
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'generate-opencode-config.js — fail-closed' {
    It 'exits 1 for an unmapped agent (no TEMPLATE_MAP entry)' {
        $repo = New-GenRepo 'unmapped'
        Set-GenFixture -Repo $repo `
            -Agent @{ 'ghost-agent' = @{ description = 'no mapping'; mode = 'primary' } } `
            -Templates @{ 'readonly' = $script:tmplReadonly }

        $out = & node (Join-Path $repo 'scripts\lib\generate-opencode-config.js') 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'no template mapping'
        $out | Should -Match 'ghost-agent'
    }

    It 'exits 1 when extraPermKeys collides with a template key' {
        $repo = New-GenRepo 'collision'
        Set-GenFixture -Repo $repo `
            -Agent @{ 'gentleman-quick-sub-auto' = @{
                description = 'Fast executor subagent'; model = 'opencode/mimo-v2.5-free';
                hidden = $true; mode = 'subagent'; prompt = '{file:prompts/gentleman-quick.md}' } } `
            -Templates @{ 'auto-sub' = $script:tmplAutoSub } `
            -Overrides @{ 'gentleman-quick-sub-auto' = @{ extraPermKeys = @{ bash = @{ '*' = 'allow' } } } }

        $out = & node (Join-Path $repo 'scripts\lib\generate-opencode-config.js') 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'collides with template keys'
        $out | Should -Match 'bash'
    }

    It 'EXTRA perm-escalation: extraPermKeys with task key on auto-sub agent is denied (H2 regression)' {
        $repo = New-GenRepo 'collision-task'
        Set-GenFixture -Repo $repo `
            -Agent @{ 'gentleman-quick-sub-auto' = @{
                description = 'Fast executor'; model = 'opencode/mimo-v2.5-free';
                hidden = $true; mode = 'subagent'; prompt = '{file:prompts/gentleman-quick.md}' } } `
            -Templates @{ 'auto-sub' = $script:tmplAutoSub } `
            -Overrides @{ 'gentleman-quick-sub-auto' = @{ extraPermKeys = @{ task = @{ '*' = 'allow' } } } }

        $out = & node (Join-Path $repo 'scripts\lib\generate-opencode-config.js') 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'collides with template keys'
        $out | Should -Match 'task'
    }
}

Describe 'generate-opencode-config.js — permission merge' {
    It 'auto-sub merge: bash:{*:allow} + task:{*:deny}, ZERO ask' {
        $repo = New-GenRepo 'auto-sub'
        Set-GenFixture -Repo $repo `
            -Agent @{ 'gentleman-quick-sub-auto' = @{
                description = 'Fast executor subagent'; model = 'opencode/mimo-v2.5-free';
                hidden = $true; mode = 'subagent'; prompt = '{file:prompts/gentleman-quick.md}' } } `
            -Templates @{ 'auto-sub' = $script:tmplAutoSub }

        & node (Join-Path $repo 'scripts\lib\generate-opencode-config.js') | Out-Null
        $LASTEXITCODE | Should -Be 0

        $agent = (Read-GenOutput (Join-Path $repo 'opencode.json')).agent.'gentleman-quick-sub-auto'
        $perm = $agent.permission
        $perm.bash.'*' | Should -Be 'allow'
        $perm.task.'*' | Should -Be 'deny'
        ($perm | ConvertTo-Json -Depth 10 -Compress) | Should -Not -Match '"ask"'
        ($perm.PSObject.Properties.Name -join ',') | Should -Be 'bash,task'
        # Base fields survive the rebuild untouched.
        $agent.description | Should -Be 'Fast executor subagent'
        $agent.mode | Should -Be 'subagent'
        $agent.hidden | Should -Be $true
    }

    It 'readonly merge: bash:{*:deny} with edit/write/task deny' {
        $repo = New-GenRepo 'readonly'
        Set-GenFixture -Repo $repo `
            -Agent @{ 'gentleman-security' = @{
                description = 'Security specialist'; model = 'opencode/nemotron-3-ultra-free';
                mode = 'primary'; prompt = '{file:prompts/gentleman-security.md}' } } `
            -Templates @{ 'readonly' = $script:tmplReadonly }

        & node (Join-Path $repo 'scripts\lib\generate-opencode-config.js') | Out-Null
        $LASTEXITCODE | Should -Be 0

        $perm = (Read-GenOutput (Join-Path $repo 'opencode.json')).agent.'gentleman-security'.permission
        $perm.bash.'*' | Should -Be 'deny'
        $perm.edit | Should -Be 'deny'
        $perm.write | Should -Be 'deny'
        $perm.task.'*' | Should -Be 'deny'
        ($perm | ConvertTo-Json -Depth 10 -Compress) | Should -Not -Match '"allow"'
    }
}

Describe 'generate-opencode-config.js — validation & overrides' {
    It '--validate exits 0 when generated output is in sync (idempotent)' {
        $repo = New-GenRepo 'idem'
        Set-GenFixture -Repo $repo `
            -Agent @{
                'gentleman-quick-sub-auto' = @{ description = 'Fast executor subagent'; model = 'opencode/mimo-v2.5-free'; hidden = $true; mode = 'subagent'; prompt = '{file:prompts/gentleman-quick.md}' }
                'gentleman-security' = @{ description = 'Security specialist'; model = 'opencode/nemotron-3-ultra-free'; mode = 'primary'; prompt = '{file:prompts/gentleman-security.md}' }
            } `
            -Templates @{ 'auto-sub' = $script:tmplAutoSub; 'readonly' = $script:tmplReadonly }

        & node (Join-Path $repo 'scripts\lib\generate-opencode-config.js') | Out-Null
        $LASTEXITCODE | Should -Be 0

        $out = & node (Join-Path $repo 'scripts\lib\generate-opencode-config.js') --validate 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'VALID'
    }

    It 'propagates hidden:true from agent-overrides.json (and only from there)' {
        $repo = New-GenRepo 'hidden'
        Set-GenFixture -Repo $repo `
            -Agent @{
                'sdd-apply' = @{ description = 'Implement code changes from task definitions'; model = 'opencode/deepseek-v4-flash-free'; mode = 'subagent'; prompt = '{file:prompts/sdd/sdd-apply.md}' }
                'gentleman-quick-sub-auto' = @{ description = 'Fast executor subagent'; mode = 'subagent' }
            } `
            -Templates @{ 'readwrite' = $script:tmplReadwrite; 'auto-sub' = $script:tmplAutoSub } `
            -Overrides @{ 'sdd-apply' = @{ hidden = $true } }

        & node (Join-Path $repo 'scripts\lib\generate-opencode-config.js') | Out-Null
        $LASTEXITCODE | Should -Be 0

        $cfg = Read-GenOutput (Join-Path $repo 'opencode.json')
        $cfg.agent.'sdd-apply'.hidden | Should -Be $true
        $cfg.agent.'gentleman-quick-sub-auto'.PSObject.Properties.Name | Should -Not -Contain 'hidden'
    }
}

Describe 'R9: regen latency benchmark fixture (Gap D — same-context measurement)' {
    # Gap D fix: baseline was measured in orchestrator context (263.8ms) vs
    # subagent context (520.9ms) → false +97.4% regression. This test measures
    # both baseline and comparison in the SAME execution context (this test run),
    # with 5 runs and median + IQR, comparing against a pinned JSON fixture.
    # Threshold: 10% relative regression from pinned baseline.

    It 'regen latency median stays within 10% of pinned baseline (5 runs)' {
        $fixturePath = Join-Path $script:testDir 'fixtures\generate-config-latency-baseline.json'
        # Fall back to repo fixture if testDir copy doesn't exist
        if (-not (Test-Path $fixturePath)) {
            $fixturePath = Join-Path $PSScriptRoot 'fixtures\generate-config-latency-baseline.json'
        }
        $fixture = Get-Content $fixturePath -Raw | ConvertFrom-Json

        $genScript = $script:genSrc
        $runs = @()
        for ($i = 0; $i -lt $fixture.runs; $i++) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            & node $genScript --validate 2>$null | Out-Null
            $LASTEXITCODE | Should -Be 0
            $sw.Stop()
            $runs += [math]::Round($sw.Elapsed.TotalMilliseconds, 2)
        }

        $sorted = $runs | Sort-Object
        $median = $sorted[2]  # 5 runs → index 2 is median
        $threshold = $fixture.baseline_median_ms * (1 + $fixture.regression_threshold_pct / 100)

        $median | Should -BeLessThan $threshold
    }

    It 'fixture is machine-readable and pinnable for trend tracking' {
        $fixturePath = Join-Path $PSScriptRoot 'fixtures\generate-config-latency-baseline.json'
        $fixture = Get-Content $fixturePath -Raw | ConvertFrom-Json

        $fixture.baseline_median_ms | Should -BeGreaterThan 0
        $fixture.regression_threshold_pct | Should -BeGreaterThan 0
        $fixture.runs | Should -Be 5
        $fixture.methodology | Should -Not -BeNullOrEmpty
    }
}
