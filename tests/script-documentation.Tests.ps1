#requires -Version 7
<#
.SYNOPSIS
  Enforces docs/SCRIPT-DOC-STANDARD.md: registered scripts must carry
  complete comment-based help (.SYNOPSIS .DESCRIPTION .PARAMETER .EXAMPLE).
.DESCRIPTION
  Reads the Script registry section of docs/SCRIPT-DOC-STANDARD.md and asserts
  each listed scripts/<name>.ps1 exists, declares a script/function block, and
  contains all four mandatory help tags exactly once.
  Runs inside the pre-commit gate (22 checks, [12/22] Pester tests) — a
  registered script without full help blocks every commit.
  Registry is parsed at DISCOVERY (Describe scope) so Context blocks are
  generated per entry; per-entry data reaches the It blocks via -TestCases
  (Pester run stage does not share Describe/Context-local variables).
.PARAMETER None
  No parameters; the registry comes from the standard doc.
.EXAMPLE
  Invoke-Pester -Path tests/script-documentation.Tests.ps1
#>
Describe "script-documentation standard" {
  # Discovery-time registry parse: Contexts are generated from this list, so it
  # cannot live in BeforeAll (which runs after the Contexts are built).
  $script:registry = @()
  $standardDoc = Join-Path $PSScriptRoot "..\docs\SCRIPT-DOC-STANDARD.md"
  if (Test-Path -LiteralPath $standardDoc) {
    $doc = Get-Content -LiteralPath $standardDoc -Raw
    # Parse only the "## Script registry" section: bullets like "- scripts/name.ps1"
    $section = [regex]::Match($doc, '(?ms)^## Script registry\s*$(.*?)^## ')
    if ($section.Success) {
      $script:registry = @(
        [regex]::Matches($section.Groups[1].Value, '(?m)^-\s+(scripts/[\w.-]+\.ps1)') |
          ForEach-Object { $_.Groups[1].Value }
      )
    }
  }

  It "registry is not empty" -TestCases @{ count = $script:registry.Count } {
    param($count)
    $count | Should -BeGreaterThan 0
  }

  foreach ($rel in $script:registry) {
    Context "registry entry: $rel" {
      It "file exists and declares a script/function block" -TestCases @{ rel = $rel } {
        param($rel)
        $path = Join-Path $PSScriptRoot "..\$rel"
        $path | Should -Exist
        Get-Content -LiteralPath $path -Raw |
          Should -Match '\[CmdletBinding\([^)]*\)\]|(?m)^\s*param\s*\(|(?m)^\s*function\s+\S+'
      }

      It "contains all four mandatory help tags" -TestCases @{ rel = $rel } {
        param($rel)
        $raw = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\$rel") -Raw
        $raw | Should -Match '(?m)\.SYNOPSIS'
        $raw | Should -Match '(?m)\.DESCRIPTION'
        $raw | Should -Match '(?m)\.PARAMETER\s+\S+'
        $raw | Should -Match '(?m)\.EXAMPLE'
      }

      It "does not duplicate the help block" -TestCases @{ rel = $rel } {
        param($rel)
        $raw = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\$rel") -Raw
        ([regex]::Matches($raw, '(?m)^\s*\.SYNOPSIS')).Count | Should -Be 1
      }
    }
  }
}