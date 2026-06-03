#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Set-DomainNameInExam and Resolve-PlaceholderInValue.
.DESCRIPTION
    Verifies domain name placeholder replacement in exam definitions.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Set-DomainNameInExam.ps1')
}

Describe 'Set-DomainNameInExam' -Tag 'Unit' {

    Context 'Placeholder replacement' {

        It 'Replaces <domainname> in string values' {
            $Exam = @{
                Categories = @(
                    @{
                        Name      = 'DNS DC1'
                        Variables = @{
                            ForwardZones = @(
                                @{ ZoneName = '<domainname>.be'; PassGrade = 2 }
                            )
                        }
                    }
                )
            }

            $Result = Set-DomainNameInExam -Exam $Exam -DomainName 'geert'

            $Result.Categories[0].Variables.ForwardZones[0].ZoneName | Should -Be 'geert.be'
        }

        It 'Replaces multiple occurrences in different properties' {
            $Exam = @{
                Categories = @(
                    @{
                        Name      = 'DNS'
                        Variables = @{
                            ARecords = @(
                                @{ Name = 'dc1'; IP = '1.2.3.4'; Zone = '<domainname>.be' }
                                @{ Name = 'dc2'; IP = '1.2.3.5'; Zone = '<domainname>.local' }
                            )
                        }
                    }
                )
            }

            $Result = Set-DomainNameInExam -Exam $Exam -DomainName 'test'

            $Result.Categories[0].Variables.ARecords[0].Zone | Should -Be 'test.be'
            $Result.Categories[0].Variables.ARecords[1].Zone | Should -Be 'test.local'
        }

        It 'Handles nested hashtables' {
            $Exam = @{
                Categories = @(
                    @{
                        Name      = 'AD'
                        Variables = @{
                            DomainTests = @(
                                @{ DomainName = '<domainname>.local' }
                            )
                        }
                    }
                )
            }

            $Result = Set-DomainNameInExam -Exam $Exam -DomainName 'mydomain'

            $Result.Categories[0].Variables.DomainTests[0].DomainName | Should -Be 'mydomain.local'
        }

        It 'Leaves non-placeholder strings unchanged' {
            $Exam = @{
                Categories = @(
                    @{
                        Name      = 'Test'
                        Variables = @{
                            HostnameTests = @(
                                @{ ExpectedHostname = 'DC1'; PassGrade = 2 }
                            )
                        }
                    }
                )
            }

            $Result = Set-DomainNameInExam -Exam $Exam -DomainName 'geert'

            $Result.Categories[0].Variables.HostnameTests[0].ExpectedHostname | Should -Be 'DC1'
            $Result.Categories[0].Variables.HostnameTests[0].PassGrade | Should -Be 2
        }

        It 'Handles categories without Variables' {
            $Exam = @{
                Categories = @(
                    @{ Name = 'NoVars' }
                )
            }

            { Set-DomainNameInExam -Exam $Exam -DomainName 'geert' } | Should -Not -Throw
        }
    }

    Context 'Parameter validation' {

        It 'Requires Exam parameter' {
            { Set-DomainNameInExam -DomainName 'geert' } | Should -Throw
        }

        It 'Requires non-empty DomainName' {
            $Exam = @{ Categories = @() }
            { Set-DomainNameInExam -Exam $Exam -DomainName '' } | Should -Throw
        }
    }
}

Describe 'Resolve-PlaceholderInValue' -Tag 'Unit' {

    Context 'String replacement' {

        It 'Replaces placeholder in a simple string' {
            $Result = Resolve-PlaceholderInValue -Value 'hello <domainname> world' -Placeholder '<domainname>' -Replacement 'test'
            $Result | Should -Be 'hello test world'
        }

        It 'Returns unchanged string when no placeholder present' {
            $Result = Resolve-PlaceholderInValue -Value 'no placeholder' -Placeholder '<domainname>' -Replacement 'test'
            $Result | Should -Be 'no placeholder'
        }
    }

    Context 'Hashtable replacement' {

        It 'Recursively replaces in hashtable values' {
            $Ht = @{ Key = '<domainname>.local' }
            $Result = Resolve-PlaceholderInValue -Value $Ht -Placeholder '<domainname>' -Replacement 'test'
            $Result.Key | Should -Be 'test.local'
        }
    }

    Context 'Array replacement' {

        It 'Recursively replaces in array elements' {
            $Arr = @('<domainname>.be', '<domainname>.local')
            $Result = Resolve-PlaceholderInValue -Value $Arr -Placeholder '<domainname>' -Replacement 'geert'
            $Result[0] | Should -Be 'geert.be'
            $Result[1] | Should -Be 'geert.local'
        }
    }

    Context 'Non-string passthrough' {

        It 'Returns integers unchanged' {
            $Result = Resolve-PlaceholderInValue -Value 42 -Placeholder '<domainname>' -Replacement 'test'
            $Result | Should -Be 42
        }

        It 'Returns booleans unchanged' {
            $Result = Resolve-PlaceholderInValue -Value $true -Placeholder '<domainname>' -Replacement 'test'
            $Result | Should -BeTrue
        }
    }
}
