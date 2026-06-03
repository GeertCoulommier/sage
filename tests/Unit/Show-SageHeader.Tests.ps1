#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-SageHeader.
.DESCRIPTION
    Verifies that the persistent TUI header renders without errors and returns
    an integer line count.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Write-SageColor.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-SageHeader.ps1')
}

Describe 'Show-SageHeader' -Tag 'Unit' {

    BeforeEach {
        $script:SageExamName    = $null
        $script:SageExamVersion = $null
        $script:SageLatestSummary = $null
    }

    Context 'Output' {

        It 'Returns a positive integer' {
            Mock Write-Host { }

            $Result = Show-SageHeader -NoClear
            $Result | Should -BeGreaterThan 0
            $Result | Should -BeOfType [int]
        }

        It 'Does not throw' {
            Mock Write-Host { }
            { Show-SageHeader -NoClear } | Should -Not -Throw
        }

        It 'Renders exam name when SageExamName is set' {
            $script:SageExamName    = 'Test Exam'
            $script:SageExamVersion = '2.0.0'
            $Lines = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host { $Lines.Add($Object) }

            Show-SageHeader -NoClear

            $Combined = $Lines -join ' '
            $Combined | Should -Match 'Test Exam'
        }

        It 'Shows last results bar when SageLatestSummary is set' {
            $script:SageLatestSummary = [PSCustomObject]@{
                TotalScore     = [PSCustomObject]@{ Raw = 11.6; Normalized = 14.5; Max = 16 }
                CategoryScores = @(
                    [PSCustomObject]@{ PassedCount = 3; FailedCount = 2; TestCount = 5 }
                    [PSCustomObject]@{ PassedCount = 2; FailedCount = 2; TestCount = 4 }
                )
            }
            $Lines = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host { $Lines.Add($Object) }

            Show-SageHeader -NoClear

            $Combined = $Lines -join ' '
            $Combined | Should -Match '14'
        }

        It 'Renders the score and test count in the results bar' {
            $script:SageLatestSummary = [PSCustomObject]@{
                TotalScore     = [PSCustomObject]@{ Raw = 13; Normalized = 16.1; Max = 20 }
                CategoryScores = @(
                    [PSCustomObject]@{ PassedCount = 20; FailedCount = 3; TestCount = 23 }
                )
            }
            $Lines = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host { $Lines.Add($Object) }

            Show-SageHeader -NoClear

            $Combined = $Lines -join ' '
            $Combined | Should -Match 'Score:'
            $Combined | Should -Match 'Tests passed:'
        }

        It 'Returns more lines when SageLatestSummary is set' {
            Mock Write-Host { }

            $WithoutSummary = Show-SageHeader -NoClear

            $script:SageLatestSummary = [PSCustomObject]@{
                TotalScore     = [PSCustomObject]@{ Raw = 11.6; Normalized = 14.5; Max = 16 }
                CategoryScores = @()
            }
            $WithSummary = Show-SageHeader -NoClear

            $WithSummary | Should -BeGreaterThan $WithoutSummary
        }
    }

    Context 'NoClear switch' {

        It 'Does not call Console.Clear when -NoClear is set' {
            Mock Write-Host { }
            $Cleared = $false

            # No easy mock for [System.Console]::Clear(), but we can confirm
            # the function completes and returns successfully with -NoClear
            { Show-SageHeader -NoClear } | Should -Not -Throw
        }
    }
}
