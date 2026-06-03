#Requires -Version 7.5

<#
.SYNOPSIS
    Reads a single key from the console without echoing it.
.DESCRIPTION
    Local definition so unit tests can mock this function when loading only
    Show-CategoryDetail.ps1.  At runtime the definition from
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
    Displays the detailed test list for a single evaluation category.
.DESCRIPTION
    Shows a split-pane screen.  The left panel contains filter and navigation
    actions; the right panel lists individual tests coloured green (pass) or
    red (fail).  Press Enter on a test to drill down into full details.
.PARAMETER CategoryGrade
    The category grade object from Sage.StudentGradeSummary.CategoryGrades.
.PARAMETER Summary
    The full Sage.StudentGradeSummary for cross-referencing test results.
.PARAMETER OutputPath
    Path to the timestamped output directory (for loading collector data).
.PARAMETER UseSpectre
    Whether PwshSpectreConsole is available for rich rendering.
.OUTPUTS
    [void]
.EXAMPLE
    Show-CategoryDetail -CategoryGrade $CatGrade -Summary $Summary -OutputPath './output/...'
#>
function Show-CategoryDetail {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UseSpectre',
        Justification = 'UseSpectre kept for API compatibility; split-pane rendering is always used.')]
    param(
        [Parameter(Mandatory)]                                                           [object] $CategoryGrade,
        [Parameter(Mandatory)]                                                           [object] $Summary,
        [Parameter()]                                                                     [string] $OutputPath,
        [Parameter()]                                                                      [bool] $UseSpectre = $false
    )

    $ErrorActionPreference = 'Stop'

    $CatName = $CategoryGrade.Category
    $Tests = @($Summary.TestResults | Where-Object { $_.Category -eq $CatName })

    $Filter = 'All'
    $LeftActionCount = 5    # All, Pass, Fail, Back, Quit
    $LeftCursor = 0
    $ActivePanel = 'Right'
    $RightCursor = 0
    $KeepGoing = $true

    while ($KeepGoing) {
        $HeaderLines = Show-SageHeader

        # ── Filter tests ───────────────────────────────────────────────────────
        $Filtered = $Tests
        if ($Filter -eq 'Pass') { $Filtered = @($Tests | Where-Object { $_.Passed }) }
        elseif ($Filter -eq 'Fail') { $Filtered = @($Tests | Where-Object { -not $_.Passed }) }
        $TotalRows = $Filtered.Count

        # Clamp cursors
        if ($LeftCursor -lt 0) { $LeftCursor = 0 }
        if ($LeftCursor -ge $LeftActionCount) { $LeftCursor = $LeftActionCount - 1 }
        if ($RightCursor -lt 0) { $RightCursor = 0 }
        if ($TotalRows -gt 0 -and $RightCursor -ge $TotalRows) { $RightCursor = $TotalRows - 1 }

        # ── Category sub-header ────────────────────────────────────────────────
        $NormCapped = [math]::Round([Math]::Min(20.0, $CategoryGrade.NormalizedScore), 2)
        Write-Host "  Category: $CatName  |  $NormCapped / 20  ($($CategoryGrade.PassedCount) passed, $($CategoryGrade.FailedCount) failed)  Filter: $Filter" -ForegroundColor Cyan
        Write-Host ''

        # ── Split-pane rendering ───────────────────────────────────────────────
        $WinH = try { [System.Console]::WindowHeight } catch { 40 }
        $WinW = try { [System.Console]::WindowWidth } catch { 80 }
        $LeftW = [Math]::Max(24, [Math]::Min(28, [int]($WinW * 0.27)))
        $RightW = $WinW - $LeftW - 3
        $ContentH = [Math]::Max(3, $WinH - $HeaderLines - 10)

        # Scroll so cursor is visible
        $RightScroll = 0
        if ($RightCursor -lt $RightScroll) { $RightScroll = $RightCursor }
        if ($RightCursor -ge ($RightScroll + $ContentH)) { $RightScroll = $RightCursor - $ContentH + 1 }

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

        $MaxTestLen = if ($Filtered.Count -gt 0) {
            ($Filtered | ForEach-Object { $_.TestName.Length } | Measure-Object -Maximum).Maximum
        }
        else { 30 }
        $ColTest = [Math]::Max(30, [Math]::Min($MaxTestLen, $RightW - 22))
        $OldFg = [System.Console]::ForegroundColor
        $Theme = Get-ActiveTheme
        $StartY = $HeaderLines + 2

        # Title row
        [System.Console]::SetCursorPosition(0, $StartY)
        [System.Console]::ForegroundColor = Resolve-ThemeColor $Theme.Accent
        [System.Console]::Write(('  Tests:').PadRight($LeftW))
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(' │ ')
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        $RHdr = "  $('#'.PadRight(4))  $('Test'.PadRight($ColTest))  $('Points'.PadRight(10))  Status"
        [System.Console]::Write($RHdr.PadRight($RightW))
        [System.Console]::ForegroundColor = $OldFg

        # Separator
        [System.Console]::SetCursorPosition(0, $StartY + 1)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('─' * $LeftW) + '─┼─' + ('─' * [Math]::Max(0, $RightW)))
        [System.Console]::ForegroundColor = $OldFg

        # Content rows
        for ($Row = 0; $Row -lt $ContentH; $Row++) {
            $RowY = $StartY + 2 + $Row
            $RightIdx = $RightScroll + $Row
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
            if ($RightIdx -lt $TotalRows) {
                $Test = $Filtered[$RightIdx]
                $Status = if ($Test.Passed) { 'PASS' } else { 'FAIL' }
                $Points = "$($Test.FinalGrade) / $($Test.PassGrade)"
                $TestName = if ($Test.TestName.Length -gt $ColTest) {
                    $Test.TestName.Substring(0, $ColTest - 3) + '...'
                }
                else { $Test.TestName.PadRight($ColTest) }
                $Num = "$($RightIdx + 1).".PadLeft(4)
                $IsSelected = ($ActivePanel -eq 'Right' -and $RightIdx -eq $RightCursor)
                $Marker = if ($IsSelected) { '►' } else { ' ' }
                $RightText = "$Marker $Num  $TestName  $($Points.PadRight(10))  $Status"
                $RightColor = if ($Test.Passed) { Resolve-ThemeColor $Theme.Pass } else { Resolve-ThemeColor $Theme.Fail }
            }
            elseif ($TotalRows -eq 0 -and $Row -eq 0) {
                $RightText = '  No tests match the current filter.'
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
                    if ($RightCursor -lt ($TotalRows - 1)) { $RightCursor++ }
                }
            }
            'Enter' {
                if ($ActivePanel -eq 'Left') {
                    switch ($LeftCursor) {
                        0 { $Filter = 'All'; $RightCursor = 0 }
                        1 { $Filter = 'Pass'; $RightCursor = 0 }
                        2 { $Filter = 'Fail'; $RightCursor = 0 }
                        3 { $KeepGoing = $false }
                        4 { $script:SageQuit = $true; $KeepGoing = $false }
                    }
                }
                else {
                    if ($TotalRows -gt 0 -and $RightCursor -lt $TotalRows) {
                        Show-TestDetail -TestResult $Filtered[$RightCursor] -OutputPath $OutputPath -UseSpectre $UseSpectre
                        if ($script:SageQuit) { $KeepGoing = $false }
                    }
                }
            }
            'Backspace' { $KeepGoing = $false }
        }

        if ($KeepGoing) {
            switch ($Key.KeyChar.ToString().ToUpper()) {
                'A' { $Filter = 'All'; $RightCursor = 0 }
                'P' { $Filter = 'Pass'; $RightCursor = 0 }
                'F' { $Filter = 'Fail'; $RightCursor = 0 }
                'B' { $KeepGoing = $false }
                'Q' { $script:SageQuit = $true; $KeepGoing = $false }
            }
        }
    }
}

