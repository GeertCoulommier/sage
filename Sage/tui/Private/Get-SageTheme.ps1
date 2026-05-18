#Requires -Version 7.5

<#
.SYNOPSIS
    Returns the active SAGE TUI colour theme as ConsoleColor fallback values.
.DESCRIPTION
    Maps the selected theme name to one of five ConsoleColor personalities
    (Blue, Purple, Green, Amber, Red).  Used as the fallback when
    PwshSpectreConsole is not available.

    For the full Spectre 256-colour theme (when PwshSpectreConsole is
    installed), use Get-SageThemeSpectre instead.

    Colour semantics:
      Primary   — active item highlights, panel borders, titles
      Accent    — sub-headers, secondary emphasis
      Header    — ASCII art logo, outer box borders
      Pass      — passed tests, high scores
      Fail      — failed tests, low scores
      Warn      — partial scores, warnings
      Muted     — borders, inactive items, hints (always DarkGray)

    All 30 themes from data/themes/themes.psd1 are mapped here.
    Call Get-ActiveTheme (defined in Show-SageHeader.ps1) at each render
    iteration instead of calling this directly, so unit tests fall back
    gracefully when no theme is set.
.PARAMETER ThemeName
    The theme name string (e.g. '4. Ocean Breeze').  Defaults to 'Default'.
.OUTPUTS
    [hashtable] — System.ConsoleColor values keyed by semantic name.
.EXAMPLE
    $Theme = Get-SageTheme -ThemeName '9. Vintage Amber'
    [System.Console]::ForegroundColor = $Theme.Pass
#>
function Get-SageTheme {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]                                                                    [string] $ThemeName = 'Default'
    )

    # ── ConsoleColor personalities ─────────────────────────────────────────────
    $Personalities = @{
        Blue = @{
            Primary = [System.ConsoleColor]::Cyan
            Accent  = [System.ConsoleColor]::DarkCyan
            Header  = [System.ConsoleColor]::Cyan
            Pass    = [System.ConsoleColor]::Green
            Fail    = [System.ConsoleColor]::Red
            Warn    = [System.ConsoleColor]::Yellow
            Muted   = [System.ConsoleColor]::DarkGray
        }
        Purple = @{
            Primary = [System.ConsoleColor]::Magenta
            Accent  = [System.ConsoleColor]::DarkMagenta
            Header  = [System.ConsoleColor]::Magenta
            Pass    = [System.ConsoleColor]::Green
            Fail    = [System.ConsoleColor]::Red
            Warn    = [System.ConsoleColor]::Yellow
            Muted   = [System.ConsoleColor]::DarkGray
        }
        Green = @{
            Primary = [System.ConsoleColor]::Green
            Accent  = [System.ConsoleColor]::DarkGreen
            Header  = [System.ConsoleColor]::Green
            Pass    = [System.ConsoleColor]::Cyan
            Fail    = [System.ConsoleColor]::Red
            Warn    = [System.ConsoleColor]::Yellow
            Muted   = [System.ConsoleColor]::DarkGray
        }
        Amber = @{
            Primary = [System.ConsoleColor]::Yellow
            Accent  = [System.ConsoleColor]::DarkYellow
            Header  = [System.ConsoleColor]::Yellow
            Pass    = [System.ConsoleColor]::Green
            Fail    = [System.ConsoleColor]::Red
            Warn    = [System.ConsoleColor]::DarkYellow
            Muted   = [System.ConsoleColor]::DarkGray
        }
        Red = @{
            Primary = [System.ConsoleColor]::Red
            Accent  = [System.ConsoleColor]::DarkRed
            Header  = [System.ConsoleColor]::Red
            Pass    = [System.ConsoleColor]::Green
            Fail    = [System.ConsoleColor]::DarkRed
            Warn    = [System.ConsoleColor]::Yellow
            Muted   = [System.ConsoleColor]::DarkGray
        }
    }

    # ── Theme → personality map (all 30 themes from data/themes/themes.psd1) ─
    $ThemeMap = @{
        'Default'              = 'Blue'
        '1. Cyberpunk Neon'    = 'Green'
        '2. Synthwave 80s'     = 'Purple'
        '3. Matrix Terminal'   = 'Green'
        '4. Ocean Breeze'      = 'Blue'
        '5. Forest Timber'     = 'Green'
        '6. Dracula Dark'      = 'Purple'
        '7. Solarized Dark'    = 'Blue'
        '8. Nordic Frost'      = 'Blue'
        '9. Vintage Amber'     = 'Amber'
        '10. Pastel Soft'      = 'Purple'
        '11. Catppuccin Mocha' = 'Blue'
        '12. Tokyo Night'      = 'Purple'
        '13. Nord Ice'         = 'Blue'
        '14. Gruvbox Dark'     = 'Amber'
        '15. Monokai Pro'      = 'Green'
        '16. One Dark Pro'     = 'Red'
        '17. Night Owl'        = 'Purple'
        '18. Ayu Mirage'       = 'Amber'
        '19. Rose Pine'        = 'Purple'
        '20. GitHub Dark'      = 'Blue'
        '21. Cloud Dancer'     = 'Blue'
        '22. Mocha Mousse'     = 'Amber'
        '23. Viva Magenta'     = 'Red'
        '24. New Age Pastel'   = 'Purple'
        '25. Earthy Boho'      = 'Amber'
        '26. Forest Velvet'    = 'Green'
        '27. Quiet Luxury'     = 'Blue'
        '28. Mid-Century Mod'  = 'Amber'
        '29. Desert Sunset'    = 'Red'
        '30. Scandi Minimal'   = 'Blue'
    }

    $Key = if ($ThemeName -and $ThemeMap.ContainsKey($ThemeName)) {
        $ThemeName
    }
    else {
        'Default'
    }

    return $Personalities[$ThemeMap[$Key]]
}

<#
.SYNOPSIS
    Returns the ordered list of all available TUI theme names.
.DESCRIPTION
    Used by Show-ThemePicker to populate the theme list.  The first entry is
    always 'Default'.
.OUTPUTS
    [string[]] — Ordered list of theme name strings.
.EXAMPLE
    $Names = Get-SageThemeNames
#>
function Get-SageThemeNames {
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Get-SageThemeNames returns a list of multiple theme names — the plural noun is intentional.')]
    param()

    return @(
        'Default'
        '1. Cyberpunk Neon'
        '2. Synthwave 80s'
        '3. Matrix Terminal'
        '4. Ocean Breeze'
        '5. Forest Timber'
        '6. Dracula Dark'
        '7. Solarized Dark'
        '8. Nordic Frost'
        '9. Vintage Amber'
        '10. Pastel Soft'
        '11. Catppuccin Mocha'
        '12. Tokyo Night'
        '13. Nord Ice'
        '14. Gruvbox Dark'
        '15. Monokai Pro'
        '16. One Dark Pro'
        '17. Night Owl'
        '18. Ayu Mirage'
        '19. Rose Pine'
        '20. GitHub Dark'
        '21. Cloud Dancer'
        '22. Mocha Mousse'
        '23. Viva Magenta'
        '24. New Age Pastel'
        '25. Earthy Boho'
        '26. Forest Velvet'
        '27. Quiet Luxury'
        '28. Mid-Century Mod'
        '29. Desert Sunset'
        '30. Scandi Minimal'
    )
}

<#
.SYNOPSIS
    Returns the active SAGE TUI colour theme as Spectre colour strings.
.DESCRIPTION
    Loads the named theme directly from data/themes/themes.psd1 and
    returns a hashtable of Spectre 256-colour palette strings
    (e.g. 'springgreen3', 'grey85', 'black on gold1').

    Used when PwshSpectreConsole is available ($script:UseSpectre = $true).
    For the 16-colour ConsoleColor fallback, use Get-SageTheme instead.
.PARAMETER ThemeName
    The theme name string (e.g. '4. Ocean Breeze').  Defaults to 'Default'.
.OUTPUTS
    [hashtable] — Spectre colour strings keyed by semantic name, or $null
    when themes.psd1 cannot be found.
.EXAMPLE
    $Theme = Get-SageThemeSpectre -ThemeName '1. Cyberpunk Neon'
    Write-SpectreHost "[$($Theme.Pass)]PASS[/]"
#>
function Get-SageThemeSpectre {
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
        Justification = 'Invoke-Expression is necessary to load .psd1 data files on Linux where dot-sourcing fails.')]
    param(
        [Parameter()]                                                                    [string] $ThemeName = 'Default'
    )

    # Default theme colours (used when themes.psd1 is absent or ThemeName = 'Default')
    $DefaultTheme = @{
        Primary = 'cyan'
        Accent  = 'darkcyan'
        Header  = 'cyan'
        Sub     = 'grey69'
        Pass    = 'green'
        Fail    = 'red'
        Warn    = 'yellow'
        Muted   = 'grey42'
    }

    if ($ThemeName -eq 'Default' -or [string]::IsNullOrEmpty($ThemeName)) {
        return $DefaultTheme
    }

    # Locate themes.psd1 — two levels up from tui/Private/ → sage/data/themes/
    $ThemesPath = Join-Path $PSScriptRoot '..' '..' 'data' 'themes' 'themes.psd1'
    $ThemesPath = [System.IO.Path]::GetFullPath($ThemesPath)

    if (-not (Test-Path $ThemesPath)) {
        return $DefaultTheme
    }

    # Load the themes array from the script-style .psd1 file
    $LoadedThemes = & {
        param([string] $FilePath)
        $Content = Get-Content -Path $FilePath -Raw
        Invoke-Expression -Command $Content
        return $Themes
    } $ThemesPath

    $ThemeData = $LoadedThemes | Where-Object { $_.Name -eq $ThemeName } | Select-Object -First 1

    if (-not $ThemeData) {
        return $DefaultTheme
    }

    return @{
        Primary = if ($ThemeData.Primary) { $ThemeData.Primary } else { $DefaultTheme.Primary }
        Accent  = if ($ThemeData.Accent)  { $ThemeData.Accent  } else { $DefaultTheme.Accent  }
        Header  = if ($ThemeData.Header)  { $ThemeData.Header  } else { $DefaultTheme.Header  }
        Sub     = if ($ThemeData.Sub)     { $ThemeData.Sub     } else { $DefaultTheme.Sub     }
        Pass    = if ($ThemeData.Pass)    { $ThemeData.Pass    } else { $DefaultTheme.Pass    }
        Fail    = if ($ThemeData.Fail)    { $ThemeData.Fail    } else { $DefaultTheme.Fail    }
        Warn    = if ($ThemeData.Warn)    { $ThemeData.Warn    } else { $DefaultTheme.Warn    }
        Muted   = if ($ThemeData.Muted)   { $ThemeData.Muted   } else { $DefaultTheme.Muted   }
    }
}
