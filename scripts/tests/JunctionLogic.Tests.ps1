#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Pester 6 tests for Test-Junction from health-check.ps1
.DESCRIPTION
  Tests the junction validation logic: return structure, status codes, and
  edge cases. Uses temp directories for filesystem state (read-only function).
  Note: Test-Junction has nested braces that break the regex extraction pattern,
  so it is defined manually (same approach as CacheHash.Tests.ps1).
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # ponytail: manual extraction — nested braces prevent regex extraction
    # Mirrors health-check.ps1 Test-Junction exactly (lines 45-71)
    function Test-Junction {
      param([string]$Path, [string]$ExpectedTarget, [string]$Label)
      $result = @{check = $Label; status = "OK"; detail = ""}
      if (Test-Path $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.LinkType -ne "Junction") {
          $result.status = "WARN"
          $result.detail = "Exists but not a junction (real file/dir)"
          return $result
        }
        if (-not (Test-Path $item.Target)) {
          $result.status = "FAIL"
          $result.detail = "Target missing: $($item.Target)"
          return $result
        }
        if ($item.Target -ne (Resolve-Path $ExpectedTarget).Path) {
          $result.status = "WARN"
          $result.detail = "Target mismatch: $($item.Target) → expected $ExpectedTarget"
          return $result
        }
        $result.detail = "$($item.Target) ✅"
      } else {
        $result.status = "FAIL"
        $result.detail = "Missing"
      }
      return $result
    }

    $script:tmpCleanup = [System.Collections.Generic.List[string]]::new()
}

AfterAll {
    foreach ($d in $script:tmpCleanup) {
        Remove-Item -LiteralPath $d -Force -Recurse -ErrorAction SilentlyContinue
    }
}

Describe 'Test-Junction Return Structure' {
    It 'always returns hashtable with check, status, detail keys' {
        $r = Test-Junction -Path "C:\nonexistent_$(Get-Random)" -ExpectedTarget "C:\nope" -Label "struct"
        $r | Should -BeOfType [hashtable]
        $r.Keys | Should -Contain 'check'
        $r.Keys | Should -Contain 'status'
        $r.Keys | Should -Contain 'detail'
    }
    It 'passes through the Label as check name' {
        $r = Test-Junction -Path "C:\nonexistent_$(Get-Random)" -ExpectedTarget "C:\nope" -Label "my-check"
        $r.check | Should -BeExactly 'my-check'
    }
}

Describe 'Test-Junction Missing Path' {
    It 'returns FAIL status when path does not exist' {
        $r = Test-Junction -Path "C:\nonexistent_$(Get-Random)" -ExpectedTarget "C:\nope" -Label "miss"
        $r.status | Should -BeExactly 'FAIL'
    }
    It 'detail says Missing' {
        $r = Test-Junction -Path "C:\nonexistent_$(Get-Random)" -ExpectedTarget "C:\nope" -Label "miss"
        $r.detail | Should -BeExactly 'Missing'
    }
}

Describe 'Test-Junction Non-Junction' {
    It 'returns WARN for existing regular directory' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "pester_jtn_$(Get-Random)"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $script:tmpCleanup.Add($tmp)
        try {
            $r = Test-Junction -Path $tmp -ExpectedTarget "C:\nope" -Label "real-dir"
            $r.status | Should -BeExactly 'WARN'
            $r.detail | Should -Match 'not a junction'
        } finally {
            Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
    It 'returns WARN for existing regular file' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "pester_jtf_$(Get-Random).txt"
        Set-Content -Path $tmp -Value "test" -Force
        $script:tmpCleanup.Add($tmp)
        try {
            $r = Test-Junction -Path $tmp -ExpectedTarget "C:\nope" -Label "real-file"
            $r.status | Should -BeExactly 'WARN'
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-Junction Dead Target' {
    It 'returns FAIL when junction target does not exist' {
        # ponytail: Windows requires target to exist at junction creation time,
        # so create target → junction → remove target to simulate dead junction
        $target = Join-Path ([System.IO.Path]::GetTempPath()) "pester_jtdt_$(Get-Random)"
        $junc   = Join-Path ([System.IO.Path]::GetTempPath()) "pester_jtdj_$(Get-Random)"
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        New-Item -ItemType Junction -Path $junc -Target $target -Force | Out-Null
        Remove-Item -LiteralPath $target -Force -Recurse
        $script:tmpCleanup.Add($junc)
        try {
            $r = Test-Junction -Path $junc -ExpectedTarget $target -Label "dead"
            $r.status | Should -BeExactly 'FAIL'
            $r.detail | Should -Match 'Target missing'
        } finally {
            Remove-Item -LiteralPath $junc -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-Junction Valid Junction' {
    It 'returns OK when junction target exists and matches' {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) "pester_jtv_$(Get-Random)"
        $junc = Join-Path ([System.IO.Path]::GetTempPath()) "pester_jtj_$(Get-Random)"
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        New-Item -ItemType Junction -Path $junc -Target $target -Force | Out-Null
        $script:tmpCleanup.Add($junc)
        $script:tmpCleanup.Add($target)
        try {
            $r = Test-Junction -Path $junc -ExpectedTarget $target -Label "good"
            $r.status | Should -BeExactly 'OK'
            $r.detail | Should -Match '✅'
        } finally {
            Remove-Item -LiteralPath $junc -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $target -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}
