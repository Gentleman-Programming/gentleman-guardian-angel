#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Pester 6 tests for dimension aggregation from score-auto.ps1
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    $__sc = Get-Content -Path "$PSScriptRoot\..\score-auto.ps1" -Raw
    if ($__sc -match '(function Add-Dimension[\s\S]*?\n\})') {
        . ([ScriptBlock]::Create($Matches[1]))
    }
}

Describe 'Dimension Aggregation' {
    BeforeEach { $script:dimensions = @{} }

    It 'computes average of multiple dimensions' {
        Add-Dimension 'A' 10.0 @{} 'max'
        Add-Dimension 'B' 0.0 @{} 'min'
        Add-Dimension 'C' 5.0 @{} 'mid'

        $avg = ($script:dimensions.Values.s | Measure-Object -Average).Average
        $avg | Should -Be 5.0
    }

    It 'computes average of single dimension' {
        Add-Dimension 'X' 8.5 @{} 'single'

        $avg = ($script:dimensions.Values.s | Measure-Object -Average).Average
        $avg | Should -Be 8.5
    }
}
