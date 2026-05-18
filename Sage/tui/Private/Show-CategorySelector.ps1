#Requires -Version 7.5

<#
.SYNOPSIS
    Reads a single key from the console without echoing it.
.DESCRIPTION
    Local definition so unit tests can mock this function when loading only
    Show-CategorySelector.ps1.  In production, Show-TargetSelector.ps1 is
    loaded afterward and its identical definition replaces this one.
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
    Displays a split-pane category selection menu grouped by target VM.
.DESCRIPTION
    Presents a left-right split screen.  The left panel contains action
    buttons (All, None, Back, Quit).  The right panel lists selectable
    evaluation categories organised under VM group headers (non-selectable).
    The cursor starts at the top selectable item in the right panel.

    Navigation:
      Left/Right arrows — switch active panel.
      Up/Down arrows    — move within the active panel.
      Space             — toggle the focused category.
      Enter             — confirm (right panel) or execute action (left panel).
      A / N             — select all / none (global shortcut).
    B / Backspace     — go back.
      Q                 — quit.
.PARAMETER Exam
    Validated exam definition hashtable.
.PARAMETER EnabledTargets
    Array of target names that are reachable and enabled.
.PARAMETER UseSpectre
    Kept for API compatibility; selection always uses the arrow-key toggle menu.
.PARAMETER PreselectedCategories
    Optional remembered category names to preselect on load.
.OUTPUTS
    [string[]] — Array of selected category names.
.EXAMPLE
    $Cats = Show-CategorySelector -Exam $Exam -EnabledTargets @('Linux','DC1')
#>
function Show-CategorySelector {
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UseSpectre',
        Justification = 'UseSpectre is kept for API compatibility; selection always uses the split-pane menu.')]
    param(
        [Parameter(Mandatory)]                                                          [hashtable] $Exam,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                 [string[]] $EnabledTargets,
        [Parameter()]                                                                      [bool] $UseSpectre = $false,
        [Parameter()]                                                          [string[]] $PreselectedCategories = @()
    )

    $ErrorActionPreference = 'Stop'

    $Available = @($Exam.Categories | Where-Object { $EnabledTargets -contains $_.Target })

    if ($Available.Count -eq 0) {
        Show-SageHeader | Out-Null
        Write-Host '  No categories available for the selected targets.' -ForegroundColor Yellow
        return @()
    }

    # ── Build display rows: VM headers + category items ────────────────────────
    # Group categories by target, preserving exam order
    $TargetOrder = [System.Collections.Generic.List[string]]::new()
    foreach ($Cat in $Available) {
        if (-not $TargetOrder.Contains($Cat.Target)) {
            $TargetOrder.Add($Cat.Target)
        }
    }

    # $DisplayRows: each entry is @{ Type='Header'|'Item'; Target=...; Cat=... }
    $DisplayRows = [System.Collections.Generic.List[hashtable]]::new()
    $SelectableIdxs = [System.Collections.Generic.List[int]]::new()   # indices of Item rows

    foreach ($TargetName in $TargetOrder) {
        $DisplayRows.Add(@{ Type = 'Header'; Target = $TargetName })
        foreach ($Cat in ($Available | Where-Object { $_.Target -eq $TargetName })) {
            $SelectableIdxs.Add($DisplayRows.Count)
            $DisplayRows.Add(@{ Type = 'Item'; Cat = $Cat })
        }
    }

    $SelectableCount = $SelectableIdxs.Count
    $TotalDisplay = $DisplayRows.Count

    # ── State ──────────────────────────────────────────────────────────────────
    $Enabled = @{}
    $UsePreselected = $PreselectedCategories -and $PreselectedCategories.Count -gt 0
    foreach ($Cat in $Available) {
        $Enabled[$Cat.Name] = if ($UsePreselected) { $PreselectedCategories -contains $Cat.Name } else { $true }
    }

    $LeftActionCount = 4
    $LeftCursor = 0
    $ActivePanel = 'Right'
    $RightCursor = 0          # index into $SelectableIdxs
    $RightScroll = 0          # first display row visible in viewport
    $Done = $false
    $GoBack = $false

    while (-not $Done) {
        $HeaderLines = Show-SageHeader
        $WinH = try { [System.Console]::WindowHeight } catch { 40 }
        $WinW = try { [System.Console]::WindowWidth } catch { 80 }

        $LeftW = [Math]::Max(24, [Math]::Min(28, [int]($WinW * 0.27)))
        $RightW = $WinW - $LeftW - 3
        $ContentH = [Math]::Max(5, $WinH - $HeaderLines - 5)

        # Clamp cursors
        if ($LeftCursor -lt 0) { $LeftCursor = 0 }
        if ($LeftCursor -ge $LeftActionCount) { $LeftCursor = $LeftActionCount - 1 }
        if ($RightCursor -lt 0) { $RightCursor = 0 }
        if ($SelectableCount -gt 0 -and $RightCursor -ge $SelectableCount) {
            $RightCursor = $SelectableCount - 1
        }

        # Keep selected item in viewport: find display row for RightCursor
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

        $LeftRows = @(
            @{ Text = 'Actions'; Title = $true }
            @{ Text = ('─' * ($LeftW - 2)); Title = $true }
            @{ Text = 'Selection'; Title = $true }
            @{ Text = 'All'; ActionId = 0 }
            @{ Text = 'None'; ActionId = 1 }
            @{ Text = ('─' * ($LeftW - 2)); Title = $true }
            @{ Text = 'Back'; ActionId = 2 }
            @{ Text = 'Quit'; ActionId = 3 }
        )
        $LeftSelectableRows = @(3, 4, 6, 7)

        $MaxNameLen = ($Available | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
        # Content prefix: "$Marker [$Mark] " = 6 chars — header must match
        $HdrPrefix = ' '.PadRight(6)
        $OldFg = [System.Console]::ForegroundColor
        $Theme = Get-ActiveTheme
        $StartY = $HeaderLines

        # ── Title row ──────────────────────────────────────────────────────────
        [System.Console]::SetCursorPosition(0, $StartY)
        [System.Console]::ForegroundColor = Resolve-ThemeColor $Theme.Primary
        [System.Console]::Write(('  Categories to evaluate:').PadRight($LeftW))
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(' │ ')
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(("$HdrPrefix$('Category'.PadRight($MaxNameLen))").PadRight($RightW))
        [System.Console]::ForegroundColor = $OldFg

        # ── Separator row ──────────────────────────────────────────────────────
        [System.Console]::SetCursorPosition(0, $StartY + 1)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('─' * $LeftW) + '─┼─' + ('─' * [Math]::Max(0, $RightW)))
        [System.Console]::ForegroundColor = $OldFg

        # ── Content rows ───────────────────────────────────────────────────────
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
                    $Marker = if ($IsActive) { '► ' } else { '  ' }
                    $LeftText = "$Marker$($LRow.Text)"
                    $LeftColor = if ($IsActive) { Resolve-ThemeColor $Theme.Primary } else { [System.ConsoleColor]::White }
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
                    $HLine = '─' * [Math]::Max(0, $RightW - $DRow.Target.Length - 5)
                    $RightText = "  ── $($DRow.Target) $HLine"
                    $RightColor = Resolve-ThemeColor $Theme.Accent
                }
                else {
                    $Cat = $DRow.Cat
                    $SelFlatIdx = $SelectableIdxs.IndexOf($DisplayIdx)
                    $IsSelected = ($ActivePanel -eq 'Right' -and $SelFlatIdx -eq $RightCursor)
                    $Mark = if ($Enabled[$Cat.Name]) { 'x' } else { ' ' }
                    $Marker = if ($IsSelected) { '►' } else { ' ' }
                    $RightText = "$Marker [$Mark] $($Cat.Name.PadRight($MaxNameLen))"
                    $RightColor = if ($Enabled[$Cat.Name]) { [System.ConsoleColor]::White } else { [System.ConsoleColor]::DarkGray }
                }
            }
            [System.Console]::ForegroundColor = $RightColor
            [System.Console]::Write($RightText.PadRight($RightW))
            [System.Console]::ForegroundColor = $OldFg
        }

        # ── Footer ─────────────────────────────────────────────────────────────
        [System.Console]::SetCursorPosition(0, $StartY + 2 + $ContentH)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('─' * $WinW).Substring(0, [Math]::Min($WinW, $WinW)))
        [System.Console]::SetCursorPosition(0, $StartY + 3 + $ContentH)
        $Footer = '  ←/→: panel  ↑/↓: navigate  Space: toggle  Enter: confirm  A: all  N: none  B/⌫: back  Q: quit'
        [System.Console]::Write($Footer.PadRight($WinW))
        [System.Console]::ResetColor()

        # ── Key input ──────────────────────────────────────────────────────────
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
            'Spacebar' {
                if ($ActivePanel -eq 'Right' -and $SelectableCount -gt 0) {
                    $CatDisplayIdx = $SelectableIdxs[$RightCursor]
                    $CurCatName = $DisplayRows[$CatDisplayIdx].Cat.Name
                    $Enabled[$CurCatName] = -not $Enabled[$CurCatName]
                }
            }
            'Enter' {
                if ($ActivePanel -eq 'Left') {
                    switch ($LeftCursor) {
                        0 { foreach ($Cat in $Available) { $Enabled[$Cat.Name] = $true } }
                        1 { foreach ($Cat in $Available) { $Enabled[$Cat.Name] = $false } }
                        2 { $GoBack = $true; $Done = $true }
                        3 { $script:SageQuit = $true; $Done = $true }
                    }
                }
                else {
                    $Done = $true
                }
            }
            'Backspace' { $GoBack = $true; $Done = $true }

        }

        if (-not $Done) {
            switch ($Key.KeyChar.ToString().ToUpper()) {
                'A' { foreach ($Cat in $Available) { $Enabled[$Cat.Name] = $true } }
                'N' { foreach ($Cat in $Available) { $Enabled[$Cat.Name] = $false } }
                'B' { $GoBack = $true; $Done = $true }
                'Q' { $script:SageQuit = $true; $Done = $true }
            }
        }
    }

    if ($GoBack -or $script:SageQuit) { return @() }
    return @($Available | Where-Object { $Enabled[$_.Name] } | ForEach-Object { $_.Name })
}
