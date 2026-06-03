#Requires -Version 7.5

<#
.SYNOPSIS
    Reads a single key from the console without echoing it.
.DESCRIPTION
    Local definition so unit tests can mock this function when loading only
    Show-ResultsSummary.ps1.  At runtime the definition from Show-TargetSelector.ps1
    is already loaded and takes precedence.
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
    Displays evaluation results in a split-pane summary with drill-down.
.DESCRIPTION
    Shows the overall score, passed count, and a per-category breakdown table.
    The screen is split: the left panel contains filter and navigation actions;
    the right panel lists categories coloured by status (green = all pass,
    yellow = partial, red = all fail).  Press Enter on a category to drill down.
.PARAMETER Summary
    The Sage.StudentGradeSummary object to display.
.PARAMETER OutputPath
    Path to the timestamped output directory (for loading collector data).
.PARAMETER UseSpectre
    Whether PwshSpectreConsole is available for rich rendering.
.OUTPUTS
    [string] — 'Back' or 'QuitTui'.
.EXAMPLE
    Show-ResultsSummary -Summary $GradeSummary -OutputPath './output/2026-04-18_143022'
#>
function Show-ResultsSummary {
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UseSpectre',
        Justification = 'UseSpectre kept for API compatibility; split-pane rendering is always used.')]
    param(
        [Parameter(Mandatory)]                                                           [object] $Summary,
        [Parameter()]                                                                     [string] $OutputPath,
        [Parameter()]                                                                      [bool] $UseSpectre = $false
    )

    $ErrorActionPreference = 'Stop'

    $FormatSlashCentered = {
        param(
            [Parameter()]                                                                 [string] $Left,
            [Parameter()]                                                                 [string] $Right,
            [Parameter(Mandatory)][ValidateRange(3, 200)]                                  [int] $Width
        )

        $HalfWidth = [Math]::Floor(($Width - 1) / 2)
        $LeftText = if ($null -eq $Left) { '' } else { "$Left" }
        $RightText = if ($null -eq $Right) { '' } else { "$Right" }

        if ($LeftText.Length -gt $HalfWidth) {
            $LeftText = $LeftText.Substring($LeftText.Length - $HalfWidth)
        }
        if ($RightText.Length -gt $HalfWidth) {
            $RightText = $RightText.Substring(0, $HalfWidth)
        }

        return "$($LeftText.PadLeft($HalfWidth))/$($RightText.PadRight($HalfWidth))"
    }

    # ── Pre-compute summary values ─────────────────────────────────────────────
    $NormScore = $Summary.TotalScore.Normalized
    $DisplayScore = [math]::Round([Math]::Min(20.0, $NormScore), 2)
    $Percentage = [math]::Round([Math]::Min(100.0, ($NormScore / 20.0) * 100), 1)
    $TotalPassed = ($Summary.CategoryScores | ForEach-Object { $_.PassedCount } | Measure-Object -Sum).Sum
    $Timestamp = if ($Summary.GradedAt) { $Summary.GradedAt } else { 'Unknown' }

    # ── Category table ─────────────────────────────────────────────────────────
    $Filter = 'All'
    $LeftActionCount = 5    # All, Pass, Fail, Back, Quit
    $LeftCursor = 0
    $ActivePanel = 'Right'
    $RightCursor = 0
    $KeepGoing = $true

    while ($KeepGoing) {
        $HeaderLines = Show-SageHeader

        # ── Filter categories ──────────────────────────────────────────────────
        $Categories = $Summary.CategoryScores
        if ($Filter -eq 'Pass') {
            $Categories = @($Categories | Where-Object { $_.FailedCount -eq 0 })
        }
        elseif ($Filter -eq 'Fail') {
            $Categories = @($Categories | Where-Object { $_.FailedCount -gt 0 })
        }
        # Build grouped display rows: target header rows + category rows
        $TargetOrder = @()
        $ByTarget = @{}
        foreach ($Cat in $Categories) {
            $TargetName = if ([string]::IsNullOrWhiteSpace($Cat.TargetName)) { 'Unspecified target' } else { $Cat.TargetName }
            if (-not $ByTarget.ContainsKey($TargetName)) {
                $ByTarget[$TargetName] = @()
                $TargetOrder += $TargetName
            }
            $ByTarget[$TargetName] += $Cat
        }

        $DisplayRows = @()
        foreach ($TargetName in $TargetOrder) {
            $DisplayRows += [pscustomobject]@{ Type = 'Header'; Target = $TargetName }
            foreach ($Cat in $ByTarget[$TargetName]) {
                $DisplayRows += [pscustomobject]@{ Type = 'Category'; Category = $Cat }
            }
        }

        $SelectableIdxs = @()
        for ($i = 0; $i -lt $DisplayRows.Count; $i++) {
            if ($DisplayRows[$i].Type -eq 'Category') {
                $SelectableIdxs += $i
            }
        }
        $SelectableCount = $SelectableIdxs.Count
        $TotalDisplay = $DisplayRows.Count

        # Clamp cursors after filter change
        if ($LeftCursor -lt 0) { $LeftCursor = 0 }
        if ($LeftCursor -ge $LeftActionCount) { $LeftCursor = $LeftActionCount - 1 }
        if ($RightCursor -lt 0) { $RightCursor = 0 }
        if ($SelectableCount -gt 0 -and $RightCursor -ge $SelectableCount) { $RightCursor = $SelectableCount - 1 }

        # ── Score sub-header ───────────────────────────────────────────────────
        $ScoreColor = if ($Percentage -ge 70) { 'Green' } elseif ($Percentage -ge 50) { 'Yellow' } else { 'Red' }
        Write-Host "  Results: $Timestamp  |  $DisplayScore / 20 ($Percentage%)  |  Passed: $TotalPassed  Filter: $Filter" -ForegroundColor $ScoreColor
        Write-Host ''

        # ── Split-pane rendering ───────────────────────────────────────────────
        $WinH = try { [System.Console]::WindowHeight } catch { 40 }
        $WinW = try { [System.Console]::WindowWidth } catch { 80 }
        $LeftW = [Math]::Max(24, [Math]::Min(28, [int]($WinW * 0.27)))
        $RightW = $WinW - $LeftW - 3
        $ContentH = [Math]::Max(3, $WinH - $HeaderLines - 10)

        # Clamp/scroll RightCursor into viewport
        if ($RightCursor -lt 0) { $RightCursor = 0 }
        if ($SelectableCount -gt 0 -and $RightCursor -ge $SelectableCount) { $RightCursor = $SelectableCount - 1 }
        $RightScroll = 0

        # Left panel rows
        $LeftRows = @(
            @{ Text = 'Actions'; Title = $true }
            @{ Text = ('─' * ($LeftW - 2)); Title = $true }
            @{ Text = 'Filter: All'; ActionId = 0 }
            @{ Text = 'Filter: Pass only'; ActionId = 1 }
            @{ Text = 'Filter: Fail only'; ActionId = 2 }
            @{ Text = ('─' * ($LeftW - 2)); Title = $true }
            @{ Text = 'Back'; ActionId = 3 }
            @{ Text = 'Quit'; ActionId = 4 }
        )
        $LeftSelectableRows = @(2, 3, 4, 6, 7)

        # Column widths for right panel
        $MaxCatLen = if ($Categories.Count -gt 0) {
            ($Categories | ForEach-Object { $_.Category.Length } | Measure-Object -Maximum).Maximum
        }
        else { 20 }
        $ScoreParts = @($Categories | ForEach-Object {
                [pscustomobject]@{
                    Left  = [string]([math]::Round([Math]::Min(20.0, $_.NormalizedScore), 2))
                    Right = '20'
                }
            })
        $ScoreHalfWidth = if ($ScoreParts.Count -gt 0) {
            $MaxScoreLeft = ($ScoreParts | ForEach-Object { $_.Left.Length } | Measure-Object -Maximum).Maximum
            $MaxScoreRight = ($ScoreParts | ForEach-Object { $_.Right.Length } | Measure-Object -Maximum).Maximum
            [Math]::Max($MaxScoreLeft, $MaxScoreRight)
        }
        else { 3 }
        $PassedParts = @($Categories | ForEach-Object {
                [pscustomobject]@{
                    Left  = [string]$_.PassedCount
                    Right = [string]($_.PassedCount + $_.FailedCount)
                }
            })
        $PassedHalfWidth = if ($PassedParts.Count -gt 0) {
            $MaxPassedLeft = ($PassedParts | ForEach-Object { $_.Left.Length } | Measure-Object -Maximum).Maximum
            $MaxPassedRight = ($PassedParts | ForEach-Object { $_.Right.Length } | Measure-Object -Maximum).Maximum
            [Math]::Max($MaxPassedLeft, $MaxPassedRight)
        }
        else { 3 }
        $ColScore = [Math]::Max(7, (2 * $ScoreHalfWidth) + 1)
        $ColPass = [Math]::Max(7, (2 * $PassedHalfWidth) + 1)
        $StaticLen = 2 + 2 + $ColScore + 2 + $ColPass + 2 + 6
        $ColCat = [Math]::Max(20, [Math]::Min($MaxCatLen, $RightW - $StaticLen))
        $HdrPrefix = ' '.PadRight(2)

        $OldFg = [System.Console]::ForegroundColor
        $Theme  = Get-ActiveTheme
        $StartY = $HeaderLines + 2   # 1 score line + 1 blank

        # Title row
        [System.Console]::SetCursorPosition(0, $StartY)
        [System.Console]::ForegroundColor = Resolve-ThemeColor $Theme.Accent
        [System.Console]::Write(('  Results:').PadRight($LeftW))
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(' │ ')
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        $RHdr = ("$HdrPrefix$('Category'.PadRight($ColCat))  $('Score'.PadRight($ColScore))  $('Passed'.PadRight($ColPass))  Status")
        [System.Console]::Write($RHdr.PadRight($RightW))
        [System.Console]::ForegroundColor = $OldFg

        # Separator
        [System.Console]::SetCursorPosition(0, $StartY + 1)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('─' * $LeftW) + '─┼─' + ('─' * [Math]::Max(0, $RightW)))
        [System.Console]::ForegroundColor = $OldFg

        # Scroll so cursor is visible
        if ($SelectableCount -gt 0) {
            $SelectedDisplayRow = $SelectableIdxs[$RightCursor]
            if ($SelectedDisplayRow -lt $RightScroll) {
                $RightScroll = $SelectedDisplayRow
            }
            elseif ($SelectedDisplayRow -ge ($RightScroll + $ContentH)) {
                $RightScroll = $SelectedDisplayRow - $ContentH + 1
            }
        }
        if ($RightScroll -lt 0) { $RightScroll = 0 }
        $MaxScroll = [Math]::Max(0, $TotalDisplay - $ContentH)
        if ($RightScroll -gt $MaxScroll) { $RightScroll = $MaxScroll }

        # Content rows
        for ($Row = 0; $Row -lt $ContentH; $Row++) {
            $RowY = $StartY + 2 + $Row
            $DisplayIdx = $RightScroll + $Row
            [System.Console]::SetCursorPosition(0, $RowY)

            # Left panel
            $LeftText = ''
            $LeftColor = [System.ConsoleColor]::White
            if ($Row -lt $LeftRows.Count) {
                $LRow = $LeftRows[$Row]
                if ($LRow.Title) {
                    $LeftText = "  $($LRow.Text)"
                    $LeftColor = [System.ConsoleColor]::DarkGray
                }
                else {
                    $SelIdx = $LeftSelectableRows.IndexOf($Row)
                    $IsActive = ($ActivePanel -eq 'Left' -and $SelIdx -eq $LeftCursor)
                    $CurFilter = switch ($LRow.ActionId) {
                        0 { $Filter -eq 'All' }
                        1 { $Filter -eq 'Pass' }
                        2 { $Filter -eq 'Fail' }
                        default { $false }
                    }
                    $Marker = if ($IsActive) { '► ' } else { '  ' }
                    $LeftText = "$Marker$($LRow.Text)"
                    $LeftColor = if ($IsActive) { Resolve-ThemeColor $Theme.Primary }
                    elseif ($CurFilter) { Resolve-ThemeColor $Theme.Warn }
                    else { [System.ConsoleColor]::White }
                }
            }
            [System.Console]::ForegroundColor = $LeftColor
            [System.Console]::Write($LeftText.PadRight($LeftW))
            [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
            [System.Console]::Write(' │ ')
            [System.Console]::ForegroundColor = $OldFg

            # Right panel
            $RightText = ''
            $RightColor = [System.ConsoleColor]::White
            if ($DisplayIdx -lt $TotalDisplay) {
                $DRow = $DisplayRows[$DisplayIdx]
                if ($DRow.Type -eq 'Header') {
                    $LineLen = [Math]::Max(0, $RightW - $DRow.Target.Length - 5)
                    $RightText = "  ── $($DRow.Target) $('─' * $LineLen)"
                    $RightColor = Resolve-ThemeColor $Theme.Accent
                }
                else {
                    $Cat = $DRow.Category
                    $Status = if ($Cat.FailedCount -eq 0) { 'PASS' }
                    elseif ($Cat.PassedCount -eq 0) { 'FAIL' }
                    else { 'PARTIAL' }
                    $ScoreStr = & $FormatSlashCentered -Left ([string]([math]::Round([Math]::Min(20.0, $Cat.NormalizedScore), 2))) -Right '20' -Width $ColScore
                    $PassedStr = & $FormatSlashCentered -Left ([string]$Cat.PassedCount) -Right ([string]($Cat.PassedCount + $Cat.FailedCount)) -Width $ColPass
                    $CatName = if ($Cat.Category.Length -gt $ColCat) {
                        $Cat.Category.Substring(0, $ColCat - 3) + '...'
                    }
                    else { $Cat.Category.PadRight($ColCat) }
                    $SelectedDisplayRow = if ($SelectableCount -gt 0) { $SelectableIdxs[$RightCursor] } else { -1 }
                    $IsSelected = ($ActivePanel -eq 'Right' -and $DisplayIdx -eq $SelectedDisplayRow)
                    $Marker = if ($IsSelected) { '►' } else { ' ' }
                    $RightText = "$Marker $CatName  $ScoreStr  $PassedStr  $Status"
                    $RightColor = switch ($Status) {
                        'PASS' { Resolve-ThemeColor $Theme.Pass }
                        'PARTIAL' { Resolve-ThemeColor $Theme.Warn }
                        'FAIL' { Resolve-ThemeColor $Theme.Fail }
                        default { [System.ConsoleColor]::White }
                    }
                }
            }
            elseif ($SelectableCount -eq 0 -and $Row -eq 0) {
                $RightText = '  No categories match the current filter.'
                $RightColor = [System.ConsoleColor]::DarkGray
            }
            [System.Console]::ForegroundColor = $RightColor
            [System.Console]::Write($RightText.PadRight($RightW))
            [System.Console]::ForegroundColor = $OldFg
        }

        # Status box
        $NavHint = '  ←/→: panel  ↑/↓: navigate  Enter: drill-down  B/⌫: back  Q: quit'
        Show-StatusBox -Lines @('', $NavHint) -StartY ($StartY + 2 + $ContentH)
        [System.Console]::ResetColor()

        # Key input
        $Key = Invoke-ReadKey

        switch ($Key.Key.ToString()) {
            'LeftArrow' { $ActivePanel = 'Left' }
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
                    if ($RightCursor -lt ($SelectableCount - 1)) { $RightCursor++ }
                }
            }
            'Enter' {
                if ($ActivePanel -eq 'Left') {
                    switch ($LeftCursor) {
                        0 { $Filter = 'All'; $RightCursor = 0 }
                        1 { $Filter = 'Pass'; $RightCursor = 0 }
                        2 { $Filter = 'Fail'; $RightCursor = 0 }
                        3 { $KeepGoing = $false; return 'Back' }
                        4 { $script:SageQuit = $true; $KeepGoing = $false; return 'QuitTui' }
                    }
                }
                else {
                    if ($SelectableCount -gt 0 -and $RightCursor -lt $SelectableCount) {
                        $SelectedDisplayRow = $SelectableIdxs[$RightCursor]
                        $SelectedCategory = $DisplayRows[$SelectedDisplayRow].Category
                        Show-CategoryDetail -CategoryGrade $SelectedCategory -Summary $Summary -OutputPath $OutputPath -UseSpectre $UseSpectre
                        if ($script:SageQuit) { $KeepGoing = $false }
                    }
                }
            }
            'Backspace' { $KeepGoing = $false; return 'Back' }
        }

        if ($KeepGoing) {
            switch ($Key.KeyChar.ToString().ToUpper()) {
                'A' { $Filter = 'All'; $RightCursor = 0 }
                'P' { $Filter = 'Pass'; $RightCursor = 0 }
                'F' { $Filter = 'Fail'; $RightCursor = 0 }
                'B' { $KeepGoing = $false; return 'Back' }
                'Q' { $script:SageQuit = $true; $KeepGoing = $false; return 'QuitTui' }
            }
        }
    }
}
