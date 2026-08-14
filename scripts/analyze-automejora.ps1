#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Project Complexity Index (PCI) + capability probe for automejora-analyzer (read-only).

.DESCRIPTION
  Scans a project root and emits: complexity tier (T1-T4), language diversity, test/coverage
  presence, CI/CD presence, dependency manifests, and a capability matrix (available tools per
  capability dimension). Never mutates anything - pure observation. PowerShell 5.1 compatible
  (no ??, ||, &&, ternary, or ::new()).

  Thresholds mirror .agents/skills/automejora-analyzer/SKILL.md section A (5-signal triage).

.PARAMETER Path
  Target project root. Default: script parent's parent (repo root when run from scripts/).

.PARAMETER Json
  Output JSON to stdout only (machine readable). Arrays are wrapped with @(...) per ADR-003
  so single-element arrays survive ConvertTo-Json serialization.

.PARAMETER WhatIf
  Dry run - print what would be scanned and exit without scanning.

.EXAMPLE
  .\scripts\analyze-automejora.ps1 -Path ..\other-project
  .\scripts\analyze-automejora.ps1 -Path ..\other-project -Json
  .\scripts\analyze-automejora.ps1 -WhatIf

.NOTES
  Read-only by design - part of the automejora-analyzer skill. No git mutation, no installs,
  no builds. Best-effort .gitignore support: built-in exclusions plus simple patterns
  (directory names and wildcard patterns); negation (!) rules are ignored.
#>
param(
    [string]$Path = "",
    [switch]$Json,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- resolve root ----------------------------------------------------------
if (-not $Path) { $Path = Split-Path $PSScriptRoot -Parent }
try { $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path }
catch { Write-Error "Path not found: $Path"; exit 2 }
$root = $resolved.TrimEnd([char[]]@('\', '/'))
$projectName = Split-Path $root -Leaf

if ($WhatIf) {
    Write-Host "[WhatIf] WOULD scan: $root" -ForegroundColor Cyan
    Write-Host "[WhatIf] WOULD probe: Pester, pytest, jest, vitest, mocha, go, cargo, dotnet, eslint, flake8, ruff, bandit, golangci-lint, PSScriptAnalyzer, npm, pip-audit, trivy, checkov, safety, lighthouse, py-spy, make"
    Write-Host "[WhatIf] WOULD detect: languages, tests, coverage, CI, dep manifests"
    Write-Host "[WhatIf] No mutation performed."
    exit 0
}

# --- helpers ---------------------------------------------------------------
$script:AlwaysExcluded = @(
    '.git', 'node_modules', '.venv', 'venv', '__pycache__', '.pytest_cache',
    '.codegraph', '.codebase-memory', '.idea', '.vscode', 'bin', 'obj',
    'coverage', 'dist', 'build', 'out', '.next', '.cache', 'temp', 'tmp',
    'backups', '.archive', '.learnings'
)

function Get-IgnoreRules {
    param([string]$Root)
    $rules = New-Object System.Collections.Generic.List[object]
    foreach ($seg in $script:AlwaysExcluded) {
        $rules.Add([pscustomobject]@{ Kind = 'seg'; Value = $seg })
    }
    $gi = Join-Path $Root '.gitignore'
    if (Test-Path -LiteralPath $gi) {
        foreach ($line in @(Get-Content -LiteralPath $gi)) {
            $l = $line.Trim()
            if ($l -eq '' -or $l.StartsWith('#')) { continue }
            if ($l.StartsWith('!')) { continue }   # negation unsupported (best-effort)
            $pat = $l.TrimStart([char[]]@('/')).TrimEnd([char[]]@('/'))
            if ($pat -match '[\*\?\[\]]') {
                $rules.Add([pscustomobject]@{ Kind = 'like'; Value = $pat })
            } else {
                $rules.Add([pscustomobject]@{ Kind = 'seg'; Value = $pat })
            }
        }
    }
    # NOTE: @($list) over List[object] throws "Argument types do not match" under
    # StrictMode Latest (verified empirically) - ToArray() is safe.
    return @($rules.ToArray())
}

function Test-Excluded {
    param([string]$RelativePath, [object[]]$Rules)
    $segments = @($RelativePath.Split('/'))
    foreach ($r in @($Rules)) {
        if ($r.Kind -eq 'seg') {
            if ($r.Value.Contains('/')) {
                if ($RelativePath -eq $r.Value -or $RelativePath.StartsWith($r.Value + '/')) { return $true }
            } else {
                foreach ($seg in $segments) { if ($seg -eq $r.Value) { return $true } }
            }
        } else {
            $name = $segments[$segments.Count - 1]
            if ($name -like $r.Value) { return $true }
            if ($RelativePath -like $r.Value) { return $true }
        }
    }
    return $false
}

function Get-SourceFiles {
    param([string]$Root, [object[]]$Rules)
    $found = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -File -Recurse -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($Root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        if (Test-Excluded -RelativePath $rel -Rules $Rules) { continue }
        $found += $f
    }
    return @($found)
}

function Test-Tool {
    param([string]$Name)
    return @(Get-Command $Name -ErrorAction SilentlyContinue).Count -gt 0
}

function Test-Module {
    param([string]$Name)
    return @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue).Count -gt 0
}

$script:LangMap = @{
    '.ps1' = 'PowerShell'; '.psm1' = 'PowerShell'; '.psd1' = 'PowerShell'
    '.js' = 'JavaScript'; '.mjs' = 'JavaScript'; '.cjs' = 'JavaScript'; '.jsx' = 'JavaScript'
    '.ts' = 'TypeScript'; '.tsx' = 'TypeScript'
    '.py' = 'Python'; '.go' = 'Go'; '.rs' = 'Rust'; '.cs' = 'C#'; '.vb' = 'VB.NET'
    '.c' = 'C'; '.cpp' = 'C++'; '.h' = 'C/C++ Header'
    '.java' = 'Java'; '.rb' = 'Ruby'; '.php' = 'PHP'; '.swift' = 'Swift'; '.kt' = 'Kotlin'
    '.scala' = 'Scala'; '.dart' = 'Dart'; '.lua' = 'Lua'
    '.sh' = 'Shell'; '.bash' = 'Shell'; '.zsh' = 'Shell'
    '.vue' = 'Vue'; '.svelte' = 'Svelte'; '.html' = 'HTML'; '.css' = 'CSS'; '.scss' = 'SCSS'; '.less' = 'Less'
    '.sql' = 'SQL'; '.tf' = 'Terraform'; '.hcl' = 'HCL'
    '.yml' = 'YAML'; '.yaml' = 'YAML'; '.json' = 'JSON'; '.toml' = 'TOML'; '.ini' = 'INI'
    '.md' = 'Markdown'; '.rst' = 'reStructuredText'; '.adoc' = 'AsciiDoc'
    '.ex' = 'Elixir'; '.exs' = 'Elixir'; '.erl' = 'Erlang'; '.hs' = 'Haskell'
}

function Get-TierLevel {
    param([int]$Files, [int]$Langs, [int]$TestScore, [int]$CiScore, [int]$DepScore)
    $levels = @(
        if ($Files -lt 25) { 1 } elseif ($Files -lt 100) { 2 } elseif ($Files -lt 500) { 3 } else { 4 }
        if ($Langs -le 1) { 1 } elseif ($Langs -eq 2) { 2 } elseif ($Langs -le 4) { 3 } else { 4 }
        $TestScore
        $CiScore
        if ($DepScore -le 0) { 1 } elseif ($DepScore -eq 1) { 2 } elseif ($DepScore -eq 2) { 3 } else { 4 }
    )
    $avg = ($levels | Measure-Object -Average).Average
    return [math]::Floor($avg + 0.5)
}

function Get-Capabilities {
    param([string]$Root, [bool]$HasTests, [bool]$HasCoverage, [bool]$HasCi, [object[]]$DepManifests)
    $cap = [ordered]@{}

    # test runner
    $testTools = @()
    if (Test-Module 'Pester') { $testTools += 'Pester' }
    foreach ($t in @('pytest', 'jest', 'vitest', 'mocha', 'go', 'cargo', 'dotnet')) { if (Test-Tool $t) { $testTools += $t } }
    $cap['testRunner'] = [ordered]@{ available = (($testTools.Count -gt 0) -or $HasTests); tools = @($testTools) }

    # linter
    $lintTools = @()
    foreach ($t in @('eslint', 'flake8', 'ruff', 'bandit', 'golangci-lint')) { if (Test-Tool $t) { $lintTools += $t } }
    if (Test-Module 'PSScriptAnalyzer') { $lintTools += 'PSScriptAnalyzer' }
    $cap['linter'] = [ordered]@{ available = ($lintTools.Count -gt 0); tools = @($lintTools) }

    # security audit
    $secTools = @()
    foreach ($t in @('npm', 'pip-audit', 'trivy', 'checkov', 'bandit', 'safety')) { if (Test-Tool $t) { $secTools += $t } }
    if ($secTools -contains 'npm' -and $DepManifests -notcontains 'package.json') {
        $secTools = @($secTools | Where-Object { $_ -ne 'npm' })
    }
    $cap['securityAudit'] = [ordered]@{ available = ($secTools.Count -gt 0); tools = @($secTools) }

    # performance
    $perfTools = @()
    foreach ($t in @('lighthouse', 'py-spy')) { if (Test-Tool $t) { $perfTools += $t } }
    $cap['performance'] = [ordered]@{ available = ($perfTools.Count -gt 0); tools = @($perfTools) }

    # build
    $buildTools = @()
    if (Test-Tool 'go') { $buildTools += 'go build' }
    if (Test-Tool 'dotnet') { $buildTools += 'dotnet build' }
    if (Test-Tool 'cargo') { $buildTools += 'cargo build' }
    if (Test-Tool 'npm') {
        $pkg = Join-Path $Root 'package.json'
        if (Test-Path -LiteralPath $pkg) {
            try {
                $parsed = Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json
                if ($null -ne $parsed.scripts -and $null -ne $parsed.scripts.PSObject.Properties['build']) {
                    $buildTools += 'npm run build'
                }
            } catch { }   # unparseable package.json -> skip
        }
    }
    $cap['build'] = [ordered]@{ available = ($buildTools.Count -gt 0); tools = @($buildTools) }

    # coverage
    $covTools = @()
    if ($HasCoverage) { $covTools += 'coverage-files' }
    if (Test-Tool 'pytest') { $covTools += 'pytest-cov' }
    $cap['coverage'] = [ordered]@{ available = ($covTools.Count -gt 0); tools = @($covTools) }

    # ci config
    $ciTools = @()
    if ($HasCi) { $ciTools += 'ci-config' }
    if (Test-Tool 'make') { $ciTools += 'make' }
    $cap['ciConfig'] = [ordered]@{ available = ($ciTools.Count -gt 0); tools = @($ciTools) }

    return $cap
}

# --- scan -------------------------------------------------------------------
$rules = @(Get-IgnoreRules -Root $root)
$sourceFiles = @(Get-SourceFiles -Root $root -Rules $rules)
$fileCount = $sourceFiles.Count

# languages
$langCounts = @{}
foreach ($f in $sourceFiles) {
    $lang = $script:LangMap[$f.Extension.ToLowerInvariant()]
    if (-not $lang) { $lang = 'Other' }
    if ($langCounts.ContainsKey($lang)) { $langCounts[$lang]++ } else { $langCounts[$lang] = 1 }
}
$languages = @($langCounts.Keys | Sort-Object)
$languageCount = $languages.Count

# tests + coverage
$testFiles = @($sourceFiles | Where-Object { $_.Name -match '\.(test|spec)\.|_test\.|\.Tests\.ps1$|^test_' })
$coverageFileNames = @('.coverage', '.lcov', 'lcov.info', 'coverage.xml', 'clover.xml', 'cobertura.xml', 'jacoco.xml', 'coverage-final.json')
$coverageFiles = @($sourceFiles | Where-Object { $_.Name -in $coverageFileNames })
$coverageDirHits = @(@('coverage', 'htmlcov', '.nyc_output') | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })
$hasTests = $testFiles.Count -gt 0
$hasCoverage = ($coverageFiles.Count -gt 0) -or ($coverageDirHits.Count -gt 0)

# CI/CD
$ciIndicators = @()
$workflowCount = 0
$workflowsDir = Join-Path $root '.github\workflows'
if (Test-Path -LiteralPath $workflowsDir) {
    $ciIndicators += '.github/workflows'
    $workflowCount = @(Get-ChildItem -LiteralPath $workflowsDir -File -Filter '*.yml' -ErrorAction SilentlyContinue).Count
    if ($workflowCount -eq 0) {
        $workflowCount = @(Get-ChildItem -LiteralPath $workflowsDir -File -Filter '*.yaml' -ErrorAction SilentlyContinue).Count
    }
}
foreach ($ind in @('.gitlab-ci.yml', 'Jenkinsfile', 'Makefile', '.circleci', 'azure-pipelines.yml', '.travis.yml', 'bitbucket-pipelines.yml')) {
    if (Test-Path -LiteralPath (Join-Path $root $ind)) { $ciIndicators += $ind }
}
$hasCi = $ciIndicators.Count -gt 0

# dependency manifests
$depNames = @('package.json', 'pyproject.toml', 'requirements.txt', 'Pipfile', 'go.mod', 'Cargo.toml',
    'composer.json', 'Gemfile', 'pom.xml', 'build.gradle', 'mix.exs', 'pubspec.yaml')
$depsFound = @($depNames | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })
$csProjHits = @(Get-ChildItem -LiteralPath $root -Filter '*.csproj' -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object {
    -not (Test-Excluded -RelativePath ($_.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')) -Rules $rules)
})
if ($csProjHits.Count -gt 0) { $depsFound += 'dotnet' }

# test dirs (for evidence)
$testDirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('test', 'tests', 'spec', 'specs', '__tests__', 'e2e') })

# evidence (relative paths only)
$evidence = @()
$evidence += $depsFound
$evidence += $ciIndicators
$evidence += @($testDirs | ForEach-Object { $_.Name })
$evidence += $coverageDirHits

# --- scoring ----------------------------------------------------------------
$testScore = if (-not $hasTests) { 1 } elseif (-not $hasCoverage) { 2 } elseif ($workflowCount -lt 1) { 3 } else { 4 }
$ciScore = if ($ciIndicators.Count -eq 0) { 1 }
           elseif ($workflowCount -ge 2) { 4 }
           elseif ($workflowCount -eq 1) { 3 }
           elseif ($ciIndicators.Count -eq 1) { 2 }
           else { 3 }
$depScore = $depsFound.Count
$tierLevel = Get-TierLevel -Files $fileCount -Langs $languageCount -TestScore $testScore -CiScore $ciScore -DepScore $depScore

$cap = Get-Capabilities -Root $root -HasTests $hasTests -HasCoverage $hasCoverage -HasCi $hasCi -DepManifests $depsFound

$report = [ordered]@{
    projectName    = $projectName
    tier           = "T$tierLevel"
    tierLevel      = $tierLevel
    fileCount      = $fileCount
    languages      = @($languages)
    tests          = [ordered]@{ present = $hasTests; hasCoverage = $hasCoverage; testFiles = $testFiles.Count; coverageFiles = $coverageFiles.Count }
    ci             = [ordered]@{ present = $hasCi; indicators = @($ciIndicators); workflowFiles = $workflowCount }
    dependencies   = [ordered]@{ present = ($depsFound.Count -gt 0); manifests = @($depsFound) }
    capabilities   = $cap
    evidence       = @($evidence)
    scannedAt      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
}

if ($Json) {
    $report | ConvertTo-Json -Depth 10
} else {
    Write-Host "=== Automejora PCI ===" -ForegroundColor Cyan
    Write-Host "  Project:   $projectName"
    Write-Host "  Tier:      T$tierLevel" -ForegroundColor Green
    Write-Host "  Files:     $fileCount"
    Write-Host "  Languages: $($languages -join ', ')"
    Write-Host "  Tests:     present=$hasTests coverage=$hasCoverage"
    Write-Host "  CI:        $($ciIndicators -join ', ')"
    Write-Host "  Deps:      $($depsFound -join ', ')"
    Write-Host "--- Capability matrix ---"
    foreach ($k in @($cap.Keys)) {
        $c = $cap[$k]
        $status = if ($c.available) { 'yes' } else { 'SKIPPED' }
        Write-Host ("  {0,-14} {1,-8} {2}" -f $k, $status, ($c.tools -join ', '))
    }
    Write-Host "---"
    $report | ConvertTo-Json -Depth 10
}
exit 0