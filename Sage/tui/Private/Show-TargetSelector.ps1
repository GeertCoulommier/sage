#Requires -Version 7.5

<#
.SYNOPSIS
    Reads a single key from the console without echoing it.
.DESCRIPTION
    Wraps [System.Console]::ReadKey so the call site is mockable in Pester tests.
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
    Displays a split-pane target selection menu.
.DESCRIPTION
    Presents a left-right split screen: the left panel contains action buttons
    (All, None, Back, Quit) and the right panel lists all available targets
    with checkbox toggles.  The cursor starts at the top of the right panel.
    Use the Left/Right arrows to switch focus between panels.

    When the right panel is active:
      - Up/Down: navigate targets
      - Space: toggle the focused target
      - Enter: confirm selection

    When the left panel is active:
      - Up/Down: navigate actions
      - Enter: execute the highlighted action

    Global shortcuts (work from either panel): A=All, N=None, B=Back, Q=Quit.

    Falls back to Read-SpectreMultiSelection when UseSpectre is true.
.PARAMETER Targets
    Array of target name strings available in the exam.
.PARAMETER TuiConfig
    The TUI configuration hashtable with target connection details.
.PARAMETER UseSpectre
    Whether PwshSpectreConsole is available for rich rendering.
.PARAMETER PreselectedTargets
    Optional remembered target names to preselect on load.
.OUTPUTS
    [string[]] — Array of selected target names.
.EXAMPLE
    $Selected = Show-TargetSelector -Targets @('Linux','DC1','DC2','Client') -TuiConfig $Cfg
#>
function Show-TargetSelector {
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UseSpectre',
        Justification = 'UseSpectre is kept for API compatibility; selection always uses the split-pane menu.')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                 [string[]] $Targets,
        [Parameter(Mandatory)]                                                          [hashtable] $TuiConfig,
        [Parameter()]                                                                      [bool] $UseSpectre = $false,
        [Parameter()]                                                             [string[]] $PreselectedTargets = @()
    )

    $ErrorActionPreference = 'Stop'

    # ── Split-pane arrow-key menu ──────────────────────────────────────────────
    $Enabled = @{}
    $UsePreselected = $PreselectedTargets -and $PreselectedTargets.Count -gt 0
    foreach ($T in $Targets) {
        $Enabled[$T] = if ($UsePreselected) { $PreselectedTargets -contains $T } else { $true }
    }

    # Left-panel selectable action indices (0=All, 1=None, 2=Back, 3=Quit)
    $LeftActionCount = 4
    $LeftCursor = 0
    $ActivePanel = 'Right'
    $RightCursor = 0
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
        if ($Targets.Count -gt 0 -and $RightCursor -ge $Targets.Count) { $RightCursor = $Targets.Count - 1 }

        # ── Left panel row definitions ─────────────────────────────────────────
        $LeftRows = @(
            @{ Text = 'Actions'; Title = $true }
            @{ Text = ('─' * ($LeftW - 2)); Title = $true }
            @{ Text = 'All'; ActionId = 0 }
            @{ Text = 'None'; ActionId = 1 }
            @{ Text = ('─' * ($LeftW - 2)); Title = $true }
            @{ Text = 'Back'; ActionId = 2 }
            @{ Text = 'Quit'; ActionId = 3 }
        )
        # Row indices inside $LeftRows that map to selectable actions
        $LeftSelectableRows = @(2, 3, 5, 6)

        $MaxNameLen    = ($Targets | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        # Compute max primary connection width to align the 'Default connection' header
        $MaxPrimaryLen = 0
        foreach ($TgtName in $Targets) {
            $TgtCfg = $TuiConfig.Targets[$TgtName]
            if ($TgtCfg) {
                $PrimaryStr = "$($TgtCfg.PrimaryHostName):$($TgtCfg.Port)"
                if ($PrimaryStr.Length -gt $MaxPrimaryLen) { $MaxPrimaryLen = $PrimaryStr.Length }
            }
        }
        $PrimaryColW = [Math]::Max($MaxPrimaryLen, 'Default connection'.Length)
        # Content row prefix: "$Marker [$Mark] " = 6 chars — header must match
        $HdrPrefix = ' '.PadRight(6)
        $OldFg = [System.Console]::ForegroundColor
        $Theme = Get-ActiveTheme
        $StartY = $HeaderLines

        # ── Title row ──────────────────────────────────────────────────────────
        [System.Console]::SetCursorPosition(0, $StartY)
        [System.Console]::ForegroundColor = Resolve-ThemeColor $Theme.Primary
        [System.Console]::Write(('  Targets to evaluate:').PadRight($LeftW))
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(' │ ')
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        $HdrLine = "$HdrPrefix$('Target'.PadRight($MaxNameLen))  $('Default connection'.PadRight($PrimaryColW))  Fallback connection"
        [System.Console]::Write($HdrLine.PadRight($RightW))
        [System.Console]::ForegroundColor = $OldFg

        # ── Separator row ──────────────────────────────────────────────────────
        [System.Console]::SetCursorPosition(0, $StartY + 1)
        [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkGray
        [System.Console]::Write(('─' * $LeftW) + '─┼─' + ('─' * [Math]::Max(0, $RightW)))
        [System.Console]::ForegroundColor = $OldFg

        # ── Content rows ───────────────────────────────────────────────────────
        for ($Row = 0; $Row -lt $ContentH; $Row++) {
            $RowY = $StartY + 2 + $Row
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
            if ($Row -lt $Targets.Count) {
                $T = $Targets[$Row]
                $Tgt = $TuiConfig.Targets[$T]
                $Mark = if ($Enabled[$T]) { 'x' } else { ' ' }
                $IsSelected = ($ActivePanel -eq 'Right' -and $Row -eq $RightCursor)
                $Marker = if ($IsSelected) { '►' } else { ' ' }
                $Primary = "$($Tgt.PrimaryHostName):$($Tgt.Port)"
                $Fallback = if ($Tgt.FallbackHostName -and $Tgt.FallbackPort) {
                    "$($Tgt.FallbackHostName):$($Tgt.FallbackPort)"
                }
                else { '' }
                $Detail = if ($Fallback) { "$($Primary.PadRight($PrimaryColW))  $Fallback" } else { $Primary }
                $RightText = "$Marker [$Mark] $($T.PadRight($MaxNameLen))  $Detail"
                $RightColor = if ($Enabled[$T]) { [System.ConsoleColor]::White } else { [System.ConsoleColor]::DarkGray }
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
                    if ($RightCursor -lt ($Targets.Count - 1)) { $RightCursor++ }
                }
            }
            'Spacebar' {
                if ($ActivePanel -eq 'Right' -and $Targets.Count -gt 0) {
                    $CurTarget = $Targets[$RightCursor]
                    $Enabled[$CurTarget] = -not $Enabled[$CurTarget]
                }
            }
            'Enter' {
                if ($ActivePanel -eq 'Left') {
                    switch ($LeftCursor) {
                        0 { foreach ($T in $Targets) { $Enabled[$T] = $true } }
                        1 { foreach ($T in $Targets) { $Enabled[$T] = $false } }
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
                'A' { foreach ($T in $Targets) { $Enabled[$T] = $true } }
                'N' { foreach ($T in $Targets) { $Enabled[$T] = $false } }
                'B' { $GoBack = $true; $Done = $true }
                'Q' { $script:SageQuit = $true; $Done = $true }
            }
        }
    }

    if ($GoBack -or $script:SageQuit) { return @() }
    return @($Targets | Where-Object { $Enabled[$_] })
}
