#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Pester 6 tests for Add-Dimension from score-auto.ps1
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    $__sc = Get-Content -Path "$PSScriptRoot\..\score-auto.ps1" -Raw
    if ($__sc -match '(function Add-Dimension[\s\S]*?\n\})') {
        . ([ScriptBlock]::Create($Matches[1]))
    }
}

Describe 'Add-Dimension' {
    BeforeEach { $script:dimensions = @{} }

    It 'stores a dimension with name, score, evidence, and rationale' {
        Add-Dimension 'test' 7.5 @{ files = @('a.ps1'); score = 7.5 } 'Test dimension'
        $script:dimensions['test'].s | Should -Be 7.5
        $script:dimensions['test'].e.files[0] | Should -BeExactly 'a.ps1'
        $script:dimensions['test'].r | Should -BeExactly 'Test dimension'
    }

    It 'overwrites existing dimension with same name' {
        Add-Dimension 'dup' 5.0 @{} 'first'
        Add-Dimension 'dup' 8.0 @{ note = 'updated' } 'second'
        $script:dimensions['dup'].s | Should -Be 8.0
        $script:dimensions['dup'].r | Should -BeExactly 'second'
    }

    It 'accepts empty evidence hashtable' {
        Add-Dimension 'empty' 10.0 @{} 'Perfect'
        $script:dimensions['empty'].s | Should -Be 10.0
        $script:dimensions['empty'].e.Keys.Count | Should -Be 0
    }

    It 'accepts score of 0' {
        Add-Dimension 'zero' 0.0 @{} 'Minimum'
        $script:dimensions['zero'].s | Should -Be 0.0
    }

    It 'accepts negative score' {
        Add-Dimension 'neg' -1.5 @{} 'Negative'
        $script:dimensions['neg'].s | Should -Be -1.5
    }

    It 'stores multiple dimensions independently' {
        Add-Dimension 'dim1' 1.0 @{} 'one'
        Add-Dimension 'dim2' 2.0 @{} 'two'
        Add-Dimension 'dim3' 3.0 @{} 'three'
        $script:dimensions.Keys.Count | Should -Be 3
        $script:dimensions['dim1'].s | Should -Be 1.0
        $script:dimensions['dim2'].s | Should -Be 2.0
        $script:dimensions['dim3'].s | Should -Be 3.0
    }
}
