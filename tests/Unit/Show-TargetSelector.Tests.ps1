#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-TargetSelector.
.DESCRIPTION
    Verifies target selection logic in fallback (non-Spectre) mode.
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
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-TargetSelector.ps1')

    Mock Show-SageHeader { return 14 } -ModuleName ''

    function New-EnterKey {
        # Simulate an Enter keypress for Invoke-ReadKey mocks.
        [PSCustomObject]@{
            Key     = 'Enter'
            KeyChar = [char]13
        }
    }

    function New-BKey {
        [PSCustomObject]@{
            Key     = 'B'
            KeyChar = [char]66
        }
    }

    function New-BackspaceKey {
        [PSCustomObject]@{
            Key     = 'Backspace'
            KeyChar = [char]8
        }
    }

}

Describe 'Show-TargetSelector' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    BeforeEach {
        $TuiConfig = @{
            Targets = @{
                Linux  = @{ PrimaryHostName = '192.168.1.2'; Port = 22 }
                DC1    = @{ PrimaryHostName = '192.168.1.3'; Port = 22 }
                DC2    = @{ PrimaryHostName = '192.168.1.4'; Port = 22 }
            }
        }
    }

    Context 'Fallback mode — select all by default' {

        It 'Returns all targets when Enter is pressed immediately' {
            Mock Invoke-ReadKey { New-EnterKey }
            Mock Write-Host { }

            $Result = Show-TargetSelector -Targets @('Linux', 'DC1', 'DC2') -TuiConfig $TuiConfig -UseSpectre $false

            $Result | Should -Contain 'Linux'
            $Result | Should -Contain 'DC1'
            $Result | Should -Contain 'DC2'
        }
    }

    Context 'Back navigation' {

        BeforeEach { $script:SageQuit = $false }

        It 'Returns empty array when B key is pressed' {
            Mock Invoke-ReadKey { New-BKey }
            Mock Write-Host { }

            $Result = Show-TargetSelector -Targets @('Linux', 'DC1') -TuiConfig $TuiConfig -UseSpectre $false

            $Result | Should -HaveCount 0
        }

        It 'Returns empty array when Backspace is pressed' {
            Mock Invoke-ReadKey { New-BackspaceKey }
            Mock Write-Host { }

            $Result = Show-TargetSelector -Targets @('Linux', 'DC1') -TuiConfig $TuiConfig -UseSpectre $false

            $Result | Should -HaveCount 0
        }

        It 'Uses remembered preselected targets when provided' {
            Mock Invoke-ReadKey { New-EnterKey }
            Mock Write-Host { }

            $Result = Show-TargetSelector -Targets @('Linux', 'DC1', 'DC2') -TuiConfig $TuiConfig -UseSpectre $false -PreselectedTargets @('Linux')

            $Result | Should -HaveCount 1
            @($Result)[0] | Should -Be 'Linux'
        }
    }

    Context 'Parameter validation' {

        It 'Requires non-empty Targets' {
            { Show-TargetSelector -Targets @() -TuiConfig $TuiConfig } | Should -Throw
        }

        It 'Requires TuiConfig' {
            { Show-TargetSelector -Targets @('Linux') } | Should -Throw
        }
    }
}
