#Requires -Version 7.5
<#
.SYNOPSIS
    Copies a single local file to a remote VM via an active PSSession.
.DESCRIPTION
    Uses Copy-Item -ToSession to transfer one file from the local host to
    the specified remote path.  The remote parent directory is created if
    it does not exist.  Typically used by Invoke-RemoteSetup and
    Invoke-RemoteCollector to upload collector/evaluation scripts.
.PARAMETER Session
    An active PSSession (from Sage.RemoteSession.Session) to the target VM.
.PARAMETER LocalPath
    Absolute path of the source file on the local host.
.PARAMETER RemotePath
    Absolute destination path on the remote VM (including filename).
.PARAMETER SkipDirectoryCheck
    When set, omits the remote parent directory creation step.  Use when the
    caller has already created the target directory (e.g. Invoke-RemoteSetup).
.OUTPUTS
    [void]
.EXAMPLE
    Copy-File -Session $remoteSession.Session -LocalPath '/tmp/MyCollector.ps1' -RemotePath '/tmp/sage-collectors/MyCollector.ps1'
    # Uploads the local script to the remote VM, creating the directory if needed.
#>
function Copy-File {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]                   [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })]            [string] $LocalPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $RemotePath,
        [Parameter()]                                                                       [switch] $SkipDirectoryCheck
    )

    $ErrorActionPreference = 'Stop'

    # Ensure the remote parent directory exists (skip when caller guarantees it already exists).
    $RemoteDir = Split-Path -Path $RemotePath -Parent
    if ($RemoteDir -and -not $SkipDirectoryCheck) {
        Invoke-Command -Session $Session -ScriptBlock {
            if (-not (Test-Path $using:RemoteDir)) {
                New-Item -ItemType Directory -Path $using:RemoteDir -Force | Out-Null
            }
        }
    }

    Copy-Item -Path $LocalPath -Destination $RemotePath -ToSession $Session -Force
}
