#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-ResultsSummary.
.DESCRIPTION
    Verifies results summary display logic.
.TAGS Unit
#>

$ConsoleWidth = try { [System.Console]::WindowWidth } catch { 0 }
$ConsoleHeight = try { [System.Console]::WindowHeight } catch { 0 }
$script:SkipInteractiveUiTests = $IsWindows -and (
    [System.Console]::IsInputRedirected -or
    [System.Console]::IsOutputRedirected -or
    $ConsoleWidth -le 0 -or
    $ConsoleHeight -le 0
)

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Write-SageColor.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-SageHeader.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-MainMenu.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-ResultsSummary.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-CategoryDetail.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-TestDetail.ps1')

    Mock Show-SageHeader { return 14 } -ModuleName ''

    function New-BKey     { [PSCustomObject]@{ Key = 'B';      KeyChar = [char]66  } }
    function New-QKey     { [PSCustomObject]@{ Key = 'Q';      KeyChar = [char]81  } }
    function New-BackspaceKey { [PSCustomObject]@{ Key = 'Backspace'; KeyChar = [char]8 } }

    function New-FakeGradeSummary {
        [PSCustomObject]@{
            TotalScore    = [PSCustomObject]@{ Normalized = 14.5; Max = 16.0; Raw = 11.6 }
            GradedAt      = '2026-04-18T14:30:22'
            TestResults          = @(
                [PSCustomObject]@{
                    Category      = 'DNS DC1'
                    TestName      = 'Zone exists'
                    Passed        = $true
                    FinalGrade    = 2
                    PassGrade     = 2
                    TargetName    = 'DC1'
                    ActualValue   = $null
                    ExpectedValue = $null
                    ErrorMessage  = $null
                }
                [PSCustomObject]@{
                    Category      = 'DNS DC1'
                    TestName      = 'PTR record'
                    Passed        = $false
                    FinalGrade    = 0
                    PassGrade     = 1
                    TargetName    = 'DC1'
                    ActualValue   = 'dc1.sage.local.'
                    ExpectedValue = 'dc1.sage.local'
                    ErrorMessage  = 'Trailing dot mismatch'
                }
            )
            CategoryScores       = @(
                [PSCustomObject]@{
                    Category        = 'DNS DC1'
                    RawScore        = 2
                    NormalizedScore = 14.5
                    MaxScore        = 3
                    PassedCount     = 1
                    FailedCount     = 1
                }
            )
        }
    }

}

Describe 'Show-ResultsSummary' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    Context 'Display and navigation' {

        It 'Displays overall score and exits on B' {
            Mock Invoke-ReadKey { New-BKey }
            Mock Write-Host { }

            $Result = Show-ResultsSummary -Summary (New-FakeGradeSummary) -UseSpectre $false
            $Result | Should -Be 'Back'
        }

        It 'Returns Back on Backspace key' {
            Mock Invoke-ReadKey { New-BackspaceKey }
            Mock Write-Host { }

            $Result = Show-ResultsSummary -Summary (New-FakeGradeSummary) -UseSpectre $false
            $Result | Should -Be 'Back'
        }

        It 'Returns QuitTui on Q input' {
            Mock Invoke-ReadKey { New-QKey }
            Mock Write-Host { }

            $Result = Show-ResultsSummary -Summary (New-FakeGradeSummary) -UseSpectre $false
            $Result | Should -Be 'QuitTui'
        }
    }

    Context 'Score calculation' {

        It 'Calculates percentage correctly' {
            Mock Invoke-ReadKey { New-BKey }
            $PercentageCalls = @()
            Mock Write-Host {
                if ($Object -match '\d+(\.\d+)?%') {
                    $script:PercentageCalls += $Object
                }
            }

            Show-ResultsSummary -Summary (New-FakeGradeSummary) -UseSpectre $false

            Should -Invoke Write-Host -ParameterFilter { $Object -match '72\.5%' }
        }
    }

    Context 'Error/unavailable category display' {

        It 'Shows error placeholder rows without throwing' {
            Mock Invoke-ReadKey { New-BKey }
            Mock Write-Host { }

            $SummaryWithError = New-FakeGradeSummary
            $SummaryWithError.CategoryScores = @(
                $SummaryWithError.CategoryScores[0],
                [PSCustomObject]@{
                    Category        = 'GPO DC1'
                    NormalizedScore = 0.0
                    MaxScore        = 0.0
                    PassedCount     = 0
                    FailedCount     = 0
                    Status          = 'Error'
                }
            )

            { Show-ResultsSummary -Summary $SummaryWithError -UseSpectre $false } | Should -Not -Throw
        }
    }
}
