#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the ConvertTo-NormalizedGrade function.
.DESCRIPTION
    Tests: basic normalisation maths, rounding to 2 decimals, full-score
    and zero-score boundaries, custom Scale parameter, and parameter
    validation for out-of-range values.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\ConvertTo-NormalizedGrade.ps1'
    . $Sut
}

Describe 'ConvertTo-NormalizedGrade' -Tag 'Unit' {

    Context 'Basic normalisation' {
        It 'Returns 16.0 for RawScore 12 / MaxScore 15 on scale 20' {
            ConvertTo-NormalizedGrade -RawScore 12 -MaxScore 15 | Should -Be 16.0
        }

        It 'Returns 8.57 for RawScore 6 / MaxScore 14 on scale 20' {
            ConvertTo-NormalizedGrade -RawScore 6 -MaxScore 14 | Should -Be 8.57
        }

        It 'Rounds to exactly 2 decimal places' {
            # 7 / 13 * 20 = 10.769230… → 10.77
            ConvertTo-NormalizedGrade -RawScore 7 -MaxScore 13 | Should -Be 10.77
        }
    }

    Context 'Boundary values' {
        It 'Returns 20.0 for a perfect score' {
            ConvertTo-NormalizedGrade -RawScore 15 -MaxScore 15 | Should -Be 20.0
        }

        It 'Returns 0.0 for a zero score' {
            ConvertTo-NormalizedGrade -RawScore 0 -MaxScore 15 | Should -Be 0.0
        }

        It 'Handles MaxScore of 1 correctly' {
            ConvertTo-NormalizedGrade -RawScore 1 -MaxScore 1 | Should -Be 20.0
        }
    }

    Context 'Custom Scale parameter' {
        It 'Normalises to a scale of 100' {
            ConvertTo-NormalizedGrade -RawScore 3 -MaxScore 4 -Scale 100 | Should -Be 75.0
        }

        It 'Normalises to a scale of 10' {
            ConvertTo-NormalizedGrade -RawScore 5 -MaxScore 8 -Scale 10 | Should -Be 6.25
        }
    }

    Context 'Output type' {
        It 'Returns a [double]' {
            $Result = ConvertTo-NormalizedGrade -RawScore 10 -MaxScore 20
            $Result | Should -BeOfType [double]
        }
    }

    Context 'Parameter validation' {
        It 'Throws when RawScore is negative' {
            { ConvertTo-NormalizedGrade -RawScore -1 -MaxScore 10 } | Should -Throw
        }

        It 'Throws when MaxScore is 0' {
            { ConvertTo-NormalizedGrade -RawScore 0 -MaxScore 0 } | Should -Throw
        }

        It 'Throws when MaxScore is negative' {
            { ConvertTo-NormalizedGrade -RawScore 0 -MaxScore -5 } | Should -Throw
        }

        It 'Throws when Scale is 0' {
            { ConvertTo-NormalizedGrade -RawScore 5 -MaxScore 10 -Scale 0 } | Should -Throw
        }
    }
}
