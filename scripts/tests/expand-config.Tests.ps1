#requires -Version 7
<#
.SYNOPSIS
    Tests for scripts/opencode-config/expand-config.ps1 — runs against a THROWAWAY
    copy of the script in a temp repo, never touches the real opencode.json.
#>
BeforeAll {
    $script:src = Join-Path $PSScriptRoot '..\opencode-config\expand-config.ps1'
    $script:testDir = Join-Path $env:TEMP "expand-config-test-$PID"

    function New-ExpandRepo {
        param([string]$Name)
        $repo = Join-Path $script:testDir $Name
        $scriptDir = Join-Path $repo 'scripts\opencode-config'
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        Copy-Item -LiteralPath $script:src -Destination (Join-Path $scriptDir 'expand-config.ps1')
        return $repo
    }

    function Set-ConfigWithImport {
        param([string]$Repo)
        New-Item -ItemType Directory -Path (Join-Path $Repo 'rules') -Force | Out-Null
        @{ 'git push' = 'deny'; 'rm -rf' = 'deny' } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $Repo 'rules\deny.json') -Encoding UTF8
        @'
{
    "permission": {
        "bash": {
            "deny": [
                {
                    "$import": "rules/deny.json"
                }
            ]
        }
    }
}
'@ | Set-Content -LiteralPath (Join-Path $Repo 'opencode.json') -Encoding UTF8
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'expand-config.ps1 — import expansion' {
    It 'expands $import markers inline and keeps valid JSON' {
        $repo = New-ExpandRepo 'imp-ok'
        Set-ConfigWithImport $repo
        $cfg = Join-Path $repo 'opencode.json'

        & (Join-Path $repo 'scripts\opencode-config\expand-config.ps1') -Quiet

        $out = Get-Content -LiteralPath $cfg -Raw
        $out | Should -Not -Match '\$import'
        $out | Should -Match '"git push": "deny"'
        { $null = $out | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'is idempotent — second run leaves the file unchanged' {
        $repo = New-ExpandRepo 'imp-idem'
        Set-ConfigWithImport $repo
        $cfg = Join-Path $repo 'opencode.json'

        & (Join-Path $repo 'scripts\opencode-config\expand-config.ps1') -Quiet
        $first = Get-Content -LiteralPath $cfg -Raw

        & (Join-Path $repo 'scripts\opencode-config\expand-config.ps1') -Quiet
        $second = Get-Content -LiteralPath $cfg -Raw

        $second | Should -Be $first
    }
}

Describe 'expand-config.ps1 — edge cases' {
    It 'does not write when the import path is missing' {
        $repo = New-ExpandRepo 'imp-missing'
        @'
{
    "permission": {
        "bash": {
            "deny": [ { "$import": "rules/nope.json" } ]
        }
    }
}
'@ | Set-Content -LiteralPath (Join-Path $repo 'opencode.json') -Encoding UTF8
        $cfg = Join-Path $repo 'opencode.json'
        $before = Get-Content -LiteralPath $cfg -Raw

        & (Join-Path $repo 'scripts\opencode-config\expand-config.ps1') -Quiet 2>$null

        (Get-Content -LiteralPath $cfg -Raw) | Should -Be $before
    }

    It 'leaves already-expanded config untouched' {
        $repo = New-ExpandRepo 'imp-none'
        @'
{
    "permission": { "bash": { "deny": [] } }
}
'@ | Set-Content -LiteralPath (Join-Path $repo 'opencode.json') -Encoding UTF8
        $cfg = Join-Path $repo 'opencode.json'
        $before = Get-Content -LiteralPath $cfg -Raw

        & (Join-Path $repo 'scripts\opencode-config\expand-config.ps1') -Quiet 2>$null

        (Get-Content -LiteralPath $cfg -Raw) | Should -Be $before
    }

    It 'fails fast when opencode.json is missing' {
        $repo = New-ExpandRepo 'imp-nocfg'
        { & (Join-Path $repo 'scripts\opencode-config\expand-config.ps1') -Quiet 2>$null } |
            Should -Throw -ExpectedMessage '*opencode.json not found*'
    }
}

