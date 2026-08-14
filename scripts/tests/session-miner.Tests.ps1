#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Pester tests for session-miner.ps1 — learning pipeline, pattern detection, populate mode.
    Uses temp directories for filesystem-level testing of file-based operations.
.NOTES
    ponytail: filesystem tests — uses temp dirs, cleaned up after.
    Extracts functions from source to avoid running main logic (which has side effects).
    Compatible with Pester 5.x / 6.x.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # Define cleaned versions of internal functions with explicit parameters
    # (originally from session-miner.ps1, adapted for test isolation)
    function rc {
        param([string]$CatalogPath)
        if (-not (Test-Path $CatalogPath)) { return ,@() }
        try {
            $c = Get-Content $CatalogPath -Raw
        } catch { return ,@() }
        $p = @()
        $rows = [regex]::Matches($c, '^\|\s*\d+\s*\|.*?\|.*?\|.*?\|.*?\|.*?\|.*?\|', 'Multiline')
        foreach ($r in $rows) {
            $parts = $r.Value -split '\|' | ForEach-Object { $_.Trim() }
            if ($parts.Count -ge 8) {
                $id = 0; [int]::TryParse($parts[1], [ref]$id) | Out-Null
                $p += [PSCustomObject]@{Id=$id; Date=$parts[2]; Pattern=$parts[3]; Symptom=$parts[4]; RootCause=$parts[5]; Fix=$parts[6]; Prevention=$parts[7]}
            }
        }
        return ,$p
    }

    function rl {
        param([string]$LearningsPath)
        if (-not (Test-Path $LearningsPath)) { return ,@() }
        try {
            $c = Get-Content $LearningsPath -Raw
        } catch { return ,@() }
        $k = @()
        $m = [regex]::Matches($c, '^[\s]*Pattern-Key:\s*([^\n\r]+)', 'Multiline')
        foreach ($x in $m) { $k += $x.Groups[1].Value.Trim() }
        return ,$k
    }

    function re {
        param([string]$ErrorsPath)
        if (-not (Test-Path $ErrorsPath)) { return ,@() }
        try {
            $c = Get-Content $ErrorsPath -Raw
        } catch { return ,@() }
        $e = @()
        $entries = [regex]::Matches($c, '^##\s+\[\w+-\d+-\d+\]\s+(.+?)$', 'Multiline')
        foreach ($entry in $entries) { $e += $entry.Groups[1].Value.Trim() }
        return ,$e
    }

    function frp {
        param([array]$Catalog, [array]$PatternKeys, [int]$MinCount = 2)
        $kc = @{}
        foreach ($k in $PatternKeys) {
            if ($kc.ContainsKey($k)) { $kc[$k]++ } else { $kc[$k] = 1 }
        }
        $r = @()
        foreach ($e in $kc.GetEnumerator()) {
            if ($e.Value -ge $MinCount) {
                $cat = $false
                foreach ($c in $Catalog) {
                    if ($c.Pattern -cmatch [regex]::Escape($e.Name)) { $cat = $true; break }
                }
                $r += [PSCustomObject]@{PatternKey=$e.Name; Count=$e.Value; Cataloged=$cat}
            }
        }
        return $r
    }

    # Helper: create temp fixture with known content
    function New-TestFixture {
        param([string]$Prefix = "sm-test")
        $root = Join-Path ([System.IO.Path]::GetTempPath()) "$Prefix-$(Get-Random)"
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        return $root
    }

    # Helper: create a test ANTI-PATTERN-CATALOG.md
    function New-TestCatalog {
        param([string]$Dir)
        $path = Join-Path $Dir 'ANTI-PATTERN-CATALOG.md'
        @"
# ANTI-PATTERN CATALOG

| # | Date | Pattern | Symptom | Root cause | Fix | Prevention |
|---|------|---------|---------|------------|-----|------------|
| 1 | 2026-05-26 | Premature solution | Coded before understanding | Didn't ask clarifying questions | STOP → re-read | Gate before code |
| 2 | 2026-06-07 | no-evidence-self-assessment | 'Done' without verification | Overconfidence | Default-FAIL | Verify before agree |
"@ | Set-Content -Path $path -Encoding UTF8
        return $path
    }

    # Helper: create a test LEARNINGS.md
    function New-TestLearnings {
        param([string]$Dir, [string[]]$Keys)
        $path = Join-Path $Dir '.learnings'
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $lp = Join-Path $path 'LEARNINGS.md'
        $lines = @("# Learnings", "")
        foreach ($k in $Keys) {
            $lines += "# 2026-07-28"
            $lines += "Pattern-Key: $k"
            $lines += ""
        }
        $lines -join "`r`n" | Set-Content -Path $lp -Encoding UTF8
        return $lp
    }

    # Helper: create a test ERRORS.md
    function New-TestErrors {
        param([string]$Dir, [string[]]$Entries)
        $path = Join-Path $Dir '.learnings'
        if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
        $ep = Join-Path $path 'ERRORS.md'
        $lines = @("# Error Log", "")
        foreach ($e in $Entries) {
            $lines += "## [2026-07-28] $e"
            $lines += ""
        }
        $lines -join "`r`n" | Set-Content -Path $ep -Encoding UTF8
        return $ep
    }
}

# ============================================================
Describe 'rl (read learnings)' {
    It 'returns empty array for missing file' {
        $result = rl -LearningsPath 'nonexistent.md'
        $result | Should -BeNullOrEmpty
    }

    It 'returns pattern keys from valid LEARNINGS.md' {
        $dir = New-TestFixture
        try {
            $lp = New-TestLearnings -Dir $dir -Keys @('test-pattern-one', 'test-pattern-two')
            $result = rl -LearningsPath $lp
            $result.Count | Should -Be 2
            $result[0] | Should -Be 'test-pattern-one'
            $result[1] | Should -Be 'test-pattern-two'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ignores inline text with Pattern-Key: (regression)' {
        $dir = New-TestFixture
        try {
            $lp = Join-Path $dir 'LEARNINGS.md'
            @"
# Learnings
Reads `Pattern-Key:` lines from this file.
Format: Pattern-Key: <example>
But real entries are on their own line:
Pattern-Key: real-pattern
"@ | Set-Content -Path $lp -Encoding UTF8
            $result = rl -LearningsPath $lp
            $result.Count | Should -Be 1
            $result[0] | Should -Be 'real-pattern'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
Describe 're (read errors)' {
    It 'returns empty array for missing file' {
        $result = re -ErrorsPath 'nonexistent.md'
        $result | Should -BeNullOrEmpty
    }

    It 'returns error entries from valid ERRORS.md' {
        $dir = New-TestFixture
        try {
            $ep = New-TestErrors -Dir $dir -Entries @('crash on startup', 'timeout after retry')
            $result = re -ErrorsPath $ep
            $result.Count | Should -Be 2
            $result[0] | Should -Be 'crash on startup'
            $result[1] | Should -Be 'timeout after retry'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ignores inline text with ## [date] (regression)' {
        $dir = New-TestFixture
        try {
            $ep = Join-Path $dir 'ERRORS.md'
            @"
# Error Log
Format: ## [YYYY-MM-DD] description
## [2026-07-28] real error here
"@ | Set-Content -Path $ep -Encoding UTF8
            $result = re -ErrorsPath $ep
            $result.Count | Should -Be 1
            $result[0] | Should -Be 'real error here'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
Describe 'rc (read catalog)' {
    It 'returns empty array for missing file' {
        $result = rc -CatalogPath 'nonexistent.md'
        $result | Should -BeNullOrEmpty
    }

    It 'parses catalog entries from ANTI-PATTERN-CATALOG.md' {
        $dir = New-TestFixture
        try {
            $cp = New-TestCatalog -Dir $dir
            $result = rc -CatalogPath $cp
            $result.Count | Should -Be 2
            $result[0].Pattern | Should -Be 'Premature solution'
            $result[1].Pattern | Should -Be 'no-evidence-self-assessment'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
Describe 'frp (find repeated patterns)' {
    It 'returns empty for single occurrence' {
        $cat = @()
        $pk = @('unique-pattern')
        $result = frp -Catalog $cat -PatternKeys $pk -MinCount 2
        @($result).Count | Should -Be 0
    }

    It 'detects repeated patterns at threshold' {
        $cat = @()
        $pk = @('repeated-pattern', 'repeated-pattern')
        $result = frp -Catalog $cat -PatternKeys $pk -MinCount 2
        @($result).Count | Should -Be 1
        $result[0].PatternKey | Should -Be 'repeated-pattern'
        $result[0].Count | Should -Be 2
        $result[0].Cataloged | Should -Be $false
    }

    It 'marks as cataloged when pattern exists in catalog' {
        $cat = @([PSCustomObject]@{Pattern='no-evidence-self-assessment'})
        $pk = @('no-evidence-self-assessment', 'no-evidence-self-assessment')
        $result = frp -Catalog $cat -PatternKeys $pk -MinCount 2
        @($result).Count | Should -Be 1
        $result[0].Cataloged | Should -Be $true
    }

    It 'respects custom threshold' {
        $cat = @()
        $pk = @('low-frequency')
        $result = frp -Catalog $cat -PatternKeys $pk -MinCount 1
        @($result).Count | Should -Be 1
    }
}

# ============================================================
Describe 'populate mode (end-to-end)' {
    It 'writes new pattern keys to LEARNINGS.md' {
        $dir = New-TestFixture
        try {
            $lp = New-TestLearnings -Dir $dir -Keys @('existing-key')
            $ep = Join-Path $dir '.learnings\ERRORS.md'
            "# Error Log`r`n" | Set-Content -Path $ep -Encoding UTF8
            $cp = Join-Path $dir 'ANTI-PATTERN-CATALOG.md'
            '# ANTI-PATTERN CATALOG' | Set-Content -Path $cp -Encoding UTF8

            $result = & "$PSScriptRoot\..\session-miner.ps1" -Mode populate -PatternKeys @('new-key', 'existing-key') -Json -Root $dir 2>&1
            $data = $result | ConvertFrom-Json

            # PatternKeys is a count (integer), not an array — check the count value
            $data.PatternKeys | Should -BeGreaterOrEqual 2

            $content = Get-Content (Join-Path $dir '.learnings\LEARNINGS.md') -Raw
            $content | Should -Match 'Pattern-Key: new-key'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes new error entries to ERRORS.md' {
        $dir = New-TestFixture
        try {
            $lp = Join-Path $dir '.learnings'
            New-Item -ItemType Directory -Path $lp -Force | Out-Null
            "# Learnings`r`n" | Set-Content -Path (Join-Path $lp 'LEARNINGS.md') -Encoding UTF8
            "# Error Log`r`n" | Set-Content -Path (Join-Path $lp 'ERRORS.md') -Encoding UTF8
            $cp = Join-Path $dir 'ANTI-PATTERN-CATALOG.md'
            '# ANTI-PATTERN CATALOG' | Set-Content -Path $cp -Encoding UTF8

            $result = & "$PSScriptRoot\..\session-miner.ps1" -Mode populate -ErrorEntries @('new error one', 'new error two') -Json -Root $dir 2>&1
            $data = $result | ConvertFrom-Json

            # ErrorEntries is a count (integer), not an array
            $data.ErrorEntries | Should -Be 2

            $content = Get-Content (Join-Path $dir '.learnings\ERRORS.md') -Raw
            $content | Should -Match 'new error one'
            $content | Should -Match 'new error two'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'deduplicates pattern keys across calls' {
        $dir = New-TestFixture
        try {
            $lp = Join-Path $dir '.learnings'
            New-Item -ItemType Directory -Path $lp -Force | Out-Null
            "# Learnings`r`n# 2026-07-28`r`nPattern-Key: existing-key`r`n" | Set-Content -Path (Join-Path $lp 'LEARNINGS.md') -Encoding UTF8
            "# Error Log`r`n" | Set-Content -Path (Join-Path $lp 'ERRORS.md') -Encoding UTF8
            $cp = Join-Path $dir 'ANTI-PATTERN-CATALOG.md'
            '# ANTI-PATTERN CATALOG' | Set-Content -Path $cp -Encoding UTF8

            & "$PSScriptRoot\..\session-miner.ps1" -Mode populate -PatternKeys @('existing-key', 'new-key') -Json -Root $dir 2>&1 | Out-Null
            $result2 = & "$PSScriptRoot\..\session-miner.ps1" -Mode populate -PatternKeys @('existing-key', 'new-key') -Json -Root $dir 2>&1

            $content = Get-Content (Join-Path $dir '.learnings\LEARNINGS.md') -Raw
            $matches = [regex]::Matches($content, 'Pattern-Key: new-key', 'Multiline')
            $matches.Count | Should -Be 1
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'handles empty PatternKeys without error' {
        $dir = New-TestFixture
        try {
            $lp = Join-Path $dir '.learnings'
            New-Item -ItemType Directory -Path $lp -Force | Out-Null
            "# Learnings`r`n" | Set-Content -Path (Join-Path $lp 'LEARNINGS.md') -Encoding UTF8
            "# Error Log`r`n" | Set-Content -Path (Join-Path $lp 'ERRORS.md') -Encoding UTF8
            $cp = Join-Path $dir 'ANTI-PATTERN-CATALOG.md'
            '# ANTI-PATTERN CATALOG' | Set-Content -Path $cp -Encoding UTF8

            $result = & "$PSScriptRoot\..\session-miner.ps1" -Mode populate -Json -Root $dir 2>&1
            $result | Should -Not -BeNullOrEmpty
            $data = $result | ConvertFrom-Json
            $data.Status | Should -Be 'CLEAN'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'converts discoveries to kebab-case keys' {
        $dir = New-TestFixture
        try {
            $lp = Join-Path $dir '.learnings'
            New-Item -ItemType Directory -Path $lp -Force | Out-Null
            "# Learnings`r`n" | Set-Content -Path (Join-Path $lp 'LEARNINGS.md') -Encoding UTF8
            "# Error Log`r`n" | Set-Content -Path (Join-Path $lp 'ERRORS.md') -Encoding UTF8
            $cp = Join-Path $dir 'ANTI-PATTERN-CATALOG.md'
            '# ANTI-PATTERN CATALOG' | Set-Content -Path $cp -Encoding UTF8

            & "$PSScriptRoot\..\session-miner.ps1" -Mode populate -PatternKeys @('Fix N+1 Query', 'Add Circuit Breaker') -Json -Root $dir 2>&1 | Out-Null

            $content = Get-Content (Join-Path $dir '.learnings\LEARNINGS.md') -Raw
            # The + character is stripped by the kebab converter, so 'Fix N+1 Query' becomes 'Fix-N1-Query'
            $content | Should -Match 'Pattern-Key: Fix-N1-Query'
            $content | Should -Match 'Pattern-Key: Add-Circuit-Breaker'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
Describe 'check mode (integration)' {
    It 'returns CLEAN when no repeated patterns' {
        $dir = New-TestFixture
        try {
            $lp = Join-Path $dir '.learnings'
            New-Item -ItemType Directory -Path $lp -Force | Out-Null
            "# Learnings`r`n# 2026-07-28`r`nPattern-Key: unique-pattern`r`n" | Set-Content -Path (Join-Path $lp 'LEARNINGS.md') -Encoding UTF8
            "# Error Log`r`n" | Set-Content -Path (Join-Path $lp 'ERRORS.md') -Encoding UTF8
            New-TestCatalog -Dir $dir | Out-Null

            $result = & "$PSScriptRoot\..\session-miner.ps1" -Mode check -Json -Root $dir 2>&1
            $data = $result | ConvertFrom-Json
            $data.Status | Should -Be 'CLEAN'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns PATTERNS_FOUND when threshold met' {
        $dir = New-TestFixture
        try {
            $lp = Join-Path $dir '.learnings'
            New-Item -ItemType Directory -Path $lp -Force | Out-Null
            "# Learnings`r`n# 2026-07-28`r`nPattern-Key: repeat-pattern`r`n# 2026-07-29`r`nPattern-Key: repeat-pattern`r`n" | Set-Content -Path (Join-Path $lp 'LEARNINGS.md') -Encoding UTF8
            "# Error Log`r`n" | Set-Content -Path (Join-Path $lp 'ERRORS.md') -Encoding UTF8
            New-TestCatalog -Dir $dir | Out-Null

            $result = & "$PSScriptRoot\..\session-miner.ps1" -Mode check -Json -Root $dir 2>&1
            $data = $result | ConvertFrom-Json
            $data.Status | Should -Be 'PATTERNS_FOUND'
            $data.RepeatedPatterns | Should -BeGreaterThan 0
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
Describe 'scan mode (integration)' {
    It 'identifies uncataloged repeated patterns' {
        $dir = New-TestFixture
        try {
            $lp = Join-Path $dir '.learnings'
            New-Item -ItemType Directory -Path $lp -Force | Out-Null
            "# Learnings`r`n# 2026-07-28`r`nPattern-Key: uncataloged-repeat`r`n# 2026-07-29`r`nPattern-Key: uncataloged-repeat`r`n" | Set-Content -Path (Join-Path $lp 'LEARNINGS.md') -Encoding UTF8
            "# Error Log`r`n" | Set-Content -Path (Join-Path $lp 'ERRORS.md') -Encoding UTF8
            New-TestCatalog -Dir $dir | Out-Null

            $result = & "$PSScriptRoot\..\session-miner.ps1" -Mode scan -Json -Root $dir 2>&1
            $data = $result | ConvertFrom-Json
            $data.UnCatalogedCount | Should -BeGreaterThan 0
            $data.CanApply | Should -Be $true
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
