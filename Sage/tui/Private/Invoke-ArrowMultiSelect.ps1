#Requires -Version 7.5
<#
.SYNOPSIS
    Interactive multi-select (or single-select) menu using arrow keys and spacebar.
.DESCRIPTION
    Renders an item list with a cursor and selection checkboxes.  The student
    navigates with arrow keys, toggles selections with Space, and confirms with
    Enter.  Pressing Q cancels and returns an empty array.

    When the console input is redirected (non-interactive / test runner) the
    function immediately returns all non-greyed items as selected (multi-select)
    or the first item (single-select), without blocking on keyboard input.

    For unit testing, pass pre-built ConsoleKeyInfo objects via $_TestKeys to
    simulate user input without blocking the test runner.
.PARAMETER Items
    Array of display strings to show in the list.
.PARAMETER Title
    Header line displayed above the item list.
.PARAMETER InitialSelection
    Optional bool array (same length as Items) pre-seeding selection state.
    Defaults to all available (non-greyed) items selected for multi-select,
    and cursor on first item for single-select.
.PARAMETER GreyedItems
    Items in this list are shown in dark grey and cannot be toggled.
.PARAMETER SingleSelect
    When set, treats the menu as a single-select list (radio-button style).
    Space or Enter confirms the item under the cursor.
.PARAMETER _TestKeys
    Internal test hook.  Provide an array of ConsoleKeyInfo objects to replay
    as simulated keystrokes instead of reading from the real console.
.OUTPUTS
    [string[]] — Selected item strings; empty array if the user cancelled.
.EXAMPLE
    $Picks = Invoke-ArrowMultiSelect -Items @('Linux','DC1','DC2') -Title 'Targets:'
.EXAMPLE
    $Choice = Invoke-ArrowMultiSelect -Items @('Run','View','Quit') -SingleSelect $true
.EXAMPLE
    # Unit-test usage — simulate Enter on first item
    $Enter = [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::Enter, $false, $false, $false)
    $Result = Invoke-ArrowMultiSelect -Items @('A','B') -_TestKeys @($Enter)
#>
function Invoke-ArrowMultiSelect {
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'InitialSelection',
        Justification = 'Used conditionally in the initialization block below.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '',
        Justification = 'Invoke- prefix is intentional for a TUI interaction function.')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                 [string[]] $Items,
        [Parameter()]                                                                      [string] $Title = 'Select:',
        [Parameter()]                                                                      [bool[]] $InitialSelection,
        [Parameter()]                                                                    [string[]] $GreyedItems = @(),
        [Parameter()]                                                                        [bool] $SingleSelect = $false,
        [Parameter()]   [System.ConsoleKeyInfo[]]                                                   $_TestKeys = $null
    )

    $ErrorActionPreference = 'Stop'

    $Count   = $Items.Count
    $UseKeys = $_TestKeys

    # ── Non-interactive fallback ───────────────────────────────────────────────
    # When stdin is redirected or test keys are not provided and no raw console
    # is available, return defaults without blocking on ReadKey.
    $IsNonInteractive = [Console]::IsInputRedirected -or
                        ($null -eq $UseKeys -and $null -eq $Host.UI.RawUI)

    if ($IsNonInteractive -and $null -eq $UseKeys) {
        if ($SingleSelect) {
            return @($Items[0])
        }
        return @($Items | Where-Object { $GreyedItems -notcontains $_ })
    }

    # ── Initialise selection state ─────────────────────────────────────────────
    $Selected = [bool[]]::new($Count)

    if ($InitialSelection -and $InitialSelection.Count -eq $Count) {
        for ($i = 0; $i -lt $Count; $i++) {
            $Selected[$i] = $InitialSelection[$i]
        }
    }
    elseif (-not $SingleSelect) {
        # Default: all available items selected
        for ($i = 0; $i -lt $Count; $i++) {
            $Selected[$i] = $GreyedItems -notcontains $Items[$i]
        }
    }

    $Cursor   = 0
    $KeyIndex = 0
    $Done     = $false
    $Cancelled = $false

    # Calculate lines to draw so we can rewind cursor each redraw
    # Title + blank + items + blank + hint = Count + 4 lines
    $OriginRow = [Console]::CursorTop

    try {
        [Console]::CursorVisible = $false

        while (-not $Done) {
            # ── Redraw ─────────────────────────────────────────────────────────
            [Console]::SetCursorPosition(0, $OriginRow)

            Write-Host "  $Title" -ForegroundColor Cyan
            Write-Host ''

            for ($i = 0; $i -lt $Count; $i++) {
                $IsGreyed  = $GreyedItems -contains $Items[$i]
                $IsCursor  = $i -eq $Cursor

                if ($SingleSelect) {
                    $Mark = if ($IsCursor) { '►' } else { ' ' }
                }
                else {
                    $Mark = if ($Selected[$i]) { '■' } else { '□' }
                }

                $Arrow = if ($IsCursor) { '▶' } else { ' ' }
                $Line  = "  $Arrow [$Mark] $($Items[$i])"

                if ($IsGreyed) {
                    Write-Host $Line -ForegroundColor DarkGray
                }
                elseif ($IsCursor) {
                    Write-Host $Line -ForegroundColor Cyan
                }
                else {
                    Write-Host $Line
                }
            }

            Write-Host ''
            if ($SingleSelect) {
                Write-Host '  [↑↓] Navigate   [Enter] Select   [Q] Cancel' -ForegroundColor DarkGray
            }
            else {
                Write-Host '  [↑↓] Navigate   [Space] Toggle   [A] All   [N] None   [Enter] Confirm   [Q] Cancel' -ForegroundColor DarkGray
            }

            # ── Read next key ──────────────────────────────────────────────────
            $Key = if ($null -ne $UseKeys -and $KeyIndex -lt $UseKeys.Count) {
                $UseKeys[$KeyIndex]
                $KeyIndex++
            }
            else {
                [Console]::ReadKey($true)
            }

            switch ($Key.Key) {
                'UpArrow' {
                    $Cursor = ($Cursor - 1 + $Count) % $Count
                }
                'DownArrow' {
                    $Cursor = ($Cursor + 1) % $Count
                }
                'Spacebar' {
                    if (-not $SingleSelect) {
                        $IsGreyed = $GreyedItems -contains $Items[$Cursor]
                        if (-not $IsGreyed) {
                            $Selected[$Cursor] = -not $Selected[$Cursor]
                        }
                    }
                    else {
                        $Done = $true
                    }
                }
                'Enter' {
                    $Done = $true
                }
                'Q' {
                    $Done      = $true
                    $Cancelled = $true
                }
                'A' {
                    if (-not $SingleSelect) {
                        for ($i = 0; $i -lt $Count; $i++) {
                            if ($GreyedItems -notcontains $Items[$i]) {
                                $Selected[$i] = $true
                            }
                        }
                    }
                }
                'N' {
                    if (-not $SingleSelect) {
                        for ($i = 0; $i -lt $Count; $i++) {
                            $Selected[$i] = $false
                        }
                    }
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }

    if ($Cancelled) {
        return @()
    }

    if ($SingleSelect) {
        return @($Items[$Cursor])
    }

    $Result = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Count; $i++) {
        if ($Selected[$i]) {
            $Result.Add($Items[$i])
        }
    }
    return $Result.ToArray()
}
