#Requires -Version 7.5

<#
.SYNOPSIS
    Returns the active theme or the default Blue theme when none is set.
.DESCRIPTION
    Used by every TUI render function instead of hardcoded colour values.
    Falls back gracefully when $script:SageTheme is not set (e.g. in unit tests
    that do not load the full TUI stack).

    When PwshSpectreConsole is available ($script:UseSpectre = $true), the
    returned hashtable contains Spectre colour strings (e.g. 'springgreen3').
    Otherwise it contains System.ConsoleColor values.
.OUTPUTS
    [hashtable] — colour values keyed by semantic name.
.EXAMPLE
    $Theme = Get-ActiveTheme
    Write-SageColor -Color $Theme.Primary -Text 'text'
#>
function Get-ActiveTheme {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:SageTheme) { return $script:SageTheme }

    # Default fallback when no theme is loaded (unit tests / early startup)
    if ($script:UseSpectre) {
        return @{
            Primary = 'cyan'
            Accent  = 'darkcyan'
            Header  = 'cyan'
            Sub     = 'grey69'
            Pass    = 'green'
            Fail    = 'red'
            Warn    = 'yellow'
            Muted   = 'grey42'
        }
    }

    return @{
        Primary = [System.ConsoleColor]::Cyan
        Accent  = [System.ConsoleColor]::DarkCyan
        Header  = [System.ConsoleColor]::Cyan
        Sub     = [System.ConsoleColor]::Gray
        Pass    = [System.ConsoleColor]::Green
        Fail    = [System.ConsoleColor]::Red
        Warn    = [System.ConsoleColor]::Yellow
        Muted   = [System.ConsoleColor]::DarkGray
    }
}

<#
.SYNOPSIS
    Renders the persistent SAGE TUI header.
.DESCRIPTION
    Clears the console and draws a two-part header:
      1. A rounded-border box with big retro ASCII-art "SAGE" letters, the full
         product subtitle, and the exam name / version loaded from the exam
         definition metadata stored in the $script:SageExamName and
         $script:SageExamVersion script-scoped variables.
      2. An optional "Last Results" bar drawn when $script:SageLatestSummary
         is set, showing the score on 20, pass/fail counts and totals.

    Call this at the top of every screen-render loop iteration after
    [System.Console]::Clear() to ensure the header is always visible.
.PARAMETER NoClear
    When set, does NOT call [System.Console]::Clear() before rendering.
    Useful when the caller has already cleared the screen.
.OUTPUTS
    [int] — The number of lines written (so callers can compute available
    content height as [System.Console]::WindowHeight - returned value).
.EXAMPLE
    $HeaderLines = Show-SageHeader
.EXAMPLE
    $HeaderLines = Show-SageHeader -NoClear
#>
function Show-SageHeader {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()]                                                                    [switch] $NoClear
    )

    $ErrorActionPreference = 'Stop'

    if (-not $NoClear) {
        [System.Console]::Clear()
    }

    $Theme = Get-ActiveTheme

    $WinWidth = try { [System.Console]::WindowWidth } catch { 80 }
    if ($WinWidth -lt 60) { $WinWidth = 80 }
    $BoxInner = $WinWidth - 4   # 2 for '  ' indent, 2 for '│' borders
    $HLine = '─' * $BoxInner

    # ── ASCII-art "SAGE" (6 rows, ~36 chars wide) ──────────────────────────────
    $Art = @(
        ' ███████╗ █████╗  ██████╗ ███████╗',
        ' ██╔════╝██╔══██╗██╔════╝ ██╔════╝',
        ' ███████╗███████║██║  ███╗█████╗  ',
        ' ╚════██║██╔══██║██║   ██║██╔══╝  ',
        ' ███████║██║  ██║╚██████╔╝███████╗',
        ' ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝'
    )

    $ExamName = if ($script:SageExamName) { $script:SageExamName }    else { 'Self-Check' }
    $ExamVersion = if ($script:SageExamVersion) { $script:SageExamVersion } else { '' }
    $VersionPart = if ($ExamVersion) { " · v$ExamVersion" } else { '' }
    $SubLine = "  Self-Check · $ExamName$VersionPart"

    $LinesWritten = 0

    Write-SageColor -Color $Theme.Header -Text "  ╭$HLine╮"
    $LinesWritten++

    foreach ($ArtRow in $Art) {
        Write-SageColor -Color $Theme.Header -Text "  │$($ArtRow.PadRight($BoxInner))│"
        $LinesWritten++
    }

    Write-SageColor -Color $Theme.Header -Text "  │$(''.PadRight($BoxInner))│"
    $LinesWritten++

    Write-SageColor -Color $Theme.Header  -Text '  │' -NoNewline
    Write-SageColor -Color $Theme.Accent  -Text "$('  Stack Assessment and Grading Engine'.PadRight($BoxInner))" -NoNewline
    Write-SageColor -Color $Theme.Header  -Text '│'
    $LinesWritten++

    Write-SageColor -Color $Theme.Header  -Text '  │' -NoNewline
    Write-SageColor -Color $Theme.Accent  -Text "$($SubLine.PadRight($BoxInner))" -NoNewline
    Write-SageColor -Color $Theme.Header  -Text '│'
    $LinesWritten++

    Write-SageColor -Color $Theme.Header -Text "  ╰$HLine╯"
    $LinesWritten++

    # ── Last-results bar ───────────────────────────────────────────────────────
    $Summary = $script:SageLatestSummary
    if ($Summary -and $Summary.TotalScore) {
        $NormScore = $Summary.TotalScore.Normalized
        $On20 = [math]::Round([Math]::Min(20.0, $NormScore), 1)
        $Pct = [math]::Round([Math]::Min(100.0, ($NormScore / 20.0) * 100), 1)
        $Passed = ($Summary.CategoryScores | ForEach-Object { $_.PassedCount } | Measure-Object -Sum).Sum
        $Total = $Passed + ($Summary.CategoryScores | ForEach-Object { $_.FailedCount } | Measure-Object -Sum).Sum
        $ResultLine = "  Score: $On20 / 20  ($Pct%)  │  Tests passed: $Passed / $Total"
        $ScoreColor = if ($Pct -ge 70) { $Theme.Pass } elseif ($Pct -ge 50) { $Theme.Warn } else { $Theme.Fail }

        Write-SageColor -Color $Theme.Accent -Text "  ╭─ Last Results $('─' * ([Math]::Max(0, $BoxInner - 15)))╮"
        Write-SageColor -Color $Theme.Accent  -Text '  │' -NoNewline
        Write-SageColor -Color $ScoreColor    -Text $ResultLine.PadRight($BoxInner) -NoNewline
        Write-SageColor -Color $Theme.Accent  -Text '│'
        Write-SageColor -Color $Theme.Accent -Text "  ╰$HLine╯"
        $LinesWritten += 3
    }

    Write-Host ''
    $LinesWritten++

    return $LinesWritten
}

<#
.SYNOPSIS
    Renders the 5-line status box at the bottom of a TUI screen.
.DESCRIPTION
    Draws a bordered 5-line box at the specified console row.  The box has one
    top border line, three content lines, and one bottom border line.  Pass up
    to three strings for the content lines; the last item is typically the
    navigation hint rendered in DarkGray.
.PARAMETER Lines
    Up to three strings to display inside the box.  Shorter strings are padded;
    longer strings are truncated.  The last element is rendered in DarkGray
    (navigation hint style); preceding elements are rendered in White.
.PARAMETER StartY
    Zero-based console row where the top border of the box should be drawn.
.OUTPUTS
    [void]
.EXAMPLE
    Show-StatusBox -Lines @('Evaluating DC1...', '', '  B/⌫: back  Q: quit') -StartY 35
#>
function Show-StatusBox {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]                                                                   [string[]] $Lines = @(),
        [Parameter(Mandatory)]                                                               [int] $StartY
    )

    $WinW = try { [System.Console]::WindowWidth } catch { 80 }
    $InnerW = $WinW - 4
    if ($InnerW -lt 10) { $InnerW = 10 }
    $OldFg = [System.Console]::ForegroundColor

    [System.Console]::SetCursorPosition(0, $StartY)
    [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
    [System.Console]::Write("  ┌$('─' * $InnerW)┐")

    for ($i = 0; $i -lt 3; $i++) {
        [System.Console]::SetCursorPosition(0, $StartY + 1 + $i)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write('  │')
        $IsNavLine = ($i -eq 2)
        if ($i -lt $Lines.Count) {
            $LineText = $Lines[$i]
            if ($LineText.Length -gt $InnerW) { $LineText = $LineText.Substring(0, $InnerW) }
            [System.Console]::ForegroundColor = if ($IsNavLine) { [System.ConsoleColor]::DarkGray } else { [System.ConsoleColor]::White }
            [System.Console]::Write($LineText.PadRight($InnerW))
        }
        else {
            [System.Console]::Write(' ' * $InnerW)
        }
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write('│')
    }

    [System.Console]::SetCursorPosition(0, $StartY + 4)
    [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
    [System.Console]::Write("  └$('─' * $InnerW)┘")

    [System.Console]::ForegroundColor = $OldFg
}
