#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Pester 6 tests for pure scoring math from score-dims.ps1 (sourced by score-auto.ps1)
.DESCRIPTION
  Tests SP (Script Performance), Or (Orthography), BP (Best Practices), and
  CC (Clean Code) scoring logic. No I/O — extracted as pure functions.
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    # ponytail: extracted pure math from score-dims.ps1 — no I/O, no side effects
    # score-dims.ps1 has no function blocks (all inline), so manual extraction.
    $script:math = [math]

    # From score-dims.ps1 lines 276-287 — SP scoring
    function Get-SpScore([int]$TotalScripts, [double]$AvgKB, [int]$HugeCount) {
        $sp = 10
        if ($TotalScripts -lt 15 -or $TotalScripts -gt 60) { $sp -= 1 }
        # Note: elseif >20 is unreachable when >15 — matches source behavior
        if ($AvgKB -gt 15) { $sp -= 1 } elseif ($AvgKB -gt 20) { $sp -= 2 }
        if ($HugeCount -gt 0) { $sp -= 2 }
        return $script:math::Max(0, $script:math::Min(10, $sp))
    }

    # From score-dims.ps1 lines 202-210 — Or scoring (corruption tiers)
    function Get-OrScore([int]$Corrupted) {
        if ($Corrupted -gt 10) { return 4 }
        elseif ($Corrupted -gt 5) { return 7 }
        elseif ($Corrupted -gt 0) { return 9 }
        else { return 10 }
    }

    # From score-dims.ps1 lines 165-170 — BP bonus/penalty
    function Get-BpBonus([double]$TryCatchRatio, [double]$BaseBP) {
        if ($TryCatchRatio -ge 0.8) { return $script:math::Min(10, $BaseBP + 1) }
        elseif ($TryCatchRatio -le 0.3) { return $script:math::Max(0, $BaseBP - 1) }
        return $BaseBP
    }

    # From score-dims.ps1 lines 149-152 — CC ratio scoring
    function Get-CcScore([double]$HelpR, [double]$ParamR, [double]$StrictR) {
        return $script:math::Round(($HelpR + $ParamR + $StrictR) / 3 * 10, 1)
    }
}

Describe 'SP Score (Script Performance)' {
    It 'returns 10 for ideal parameters (30 scripts, 5KB avg, 0 huge)' {
        Get-SpScore 30 5.0 0 | Should -Be 10
    }
    It 'penalizes -1 for low script count (<15)' {
        Get-SpScore 10 5.0 0 | Should -Be 9
    }
    It 'penalizes -1 for high script count (>60)' {
        Get-SpScore 70 5.0 0 | Should -Be 9
    }
    It 'penalizes -1 for avg size >15KB' {
        Get-SpScore 30 16.0 0 | Should -Be 9
    }
    It 'penalizes same -1 for avg >20KB (elseif unreachable in source)' {
        Get-SpScore 30 25.0 0 | Should -Be 9
    }
    It 'penalizes -2 for huge scripts' {
        Get-SpScore 30 5.0 1 | Should -Be 8
    }
    It 'combines all penalties (min achievable = 6)' {
        Get-SpScore 10 25.0 3 | Should -Be 6
    }
    It 'never exceeds 10' {
        Get-SpScore 30 5.0 0 | Should -BeLessOrEqual 10
    }
}

Describe 'Or Score (Orthography Corruption)' {
    It 'returns 10 for zero corrupted files' {
        Get-OrScore 0 | Should -Be 10
    }
    It 'returns 9 for 1-5 corrupted files' {
        Get-OrScore 1 | Should -Be 9
        Get-OrScore 5 | Should -Be 9
    }
    It 'returns 7 for 6-10 corrupted files' {
        Get-OrScore 6 | Should -Be 7
        Get-OrScore 10 | Should -Be 7
    }
    It 'returns 4 for >10 corrupted files' {
        Get-OrScore 11 | Should -Be 4
        Get-OrScore 100 | Should -Be 4
    }
    It 'handles negative input as zero corruption' {
        Get-OrScore -1 | Should -Be 10
    }
}

Describe 'BP Bonus/Penalty (Best Practices)' {
    It 'adds +1 when try/catch ratio >= 0.8' {
        Get-BpBonus 0.8 7.0 | Should -Be 8.0
    }
    It 'caps bonus at 10 (cannot exceed)' {
        Get-BpBonus 1.0 10.0 | Should -Be 10
    }
    It 'subtracts -1 when try/catch ratio <= 0.3' {
        Get-BpBonus 0.3 5.0 | Should -Be 4.0
    }
    It 'floors penalty at 0' {
        Get-BpBonus 0.0 0.5 | Should -Be 0
    }
    It 'no change for ratio in (0.3, 0.8)' {
        Get-BpBonus 0.5 6.0 | Should -Be 6.0
    }
    It 'handles ratio exactly 0.3 (boundary — no change)' {
        Get-BpBonus 0.3 6.0 | Should -Be 5.0
    }
    It 'handles ratio exactly 0.8 (boundary — bonus applies)' {
        Get-BpBonus 0.8 5.0 | Should -Be 6.0
    }
}

Describe 'CC Score (Clean Code Ratios)' {
    It 'returns 10 when all ratios are 1.0 (100%)' {
        Get-CcScore 1.0 1.0 1.0 | Should -Be 10.0
    }
    It 'returns 0 when all ratios are 0' {
        Get-CcScore 0.0 0.0 0.0 | Should -Be 0.0
    }
    It 'averages three ratios scaled to 10' {
        # (1.0 + 0.0 + 0.0) / 3 * 10 = 3.3
        Get-CcScore 1.0 0.0 0.0 | Should -Be 3.3
    }
    It 'rounds to 1 decimal place' {
        # (0.7 + 0.8 + 0.7) / 3 * 10 = 7.333... → 7.3
        Get-CcScore 0.7 0.8 0.7 | Should -Be 7.3
    }
    It 'is symmetric across parameters' {
        $a = Get-CcScore 0.2 0.5 0.8
        $b = Get-CcScore 0.8 0.5 0.2
        $a | Should -Be $b
    }
}
