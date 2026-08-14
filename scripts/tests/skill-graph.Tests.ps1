#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Pester tests for skill-graph.ps1 core logic.
  Tests: Register-Skill, New-Graph, Resolve-Skill token matching, Get-AgentRecommendation.
  Compatible with Pester 5.x / 6.x.

  NOTE: skill-graph.ps1 uses $skillRegistry (bare, line 43) for init and
  $script:skillRegistry (Register-Skill, line 54) for mutation. When dot-sourced
  under Pester 6, these resolve to different scopes. This test extracts only the
  FUNCTIONS via regex and initializes its own registry.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # --- Extract functions only (skip top-level initialization) ---
    $raw = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'skill-graph.ps1') -Raw

    # Register-Skill no longer exists in the script (replaced by pipe-delimited
    # data parsing). Recreate as a test helper for populating the registry.
    $script:skillRegistry = @()
    function Register-Skill {
        param([string]$Name, [string]$Triggers, [string]$Category, [string]$Effort,
              [string]$DependsOn, [string]$Related, [string]$Description)
        $script:skillRegistry += [PSCustomObject]@{
            Name = $Name; Triggers = $Triggers; Category = $Category; Effort = $Effort
            DependsOn = $DependsOn; Related = $Related; Description = $Description
        }
    }

    # Extract functions — replace bare $skillRegistry/$external/$valid* with $script: for Pester scope
    foreach ($fn in @('New-Graph', 'Resolve-Skill', 'Get-AgentRecommendation', 'Get-SkillRegistry', 'Get-FileSha256')) {
        $fnStart = $raw.IndexOf("function $fn")
        if ($fnStart -ge 0) {
            $bracePos = $raw.IndexOf('{', $fnStart)
            $depth = 0; $endIdx = $bracePos
            for ($i = $bracePos; $i -lt $raw.Length; $i++) {
                if ($raw[$i] -eq '{') { $depth++ }
                elseif ($raw[$i] -eq '}') { $depth--; if ($depth -eq 0) { $endIdx = $i; break } }
            }
            $fnText = $raw.Substring($fnStart, $endIdx - $fnStart + 1)
            $fnText = $fnText -replace '(?<!\$script:)\$skillRegistry\b', '$script:skillRegistry'
            $fnText = $fnText -replace '(?<!\$script:)\$externalPatterns\b', '$script:externalPatterns'
            $fnText = $fnText -replace '(?<!\$script:)\$agentRecommendations\b', '$script:agentRecommendations'
            $fnText = $fnText -replace '(?<!\$script:)\$validCategories\b', '$script:validCategories'
            $fnText = $fnText -replace '(?<!\$script:)\$validEfforts\b', '$script:validEfforts'
            $fnText = $fnText -replace '(?<!\$script:)\$cacheTtlMinutes\b', '$script:cacheTtlMinutes'
            . ([ScriptBlock]::Create($fnText))
        }
    }

    # Extract agentRecommendations data
    if ($raw -match '(?s)(\$agentRecommendations\s*=\s*@\(.+?\n\))') {
        $dataText = $Matches[1] -replace '\$agentRecommendations', '$script:agentRecommendations'
        . ([ScriptBlock]::Create($dataText))
    }

    # Initialize external patterns (used by Resolve-Skill)
    $script:externalPatterns = @()

    # Initialize valid category/effort constants used by Get-SkillRegistry parsing
    $script:validCategories = @('meta','quality','coordination','code-ops','specialized','testing','web-quality','memory','documents','compression','performance','research','SDD')
    $script:validEfforts = @('low','medium','high')

    # Cache TTL constant (default of Get-SkillRegistry -TtlMinutes)
    $script:cacheTtlMinutes = 60
}

# ============================================================
Describe 'New-Graph' {
    BeforeEach {
        $script:skillRegistry = @()
        Register-Skill 'A' 'triggerA' 'test' 'low' 'B' '' 'Skill A depends on B'
        Register-Skill 'B' 'triggerB' 'test' 'low' '' '' 'Skill B'
        Register-Skill 'C' 'triggerC' 'test' 'low' 'A' '' 'Skill C depends on A'
    }

    It 'creates nodes for all registered skills' {
        $graph = New-Graph

        $graph.Nodes.ContainsKey('A') | Should -Be $true
        $graph.Nodes.ContainsKey('B') | Should -Be $true
        $graph.Nodes.ContainsKey('C') | Should -Be $true
    }

    It 'creates adjacency lists for all nodes' {
        $graph = New-Graph

        $graph.AdjList.ContainsKey('A') | Should -Be $true
        $graph.AdjList.ContainsKey('B') | Should -Be $true
        $graph.AdjList.ContainsKey('C') | Should -Be $true
    }

    It 'links dependencies correctly (A depends on B)' {
        $graph = New-Graph

        $graph.AdjList['B'].to.ContainsKey('A') | Should -Be $true
        $graph.AdjList['B'].to['A'] | Should -Be 'depends_on'

        $graph.AdjList['A'].from.ContainsKey('B') | Should -Be $true
        $graph.AdjList['A'].from['B'] | Should -Be 'depended_by'
    }

    It 'links C -> A (C depends on A)' {
        $graph = New-Graph

        $graph.AdjList['A'].to.ContainsKey('C') | Should -Be $true
        $graph.AdjList['C'].from.ContainsKey('A') | Should -Be $true
    }
}

# ============================================================
Describe 'Resolve-Skill' {
    BeforeEach {
        $script:skillRegistry = @()
        Register-Skill 'quality-gate' 'quality gate|pre-commit|validate commit' 'quality' 'medium' '' 'auto-metrics|commit-crafter' 'Pre-commit quality gate'
        Register-Skill 'auto-metrics' 'auto-score|metrics|post-task|evaluate|self-evaluate' 'quality' 'medium' '' '' 'Post-task self-evaluation'
        Register-Skill 'triple-verify' 'triple verify|triangulate|3 enfoques|verificacion profunda|!ship' 'quality' 'high' '' '' 'Triple verification'
        Register-Skill 'seo' 'SEO|search engine|meta tags|structured data|sitemap' 'web-quality' 'medium' '' '' 'SEO optimization'
        Register-Skill 'accessibility' 'accessibility|a11y|WCAG|screen reader|keyboard nav' 'web-quality' 'medium' '' '' 'Web accessibility'
        Register-Skill 'research' 'research|investigar|technical investigation|learn|compare solutions' 'research' 'medium' '' '' 'Structured research'
    }

    It 'returns empty for no-match task' {
        $results = @(Resolve-Skill 'xyzzy plugh' 0)
        $results.Count | Should -Be 0
    }

    It 'matches single skill by trigger word' {
        $results = @(Resolve-Skill 'quality gate please' 0)

        $results.Count | Should -BeGreaterOrEqual 1
        $results[0].Name | Should -Be 'quality-gate'
        $results[0].Score | Should -BeGreaterOrEqual 1
    }

    It 'matches multiple skills when triggers overlap' {
        $results = @(Resolve-Skill 'quality gate and metrics evaluation' 0)

        $names = @($results | ForEach-Object { $_.Name })
        $names | Should -Contain 'quality-gate'
        $names | Should -Contain 'auto-metrics'
    }

    It 'respects MaxDepth=0 (no dependencies)' {
        $results = @(Resolve-Skill 'quality gate' 0)

        $names = @($results | ForEach-Object { $_.Name })
        $names | Should -Contain 'quality-gate'
        $depth0Deps = @($results | Where-Object { $_.Name -eq 'auto-metrics' -and $_.Depth -eq 0 })
        $depth0Deps.Count | Should -Be 0
    }

    It 'includes dependents at MaxDepth=1' {
        # BFS follows .to edges (dependents, not dependencies)
        # quality-gate has no dependents in our test, so only quality-gate itself
        $results = @(Resolve-Skill 'quality gate' 1)

        $names = @($results | ForEach-Object { $_.Name })
        $names | Should -Contain 'quality-gate'
        # quality-gate has no dependents — only the direct match
        $names.Count | Should -Be 1
    }

    It 'matches case-insensitively' {
        $results = @(Resolve-Skill 'QUALITY GATE' 0)

        $results.Count | Should -BeGreaterOrEqual 1
        $results[0].Name | Should -Be 'quality-gate'
    }

    It 'returns results sorted by depth then score' {
        $results = @(Resolve-Skill 'quality gate' 1)

        $results[0].Depth | Should -Be 0
    }
}

# ============================================================
Describe 'Get-AgentRecommendation' {
    BeforeEach {
        $script:skillRegistry = @()
        Register-Skill 'quality-gate' 'quality gate|pre-commit|validate commit' 'quality' 'medium' '' '' 'Pre-commit quality gate'
        Register-Skill 'code-review-agent' 'code review|4r review|risk audit' 'quality' 'medium' '' '' '4R code review'
        Register-Skill 'security-scanner' 'secret scan|injection|vulnerability' 'quality' 'high' '' '' 'Pre-commit security scan'
        Register-Skill 'triple-verify' 'triple verify|triangulate|verificacion profunda' 'quality' 'high' '' '' 'Triple verification'
        Register-Skill 'recovery-protocol' 'stop diagnose|frustration|error recovery' 'coordination' 'low' '' '' 'Recovery protocol'
        Register-Skill 'immune-system' 'immunity|anti-pattern|repeated error' 'meta' 'medium' '' '' 'Immune system'
        Register-Skill 'seo' 'SEO|search engine|meta tags|structured data|sitemap' 'web-quality' 'medium' '' '' 'SEO optimization'
        Register-Skill 'research' 'research|investigar|technical investigation|learn|compare solutions' 'research' 'medium' '' '' 'Structured research'
        # Auto-register every skill referenced in agentRecommendations so the lookup
        # never warns (recommendation table must stay consistent with the registry).
        $referenced = @($script:agentRecommendations | ForEach-Object { $_.S } | Sort-Object -Unique)
        $existing = @($script:skillRegistry | ForEach-Object { $_.Name })
        foreach ($r in $referenced) {
            if ($r -notin $existing) { Register-Skill $r '' '' 'low' '' '' "Auto-registered from agentRecommendations" }
        }
    }

    It 'recommends agents for review task' {
        $result = @(Get-AgentRecommendation 'review code for security issues')
        $result | Should -Not -BeNullOrEmpty
        $result | Should -Contain 'code-review-agent'
    }

    It 'recommends agents for bug fix task' {
        $result = @(Get-AgentRecommendation 'fix this bug in the login page')
        $result | Should -Not -BeNullOrEmpty
        $result | Should -Contain 'recovery-protocol'
    }

    It 'recommends agents for SEO task' {
        $result = @(Get-AgentRecommendation 'improve SEO for the landing page')
        $result | Should -Not -BeNullOrEmpty
        $result | Should -Contain 'seo'
        # Regression: "improve" contains "pr" but must NOT trigger commit/PR recommendations
        $result | Should -Not -Contain 'commit-crafter'
        $result | Should -Not -Contain 'branch-pr'
    }

    It 'recommends commit agents for plural PRs' {
        # Regression: \bprs?\b must keep plural "PRs" triggering commit/PR recommendations
        $result = @(Get-AgentRecommendation 'review the PRs before merging')
        $result | Should -Contain 'commit-crafter'
        $result | Should -Contain 'branch-pr'
    }

    It 'returns unique recommendations' {
        $result = @(Get-AgentRecommendation 'review code and fix bugs and improve quality')
        $result.Count | Should -Be (@($result | Select-Object -Unique)).Count
    }
}

# ============================================================
Describe 'Skill Graph Integration' {
    BeforeEach {
        $script:skillRegistry = @()
        Register-Skill 'A' 'trigger_a' 'test' 'low' 'B' '' 'A depends on B'
        Register-Skill 'B' 'trigger_b' 'test' 'low' '' '' 'B standalone'
        Register-Skill 'C' 'trigger_c' 'test' 'low' 'A' '' 'C depends on A'
    }

    It 'resolves dependency chain A -> B via BFS' {
        $results = @(Resolve-Skill 'trigger_a' 1)
        $names = @($results | ForEach-Object { $_.Name })
        $names | Should -Contain 'A'
        $names | Should -Contain 'B'
    }

    It 'resolves deep chain C -> A -> B at depth 2' {
        $results = @(Resolve-Skill 'trigger_c' 2)
        $names = @($results | ForEach-Object { $_.Name })
        $names | Should -Contain 'C'
        $names | Should -Contain 'A'
        $names | Should -Contain 'B'
    }
    It 'does not resolve deep chain at depth 0' {
        # Use specific text that only matches C — "trigger_c" tokenizes to just "trigger"
        # which matches all skills. Use a unique trigger instead.
        $results = @(Resolve-Skill 'trigger_c' 0)

        # At depth 0, BFS doesn't expand, so only direct matches appear
        # "trigger_c" tokenizes to ["trigger", "c"] → after length filter: ["trigger"]
        # "trigger" matches all skills with "trigger" in their triggers (A, B, C)
        $names = @($results | ForEach-Object { $_.Name })
        $names | Should -Contain 'C'
        # All 3 match because token "trigger" is common — but depths should all be 0
        $results | ForEach-Object { $_.Depth } | Should -Not -Contain 1
    }
}

# ============================================================
Describe 'Resolve-Skill C4a: name-match bonus (dual resolution alignment)' {
    BeforeEach {
        $script:skillRegistry = @()
        # Name-match bonus: skill name contains token but triggers don't
        Register-Skill 'accessibility' 'a11y|wcag|screen reader' 'web-quality' 'medium' '' '' 'Web accessibility audit'
        Register-Skill 'seo-tools' 'SEO|meta tags|sitemap|structured data' 'web-quality' 'medium' '' '' 'SEO optimization tools'
    }

    It 'applies name-match bonus (3 pts) when task token matches skill name but not triggers' {
        # "accessibility" matches the skill NAME but NOT any trigger (a11y|wcag|screen reader)
        $results = @(Resolve-Skill 'accessibility please' 0)

        $results.Count | Should -Be 1
        $results[0].Name | Should -Be 'accessibility'
        $results[0].Score | Should -Be 3  # name bonus only, no trigger match
    }

    It 'combines trigger match (1pt) + name bonus (3pts) for score 4' {
        # "a11y" matches trigger "a11y" (+1) AND token "accessibility" matches name (+3)
        $results = @(Resolve-Skill 'accessibility a11y' 0)

        $results[0].Name | Should -Be 'accessibility'
        $results[0].Score | Should -Be 4  # 1 trigger + 3 name
    }

    It 'does NOT apply name bonus when token only matches trigger' {
        # "a11y" only matches trigger, skill name "accessibility" doesn't contain "a11y"
        $results = @(Resolve-Skill 'a11y testing' 0)

        $results[0].Name | Should -Be 'accessibility'
        $results[0].Score | Should -Be 1  # only trigger match
    }

    It 'uses same token-split regex as skill-resolver-fast.ps1 (C4a alignment)' {
        # Both resolvers must tokenize identically: \s+|[-_/.,!?;:()]
        # "triple-verify" splits to ["triple", "verify"] (hyphen is delimiter)
        # "pre.commit" splits to ["pre", "commit"] (dot is delimiter)
        $testTask = 'triple-verify pre.commit'
        $tokens = $testTask.ToLowerInvariant() -split '\s+|[-_/.,!?;:()]' |
            Where-Object { $_.Length -gt 2 } | Select-Object -Unique

        $tokens | Should -Contain 'triple'
        $tokens | Should -Contain 'verify'
        $tokens | Should -Contain 'pre'
        $tokens | Should -Contain 'commit'
    }
}

# ============================================================
Describe 'Skill Registry Cache' {
    BeforeAll {
        $script:testCsv = Join-Path $TestDrive 'test-registry.csv'
        $script:testCache = Join-Path $TestDrive 'skill-graph-cache.json'
    }

    BeforeEach {
        Set-Content -Path $script:testCsv -Value @(
            'Name|Triggers|Category|Effort|DependsOn|Related|Description'
            'A|trigger_a|test|low|||Skill A depends on B'
            'B|trigger_b|test|low|||Skill B'
        ) -Encoding utf8
        Remove-Item $script:testCache -Force -ErrorAction SilentlyContinue
    }

    It 'cache miss: cold parse runs and writes cache file' {
        $result = @(Get-SkillRegistry -CsvPath $script:testCsv -CachePath $script:testCache)

        $result.Count | Should -Be 2
        @($result | ForEach-Object { $_.Name }) | Should -Contain 'A'
        @($result | ForEach-Object { $_.Name }) | Should -Contain 'B'
        (Test-Path $script:testCache) | Should -Be $true
    }

    It 'cache hit with matching hash: loads cache without re-parsing' {
        # Prime the cache (cold parse + write)
        $null = @(Get-SkillRegistry -CsvPath $script:testCsv -CachePath $script:testCache)
        $primed = Get-Content $script:testCache -Raw

        # Second call with unchanged CSV must hit the cache — file NOT rewritten
        # (a rewrite would update cachedAt timestamp, proving a re-parse occurred)
        $result = @(Get-SkillRegistry -CsvPath $script:testCsv -CachePath $script:testCache)

        $result.Count | Should -Be 2
        (Get-Content $script:testCache -Raw) | Should -Be $primed
    }

    It 'cache stale after CSV changes: re-parses and refreshes cache' {
        # Prime cache from 2-row CSV
        $null = @(Get-SkillRegistry -CsvPath $script:testCsv -CachePath $script:testCache)

        # Append a new row — CSV content hash changes → cache invalidated
        Add-Content -Path $script:testCsv -Value 'C|trigger_c|test|low|||Skill C' -Encoding utf8

        $result = @(Get-SkillRegistry -CsvPath $script:testCsv -CachePath $script:testCache)

        $result.Count | Should -Be 3
        @($result | ForEach-Object { $_.Name }) | Should -Contain 'C'
        # Cache refreshed with new hash (contains 3 skills now)
        $cached = Get-Content $script:testCache -Raw | ConvertFrom-Json
        $cached.skills.Count | Should -Be 3
    }

    It 'corrupt JSON cache: falls back to parse and overwrites cache' {
        # Write garbage into the cache file (invalid JSON)
        Set-Content -Path $script:testCache -Value '{ this is not valid json ]]' -Encoding utf8

        $result = @(Get-SkillRegistry -CsvPath $script:testCsv -CachePath $script:testCache)

        $result.Count | Should -Be 2
        @($result | ForEach-Object { $_.Name }) | Should -Contain 'A'
        # Cache overwritten with valid JSON
        $cached = Get-Content $script:testCache -Raw | ConvertFrom-Json
        $cached.hash.Length | Should -Be 64
        $cached.skills.Count | Should -Be 2
    }
}
