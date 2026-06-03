#Requires -Version 7.5

<#
.SYNOPSIS
    Displays a theme selection screen for the SAGE TUI.
.DESCRIPTION
    Presents a split-pane screen.  The left panel is a scrollable list of all
    available themes; the right panel shows a colour-block preview and a small
    demo score card for the currently highlighted theme.

    Navigation:
      Up/Down arrows — navigate the theme list.
      Enter          — confirm the selection, save to exam.psd1, apply live.
      B / Backspace  — cancel and go back without changing the theme.
      Q              — quit the TUI.

    The selected theme is written to the Remembered.Theme key in the personal
    config file and applied immediately by updating $script:SageTheme.
.PARAMETER TuiPath
    Path to the tui/ directory.
.PARAMETER ConfigPath
    Absolute path to the writable personal config (data/config/tui-config-personal.psd1).
    If omitted, falls back to tui-config.psd1 in TuiPath (legacy).
.OUTPUTS
    [string] — 'Back' or 'QuitTui'.
.EXAMPLE
    Show-ThemePicker -TuiPath '/home/student/sage/tui' -ConfigPath '/home/student/sage/data/config/tui-config-personal.psd1'
#>
function Show-ThemePicker {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TuiPath,
        [Parameter()]                                                                      [string] $ConfigPath
    )

    $ErrorActionPreference = 'Stop'

    $ThemeNames   = Get-SageThemeNames
    $ThemeCount   = $ThemeNames.Count
    $Cursor       = 0
    $Scroll       = 0
    $KeepGoing    = $true
    $ExamFile     = if ($ConfigPath) { $ConfigPath } else { Join-Path $TuiPath 'tui-config.psd1' }

    # Find index of current theme; track original for B/Backspace restore
    $CurrentName  = if ($script:SageThemeName) { $script:SageThemeName } else { 'Default' }
    $OriginalName = $CurrentName
    $StartIdx = [array]::IndexOf($ThemeNames, $CurrentName)
    if ($StartIdx -ge 0) { $Cursor = $StartIdx }

    while ($KeepGoing) {
        $HeaderLines = Show-SageHeader

        $WinH     = try { [System.Console]::WindowHeight } catch { 40 }
        $WinW     = try { [System.Console]::WindowWidth  } catch { 80 }
        $LeftW    = [Math]::Max(26, [Math]::Min(35, [int]($WinW * 0.35)))
        $RightW   = $WinW - $LeftW - 3
        $ContentH = [Math]::Max(5, $WinH - $HeaderLines - 7)

        # Clamp cursor and scroll
        if ($Cursor -lt 0)              { $Cursor = 0 }
        if ($Cursor -ge $ThemeCount)    { $Cursor = $ThemeCount - 1 }
        if ($Cursor -lt $Scroll)        { $Scroll = $Cursor }
        if ($Cursor -ge $Scroll + $ContentH) { $Scroll = $Cursor - $ContentH + 1 }
        if ($Scroll -lt 0)              { $Scroll = 0 }

        $PreviewTheme     = if ($script:UseSpectre) {
            Get-SageThemeSpectre -ThemeName $ThemeNames[$Cursor]
        }
        else {
            Get-SageTheme -ThemeName $ThemeNames[$Cursor]
        }
        $IsCurrentTheme   = $ThemeNames[$Cursor] -eq $CurrentName

        $OldFg  = [System.Console]::ForegroundColor
        $StartY = $HeaderLines

        # ── Title row ──────────────────────────────────────────────────────────
        [System.Console]::SetCursorPosition(0, $StartY)
        Write-SageColor -Color $PreviewTheme.Primary -Text ('  Select Theme:').PadRight($LeftW) -NoNewline
        Write-SageColor -Color $PreviewTheme.Muted   -Text ' │ ' -NoNewline
        Write-SageColor -Color $PreviewTheme.Primary -Text ('  Theme Preview').PadRight($RightW) -NoNewline
        [System.Console]::ForegroundColor = $OldFg

        # ── Separator ──────────────────────────────────────────────────────────
        [System.Console]::SetCursorPosition(0, $StartY + 1)
        Write-SageColor -Color $PreviewTheme.Muted -Text (('─' * $LeftW) + '─┼─' + ('─' * [Math]::Max(0, $RightW))) -NoNewline
        [System.Console]::ForegroundColor = $OldFg

        # ── Build preview lines for right panel ─────────────────────────────────
        $PreviewLines = [System.Collections.Generic.List[hashtable]]::new()

        # Color blocks
        $BlockStr = '████'
        $Slots = @(
            @{ Name = 'Primary'; ColorKey = 'Primary' }
            @{ Name = 'Accent';  ColorKey = 'Accent'  }
            @{ Name = 'Header';  ColorKey = 'Header'  }
            @{ Name = 'Pass';    ColorKey = 'Pass'     }
            @{ Name = 'Fail';    ColorKey = 'Fail'     }
            @{ Name = 'Warn';    ColorKey = 'Warn'     }
            @{ Name = 'Muted';   ColorKey = 'Muted'    }
        )

        $PreviewLines.Add(@{ Text = ''; Color = $OldFg })
        foreach ($Slot in $Slots) {
            $PreviewLines.Add(@{
                Block      = $BlockStr
                Label      = "  $($Slot.Name.PadRight(8))  $($PreviewTheme[$Slot.ColorKey])"
                BlockColor = $PreviewTheme[$Slot.ColorKey]
                Color      = $OldFg
            })
        }

        # Demo score card — inner width = 29, total line width = 33 (2 indent + 31 box)
        # Border characters (╭╮│╰╯) are always in Header colour; content in semantic colours.
        $PreviewLines.Add(@{ Text = ''; Color = $OldFg })
        $BorderColor = $PreviewTheme.Header
        $PreviewLines.Add(@{ Text = '  ── Demo ──────────────────────'; Color = $PreviewTheme.Muted })
        $PreviewLines.Add(@{ Text = '  ╭─ Score ─────────────────────╮'; Color = $BorderColor })
        $PreviewLines.Add(@{
            Prefix      = '  │'
            Content     = '  Score: 17.50 / 20          '
            Suffix      = '│'
            Color       = $PreviewTheme.Primary
            BorderColor = $BorderColor
        })
        $PreviewLines.Add(@{
            Prefix      = '  │'
            Content     = '  ✓ DNS Resolution       PASS'
            Suffix      = '│'
            Color       = $PreviewTheme.Pass
            BorderColor = $BorderColor
        })
        $PreviewLines.Add(@{
            Prefix      = '  │'
            Content     = '  ✗ OU Structure         FAIL'
            Suffix      = '│'
            Color       = $PreviewTheme.Fail
            BorderColor = $BorderColor
        })
        $PreviewLines.Add(@{
            Prefix      = '  │'
            Content     = '  ~ File Share           PART'
            Suffix      = '│'
            Color       = $PreviewTheme.Warn
            BorderColor = $BorderColor
        })
        $PreviewLines.Add(@{ Text = '  ╰─────────────────────────────╯'; Color = $BorderColor })

        # ── Content rows ────────────────────────────────────────────────────────
        for ($Row = 0; $Row -lt $ContentH; $Row++) {
            $RowY      = $StartY + 2 + $Row
            $ThemeIdx  = $Scroll + $Row
            [System.Console]::SetCursorPosition(0, $RowY)

            # Left panel: theme list
            $LeftText  = ''
            $LeftColor = [System.ConsoleColor]::White
            if ($ThemeIdx -lt $ThemeCount) {
                $TName     = $ThemeNames[$ThemeIdx]
                $IsActive  = $ThemeIdx -eq $Cursor
                $IsCurrent = $TName -eq $CurrentName
                $Marker    = if ($IsActive) { '► ' } else { '  ' }
                $Badge     = if ($IsCurrent) { ' ✓' } else { '  ' }
                $LeftText  = "$Marker$TName$Badge"
                $LeftColor = if ($IsActive) {
                    [System.ConsoleColor]::Cyan
                }
                elseif ($IsCurrent) {
                    [System.ConsoleColor]::Green
                }
                else {
                    [System.ConsoleColor]::White
                }
            }
            Write-SageColor -Color $LeftColor -Text $LeftText.PadRight($LeftW) -NoNewline
            Write-SageColor -Color $PreviewTheme.Muted -Text ' │ ' -NoNewline

            # Right panel: preview
            if ($Row -lt $PreviewLines.Count) {
                $PLine = $PreviewLines[$Row]
                if ($PLine.Block) {
                    Write-SageColor -Color $PLine.BlockColor -Text "  $($PLine.Block)" -NoNewline
                    $Written = 2 + $PLine.Block.Length
                    Write-Host $PLine.Label.PadRight([Math]::Max(0, $RightW - $Written)) -NoNewline
                }
                elseif ($PLine.Prefix) {
                    # Multi-colour line: border │ + content + border │
                    Write-SageColor -Color $PLine.BorderColor -Text $PLine.Prefix -NoNewline
                    Write-SageColor -Color $PLine.Color       -Text $PLine.Content -NoNewline
                    Write-SageColor -Color $PLine.BorderColor -Text $PLine.Suffix -NoNewline
                    $LineLen = $PLine.Prefix.Length + $PLine.Content.Length + $PLine.Suffix.Length
                    Write-Host (' ' * [Math]::Max(0, $RightW - $LineLen)) -NoNewline
                }
                else {
                    Write-SageColor -Color $PLine.Color -Text $PLine.Text.PadRight($RightW) -NoNewline
                }
            }
            else {
                Write-Host (' ' * $RightW) -NoNewline
            }
            Write-Host ''
        }

        # ── Status box ─────────────────────────────────────────────────────────
        $ActiveName  = $ThemeNames[$Cursor]
        $CurrentMark = if ($IsCurrentTheme) { '  (current)' } else { '' }
        $HintLine    = '  ↑/↓: navigate (auto-applies)  Enter: confirm  B/⌫: restore original  Q: quit'
        Show-StatusBox -Lines @("  $ActiveName$CurrentMark", '', $HintLine) -StartY ($StartY + 2 + $ContentH)

        # ── Key input ───────────────────────────────────────────────────────────
        $Key = Invoke-ReadKey

        switch ($Key.Key.ToString()) {
            'UpArrow' {
                if ($Cursor -gt 0) { $Cursor-- }
                # Auto-apply theme on cursor move
                $Selected = $ThemeNames[$Cursor]
                $script:SageTheme     = if ($script:UseSpectre) {
                    Get-SageThemeSpectre -ThemeName $Selected
                }
                else {
                    Get-SageTheme -ThemeName $Selected
                }
                $script:SageThemeName = $Selected
                if (Test-Path $ExamFile) {
                    try { Set-RememberedSettingInExamConfig -ConfigPath $ExamFile -SettingName 'Theme' -SettingLiteral "'$Selected'" }
                    catch { Write-Verbose "Could not persist theme to tui-config.psd1: $($_.Exception.Message)" }
                }
            }
            'DownArrow' {
                if ($Cursor -lt ($ThemeCount - 1)) { $Cursor++ }
                # Auto-apply theme on cursor move
                $Selected = $ThemeNames[$Cursor]
                $script:SageTheme     = if ($script:UseSpectre) {
                    Get-SageThemeSpectre -ThemeName $Selected
                }
                else {
                    Get-SageTheme -ThemeName $Selected
                }
                $script:SageThemeName = $Selected
                if (Test-Path $ExamFile) {
                    try { Set-RememberedSettingInExamConfig -ConfigPath $ExamFile -SettingName 'Theme' -SettingLiteral "'$Selected'" }
                    catch { Write-Verbose "Could not persist theme to tui-config.psd1: $($_.Exception.Message)" }
                }
            }
            'Enter' {
                # Theme already applied via cursor movement; just confirm and update CurrentName marker
                $CurrentName = $ThemeNames[$Cursor]
                $KeepGoing = $false
                return 'Back'
            }
            'Backspace' {
                # Restore the original theme
                $script:SageTheme     = if ($script:UseSpectre) {
                    Get-SageThemeSpectre -ThemeName $OriginalName
                }
                else {
                    Get-SageTheme -ThemeName $OriginalName
                }
                $script:SageThemeName = $OriginalName
                if (Test-Path $ExamFile) {
                    try { Set-RememberedSettingInExamConfig -ConfigPath $ExamFile -SettingName 'Theme' -SettingLiteral "'$OriginalName'" }
                    catch { Write-Verbose "Could not persist theme to tui-config.psd1: $($_.Exception.Message)" }
                }
                $KeepGoing = $false
                return 'Back'
            }
        }

        if ($KeepGoing) {
            switch ($Key.KeyChar.ToString().ToUpper()) {
                'B' {
                    # Restore the original theme
                    $script:SageTheme     = if ($script:UseSpectre) {
                        Get-SageThemeSpectre -ThemeName $OriginalName
                    }
                    else {
                        Get-SageTheme -ThemeName $OriginalName
                    }
                    $script:SageThemeName = $OriginalName
                    if (Test-Path $ExamFile) {
                        try { Set-RememberedSettingInExamConfig -ConfigPath $ExamFile -SettingName 'Theme' -SettingLiteral "'$OriginalName'" }
                        catch { Write-Verbose "Could not persist theme to tui-config.psd1: $($_.Exception.Message)" }
                    }
                    $KeepGoing = $false
                    return 'Back'
                }
                'Q' { $script:SageQuit = $true; $KeepGoing = $false; return 'QuitTui' }
            }
        }
    }

    return 'Back'
}
