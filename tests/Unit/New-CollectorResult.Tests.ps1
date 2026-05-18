#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the New-CollectorResult factory function.
.DESCRIPTION
    Tests: PSTypeName stamping, all properties populated, defaults for
    optional parameters, Available true/false semantics, and Duration
    handling.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\New-CollectorResult.ps1'
    . $Sut
}

Describe 'New-CollectorResult' -Tag 'Unit' {

    Context 'Output type and PSTypeName' {
        BeforeAll {
            $script:Result = New-CollectorResult -CollectorName 'Dns' -Available $true
        }

        It 'Returns exactly one object' {
            @($script:Result).Count | Should -Be 1
        }

        It 'Has PSTypeName Sage.CollectorResult' {
            $script:Result.PSObject.TypeNames | Should -Contain 'Sage.CollectorResult'
        }
    }

    Context 'Available collector—all properties' {
        BeforeAll {
            $script:Result = New-CollectorResult -CollectorName 'Docker' -Available $true -Data @{ Containers = @('web', 'db') } -Errors @('minor glitch') -Duration ([timespan]::FromSeconds(2.5))
        }

        It 'CollectorName matches input' {
            $script:Result.CollectorName | Should -Be 'Docker'
        }

        It 'Available is $true' {
            $script:Result.Available | Should -BeTrue
        }

        It 'Data contains the supplied hashtable' {
            $script:Result.Data.Containers | Should -Contain 'web'
            $script:Result.Data.Containers | Should -Contain 'db'
        }

        It 'Errors array is populated' {
            $script:Result.Errors | Should -Contain 'minor glitch'
        }

        It 'Duration reflects the supplied timespan' {
            $script:Result.Duration.TotalSeconds | Should -Be 2.5
        }
    }

    Context 'Unavailable collector with Reason' {
        BeforeAll {
            $script:Result = New-CollectorResult -CollectorName 'Iis' -Available $false -Reason 'IIS not installed'
        }

        It 'Available is $false' {
            $script:Result.Available | Should -BeFalse
        }

        It 'Reason explains the unavailability' {
            $script:Result.Reason | Should -Be 'IIS not installed'
        }
    }

    Context 'Default parameter values' {
        BeforeAll {
            $script:Result = New-CollectorResult -CollectorName 'Dhcp' -Available $true
        }

        It 'Data defaults to empty hashtable' {
            $script:Result.Data | Should -BeOfType [hashtable]
            $script:Result.Data.Count | Should -Be 0
        }

        It 'Errors defaults to empty array' {
            @($script:Result.Errors).Count | Should -Be 0
        }

        It 'Duration defaults to zero' {
            $script:Result.Duration | Should -Be ([timespan]::Zero)
        }

        It 'Reason defaults to $null' {
            $script:Result.Reason | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {
        It 'Throws when CollectorName is empty' {
            { New-CollectorResult -CollectorName '' -Available $true } | Should -Throw
        }

        It 'Throws when CollectorName is null' {
            { New-CollectorResult -CollectorName $null -Available $true } | Should -Throw
        }
    }
}
