#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Import-ResultSummary.
.DESCRIPTION
    Verifies loading of saved evaluation results from disk.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Import-ResultSummary.ps1')
}

Describe 'Import-ResultSummary' -Tag 'Unit' {

    BeforeEach {
        $TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
        New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $TestDir) {
            Remove-Item -Path $TestDir -Recurse -Force
        }
    }

    Context 'When grade-summary.json exists in a subdirectory' {

        It 'Loads the summary from a student subdirectory' {
            $StudentDir = Join-Path $TestDir 'Self-Check'
            New-Item -Path $StudentDir -ItemType Directory | Out-Null
            $SummaryData = @{
                TotalNormalizedScore = 14.5
                MaxNormalizedScore   = 20
                ExamName             = 'Test'
            }
            $SummaryData | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $StudentDir 'grade-summary.json') -Encoding utf8

            $Result = Import-ResultSummary -OutputPath $TestDir

            $Result | Should -Not -BeNullOrEmpty
            $Result.TotalNormalizedScore | Should -Be 14.5
        }
    }

    Context 'When results.json exists at top level' {

        It 'Loads from results.json' {
            $SummaryData = @{
                TotalNormalizedScore = 10
                MaxNormalizedScore   = 20
            }
            $SummaryData | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $TestDir 'results.json') -Encoding utf8

            $Result = Import-ResultSummary -OutputPath $TestDir

            $Result | Should -Not -BeNullOrEmpty
            $Result.TotalNormalizedScore | Should -Be 10
        }
    }

    Context 'When no result files exist' {

        It 'Returns null for empty directory' {
            $Result = Import-ResultSummary -OutputPath $TestDir
            $Result | Should -BeNullOrEmpty
        }

        It 'Returns null for non-existent path' {
            $Result = Import-ResultSummary -OutputPath (Join-Path $TestDir 'nonexistent')
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It 'Requires OutputPath' {
            { Import-ResultSummary } | Should -Throw
        }
    }
}
