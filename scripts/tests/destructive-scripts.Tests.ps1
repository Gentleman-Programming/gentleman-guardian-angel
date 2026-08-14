#requires -Version 7

BeforeAll {
    $scriptsRoot = Resolve-Path "$PSScriptRoot/.."
}

Describe "Destructive Script Safety — <_.Name>" -ForEach (
    (Get-ChildItem -Path "$PSScriptRoot/.." -Filter "*.ps1" -Recurse) |
    Where-Object {
        $_.DirectoryName -notlike "*tests*" -and
        $_.FullName -notmatch '\\scripts\\lib[\\/]' -and
        $_.Name -ne "destructive-scripts.Tests.ps1" -and
        $_.Name -notlike "smoke-*" -and
        ($_.Name -match '(close|rollback|restore|backup|push|clean|force|forge|wipe|demote|store)' -or
         (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'Remove-Item|git push|Clear-Content')
    }
) {

    BeforeAll {
        $scriptContent = Get-Content $_.FullName -Raw -ErrorAction Stop
    }

    Context "Parameter Validation" {

        It "should have a param block" {
            $scriptContent | Should -Match 'param\s*\('
        }

        It "should have named parameters (not empty param())" {
            $scriptContent | Should -Match 'param\s*\([^)]+\S+[^)]*\)'
        }
    }

    Context "Safety Guards" {

        It "should have WhatIf/Confirm, Force, or DryRun support" {
            $hasShouldProcess = $scriptContent -match 'SupportsShouldProcessing'
            $hasWhatIf = $scriptContent -match '\$WhatIfPreference|\-WhatIf'
            $hasForceParam = $scriptContent -match 'param\s*\([^)]*\[switch\]\s*\$Force[^)]*\)'
            $hasForceVar = $scriptContent -match '\$Force\b'
            $hasForce = $hasForceParam -or $hasForceVar
            $hasDryRun = $scriptContent -match 'DryRun|dry.run'

            ($hasShouldProcess -or $hasWhatIf -or $hasForce -or $hasDryRun) |
                Should -BeTrue -Because "destructive scripts need at least one safety mechanism"
        }

        It "should have SupportsShouldProcessing OR equivalent param-based safety (flag if missing)" {
            $hasShouldProcess = $scriptContent -match 'SupportsShouldProcessing'
            $hasForceOrDryRun = $scriptContent -match 'param\s*\(' -and
                $scriptContent -match '\[switch\]\s*\$(Force|DryRun|WhatIf|Confirm)'

            if (-not $hasShouldProcess) {
                Write-Warning "INFO: $($_.Name) lacks SupportsShouldProcessing (advanced function binding)"
            }
            ($hasShouldProcess -or $hasForceOrDryRun) |
                Should -BeTrue -Because "scripts need SupportsShouldProcessing or explicit -Force/-DryRun/-WhatIf params"
        }

        It "should have a -Force parameter for explicit override" {
            $scriptContent | Should -Match 'param\s*\([\s\S]*?\$Force[\s\S]*?\)'
        }

        It "should have -Force as a script parameter (not just cmdlet flag)" {
            $scriptContent | Should -Match 'param\s*\([\s\S]*?\$Force[\s\S]*?\)'
        }

        It "should gate destructive Remove-Item behind a condition" {
            $lines = @($scriptContent -split "`n")
            $removeLines = @($lines | Where-Object { $_ -match 'Remove-Item' })
            $ifLines = @($lines | Where-Object { $_ -match '^\s*(if|switch|\$Force|\$WhatIf|\$DryRun)' })

            if ($removeLines.Count -gt 0) {
                $ifLines.Count | Should -BeGreaterThan 0 -Because "Remove-Item calls should be gated by a condition"
            }
        }
    }

    Context "Dry-Run Mode" {

        It "should support WhatIf or DryRun or ShouldProcess or custom DryRun param" {
            $hasDryRun = $scriptContent -match 'DryRun|dry.run|WhatIfPreference|\-WhatIf'
            $hasShouldProcess = $scriptContent -match 'SupportsShouldProcessing'
            $hasDryRunSwitch = $scriptContent -match '\[switch\]\s*\$DryRun'

            ($hasDryRun -or $hasShouldProcess -or $hasDryRunSwitch) | Should -BeTrue
        }

        It "should NOT perform Remove-Item unconditionally at script top level" {
            $scriptContent | Should -Not -Match '(?m)^\s*Remove-Item\s+.*\s+-Recurse\s+-Force\s*$'
        }
    }

    Context "Error Handling" {

        It "should not use -ErrorAction SilentlyContinue on destructive ops outside cleanup" {
            $lines = $scriptContent -split "`n"
            $destructiveSilentLines = @()
            foreach ($line in $lines) {
                if ($line -match 'Remove-Item.*-ErrorAction\s+SilentlyContinue' -and
                    $line -notmatch '(cleanup|temp|tmp|AfterAll|finally|Remove-Item.*\.tmp)') {
                    $destructiveSilentLines += $line.Trim()
                }
            }
            if ($destructiveSilentLines.Count -gt 0) {
                Write-Warning "INFO: $($_.Name) has silent error suppression on destructive ops: $($destructiveSilentLines -join '; ')"
            }
            $destructiveSilentLines.Count | Should -Be 0 -Because "destructive Remove-Item should not silently suppress errors"
        }

        It "should have try/catch or -ErrorAction Stop or throw" {
            $hasTryCatch = $scriptContent -match 'try\s*\{'
            $hasErrorStop = $scriptContent -match '-ErrorAction\s+Stop'
            $hasThrow = $scriptContent -match 'throw\s'

            ($hasTryCatch -or $hasErrorStop -or $hasThrow) | Should -BeTrue
        }

        It "should have meaningful output (Write-Output/Host/Warning)" {
            $hasOutput = $scriptContent -match 'Write-Output|Write-Host|Write-Information|Write-Verbose|Write-Warning'
            $hasOutput | Should -BeTrue
        }
    }
}

Describe "Destructive Script Cross-Checks" {

    BeforeAll {
        $allNonTest = Get-ChildItem -Path "$PSScriptRoot/.." -Filter "*.ps1" -Recurse |
            Where-Object {
                $_.DirectoryName -notlike "*tests*" -and
                $_.FullName -notmatch '\\scripts\\lib[\\/]' -and
                $_.Name -ne "destructive-scripts.Tests.ps1"
            }

        $scriptsUsingRemoveRecurse = $allNonTest | Where-Object {
            (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'Remove-Item.*-Recurse'
        }

        $scriptsUsingGitPush = $allNonTest | Where-Object {
            (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'git push'
        }

        $scriptsUsingRemoveItem = $allNonTest | Where-Object {
            (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'Remove-Item'
        }

        $scriptsUnsafeRemove = @()
        foreach ($s in $scriptsUsingRemoveItem) {
            $c = Get-Content $s.FullName -Raw -ErrorAction SilentlyContinue
            $hasForceParam = $c -match 'param\s*\([\s\S]*?\$Force[\s\S]*?\)'
            if ($c -notmatch 'SupportsShouldProcessing|DryRun|WhatIf|\-Confirm' -and -not $hasForceParam) {
                $scriptsUnsafeRemove += $s
            }
        }

        $scriptsUnsafePush = @()
        foreach ($s in $scriptsUsingGitPush) {
            $c = Get-Content $s.FullName -Raw -ErrorAction SilentlyContinue
            $hasForceParam = $c -match 'param\s*\([\s\S]*?\$Force[\s\S]*?\)'
            if ($c -notmatch 'SupportsShouldProcessing|DryRun|WhatIf|\-Confirm' -and -not $hasForceParam) {
                $scriptsUnsafePush += $s
            }
        }
    }

    It "should have at least one script with Remove-Item -Recurse to verify filter works" {
        $scriptsUsingRemoveRecurse.Count | Should -BeGreaterThan 0
    }

    It "should have at least one script with git push to verify filter works" {
        $scriptsUsingGitPush.Count | Should -BeGreaterThan 0
    }

    It "all scripts with Remove-Item should have safety guards" {
        if ($scriptsUnsafeRemove.Count -gt 0) {
            $names = ($scriptsUnsafeRemove | ForEach-Object { $_.Name }) -join ", "
            $names | Should -BeNullOrEmpty -Because "unsafe scripts found: $names"
        }
    }

    It "all scripts with git push should have safety guards" {
        if ($scriptsUnsafePush.Count -gt 0) {
            $names = ($scriptsUnsafePush | ForEach-Object { $_.Name }) -join ", "
            $names | Should -BeNullOrEmpty -Because "unsafe scripts found: $names"
        }
    }
}
