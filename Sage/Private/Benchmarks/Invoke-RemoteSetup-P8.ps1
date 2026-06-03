#Requires -Version 7.5
<#
.SYNOPSIS
    P8 optimized Invoke-RemoteSetup: caches the Pester module check result per
    target host to avoid repeated round-trips across students.
.DESCRIPTION
    Drop-in replacement for the module-check phase of Invoke-RemoteSetup.
    Instead of issuing an Invoke-Command to check Pester's installed version on
    every student × every target (N×3 round-trips), this variant caches the
    result in $script:P8_ModuleCheckCache after the first successful check.

    Cache key: "$HostName:$Port-$ModuleName"

    For 30 students on 3 shared VMs, the module check runs at most 3 times
    (once per unique target) instead of 90 times.

    THREAD SAFETY
    ─────────────
    In parallel mode (ThrottleLimit > 1), each runspace gets its own module scope
    and therefore its own $script:P8_ModuleCheckCache.  Within a single runspace
    the cache is accurate.  Across runspaces each target is checked once per
    runspace, which is still an improvement over the previous design (one check
    per student per call, regardless of mode).

    For full cross-runspace caching, a concurrent dictionary in a shared .NET
    object would be needed — not implemented here because the per-runspace cache
    already provides significant savings in practice.
.PARAMETER RemoteSession
    Active Sage.RemoteSession returned by New-RemoteSession.
.PARAMETER Dependencies
    Hashtable from exam.psd1 Dependencies key.
.PARAMETER EvaluationsPath
    Optional path to the directory containing evaluation scripts.
.OUTPUTS
    [void]
.EXAMPLE
    Invoke-RemoteSetup-P8 -RemoteSession $Session -Dependencies @{ Modules = @('Pester') }
#>

# Module-scope cache: persists across calls within the same pwsh process
if (-not (Get-Variable -Name 'P8_ModuleCheckCache' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:P8_ModuleCheckCache = @{}
}

function Invoke-RemoteSetup-P8 {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '',
        Justification = '$env:TEMP inside Invoke-Command intentionally references the remote environment.')]
    param(
        [Parameter(Mandatory)][PSTypeName('Sage.RemoteSession')]                   [PSCustomObject] $RemoteSession,
        [Parameter()]                                                                   [hashtable] $Dependencies = @{ Modules = @() },
        [Parameter()][ValidateNotNullOrEmpty()]                                            [string] $EvaluationsPath
    )

    $ErrorActionPreference = 'Stop'

    $Session = $RemoteSession.Session
    $TargetName = $RemoteSession.TargetName
    $IsRemoteWindows = $RemoteSession.Platform -eq 'Windows'
    $RemoteTempBase = if ($IsRemoteWindows) { $null } else { '/tmp' }

    # ── 1. Module check — P8 cached ──────────────────────────────────────────
    $ModuleList = $Dependencies.Modules
    if (-not $ModuleList) { $ModuleList = @() }

    foreach ($ModuleName in $ModuleList) {
        $CacheKey = "$($RemoteSession.HostName):$($RemoteSession.Port)-$ModuleName"

        if ($script:P8_ModuleCheckCache.ContainsKey($CacheKey)) {
            Write-Verbose "[P8] Module check cached for '$ModuleName' on '$TargetName' (key: $CacheKey)"
            continue
        }

        Write-Verbose "[P8] Checking module '$ModuleName' on '$TargetName' (cache miss)."

        $Installed = Invoke-Command -Session $Session -ScriptBlock {
            $minVersion = if ($using:ModuleName -eq 'Pester') { [Version]'5.0.0' } else { [Version]'0.0.0' }
            $null -ne (Get-Module -Name $using:ModuleName -ListAvailable -ErrorAction SilentlyContinue |
                    Where-Object { [Version]$_.Version -ge $minVersion } |
                    Select-Object -First 1)
        }

        if ($Installed) {
            $script:P8_ModuleCheckCache[$CacheKey] = $true
            Write-Verbose "[P8] Module '$ModuleName' present on '$TargetName' — cached."
            continue
        }

        # Not installed — attempt install
        $InstallOk = $false
        try {
            Invoke-Command -Session $Session -ScriptBlock {
                Install-Module -Name $using:ModuleName -Force -Scope CurrentUser -ErrorAction Stop
            }
            $InstallOk = $true
        }
        catch {
            Write-Warning "[P8] Install-Module '$ModuleName' failed on '$TargetName': $($_.Exception.Message)"
        }

        if (-not $InstallOk) {
            $LocalModule = Get-Module -Name $ModuleName -ListAvailable -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $LocalModule) {
                $ErrMsg = "Module '$ModuleName' not available locally for fallback copy to '$TargetName'."
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new($ErrMsg),
                        'InvokeRemoteSetupP8.ModuleNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $ModuleName
                    )
                )
            }
            $LocalModuleDir = Split-Path $LocalModule.Path -Parent
            $RemoteModuleDest = if ($IsRemoteWindows) {
                Invoke-Command -Session $Session -ScriptBlock {
                    Join-Path $HOME 'Documents' 'PowerShell' 'Modules' $using:ModuleName
                }
            }
            else { '/usr/local/share/powershell/Modules/' + $ModuleName }

            $CopyItemParams = @{
                Path        = $LocalModuleDir
                Destination = $RemoteModuleDest
                ToSession   = $Session
                Recurse     = $true
                Force       = $true
            }
            Copy-Item @CopyItemParams
        }

        # Cache after successful install (or copy)
        $script:P8_ModuleCheckCache[$CacheKey] = $true
        Write-Verbose "[P8] Module '$ModuleName' installed on '$TargetName' — cached."
    }

    # ── 2. Copy collector scripts (unchanged from original) ───────────────────
    $CollectorsPath = Join-Path $PSScriptRoot '..' '..' 'Collectors'
    if (Test-Path $CollectorsPath) {
        $RemoteCollectors = if ($IsRemoteWindows) {
            Invoke-Command -Session $Session -ScriptBlock { Join-Path $env:TEMP 'sage-collectors' }
        }
        else { "$RemoteTempBase/sage-collectors" }

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
            else { "$RemoteCollectors/$FileName" }
            Copy-File -Session $Session -LocalPath $File.FullName -RemotePath $RemotePath
        }
    }

    # ── 3. Copy evaluation scripts (unchanged from original) ──────────────────
    if (-not $EvaluationsPath) {
        $EvaluationsPath = Join-Path $PSScriptRoot '..' '..' 'Evaluators'
    }
    if (Test-Path $EvaluationsPath) {
        $RemoteEvals = if ($IsRemoteWindows) {
            Invoke-Command -Session $Session -ScriptBlock { Join-Path $env:TEMP 'sage-evaluations' }
        }
        else { "$RemoteTempBase/sage-evaluations" }

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
            else { "$RemoteEvals/$FileName" }
            Copy-File -Session $Session -LocalPath $File.FullName -RemotePath $RemotePath
        }
    }
}
