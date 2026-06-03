#Requires -Version 7.5
<#
.SYNOPSIS
    Student self-evaluation TUI entry point.
.DESCRIPTION
    Launches the SAGE Self-Check terminal user interface.  Students navigate an
    interactive menu to select targets and categories, run evaluations against
    their VMs, and drill down into results with full feedback.

    The TUI loads a prebuilt exam definition from tui/tui-config.psd1, tests SSH
    connectivity to each target (LAN IP first, public DNS fallback), and
    orchestrates evaluation via the existing SAGE pipeline.

    Requires the SAGE module and tui/ directory to be present in the same
    repository.  Uses PwshSpectreConsole for rich rendering when available,
    with a plain-text fallback.
.PARAMETER TuiPath
    Path to the tui/ directory containing tui-config.psd1 and Private/ helpers.
    Defaults to the 'tui' folder in the module root.
.OUTPUTS
    [void]
.EXAMPLE
    Invoke-SelfCheck
    # Launches the interactive TUI.
.EXAMPLE
    Invoke-SelfCheck -TuiPath '/home/student/sage/tui'
    # Launches with a custom TUI directory.
#>
function Invoke-SelfCheck {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]                                                                      [string] $TuiPath
    )

    $ErrorActionPreference = 'Stop'

    # ── Resolve TUI directory ──────────────────────────────────────────────────
    if (-not $TuiPath) {
        $TuiPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tui'
    }

    if (-not (Test-Path $TuiPath)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.DirectoryNotFoundException]::new("TUI directory not found: $TuiPath"),
                'TuiDirectoryNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $TuiPath
            )
        )
    }

    # ── Dot-source TUI helpers ─────────────────────────────────────────────────
    $PrivateDir = Join-Path $TuiPath 'Private'
    foreach ($File in (Get-ChildItem -Path $PrivateDir -Filter '*.ps1' -Recurse)) {
        . $File.FullName
    }

    # ── Check for PwshSpectreConsole ───────────────────────────────────────────
    $UseSpectre = $null -ne (Get-Module -ListAvailable -Name 'PwshSpectreConsole')
    if ($UseSpectre) {
        Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        $UseSpectre = $null -ne (Get-Module -Name 'PwshSpectreConsole')
    }
    if (-not $UseSpectre) {
        Write-Host '  PwshSpectreConsole not found — using plain text mode.' -ForegroundColor Yellow
        Write-Host '  Install for a richer experience: Install-Module PwshSpectreConsole' -ForegroundColor Yellow
        Write-Host ''
    }

    # ── Load TUI configuration ─────────────────────────────────────────────────
    # Vanilla config: ships with the module, never written to.
    # User config:    data/config/tui-config-personal.psd1 — created on first modification.
    $VanillaTuiConfigPath = Join-Path $TuiPath 'tui-config.psd1'
    if (-not (Test-Path $VanillaTuiConfigPath)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new("TUI exam config not found: $VanillaTuiConfigPath"),
                'TuiConfigNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $VanillaTuiConfigPath
            )
        )
    }
    $ModuleRoot = [System.IO.Path]::GetFullPath((Join-Path $TuiPath '..'))
    $UserTuiConfigPath = Join-Path $ModuleRoot 'data' 'config' 'tui-config-personal.psd1'
    # Ensure the personal config exists before doing anything; create it from vanilla if needed.
    $TuiConfigPath = Initialize-TuiUserConfig -VanillaConfigPath $VanillaTuiConfigPath -UserConfigPath $UserTuiConfigPath
    $TuiConfig = Import-PowerShellDataFile -Path $TuiConfigPath

    # ── Load exam definition ───────────────────────────────────────────────────
    $ExamPath = Join-Path $TuiPath $TuiConfig.ExamDefinitionPath
    $ExamPath = [System.IO.Path]::GetFullPath($ExamPath)
    $Exam = Import-ExamDefinition -Path $ExamPath

    # ── Output directory ───────────────────────────────────────────────────────
    $OutputDir = if ($TuiConfig.Remembered -and $TuiConfig.Remembered.OutputDir) {
        $TuiConfig.Remembered.OutputDir
    }
    else {
        Join-Path $TuiPath 'output'
    }
    if (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
        $OutputDir = [System.IO.Path]::GetFullPath((Join-Path $TuiPath $OutputDir))
    }

    # ── Expose exam metadata to header renderer ───────────────────────────────
    $script:SageExamName = $Exam.Name
    $script:SageExamVersion = $Exam.Version
    $script:SageQuit = $false

    # ── Load theme ─────────────────────────────────────────────────────────────
    $script:SageThemeName = if ($TuiConfig.Remembered -and $TuiConfig.Remembered.Theme) {
        $TuiConfig.Remembered.Theme
    }
    else {
        'Default'
    }
    $script:SageTheme = if ($UseSpectre) {
        Get-SageThemeSpectre -ThemeName $script:SageThemeName
    }
    else {
        Get-SageTheme -ThemeName $script:SageThemeName
    }

    # Pre-load latest summary for header status bar on first menu render.
    $InitialPath = Get-LatestOutputPath -OutputDir $OutputDir
    if ($InitialPath) {
        $script:SageLatestSummary = Import-ResultSummary -OutputPath $InitialPath
    }

    # ── Main menu loop ─────────────────────────────────────────────────────────
    $LastResultPath = $null
    $DomainName = if ($TuiConfig.Remembered -and $TuiConfig.Remembered.DomainName) {
        $TuiConfig.Remembered.DomainName
    }
    else {
        $null
    }

    while (-not $script:SageQuit) {
        $Choice = Show-MainMenu -UseSpectre $UseSpectre

        switch ($Choice) {
            'RunEvaluation' {
                # Re-read config to pick up manual settings edits from previous screens.
                $TuiConfig = Import-PowerShellDataFile -Path $TuiConfigPath

                # ── Target selection ───────────────────────────────────────
                $AllTargets = if ($TuiConfig.TargetOrder) {
                    @($TuiConfig.TargetOrder | Where-Object { $Exam.Targets.ContainsKey($_) })
                }
                else {
                    @($Exam.Targets.Keys)
                }
                $RememberedTargets = if ($TuiConfig.Remembered -and $TuiConfig.Remembered.SelectedTargets) {
                    @($TuiConfig.Remembered.SelectedTargets | Where-Object { $AllTargets -contains $_ })
                }
                else {
                    @()
                }
                $EnabledTargets = Show-TargetSelector -Targets $AllTargets -TuiConfig $TuiConfig -UseSpectre $UseSpectre -PreselectedTargets $RememberedTargets

                if (-not $EnabledTargets -or $EnabledTargets.Count -eq 0) {
                    Write-Host '  No targets selected.' -ForegroundColor Yellow
                    continue
                }

                try {
                    Save-SelectedTargetsInExamConfig -ConfigPath $TuiConfigPath -Targets $EnabledTargets
                }
                catch {
                    Write-Warning "Could not save selected targets to tui-config.psd1: $($_.Exception.Message)"
                }

                # ── Connection check ───────────────────────────────────────
                # Re-read the active config path (may have just been initialised).
                $ConnInfo = Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $TuiConfigPath -Exam $Exam -EnabledTargets $EnabledTargets -UseSpectre $UseSpectre

                $ReachableTargets = @($ConnInfo.Keys | Where-Object { $ConnInfo[$_].HostName })
                if ($ReachableTargets.Count -eq 0) {
                    Write-Host '  No reachable targets. Check connectivity and try again.' -ForegroundColor Red
                    continue
                }

                # ── SSH key setup ──────────────────────────────────────────
                # Build a filtered ConnectionInfo containing only reachable targets.
                $ReachableConnInfo = @{}
                foreach ($RTarget in $ReachableTargets) {
                    $ReachableConnInfo[$RTarget] = $ConnInfo[$RTarget]
                }
                $KeySetupParams = @{
                    ConnectionInfo = $ReachableConnInfo
                    Exam           = $Exam
                }
                $SageKeyDir = Join-Path $TuiPath 'keys'
                if (Test-Path $SageKeyDir) {
                    $KeySetupParams['KeyDir'] = $SageKeyDir
                }

                try {
                    $AuthStatus = Invoke-SshKeySetup @KeySetupParams
                }
                catch {
                    Write-Host ''
                    Write-Host '  SSH key setup encountered an error:' -ForegroundColor Red
                    Write-Host "  $_" -ForegroundColor Red
                    Write-Host '  Troubleshooting:' -ForegroundColor Yellow
                    Write-Host '    - Verify SSH is installed and available in PATH' -ForegroundColor Gray
                    Write-Host '    - Check SSH connectivity: ssh user@host' -ForegroundColor Gray
                    Write-Host '    - Ensure password authentication is enabled on the target' -ForegroundColor Gray
                    Write-Host ''
                    Write-Host '  Press any key to continue...' -ForegroundColor Gray
                    $null = Read-Host ''
                    continue
                }

                # ── Keep only targets with working key authentication ────────
                $AuthenticatedTargets = @($ReachableTargets | Where-Object {
                        $AuthStatus.ContainsKey($_) -and $AuthStatus[$_].KeyAuthWorks
                    })

                if ($AuthenticatedTargets.Count -eq 0) {
                    Write-Host ''
                    Write-Host '  No targets have working SSH key authentication.' -ForegroundColor Red
                    Write-Host '  Troubleshooting:' -ForegroundColor Yellow
                    Write-Host '    - Check that the correct password was entered' -ForegroundColor Gray
                    Write-Host '    - Ensure the target allows password authentication' -ForegroundColor Gray
                    Write-Host '    - Verify the SSH port is correct and the target is reachable' -ForegroundColor Gray
                    Write-Host ''
                    $null = Read-Host '  Press Enter to return to the menu'
                    continue
                }

                $FilteredConnInfo = @{}
                foreach ($TargetName in $AuthenticatedTargets) {
                    $FilteredConnInfo[$TargetName] = $ConnInfo[$TargetName]
                }

                # ── Category selection ─────────────────────────────────────
                $RememberedCategories = if ($TuiConfig.Remembered -and $TuiConfig.Remembered.SelectedCategories) {
                    @($TuiConfig.Remembered.SelectedCategories)
                }
                else {
                    @()
                }
                $SelectedCategories = Show-CategorySelector -Exam $Exam -EnabledTargets $AuthenticatedTargets -UseSpectre $UseSpectre -PreselectedCategories $RememberedCategories

                if (-not $SelectedCategories -or $SelectedCategories.Count -eq 0) {
                    Write-Host '  No categories selected.' -ForegroundColor Yellow
                    continue
                }

                try {
                    Save-SelectedCategoriesInExamConfig -ConfigPath $TuiConfigPath -Categories $SelectedCategories
                }
                catch {
                    Write-Warning "Could not save selected categories to tui-config.psd1: $($_.Exception.Message)"
                }

                # ── Domain name prompt (Windows categories only) ────────────
                # Only ask when at least one selected category targets a Windows
                # server AND its Variables contain the <domainname> placeholder.
                $NeedsDomain = $false
                foreach ($CatName in $SelectedCategories) {
                    $CatDef = $Exam.Categories | Where-Object { $_.Name -eq $CatName } | Select-Object -First 1
                    if (-not $CatDef) { continue }

                    if ($CatDef.Variables) {
                        $Json = $CatDef.Variables | ConvertTo-Json -Depth 10 -Compress
                        if ($Json -match '<domainname>') {
                            $NeedsDomain = $true
                            break
                        }
                    }
                }

                if ($NeedsDomain -and [string]::IsNullOrWhiteSpace($DomainName)) {
                    $DomainName = Invoke-DomainNamePrompt
                    if ([string]::IsNullOrWhiteSpace($DomainName)) {
                        Write-Host '  Skipping domain-dependent categories.' -ForegroundColor Yellow
                        $DomainName = $null
                    }
                    else {
                        try {
                            Save-DomainNameInExamConfig -ConfigPath $TuiConfigPath -DomainName $DomainName
                        }
                        catch {
                            Write-Warning "Could not save domain name to tui-config.psd1: $($_.Exception.Message)"
                        }
                    }
                }

                # ── Run evaluation ─────────────────────────────────────────
                Write-Host ''
                Write-Host '  Running evaluation — please wait...' -ForegroundColor Cyan
                Write-Host '  (Scores are shown after all categories complete.)' -ForegroundColor DarkGray
                Write-Host ''

                $EvalParams = @{
                    Exam               = $Exam
                    ConnectionInfo     = $FilteredConnInfo
                    SelectedCategories = $SelectedCategories
                    OutputDir          = $OutputDir
                    DomainName         = $DomainName
                }
                $EvalResult = Invoke-LocalEvaluation @EvalParams

                $LastResultPath = $EvalResult.OutputPath

                if ($EvalResult.Error) {
                    Write-Host "  Evaluation failed: $($EvalResult.Error)" -ForegroundColor Red
                }
                else {
                    if ($EvalResult.Summary) {
                        $script:SageLatestSummary = $EvalResult.Summary
                    }
                    Show-ResultsSummary -Summary $EvalResult.Summary -OutputPath $EvalResult.OutputPath -UseSpectre $UseSpectre
                }
            }
            'ViewLastResults' {
                if (-not $LastResultPath) {
                    $LastResultPath = Get-LatestOutputPath -OutputDir $OutputDir
                }
                if (-not $LastResultPath) {
                    Write-Host '  No previous results found.' -ForegroundColor Yellow
                    continue
                }
                $Summary = Import-ResultSummary -OutputPath $LastResultPath
                if ($Summary) {
                    $script:SageLatestSummary = $Summary
                    Show-ResultsSummary -Summary $Summary -OutputPath $LastResultPath -UseSpectre $UseSpectre
                }
                else {
                    Write-Host '  Could not load results.' -ForegroundColor Yellow
                }
            }
            'ViewPreviousRuns' {
                Show-PreviousRuns -OutputDir $OutputDir -UseSpectre $UseSpectre
            }
            'Settings' {
                Show-Settings -TuiPath $TuiPath -OutputDir $OutputDir -UseSpectre $UseSpectre -ConfigPath $TuiConfigPath
                # Re-read config to pick up any changes made in Settings.
                $TuiConfig = Import-PowerShellDataFile -Path $TuiConfigPath
                if ($TuiConfig.Remembered -and $TuiConfig.Remembered.OutputDir) {
                    $NewOutputDir = $TuiConfig.Remembered.OutputDir
                    if (-not [System.IO.Path]::IsPathRooted($NewOutputDir)) {
                        $NewOutputDir = [System.IO.Path]::GetFullPath((Join-Path $TuiPath $NewOutputDir))
                    }
                    $OutputDir = $NewOutputDir
                }
                if ($TuiConfig.Remembered -and $TuiConfig.Remembered.Theme) {
                    $script:SageThemeName = $TuiConfig.Remembered.Theme
                    $script:SageTheme = if ($UseSpectre) {
                        Get-SageThemeSpectre -ThemeName $script:SageThemeName
                    }
                    else {
                        Get-SageTheme -ThemeName $script:SageThemeName
                    }
                }
            }
            'Quit' {
                return
            }
        }
    }
}

<#
.SYNOPSIS
    Prompts the student for a domain name and returns its base part.
.DESCRIPTION
    Accepts input in forms like 'voornaam' or 'voornaam.local'.
    For two-part domains, returns the first part (e.g. 'voornaam').
    For single-part input, asks for confirmation that '.local' was intended.
    For domains with more than two parts, warns and asks for confirmation.
.OUTPUTS
    [string] — The validated base domain name, or empty string if cancelled.
.EXAMPLE
    $Domain = Invoke-DomainNamePrompt
#>
function Invoke-DomainNamePrompt {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $ErrorActionPreference = 'Stop'

    Write-Host ''
    Write-Host '  Some selected categories require your Active Directory domain name.' -ForegroundColor Cyan
    Write-Host '  Example: [your_first_name].local (enter a full domain name)' -ForegroundColor DarkGray
    Write-Host ''

    while ($true) {
        $DomainInput = (Read-Host '  Enter your domain name (e.g. [your_first_name] or [your_first_name].local):').Trim()

        if ([string]::IsNullOrWhiteSpace($DomainInput)) {
            return ''
        }

        $Parts = $DomainInput -split '\.'
        switch ($Parts.Count) {
            1 {
                Write-Host ''
                Write-Host "  Did you mean '$DomainInput.local'?" -ForegroundColor Yellow
                $Confirm = (Read-Host '  Enter Y to use that, N to type again').Trim().ToUpper()
                if ($Confirm -eq '' -or $Confirm -eq 'Y') {
                    return $DomainInput
                }
                Write-Host '  Please enter your domain name again.' -ForegroundColor Yellow
                Write-Host ''
            }
            2 {
                return $Parts[0]
            }
            default {
                Write-Host "  '$DomainInput' has more than two parts — expected a 2-part domain like 'voornaam.local'." -ForegroundColor Yellow
                $Confirm = (Read-Host '  Are you sure this is correct? (y/N)').Trim().ToUpper()
                if ($Confirm -eq 'Y') {
                    return $Parts[0]
                }
                Write-Host '  Please enter your domain name again.' -ForegroundColor Yellow
                Write-Host ''
            }
        }
    }
}
