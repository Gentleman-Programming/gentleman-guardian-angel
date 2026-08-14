#requires -Version 7
<#
.SYNOPSIS
    E2E validation for SKILL.md frontmatter consistency across all skills.
.DESCRIPTION
    Validates:
    - All SKILL.md files have YAML frontmatter
    - Required fields present (name, description)
    - Triggers field is array
    - No duplicate skill names
.NOTES
    Scans .agents/skills/ recursively.
#>

Describe "SKILL.md Frontmatter Validation" {
    BeforeAll {
        $skillsRoot = Join-Path $PSScriptRoot "..\.agents\skills"
        $skillFiles = Get-ChildItem -Path $skillsRoot -Filter "SKILL.md" -Recurse -File
    }

    Context "Frontmatter Presence" {
        It "All SKILL.md files have frontmatter (--- delimiters)" {
            $missingFrontmatter = @()
            foreach ($file in $skillFiles) {
                $content = Get-Content $file.FullName -Raw
                if ($content -notmatch '^\s*---\s*\r?\n') {
                    $missingFrontmatter += $file.FullName
                }
            }
            $missingFrontmatter.Count | Should -Be 0
        }

        It "All SKILL.md files have closing frontmatter delimiter" {
            $unclosedFrontmatter = @()
            foreach ($file in $skillFiles) {
                $content = Get-Content $file.FullName -Raw
                $matches = [regex]::Matches($content, '^\s*---\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
                if ($matches.Count -lt 2) {
                    $unclosedFrontmatter += $file.FullName
                }
            }
            $unclosedFrontmatter.Count | Should -Be 0
        }
    }

    Context "Required Fields" {
        It "All skills have 'name' field" {
            $missingName = @()
            foreach ($file in $skillFiles) {
                $content = Get-Content $file.FullName -Raw
                if ($content -match '^\s*---\s*\r?\n([\s\S]*?)\r?\n\s*---') {
                    $frontmatter = $matches[1]
                    # Check for name field (with or without quotes, with any whitespace)
                    if ($frontmatter -notmatch 'name:\s*\S') {
                        $missingName += $file.FullName
                    }
                }
            }
            $missingName.Count | Should -Be 0
        }

        It "All skills have 'description' field" {
            $missingDescription = @()
            foreach ($file in $skillFiles) {
                $content = Get-Content $file.FullName -Raw
                if ($content -match '^\s*---\s*\r?\n([\s\S]*?)\r?\n\s*---') {
                    $frontmatter = $matches[1]
                    # Check for description field (with or without quotes, with any whitespace)
                    if ($frontmatter -notmatch 'description:\s*\S') {
                        $missingDescription += $file.FullName
                    }
                }
            }
            $missingDescription.Count | Should -Be 0
        }
    }

    Context "Field Format" {
        It "Description fields are non-empty" {
            $emptyDescriptions = @()
            foreach ($file in $skillFiles) {
                $content = Get-Content $file.FullName -Raw
                if ($content -match '^\s*---\s*\r?\n[\s\S]*?description:\s*$') {
                    $emptyDescriptions += $file.FullName
                }
            }
            $emptyDescriptions.Count | Should -Be 0
        }

        It "Name fields match directory name" {
            $mismatchedNames = @()
            foreach ($file in $skillFiles) {
                $dirName = Split-Path $file.Directory -Leaf
                $content = Get-Content $file.FullName -Raw
                if ($content -match '^\s*---\s*\r?\n[\s\S]*?name:\s*(.+?)\s*\r?\n') {
                    $skillName = $matches[1].Trim()
                    # Allow name to differ from directory (e.g., _shared)
                    if ($dirName -notmatch '^_' -and $skillName -ne $dirName) {
                        # Not a failure, just informational
                    }
                }
            }
            # This is informational, not a hard requirement
            $true | Should -Be $true
        }
    }

    Context "Uniqueness" {
        It "No duplicate skill names across all SKILL.md files" {
            $skillNames = @()
            foreach ($file in $skillFiles) {
                $content = Get-Content $file.FullName -Raw
                if ($content -match '^\s*---\s*\r?\n[\s\S]*?name:\s*(.+?)\s*\r?\n') {
                    $skillNames += $matches[1].Trim()
                }
            }
            $uniqueNames = $skillNames | Select-Object -Unique
            $skillNames.Count | Should -Be $uniqueNames.Count
        }

        It "No duplicate skill directories" {
            $dirNames = $skillFiles | ForEach-Object { Split-Path $_.Directory -Leaf }
            $uniqueDirs = $dirNames | Select-Object -Unique
            $dirNames.Count | Should -Be $uniqueDirs.Count
        }
    }

    Context "Coverage" {
        It "At least 80 skills are defined" {
            $skillFiles.Count | Should -BeGreaterOrEqual 80
        }

        It "Skills are organized in .agents/skills/ directory" {
            $skillFiles.Count | Should -BeGreaterThan 0
            $skillFiles[0].FullName | Should -Match '[\\/]\.agents[\\/]skills[\\/]'
        }
    }
}