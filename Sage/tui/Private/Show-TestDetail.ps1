#Requires -Version 7.5
<#
.SYNOPSIS
    Displays detailed information for a single test result.
.DESCRIPTION
    Shows the test name, status, points awarded vs maximum, expected vs actual
    values, and relevant collector data for failed tests.  The screen uses
    split-pane rendering: test metadata on the left, collector data (if any)
    on the right.
.PARAMETER TestResult
    The individual Sage.TestResult object to display.
.PARAMETER OutputPath
    Path to the timestamped output directory (for loading collector data).
.PARAMETER UseSpectre
    Kept for API compatibility; split-pane rendering is always used.
.OUTPUTS
    [void]
.EXAMPLE
    Show-TestDetail -TestResult $Test -OutputPath './output/2026-04-18_143022'
#>
function Show-TestDetail {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UseSpectre',
        Justification = 'UseSpectre kept for API compatibility; split-pane rendering is always used.')]
    param(
        [Parameter(Mandatory)]                                                           [object] $TestResult,
        [Parameter()]                                                                     [string] $OutputPath,
        [Parameter()]                                                                      [bool] $UseSpectre = $false
    )

    $ErrorActionPreference = 'Stop'

    # ── Load collector data ────────────────────────────────────────────────────
    $CollectorDisplayLines = @()
    if ($OutputPath) {
        $SafeCat = $TestResult.Category -replace '[^\w\-.]', '' -replace '\s+', '_'
        $FileName = "$($TestResult.TargetName)-${SafeCat}-collector.md"
        $CollectorFile = Get-ChildItem -Path $OutputPath -Filter $FileName -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($CollectorFile -and (Test-Path $CollectorFile)) {
            $Content = Get-Content -Path $CollectorFile -Raw -Encoding utf8 -ErrorAction SilentlyContinue
            if ($Content) {
                $RawLines = @($Content -split '[\r\n]+' | ForEach-Object { $_.TrimEnd() })
                $CollectorDisplayLines = ConvertFrom-CollectorMarkdown -Lines $RawLines -Theme (Get-ActiveTheme)
            }
        }
    }

    $WrapText = {
        param(
            [Parameter()][AllowEmptyString()]                                             [string] $Text,
            [Parameter(Mandatory)][ValidateRange(1, 500)]                                  [int] $Width
        )

        if ([string]::IsNullOrEmpty($Text)) {
            return @('')
        }

        $Wrapped = [System.Collections.Generic.List[string]]::new()
        $Remaining = $Text
        while ($Remaining.Length -gt $Width) {
            $Cut = $Remaining.LastIndexOf(' ', $Width)
            if ($Cut -lt 1) { $Cut = $Width }
            $Wrapped.Add($Remaining.Substring(0, $Cut).TrimEnd())
            $Remaining = $Remaining.Substring($Cut).TrimStart()
        }
        $Wrapped.Add($Remaining)
        return $Wrapped.ToArray()
    }

    $KeepGoing = $true
    $ActivePanel = 'Right'
    $CollectorScroll = 0
    while ($KeepGoing) {
        $HeaderLines = Show-SageHeader

        $WinH = try { [System.Console]::WindowHeight } catch { 40 }
        $WinW = try { [System.Console]::WindowWidth } catch { 80 }
        $LeftW = [Math]::Max(30, [Math]::Min(45, [int]($WinW * 0.45)))
        $RightW = $WinW - $LeftW - 3
        $ContentH = [Math]::Max(3, $WinH - $HeaderLines - 8)

        $StatusText = if ($TestResult.Passed) { 'PASS' } else { 'FAIL' }
        $Theme = Get-ActiveTheme
        $StatusColor = if ($TestResult.Passed) { $Theme.Pass } else { $Theme.Fail }

        # Left panel detail lines
        $LeftLines = [System.Collections.Generic.List[hashtable]]::new()
        $LeftLines.Add(@{ Text = $TestResult.TestName; Color = $Theme.Primary })
        $LeftLines.Add(@{ Text = ''; Color = [System.ConsoleColor]::White })
        $LeftLines.Add(@{ Text = "Category : $($TestResult.Category)"; Color = [System.ConsoleColor]::White })
        $LeftLines.Add(@{ Text = "Target   : $($TestResult.TargetName)"; Color = [System.ConsoleColor]::White })
        $LeftLines.Add(@{ Text = "Status   : $StatusText"; Color = $StatusColor })
        $LeftLines.Add(@{ Text = "Points   : $($TestResult.FinalGrade) / $($TestResult.PassGrade)"; Color = [System.ConsoleColor]::White })
        if ($TestResult.ExpectedValue) {
            $LeftLines.Add(@{ Text = ''; Color = [System.ConsoleColor]::White })
            $LeftLines.Add(@{ Text = "Expected : $($TestResult.ExpectedValue)"; Color = $Theme.Pass })
        }
        if ($TestResult.ActualValue) {
            $LeftLines.Add(@{ Text = "Actual   : $($TestResult.ActualValue)"; Color = $StatusColor })
        }
        if ($TestResult.ErrorMessage) {
            $LeftLines.Add(@{ Text = ''; Color = [System.ConsoleColor]::White })
            $DisplayError = $TestResult.ErrorMessage
            if ($TestResult.ExpectedValue -and $DisplayError -match 'Expected a value') {
                $DisplayError = $DisplayError -replace 'Expected a value', "Expected '$($TestResult.ExpectedValue)'"
            }
            $LeftLines.Add(@{ Text = "Error    : $DisplayError"; Color = $Theme.Warn })
        }

        $WrappedLeftLines = [System.Collections.Generic.List[hashtable]]::new()
        $LeftWrapWidth = [Math]::Max(8, $LeftW - 2)
        foreach ($Line in $LeftLines) {
            $Segments = & $WrapText -Text $Line.Text -Width $LeftWrapWidth
            foreach ($Segment in $Segments) {
                $WrappedLeftLines.Add(@{ Text = $Segment; Color = $Line.Color })
            }
        }

        $WrappedCollectorLines = [System.Collections.Generic.List[hashtable]]::new()
        $RightWrapWidth = [Math]::Max(8, $RightW)
        foreach ($CollLine in $CollectorDisplayLines) {
            $Segments = & $WrapText -Text $CollLine.Text -Width $RightWrapWidth
            foreach ($Segment in $Segments) {
                $WrappedCollectorLines.Add(@{ Text = $Segment; Color = $CollLine.Color })
            }
        }

        $MaxCollectorScroll = [Math]::Max(0, $WrappedCollectorLines.Count - $ContentH)
        if ($CollectorScroll -lt 0) { $CollectorScroll = 0 }
        if ($CollectorScroll -gt $MaxCollectorScroll) { $CollectorScroll = $MaxCollectorScroll }

        $OldFg = [System.Console]::ForegroundColor
        $StartY = $HeaderLines

        # Title row
        [System.Console]::SetCursorPosition(0, $StartY)
        [System.Console]::ForegroundColor = if ($ActivePanel -eq 'Left') { Resolve-ThemeColor $Theme.Primary } else { Resolve-ThemeColor $Theme.Accent }
        $LeftTitle = if ($ActivePanel -eq 'Left') { '► Test Detail' } else { '  Test Detail' }
        [System.Console]::Write($LeftTitle.PadRight($LeftW))
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(' │ ')
        [System.Console]::ForegroundColor = if ($ActivePanel -eq 'Right') { Resolve-ThemeColor $Theme.Primary } else { [System.ConsoleColor]::DarkGray }
        $RightTitle = if ($ActivePanel -eq 'Right') { '► Collector Data' } else { '  Collector Data' }
        [System.Console]::Write($RightTitle.PadRight($RightW))
        [System.Console]::ForegroundColor = $OldFg

        # Separator
        [System.Console]::SetCursorPosition(0, $StartY + 1)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('─' * $LeftW) + '─┼─' + ('─' * [Math]::Max(0, $RightW)))
        [System.Console]::ForegroundColor = $OldFg

        # Content rows
        for ($Row = 0; $Row -lt $ContentH; $Row++) {
            $RowY = $StartY + 2 + $Row
            [System.Console]::SetCursorPosition(0, $RowY)

            # Left panel
            if ($Row -lt $WrappedLeftLines.Count) {
                $LLine = $WrappedLeftLines[$Row]
                $LText = $LLine.Text
                [System.Console]::ForegroundColor = Resolve-ThemeColor $LLine.Color
                [System.Console]::Write("  $($LText.PadRight($LeftW - 2))")
            }
            else {
                [System.Console]::ForegroundColor = [System.ConsoleColor]::White
                [System.Console]::Write(' ' * $LeftW)
            }
            [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
            [System.Console]::Write(' │ ')

            # Right panel (collector data)
            $CollIdx = $CollectorScroll + $Row
            if ($CollIdx -lt $WrappedCollectorLines.Count) {
                $CLine = $WrappedCollectorLines[$CollIdx]
                [System.Console]::ForegroundColor = if ($ActivePanel -eq 'Right') { Resolve-ThemeColor $CLine.Color } else { [System.ConsoleColor]::DarkGray }
                [System.Console]::Write($CLine.Text.PadRight($RightW))
            }
            elseif ($WrappedCollectorLines.Count -eq 0 -and $Row -eq 0) {
                [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
                $Msg = '  No collector data available.'
                [System.Console]::Write($Msg.PadRight($RightW))
            }
            else {
                [System.Console]::Write(' ' * $RightW)
            }
            [System.Console]::ForegroundColor = $OldFg
        }

        # Status box
        $NavHint = '  ←/→ or Tab: panel  ↑/↓ PgUp/PgDn Home/End: scroll collector  B/⌫: back  Q: quit'
        Show-StatusBox -Lines @('', $NavHint) -StartY ($StartY + 2 + $ContentH)
        [System.Console]::ResetColor()

        # Key input
        $Key = Invoke-ReadKey
        switch ($Key.Key.ToString()) {
            'LeftArrow' { $ActivePanel = 'Left' }
            'RightArrow' { $ActivePanel = 'Right' }
            'Tab' {
                if ($ActivePanel -eq 'Left') {
                    $ActivePanel = 'Right'
                }
                else {
                    $ActivePanel = 'Left'
                }
            }
            'UpArrow' {
                if ($ActivePanel -eq 'Right' -and $CollectorScroll -gt 0) {
                    $CollectorScroll--
                }
            }
            'DownArrow' {
                if ($ActivePanel -eq 'Right' -and $CollectorScroll -lt $MaxCollectorScroll) {
                    $CollectorScroll++
                }
            }
            'PageUp' {
                if ($ActivePanel -eq 'Right' -and $CollectorScroll -gt 0) {
                    $CollectorScroll = [Math]::Max(0, $CollectorScroll - $ContentH)
                }
            }
            'PageDown' {
                if ($ActivePanel -eq 'Right' -and $CollectorScroll -lt $MaxCollectorScroll) {
                    $CollectorScroll = [Math]::Min($MaxCollectorScroll, $CollectorScroll + $ContentH)
                }
            }
            'Home' {
                if ($ActivePanel -eq 'Right') {
                    $CollectorScroll = 0
                }
            }
            'End' {
                if ($ActivePanel -eq 'Right') {
                    $CollectorScroll = $MaxCollectorScroll
                }
            }
            'Backspace' { $KeepGoing = $false }
        }
        if ($KeepGoing) {
            switch ($Key.KeyChar.ToString().ToUpper()) {
                'B' { $KeepGoing = $false }
                'Q' { $script:SageQuit = $true; $KeepGoing = $false }
            }
        }
    }
}

