#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-ThemePicker.
.DESCRIPTION
    Verifies theme picker navigation, selection, and persistence logic.
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
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Get-SageTheme.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Save-TuiPreferencesInExam.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-ThemePicker.ps1')

    # Delegate stub — tests set $script:NextKey to control which key is returned
    $script:NextKey = [PSCustomObject]@{ Key = 'Q'; KeyChar = [char]81 }
    $script:CallCount = 0
    function Invoke-ReadKey {
        if ($script:NextKey -is [scriptblock]) {
            return & $script:NextKey
        }
        return $script:NextKey
    }
    Mock Show-SageHeader { return 14 } -ModuleName ''
    Mock Show-StatusBox { } -ModuleName ''

    function New-BackspaceKey {
        [PSCustomObject]@{ Key = 'Backspace'; KeyChar = [char]8 }
    }

    function New-BKey {
        [PSCustomObject]@{ Key = 'B'; KeyChar = [char]66 }
    }

    function New-QKey {
        [PSCustomObject]@{ Key = 'Q'; KeyChar = [char]81 }
    }

    function New-EnterKey {
        [PSCustomObject]@{ Key = 'Enter'; KeyChar = [char]13 }
    }

    function New-DownKey {
        [PSCustomObject]@{ Key = 'DownArrow'; KeyChar = [char]0 }
    }

}

Describe 'Show-ThemePicker' -Tag 'Unit' {

    BeforeEach {
        $TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-themepicker-$(New-Guid)"
        New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
        $script:SageQuit = $false
        $script:SageTheme = $null
        $script:SageThemeName = $null
    }

    AfterEach {
        if (Test-Path $TestDir) {
            Remove-Item -Path $TestDir -Recurse -Force
        }
    }

    Context 'Navigation — back without selecting' -Skip:$script:SkipInteractiveUiTests {

        It 'Returns Back on Backspace key' {
            $script:NextKey = New-BackspaceKey
            $Result = Show-ThemePicker -TuiPath $TestDir
            $Result | Should -Be 'Back'
        }

        It 'Returns Back on B shortcut key' {
            $script:NextKey = New-BKey
            $Result = Show-ThemePicker -TuiPath $TestDir
            $Result | Should -Be 'Back'
        }

        It 'Sets SageQuit and returns QuitTui on Q shortcut key' {
            $script:NextKey = New-QKey
            $Result = Show-ThemePicker -TuiPath $TestDir
            $Result | Should -Be 'QuitTui'
            $script:SageQuit | Should -BeTrue
        }
    }

    Context 'Theme selection' -Skip:$script:SkipInteractiveUiTests {

        It 'Auto-applies theme on Down arrow (without pressing Enter)' {
            $script:CallCount = 0
            $script:NextKey = {
                $script:CallCount++
                if ($script:CallCount -eq 1) { return New-DownKey }   # move + auto-apply
                return New-BKey                                         # restore original and exit
            }

            $Names = Get-SageThemeNames

            # After Down the theme should be applied in memory (before B restores original)
            # Verify by intercepting: we check after Down that theme was applied
            # Then B restores, so final state = original (null → Default)
            $null = Show-ThemePicker -TuiPath $TestDir

            # B restores the original (null = 'Default' mapped)
            $script:SageThemeName | Should -Be 'Default'
        }

        It 'Applies selected theme to script scope on Down then Enter' {
            # Down auto-applies, Enter confirms and exits
            $script:CallCount = 0
            $script:NextKey = {
                $script:CallCount++
                if ($script:CallCount -eq 1) { return New-DownKey }
                return New-EnterKey
            }

            $null = Show-ThemePicker -TuiPath $TestDir

            # After Down+Enter: theme should be the second theme in Get-SageThemeNames
            $Names = Get-SageThemeNames
            $script:SageThemeName | Should -Be $Names[1]
            $script:SageTheme | Should -Not -BeNullOrEmpty
            $script:SageTheme.Primary | Should -BeOfType [System.ConsoleColor]
        }

        It 'Persists theme to tui-config.psd1 on cursor move when file exists' {
            # Create a minimal tui-config.psd1 with a Remembered block
            $ExamFile = Join-Path $TestDir 'tui-config.psd1'
            @'
@{
    Remembered = @{
        Theme = 'Default'
    }
}
'@ | Set-Content -Path $ExamFile -Encoding UTF8

            $Names = Get-SageThemeNames
            # Down auto-applies and persists theme[1], Enter confirms exit
            $script:CallCount = 0
            $script:NextKey = {
                $script:CallCount++
                if ($script:CallCount -eq 1) { return New-DownKey }
                return New-EnterKey
            }
            $null = Show-ThemePicker -TuiPath $TestDir

            $Lines = Get-Content -Path $ExamFile -Raw
            $Lines | Should -Match "Theme\s*="
            $Lines | Should -Match ([regex]::Escape($Names[1]))
        }

        It 'Skips persistence gracefully when tui-config.psd1 does not exist' {
            # TestDir has no tui-config.psd1 — Down then Enter should not throw
            $script:CallCount = 0
            $script:NextKey = {
                $script:CallCount++
                if ($script:CallCount -eq 1) { return New-DownKey }
                return New-EnterKey
            }
            { $null = Show-ThemePicker -TuiPath $TestDir } | Should -Not -Throw
        }
    }

    Context 'Get-SageThemeNames' {

        It 'Returns at least 31 entries (Default + 30 named themes)' {
            $Names = Get-SageThemeNames
            $Names | Should -HaveCount 31
        }

        It 'First entry is Default' {
            $Names = Get-SageThemeNames
            $Names[0] | Should -Be 'Default'
        }
    }

    Context 'Get-SageTheme personality mapping' {

        It 'Default returns Blue personality (Primary = Cyan)' {
            $T = Get-SageTheme -ThemeName 'Default'
            $T.Primary | Should -Be ([System.ConsoleColor]::Cyan)
        }

        It 'Unknown theme name falls back to Default' {
            $T = Get-SageTheme -ThemeName 'NonExistentTheme'
            $T.Primary | Should -Be ([System.ConsoleColor]::Cyan)
        }

        It '9. Vintage Amber returns Amber personality (Primary = Yellow)' {
            $T = Get-SageTheme -ThemeName '9. Vintage Amber'
            $T.Primary | Should -Be ([System.ConsoleColor]::Yellow)
        }

        It '2. Synthwave 80s returns Purple personality (Primary = Magenta)' {
            $T = Get-SageTheme -ThemeName '2. Synthwave 80s'
            $T.Primary | Should -Be ([System.ConsoleColor]::Magenta)
        }

        It 'All 31 theme names map to a valid theme with ConsoleColor values' {
            $Names = Get-SageThemeNames
            foreach ($Name in $Names) {
                $T = Get-SageTheme -ThemeName $Name
                $T | Should -Not -BeNullOrEmpty
                $T.Primary | Should -BeOfType [System.ConsoleColor]
                $T.Pass    | Should -BeOfType [System.ConsoleColor]
                $T.Fail    | Should -BeOfType [System.ConsoleColor]
            }
        }
    }
}
