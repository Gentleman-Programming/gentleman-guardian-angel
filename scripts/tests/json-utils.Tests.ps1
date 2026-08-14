#requires -Version 7
param([switch]$Quiet)

BeforeAll {
    # Import module — same pattern as sync-vmk.Tests.ps1
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib' 'json-utils.ps1')
}

Describe 'Get-DeepClone' {
    Context 'single-element array preservation' {
        It 'Single-element array stays enumerable (not unwrapped to string)' {
            $obj = [pscustomobject]@{ paths = @('.agents/skills') }
            $clone = Get-DeepClone $obj
            # PSSerializer returns ArrayList, not [array] — check enumerable behavior instead
            $clone.paths.Count | Should -Be 1
            $clone.paths[0] | Should -Be '.agents/skills'
        }

        It 'Multi-element array preserved' {
            $obj = [pscustomobject]@{ paths = @('.agents/skills', '.agents/other') }
            $clone = Get-DeepClone $obj
            $clone.paths.Count | Should -Be 2
            $clone.paths[0] | Should -Be '.agents/skills'
            $clone.paths[1] | Should -Be '.agents/other'
        }

        It 'Nested single-element array preserved' {
            $obj = [pscustomobject]@{
                skills = [pscustomobject]@{
                    paths = @('.agents/skills')
                }
            }
            $clone = Get-DeepClone $obj
            $clone.skills.paths.Count | Should -Be 1
            $clone.skills.paths[0] | Should -Be '.agents/skills'
        }

        It 'True deep copy (modifying clone does not affect original)' {
            $obj = [pscustomobject]@{ data = @('x','y','z') }
            $clone = Get-DeepClone $obj
            $clone.data[0] = 'modified'
            $obj.data[0] | Should -Be 'x'
        }
    }

    Context 'null and edge cases' {
        It 'null input returns null' {
            $result = Get-DeepClone $null
            $result | Should -Be $null
        }
    }
}

Describe 'ConvertTo-JsonSafe' {
    Context 'skills.paths array preservation' {
        It 'Single-element paths array stays array in JSON string' {
            $obj = [pscustomobject]@{
                skills = [pscustomobject]@{
                    paths = @('.agents/skills')
                }
            }
            $json = ConvertTo-JsonSafe -InputObject $obj
            # Should match: "paths": [  (array opening — allows multiline)
            $json | Should -Match '"paths"\s*:\s*\['
            $json | Should -Match '"\.agents/skills"\s*]'
            # Should match closing bracket
            $json | Should -Match '\s*\]'
            # Should NOT match: "paths": ".agents/skills"  (string syntax)
            $json | Should -Not -Match '"paths"\s*:\s*"\.agents/skills"'
        }

        It 'Nested object with single-element paths preserved' {
            $obj = [pscustomobject]@{
                foo = 'bar'
                skills = [pscustomobject]@{
                    paths = @('.agents/skills')
                }
            }
            $json = ConvertTo-JsonSafe -InputObject $obj
            $json | Should -Match '"paths"\s*:\s*\['
            $json | Should -Match '"foo"\s*:\s*"bar"'
        }
    }

    Context 'null input' {
        It 'null returns literal null string' {
            $json = ConvertTo-JsonSafe -InputObject $null
            $json | Should -Be 'null'
        }
    }
}

