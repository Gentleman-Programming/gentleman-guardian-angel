#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
# Enforces PS version declaration matches reality (dot-sources must not pull PS7-only libs)
$repoScripts = Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) '*.ps1') -File
$repoLibs    = Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\*.ps1') -File

Describe 'PS version declaration consistency' {
    It 'every scripts/*.ps1 declares #requires -Version (5.1|7) in first 3 lines' {
        $missing = @()
        foreach ($s in $repoScripts) {
            $head = (Get-Content $s.FullName -TotalCount 3) -join "`n"
            if ($head -notmatch '#requires -Version (5\.1|7)') { $missing += $s.Name }
        }
        $missing | Should -BeNullOrEmpty
    }

    It 'every lib/*.ps1 declares #requires -Version 7' {
        $bad = @()
        foreach ($l in $repoLibs) {
            $head = (Get-Content $l.FullName -TotalCount 3) -join "`n"
            if ($head -notmatch '#requires -Version 7') { $bad += $l.Name }
        }
        $bad | Should -BeNullOrEmpty
    }

    It 'a 5.1-declared script must not dot-source a 7-declared lib' {
        $violations = @()
        foreach ($s in $repoScripts) {
            $head = (Get-Content $s.FullName -TotalCount 3) -join "`n"
            if ($head -match '#requires -Version 5\.1') {
                $body = Get-Content $s.FullName -Raw
                # find dot-source references to lib files
                if ($body -match 'platform\.ps1|mcp-resilience\.ps1|permission-gate-lib\.ps1|cache\.ps1|score-dims\.ps1|file-manifest\.ps1|engram-validate-lib\.ps1') {
                    $violations += $s.Name
                }
            }
        }
        $violations | Should -BeNullOrEmpty
    }
}
