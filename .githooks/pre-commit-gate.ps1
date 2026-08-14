#!/usr/bin/env pwsh
#requires -Version 7
<#
.SYNOPSIS Pre-commit quality gate — ALL 21 checks in a single pwsh invocation
.DESCRIPTION Called by .githooks/pre-commit. Replaces 9 separate pwsh calls.
  Saves ~1.8s per commit by eliminating redundant process startups.
#>
param([string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (git rev-parse --show-toplevel 2>$null) ?? '.' }

$passed = 0; $failed = 0; $blocked = $false
$configSizeBudget = 98304  # ADR-007: opencode.json size budget (bytes)

function Pass { $script:passed++; Write-Host "  $([char]0x1b)[32mOK$([char]0x1b)[0m" }
function Warn  { param([string]$Msg) $script:passed++; if ($Msg) { Write-Host "  $([char]0x1b)[33m$Msg$([char]0x1b)[0m" } else { Write-Host "  $([char]0x1b)[33mWARN$([char]0x1b)[0m" } }
function Fail  { param([string]$Msg) $script:failed++; $script:blocked = $true; if ($Msg) { Write-Host "  $([char]0x1b)[31mBLOCKING: $Msg$([char]0x1b)[0m" } else { Write-Host "  $([char]0x1b)[31mBLOCKING$([char]0x1b)[0m" } }

# Detect staged files (done once, reused by multiple checks)
$staged = git diff --cached --name-only --diff-filter=ACM
$stagedPS1       = $staged | Where-Object { $_ -like '*.ps1' }
$stagedSkills    = $staged | Where-Object { $_ -match '\.agents/skills/' }
$stagedProject   = $staged | Where-Object { $_ -match '\.project\.json$' }
$stagedRules     = $staged | Where-Object { $_ -match 'review-rules\.jsonc$' }
$stagedAgents    = $staged | Where-Object { $_ -match 'AGENTS\.md|\.agents/skills/' }
$stagedRoja      = $staged | Where-Object { $_ -match '^(src/|test/|scripts/|migrations/|ci/|\.github/)' }
$stagedSkillMds  = $staged | Where-Object { $_ -match '\.agents/skills/[^/]+/SKILL\.md$' }
$stagedTests     = $staged | Where-Object { $_ -match '\.Tests\.ps1$' }
$stagedConfig    = $staged | Where-Object { $_ -match 'scripts/opencode-config/' }

Write-Host "`n=== Gentleman Quality Gate ==="

# [1/13] Trailing whitespace
Write-Host "[1/13] Trailing whitespace..."
$wsOut = git diff --cached --check 2>&1
$wsLines = $wsOut | Where-Object { $_ -notmatch '^\s*$' }
if ($wsLines) { $wsLines -join "`n" | ForEach-Object { Write-Host "    $_" }; Warn "fix trailing whitespace before push" }
else { Pass }

# [2/13] #requires Version check
Write-Host "[2/13] #requires Version check (staged .ps1)..."
if ($stagedPS1) {
    $missing = $stagedPS1 | Where-Object {
        $full = Join-Path $RepoRoot $_
        if (-not (Test-Path $full)) { $false }
        else { -not ((Get-Content $full -TotalCount 3) -match '#requires -Version (5\.1|7)') }
    }
    if ($missing) { $missing | ForEach-Object { Write-Host "    $_" }; Fail "scripts missing '#requires -Version 5.1 or 7'" }
    else { Pass }
} else { Pass }

# [3/13] Cross-ref check
Write-Host "[3/13] Cross-ref check..."
if ($stagedSkills) {
    & "$RepoRoot/scripts/cross-ref-check.ps1" -Quiet -ErrorAction SilentlyContinue 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Pass } else { Fail "cross-ref validation failed" }
} else { Pass }

# [4/13] Skill drift
Write-Host "[4/13] Skill drift..."
if ($stagedSkills) {
    & "$RepoRoot/scripts/check-skill-drift.ps1" -Quiet -ErrorAction SilentlyContinue 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Pass } else { Warn "skill drift detected (non-blocking)" }
} else { Pass }

# [5/13] Improvement cycle — overweight skills
Write-Host "[5/13] Improvement cycle..."
$canonical = "$RepoRoot/.agents/skills"
$overweight = if (Test-Path $canonical) {
    Get-ChildItem $canonical -Directory | Where-Object { $_.Name -ne '_shared' } | ForEach-Object {
        $md = Join-Path $_.FullName 'SKILL.md'
        if (Test-Path $md) { $len = (Get-Content $md -Raw).Length; if ($len -gt 3072) { "$($_.Name) ($($len)B)" } }
    }
}
if ($overweight) { Warn "skills >3KB (consider improvement cycle):`n$($overweight -join "`n")" } else { Pass }

# [6/13] .project.json integrity
Write-Host "[6/13] .project.json integrity..."
if ($stagedProject) {
    try {
        $json = Get-Content "$RepoRoot/.project.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $dims = $json.score.dimensions.PSObject.Properties.Name.Count
        $current = $json.score.current
        if ($dims -ne 13) { Fail "Expected 13 dimensions, found $dims" }
        elseif ($null -eq $current -or $current -lt 5) { Fail "score.current missing or < 5" }
        else { Pass }
    } catch { Fail ".project.json parse error: $_" }
} else { Pass }

# [7/13] review-rules.jsonc integrity
Write-Host "[7/13] review-rules.jsonc integrity..."
if ($stagedRules) {
    try {
        $raw = Get-Content "$RepoRoot/review-rules.jsonc" -Raw -Encoding UTF8
        $parsed = $raw -replace '(?m)^\s*//.*$','' -replace '(?m)\s*//[^"''\n]*$','' -replace '(?s)/\*.*?\*/','' | ConvertFrom-Json
        $z = $parsed.zones.PSObject.Properties.Name.Count; $c = $parsed.context_zones.PSObject.Properties.Name.Count
        $m = $parsed.modes.PSObject.Properties.Name.Count; $p = $parsed.jd_profiles.PSObject.Properties.Name.Count
        $s = $parsed.jd_profile_selector.Count
        if ($z -ne 3) { Fail "Expected 3 zones, found $z" }
        elseif ($c -ne 4) { Fail "Expected 4 context zones, found $c" }
        elseif ($m -ne 4) { Fail "Expected 4 modes, found $m" }
        elseif ($p -lt 1) { Fail "Expected >=1 jd_profiles, found $p" }
        elseif ($s -lt 1) { Fail "Expected >=1 selectors, found $s" }
        else { Pass }
    } catch { Fail "review-rules.jsonc parse error: $_" }
} else { Pass }

# [8/13] Benchmark check
Write-Host "[8/13] Benchmark check..."
if ($stagedAgents) {
    $benchOut = & "$RepoRoot/scripts/benchmark.ps1" -Gate 2>&1 | Out-String
    if ($benchOut -match 'REGRESSIONS') { Warn "benchmark regressions detected`n$benchOut" }
    else { $benchOut.Trim() -split "`n" | ForEach-Object { Write-Host "    $_" }; Pass }
} else { Pass }

# [9/13] JD review check — respects .jd-cleared/<path> markers or FORCE_SHIP env
# Clears the recurring Warn for files already cleared via `!judgment-day`.
# Marker naming: path separators -> underscores (scripts/foo.ps1 -> .jd-cleared/scripts_foo.ps1)
Write-Host "[9/13] JD review check (ROZA zone)..."
if ($stagedRoja) {
    $uncleared = @()
    foreach ($f in $stagedRoja) {
        $marker = "$RepoRoot/.jd-cleared/" + ($f.Replace('/','_').Replace('\','_'))
        if (-not (Test-Path $marker -PathType Leaf)) { $uncleared += $f }
    }
    if ($env:FORCE_SHIP) {
        Warn "FORCE_SHIP set — JD bypass acknowledged (ensure '!ship' was intentional)`n    $($stagedRoja -join "`n")"
    } elseif ($uncleared.Count -eq 0) {
        Pass
    } else {
        Fail "ROZA zone files staged without JD dual review — BLOCKED:`n  $($uncleared | ForEach-Object { '    ' + $_ } | Out-String)  Run `!judgment-day` or touch .jd-cleared markers, or set FORCE_SHIP=1"
    }
} else { Pass }

# [10/13] Secrets scan — parse diff to get real filenames (not "InputStream")
Write-Host "[10/13] Secrets scan..."
$diffLines = git diff --cached --diff-filter=ACM -- ':!.githooks' ':!*.Tests.ps1' ':!scripts/check-mcp-security.ps1' ':!.agents/skills/*/references/*' ':!.gitleaks.toml' ':!docs/mejoras/*'
$secrets = @(); $currentFile = ""; $lineInFile = 0
foreach ($dl in $diffLines) {
    if ($dl -match '^\+\+\+ b/(.+)$') { $currentFile = $Matches[1]; continue }
    if ($dl -match '^@@ -\d+,\d+ \+(\d+),\d+ @@') { $lineInFile = [int]$Matches[1] - 1; continue }
    if ($dl -match '^\+([^\+].*)$') {
        $lineInFile++
        $text = $Matches[1]
        if ($text -match '(ghp_|gho_|github_pat_|AKIA|ctx7sk_|-----BEGIN\s+(RSA|EC|DSA|PRIVATE)\s+KEY|GH_TOKEN\s*=|GITHUB_TOKEN\s*=|password\s*=|api[_-]?key\s*=|secret\s*=|token\s*=)') {
            $secrets += [PSCustomObject]@{ Filename = $currentFile; LineNumber = $lineInFile; Line = $text }
        }
    }
}
if ($secrets) {
    $secrets | ForEach-Object {
        $line = $_.Line.Trim()
        if ($line.Length -gt 80) { $line = $line.Substring(0,77)+'...' }
        Write-Host "    $($_.Filename):$($_.LineNumber) $line"
    }
    Fail "potential secrets found in staged diff"
} else { Pass }

# [11/13] SKILL.md frontmatter completeness
Write-Host "[11/13] Taste invariant: SKILL.md frontmatter..."
if ($stagedSkillMds) {
    $fmFail = $false
    foreach ($sf in $stagedSkillMds) {
        $fullPath = Join-Path $RepoRoot $sf
        if (-not (Test-Path $fullPath)) { continue }
        $content = Get-Content $fullPath -Raw
        $fm = if ($content -match '(?s)^---\s*(.*?)---') { $Matches[1] } else { '' }
        if ($fm -notmatch 'name:\s+') { Write-Host "  $([char]0x1b)[31m  BLOCKING: $sf — missing 'name:'$([char]0x1b)[0m"; $fmFail=$true }
        if ($fm -notmatch 'description:\s+') { Write-Host "  $([char]0x1b)[31m  BLOCKING: $sf — missing 'description:'$([char]0x1b)[0m"; $fmFail=$true }
        if ($fm -notmatch 'triggers:\s+') { Write-Host "  $([char]0x1b)[31m  BLOCKING: $sf — missing 'triggers:'$([char]0x1b)[0m"; $fmFail=$true }
    }
    if ($fmFail) { Fail "frontmatter issues" } else { Pass }
} else { Pass }

# [12/13] Pester tests
Write-Host "[12/13] Pester tests..."
if ($stagedTests) {
    try {
        Import-Module Pester -ErrorAction Stop
        $pester = Get-Module Pester
        $testPaths = @($stagedTests | ForEach-Object { Join-Path $RepoRoot $_ })
        $cfg = [PesterConfiguration]@{
            Run = @{
                Path     = $testPaths
                Exit     = $false
                PassThru = $true
            }
        }
        if ($pester.Version.Major -ge 5 -and $cfg.PSObject.Properties['Filter']) { $cfg.Filter.ExcludeTag = 'E2E' }
        if ($testPaths.Count -gt 1 -and $pester.Version.Major -ge 5) { $cfg.Run.Parallel = $true }
        $results = Invoke-Pester -Configuration $cfg
        if ($null -eq $results) {
            Warn "Pester: no results returned"
        } elseif ($null -eq $results.FailedCount) {
            Warn "Pester: FailedCount property not available (Pester version mismatch)"
        } elseif ($results.FailedCount -gt 0) {
            Fail "Pester: $($results.FailedCount) test(s) failed"
        } else {
            Pass
        }
    } catch { Warn "Pester not available: $_" }
} else { Pass }

# [13/13] Config expansion check
Write-Host "[13/13] Config expansion check..."
if ($stagedConfig) {
    $importMarkers = git show :opencode.json 2>$null | Select-String -Pattern '\$import'
    if ($importMarkers) { Fail "Config sources changed but opencode.json has unresolved `$import markers" }
    else { Pass }
} else { Pass }

# [14/14] opencode.json sync with SSoT (scripts/lib/*)
Write-Host "[14/14] opencode.json sync with SSoT..."
$stagedLib = $staged | Where-Object { $_ -match '^(scripts/lib/|opencode\.json$)' }
if ($stagedLib) {
    & "$RepoRoot/scripts/regenerate-opencode.ps1" -Quiet -ErrorAction SilentlyContinue 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Pass } else { Fail "opencode.json out of sync with SSoT — run scripts/regenerate-opencode.ps1 -Yes" }
} else { Pass }

# [15/15] Write-scope enforcement (OPT-IN via .gentleman/write-scope.json)
# Absent file => no constraint, pass. Present => staged changes outside
# allowed_paths fail the gate (wired in as a follow-up to INFRA-I6).
Write-Host "[15/15] Write-scope check..."
$scopeFile = Join-Path $RepoRoot '.gentleman\write-scope.json'
if (Test-Path -LiteralPath $scopeFile) {
    try {
        $scope = Get-Content -LiteralPath $scopeFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $allowed = @($scope.allowed_paths) -join ','
        if (-not $allowed) { Fail "write-scope.json has no allowed_paths" }
        else {
            & "$RepoRoot/scripts/validate-write-scope.ps1" -AllowedPaths $allowed -BaseRef HEAD -Staged -ErrorAction SilentlyContinue 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Pass } else { Fail "staged changes outside allowed_paths ($scopeFile)" }
        }
    } catch { Fail "write-scope.json parse error: $_" }
} else { Pass }

# [16/16] Config drift check (repo opencode.json vs global opencode.json(c))
# Runs ONLY when a global config exists (developer machines synced via
# sync-global.ps1). Machines without one (fresh clones, CI runners) skip —
# wiring this into quality-gate.yml would false-fail every CI run.
Write-Host "[16/16] Config drift check..."
$globalDir = Join-Path $env:USERPROFILE '.config\opencode'
$globalConf = @("$globalDir\opencode.json", "$globalDir\opencode.jsonc") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($globalConf) {
    & "$RepoRoot/scripts/check-config-drift.ps1" -Quiet -ErrorAction SilentlyContinue 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Pass } else { Warn "config drift vs global — run scripts/sync-global.ps1" }
} else { Pass }

# [17/17] Config size budget (ADR-007)
# Enforces opencode.json ≤ 65,536 B so config growth cannot silently creep past
# the budget. Mirrored in quality-gate.yml ("Config size budget" step).
Write-Host "[17/17] Config size budget..."
$configPath = Join-Path $RepoRoot 'opencode.json'
if (Test-Path -LiteralPath $configPath) {
    $configSize = (Get-Item -LiteralPath $configPath).Length
    if ($configSize -gt $configSizeBudget) { Fail "opencode.json exceeds $configSizeBudget B budget (ADR-007): $configSize B" }
    else { Pass }
} else { Fail "opencode.json not found at $configPath" }

# [18/18] Backlog integrity check
# Verifies CYCLE.md backlog item status matches repo reality. Runs ALWAYS
# (like [17/17]) and is fail-closed if the script is missing. Mirrored in
# .github/workflows/quality-gate.yml ("Backlog integrity check" step).
Write-Host "[18/18] Backlog integrity check..."
$backlogScript = Join-Path $RepoRoot 'scripts/check-backlog-integrity.ps1'
if (Test-Path -LiteralPath $backlogScript) {
    & "$RepoRoot/scripts/check-backlog-integrity.ps1" *> $null
    if ($LASTEXITCODE -eq 0) { Pass } else { Fail "backlog integrity check failed — CYCLE.md status does not match repo reality" }
} else { Fail "backlog-integrity.ps1 not found at $backlogScript" }

# [19/19] Token budget check (C9)
# Runs check-token-budget.ps1 to audit skill/prompt file sizes against
# the 2,000-byte average target (ADR-007). Uses Warn (not Fail) since
# oversize skills are a known condition under ADR-018.
Write-Host "[19/19] Token budget check..."
$budgetScript = Join-Path $RepoRoot 'scripts/check-token-budget.ps1'
if (Test-Path -LiteralPath $budgetScript) {
    $budgetOut = & "$RepoRoot/scripts/check-token-budget.ps1" -Json 2>&1 | Out-String
    $budgetResult = try { $budgetOut | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    if ($budgetResult -and -not $budgetResult.passed) {
        $skillAvg = if ($budgetResult.stats.skills) { $budgetResult.stats.skills.average } else { 'N/A' }
        $promptAvg = if ($budgetResult.stats.prompts) { $budgetResult.stats.prompts.average } else { 'N/A' }
        $overFiles = 0
        if ($budgetResult.stats.skills) { $overFiles += $budgetResult.stats.skills.overBudgetFiles }
        if ($budgetResult.stats.prompts) { $overFiles += $budgetResult.stats.prompts.overBudgetFiles }
        Warn "token budget exceeded — skills $($skillAvg)B/$($budgetResult.budget), prompts $($promptAvg)B/$($budgetResult.budget) ($overFiles files over)"
    } else { Pass }
} else {
    Warn "check-token-budget.ps1 not found"
}

# [20/20] Budget script validation (C6)
# Verifies check-budget.ps1 is present and syntactically valid —
# ensures the budget enforcement tool is available for runtime use
# by the orchestrator during agent sessions.
Write-Host "[20/20] Budget script validation..."
$budgetRuntime = Join-Path $RepoRoot 'scripts/check-budget.ps1'
if (Test-Path -LiteralPath $budgetRuntime) {
    $btTokens = $null; $btErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($budgetRuntime, [ref]$btTokens, [ref]$btErrors) | Out-Null
    if ($btErrors) {
        $btErrors | ForEach-Object { Write-Host "    $_" }
        Fail "check-budget.ps1 has syntax errors"
    } else { Pass }
} else {
    Warn "check-budget.ps1 not found"
}

# [21/21] Context watchdog validation (C8)
# Verifies ctx-watchdog.ps1 is present and syntactically valid —
# ensures the context-zone monitoring tool is available for runtime
# use by the skill-graph during agent sessions.
Write-Host "[21/21] Context watchdog validation..."
$watchdogScript = Join-Path $RepoRoot 'scripts/ctx-watchdog.ps1'
if (Test-Path -LiteralPath $watchdogScript) {
    $wdTokens = $null; $wdErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($watchdogScript, [ref]$wdTokens, [ref]$wdErrors) | Out-Null
    if ($wdErrors) {
        $wdErrors | ForEach-Object { Write-Host "    $_" }
        Fail "ctx-watchdog.ps1 has syntax errors"
    } else { Pass }
} else {
    Warn "ctx-watchdog.ps1 not found"
}

# [22/22] Adversarial-breaker profile scan — lightweight commit-time scan.
# Runs AFTER Verify ([12/13] Pester tests) — catches obvious security patterns.
# The full adversarial-breaker skill (sub-agent deep analysis) is triggered
# manually via `!breaker` or auto-triggered in SDD post-Verify for ROZA zone.
Write-Host "[22/22] Adversarial-breaker profile scan..."
$stagedSecurity = $staged | Where-Object { $_ -match '\.ps1$' }
if ($stagedSecurity) {
    & "$RepoRoot/scripts/check-adversarial.ps1" -RepoRoot $RepoRoot -ErrorAction SilentlyContinue 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Pass } else { Fail "adversarial profile violations — see output above, touch .breaker-cleared/<file> markers or set FORCE_SHIP=1" }
} else { Pass }

# Summary
Write-Host "`n=== Gate: $passed/$($passed+$failed) passed ==="
if ($blocked) { Write-Host "  $([char]0x1b)[31mBLOCKED$([char]0x1b)[0m" }
else { Write-Host "  $([char]0x1b)[32mALL CLEAR$([char]0x1b)[0m" }

# Capture result
$blockedStr = if ($blocked) { 'yes' } else { 'no' }
& "$RepoRoot/scripts/capture-errors.ps1" -Source quality-gate -Passed $passed -Failed $failed -Blocked $blockedStr *>$null

exit $(if ($blocked) { 1 } else { 0 })
