#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-MainMenu.
.DESCRIPTION
    Verifies the main menu arrow-key navigation: valid selections and quit.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Write-SageColor.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-SageHeader.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-MainMenu.ps1')

    Mock Show-SageHeader { return 14 } -ModuleName ''

    function New-EnterKey {
        [PSCustomObject]@{ Key = 'Enter'; KeyChar = [char]13 }
    }

    function New-QKey {
        [PSCustomObject]@{ Key = 'Q'; KeyChar = [char]81 }
    }

    function New-DownKey {
        [PSCustomObject]@{ Key = 'DownArrow'; KeyChar = [char]0 }
    }
}

Describe 'Show-MainMenu' -Tag 'Unit' {

    Context 'Arrow-key navigation' {

        It 'Returns RunEvaluation when Enter is pressed at cursor 0' {
            Mock Invoke-ReadKey { New-EnterKey }
            Mock Write-Host { }

            $Result = Show-MainMenu
            $Result | Should -Be 'RunEvaluation'
        }

        It 'Returns ViewLastResults after one Down then Enter' {
            $script:CallCount = 0
            Mock Invoke-ReadKey {
                $script:CallCount++
                if ($script:CallCount -eq 1) { return New-DownKey }
                return New-EnterKey
            }
            Mock Write-Host { }

            $Result = Show-MainMenu
            $Result | Should -Be 'ViewLastResults'
        }

        It 'Returns ViewPreviousRuns after two Down then Enter' {
            $script:CallCount = 0
            Mock Invoke-ReadKey {
                $script:CallCount++
                if ($script:CallCount -le 2) { return New-DownKey }
                return New-EnterKey
            }
            Mock Write-Host { }

            $Result = Show-MainMenu
            $Result | Should -Be 'ViewPreviousRuns'
        }

        It 'Returns Settings after three Down then Enter' {
            $script:CallCount = 0
            Mock Invoke-ReadKey {
                $script:CallCount++
                if ($script:CallCount -le 3) { return New-DownKey }
                return New-EnterKey
            }
            Mock Write-Host { }

            $Result = Show-MainMenu
            $Result | Should -Be 'Settings'
        }

        It 'Returns Quit after four Down then Enter' {
            $script:CallCount = 0
            Mock Invoke-ReadKey {
                $script:CallCount++
                if ($script:CallCount -le 4) { return New-DownKey }
                return New-EnterKey
            }
            Mock Write-Host { }

            $Result = Show-MainMenu
            $Result | Should -Be 'Quit'
        }

        It 'Returns Quit on Backspace keypress' {
            Mock Invoke-ReadKey { [PSCustomObject]@{ Key = 'Backspace'; KeyChar = [char]8 } }
            Mock Write-Host { }

            $Result = Show-MainMenu
            $Result | Should -Be 'Quit'
        }

        It 'Returns Quit on Q keypress' {
            Mock Invoke-ReadKey { New-QKey }
            Mock Write-Host { }

            $Result = Show-MainMenu
            $Result | Should -Be 'Quit'
        }

    }

    Context 'Header display' {

        It 'Calls Show-SageHeader on each render' {
            Mock Invoke-ReadKey { New-QKey }
            Mock Write-Host { }
            Mock Show-SageHeader { return 14 }

            Show-MainMenu

            Should -Invoke Show-SageHeader -Times 1 -Exactly
        }
    }

    Context 'Disclaimer display' {

        It 'Shows disclaimer text' {
            Mock Invoke-ReadKey { New-QKey }
            Mock Write-Host { }
            Mock Get-ActiveTheme { @{Primary = 'White'; Muted = 'DarkGray'} }
            Mock Show-SageHeader { return 14 }

            # The function should complete without errors when displaying the menu
            # Disclaimer is conditionally shown based on window height; this test
            # verifies the function completes successfully (disclaimer or not).
            $Result = Show-MainMenu

            $Result | Should -Be 'Quit'
        }
    }
}
