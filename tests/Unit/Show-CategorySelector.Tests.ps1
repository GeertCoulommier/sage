#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-CategorySelector.
.DESCRIPTION
    Verifies category selection logic in fallback (non-Spectre) mode.
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
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-CategorySelector.ps1')

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

Describe 'Show-CategorySelector' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    BeforeEach {
        $Exam = @{
            Categories = @(
                @{ Name = 'DNS DC1'; Target = 'DC1' }
                @{ Name = 'Docker Linux'; Target = 'Linux' }
                @{ Name = 'DHCP DC1'; Target = 'DC1' }
                @{ Name = 'IIS Client'; Target = 'Client' }
            )
        }
    }

    Context 'Fallback mode — select all available by default' {

        It 'Returns all available categories when Enter is pressed' {
            Mock Invoke-ReadKey { New-EnterKey }
            Mock Write-Host { }

            $Result = Show-CategorySelector -Exam $Exam -EnabledTargets @('DC1', 'Linux') -UseSpectre $false

            $Result | Should -Contain 'DNS DC1'
            $Result | Should -Contain 'Docker Linux'
            $Result | Should -Contain 'DHCP DC1'
            $Result | Should -Not -Contain 'IIS Client'
        }
    }

    Context 'Back navigation' {

        BeforeEach { $script:SageQuit = $false }

        It 'Returns empty array when B key is pressed' {
            Mock Invoke-ReadKey { New-BKey }
            Mock Write-Host { }

            $Result = Show-CategorySelector -Exam $Exam -EnabledTargets @('DC1', 'Linux') -UseSpectre $false

            $Result | Should -HaveCount 0
        }

        It 'Returns empty array when Backspace is pressed' {
            Mock Invoke-ReadKey { New-BackspaceKey }
            Mock Write-Host { }

            $Result = Show-CategorySelector -Exam $Exam -EnabledTargets @('DC1', 'Linux') -UseSpectre $false

            $Result | Should -HaveCount 0
        }

        It 'Uses remembered preselected categories when provided' {
            Mock Invoke-ReadKey { New-EnterKey }
            Mock Write-Host { }

            $Result = Show-CategorySelector -Exam $Exam -EnabledTargets @('DC1', 'Linux') -UseSpectre $false -PreselectedCategories @('DNS DC1')

            $Result | Should -HaveCount 1
            @($Result)[0] | Should -Be 'DNS DC1'
        }
    }

    Context 'Target filtering' {

        It 'Excludes categories for disabled targets' {
            Mock Invoke-ReadKey { New-EnterKey }
            Mock Write-Host { }

            $Result = Show-CategorySelector -Exam $Exam -EnabledTargets @('DC1') -UseSpectre $false

            $Result | Should -Contain 'DNS DC1'
            $Result | Should -Contain 'DHCP DC1'
            $Result | Should -Not -Contain 'Docker Linux'
            $Result | Should -Not -Contain 'IIS Client'
        }
    }

    Context 'Parameter validation' {

        It 'Requires Exam' {
            { Show-CategorySelector -EnabledTargets @('DC1') } | Should -Throw
        }

        It 'Requires non-empty EnabledTargets' {
            { Show-CategorySelector -Exam $Exam -EnabledTargets @() } | Should -Throw
        }
    }

    Context 'Left-panel layout includes Selection header' {

        It 'Renders without error — Selection header row is present in left panel' {
            Mock Invoke-ReadKey { New-EnterKey }
            Mock Write-Host { }

            # Must not throw; the Selection header is a non-selectable title row
            { Show-CategorySelector -Exam $Exam -EnabledTargets @('DC1') -UseSpectre $false } | Should -Not -Throw
        }
    }
}
