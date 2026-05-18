#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-CategoryDetail.
.DESCRIPTION
    Verifies category detail display logic and key navigation.
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
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-CategoryDetail.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-TestDetail.ps1')

    Mock Show-SageHeader { return 14 } -ModuleName ''

    function New-BKey     { [PSCustomObject]@{ Key = 'B';      KeyChar = [char]66  } }
    function New-QKey     { [PSCustomObject]@{ Key = 'Q';      KeyChar = [char]81  } }
    function New-BackspaceKey { [PSCustomObject]@{ Key = 'Backspace'; KeyChar = [char]8 }
    }
    function New-EnterKey { [PSCustomObject]@{ Key = 'Enter';  KeyChar = [char]13  } }

    function New-FakeCategoryGrade {
        [PSCustomObject]@{
            Category        = 'DNS DC1'
            RawScore        = 2
            NormalizedScore = 13.33
            MaxScore        = 3
            PassedCount     = 1
            FailedCount     = 1
        }
    }

    function New-FakeSummary {
        [PSCustomObject]@{
            TotalScore  = [PSCustomObject]@{ Normalized = 13.33; Max = 16.0; Raw = 2.0 }
            GradedAt    = '2026-04-18T14:30:22'
            TestResults = @(
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
        }
    }

}

Describe 'Show-CategoryDetail' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    BeforeEach { $script:SageQuit = $false }

    Context 'Navigation' {

        It 'Exits without throw when B key is pressed' {
            Mock Invoke-ReadKey { New-BKey }
            Mock Write-Host { }

            { Show-CategoryDetail -CategoryGrade (New-FakeCategoryGrade) -Summary (New-FakeSummary) -UseSpectre $false } |
                Should -Not -Throw
        }

        It 'Sets SageQuit on Q key' {
            Mock Invoke-ReadKey { New-QKey }
            Mock Write-Host { }

            Show-CategoryDetail -CategoryGrade (New-FakeCategoryGrade) -Summary (New-FakeSummary) -UseSpectre $false

            $script:SageQuit | Should -BeTrue
        }

        It 'Exits on Backspace key' {
            Mock Invoke-ReadKey { New-BackspaceKey }
            Mock Write-Host { }

            { Show-CategoryDetail -CategoryGrade (New-FakeCategoryGrade) -Summary (New-FakeSummary) -UseSpectre $false } |
                Should -Not -Throw
        }
    }

    Context 'Sub-header display' {

        It 'Shows category name in sub-header' {
            Mock Invoke-ReadKey { New-BKey }
            Mock Write-Host { }

            Show-CategoryDetail -CategoryGrade (New-FakeCategoryGrade) -Summary (New-FakeSummary) -UseSpectre $false

            Should -Invoke Write-Host -ParameterFilter { $Object -match 'DNS DC1' }
        }
    }

    Context 'Parameter validation' {

        It 'Requires CategoryGrade' {
            { Show-CategoryDetail -Summary (New-FakeSummary) } | Should -Throw
        }

        It 'Requires Summary' {
            { Show-CategoryDetail -CategoryGrade (New-FakeCategoryGrade) } | Should -Throw
        }
    }
}
