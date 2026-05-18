#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-TestDetail.
.DESCRIPTION
    Verifies test-detail rendering and handling of empty text fields.
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
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Compare-Results.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-TestDetail.ps1')

    function Invoke-ReadKey {
        [CmdletBinding()]
        [OutputType([System.ConsoleKeyInfo])]
        param()
        [System.Console]::ReadKey($true)
    }

    Mock Show-SageHeader { return 14 } -ModuleName ''

    function New-BackspaceKey { [PSCustomObject]@{ Key = 'Backspace'; KeyChar = [char]8 } }

    function New-FakeTestResult {
        [PSCustomObject]@{
            Category      = 'DNS DC1'
            TestName      = 'PTR record'
            Passed        = $false
            FinalGrade    = 0
            PassGrade     = 1
            TargetName    = 'DC1'
            ActualValue   = ''
            ExpectedValue = ''
            ErrorMessage  = ''
        }
    }

}

Describe 'Show-TestDetail' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    BeforeEach {
        $script:SageQuit = $false
    }

    It 'Does not throw when detail values are empty strings' {
        Mock Invoke-ReadKey { New-BackspaceKey }
        Mock Write-Host { }

        { Show-TestDetail -TestResult (New-FakeTestResult) -OutputPath '' -UseSpectre $false } |
            Should -Not -Throw
    }
}
