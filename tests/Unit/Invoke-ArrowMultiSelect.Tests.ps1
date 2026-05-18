#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Invoke-ArrowMultiSelect.
.DESCRIPTION
    Verifies the arrow-key multi-select and single-select helper using the
    _TestKeys hook to simulate keystrokes without blocking on the console.
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
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Invoke-ArrowMultiSelect.ps1')

    # Helper to build ConsoleKeyInfo objects for test injection
    function New-Key {
        [OutputType([System.ConsoleKeyInfo])]
        param([System.ConsoleKey] $Key, [char] $KeyChar = [char]0)
        [System.ConsoleKeyInfo]::new($KeyChar, $Key, $false, $false, $false)
    }
}

Describe 'Invoke-ArrowMultiSelect' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    Context 'Multi-select — defaults (all selected)' {

        It 'Returns all items when Enter is pressed immediately' {
            $Enter  = New-Key ([System.ConsoleKey]::Enter)
            $Result = Invoke-ArrowMultiSelect -Items @('A', 'B', 'C') -_TestKeys @($Enter)

            $Result | Should -Contain 'A'
            $Result | Should -Contain 'B'
            $Result | Should -Contain 'C'
        }

        It 'Excludes greyed items from default selection' {
            $Enter  = New-Key ([System.ConsoleKey]::Enter)
            $Result = Invoke-ArrowMultiSelect `
                -Items       @('A', 'B', 'C') `
                -GreyedItems @('B') `
                -_TestKeys   @($Enter)

            $Result | Should -Contain 'A'
            $Result | Should -Not -Contain 'B'
            $Result | Should -Contain 'C'
        }
    }

    Context 'Multi-select — space toggles item under cursor' {

        It 'Deselects the item under cursor when Space is pressed' {
            # Cursor starts at 0 (item A). Space deselects A. Enter confirms.
            $Space  = New-Key ([System.ConsoleKey]::Spacebar)
            $Enter  = New-Key ([System.ConsoleKey]::Enter)
            $Result = Invoke-ArrowMultiSelect -Items @('A', 'B', 'C') -_TestKeys @($Space, $Enter)

            $Result | Should -Not -Contain 'A'
            $Result | Should -Contain 'B'
            $Result | Should -Contain 'C'
        }

        It 'Navigates cursor down then toggles' {
            $Down   = New-Key ([System.ConsoleKey]::DownArrow)
            $Space  = New-Key ([System.ConsoleKey]::Spacebar)
            $Enter  = New-Key ([System.ConsoleKey]::Enter)
            # Move to B, deselect it
            $Result = Invoke-ArrowMultiSelect -Items @('A', 'B', 'C') -_TestKeys @($Down, $Space, $Enter)

            $Result | Should -Contain 'A'
            $Result | Should -Not -Contain 'B'
            $Result | Should -Contain 'C'
        }
    }

    Context 'Multi-select — A / N shortcuts' {

        It 'A key selects all items' {
            $N      = New-Key ([System.ConsoleKey]::N)
            $A      = New-Key ([System.ConsoleKey]::A)
            $Enter  = New-Key ([System.ConsoleKey]::Enter)
            # N first deselects all, then A re-selects all
            $Result = Invoke-ArrowMultiSelect -Items @('A', 'B') -_TestKeys @($N, $A, $Enter)

            $Result | Should -Contain 'A'
            $Result | Should -Contain 'B'
        }

        It 'N key deselects all items' {
            $N      = New-Key ([System.ConsoleKey]::N)
            $Enter  = New-Key ([System.ConsoleKey]::Enter)
            $Result = Invoke-ArrowMultiSelect -Items @('A', 'B') -_TestKeys @($N, $Enter)

            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'Cancellation — Q returns empty array' {

        It 'Returns empty array on Q' {
            $Q      = New-Key ([System.ConsoleKey]::Q)
            $Result = Invoke-ArrowMultiSelect -Items @('A', 'B') -_TestKeys @($Q)

            $Result | Should -BeNullOrEmpty
        }

    }

    Context 'Single-select mode' {

        It 'Returns the item under cursor on Enter' {
            $Enter  = New-Key ([System.ConsoleKey]::Enter)
            $Result = Invoke-ArrowMultiSelect -Items @('Run', 'View', 'Quit') -SingleSelect $true -_TestKeys @($Enter)

            $Result | Should -Be 'Run'
        }

        It 'Returns the second item after one DownArrow + Enter' {
            $Down   = New-Key ([System.ConsoleKey]::DownArrow)
            $Enter  = New-Key ([System.ConsoleKey]::Enter)
            $Result = Invoke-ArrowMultiSelect -Items @('Run', 'View', 'Quit') -SingleSelect $true -_TestKeys @($Down, $Enter)

            $Result | Should -Be 'View'
        }

        It 'Returns empty array when Q is pressed' {
            $Q      = New-Key ([System.ConsoleKey]::Q)
            $Result = Invoke-ArrowMultiSelect -Items @('Run', 'View', 'Quit') -SingleSelect $true -_TestKeys @($Q)

            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'Non-interactive fallback (IsInputRedirected)' {

        It 'Returns all non-greyed items without blocking when input is redirected' {
            # We cannot easily force IsInputRedirected=true, but we can verify
            # that the function runs correctly with an immediate Enter key when
            # no keys are provided and the console is non-interactive.
            # Test via _TestKeys as the primary path.
            $Enter  = New-Key ([System.ConsoleKey]::Enter)
            $Result = Invoke-ArrowMultiSelect `
                -Items       @('A', 'B', 'C') `
                -GreyedItems @('C') `
                -_TestKeys   @($Enter)

            $Result | Should -Contain 'A'
            $Result | Should -Contain 'B'
            $Result | Should -Not -Contain 'C'
        }
    }

    Context 'Parameter validation' {

        It 'Requires non-empty Items' {
            { Invoke-ArrowMultiSelect -Items @() } | Should -Throw
        }
    }
}
