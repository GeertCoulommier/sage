#Requires -Version 7.5

<#
.SYNOPSIS
    Reads a single key from the console without echoing it.
.DESCRIPTION
    Local definition so unit tests can mock this function when loading only
    Show-MainMenu.ps1.  At runtime the definition from Show-TargetSelector.ps1
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
    Displays the SAGE TUI main menu and handles navigation.
.DESCRIPTION
    Presents the main menu as an arrow-key navigable list.  The cursor starts
    at the first action and moves with Up/Down arrows.  Press Enter to select,
    Q to quit.  Returns the user's selection as a string constant.
.PARAMETER UseSpectre
    Kept for API compatibility.  Navigation always uses the arrow-key menu.
.PARAMETER SpectreAvailable
    Kept for API compatibility.
.PARAMETER LatestSummary
    Kept for API compatibility; the header reads from $script:SageLatestSummary.
.OUTPUTS
    [string] — One of: 'RunEvaluation', 'ViewLastResults', 'ViewPreviousRuns',
    'Settings', 'Quit'.
.EXAMPLE
    $Choice = Show-MainMenu -UseSpectre $false -SpectreAvailable $false
#>
function Show-MainMenu {
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UseSpectre',
        Justification = 'UseSpectre is kept for API compatibility; navigation always uses the arrow-key menu.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SpectreAvailable',
        Justification = 'SpectreAvailable is reserved for future renderer-specific enhancements.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LatestSummary',
        Justification = 'LatestSummary is kept for API compatibility; the header reads from $script:SageLatestSummary.')]
    param(
        [Parameter()]                                                                      [bool] $UseSpectre = $false,
        [Parameter()]                                                                      [bool] $SpectreAvailable = $false,
        [Parameter()]                                                                    [object] $LatestSummary = $null
    )

    $ErrorActionPreference = 'Stop'

    $MenuItems = [ordered]@{
        'Run Evaluation'     = 'RunEvaluation'
        'View Last Results'  = 'ViewLastResults'
        'View Previous Runs' = 'ViewPreviousRuns'
        'Settings'           = 'Settings'
        'Quit'               = 'Quit'
    }
    $MenuKeys = @($MenuItems.Keys)
    $MenuCount = $MenuKeys.Count
    $Cursor = 0
    $Done = $false
    $ReturnValue = $null

    while (-not $Done) {
        $HeaderLines = Show-SageHeader
        $WinH = try { [System.Console]::WindowHeight } catch { 40 }

        # ── Disclaimer ────────────────────────────────────────────────────────
        $Width = try { [System.Console]::WindowWidth - 4 } catch { 76 }
        if ($Width -lt 40) { $Width = 76 }
        $DisclaimerLines = @(
            ' This testing suite is provided as-is and does not guarantee test accuracy:',
            ' it tends to be accurate for PASSED tests, but might be to strict for FAILED ones, ',
            ' meaning your configuration might be correct, but not exactly match the expected output. ',
            ' It also can NOT provide predictions on the content of exams. '
        )

        $RowsAvailable = [Math]::Max(0, $WinH - $HeaderLines)
        if ($RowsAvailable -lt ($MenuCount + 9)) {
            $DisclaimerLines = @(
                ' This testing suite is provided as-is.'
            )
        }
        if ($RowsAvailable -lt ($MenuCount + 7)) {
            $DisclaimerLines = @()
        }

        if ($DisclaimerLines.Count -gt 0) {
            Write-Host "  ┌$('─' * $Width)┐" -ForegroundColor DarkGray
            foreach ($DLine in $DisclaimerLines) {
                Write-Host "  │ $($DLine.PadRight($Width - 1))│" -ForegroundColor DarkGray
            }
            Write-Host "  └$('─' * $Width)┘" -ForegroundColor DarkGray
        }
        Write-Host ''

        # ── Menu rows ─────────────────────────────────────────────────────────
        $Theme = Get-ActiveTheme
        for ($i = 0; $i -lt $MenuCount; $i++) {
            $Label = $MenuKeys[$i]
            $IsActive = ($i -eq $Cursor)
            $Marker = if ($IsActive) { '► ' } else { '  ' }
            $Color = if ($IsActive) { $Theme.Primary } else { [System.ConsoleColor]::White }
            Write-SageColor -Color $Color -Text "  $Marker$Label"
        }
        Write-Host ''
        Write-SageColor -Color $Theme.Muted -Text '  ↑/↓: navigate  Enter: select  Q: quit'

        # ── Key input ─────────────────────────────────────────────────────────
        $Key = Invoke-ReadKey

        switch ($Key.Key.ToString()) {
            'UpArrow' { if ($Cursor -gt 0) { $Cursor-- } }
            'DownArrow' { if ($Cursor -lt ($MenuCount - 1)) { $Cursor++ } }
            'Enter' {
                $ReturnValue = $MenuItems[$MenuKeys[$Cursor]]
                $Done = $true
            }
            'Backspace' {
                $ReturnValue = 'Quit'
                $Done = $true
            }
        }

        if (-not $Done) {
            switch ($Key.KeyChar.ToString().ToUpper()) {
                'Q' { $ReturnValue = 'Quit'; $Done = $true }
            }
        }
    }

    return $ReturnValue
}
