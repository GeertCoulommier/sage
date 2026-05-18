#Requires -Version 7.5
<#
.SYNOPSIS
    Converts Markdown collector output lines into color-annotated display lines.
.DESCRIPTION
    Parses a Markdown-formatted collector report line by line and assigns a
    ConsoleColor to each line based on its Markdown element type (heading,
    code block, bold text, etc.). Code blocks are indented relative to the
    current heading level (2 * heading_level spaces) and displayed in standard
    text color. Designed for use in TUI split-pane rendering where lines are
    output with SetCursorPosition and PadRight.
.PARAMETER Lines
    Array of raw Markdown line strings (e.g. from Get-Content split on newlines).
.PARAMETER Theme
    Active TUI theme object (from Get-ActiveTheme).  When omitted, a plain
    default palette is used (White/Gray only).
.OUTPUTS
    [hashtable[]]  Array of @{ Text = [string]; Color = [System.ConsoleColor]; Indent = [int] }.
.EXAMPLE
    $DisplayLines = ConvertFrom-CollectorMarkdown -Lines $RawLines -Theme (Get-ActiveTheme)
#>
function ConvertFrom-CollectorMarkdown {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()]                              [string[]] $Lines = @(),
        [Parameter()]                                                                    [object] $Theme = $null
    )

    $ErrorActionPreference = 'Stop'

    $Primary = if ($Theme -and $Theme.Primary) { $Theme.Primary } else { [System.ConsoleColor]::Cyan }
    $Accent = if ($Theme -and $Theme.Accent) { $Theme.Accent } else { [System.ConsoleColor]::DarkCyan }
    $WarnClr = if ($Theme -and $Theme.Warn) { $Theme.Warn } else { [System.ConsoleColor]::Yellow }

    $Result = [System.Collections.Generic.List[hashtable]]::new()
    $InCodeBlock = $false
    $CurrentHeaderLevel = 0

    foreach ($Line in $Lines) {
        # ── Code fence boundary ────────────────────────────────────────────────
        if ($Line -match '^```') {
            $InCodeBlock = -not $InCodeBlock
            continue
        }

        # ── Code block content ─────────────────────────────────────────────────
        if ($InCodeBlock) {
            $CodeIndent = 2 * $CurrentHeaderLevel
            $Padding = ' ' * $CodeIndent
            $Result.Add(@{ Text = "$Padding$Line"; Color = [System.ConsoleColor]::White; Indent = $CodeIndent })
            continue
        }

        # ── Empty line ─────────────────────────────────────────────────────────
        if ([string]::IsNullOrWhiteSpace($Line)) {
            $Result.Add(@{ Text = ''; Color = [System.ConsoleColor]::DarkGray })
            continue
        }

        # ── Headings ───────────────────────────────────────────────────────────
        if ($Line -match '^#### (.+)$') {
            $CurrentHeaderLevel = 4
            $Result.Add(@{ Text = "      $($Matches[1])"; Color = [System.ConsoleColor]::DarkCyan })
            continue
        }
        if ($Line -match '^### (.+)$') {
            $CurrentHeaderLevel = 3
            $Result.Add(@{ Text = "    $($Matches[1])"; Color = [System.ConsoleColor]::Cyan })
            continue
        }
        if ($Line -match '^## (.+)$') {
            $CurrentHeaderLevel = 2
            $Result.Add(@{ Text = "  $($Matches[1])"; Color = $Accent })
            continue
        }
        if ($Line -match '^# (.+)$') {
            $CurrentHeaderLevel = 1
            $Result.Add(@{ Text = "  $($Matches[1])"; Color = $Primary })
            continue
        }

        # ── Bold text **...** ──────────────────────────────────────────────────
        if ($Line -match '\*\*') {
            $CleanLine = $Line -replace '\*\*', ''
            $Result.Add(@{ Text = "  $CleanLine"; Color = $Accent })
            continue
        }

        # ── Blockquote ────────────────────────────────────────────────────────
        if ($Line -match '^> (.+)$') {
            $Result.Add(@{ Text = "  $($Matches[1])"; Color = $WarnClr })
            continue
        }

        # ── Bullet list ───────────────────────────────────────────────────────
        if ($Line -match '^[-*] (.+)$') {
            $Result.Add(@{ Text = "  • $($Matches[1])"; Color = [System.ConsoleColor]::White })
            continue
        }

        # ── Italics / plain text ───────────────────────────────────────────────
        $Result.Add(@{ Text = "  $Line"; Color = [System.ConsoleColor]::White })
    }

    return $Result.ToArray()
}

<#
.DESCRIPTION
    Takes an older and newer Sage.StudentGradeSummary and computes per-test
    diff indicators (improved, regressed, unchanged, new, removed) along with
    the overall score delta.
.PARAMETER OlderSummary
    The earlier Sage.StudentGradeSummary.
.PARAMETER NewerSummary
    The more recent Sage.StudentGradeSummary.
.OUTPUTS
    [PSCustomObject] — { ScoreDelta, CategoryDiffs[], TestDiffs[] }.
.EXAMPLE
    $Diff = Compare-Results -OlderSummary $Old -NewerSummary $New
#>
function Compare-Results {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Compare-Results compares two result sets — the plural noun is intentional.')]
    param(
        [Parameter(Mandatory)]                                                           [object] $OlderSummary,
        [Parameter(Mandatory)]                                                           [object] $NewerSummary
    )

    $ErrorActionPreference = 'Stop'

    $ScoreDelta = $NewerSummary.TotalScore.Normalized - $OlderSummary.TotalScore.Normalized

    # ── Build test lookup from older results ───────────────────────────────────
    $OlderTests = @{}
    if ($OlderSummary.TestResults) {
        foreach ($Test in $OlderSummary.TestResults) {
            $Key = "$($Test.Category)|$($Test.TestName)"
            $OlderTests[$Key] = $Test
        }
    }

    # ── Compare tests ─────────────────────────────────────────────────────────
    $TestDiffs = @()
    if ($NewerSummary.TestResults) {
        foreach ($Test in $NewerSummary.TestResults) {
            $Key = "$($Test.Category)|$($Test.TestName)"
            $OldTest = $OlderTests[$Key]

            $Status = if (-not $OldTest) { 'New' }
            elseif ($Test.Passed -and -not $OldTest.Passed) { 'Improved' }
            elseif (-not $Test.Passed -and $OldTest.Passed) { 'Regressed' }
            else { 'Unchanged' }

            $TestDiffs += [PSCustomObject]@{
                Category  = $Test.Category
                TestName  = $Test.TestName
                OldPassed = if ($OldTest) { $OldTest.Passed } else { $null }
                NewPassed = $Test.Passed
                OldGrade  = if ($OldTest) { $OldTest.FinalGrade } else { 0 }
                NewGrade  = $Test.FinalGrade
                Status    = $Status
            }
        }
    }

    # ── Detect removed tests ──────────────────────────────────────────────────
    $NewerKeys = if ($NewerSummary.TestResults) {
        @($NewerSummary.TestResults | ForEach-Object { "$($_.Category)|$($_.TestName)" })
    }
    else {
        @()
    }
    foreach ($Key in $OlderTests.Keys) {
        if ($NewerKeys -notcontains $Key) {
            $OldTest = $OlderTests[$Key]
            $TestDiffs += [PSCustomObject]@{
                Category  = $OldTest.Category
                TestName  = $OldTest.TestName
                OldPassed = $OldTest.Passed
                NewPassed = $null
                OldGrade  = $OldTest.FinalGrade
                NewGrade  = 0
                Status    = 'Removed'
            }
        }
    }

    # ── Category diffs ─────────────────────────────────────────────────────────
    $OlderCats = @{}
    if ($OlderSummary.CategoryScores) {
        foreach ($Cat in $OlderSummary.CategoryScores) {
            $OlderCats[$Cat.Category] = $Cat
        }
    }

    $CategoryDiffs = @()
    if ($NewerSummary.CategoryScores) {
        foreach ($Cat in $NewerSummary.CategoryScores) {
            $OldCat = $OlderCats[$Cat.Category]
            $OldScore = if ($OldCat) { $OldCat.NormalizedScore } else { 0 }
            $CategoryDiffs += [PSCustomObject]@{
                Category = $Cat.Category
                OldScore = $OldScore
                NewScore = $Cat.NormalizedScore
                Delta    = $Cat.NormalizedScore - $OldScore
            }
        }
    }

    return [PSCustomObject]@{
        ScoreDelta    = $ScoreDelta
        CategoryDiffs = $CategoryDiffs
        TestDiffs     = $TestDiffs
    }
}

<#
.SYNOPSIS
    Displays the diff results between two evaluation runs in a left-right layout.
.DESCRIPTION
    Shows a side-by-side comparison of two evaluation runs.  The screen is split
    into a left panel (Actions) and a right panel (Results).  Use the left and
    right arrow keys to switch focus between panels.  In the right panel, up and
    down arrows scroll through the test diff list.  "↑ N more above" and
    "↓ N more below" indicators appear when the list is truncated.  Pressing
    Enter on the right panel drills into the selected test; pressing Enter on the
    left panel activates the highlighted action.
.PARAMETER Diff
    The diff object from Compare-Results.
.PARAMETER OlderDate
    Human-readable date string for the older (left) run.
.PARAMETER NewerDate
    Human-readable date string for the newer (right) run.
.PARAMETER RunA
    Optional run object (with .Summary and .Path) for the older run.
.PARAMETER RunB
    Optional run object (with .Summary and .Path) for the newer run.
.PARAMETER UseSpectre
    Whether PwshSpectreConsole is available for rich rendering.
.OUTPUTS
    [void]
.EXAMPLE
    Show-DiffResults -Diff $Diff -OlderDate '2026-04-18 14:30:22' -NewerDate '2026-04-18 15:15:00'
#>
function Show-DiffResults {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Show-DiffResults renders a list of diff items — the plural noun is intentional.')]
    param(
        [Parameter(Mandatory)]                                                           [object] $Diff,
        [Parameter()]                                                                    [string] $OlderDate = 'Run A',
        [Parameter()]                                                                    [string] $NewerDate = 'Run B',
        [Parameter()]                                                                    [object] $RunA = $null,
        [Parameter()]                                                                    [object] $RunB = $null,
        [Parameter()]                                                                      [bool] $UseSpectre = $false
    )

    $ErrorActionPreference = 'Stop'

    $AllSorted = @($Diff.TestDiffs | Sort-Object -Property {
            $Parts = $_.Category -split ' '
            $Parts[-1]
        }, Category, TestName)

    $ChangedSorted = @($AllSorted | Where-Object { $_.Status -ne 'Unchanged' })

    $DiffFilter = 'All'    # 'All' | 'SameOnly' | 'DiffOnly'
    $RightScroll = 0
    $RightCursor = 0
    $LeftCursor = 0        # 0=All, 1=SameOnly, 2=DiffOnly, 3=Back, 4=Quit
    $ActivePanel = 'Right'
    $KeepGoing = $true

    # Left-panel action IDs
    $LeftActionCount = 5    # All, SameOnly, DiffOnly, Back, Quit

    while ($KeepGoing) {
        $HeaderLines = Show-SageHeader

        $Sorted = switch ($DiffFilter) {
            'All' { $AllSorted }
            'SameOnly' { @($AllSorted | Where-Object { $_.Status -eq 'Unchanged' }) }
            default { $ChangedSorted }   # 'DiffOnly'
        }
        $TotalItems = $Sorted.Count

        $WinH = try { [System.Console]::WindowHeight } catch { 40 }
        $WinW = try { [System.Console]::WindowWidth } catch { 80 }

        $LeftW = [Math]::Max(22, [Math]::Min(30, [int]($WinW * 0.28)))
        $RightW = $WinW - $LeftW - 3
        $ContentH = [Math]::Max(3, $WinH - $HeaderLines - 8)

        # ── Build grouped display rows (VM → Category → Item) ──────────────────
        $DisplayRows = [System.Collections.Generic.List[hashtable]]::new()
        $SelectableIdxs = [System.Collections.Generic.List[int]]::new()

        $VmOrder = [System.Collections.Generic.List[string]]::new()
        $CatOrder = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new()
        foreach ($Test in $Sorted) {
            $Parts = $Test.Category -split ' '
            $Vm = $Parts[-1]
            if (-not $VmOrder.Contains($Vm)) { $VmOrder.Add($Vm) }
            if (-not $CatOrder.ContainsKey($Vm)) {
                $CatOrder[$Vm] = [System.Collections.Generic.List[string]]::new()
            }
            if (-not $CatOrder[$Vm].Contains($Test.Category)) {
                $CatOrder[$Vm].Add($Test.Category)
            }
        }

        foreach ($Vm in $VmOrder) {
            $DisplayRows.Add(@{ Type = 'VmHeader'; Vm = $Vm })
            foreach ($Cat in $CatOrder[$Vm]) {
                $DisplayRows.Add(@{ Type = 'CatHeader'; Category = $Cat })
                foreach ($Test in ($Sorted | Where-Object { $_.Category -eq $Cat })) {
                    $SelectableIdxs.Add($DisplayRows.Count)
                    $DisplayRows.Add(@{ Type = 'Item'; Test = $Test })
                }
            }
        }

        $TotalDisplayRows = $DisplayRows.Count

        # Clamp cursors
        if ($LeftCursor -lt 0) { $LeftCursor = 0 }
        if ($LeftCursor -ge $LeftActionCount) { $LeftCursor = $LeftActionCount - 1 }
        if ($RightCursor -lt 0) { $RightCursor = 0 }
        if ($TotalItems -gt 0 -and $RightCursor -ge $TotalItems) {
            $RightCursor = $TotalItems - 1
        }

        # Keep selected item in viewport
        if ($TotalItems -gt 0) {
            $SelectedDisplayRow = $SelectableIdxs[$RightCursor]
            if ($SelectedDisplayRow -lt $RightScroll) {
                $RightScroll = $SelectedDisplayRow
            }
            elseif ($SelectedDisplayRow -ge ($RightScroll + $ContentH)) {
                $RightScroll = $SelectedDisplayRow - $ContentH + 1
            }
        }
        if ($RightScroll -lt 0) { $RightScroll = 0 }
        $MaxDisplayScroll = [Math]::Max(0, $TotalDisplayRows - $ContentH)
        if ($RightScroll -gt $MaxDisplayScroll) { $RightScroll = $MaxDisplayScroll }

        $DeltaStr = if ($Diff.ScoreDelta -gt 0) { "+$($Diff.ScoreDelta)" } else { "$($Diff.ScoreDelta)" }
        $Theme = Get-ActiveTheme
        $DeltaColor = if ($Diff.ScoreDelta -gt 0) { $Theme.Pass }
        elseif ($Diff.ScoreDelta -lt 0) { $Theme.Fail }
        else { [System.ConsoleColor]::White }

        # ── Build left panel row texts ──────────────────────────────────────────
        $LeftRows = @(
            @{ Text = 'Actions'; Title = $true }
            @{ Text = ('─' * ($LeftW - 2)); Title = $true }
            @{ Text = 'View: All'; ActionId = 0 }
            @{ Text = 'View: Same only'; ActionId = 1 }
            @{ Text = 'View: Diff only'; ActionId = 2 }
            @{ Text = ('─' * ($LeftW - 2)); Title = $true }
            @{ Text = 'Back'; ActionId = 3 }
            @{ Text = 'Quit'; ActionId = 4 }
        )
        $LeftSelectableRows = @(2, 3, 4, 6, 7)   # row indices of selectable items

        # ── Render title row ────────────────────────────────────────────────────
        $StartY = $HeaderLines
        [System.Console]::SetCursorPosition(0, $StartY)

        $OldFg = [System.Console]::ForegroundColor
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write('  Actions:'.PadRight($LeftW))
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(' │ ')

        # Dates left-aligned, ΔScore right-aligned
        $DatePart = "Newer: $NewerDate   Older: $OlderDate"
        $DeltaPart = "ΔScore: $DeltaStr"
        $Available = $RightW - 2  # account for leading '  '
        $Padding = [Math]::Max(1, $Available - $DatePart.Length - $DeltaPart.Length)
        [System.Console]::ForegroundColor = Resolve-ThemeColor $Theme.Primary
        [System.Console]::Write("  $DatePart")
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(' ' * $Padding)
        [System.Console]::ForegroundColor = $DeltaColor
        [System.Console]::Write($DeltaPart)
        [System.Console]::ForegroundColor = $OldFg

        # ── Column header row ─────────────────────────────────────────────────
        $NameW = [Math]::Max(15, $RightW - 28)
        $ColNew = 5  # 'Newer'
        $ColOld = 5  # 'Older'
        [System.Console]::SetCursorPosition(0, $StartY + 1)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('  ' + 'Actions:').PadRight($LeftW))
        [System.Console]::Write(' │ ')
        $ColHdr = "  $('#'.PadRight(4))  $('Test Name'.PadRight($NameW))  $('Newer'.PadRight($ColNew))  $('Older'.PadRight($ColOld))  Diff"
        [System.Console]::Write($ColHdr.PadRight($RightW))
        [System.Console]::ForegroundColor = $OldFg

        # ── Separator ──────────────────────────────────────────────────────────
        [System.Console]::SetCursorPosition(0, $StartY + 2)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('─' * $LeftW) + '─┼─' + ('─' * [Math]::Max(0, $RightW)))
        [System.Console]::ForegroundColor = $OldFg

        # ── Content rows ────────────────────────────────────────────────────────
        for ($Row = 0; $Row -lt $ContentH; $Row++) {
            $RowY = $StartY + 3 + $Row
            $DisplayIdx = $RightScroll + $Row
            [System.Console]::SetCursorPosition(0, $RowY)

            # ── Left panel ─────────────────────────────────────────────────────
            $LeftText = ''
            $LeftColor = [System.ConsoleColor]::White
            if ($Row -lt $LeftRows.Count) {
                $LRow = $LeftRows[$Row]
                if ($LRow.Title) {
                    $LeftText = "  $($LRow.Text)"
                    $LeftColor = [System.ConsoleColor]::DarkGray
                }
                else {
                    $SelIdxInSelectable = $LeftSelectableRows.IndexOf($Row)
                    $IsActive = ($ActivePanel -eq 'Left' -and $SelIdxInSelectable -eq $LeftCursor)
                    $CurFilter = switch ($LRow.ActionId) {
                        0 { $DiffFilter -eq 'All' }
                        1 { $DiffFilter -eq 'SameOnly' }
                        2 { $DiffFilter -eq 'DiffOnly' }
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

            # ── Right panel ────────────────────────────────────────────────────
            $RightText = ''
            $RightColor = [System.ConsoleColor]::White

            if ($TotalItems -eq 0 -and $Row -eq 0) {
                $RightText = '  (no items to display)'
                $RightColor = [System.ConsoleColor]::DarkGray
            }
            elseif ($DisplayIdx -lt $TotalDisplayRows) {
                $DRow = $DisplayRows[$DisplayIdx]
                if ($DRow.Type -eq 'VmHeader') {
                    $HLine = '─' * [Math]::Max(0, $RightW - $DRow.Vm.Length - 5)
                    $RightText = "  ── $($DRow.Vm) $HLine"
                    $RightColor = Resolve-ThemeColor $Theme.Accent
                }
                elseif ($DRow.Type -eq 'CatHeader') {
                    $HLine = '─' * [Math]::Max(0, $RightW - $DRow.Category.Length - 7)
                    $RightText = "    ── $($DRow.Category) $HLine"
                    $RightColor = [System.ConsoleColor]::DarkGray
                }
                else {
                    $ItemIdx = $SelectableIdxs.IndexOf($DisplayIdx)
                    $Test = $Sorted[$ItemIdx]
                    $IsSelected = ($ActivePanel -eq 'Right' -and $ItemIdx -eq $RightCursor)
                    $Marker = if ($IsSelected) { '►' } else { ' ' }

                    $LeftStat = if ($null -eq $Test.NewPassed) { 'N/A ' }
                    elseif ($Test.NewPassed) { 'PASS' }
                    else { 'FAIL' }
                    $RightStat = if ($null -eq $Test.OldPassed) { 'N/A ' }
                    elseif ($Test.OldPassed) { 'PASS' }
                    else { 'FAIL' }

                    $Icon = switch ($Test.Status) {
                        'Improved' { '[+]' }
                        'Regressed' { '[-]' }
                        'New' { '[*]' }
                        'Removed' { '[x]' }
                        default { '   ' }
                    }
                    $RightColor = switch ($Test.Status) {
                        'Improved' { Resolve-ThemeColor $Theme.Pass }
                        'Regressed' { Resolve-ThemeColor $Theme.Fail }
                        'New' { Resolve-ThemeColor $Theme.Primary }
                        'Removed' { [System.ConsoleColor]::DarkGray }
                        default { [System.ConsoleColor]::White }
                    }

                    $Name = if ($Test.TestName.Length -gt $NameW) {
                        $Test.TestName.Substring(0, $NameW - 3) + '...'
                    }
                    else {
                        $Test.TestName.PadRight($NameW)
                    }
                    $Num = "$($ItemIdx + 1).".PadLeft(4)
                    $RightText = "$Marker $Num  $Name  $($LeftStat.PadRight($ColNew))  $($RightStat.PadRight($ColOld))  $Icon"
                }
            }

            [System.Console]::ForegroundColor = $RightColor
            [System.Console]::Write($RightText.PadRight($RightW))
            [System.Console]::ForegroundColor = $OldFg
        }

        # ── Status box ──────────────────────────────────────────────────────────
        $NavHint = '  ←/→: switch panel  ↑/↓: navigate  Enter: select/drill-down  B/⌫: back  Q: quit'
        Show-StatusBox -Lines @('', $NavHint) -StartY ($StartY + 3 + $ContentH)
        [System.Console]::ResetColor()
        [System.Console]::SetCursorPosition(0, $StartY + 5 + $ContentH)

        # ── Key input ───────────────────────────────────────────────────────────
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
                    if ($RightCursor -lt ($TotalItems - 1)) { $RightCursor++ }
                }
            }
            'Enter' {
                if ($ActivePanel -eq 'Left') {
                    switch ($LeftCursor) {
                        0 { $DiffFilter = 'All'; $RightScroll = 0; $RightCursor = 0 }
                        1 { $DiffFilter = 'SameOnly'; $RightScroll = 0; $RightCursor = 0 }
                        2 { $DiffFilter = 'DiffOnly'; $RightScroll = 0; $RightCursor = 0 }
                        3 { $KeepGoing = $false }
                        4 { $script:SageQuit = $true; $KeepGoing = $false }
                    }
                }
                else {
                    if ($TotalItems -gt 0 -and $RightCursor -lt $TotalItems) {
                        Invoke-DiffDrillDown -TestDiff $Sorted[$RightCursor] -RunLeft $RunB -RunRight $RunA -LeftLabel $NewerDate -RightLabel $OlderDate -UseSpectre $UseSpectre
                        if ($script:SageQuit) { $KeepGoing = $false }
                    }
                }
            }
            'Backspace' { $KeepGoing = $false }
        }

        if ($KeepGoing) {
            switch ($Key.KeyChar.ToString().ToUpper()) {
                'A' { $DiffFilter = 'All'; $RightScroll = 0; $RightCursor = 0 }
                'S' { $DiffFilter = 'SameOnly'; $RightScroll = 0; $RightCursor = 0 }
                'D' { $DiffFilter = 'DiffOnly'; $RightScroll = 0; $RightCursor = 0 }
                'B' { $KeepGoing = $false }
                'Q' { $script:SageQuit = $true; $KeepGoing = $false }
            }
        }
    }
}

<#
.SYNOPSIS
    Shows a split-screen diff detail for a single test, A on the left, B on the right.
.DESCRIPTION
    Resolves the full TestResult from RunA and RunB for the given TestDiff and renders a
    side-by-side split: left panel shows run A result details, right panel shows run B
    result details.  Collector data is shown below the result details when the test failed.
.PARAMETER TestDiff
    The PSCustomObject diff entry from Compare-Results.
.PARAMETER RunA
    Optional older run object with .Summary and .Path properties.
.PARAMETER RunB
    Optional newer run object with .Summary and .Path properties.
.PARAMETER UseSpectre
    Kept for API compatibility; split-pane rendering is always used.
.OUTPUTS
    [void]
.EXAMPLE
    Invoke-DiffDrillDown -TestDiff $Diff.TestDiffs[0] -RunA $RunA -RunB $RunB
#>
function Invoke-DiffDrillDown {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UseSpectre',
        Justification = 'UseSpectre kept for API compatibility; split-pane rendering is always used.')]
    param(
        [Parameter(Mandatory)]                                                           [object] $TestDiff,
        [Parameter()]                                                                 [object] $RunLeft = $null,
        [Parameter()]                                                                [object] $RunRight = $null,
        [Parameter()]                                                                [string] $LeftLabel = 'Newer run',
        [Parameter()]                                                               [string] $RightLabel = 'Older run',
        [Parameter()]                                                                      [bool] $UseSpectre = $false
    )

    $ErrorActionPreference = 'Stop'

    # Resolve full test results from each run
    $ResultLeft = $null
    $ResultRight = $null
    $PathLeft = $null
    $PathRight = $null

    if ($RunLeft -and $RunLeft.Summary.TestResults) {
        $ResultLeft = $RunLeft.Summary.TestResults | Where-Object {
            $_.Category -eq $TestDiff.Category -and $_.TestName -eq $TestDiff.TestName
        } | Select-Object -First 1
        $PathLeft = $RunLeft.Path
    }
    if ($RunRight -and $RunRight.Summary.TestResults) {
        $ResultRight = $RunRight.Summary.TestResults | Where-Object {
            $_.Category -eq $TestDiff.Category -and $_.TestName -eq $TestDiff.TestName
        } | Select-Object -First 1
        $PathRight = $RunRight.Path
    }

    # Helper: load collector display lines for a result (from .md file)
    $GetCollectorLines = {
        param([object] $Res, [string] $Path)
        if (-not $Res -or -not $Path) { return @() }
        $SafeCat = $Res.Category -replace '[^\w\-.]', '' -replace '\s+', '_'
        $FileName = "$($Res.TargetName)-${SafeCat}-collector.md"
        $File = Get-ChildItem -Path $Path -Filter $FileName -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($File -and (Test-Path $File)) {
            $Content = Get-Content -Path $File -Raw -Encoding utf8 -ErrorAction SilentlyContinue
            if ($Content) {
                $RawLines = @($Content -split '[\r\n]+' | ForEach-Object { $_.TrimEnd() })
                return ConvertFrom-CollectorMarkdown -Lines $RawLines -Theme (Get-ActiveTheme)
            }
        }
        return @()
    }

    $CollLeft = & $GetCollectorLines $ResultLeft $PathLeft
    $CollRight = & $GetCollectorLines $ResultRight $PathRight

    # Helper: build display lines for one side
    $BuildSideLines = {
        param([object] $Res, $Coll)
        $T = Get-ActiveTheme
        $Lines = [System.Collections.Generic.List[hashtable]]::new()
        if (-not $Res) {
            $Lines.Add(@{ Text = '(not in this run)'; Color = [System.ConsoleColor]::DarkGray })
            return $Lines
        }
        $St = if ($Res.Passed) { 'PASS' } else { 'FAIL' }
        $Clr = if ($Res.Passed) { $T.Pass } else { $T.Fail }
        $Lines.Add(@{ Text = "Status  : $St"; Color = $Clr })
        $Lines.Add(@{ Text = "Points  : $($Res.FinalGrade) / $($Res.PassGrade)"; Color = [System.ConsoleColor]::White })
        if (-not $Res.Passed) {
            if ($Res.ExpectedValue) { $Lines.Add(@{ Text = "Expected: $($Res.ExpectedValue)"; Color = $T.Pass }) }
            if ($Res.ActualValue) { $Lines.Add(@{ Text = "Actual  : $($Res.ActualValue)"; Color = $Clr }) }
            if ($Res.ErrorMessage) {
                $DisplayError = $Res.ErrorMessage
                if ($Res.ExpectedValue -and $DisplayError -match 'Expected a value') {
                    $DisplayError = $DisplayError -replace 'Expected a value', "Expected '$($Res.ExpectedValue)'"
                }
                $Lines.Add(@{ Text = "Error   : $DisplayError"; Color = $T.Warn })
            }
        }
        if ($Coll -and $Coll.Count -gt 0) {
            $Lines.Add(@{ Text = ''; Color = [System.ConsoleColor]::DarkGray })
            $Lines.Add(@{ Text = '──────────────────────────────'; Color = [System.ConsoleColor]::DarkGray })
            foreach ($CLine in $Coll) {
                $Lines.Add($CLine)
            }
        }
        return $Lines
    }

    $LinesLeft = & $BuildSideLines $ResultLeft $CollLeft
    $LinesRight = & $BuildSideLines $ResultRight $CollRight

    $WrapText = {
        param(
            [Parameter()][AllowEmptyString()]                                             [string] $Text,
            [Parameter(Mandatory)][ValidateRange(1, 500)]                                  [int] $Width
        )

        if ([string]::IsNullOrEmpty($Text)) {
            return @('')
        }

        # Detect where continuation lines should be indented
        # For key-value pairs like "  Key:    Value", align to where Value starts
        $ContinuationIndent = 0
        $KeyValueMatch = [regex]::Match($Text, '^\s*\w+:\s+')
        if ($KeyValueMatch.Success) {
            # Continuation lines indent to where the value starts
            $ContinuationIndent = $KeyValueMatch.Value.Length
        }
        else {
            # For non-key-value lines, extract leading whitespace
            $LeadingMatch = [regex]::Match($Text, '^\s*')
            $ContinuationIndent = if ($LeadingMatch.Success) { $LeadingMatch.Value.Length } else { 0 }
        }

        $Wrapped = [System.Collections.Generic.List[string]]::new()
        $Remaining = $Text
        $PrevContentLen = $Remaining.TrimStart().Length
        while ($Remaining.Length -gt $Width) {
            $Cut = $Remaining.LastIndexOf(' ', $Width)
            if ($Cut -lt 1) { $Cut = $Width }
            $Wrapped.Add($Remaining.Substring(0, $Cut).TrimEnd())
            $Remaining = $Remaining.Substring($Cut).TrimStart()
            # Indent continuation line to align with value start
            if ($Remaining.Length -gt 0 -and $ContinuationIndent -gt 0) {
                $Remaining = (' ' * $ContinuationIndent) + $Remaining
            }
            # Guard against infinite loop: stop if no progress on content length
            $ContentLen = $Remaining.TrimStart().Length
            if ($ContentLen -ge $PrevContentLen) { break }
            $PrevContentLen = $ContentLen
        }
        $Wrapped.Add($Remaining)
        return $Wrapped.ToArray()
    }

    $KeepGoing = $true
    $Scroll = 0
    while ($KeepGoing) {
        $HeaderLines = Show-SageHeader

        $WinH = try { [System.Console]::WindowHeight } catch { 40 }
        $WinW = try { [System.Console]::WindowWidth } catch { 80 }
        $HalfW = [int]($WinW / 2) - 2
        $ContentH = [Math]::Max(3, $WinH - $HeaderLines - 7)

        $WrappedLeft = [System.Collections.Generic.List[hashtable]]::new()
        $WrappedRight = [System.Collections.Generic.List[hashtable]]::new()
        $LeftWrapWidth = [Math]::Max(8, $HalfW - 2)
        $RightWrapWidth = [Math]::Max(8, $WinW - $HalfW - 3)
        foreach ($Line in $LinesLeft) {
            $Segments = & $WrapText -Text $Line.Text -Width $LeftWrapWidth
            foreach ($Segment in $Segments) {
                $WrappedLeft.Add(@{ Text = $Segment; Color = $Line.Color })
            }
        }
        foreach ($Line in $LinesRight) {
            $Segments = & $WrapText -Text $Line.Text -Width $RightWrapWidth
            foreach ($Segment in $Segments) {
                $WrappedRight.Add(@{ Text = $Segment; Color = $Line.Color })
            }
        }

        $OldFg = [System.Console]::ForegroundColor
        $StartY = $HeaderLines

        # Title row — dates only (no duplicate in content)
        [System.Console]::SetCursorPosition(0, $StartY)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkCyan
        [System.Console]::Write(("  $LeftLabel").PadRight($HalfW))
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(' │ ')
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkCyan
        [System.Console]::Write(("  $RightLabel").PadRight($WinW - $HalfW - 3))
        [System.Console]::ForegroundColor = $OldFg

        # Separator
        [System.Console]::SetCursorPosition(0, $StartY + 1)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('─' * $HalfW) + '─┼─' + ('─' * [Math]::Max(0, $WinW - $HalfW - 3)))
        [System.Console]::ForegroundColor = $OldFg

        # Clamp scroll
        $MaxLines = [Math]::Max($WrappedLeft.Count, $WrappedRight.Count)
        $MaxScroll = [Math]::Max(0, $MaxLines - $ContentH)
        if ($Scroll -lt 0) { $Scroll = 0 }
        if ($Scroll -gt $MaxScroll) { $Scroll = $MaxScroll }

        # Content rows (scrollable)
        for ($Row = 0; $Row -lt $ContentH; $Row++) {
            $RowY = $StartY + 2 + $Row
            $LineIdx = $Scroll + $Row
            [System.Console]::SetCursorPosition(0, $RowY)

            if ($LineIdx -lt $WrappedLeft.Count) {
                $LA = $WrappedLeft[$LineIdx]
                $LAText = $LA.Text
                [System.Console]::ForegroundColor = if ($LA.Color) { $LA.Color } else { [System.ConsoleColor]::White }
                [System.Console]::Write("  $($LAText.PadRight($HalfW - 2))")
            }
            else {
                [System.Console]::ForegroundColor = [System.ConsoleColor]::White
                [System.Console]::Write(' ' * $HalfW)
            }
            [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
            [System.Console]::Write(' │ ')

            $RightW = $WinW - $HalfW - 3
            if ($LineIdx -lt $WrappedRight.Count) {
                $LB = $WrappedRight[$LineIdx]
                $LBText = $LB.Text
                [System.Console]::ForegroundColor = if ($LB.Color) { $LB.Color } else { [System.ConsoleColor]::White }
                [System.Console]::Write($LBText.PadRight($RightW))
            }
            else {
                [System.Console]::ForegroundColor = [System.ConsoleColor]::White
                [System.Console]::Write(' ' * $RightW)
            }
            [System.Console]::ForegroundColor = $OldFg
        }

        # Status box
        $ScrollHint = if ($MaxLines -gt $ContentH) { '  ↑/↓: scroll  ' } else { '  ' }
        $NavHint = "${ScrollHint}B/⌫: back  Q: quit"
        Show-StatusBox -Lines @('', $NavHint) -StartY ($StartY + 2 + $ContentH)
        [System.Console]::ResetColor()

        # Key input
        $Key = Invoke-ReadKey
        switch ($Key.Key.ToString()) {
            'UpArrow' { if ($Scroll -gt 0) { $Scroll-- } }
            'DownArrow' { if ($Scroll -lt $MaxScroll) { $Scroll++ } }
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

