#Requires -Version 7.5
<#
.SYNOPSIS
    Prepares a remote VM for evaluation: installs required modules and copies
    collector + evaluation scripts.
.DESCRIPTION
    Performs the following steps on the remote VM referenced by EvalSession:
      1. For each module listed in $Dependencies.Modules, attempts Install-Module.
         If Install-Module fails (no internet, restricted repo), falls back to
         copying the local module folder via Copy-Item -ToSession.
      2. Copies all collector scripts (Collectors/*.ps1) to /tmp/sage-collectors/
         (Linux) or $env:TEMP\sage-collectors\ (Windows).
      3. Copies all evaluation scripts (Evaluators/*.Tests.ps1) to
         /tmp/sage-evaluations/ or the Windows equivalent.

    All steps are logged via Write-Log.  Errors are terminating.
.PARAMETER RemoteSession
    Active Sage.RemoteSession returned by New-RemoteSession.
.PARAMETER Dependencies
    Hashtable from exam.psd1 Dependencies key.  Expected shape:
      @{ Modules = @('Pester') }
.PARAMETER EvaluationsPath
    Optional path to the directory containing evaluation scripts.  Defaults to
    ../Evaluators relative to the module Private/ directory.  Allows exam
    grading to use private evaluators from a different location.
.OUTPUTS
    [void]
.EXAMPLE
    $setupParams = @{
        RemoteSession = $remoteSession
        Dependencies  = @{ Modules = @('Pester') }
    }
    Invoke-RemoteSetup @setupParams
    # Installs Pester on the remote VM and copies collector and evaluation scripts.
#>
function Invoke-RemoteSetup {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '',
        Justification = '$env:TEMP and $env:ProgramFiles inside Invoke-Command scriptblocks intentionally reference the remote environment, not the local one.')]
    param(
        [Parameter(Mandatory)][PSTypeName('Sage.RemoteSession')]                   [PSCustomObject] $RemoteSession,
        [Parameter()]                                                                   [hashtable] $Dependencies = @{ Modules = @() },
        [Parameter()][ValidateNotNullOrEmpty()]                                            [string] $EvaluationsPath
    )

    $ErrorActionPreference = 'Stop'

    $Session = $RemoteSession.Session
    $TargetName = $RemoteSession.TargetName
    $IsRemoteWindows = $RemoteSession.Platform -eq 'Windows'

    # ── Resolve remote temp/program paths (cannot pass $env: literals via $using:) ──
    # NOTE: For Windows targets, $RemoteTempBase is kept $null — all Windows remote path
    # construction happens inside Invoke-Command to avoid local C: drive issues on Linux.
    $RemoteTempBase = if ($IsRemoteWindows) { $null } else { '/tmp' }

    # ── 1. Install required modules ──────────────────────────────────────────────
    $ModuleList = $Dependencies.Modules
    if (-not $ModuleList) { $ModuleList = @() }

    foreach ($ModuleName in $ModuleList) {
        $LogParams = @{
            Level    = 'Info'
            Category = 'Setup'
            Message  = "Checking module '$ModuleName' on '$TargetName'."
            Target   = $TargetName
        }
        Write-Log @LogParams

        $Installed = Invoke-Command -Session $Session -ScriptBlock {
            # Pester 3.x ships with Windows but lacks Pester 5 APIs (New-PesterContainer etc.).
            # Require at least 5.0.0 so the old built-in version does not satisfy the check.
            $minVersion = if ($using:ModuleName -eq 'Pester') { [Version]'5.0.0' } else { [Version]'0.0.0' }
            $null -ne (Get-Module -Name $using:ModuleName -ListAvailable -ErrorAction SilentlyContinue |
                    Where-Object { [Version]$_.Version -ge $minVersion } |
                    Select-Object -First 1)
        }

        if ($Installed) {
            $LogParams = @{
                Level    = 'Verbose'
                Category = 'Setup'
                Message  = "Module '$ModuleName' already present on '$TargetName'."
                Target   = $TargetName
            }
            Write-Log @LogParams
            continue
        }

        # Try Install-Module first
        $InstallOk = $false
        try {
            Invoke-Command -Session $Session -ScriptBlock {
                Install-Module -Name $using:ModuleName -Force -Scope CurrentUser -ErrorAction Stop
            }
            $InstallOk = $true
            $LogParams = @{
                Level    = 'Info'
                Category = 'Setup'
                Message  = "Module '$ModuleName' installed via Install-Module on '$TargetName'."
                Target   = $TargetName
            }
            Write-Log @LogParams
        }
        catch {
            $LogParams = @{
                Level    = 'Warning'
                Category = 'Setup'
                Message  = "Install-Module '$ModuleName' failed on '$TargetName', falling back to local copy: $($_.Exception.Message)"
                Target   = $TargetName
            }
            Write-Log @LogParams
        }

        # Fallback: copy local module folder
        if (-not $InstallOk) {
            $LocalModule = Get-Module -Name $ModuleName -ListAvailable -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $LocalModule) {
                $ErrMsg = "Module '$ModuleName' not available locally for fallback copy to '$TargetName'."
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new($ErrMsg),
                        'InvokeRemoteSetup.ModuleNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $ModuleName
                    )
                )
            }
            $LocalModuleDir = Split-Path $LocalModule.Path -Parent
            $RemoteModuleDest = if ($IsRemoteWindows) {
                # Build destination path on the remote side to avoid local cross-platform path issues
                # (Windows paths like C:\... are not resolvable locally on Linux)
                Invoke-Command -Session $Session -ScriptBlock {
                    Join-Path $HOME 'Documents' 'PowerShell' 'Modules' $using:ModuleName
                }
            }
            else {
                '/usr/local/share/powershell/Modules/' + $ModuleName
            }
            $CopyItemParams = @{
                Path        = $LocalModuleDir
                Destination = $RemoteModuleDest
                ToSession   = $Session
                Recurse     = $true
                Force       = $true
            }
            Copy-Item @CopyItemParams
            $LogParams = @{
                Level    = 'Info'
                Category = 'Setup'
                Message  = "Module '$ModuleName' copied to '$TargetName' via local fallback."
                Target   = $TargetName
            }
            Write-Log @LogParams
        }
    }

    # ── 2. Copy collector scripts ──────────────────────────────────────────────
    $CollectorsPath = Join-Path $PSScriptRoot '..' 'Collectors'
    if (Test-Path $CollectorsPath) {
        # Windows paths are resolved remotely to avoid local C: drive issues on Linux.
        $RemoteCollectors = if ($IsRemoteWindows) {
            Invoke-Command -Session $Session -ScriptBlock { Join-Path $env:TEMP 'sage-collectors' }
        }
        else {
            "$RemoteTempBase/sage-collectors"
        }

        Invoke-Command -Session $Session -ScriptBlock {
            if (-not (Test-Path $using:RemoteCollectors)) {
                New-Item -ItemType Directory -Path $using:RemoteCollectors -Force | Out-Null
            }
        }

        $Collectors = Get-ChildItem -Path $CollectorsPath -Filter '*.ps1'
        foreach ($File in $Collectors) {
            $FileName = $File.Name
            $RemotePath = if ($IsRemoteWindows) {
                Invoke-Command -Session $Session -ScriptBlock { Join-Path $using:RemoteCollectors $using:FileName }
            }
            else {
                "$RemoteCollectors/$FileName"
            }
            Copy-File -Session $Session -LocalPath $File.FullName -RemotePath $RemotePath
        }
        $LogParams = @{
            Level    = 'Info'
            Category = 'Setup'
            Message  = "Copied $($Collectors.Count) collector(s) to '$TargetName'."
            Target   = $TargetName
        }
        Write-Log @LogParams
    }

    # ── 3. Copy evaluation scripts ──────────────────────────────────────────────
    if (-not $EvaluationsPath) {
        $EvaluationsPath = Join-Path $PSScriptRoot '..' 'Evaluators'
    }
    if (Test-Path $EvaluationsPath) {
        $RemoteEvals = if ($IsRemoteWindows) {
            Invoke-Command -Session $Session -ScriptBlock { Join-Path $env:TEMP 'sage-evaluations' }
        }
        else {
            "$RemoteTempBase/sage-evaluations"
        }

        Invoke-Command -Session $Session -ScriptBlock {
            if (-not (Test-Path $using:RemoteEvals)) {
                New-Item -ItemType Directory -Path $using:RemoteEvals -Force | Out-Null
            }
        }

        $EvalFiles = Get-ChildItem -Path $EvaluationsPath -Filter '*.ps1'
        foreach ($File in $EvalFiles) {
            $FileName = $File.Name
            $RemotePath = if ($IsRemoteWindows) {
                Invoke-Command -Session $Session -ScriptBlock { Join-Path $using:RemoteEvals $using:FileName }
            }
            else {
                "$RemoteEvals/$FileName"
            }
            Copy-File -Session $Session -LocalPath $File.FullName -RemotePath $RemotePath
        }
        $LogParams = @{
            Level    = 'Info'
            Category = 'Setup'
            Message  = "Copied $($EvalFiles.Count) evaluation file(s) to '$TargetName'."
            Target   = $TargetName
        }
        Write-Log @LogParams
    }
}
