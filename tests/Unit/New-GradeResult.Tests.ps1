#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the New-GradeResult factory function.
.DESCRIPTION
    Tests: PSTypeName, required properties, AwardedGrade logic, FinalGrade,
    ManualOverride defaults, Timestamp type, FailGrade default, and parameter
    validation.
.TAGS Unit
#>

BeforeAll {
    # Load Private function directly (module not imported to keep tests fast)
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\New-GradeResult.ps1'
    . $Sut
}

Describe 'New-GradeResult' -Tag 'Unit' {

    Context 'Output type and PSTypeName' {
        It 'Returns exactly one object' {
            $Params = @{
                StudentEmail = 'a@ehb.be'
                StudentName  = 'Test Student'
                StudentData  = @{}
                TargetName   = 'WinSrv1'
                Category     = 'DNS'
                TestName     = 'A record exists'
                Passed       = $true
                PassGrade    = 2
            }
            $Result = New-GradeResult @Params
            $Result | Should -Not -BeNullOrEmpty
            @($Result).Count | Should -Be 1
        }

        It 'Stamps PSTypeName as Sage.TestResult' {
            $Params = @{
                StudentEmail = 'a@ehb.be'
                StudentName  = 'Test Student'
                StudentData  = @{}
                TargetName   = 'WinSrv1'
                Category     = 'DNS'
                TestName     = 'A record exists'
                Passed       = $true
                PassGrade    = 2
            }
            $Result = New-GradeResult @Params
            $Result.PSObject.TypeNames | Should -Contain 'Sage.TestResult'
        }
    }

    Context 'Passed test — AwardedGrade / FinalGrade' {
        BeforeAll {
            $Params = @{
                StudentEmail = 'a@ehb.be'
                StudentName  = 'S'
                StudentData  = @{}
                TargetName   = 'T'
                Category     = 'C'
                TestName     = 'N'
                Passed       = $true
                PassGrade    = 3
                FailGrade    = 1
            }
            $script:Passed = New-GradeResult @Params
        }
        It 'AwardedGrade equals PassGrade when Passed=$true' {
            $script:Passed.AwardedGrade | Should -Be 3
        }
        It 'FinalGrade equals PassGrade when Passed=$true (no override)' {
            $script:Passed.FinalGrade | Should -Be 3
        }
    }

    Context 'Failed test — AwardedGrade / FinalGrade' {
        BeforeAll {
            $Params = @{
                StudentEmail = 'a@ehb.be'
                StudentName  = 'S'
                StudentData  = @{}
                TargetName   = 'T'
                Category     = 'C'
                TestName     = 'N'
                Passed       = $false
                PassGrade    = 3
                FailGrade    = 1
            }
            $script:Failed = New-GradeResult @Params
        }
        It 'AwardedGrade equals FailGrade when Passed=$false' {
            $script:Failed.AwardedGrade | Should -Be 1
        }
        It 'FinalGrade equals FailGrade when Passed=$false (no override)' {
            $script:Failed.FinalGrade | Should -Be 1
        }
    }

    Context 'FailGrade default' {
        It 'FailGrade defaults to 0 when not provided' {
            $Params = @{
                StudentEmail = 'a@ehb.be'
                StudentName  = 'S'
                StudentData  = @{}
                TargetName   = 'T'
                Category     = 'C'
                TestName     = 'N'
                Passed       = $false
                PassGrade    = 2
            }
            $Result = New-GradeResult @Params
            $Result.FailGrade | Should -Be 0
            $Result.AwardedGrade | Should -Be 0
        }
    }

    Context 'Manual override defaults' {
        BeforeAll {
            $Params = @{
                StudentEmail = 'a@ehb.be'
                StudentName  = 'S'
                StudentData  = @{}
                TargetName   = 'T'
                Category     = 'C'
                TestName     = 'N'
                Passed       = $true
                PassGrade    = 1
            }
            $script:r = New-GradeResult @Params
        }
        It 'ManualOverrideGrade is null by default' {
            $script:r.ManualOverrideGrade | Should -BeNullOrEmpty
        }
        It 'ManualOverrideReason is null by default' {
            $script:r.ManualOverrideReason | Should -BeNullOrEmpty
        }
    }

    Context 'Timestamp' {
        It 'Timestamp is a [datetime] and close to now' {
            $Before = [datetime]::Now.AddSeconds(-2)
            $Params = @{
                StudentEmail = 'a@ehb.be'
                StudentName  = 'S'
                StudentData  = @{}
                TargetName   = 'T'
                Category     = 'C'
                TestName     = 'N'
                Passed       = $true
                PassGrade    = 1
            }
            $Result = New-GradeResult @Params
            $After = [datetime]::Now.AddSeconds(2)
            $Result.Timestamp | Should -BeOfType [datetime]
            $Result.Timestamp | Should -BeGreaterThan $Before
            $Result.Timestamp | Should -BeLessThan $After
        }
    }

    Context 'StudentData hashtable is preserved' {
        It 'Passes through all StudentData keys unchanged' {
            $Data = @{
                pointer = '12345'
                subgroep = 'A'
                custom = 'X'
            }
            $Params = @{
                StudentEmail = 'a@ehb.be'
                StudentName  = 'S'
                StudentData  = $Data
                TargetName   = 'T'
                Category     = 'C'
                TestName     = 'N'
                Passed       = $true
                PassGrade    = 1
            }
            $Result = New-GradeResult @Params
            $Result.StudentData.pointer | Should -Be '12345'
            $Result.StudentData.subgroep | Should -Be 'A'
            $Result.StudentData.custom | Should -Be 'X'
        }
    }

    Context 'Parameter validation' {
        It 'Throws when StudentEmail is empty' {
            {
                $Params = @{
                    StudentEmail = ''
                    StudentName  = 'S'
                    StudentData  = @{}
                    TargetName   = 'T'
                    Category     = 'C'
                    TestName     = 'N'
                    Passed       = $true
                    PassGrade    = 1
                }
                New-GradeResult @Params
            } | Should -Throw
        }
        It 'Throws when PassGrade exceeds 100' {
            {
                $Params = @{
                    StudentEmail = 'a@ehb.be'
                    StudentName  = 'S'
                    StudentData  = @{}
                    TargetName   = 'T'
                    Category     = 'C'
                    TestName     = 'N'
                    Passed       = $true
                    PassGrade    = 101
                }
                New-GradeResult @Params
            } | Should -Throw
        }
        It 'Throws when PassGrade is negative' {
            {
                $Params = @{
                    StudentEmail = 'a@ehb.be'
                    StudentName  = 'S'
                    StudentData  = @{}
                    TargetName   = 'T'
                    Category     = 'C'
                    TestName     = 'N'
                    Passed       = $true
                    PassGrade    = -1
                }
                New-GradeResult @Params
            } | Should -Throw
        }
    }
}
