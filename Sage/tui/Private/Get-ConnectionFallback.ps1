#Requires -Version 7.5
<#
.SYNOPSIS
    Saves fallback hostname/port for a target back into exam.psd1.
.DESCRIPTION
    Reads the exam.psd1 file line by line, locates the named target block, and
    inserts or updates the FallbackHostName and FallbackPort keys.  Preserves
    all comments and formatting in the rest of the file.
.PARAMETER ConfigPath
    Absolute path to the exam.psd1 file.
.PARAMETER TargetName
    The key name of the target block to update (e.g. 'Linux').
.PARAMETER FallbackHostName
    The public hostname or IP to store.
.PARAMETER FallbackPort
    The port number to store.
.OUTPUTS
    [void]
.EXAMPLE
    Save-FallbackInExamConfig -ConfigPath '/path/tui/exam.psd1' -TargetName 'Linux' -FallbackHostName 'host.example.com' -FallbackPort 20022
#>
function Save-FallbackInExamConfig {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]                                                           [string] $ConfigPath,
        [Parameter(Mandatory)]                                                           [string] $TargetName,
        [Parameter(Mandatory)]                                                           [string] $FallbackHostName,
        [Parameter(Mandatory)]                                                              [int] $FallbackPort
    )

    $ErrorActionPreference = 'Stop'

    $Lines  = [System.IO.File]::ReadAllLines($ConfigPath)
    $Result = [System.Collections.Generic.List[string]]::new()

    # ── Pre-scan: determine if FallbackHostName/FallbackPort already exist ─────
    $InPreScan       = $false
    $PreScanDepth    = 0
    $HasFallbackHost = $false
    $HasFallbackPort = $false

    foreach ($Line in $Lines) {
        if (-not $InPreScan) {
            if ($Line -match "^\s*$([regex]::Escape($TargetName))\s*=\s*@\{") {
                $InPreScan    = $true
                $PreScanDepth = 1
            }
            continue
        }
        $Opens       = ($Line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
        $Closes      = ($Line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
        $PreScanDepth = $PreScanDepth + $Opens - $Closes
        if ($PreScanDepth -le 0) { break }
        if ($Line -match '^\s*FallbackHostName\s*=') { $HasFallbackHost = $true }
        if ($Line -match '^\s*FallbackPort\s*=')     { $HasFallbackPort = $true }
    }

    # ── Rewrite pass ──────────────────────────────────────────────────────────
    $InTarget             = $false
    $Depth                = 0
    $FallbackHostInserted = $false
    $FallbackPortInserted = $false

    foreach ($Line in $Lines) {
        if (-not $InTarget) {
            if ($Line -match "^\s*$([regex]::Escape($TargetName))\s*=\s*@\{") {
                $InTarget             = $true
                $Depth                = 1
                $FallbackHostInserted = $false
                $FallbackPortInserted = $false
                $Result.Add($Line)
                continue
            }
            $Result.Add($Line)
            continue
        }

        # Count brace depth
        $Opens  = ($Line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
        $Closes = ($Line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
        $Depth  = $Depth + $Opens - $Closes

        if ($Depth -le 0) {
            # Closing brace of target block — flush any missing keys first
            if (-not $FallbackHostInserted) {
                $Result.Add("            FallbackHostName = '$FallbackHostName'")
            }
            if (-not $FallbackPortInserted) {
                $Result.Add("            FallbackPort     = $FallbackPort")
            }
            $InTarget = $false
            $Result.Add($Line)
            continue
        }

        # Replace existing FallbackHostName
        if ($Line -match '^\s*FallbackHostName\s*=') {
            $Result.Add("            FallbackHostName = '$FallbackHostName'")
            $FallbackHostInserted = $true
            continue
        }

        # Replace existing FallbackPort
        if ($Line -match '^\s*FallbackPort\s*=') {
            $Result.Add("            FallbackPort     = $FallbackPort")
            $FallbackPortInserted = $true
            continue
        }

        # Insert FallbackHostName after PrimaryHostName — only when NOT already in file
        if ($Line -match '^\s*PrimaryHostName\s*=' -and -not $HasFallbackHost -and -not $FallbackHostInserted) {
            $Result.Add($Line)
            $Result.Add("            FallbackHostName = '$FallbackHostName'")
            $FallbackHostInserted = $true
            continue
        }

        # Insert FallbackPort after Port — only when NOT already in file
        if ($Line -match '^\s*Port\s*=' -and -not $HasFallbackPort -and -not $FallbackPortInserted) {
            $Result.Add($Line)
            $Result.Add("            FallbackPort     = $FallbackPort")
            $FallbackPortInserted = $true
            continue
        }

        $Result.Add($Line)
    }

    [System.IO.File]::WriteAllLines($ConfigPath, $Result, [System.Text.Encoding]::UTF8)
    Write-Verbose "Saved fallback for '$TargetName' to '$ConfigPath'."
}

<#
.SYNOPSIS
    Tests SSH connectivity to each target and falls back to a saved or
    user-supplied alternate hostname when the primary is unreachable.
.DESCRIPTION
    For each enabled target:
      1. Tries the primary hostname from the TUI config (LAN IP).
      2. If that fails and a FallbackHostName is stored in exam.psd1, tries
         that automatically.
      3. If still unreachable, prompts the student for a public hostname and
         port.  The last entered hostname/port are offered as defaults for
         subsequent targets on the same machine.
      4. When the student provides fallback details, saves them to exam.psd1
         so they are used automatically on the next run.

    Returns a hashtable mapping target names to PSCustomObjects with HostName
    (string or $null), Port (int), and Status.
.PARAMETER TuiConfig
    The TUI configuration hashtable loaded from tui/exam.psd1.
.PARAMETER TuiConfigPath
    Absolute path to tui/exam.psd1.  Used to re-read saved fallbacks and to
    persist newly entered fallback details.
.PARAMETER Exam
    The validated exam definition hashtable from Import-ExamDefinition.
.PARAMETER EnabledTargets
    Array of target names to test.  Only these targets are probed.
.PARAMETER TimeoutSeconds
    SSH connection timeout in seconds.  Default: 5.
.PARAMETER UseSpectre
    When true, uses Read-SpectreText for prompts instead of Read-Host.
.OUTPUTS
    [hashtable] — Keys are target names; values are PSCustomObjects with
    HostName (string or $null), Port (int), and Status.
.EXAMPLE
    $Working = Get-ConnectionFallback -TuiConfig $Cfg -TuiConfigPath $CfgPath -Exam $Exam -EnabledTargets @('Linux','DC1')
    $Working['Linux'].HostName   # '192.168.1.2' or saved/user-supplied fallback
#>
function Get-ConnectionFallback {
    [CmdletBinding()]
    [OutputType([hashtable])]    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TuiConfig',
        Justification = 'TuiConfig structure is documented and may be used in future enhancements.')]    param(
        [Parameter(Mandatory)]                                                          [hashtable] $TuiConfig,
        [Parameter(Mandatory)]                                                           [string] $TuiConfigPath,
        [Parameter(Mandatory)]                                                          [hashtable] $Exam,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                 [string[]] $EnabledTargets,
        [Parameter()]         [ValidateRange(1, 60)]                                        [int] $TimeoutSeconds = 5,
        [Parameter()]                                                                      [bool] $UseSpectre = $false
    )

    $ErrorActionPreference = 'Stop'

    # Re-read config to pick up fallbacks saved during a previous run
    $FreshConfig = Import-PowerShellDataFile -Path $TuiConfigPath

    $Result           = @{}
    $LastFallbackHost = $null
    $LastFallbackPort = $null
    $PreferFallbackTargets = @()
    if ($FreshConfig.Remembered -and $FreshConfig.Remembered.PreferFallbackTargets) {
        foreach ($RememberedTarget in $FreshConfig.Remembered.PreferFallbackTargets) {
            if (-not [string]::IsNullOrWhiteSpace($RememberedTarget) -and $PreferFallbackTargets -notcontains $RememberedTarget) {
                $PreferFallbackTargets += $RememberedTarget
            }
        }
    }

    foreach ($TargetName in $EnabledTargets) {
        $TuiTarget  = $FreshConfig.Targets[$TargetName]
        $ExamTarget = $Exam.Targets[$TargetName]

        if (-not $TuiTarget -or -not $ExamTarget) {
            Write-Warning "Target '$TargetName' not found in configuration — skipped."
            $Result[$TargetName] = [PSCustomObject]@{
                HostName = $null
                Port     = 0
                Status   = 'NotFound'
            }
            continue
        }

        $PrimaryHost       = $TuiTarget.PrimaryHostName
        $Port              = $TuiTarget.Port
        $SavedFallback     = $TuiTarget.FallbackHostName
        $SavedFallbackPort = if ($TuiTarget.FallbackPort) { $TuiTarget.FallbackPort } else { $Port }
        $TrySavedFirst     = ($PreferFallbackTargets -contains $TargetName) -and -not [string]::IsNullOrWhiteSpace($SavedFallback)

        if ($TrySavedFirst) {
            Write-Host "  Connecting to $TargetName via preferred fallback (${SavedFallback}:$SavedFallbackPort)..." -ForegroundColor DarkGray
            $Connected = Test-SshConnection -HostName $SavedFallback -Port $SavedFallbackPort -TimeoutSeconds $TimeoutSeconds

            if ($Connected) {
                Write-Verbose "Target '$TargetName': connected via preferred fallback (${SavedFallback}:$SavedFallbackPort)."
                $Result[$TargetName] = [PSCustomObject]@{
                    HostName = $SavedFallback
                    Port     = $SavedFallbackPort
                    Status   = 'FallbackPreferred'
                }
                continue
            }

            Write-Warning "Target '$TargetName': preferred fallback ${SavedFallback}:$SavedFallbackPort is unreachable, trying primary."
        }

        # ── 1. Try primary ────────────────────────────────────────────────────
        Write-Host "  Connecting to $TargetName (${PrimaryHost}:$Port)..." -ForegroundColor DarkGray
        $Connected = Test-SshConnection -HostName $PrimaryHost -Port $Port -TimeoutSeconds $TimeoutSeconds

        if ($Connected) {
            Write-Verbose "Target '$TargetName': connected via primary (${PrimaryHost}:$Port)."
            $Result[$TargetName] = [PSCustomObject]@{
                HostName = $PrimaryHost
                Port     = $Port
                Status   = 'Primary'
            }
            continue
        }

        Write-Warning "Target '$TargetName': primary address ${PrimaryHost}:$Port is unreachable."

        # ── 2. Try saved fallback automatically (if any) ──────────────────────
        if ($SavedFallback -and -not $TrySavedFirst) {
            Write-Host "  Trying saved fallback: ${SavedFallback}:$SavedFallbackPort..." -ForegroundColor DarkGray
            $Connected = Test-SshConnection -HostName $SavedFallback -Port $SavedFallbackPort -TimeoutSeconds $TimeoutSeconds

            if ($Connected) {
                Write-Verbose "Target '$TargetName': connected via saved fallback (${SavedFallback}:$SavedFallbackPort)."
                $Result[$TargetName] = [PSCustomObject]@{
                    HostName = $SavedFallback
                    Port     = $SavedFallbackPort
                    Status   = 'Fallback'
                }
                if ($PreferFallbackTargets -notcontains $TargetName) {
                    $PreferFallbackTargets += $TargetName
                    try {
                        Save-PreferFallbackTargetsInExamConfig -ConfigPath $TuiConfigPath -Targets @($PreferFallbackTargets)
                    }
                    catch {
                        Write-Warning "Could not save preferred-fallback targets to exam.psd1: $($_.Exception.Message)"
                    }
                }
                continue
            }

            Write-Warning "Target '$TargetName': saved fallback ${SavedFallback}:$SavedFallbackPort also unreachable."
        }

        # ── 3. Prompt for fallback ────────────────────────────────────────────
        $DefaultHost = if ($LastFallbackHost) { $LastFallbackHost } elseif ($SavedFallback) { $SavedFallback } else { '' }
        $DefaultPort = if ($LastFallbackPort) { $LastFallbackPort } elseif ($SavedFallback) { $SavedFallbackPort } else { $Port }

        $FallbackHost = $null
        $FallbackPort = $DefaultPort

        if ($UseSpectre) {
            $FallbackHost = Read-SpectreText -Message "Public hostname or IP for '$TargetName'" -DefaultAnswer $DefaultHost -AllowEmpty
            if ([string]::IsNullOrWhiteSpace($FallbackHost)) { $FallbackHost = $DefaultHost }
        }
        else {
            $HostPrompt   = if ($DefaultHost) { "  Enter public hostname for '$TargetName' [default: $DefaultHost]" } else { "  Enter public hostname for '$TargetName' (or Enter to skip)" }
            $FallbackHost = Read-Host $HostPrompt
            if ([string]::IsNullOrWhiteSpace($FallbackHost)) { $FallbackHost = $DefaultHost }
        }

        if ([string]::IsNullOrWhiteSpace($FallbackHost)) {
            Write-Warning "Target '$TargetName': skipped (no fallback provided)."
            $Result[$TargetName] = [PSCustomObject]@{
                HostName = $null
                Port     = $Port
                Status   = 'Unreachable'
            }
            continue
        }

        if ($UseSpectre) {
            $PortInput    = Read-SpectreText -Message "Port for '$TargetName'" -DefaultAnswer "$DefaultPort" -AllowEmpty
            $FallbackPort = if ([string]::IsNullOrWhiteSpace($PortInput)) { $DefaultPort } else { [int]$PortInput }
        }
        else {
            $PortInput    = Read-Host "  Port for '$TargetName' [default: $DefaultPort]"
            $FallbackPort = if ([string]::IsNullOrWhiteSpace($PortInput)) { $DefaultPort } else { [int]$PortInput }
        }

        # Persist to exam.psd1 for future runs
        try {
            Save-FallbackInExamConfig -ConfigPath $TuiConfigPath -TargetName $TargetName -FallbackHostName $FallbackHost -FallbackPort $FallbackPort
            Write-Host "  Fallback for '$TargetName' saved to exam.psd1." -ForegroundColor DarkGray
        }
        catch {
            Write-Warning "Could not save fallback to exam.psd1: $($_.Exception.Message)"
        }

        # Remember for subsequent targets in this run
        $LastFallbackHost = $FallbackHost
        $LastFallbackPort = $FallbackPort

        # ── 4. Try user-supplied fallback ─────────────────────────────────────
        $Connected = Test-SshConnection -HostName $FallbackHost -Port $FallbackPort -TimeoutSeconds $TimeoutSeconds

        if ($Connected) {
            Write-Verbose "Target '$TargetName': connected via user input (${FallbackHost}:$FallbackPort)."
            $Result[$TargetName] = [PSCustomObject]@{
                HostName = $FallbackHost
                Port     = $FallbackPort
                Status   = 'UserInput'
            }
            if ($PreferFallbackTargets -notcontains $TargetName) {
                $PreferFallbackTargets += $TargetName
                try {
                    Save-PreferFallbackTargetsInExamConfig -ConfigPath $TuiConfigPath -Targets @($PreferFallbackTargets)
                }
                catch {
                    Write-Warning "Could not save preferred-fallback targets to exam.psd1: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Warning "Target '$TargetName': ${FallbackHost}:$FallbackPort is also unreachable."
            $Result[$TargetName] = [PSCustomObject]@{
                HostName = $null
                Port     = $FallbackPort
                Status   = 'Unreachable'
            }
        }
    }

    return $Result
}
