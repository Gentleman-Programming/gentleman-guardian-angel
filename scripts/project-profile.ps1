#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Detect project tech stack and output structured profile for !pcycle orchestration.
.DESCRIPTION
  Scans a project directory for stack indicators (package.json, go.mod, Cargo.toml, etc.)
  and returns a normalized JSON profile consumed by project-cycle.ps1.
.PARAMETER Path
  Target project root (default: cwd).
.PARAMETER Quiet
  Output JSON only (machine-readable).
.EXAMPLE
  .\scripts\project-profile.ps1 -Path ..\some-project -Quiet
#>
param(
    [string]$Path = "",
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $Path) { $Path = (Get-Location).Path }
$resolvedPath = Resolve-Path $Path -ErrorAction Stop
$resolved = "$($resolvedPath.Path)"

function Get-File([string]$Name) {
    $p = Join-Path $resolved $Name
    if (Test-Path $p) { return $p }
    return $null
}

# ── Detect stack ──────────────────────────────────────────────
$stack = "unknown"
$pkgMgr = "none"
$frameworks = @()
$testRunner = "none"
$ciProvider = "none"

# Node
$pkgJson = Get-File "package.json"
if ($pkgJson) {
    $stack = "node"
    if (Get-File "pnpm-lock.yaml") { $pkgMgr = "pnpm" }
    elseif (Get-File "yarn.lock")  { $pkgMgr = "yarn" }
    elseif (Get-File "package-lock.json") { $pkgMgr = "npm" }
    elseif (Get-File "npm-shrinkwrap.json") { $pkgMgr = "npm" }
    else { $pkgMgr = "npm (no lockfile)" }

    try {
        $pkg = Get-Content $pkgJson -Raw | ConvertFrom-Json
        # Detect frameworks from dependencies
        $allDeps = @()
        if ($pkg.dependencies)    { $allDeps += $pkg.dependencies.PSObject.Properties.Name }
        if ($pkg.devDependencies) { $allDeps += $pkg.devDependencies.PSObject.Properties.Name }
        if ($pkg.peerDependencies){ $allDeps += $pkg.peerDependencies.PSObject.Properties.Name }

        $knownFw = @{
            "react"          = "react"
            "vue"            = "vue"
            "next"           = "next"
            "nuxt"           = "nuxt"
            "@angular/core"  = "angular"
            "svelte"         = "svelte"
            "gatsby"         = "gatsby"
            "remix"          = "remix"
            "express"        = "express"
            "fastify"        = "fastify"
            "nestjs/core"    = "nestjs"
            "@sveltejs/kit"  = "sveltekit"
            "solid-js"       = "solid"
        }
        $knownTR = @{
            "jest"          = "jest"
            "vitest"        = "vitest"
            "mocha"         = "mocha"
            "jasmine"       = "jasmine"
            "ava"           = "ava"
            "tap"           = "tap"
            "node:test"     = "node:test"
            "@playwright/test" = "playwright"
            "cypress"       = "cypress"
        }
        foreach ($d in $allDeps) {
            if ($knownFw.ContainsKey($d)) { $frameworks += $knownFw[$d] }
            if ($knownTR.ContainsKey($d)) { $testRunner = $knownTR[$d] }
        }
        # Check for TypeScript
        if ("typescript" -in $allDeps) { $frameworks += "typescript" }
        $frameworks = $frameworks | Select-Object -Unique
    } catch {
        Write-Debug "project-profile: $($_.Exception.Message)"
        # package.json parse error, continue
    }
}

# Go
elseif (Get-File "go.mod") {
    $stack = "go"
    $pkgMgr = "go-mod"
    try {
        $gomod = Get-Content (Get-File "go.mod") -TotalCount 1
        if ($gomod -match '^module\s+(\S+)') { $frameworks += $Matches[1] }
    } catch { Write-Debug "go.mod parse failed: $_" }
}

# Python
elseif (Get-File "pyproject.toml") {
    $stack = "python"
    if (Get-File "poetry.lock")      { $pkgMgr = "poetry" }
    elseif (Get-File "Pipfile.lock") { $pkgMgr = "pipenv" }
    elseif (Get-File "requirements.txt") { $pkgMgr = "pip" }
    else { $pkgMgr = "pip" }
    # Detect test runner
    $pyproject = Get-Content (Get-File "pyproject.toml") -Raw
    if ($pyproject -match "pytest")  { $testRunner = "pytest" }
    elseif ($pyproject -match "unittest") { $testRunner = "unittest" }
}
elseif (Get-File "requirements.txt") {
    $stack = "python"; $pkgMgr = "pip"
}
elseif (Get-File "setup.py") {
    $stack = "python"; $pkgMgr = "setuptools"
}

# Rust
elseif (Get-File "Cargo.toml") {
    $stack = "rust"; $pkgMgr = "cargo"
}

# .NET
elseif ((Get-ChildItem $resolved -Filter "*.sln" -Depth 0 -ErrorAction SilentlyContinue) -or (Get-ChildItem $resolved -Filter "*.csproj" -Depth 1 -ErrorAction SilentlyContinue)) {
    $stack = "dotnet"; $pkgMgr = "nuget"
}

# Ruby
elseif (Get-File "Gemfile") {
    $stack = "ruby"; $pkgMgr = "bundler"
}

# PHP
elseif (Get-File "composer.json") {
    $stack = "php"; $pkgMgr = "composer"
}

# Docker
$hasDocker = [bool](Get-File "Dockerfile") -or [bool](Get-File "docker-compose.yml")

# CI
if (Test-Path (Join-Path $resolved ".github\workflows")) { $ciProvider = "github-actions" }
elseif (Get-File ".gitlab-ci.yml") { $ciProvider = "gitlab-ci" }
elseif (Get-File "Jenkinsfile")    { $ciProvider = "jenkins" }
elseif (Test-Path (Join-Path $resolved ".circleci")) { $ciProvider = "circleci" }

# ── File count & LOC ─────────────────────────────────────────
$fileCount = (Get-ChildItem $resolved -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension -notin @('.exe','.dll','.bin','.png','.jpg','.gif','.ico','.svg','.woff','.woff2','.ttf','.eot','.map')
}).Count
$loc = 0
Get-ChildItem $resolved -File -Recurse -ErrorAction SilentlyContinue -Include *.js,*.ts,*.jsx,*.tsx,*.go,*.py,*.rs,*.cs,*.rb,*.php,*.json,*.yaml,*.yml,*.toml,*.css,*.scss,*.html,*.md,*.ps1,*.psm1 | ForEach-Object {
    try { $loc += (Get-Content $_.FullName -ReadCount 0).Count } catch { Write-Debug "LOC count failed for $($_.Name): $_" }
}

# ── Maturity heuristic ────────────────────────────────────────
$gitLog = Get-File ".git"
$maturity = "unknown"
if ($gitLog) {
    try {
        $gitDir = Join-Path $resolved ".git"
        $firstCommit = & "git" "--git-dir=$gitDir" "--work-tree=$resolved" "log" "--reverse" "--format=%ci" "HEAD" 2>$null | Select-Object -First 1
        if ($firstCommit) {
            $age = [datetime]::UtcNow - [datetime]::ParseExact($firstCommit.Substring(0,10), "yyyy-MM-dd", $null)
            $maturity = if ($age.TotalDays -gt 1095) { "established" }
                       elseif ($age.TotalDays -gt 365) { "mature" }
                       elseif ($age.TotalDays -gt 180) { "medium" }
                       else { "young" }
        }
    } catch { $maturity = "unknown" }
}

# ── Output ────────────────────────────────────────────────────
$projectProfile = [PSCustomObject]@{
    profile = [PSCustomObject]@{
        path         = "$($resolved)"
        name         = Split-Path "$($resolved)" -Leaf
    }
    stack = [PSCustomObject]@{
        type         = $stack
        pkgManager   = $pkgMgr
        frameworks   = $frameworks
        testRunner   = $testRunner
        hasTypescript = $stack -eq "node" -and ("typescript" -in $frameworks)
        hasDocker    = $hasDocker
        ciProvider   = $ciProvider
    }
    size = [PSCustomObject]@{
        files        = $fileCount
        loc          = $loc
        maturity     = $maturity
    }
}

if ($Quiet) {
    $projectProfile | ConvertTo-Json -Depth 4
} else {
    Write-Host "=== Project Profile ===" -ForegroundColor Cyan
    Write-Host "  Path:     $resolved"
    Write-Host "  Stack:    $stack" -ForegroundColor Green
    Write-Host "  Package:  $pkgMgr" -ForegroundColor Yellow
    if ($frameworks.Count -gt 0) { Write-Host "  Frameworks: $($frameworks -join ', ')" -ForegroundColor Magenta }
    Write-Host "  Test:     $testRunner"
    Write-Host "  CI:       $ciProvider"
    Write-Host "  Docker:   $hasDocker"
    Write-Host "  Files:    $fileCount"
    Write-Host "  LOC:      $loc"
    Write-Host "  Maturity: $maturity"
    Write-Host "---"
    $projectProfile | ConvertTo-Json -Depth 4
}
exit 0
