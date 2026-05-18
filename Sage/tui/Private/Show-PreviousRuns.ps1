#Requires -Version 7.5

<#
.SYNOPSIS
    Reads a single key from the console without echoing it.
.DESCRIPTION
    Local definition so unit tests can mock this function when loading only
    Show-PreviousRuns.ps1.  At runtime the definition from
    Show-TargetSelector.ps1 is already loaded and takes precedence.
.OUTPUTS
    [System.ConsoleKeyInfo]
.EXAMPLE
    $Key = Invoke-ReadKey
#>
function Invoke-ReadKey {
    [CmdletBinding()]
    [OutputType([System.ConsoleKeyInfo])]
    param()
    [System.Console]::ReadKey($true)
}

<#
.SYNOPSIS
    Displays a list of previous evaluation runs with scores and deltas.
.DESCRIPTION
    Scans the output directory for timestamped subdirectories, loads the
    grade summary from each, and displays a split-pane screen.  The left
    panel contains navigation actions; the right panel lists runs newest
    first.  Press Space to mark a run for diff (max 2), Enter to drill
    down into results, D to diff 2 marked runs.
.PARAMETER OutputDir
    Root output directory to scan.
.PARAMETER UseSpectre
    Whether PwshSpectreConsole is available for rich rendering.
.PARAMETER LatestSummary
    The most recent Sage.StudentGradeSummary, used for the fixed banner.
    When not provided, the first run in the list is used as the latest.
.OUTPUTS
    [string] — 'Back' or 'QuitTui'.
.EXAMPLE
    Show-PreviousRuns -OutputDir './output' -LatestSummary $LatestSummary
#>
function Show-PreviousRuns {
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Show-PreviousRuns renders a list of past evaluation runs — the plural noun is intentional.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LatestSummary',
        Justification = 'API compat; last-results summary is now read from $script:SageLatestSummary by Show-SageHeader.')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $OutputDir,
        [Parameter()]                                                                        [bool] $UseSpectre = $false,
        [Parameter()]                                                                      [object] $LatestSummary = $null
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $OutputDir)) {
        Show-SageHeader | Out-Null
        Write-Host '  No output directory found.' -ForegroundColor Yellow
        return 'Back'
    }

    $Dirs = Get-ChildItem -Path $OutputDir -Directory |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{6}$' } |
        Sort-Object -Property Name -Descending

    if ($Dirs.Count -eq 0) {
        Show-SageHeader | Out-Null
        Write-Host '  No previous evaluation runs found.' -ForegroundColor Yellow
        return 'Back'
    }

    # ── Load summaries (newest first) ──────────────────────────────────────────
    $Runs = @()
    foreach ($Dir in $Dirs) {
        $Summary = Import-ResultSummary -OutputPath $Dir.FullName
        $TargetsDisplay = '-'
        if ($Summary -and $Summary.CategoryScores) {
            $TargetNames = @($Summary.CategoryScores | ForEach-Object { $_.TargetName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            if ($TargetNames.Count -gt 0) {
                $TargetsDisplay = $TargetNames -join ', '
            }
        }
        $Runs += [PSCustomObject]@{
            Path     = $Dir.FullName
            DirName  = $Dir.Name
            Date     = $Dir.Name -replace '_', ' ' -replace '(\d{4}-\d{2}-\d{2}) (\d{2})(\d{2})(\d{2})', '$1 $2:$3:$4'
            Score    = if ($Summary) { $Summary.TotalScore.Normalized } else { $null }
            MaxScore = if ($Summary) { $Summary.TotalScore.Max } else { $null }
            Targets  = $TargetsDisplay
            Summary  = $Summary
        }
    }

    $LeftActionCount = 3    # Diff, Back, Quit
    $LeftCursor      = 0
    $RightCursor     = 0
    $MarkedRuns      = [System.Collections.Generic.HashSet[int]]::new()
    $KeepGoing       = $true

    # ── Pre-compute score deltas ───────────────────────────────────────────────
    $PrevScore = $null
    foreach ($Run in $Runs) {
        $NormScore = if ($null -ne $Run.Score) { [math]::Round([Math]::Min(20.0, $Run.Score), 1) } else { $null }
        $Change    = if ($null -eq $PrevScore -or $null -eq $NormScore) { '-' }
                     elseif (($NormScore - $PrevScore) -gt 0)  { "+$($NormScore - $PrevScore)" }
                     elseif (($NormScore - $PrevScore) -lt 0)  { "$($NormScore - $PrevScore)" }
                     else { 'same' }
        $Run | Add-Member -NotePropertyName 'DisplayScore' -NotePropertyValue $NormScore -Force
        $Run | Add-Member -NotePropertyName 'Change'       -NotePropertyValue $Change       -Force
        $PrevScore = $NormScore
    }
    $TotalRows = $Runs.Count

    # Pre-mark the 2 most recent runs and put cursor on the Diff action
    if ($TotalRows -ge 2) {
        $MarkedRuns.Add(0) | Out-Null
        $MarkedRuns.Add(1) | Out-Null
        $ActivePanel = 'Left'
        $LeftCursor  = 0   # Diff action
    }
    else {
        $ActivePanel = 'Right'
    }

    while ($KeepGoing) {
        $HeaderLines = Show-SageHeader

        # Clamp cursors
        if ($LeftCursor  -lt 0)                          { $LeftCursor  = 0 }
        if ($LeftCursor  -ge $LeftActionCount)            { $LeftCursor  = $LeftActionCount - 1 }
        if ($RightCursor -lt 0)                          { $RightCursor = 0 }
        if ($TotalRows -gt 0 -and $RightCursor -ge $TotalRows) { $RightCursor = $TotalRows - 1 }

        # ── Sub-header ─────────────────────────────────────────────────────────
        $MarkedCount = $MarkedRuns.Count
        Write-Host "  Previous Evaluation Runs  (newest first)  |  Marked for diff: $MarkedCount / 2" -ForegroundColor Cyan
        Write-Host ''

        if ($UseSpectre) { $UseSpectre = $UseSpectre }   # suppress unused-param warning

        # ── Split-pane rendering ───────────────────────────────────────────────
        $WinH     = try { [System.Console]::WindowHeight } catch { 40 }
        $WinW     = try { [System.Console]::WindowWidth  } catch { 80 }
        $LeftW    = [Math]::Max(24, [Math]::Min(28, [int]($WinW * 0.27)))
        $RightW   = $WinW - $LeftW - 3
        $ContentH = [Math]::Max(1, $WinH - $HeaderLines - 10)

        # Scroll so cursor is visible
        $RightScroll = 0
        if ($RightCursor -lt $RightScroll) { $RightScroll = $RightCursor }
        if ($RightCursor -ge ($RightScroll + $ContentH)) { $RightScroll = $RightCursor - $ContentH + 1 }

        $DiffLabel = if ($MarkedCount -eq 2) { 'Diff 2 marked' } else { "Diff ($MarkedCount/2 marked)" }
        $LeftRows  = @(
            @{ Text = 'Actions';            Title    = $true }
            @{ Text = ('─' * ($LeftW - 2)); Title    = $true }
            @{ Text = $DiffLabel;           ActionId = 0     }
            @{ Text = ('─' * ($LeftW - 2)); Title    = $true }
            @{ Text = 'Back';               ActionId = 1     }
            @{ Text = 'Quit';               ActionId = 2     }
        )
        $LeftSelectableRows = @(2, 4, 5)

        $OldFg  = [System.Console]::ForegroundColor
        $Theme  = Get-ActiveTheme
        $StartY = $HeaderLines + 2

        # Title row
        $DateW = [Math]::Max(19, [Math]::Min(22, (($Runs | ForEach-Object { $_.Date.Length } | Measure-Object -Maximum).Maximum)))
        $ScoreW = [Math]::Max(7, (($Runs | ForEach-Object {
            if ($null -ne $_.DisplayScore) { "$($_.DisplayScore) / 20".Length } else { 3 }
        } | Measure-Object -Maximum).Maximum))
        $ChangeW = [Math]::Max(6, (($Runs | ForEach-Object { "$($_.Change)".Length } | Measure-Object -Maximum).Maximum))
        $StaticW = 2 + 4 + 5 + 2 + $DateW + 2 + $ScoreW + 2 + $ChangeW + 2
        $TargetsW = [Math]::Max(10, $RightW - $StaticW)

        [System.Console]::SetCursorPosition(0, $StartY)
        [System.Console]::ForegroundColor = Resolve-ThemeColor $Theme.Accent
        [System.Console]::Write(('  Runs:').PadRight($LeftW))
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(' │ ')
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        $RHdr = "  $('#'.PadRight(3))  $('Date'.PadRight($DateW))  $('Score'.PadRight($ScoreW))  $('Change'.PadRight($ChangeW))  Targets"
        [System.Console]::Write($RHdr.PadRight($RightW))
        [System.Console]::ForegroundColor = $OldFg

        # Separator
        [System.Console]::SetCursorPosition(0, $StartY + 1)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('─' * $LeftW) + '─┼─' + ('─' * [Math]::Max(0, $RightW)))
        [System.Console]::ForegroundColor = $OldFg

        # Content rows
        for ($Row = 0; $Row -lt $ContentH; $Row++) {
            $RowY     = $StartY + 2 + $Row
            $RightIdx = $RightScroll + $Row
            [System.Console]::SetCursorPosition(0, $RowY)

            # Left panel
            $LeftText  = ''
            $LeftColor = [System.ConsoleColor]::White
            if ($Row -lt $LeftRows.Count) {
                $LRow = $LeftRows[$Row]
                if ($LRow.Title) {
                    $LeftText  = "  $($LRow.Text)"
                    $LeftColor = [System.ConsoleColor]::DarkGray
                }
                else {
                    $SelIdx   = $LeftSelectableRows.IndexOf($Row)
                    $IsActive = ($ActivePanel -eq 'Left' -and $SelIdx -eq $LeftCursor)
                    $Marker   = if ($IsActive) { '► ' } else { '  ' }
                    $LeftText = "$Marker$($LRow.Text)"
                    $LeftColor = if ($LRow.ActionId -eq 0) {
                        if ($MarkedCount -eq 2) {
                            if ($IsActive) { $Theme.Primary } else { $Theme.Pass }
                        }
                        else { [System.ConsoleColor]::DarkGray }
                    }
                    elseif ($IsActive) { $Theme.Primary }
                    else { [System.ConsoleColor]::White }
                }
            }
            [System.Console]::ForegroundColor = $LeftColor
            [System.Console]::Write($LeftText.PadRight($LeftW))
            [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
            [System.Console]::Write(' │ ')
            [System.Console]::ForegroundColor = $OldFg

            # Right panel
            $RightText  = ''
            $RightColor = [System.ConsoleColor]::White
            if ($RightIdx -lt $TotalRows) {
                $Run        = $Runs[$RightIdx]
                $IsSelected = ($ActivePanel -eq 'Right' -and $RightIdx -eq $RightCursor)
                $IsMarked   = $MarkedRuns.Contains($RightIdx)
                $Selector   = if ($IsSelected) { '►' } else { ' ' }
                $MarkBadge  = if ($IsMarked) { '[M]' } else { '   ' }
                $ScoreStr   = if ($null -ne $Run.DisplayScore) { "$($Run.DisplayScore) / 20" } else { 'N/A' }
                $Num        = "$($RightIdx + 1).".PadLeft(3)
                $TargetsText = if ($Run.Targets.Length -gt $TargetsW) {
                    $Run.Targets.Substring(0, [Math]::Max(0, $TargetsW - 3)) + '...'
                }
                else {
                    $Run.Targets.PadRight($TargetsW)
                }
                $RightText  = "$Selector $MarkBadge $Num  $($Run.Date.PadRight($DateW))  $($ScoreStr.PadRight($ScoreW))  $($Run.Change.PadRight($ChangeW))  $TargetsText"
                $RightColor = if ($IsSelected) { Resolve-ThemeColor $Theme.Primary }
                              elseif ($IsMarked) { Resolve-ThemeColor $Theme.Warn }
                              else { [System.ConsoleColor]::White }
            }
            elseif ($TotalRows -eq 0 -and $Row -eq 0) {
                $RightText  = '  No previous runs found.'
                $RightColor = [System.ConsoleColor]::DarkGray
            }
            [System.Console]::ForegroundColor = $RightColor
            [System.Console]::Write($RightText.PadRight($RightW))
            [System.Console]::ForegroundColor = $OldFg
        }

        # Status box
        $NavHint = '  ←/→: panel  ↑/↓: navigate  Space: mark  Enter: open/diff  D: diff  B/⌫: back  Q: quit'
        Show-StatusBox -Lines @('', $NavHint) -StartY ($StartY + 2 + $ContentH)
        [System.Console]::ResetColor()

        # Key input
        $Key = Invoke-ReadKey

        switch ($Key.Key.ToString()) {
            'LeftArrow'  { $ActivePanel = 'Left' }
            'RightArrow' { $ActivePanel = 'Right' }
            'UpArrow' {
                if ($ActivePanel -eq 'Left') {
                    if ($LeftCursor -gt 0) { $LeftCursor-- }
                }
                else {
                    if ($RightCursor -gt 0) { $RightCursor-- }
                }
            }
            'DownArrow' {
                if ($ActivePanel -eq 'Left') {
                    if ($LeftCursor -lt ($LeftActionCount - 1)) { $LeftCursor++ }
                }
                else {
                    if ($RightCursor -lt ($TotalRows - 1)) { $RightCursor++ }
                }
            }
            'Spacebar' {
                if ($ActivePanel -eq 'Right' -and $TotalRows -gt 0) {
                    if ($MarkedRuns.Contains($RightCursor)) {
                        $MarkedRuns.Remove($RightCursor) | Out-Null
                    }
                    elseif ($MarkedRuns.Count -lt 2) {
                        $MarkedRuns.Add($RightCursor) | Out-Null
                    }
                }
            }
            'Enter' {
                if ($ActivePanel -eq 'Left') {
                    switch ($LeftCursor) {
                        0 {
                            if ($MarkedCount -eq 2) {
                                $SortedMarked = @($MarkedRuns | Sort-Object -Descending)
                                $DiffRunA     = $Runs[$SortedMarked[0]]
                                $DiffRunB     = $Runs[$SortedMarked[1]]
                                if ($DiffRunA.Summary -and $DiffRunB.Summary) {
                                    $Diff = Compare-Results -OlderSummary $DiffRunA.Summary -NewerSummary $DiffRunB.Summary
                                    Show-DiffResults -Diff $Diff -OlderDate $DiffRunA.Date -NewerDate $DiffRunB.Date -RunA $DiffRunA -RunB $DiffRunB -UseSpectre $UseSpectre
                                    if ($script:SageQuit) { $KeepGoing = $false }
                                }
                            }
                        }
                        1 { $KeepGoing = $false; return 'Back' }
                        2 { $script:SageQuit = $true; $KeepGoing = $false; return 'QuitTui' }
                    }
                }
                else {
                    if ($TotalRows -gt 0 -and $RightCursor -lt $TotalRows) {
                        $SelectedRun = $Runs[$RightCursor]
                        if ($SelectedRun.Summary) {
                            Show-ResultsSummary -Summary $SelectedRun.Summary -OutputPath $SelectedRun.Path -UseSpectre $UseSpectre
                            if ($script:SageQuit) { $KeepGoing = $false }
                        }
                    }
                }
            }
            'Backspace' { $KeepGoing = $false; return 'Back' }
        }

        if ($KeepGoing) {
            switch ($Key.KeyChar.ToString().ToUpper()) {
                'D' {
                    if ($MarkedCount -eq 2) {
                        $SortedMarked = @($MarkedRuns | Sort-Object -Descending)
                        $DiffRunA     = $Runs[$SortedMarked[0]]
                        $DiffRunB     = $Runs[$SortedMarked[1]]
                        if ($DiffRunA.Summary -and $DiffRunB.Summary) {
                            $Diff = Compare-Results -OlderSummary $DiffRunA.Summary -NewerSummary $DiffRunB.Summary
                                Show-DiffResults -Diff $Diff -OlderDate $DiffRunA.Date -NewerDate $DiffRunB.Date -RunA $DiffRunA -RunB $DiffRunB -UseSpectre $UseSpectre
                                if ($script:SageQuit) { $KeepGoing = $false }
                            }
                        }
                    }
                    'B' { $KeepGoing = $false; return 'Back' }
                    'Q' { $script:SageQuit = $true; $KeepGoing = $false; return 'QuitTui' }
                }
            }
    }
}


<#
.SYNOPSIS
    Prompts the user to select exactly two runs to compare, then shows the diff.
.DESCRIPTION
    Defaults to the two most recent runs.  In Spectre mode, uses two sequential
    Read-SpectreSelection prompts (one for each run) so the selection is limited
    to exactly 2.  In plain-text mode, the user enters two space-separated
    numbers.  After selection, calls Show-DiffResults.
.PARAMETER Runs
    Sorted array of run objects (oldest first).
.PARAMETER UseSpectre
    Whether PwshSpectreConsole is available for rich rendering.
.OUTPUTS
    [void]
.EXAMPLE
    Show-DiffSelector -Runs $SortedRuns -UseSpectre $true
#>
function Show-DiffSelector {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]                                                           [object[]] $Runs,
        [Parameter()]                                                                      [bool] $UseSpectre = $false
    )

    $ErrorActionPreference = 'Stop'

    # $Runs is already sorted newest-first (from Show-PreviousRuns)
    $Count = $Runs.Count
    $IdxA  = 1   # 0-based: second newest (default)
    $IdxB  = 0   # 0-based: newest (default)

    if ($UseSpectre) {
        # ── Spectre: offer default shortcut first, then two sequential prompts ─
        $RunLabels    = @($Runs | ForEach-Object { $_.Date })
        $DefaultLabel = "Default — compare 2 most recent ($($Runs[1].Date)  vs  $($Runs[0].Date))"
        $ModeChoices  = @($DefaultLabel, 'Choose specific runs')

        Show-SageHeader | Out-Null
        $ModeSelection = Read-SpectreSelection -Message 'Which runs to compare?' -Choices $ModeChoices -PageSize 2

        if ($ModeSelection.Trim() -ne $DefaultLabel) {
            Show-SageHeader | Out-Null
            Write-Host '  Select run A (older):' -ForegroundColor Cyan
            $SelectionA = Read-SpectreSelection -Message 'Select run A:' -Choices $RunLabels -PageSize $Count
            $IdxA       = [array]::IndexOf($RunLabels, $SelectionA.Trim())
            if ($IdxA -lt 0) { $IdxA = 1 }

            $RunLabelsB = @($RunLabels | Where-Object { $_ -ne $SelectionA.Trim() })
            Show-SageHeader | Out-Null
            Write-Host '  Select run B (newer):' -ForegroundColor Cyan
            $SelectionB = Read-SpectreSelection -Message 'Select run B:' -Choices $RunLabelsB -PageSize $RunLabelsB.Count
            $IdxBFull   = [array]::IndexOf($RunLabels, $SelectionB.Trim())
            if ($IdxBFull -lt 0) { $IdxBFull = 0 }
            $IdxB = $IdxBFull

            # Ensure A is older (higher index = older in newest-first list)
            if ($IdxA -lt $IdxB) { $Tmp = $IdxA; $IdxA = $IdxB; $IdxB = $Tmp }
        }
    }
    else {
        # ── Plain text: display list newest-first, accept two numbers ─────────
        Show-SageHeader | Out-Null
        Write-Host "  Compare runs — newest first (default: runs 1 and 2):" -ForegroundColor Cyan
        Write-Host ''
        for ($I = 0; $I -lt $Count; $I++) {
            Write-Host "  [$($I + 1)]  $($Runs[$I].Date)"
        }
        Write-Host ''
        Write-Host '  Enter two numbers (e.g. "1 3"), or press Enter for the default (1 and 2).'
        $UserInput  = Read-Host '  Choice'
        $UserInput  = $UserInput.Trim()
        $InputParts = ($UserInput -split '\s+') | Where-Object { $_ -ne '' }

        if ($UserInput -and $InputParts.Count -eq 2 -and $InputParts[0] -match '^\d+$' -and $InputParts[1] -match '^\d+$') {
            $CandA = [int]$InputParts[0] - 1
            $CandB = [int]$InputParts[1] - 1
            if ($CandA -ge 0 -and $CandA -lt $Count -and $CandB -ge 0 -and $CandB -lt $Count -and $CandA -ne $CandB) {
                # Ensure A is older (higher index = older)
                if ($CandA -lt $CandB) { $Tmp = $CandA; $CandA = $CandB; $CandB = $Tmp }
                $IdxA = $CandA
                $IdxB = $CandB
            }
            else {
                Write-Host '  Invalid selection, using default (runs 1 and 2).' -ForegroundColor Yellow
            }
        }
    }

    $DiffRunA = $Runs[$IdxA]   # older
    $DiffRunB = $Runs[$IdxB]   # newer

    if (-not $DiffRunA.Summary -or -not $DiffRunB.Summary) {
        Write-Host '  Could not load one or both result files.' -ForegroundColor Yellow
        return
    }

    $Diff = Compare-Results -OlderSummary $DiffRunA.Summary -NewerSummary $DiffRunB.Summary
    Show-DiffResults -Diff $Diff -OlderDate $DiffRunA.Date -NewerDate $DiffRunB.Date -RunA $DiffRunA -RunB $DiffRunB -UseSpectre $UseSpectre
}
