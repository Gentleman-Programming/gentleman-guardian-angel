#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Pester 6 tests for cache hash computation from score-auto.ps1
#>
param([switch]$Quiet)
Set-StrictMode -Version Latest

BeforeAll {
    function Get-CacheHash([string]$GitHead, [string]$ScriptsHash, [string]$SkillsHash) {
        $compositeKey = "$GitHead|$ScriptsHash|$SkillsHash"
        return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($compositeKey))
    }
}

Describe 'Cache Hash Computation' {
    It 'produces deterministic hash for same inputs' {
        $h1 = Get-CacheHash 'abc123' 'file1:100|file2:200' 'skill1:300'
        $h2 = Get-CacheHash 'abc123' 'file1:100|file2:200' 'skill1:300'
        $h1 | Should -Be $h2
    }

    It 'produces different hash when git HEAD changes' {
        $h1 = Get-CacheHash 'abc123' 'file1:100' 'skill1:300'
        $h2 = Get-CacheHash 'def456' 'file1:100' 'skill1:300'
        $h1 | Should -Not -Be $h2
    }

    It 'produces different hash when scripts change' {
        $h1 = Get-CacheHash 'abc123' 'file1:100' 'skill1:300'
        $h2 = Get-CacheHash 'abc123' 'file1:200' 'skill1:300'
        $h1 | Should -Not -Be $h2
    }

    It 'produces different hash when skills change' {
        $h1 = Get-CacheHash 'abc123' 'file1:100' 'skill1:300'
        $h2 = Get-CacheHash 'abc123' 'file1:100' 'skill1:400'
        $h1 | Should -Not -Be $h2
    }

    It 'returns valid base64' {
        $hash = Get-CacheHash 'abc' '' ''
        $hash | Should -Match '^[A-Za-z0-9+/=]+$'
    }

    It 'handles empty strings without error' {
        { Get-CacheHash '' '' '' } | Should -Not -Throw
        $hash = Get-CacheHash '' '' ''
        $hash | Should -Match '^[A-Za-z0-9+/=]+$'
    }
}
