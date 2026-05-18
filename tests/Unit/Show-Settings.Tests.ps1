#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-Settings.
.DESCRIPTION
    Verifies settings menu arrow-key navigation logic.
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
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-Settings.ps1')

    Mock Show-SageHeader { return 14 } -ModuleName ''

    function New-EnterKey {
        [PSCustomObject]@{ Key = 'Enter'; KeyChar = [char]13 }
    }

    function New-BKey {
        [PSCustomObject]@{ Key = 'B'; KeyChar = [char]66 }
    }

    function New-QKey {
        [PSCustomObject]@{ Key = 'Q'; KeyChar = [char]81 }
    }

    function New-BackspaceKey {
        [PSCustomObject]@{ Key = 'Backspace'; KeyChar = [char]8 }
    }

    function New-DownKey {
        [PSCustomObject]@{ Key = 'DownArrow'; KeyChar = [char]0 }
    }

}

Describe 'Show-Settings' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    BeforeEach {
        $TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
        New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
        $OutputDir = Join-Path $TestDir 'output'
        New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
        $script:SageQuit = $false
    }

    AfterEach {
        if (Test-Path $TestDir) {
            Remove-Item -Path $TestDir -Recurse -Force
        }
    }

    Context 'Navigation' {

        It 'Returns Back on Backspace key' {
            Mock Invoke-ReadKey { New-BackspaceKey }
            Mock Write-Host { }

            $Result = Show-Settings -TuiPath $TestDir -OutputDir $OutputDir
            $Result | Should -Be 'Back'
        }

        It 'Returns Back on B shortcut key' {
            Mock Invoke-ReadKey { New-BKey }
            Mock Write-Host { }

            $Result = Show-Settings -TuiPath $TestDir -OutputDir $OutputDir
            $Result | Should -Be 'Back'
        }

        It 'Returns Back when Back action is selected with Enter (cursor 4)' {
            $script:CallCount = 0
            Mock Invoke-ReadKey {
                $script:CallCount++
                if ($script:CallCount -le 4) { return New-DownKey }
                return New-EnterKey
            }
            Mock Write-Host { }

            $Result = Show-Settings -TuiPath $TestDir -OutputDir $OutputDir
            $Result | Should -Be 'Back'
        }

        It 'Sets SageQuit and returns QuitTui on Q shortcut key' {
            Mock Invoke-ReadKey { New-QKey }
            Mock Write-Host { }

            $Result = Show-Settings -TuiPath $TestDir -OutputDir $OutputDir
            $Result | Should -Be 'QuitTui'
            $script:SageQuit | Should -BeTrue
        }
    }

    Context 'Clear results' {

        It 'Deletes timestamped directories on confirmation' {
            $RunDir = Join-Path $OutputDir '2026-04-18_143022'
            New-Item -Path $RunDir -ItemType Directory | Out-Null

            $script:NavCount = 0
            Mock Invoke-ReadKey {
                $script:NavCount++
                if ($script:NavCount -eq 1) { return New-EnterKey }  # select 'Clear all previous results' (index 0)
                return New-BackspaceKey                               # exit after confirming
            }
            $script:ReadCount = 0
            Mock Read-Host {
                $script:ReadCount++
                if ($script:ReadCount -eq 1) { return 'Y' }    # confirm clear
                return 'N'
            }
            Mock Write-Host { }

            Show-Settings -TuiPath $TestDir -OutputDir $OutputDir

            Test-Path $RunDir | Should -BeFalse
        }
    }

    Context 'Parameter validation' {

        It 'Requires TuiPath' {
            { Show-Settings -OutputDir './output' } | Should -Throw
        }

        It 'Requires OutputDir' {
            { Show-Settings -TuiPath './tui' } | Should -Throw
        }
    }
}
