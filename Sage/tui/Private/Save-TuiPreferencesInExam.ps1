#Requires -Version 7.5
<#
.SYNOPSIS
    Ensures the user TUI config exists, creating it from the vanilla config if needed.
.DESCRIPTION
    The vanilla tui/tui-config.psd1 is never written to by the TUI.  On the first
    modification, this function copies the vanilla config to data/config/tui-config-personal.psd1
    and returns the user config path.  On subsequent calls the user config path is
    returned immediately.
.PARAMETER VanillaConfigPath
    Absolute path to the read-only vanilla tui/tui-config.psd1.
.PARAMETER UserConfigPath
    Absolute path where personalised settings are stored (data/config/tui-config-personal.psd1).
.OUTPUTS
    [string] — Absolute path to the active user config file.
.EXAMPLE
    $ActiveConfig = Initialize-TuiUserConfig -VanillaConfigPath $V -UserConfigPath $U
#>
function Initialize-TuiUserConfig {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $VanillaConfigPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $UserConfigPath
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $UserConfigPath)) {
        $UserConfigDir = Split-Path $UserConfigPath -Parent
        if (-not (Test-Path $UserConfigDir)) {
            New-Item -ItemType Directory -Force -Path $UserConfigDir | Out-Null
        }
        Copy-Item -Path $VanillaConfigPath -Destination $UserConfigPath -Force
    }

    Sync-TuiExamDefinitionPathInConfig -VanillaConfigPath $VanillaConfigPath -UserConfigPath $UserConfigPath

    return $UserConfigPath
}

<#
.SYNOPSIS
    Keeps the personal TUI config aligned with the shipped exam definition path.
.DESCRIPTION
    The exam definition path is module metadata rather than a user preference.
    When the bundled exam file is renamed, older personal configs can keep a
    stale path and break self-check startup. This function updates the personal
    config to the current shipped path while preserving remembered settings.
.OUTPUTS
    [void]
.EXAMPLE
    Sync-TuiExamDefinitionPathInConfig -VanillaConfigPath $V -UserConfigPath $U
#>
function Sync-TuiExamDefinitionPathInConfig {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $VanillaConfigPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $UserConfigPath
    )

    $VanillaConfig = Import-PowerShellDataFile -Path $VanillaConfigPath
    $UserConfig = Import-PowerShellDataFile -Path $UserConfigPath

    $ExpectedExamDefinitionPath = [string] $VanillaConfig.ExamDefinitionPath
    if ([string]::IsNullOrWhiteSpace($ExpectedExamDefinitionPath)) {
        return
    }

    $CurrentExamDefinitionPath = [string] $UserConfig.ExamDefinitionPath
    $ExamBasePath = Split-Path $VanillaConfigPath -Parent
    $ResolvedCurrentExamPath = if ([string]::IsNullOrWhiteSpace($CurrentExamDefinitionPath)) {
        $null
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $ExamBasePath $CurrentExamDefinitionPath))
    }

    $NeedsUpdate =
    [string]::IsNullOrWhiteSpace($CurrentExamDefinitionPath) -or
    $CurrentExamDefinitionPath -ne $ExpectedExamDefinitionPath -or
    -not (Test-Path $ResolvedCurrentExamPath -PathType Leaf)

    if (-not $NeedsUpdate) {
        return
    }

    $Literal = "'$($ExpectedExamDefinitionPath -replace "'", "''")'"
    Set-RootStringSettingInConfigFile -ConfigPath $UserConfigPath -SettingName 'ExamDefinitionPath' -SettingLiteral $Literal
}

<#!
.SYNOPSIS
    Updates a root-level string setting in a PSD1 config file.
.DESCRIPTION
    Replaces an existing string literal assignment when present, or inserts the
    setting near the start of the root hashtable when it is missing.
.OUTPUTS
    [void]
.EXAMPLE
    Set-RootStringSettingInConfigFile -ConfigPath './tui-config.psd1' -SettingName 'ExamDefinitionPath' -SettingLiteral "'../data/exam.psd1'"
#>
function Set-RootStringSettingInConfigFile {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ConfigPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $SettingName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $SettingLiteral
    )

    $Lines = [System.IO.File]::ReadAllLines($ConfigPath)
    $Result = [System.Collections.Generic.List[string]]::new()
    $Updated = $false

    foreach ($Line in $Lines) {
        if (-not $Updated -and $Line -match "^\s*$([regex]::Escape($SettingName))\s*=") {
            $Indent = ([regex]::Match($Line, '^\s*')).Value
            $Result.Add("$Indent$SettingName = $SettingLiteral")
            $Updated = $true
            continue
        }

        $Result.Add($Line)
    }

    if (-not $Updated) {
        $InsertAt = 1
        if ($Lines.Length -gt 0 -and $Lines[0] -notmatch '^\s*@\{$') {
            for ($i = 0; $i -lt $Lines.Length; $i++) {
                if ($Lines[$i] -match '^\s*@\{$') {
                    $InsertAt = $i + 1
                    break
                }
            }
        }

        $Result.Insert($InsertAt, "    $SettingName = $SettingLiteral")
    }

    [System.IO.File]::WriteAllLines($ConfigPath, $Result, [System.Text.Encoding]::UTF8)
}

<#
.SYNOPSIS
    Saves remembered TUI preferences into tui/exam.psd1.
.DESCRIPTION
    Updates values under the Remembered hashtable in the TUI config file while
    preserving the remainder of the file. If the Remembered block is missing,
    it is inserted near the end of the root hashtable.
.OUTPUTS
    [void]
.EXAMPLE
    Save-DomainNameInExamConfig -ConfigPath './tui/exam.psd1' -DomainName 'geert'
#>
function Set-RememberedSettingInExamConfig {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ConfigPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $SettingName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $SettingLiteral
    )

    $ErrorActionPreference = 'Stop'

    $Lines = [System.IO.File]::ReadAllLines($ConfigPath)
    $Result = [System.Collections.Generic.List[string]]::new()

    $RememberedStart = -1
    for ($i = 0; $i -lt $Lines.Length; $i++) {
        if ($Lines[$i] -match '^\s*Remembered\s*=\s*@\{') {
            $RememberedStart = $i
            break
        }
    }

    if ($RememberedStart -lt 0) {
        $InsertAt = -1
        for ($i = $Lines.Length - 1; $i -ge 0; $i--) {
            if ($Lines[$i] -match '^\}$') {
                $InsertAt = $i
                break
            }
        }
        if ($InsertAt -lt 0) {
            throw "Could not find root hashtable closing brace in $ConfigPath"
        }

        for ($i = 0; $i -lt $Lines.Length; $i++) {
            if ($i -eq $InsertAt) {
                $Result.Add('')
                $Result.Add('    # ── Remembered TUI preferences ────────────────────────────────────────────')
                $Result.Add('    Remembered            = @{')
                $Result.Add("        $SettingName = $SettingLiteral")
                $Result.Add('    }')
            }
            $Result.Add($Lines[$i])
        }

        [System.IO.File]::WriteAllLines($ConfigPath, $Result, [System.Text.Encoding]::UTF8)
        return
    }

    $InRemembered = $false
    $Depth = 0
    $Updated = $false

    foreach ($Line in $Lines) {
        if (-not $InRemembered) {
            if ($Line -match '^\s*Remembered\s*=\s*@\{') {
                $InRemembered = $true
                $Depth = 1
                $Result.Add($Line)
                continue
            }
            $Result.Add($Line)
            continue
        }

        $Opens = ($Line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
        $Closes = ($Line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
        $NextDepth = $Depth + $Opens - $Closes

        if ($Line -match "^\s*$([regex]::Escape($SettingName))\s*=") {
            $Result.Add("        $SettingName = $SettingLiteral")
            $Updated = $true
            $Depth = $NextDepth
            continue
        }

        if ($NextDepth -le 0) {
            if (-not $Updated) {
                $Result.Add("        $SettingName = $SettingLiteral")
                $Updated = $true
            }
            $Result.Add($Line)
            $InRemembered = $false
            $Depth = $NextDepth
            continue
        }

        $Result.Add($Line)
        $Depth = $NextDepth
    }

    [System.IO.File]::WriteAllLines($ConfigPath, $Result, [System.Text.Encoding]::UTF8)
}

<#
.SYNOPSIS
    Converts a string array to a PSD1 array literal.
.DESCRIPTION
    Escapes single quotes and returns literals like @('A', 'B').
.OUTPUTS
    [string]
.EXAMPLE
    ConvertTo-Psd1StringArrayLiteral -Values @('Linux','DC1')
#>
function ConvertTo-Psd1StringArrayLiteral {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]                                                                   [string[]] $Values = @()
    )

    if (-not $Values -or $Values.Count -eq 0) {
        return '@()'
    }

    $Escaped = @()
    foreach ($Value in $Values) {
        $Escaped += "'$($Value -replace "'", "''")'"
    }

    return "@($($Escaped -join ', '))"
}

<#
.SYNOPSIS
    Saves the remembered domain name to tui/exam.psd1.
.OUTPUTS
    [void]
.EXAMPLE
    Save-DomainNameInExamConfig -ConfigPath './tui/exam.psd1' -DomainName 'geert'
#>
function Save-DomainNameInExamConfig {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ConfigPath,
        [Parameter(Mandatory)]                                                              [string] $DomainName
    )

    $Literal = "'$($DomainName -replace "'", "''")'"
    Set-RememberedSettingInExamConfig -ConfigPath $ConfigPath -SettingName 'DomainName' -SettingLiteral $Literal
}

<#
.SYNOPSIS
    Saves remembered selected targets to tui/exam.psd1.
.OUTPUTS
    [void]
.EXAMPLE
    Save-SelectedTargetsInExamConfig -ConfigPath './tui/exam.psd1' -Targets @('Linux')
#>
function Save-SelectedTargetsInExamConfig {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ConfigPath,
        [Parameter()]                                                                   [string[]] $Targets = @()
    )

    $Literal = ConvertTo-Psd1StringArrayLiteral -Values $Targets
    Set-RememberedSettingInExamConfig -ConfigPath $ConfigPath -SettingName 'SelectedTargets' -SettingLiteral $Literal
}

<#
.SYNOPSIS
    Saves remembered selected categories to tui/exam.psd1.
.OUTPUTS
    [void]
.EXAMPLE
    Save-SelectedCategoriesInExamConfig -ConfigPath './tui/exam.psd1' -Categories @('DNS DC1')
#>
function Save-SelectedCategoriesInExamConfig {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ConfigPath,
        [Parameter()]                                                                [string[]] $Categories = @()
    )

    $Literal = ConvertTo-Psd1StringArrayLiteral -Values $Categories
    Set-RememberedSettingInExamConfig -ConfigPath $ConfigPath -SettingName 'SelectedCategories' -SettingLiteral $Literal
}

<#
.SYNOPSIS
    Saves preferred fallback-first target names to tui/exam.psd1.
.OUTPUTS
    [void]
.EXAMPLE
    Save-PreferFallbackTargetsInExamConfig -ConfigPath './tui/tui-config.psd1' -Targets @('Linux')
#>
function Save-PreferFallbackTargetsInExamConfig {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ConfigPath,
        [Parameter()]                                                                   [string[]] $Targets = @()
    )

    $Literal = ConvertTo-Psd1StringArrayLiteral -Values $Targets
    Set-RememberedSettingInExamConfig -ConfigPath $ConfigPath -SettingName 'PreferFallbackTargets' -SettingLiteral $Literal
}

<#
.SYNOPSIS
    Saves the remembered output directory to tui/tui-config.psd1.
.OUTPUTS
    [void]
.EXAMPLE
    Save-OutputDirInExamConfig -ConfigPath './tui/tui-config.psd1' -OutputDir './output'
#>
function Save-OutputDirInExamConfig {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ConfigPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $OutputDir
    )

    $Literal = "'$($OutputDir -replace "'", "''")'"
    Set-RememberedSettingInExamConfig -ConfigPath $ConfigPath -SettingName 'OutputDir' -SettingLiteral $Literal
}

<#
.SYNOPSIS
    Updates a single connection property for a target in tui/tui-config.psd1.
.DESCRIPTION
    Replaces the value of a Targets.<TargetName>.<PropertyName> entry in the
    config file while preserving all other content.  Supported property names:
    PrimaryHostName, FallbackHostName, Port, FallbackPort.
.OUTPUTS
    [void]
.EXAMPLE
    Set-TargetConnectionInConfigFile -ConfigPath './tui/tui-config.psd1' -TargetName 'DC1' -PropertyName 'PrimaryHostName' -NewValue '10.0.0.1'
#>
function Set-TargetConnectionInConfigFile {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ConfigPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TargetName,
        [Parameter(Mandatory)][ValidateSet('PrimaryHostName', 'FallbackHostName', 'Port', 'FallbackPort')]
        [string] $PropertyName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $NewValue
    )

    $ErrorActionPreference = 'Stop'

    $Lines = [System.IO.File]::ReadAllLines($ConfigPath)
    $Result = [System.Collections.Generic.List[string]]::new()

    # Literal for the value: validated integers for Port/FallbackPort,
    # quoted strings for host names.
    $Literal = if ($PropertyName -in @('Port', 'FallbackPort')) {
        $ParsedPort = 0
        if (-not [int]::TryParse($NewValue, [ref]$ParsedPort)) {
            throw "Value for $PropertyName must be a whole number. Received '$NewValue'."
        }
        if ($ParsedPort -lt 1 -or $ParsedPort -gt 65535) {
            throw "Value for $PropertyName must be between 1 and 65535. Received '$NewValue'."
        }

        "$ParsedPort"
    }
    else {
        "'$($NewValue -replace "'", "''")'"
    }

    $InTargets = $false
    $InTargetBlock = $false
    $TargetDepth = 0
    $TargetsDepth = 0
    $Updated = $false

    foreach ($Line in $Lines) {
        $Opens = ($Line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
        $Closes = ($Line.ToCharArray() | Where-Object { $_ -eq '}' }).Count

        if (-not $InTargets) {
            if ($Line -match '^\s*Targets\s*=\s*@\{') {
                $InTargets = $true
                $TargetsDepth = 1
            }
            $Result.Add($Line)
            continue
        }

        # Inside Targets block
        if (-not $InTargetBlock) {
            if ($Line -match "^\s*$([regex]::Escape($TargetName))\s*=\s*@\{") {
                $InTargetBlock = $true
                $TargetDepth = 1
                $TargetsDepth += $Opens - $Closes
                $Result.Add($Line)
                continue
            }
        }
        else {
            # Inside the named target block
            if (-not $Updated -and $Line -match "^\s*$([regex]::Escape($PropertyName))\s*=") {
                $Indent = ($Line -replace '^(\s*).*', '$1')
                $Result.Add("$Indent$PropertyName  = $Literal")
                $Updated = $true
                $TargetDepth += $Opens - $Closes
                continue
            }
            $TargetDepth += $Opens - $Closes
            if ($TargetDepth -le 0) {
                $InTargetBlock = $false
            }
        }

        $TargetsDepth += $Opens - $Closes
        if ($TargetsDepth -le 0) { $InTargets = $false }
        $Result.Add($Line)
    }

    [System.IO.File]::WriteAllLines($ConfigPath, $Result, [System.Text.Encoding]::UTF8)
}
