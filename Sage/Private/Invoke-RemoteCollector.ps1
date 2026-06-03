#Requires -Version 7.5
<#
.SYNOPSIS
    Dispatches a named collector script to a remote VM and returns a Sage.CollectorResult.
.DESCRIPTION
    Locates the collector script at Collectors/Invoke-<Name>Collector.ps1 relative
    to the module root, copies it to the remote VM, executes it with the supplied
    Variables hashtable, and wraps the result in a Sage.CollectorResult object.

    If the collector script does not exist locally, a terminating error is thrown.
    Any execution error on the remote side is caught and returned as an unavailable
    CollectorResult with the error message in Reason.
.PARAMETER Name
    Short name of the collector, matching the Collector key in exam.psd1
    (e.g. 'Dns', 'Docker').  The file Collectors/Invoke-<Name>Collector.ps1 must exist.
.PARAMETER RemoteSession
    Active Sage.RemoteSession returned by New-RemoteSession.
.PARAMETER Variables
    Hashtable of exam variables for the current category (from exam.psd1 category
    Variables block).  Passed to the collector script as -Variables.
.OUTPUTS
    [PSCustomObject] typed as 'Sage.CollectorResult'
.EXAMPLE
    $result = Invoke-RemoteCollector -Name 'Dns' -RemoteSession $remoteSession -Variables @{ DnsServerIp = '10.2.3.1' }
    # Returns a Sage.CollectorResult with Available, Data, Errors, and Duration.
#>
function Invoke-RemoteCollector {
    [CmdletBinding()]
    [OutputType('Sage.CollectorResult')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables',
        Justification = 'Used via $using: scope in Invoke-Command scriptblock')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $Name,
        [Parameter(Mandatory)][PSTypeName('Sage.RemoteSession')]                   [PSCustomObject] $RemoteSession,
        [Parameter()]                                                                   [hashtable] $Variables = @{}
    )

    $ErrorActionPreference = 'Stop'

    $IsRemoteWindows = $RemoteSession.Platform -eq 'Windows'
    $TargetName = $RemoteSession.TargetName
    $CollectorName = "Invoke-${Name}Collector.ps1"
    $LocalPath = Join-Path $PSScriptRoot '..' 'Collectors' $CollectorName

    if (-not (Test-Path $LocalPath)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new(
                    "Collector script '$CollectorName' not found at: $LocalPath"),
                'InvokeRemoteCollector.ScriptNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $LocalPath
            )
        )
    }

    # Join-Path on Windows converts '/tmp/...' to '\tmp\...' which breaks Linux paths.
    # Windows paths are resolved remotely to avoid local C: drive issues on Linux.
    $RemotePath = if ($IsRemoteWindows) {
        Invoke-Command -Session $RemoteSession.Session -ScriptBlock {
            Join-Path $env:TEMP 'sage-collectors' $using:CollectorName
        }
    }
    else {
        "/tmp/sage-collectors/$CollectorName"
    }

    $LogParams = @{
        Level    = 'Verbose'
        Category = 'Collector'
        Message  = "Starting collector '$Name' on '$TargetName'."
        Target   = $TargetName
    }
    Write-Log @LogParams

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Copy-File -Session $RemoteSession.Session -LocalPath $LocalPath -RemotePath $RemotePath

        $RawResult = Invoke-Command -Session $RemoteSession.Session -ScriptBlock {
            & $using:RemotePath -Variables $using:Variables
        }

        $Stopwatch.Stop()

        $LogParams = @{
            Level    = 'Info'
            Category = 'Collector'
            Message  = "Collector '$Name' completed on '$TargetName' in $($Stopwatch.Elapsed.TotalSeconds.ToString('F2'))s. Available=$($RawResult.Available)."
            Target   = $TargetName
            Data     = @{
                Duration = $Stopwatch.Elapsed.TotalSeconds
                DataKeys = ($RawResult.Data.Keys -join ',')
            }
        }
        Write-Log @LogParams

        $CollectorParams = @{
            CollectorName = $Name
            Available     = [bool]$RawResult.Available
            Reason        = $RawResult.Reason
            Data          = ($RawResult.Data ?? @{})
            Errors        = ($RawResult.Errors ?? @())
            Duration      = $Stopwatch.Elapsed
        }
        New-CollectorResult @CollectorParams
    }
    catch {
        $Stopwatch.Stop()
        $LogParams = @{
            Level    = 'Error'
            Category = 'Collector'
            Message  = "Collector '$Name' error on '$TargetName': $($_.Exception.Message)"
            Target   = $TargetName
        }
        Write-Log @LogParams

        $CollectorParams = @{
            CollectorName = $Name
            Available     = $false
            Reason        = $_.Exception.Message
            Duration      = $Stopwatch.Elapsed
        }
        New-CollectorResult @CollectorParams
    }
}
