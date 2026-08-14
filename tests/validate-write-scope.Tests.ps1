#requires -Version 7
Describe "validate-write-scope.ps1" {
  BeforeAll { $scriptPath = Join-Path $PSScriptRoot "..\scripts\validate-write-scope.ps1" }

  It "T1 accepts string[] form, CLEAN on no changes" {
    $r = & $scriptPath -AllowedPaths @("mejora-log.md","adr/*","scripts/*.ps1","tests/*") -BaseRef HEAD 2>&1
    $LASTEXITCODE | Should -Be 0
    ($r -join "`n") | Should -Match '\[CLEAN\]'
  }

  It "T2 staged VIOLATION (file outside allowed patterns)" {
    $scratch = "tests/_scratch_vws.txt"
    "x" | Set-Content -Path $scratch
    try {
      git add $scratch
      $o = & $scriptPath -AllowedPaths @("zzz/nonexistent/*") -Staged -BaseRef HEAD 2>&1
      $LASTEXITCODE | Should -Be 1
      ($o -join "`n") | Should -Match '\[VIOLATION\]'
    } finally {
      git reset --quiet -- $scratch 2>$null
      if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Force }
    }
  }

  It "T3 comma-separated string back-compat CLEAN" {
    $r = & $scriptPath -AllowedPaths "mejora-log.md,adr/*,scripts/*.ps1,tests/*" -BaseRef HEAD 2>&1
    $LASTEXITCODE | Should -Be 0
    ($r -join "`n") | Should -Match '\[CLEAN\]'
  }

  It "T4 empty allowed-paths fails CLOSED (exit 1)" {
    $r = & $scriptPath -AllowedPaths @() -BaseRef HEAD 2>&1
    $LASTEXITCODE | Should -Be 1
    ($r -join "`n") | Should -Match 'ERROR'
  }
}