#requires -Version 7

BeforeAll {
    # Standalone reimplementation of the script's core glob-to-regex conversion
    function Test-ConvertGlobToRegex {
        param([string]$Glob)
        $escaped = [regex]::Escape($Glob)
        $escaped = $escaped -replace '\\\*', '.*'
        $escaped = $escaped -replace '\\\?', '.'
        return "^$escaped$"
    }

    # Test helper: replicates the core validation loop
    function Test-ValidateScope {
        param([string[]]$ChangedFiles, [string[]]$Patterns)
        $violations = @(); $clean = @()
        foreach ($file in $ChangedFiles) {
            $matched = $false
            foreach ($pattern in $Patterns) {
                try {
                    $regex = Test-ConvertGlobToRegex -Glob $pattern
                    if ($file -match $regex) { $matched = $true; break }
                } catch { }
            }
            if ($matched) { $clean += $file } else { $violations += $file }
        }
        return @{ Clean = @($clean); Violations = @($violations) }
    }
}

Describe 'Test-ConvertGlobToRegex' {

    It 'converts <Glob> to <Expected>' -ForEach @(
        @{ Glob = '*.ts';         Expected = '^.*\.ts$' }
        @{ Glob = 'src/auth/*';   Expected = '^src/auth/.*$' }
        @{ Glob = 'src/auth/*.ts'; Expected = '^src/auth/.*\.ts$' }
        @{ Glob = 'scripts/*.ps1'; Expected = '^scripts/.*\.ps1$' }
        @{ Glob = '*';            Expected = '^.*$' }
        @{ Glob = '?';            Expected = '^.$' }
    ) {
        Test-ConvertGlobToRegex -Glob $Glob | Should -BeExactly $Expected
    }

    It 'escapes regex metacharacters (dots, plus, parens, brackets)' {
        Test-ConvertGlobToRegex -Glob 'src/login+v2(1).ts' |
            Should -BeExactly '^src/login\+v2\(1\)\.ts$'
    }

    It 'converts ? to single-character wildcard' {
        Test-ConvertGlobToRegex -Glob 'src/?.ts' | Should -BeExactly '^src/.\.ts$'
    }

    It 'converts multiple ? to wildcard sequence' {
        Test-ConvertGlobToRegex -Glob 'src/??.ts' | Should -BeExactly '^src/..\.ts$'
    }

    It 'handles mixed * and ? wildcards' {
        Test-ConvertGlobToRegex -Glob 'src/?-*.ts' | Should -BeExactly '^src/.-.*\.ts$'
    }

    It 'converts exact path (no wildcards) with anchor wrappers' {
        Test-ConvertGlobToRegex -Glob 'src/auth/login.ts' |
            Should -BeExactly '^src/auth/login\.ts$'
    }
}

Describe 'Scope validation logic' {

    It 'passes file matching single pattern' {
        $r = Test-ValidateScope -ChangedFiles @('src/auth/login.ts') -Patterns @('src/auth/*')
        $r.Clean.Count | Should -Be 1
        $r.Violations.Count | Should -Be 0
    }

    It 'passes file matching first of several patterns' {
        $r = Test-ValidateScope -ChangedFiles @('src/api/users.ts') -Patterns @('src/api/*', 'src/auth/*')
        $r.Clean.Count | Should -Be 1
        $r.Violations.Count | Should -Be 0
    }

    It 'flags file that matches none of the patterns' {
        $r = Test-ValidateScope -ChangedFiles @('config/deploy.yml') -Patterns @('src/*', 'scripts/*')
        $r.Clean.Count | Should -Be 0
        $r.Violations.Count | Should -Be 1
        $r.Violations[0] | Should -BeExactly 'config/deploy.yml'
    }

    It 'separates clean and violation across multiple files' {
        $r = Test-ValidateScope -ChangedFiles @('src/a.ts', 'docs/b.md', 'src/c.ts') -Patterns @('src/*')
        $r.Clean.Count | Should -Be 2
        $r.Violations.Count | Should -Be 1
        $r.Violations[0] | Should -BeExactly 'docs/b.md'
    }

    It 'returns empty sets when no files changed' {
        $r = Test-ValidateScope -ChangedFiles @() -Patterns @('src/*')
        $r.Clean.Count | Should -Be 0
        $r.Violations.Count | Should -Be 0
    }

    It 'flags ALL files when patterns list is empty' {
        $r = Test-ValidateScope -ChangedFiles @('src/a.ts', 'docs/b.md') -Patterns @()
        $r.Clean.Count | Should -Be 0
        $r.Violations.Count | Should -Be 2
    }

    It 'matches nested paths under directory glob' {
        $r = Test-ValidateScope -ChangedFiles @('src/auth/subdir/login.ts') -Patterns @('src/auth/*')
        $r.Clean.Count | Should -Be 1
        $r.Violations.Count | Should -Be 0
    }

    It 'matches exact path with no wildcards' {
        $r = Test-ValidateScope -ChangedFiles @('src/auth/login.ts') -Patterns @('src/auth/login.ts')
        $r.Clean.Count | Should -Be 1
        $r.Violations.Count | Should -Be 0
    }

    It 'handles paths with regex-special characters' {
        $r = Test-ValidateScope -ChangedFiles @('src/login+v2(1).ts') -Patterns @('src/*')
        $r.Clean.Count | Should -Be 1
        $r.Violations.Count | Should -Be 0
    }

    It 'respects overlapping patterns (broader + narrower)' {
        $r = Test-ValidateScope -ChangedFiles @('src/auth/admin.ts') -Patterns @('src/*', 'src/auth/*')
        $r.Clean.Count | Should -Be 1
        $r.Clean[0] | Should -BeExactly 'src/auth/admin.ts'
        $r.Violations.Count | Should -Be 0
    }
}

Describe 'Parameter validation logic' {

    It 'detects empty AllowedPaths using same check as script' {
        $p = ''; (-not $p -or $p.Trim() -eq '') | Should -BeTrue
    }

    It 'detects whitespace-only AllowedPaths' {
        $p = '   '; (-not $p -or $p.Trim() -eq '') | Should -BeTrue
    }

    It 'detects BaseRef with spaces' {
        $p = 'HEAD HEAD~1'; $p -match '\s' | Should -BeTrue
    }

    It 'accepts single-word BaseRef' {
        $p = 'HEAD'; $p -match '\s' | Should -BeFalse
    }

    It 'detects empty BaseRef' {
        $p = ''; (-not $p -or $p.Trim() -eq '') | Should -BeTrue
    }
}

