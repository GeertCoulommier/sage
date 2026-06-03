#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Copy-ExamWithCategories.
.DESCRIPTION
    Verifies that exam definitions are correctly filtered by selected categories.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Copy-ExamWithCategories.ps1')

    function New-FakeExam {
        @{
            Name       = 'Test Exam'
            Version    = '1.0.0'
            Targets    = @{
                Linux = @{
                    Port     = 22
                    UserName = 'student'
                    Platform = 'Linux'
                }
                DC1   = @{
                    Port     = 22
                    UserName = 'administrator'
                    Platform = 'Windows'
                }
            }
            Categories = @(
                @{ Name = 'DNS DC1'; Target = 'DC1'; Collector = 'Dns'; Evaluation = 'Dns'; Variables = @{} }
                @{ Name = 'Docker Linux'; Target = 'Linux'; Collector = 'Docker'; Evaluation = 'Docker'; Variables = @{} }
                @{ Name = 'DHCP DC1'; Target = 'DC1'; Collector = 'Dhcp'; Evaluation = 'Dhcp'; Variables = @{} }
            )
        }
    }
}

Describe 'Copy-ExamWithCategories' -Tag 'Unit' {

    BeforeEach {
        $Exam = New-FakeExam
    }

    Context 'Category filtering' {

        It 'Returns only selected categories' {
            $Result = Copy-ExamWithCategories -Exam $Exam -SelectedCategories @('DNS DC1')

            $Result.Categories.Count | Should -Be 1
            $Result.Categories[0].Name | Should -Be 'DNS DC1'
        }

        It 'Returns multiple selected categories' {
            $Result = Copy-ExamWithCategories -Exam $Exam -SelectedCategories @('DNS DC1', 'Docker Linux')

            $Result.Categories.Count | Should -Be 2
        }

        It 'Returns empty categories array when nothing matches' {
            $Result = Copy-ExamWithCategories -Exam $Exam -SelectedCategories @('NonExistent')

            $Result.Categories.Count | Should -Be 0
        }
    }

    Context 'Target cloning' {

        It 'Does not mutate the original exam targets' {
            $Result = Copy-ExamWithCategories -Exam $Exam -SelectedCategories @('DNS DC1')

            $Result.Targets['DC1'].Port = 99999
            $Exam.Targets['DC1'].Port | Should -Be 22
        }

        It 'Preserves all target properties' {
            $Result = Copy-ExamWithCategories -Exam $Exam -SelectedCategories @('DNS DC1')

            $Result.Targets['DC1'].UserName | Should -Be 'administrator'
            $Result.Targets['DC1'].Platform | Should -Be 'Windows'
        }

        It 'Removes targets with no remaining categories' {
            $Result = Copy-ExamWithCategories -Exam $Exam -SelectedCategories @('DNS DC1')

            $Result.Targets.ContainsKey('DC1')   | Should -BeTrue
            $Result.Targets.ContainsKey('Linux') | Should -BeFalse
        }

        It 'Keeps multiple targets when categories from both are selected' {
            $Result = Copy-ExamWithCategories -Exam $Exam -SelectedCategories @('DNS DC1', 'Docker Linux')

            $Result.Targets.ContainsKey('DC1')   | Should -BeTrue
            $Result.Targets.ContainsKey('Linux') | Should -BeTrue
        }
    }

    Context 'Metadata preservation' {

        It 'Preserves exam name and version' {
            $Result = Copy-ExamWithCategories -Exam $Exam -SelectedCategories @('DNS DC1')

            $Result.Name    | Should -Be 'Test Exam'
            $Result.Version | Should -Be '1.0.0'
        }
    }

    Context 'Parameter validation' {

        It 'Requires Exam parameter' {
            { Copy-ExamWithCategories -SelectedCategories @('DNS DC1') } | Should -Throw
        }

        It 'Requires non-empty SelectedCategories' {
            { Copy-ExamWithCategories -Exam $Exam -SelectedCategories @() } | Should -Throw
        }
    }
}
