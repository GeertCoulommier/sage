#Requires -Version 7.5
<#
.SYNOPSIS
    Displays the TUI settings menu.
.DESCRIPTION
    Shows a scrollable list of all TUI configuration values: domain name,
    connection targets (default/fallback/preferred), output directory, config
    editor shortcut, result cleaner, and theme selector.

    Navigation:
      Up/Down     — scroll through items
      Left/Right  — cycle sub-fields within a target item (default ↔ fallback)
      Enter       — edit the focused item (for editable items) or invoke action
      B / Backspace — go back
      Q — quit the TUI

    When tui-config.psd1 is present, domain name and target entries are
    shown above the static action items.
.PARAMETER TuiPath
    Path to the tui/ directory.
.PARAMETER OutputDir
    Current output directory path.
.PARAMETER UseSpectre
    Kept for API compatibility.  Navigation always uses the arrow-key menu.
.OUTPUTS
    [string] — 'Back' or 'QuitTui'.
.EXAMPLE
    Show-Settings -TuiPath '/home/student/sage/tui' -OutputDir './output'
#>
function Show-Settings {
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Show-Settings renders a settings menu — the plural noun is intentional.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UseSpectre',
        Justification = 'UseSpectre is kept for API compatibility; navigation always uses the arrow-key menu.')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TuiPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $OutputDir,
        [Parameter()]                                                                      [bool] $UseSpectre = $false,
        [Parameter()]                                                                      [string] $ConfigPath
    )

    $ErrorActionPreference = 'Stop'

    $ConfigFile = if ($ConfigPath) { $ConfigPath } else { Join-Path $TuiPath 'tui-config.psd1' }

    # ── Build the scrollable item list ─────────────────────────────────────────
    # Item types:
    #   'action'   — selectable, runs a named action
    #   'editable' — selectable, opens a prompt to change the value
    #   'header'   — non-selectable section label (skipped during Up/Down nav)
    #   'target'   — selectable, supports Tab sub-field focus (default/fallback)
    #   'nav'      — selectable, Back/Quit
    $BuildItems = {
        $Items = [System.Collections.Generic.List[hashtable]]::new()

        $Cfg = $null
        if (Test-Path $ConfigFile) {
            try { $Cfg = Import-PowerShellDataFile -Path $ConfigFile -ErrorAction SilentlyContinue }
            catch { $Cfg = $null }
        }

        # ── Always first: clear results ─────────────────────────────────────────
        $Items.Add(@{ Label = 'Clear all previous results'; Value = ''; Type = 'action'; Key = 'ClearResults' })

        # ── Dynamic items (domain + targets) when config present ────────────────
        if ($Cfg) {
            $Domain = if ($Cfg.Remembered -and $Cfg.Remembered.ContainsKey('DomainName')) {
                $Cfg.Remembered.DomainName
            }
            else { '' }
            $Items.Add(@{
                Label = 'Domain name'
                Value = if ($Domain) { $Domain } else { '(not set)' }
                Type  = 'editable'
                Key   = 'DomainName'
            })

            if ($Cfg.Targets -and $Cfg.TargetOrder) {
                $PreferFallback = if ($Cfg.Remembered -and $Cfg.Remembered.PreferFallbackTargets) {
                    @($Cfg.Remembered.PreferFallbackTargets)
                }
                else { @() }

                # Targets: section header (not selectable)
                $Items.Add(@{ Label = 'Targets'; Value = ''; Type = 'header'; Key = '' })

                foreach ($TgtName in $Cfg.TargetOrder) {
                    $TgtCfg = $Cfg.Targets[$TgtName]
                    if (-not $TgtCfg) { continue }
                    $PrimaryStr  = "$($TgtCfg.PrimaryHostName):$($TgtCfg.Port)"
                    $FallbackStr = if ($TgtCfg.FallbackHostName -and $TgtCfg.FallbackPort) {
                        "$($TgtCfg.FallbackHostName):$($TgtCfg.FallbackPort)"
                    }
                    else { '(none)' }
                    $Preferred = if ($PreferFallback -contains $TgtName) { 'fallback' } else { 'default' }
                    $Items.Add(@{
                        Label       = "  $TgtName"
                        Value       = ''
                        Type        = 'target'
                        Key         = "Target:$TgtName"
                        Default     = $PrimaryStr
                        Fallback    = $FallbackStr
                        Prefers     = $Preferred
                    })
                }
            }
        }

        # ── Static items ───────────────────────────────────────────────────────
        $EffOutputDir = $OutputDir
        if ($Cfg -and $Cfg.Remembered -and $Cfg.Remembered.ContainsKey('OutputDir')) {
            $EffOutputDir = $Cfg.Remembered.OutputDir
        }
        $Items.Add(@{
            Label = 'Output directory'
            Value = $EffOutputDir
            Type  = 'editable'
            Key   = 'OutputDir'
        })

        $Items.Add(@{ Label = 'Edit tui-config.psd1'; Value = ''; Type = 'action'; Key = 'EditConfig' })
        $ThemeName = if ($script:SageThemeName) { $script:SageThemeName } else { 'Default' }
        $Items.Add(@{ Label = 'Theme'; Value = $ThemeName; Type = 'action'; Key = 'Theme' })
        $Items.Add(@{ Label = 'Back';  Value = '';         Type = 'nav';    Key = 'Back'  })
        $Items.Add(@{ Label = 'Quit';  Value = '';         Type = 'nav';    Key = 'Quit'  })

        return $Items
    }

    $Items     = & $BuildItems
    $ItemCount = $Items.Count
    $Cursor    = 0
    $Scroll    = 0
    $SubFocus  = 0   # Tab sub-field focus within a 'target' item (0=name, 1=default, 2=fallback)
    $KeepGoing = $true

    # Helper: find next non-header item index from a given index (direction +1/-1)
    $NextSelectable = {
        param([int] $From, [int] $Dir, [int] $Count, [object[]] $ItemList)
        $Next = $From
        for ($Step = 0; $Step -lt $Count; $Step++) {
            $Next = $Next + $Dir
            if ($Next -lt 0) { $Next = 0; break }
            if ($Next -ge $Count) { $Next = $Count - 1; break }
            if ($ItemList[$Next].Type -ne 'header') { break }
        }
        return $Next
    }

    while ($KeepGoing) {
        $Items     = & $BuildItems
        $ItemCount = $Items.Count

        $HeaderLines = Show-SageHeader
        $WinH     = try { [System.Console]::WindowHeight } catch { 40 }
        $WinW     = try { [System.Console]::WindowWidth  } catch { 80 }
        $ContentH = [Math]::Max(3, $WinH - $HeaderLines - 6)
        $Theme    = Get-ActiveTheme

        # Clamp cursor and scroll
        if ($Cursor -lt 0)                  { $Cursor = 0 }
        if ($Cursor -ge $ItemCount)         { $Cursor = $ItemCount - 1 }
        if ($Cursor -lt $Scroll)            { $Scroll = $Cursor }
        if ($Cursor -ge $Scroll + $ContentH) { $Scroll = $Cursor - $ContentH + 1 }
        if ($Scroll -lt 0)                  { $Scroll = 0 }

        $OldFg  = [System.Console]::ForegroundColor
        $StartY = $HeaderLines

        [System.Console]::SetCursorPosition(0, $StartY)
        Write-SageColor -Color $Theme.Primary -Text '  Settings'
        Write-SageColor -Color $Theme.Muted   -Text "  $('─' * ([Math]::Max(0, $WinW - 4)))"

        $LabelW = [Math]::Max(20, [Math]::Min(28, [int]($WinW * 0.32)))
        $ValueW = $WinW - $LabelW - 8   # 4 leading + 2 marker + 2 separator

        for ($Row = 0; $Row -lt $ContentH; $Row++) {
            $ItemIdx = $Scroll + $Row
            [System.Console]::SetCursorPosition(0, $StartY + 2 + $Row)

            if ($ItemIdx -ge $ItemCount) {
                [System.Console]::Write(' ' * $WinW)
                continue
            }

            $Item     = $Items[$ItemIdx]
            $IsActive = ($ItemIdx -eq $Cursor)

            # Header items: non-selectable section label
            if ($Item.Type -eq 'header') {
                Write-SageColor -Color $Theme.Accent -Text ("  $($Item.Label):" ).PadRight($WinW) -NoNewline
                [System.Console]::ForegroundColor = $OldFg
                continue
            }

            $Marker = if ($IsActive) { '► ' } else { '  ' }

            $LabelColor = if ($IsActive)                { $Theme.Primary }
                          elseif ($Item.Type -eq 'nav') { $Theme.Muted   }
                          else                          { [System.ConsoleColor]::White }

            # Target items: multi-field display with Tab sub-focus
            if ($Item.Type -eq 'target') {
                $TgtSubFocus = if ($IsActive) { $SubFocus } else { 0 }
                $DefPart  = "default=$($Item.Default)"
                $FbkPart  = "fallback=$($Item.Fallback)"
                $PrefPart = "[prefers: $($Item.Prefers)]"

                $DefColor  = if ($TgtSubFocus -eq 1) { $Theme.Primary } else { [System.ConsoleColor]::DarkGray }
                $FbkColor  = if ($TgtSubFocus -eq 2) { $Theme.Primary } else { [System.ConsoleColor]::DarkGray }
                $DefMarker = if ($TgtSubFocus -eq 1) { '►' } else { ' ' }
                $FbkMarker = if ($TgtSubFocus -eq 2) { '►' } else { ' ' }

                $NamePart = "$Marker$($Item.Label.PadRight($LabelW))"
                Write-SageColor -Color $LabelColor -Text "  $NamePart" -NoNewline
                Write-SageColor -Color $DefColor   -Text "  $DefMarker$DefPart" -NoNewline
                Write-SageColor -Color $FbkColor   -Text "  $FbkMarker$FbkPart" -NoNewline
                Write-SageColor -Color $Theme.Muted -Text "  $PrefPart" -NoNewline
                $Written = 2 + 4 + $LabelW + 3 + $DefPart.Length + 3 + $FbkPart.Length + 2 + $PrefPart.Length
                [System.Console]::Write(' ' * [Math]::Max(0, $WinW - $Written))
                [System.Console]::ForegroundColor = $OldFg
                continue
            }

            $ValueColor = if ($IsActive)                { $Theme.Accent  }
                          elseif ($Item.Type -eq 'nav') { $Theme.Muted   }
                          else                          { [System.ConsoleColor]::DarkGray }

            $LabelText = $Item.Label.PadRight($LabelW)
            $ValueText = if ($Item.Value) {
                $V = $Item.Value
                if ($V.Length -gt $ValueW) { $V.Substring(0, $ValueW - 3) + '...' } else { $V }
            }
            else { '' }

            Write-SageColor -Color $LabelColor -Text "  $Marker$LabelText" -NoNewline
            if ($Item.Value) {
                Write-SageColor -Color $ValueColor -Text "  $ValueText" -NoNewline
            }
            [System.Console]::ForegroundColor = $OldFg
            $ValueExtra = if ($Item.Value) { 2 + [Math]::Min($ValueText.Length, $ValueW) } else { 0 }
            $Written    = 2 + 2 + $LabelW + $ValueExtra
            $Remaining  = [Math]::Max(0, $WinW - $Written)
            [System.Console]::Write(' ' * $Remaining)
        }

        [System.Console]::SetCursorPosition(0, $StartY + 2 + $ContentH)
        Write-SageColor -Color $Theme.Muted -Text "  $('─' * ([Math]::Max(0, $WinW - 4)))"
        $HintSuffix = if ($Items[$Cursor].Type -eq 'target') { '  ←/→: switch field' } else { '' }
        Write-SageColor -Color $Theme.Muted -Text "  ↑/↓: navigate  Enter: select/edit  ←/→: target field  B/⌫: back  Q: quit$HintSuffix"
        [System.Console]::ForegroundColor = $OldFg

        $Key = Invoke-ReadKey

        switch ($Key.Key.ToString()) {
            'UpArrow' {
                $SubFocus = 0
                $Cursor = & $NextSelectable -From $Cursor -Dir -1 -Count $ItemCount -ItemList $Items
            }
            'DownArrow' {
                $SubFocus = 0
                $Cursor = & $NextSelectable -From $Cursor -Dir 1 -Count $ItemCount -ItemList $Items
            }
            'LeftArrow' {
                if ($Items[$Cursor].Type -eq 'target') {
                    $SubFocus = ($SubFocus + 2) % 3
                }
            }
            'RightArrow' {
                if ($Items[$Cursor].Type -eq 'target') {
                    $SubFocus = ($SubFocus + 1) % 3
                }
            }
            'Backspace' { $KeepGoing = $false; return 'Back' }
            'Enter' {
                $Item = $Items[$Cursor]
                switch ($Item.Key) {
                    'DomainName' {
                        # Re-use the same domain name prompt logic as the initial setup
                        $NewVal = Invoke-DomainNamePrompt
                        if (-not [string]::IsNullOrWhiteSpace($NewVal)) {
                            if (Test-Path $ConfigFile) {
                                try { Save-DomainNameInExamConfig -ConfigPath $ConfigFile -DomainName $NewVal.Trim() }
                                catch { Write-Warning "Could not save domain name: $($_.Exception.Message)" }
                            }
                        }
                    }
                    { $_ -and $_.StartsWith('Target:') } {
                        $TgtName = $Item.Key.Substring(7)
                        $Cfg2    = if (Test-Path $ConfigFile) {
                            try { Import-PowerShellDataFile -Path $ConfigFile } catch { $null }
                        }
                        else { $null }
                        if ($Cfg2 -and $Cfg2.Targets -and $Cfg2.Targets[$TgtName]) {
                            $TgtCfg = $Cfg2.Targets[$TgtName]
                            switch ($SubFocus) {
                                1 {
                                    # Edit default connection
                                    $NewPH = Read-Host "  $TgtName default host (current: $($TgtCfg.PrimaryHostName))"
                                    if ($NewPH.Trim()) {
                                        try { Set-TargetConnectionInConfigFile -ConfigPath $ConfigFile -TargetName $TgtName -PropertyName 'PrimaryHostName' -NewValue $NewPH.Trim() }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                    $NewPP = Read-Host "  $TgtName default port (current: $($TgtCfg.Port))"
                                    if ($NewPP.Trim()) {
                                        try { Set-TargetConnectionInConfigFile -ConfigPath $ConfigFile -TargetName $TgtName -PropertyName 'Port' -NewValue $NewPP.Trim() }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                }
                                2 {
                                    # Edit fallback connection
                                    $NewFH = Read-Host "  $TgtName fallback host (current: $($TgtCfg.FallbackHostName))"
                                    if ($NewFH.Trim()) {
                                        try { Set-TargetConnectionInConfigFile -ConfigPath $ConfigFile -TargetName $TgtName -PropertyName 'FallbackHostName' -NewValue $NewFH.Trim() }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                    $NewFP = Read-Host "  $TgtName fallback port (current: $($TgtCfg.FallbackPort))"
                                    if ($NewFP.Trim()) {
                                        try { Set-TargetConnectionInConfigFile -ConfigPath $ConfigFile -TargetName $TgtName -PropertyName 'FallbackPort' -NewValue $NewFP.Trim() }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                }
                                default {
                                    # Edit all fields (original behaviour)
                                    $NewPH = Read-Host "  $TgtName default host (current: $($TgtCfg.PrimaryHostName))"
                                    if ($NewPH.Trim()) {
                                        try { Set-TargetConnectionInConfigFile -ConfigPath $ConfigFile -TargetName $TgtName -PropertyName 'PrimaryHostName' -NewValue $NewPH.Trim() }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                    $NewPP = Read-Host "  $TgtName default port (current: $($TgtCfg.Port))"
                                    if ($NewPP.Trim()) {
                                        try { Set-TargetConnectionInConfigFile -ConfigPath $ConfigFile -TargetName $TgtName -PropertyName 'Port' -NewValue $NewPP.Trim() }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                    $NewFH = Read-Host "  $TgtName fallback host (current: $($TgtCfg.FallbackHostName))"
                                    if ($NewFH.Trim()) {
                                        try { Set-TargetConnectionInConfigFile -ConfigPath $ConfigFile -TargetName $TgtName -PropertyName 'FallbackHostName' -NewValue $NewFH.Trim() }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                    $NewFP = Read-Host "  $TgtName fallback port (current: $($TgtCfg.FallbackPort))"
                                    if ($NewFP.Trim()) {
                                        try { Set-TargetConnectionInConfigFile -ConfigPath $ConfigFile -TargetName $TgtName -PropertyName 'FallbackPort' -NewValue $NewFP.Trim() }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                    $Cfg3 = if (Test-Path $ConfigFile) { try { Import-PowerShellDataFile -Path $ConfigFile } catch { $null } } else { $null }
                                    $Pref = if ($Cfg3 -and $Cfg3.Remembered -and $Cfg3.Remembered.PreferFallbackTargets) {
                                        @($Cfg3.Remembered.PreferFallbackTargets)
                                    }
                                    else { @() }
                                    $CurrentPref = if ($Pref -contains $TgtName) { 'fallback' } else { 'default' }
                                    $NewPref = Read-Host "  $TgtName preferred connection (current: $CurrentPref, enter 'fallback' or 'default')"
                                    if ($NewPref.Trim() -eq 'fallback' -and $Pref -notcontains $TgtName) {
                                        try { Save-PreferFallbackTargetsInExamConfig -ConfigPath $ConfigFile -Targets ($Pref + $TgtName) }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                    elseif ($NewPref.Trim() -eq 'default' -and $Pref -contains $TgtName) {
                                        try { Save-PreferFallbackTargetsInExamConfig -ConfigPath $ConfigFile -Targets @($Pref | Where-Object { $_ -ne $TgtName }) }
                                        catch { Write-Warning "Could not save: $($_.Exception.Message)" }
                                    }
                                }
                            }
                        }
                    }
                    'OutputDir' {
                        $Current = $Item.Value
                        $NewDir  = Read-Host "  Output directory (current: $Current)"
                        if (-not [string]::IsNullOrWhiteSpace($NewDir)) {
                            $NewDir = $NewDir.Trim()
                            if (-not (Test-Path $NewDir)) {
                                try { $null = New-Item -Path $NewDir -ItemType Directory -Force }
                                catch { Write-Warning "Could not create directory: $($_.Exception.Message)" }
                            }
                            if (Test-Path $ConfigFile) {
                                try { Save-OutputDirInExamConfig -ConfigPath $ConfigFile -OutputDir $NewDir }
                                catch { Write-Warning "Could not save output dir: $($_.Exception.Message)" }
                            }
                            $OutputDir = $NewDir
                        }
                    }
                    'EditConfig' {
                        if (Test-Path $ConfigFile) {
                            $Editor = if ($env:EDITOR) { $env:EDITOR } else { 'nano' }
                            & $Editor $ConfigFile
                        }
                        else {
                            Write-Host '  tui-config.psd1 not found.' -ForegroundColor Yellow
                        }
                    }
                    'ClearResults' {
                        $EffDir = $OutputDir
                        if (Test-Path $ConfigFile) {
                            $Cfg4 = try { Import-PowerShellDataFile -Path $ConfigFile -ErrorAction SilentlyContinue } catch { $null }
                            if ($Cfg4 -and $Cfg4.Remembered -and $Cfg4.Remembered.OutputDir) {
                                $EffDir = $Cfg4.Remembered.OutputDir
                                if (-not [System.IO.Path]::IsPathRooted($EffDir)) {
                                    $EffDir = [System.IO.Path]::GetFullPath((Join-Path $TuiPath $EffDir))
                                }
                            }
                        }
                        $Confirm = Read-Host '  Are you sure? This deletes all previous results. (y/N)'
                        if ($Confirm.Trim().ToUpper() -eq 'Y') {
                            if (Test-Path $EffDir) {
                                $Dirs = Get-ChildItem -Path $EffDir -Directory |
                                    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{6}$' }
                                foreach ($Dir in $Dirs) {
                                    Remove-Item -Path $Dir.FullName -Recurse -Force
                                }
                                Write-Host "  Cleared $($Dirs.Count) previous run(s)." -ForegroundColor Green
                            }
                            else {
                                Write-Host '  No output directory found.' -ForegroundColor Yellow
                            }
                        }
                    }
                    'Theme' {
                        $PickerResult = Show-ThemePicker -TuiPath $TuiPath -ConfigPath $ConfigFile
                        if ($PickerResult -eq 'QuitTui') {
                            $script:SageQuit = $true
                            $KeepGoing = $false
                            return 'QuitTui'
                        }
                    }
                    'Back' { $KeepGoing = $false; return 'Back' }
                    'Quit' { $script:SageQuit = $true; $KeepGoing = $false; return 'QuitTui' }
                }
            }
        }

        if ($KeepGoing) {
            switch ($Key.KeyChar.ToString().ToUpper()) {
                'B' { $KeepGoing = $false; return 'Back' }
                'Q' { $script:SageQuit = $true; $KeepGoing = $false; return 'QuitTui' }
            }
        }
    }

    return 'Back'
}
