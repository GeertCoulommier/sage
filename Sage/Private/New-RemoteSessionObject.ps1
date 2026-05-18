#Requires -Version 7.5
#pragma warning disable PSAvoidUsingPlainTextForPassword
<#
.SYNOPSIS
    Creates a Sage.RemoteSession PSCustomObject.
.DESCRIPTION
    Factory function wrapping an active PSSession together with connection
    metadata. Returned by New-RemoteSession (Public) and consumed by
    Invoke-RemoteCollector and Invoke-RemotePester.
.PARAMETER TargetName
    Logical name for the target as defined in exam.psd1 (e.g. 'LinuxVM').
.PARAMETER HostName
    DNS name or IP address of the remote host.
.PARAMETER Port
    SSH port number (1–65535).
.PARAMETER UserName
    SSH user name on the remote host.
.PARAMETER Platform
    Operating system of the remote target: 'Windows' or 'Linux'.
.PARAMETER Session
    Active PSSession returned by New-PSSession.
.PARAMETER VaultEntryName
    Name of the vault entry used to obtain the credential (for audit purposes).
.OUTPUTS
    [PSCustomObject] typed as 'Sage.RemoteSession'
.EXAMPLE
    $sessionParams = @{
        TargetName = 'LinuxVM'
        HostName   = '10.2.3.4'
        Port       = 20022
        UserName   = 'student'
        Platform   = 'Linux'
        Session    = $psSession
    }
    $remoteSession = New-RemoteSessionObject @sessionParams
    # Returns a Sage.RemoteSession wrapping the active PSSession.
#>
function New-RemoteSessionObject {
    [CmdletBinding()]
    [OutputType('Sage.RemoteSession')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TargetName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $HostName,
        [Parameter(Mandatory)][ValidateRange(1, 65535)]                                       [int] $Port,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $UserName,
        [Parameter(Mandatory)][ValidateSet('Windows', 'Linux')]                            [string] $Platform,
        [Parameter(Mandatory)]                   [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter()]                                                                      [string] $VaultEntryName
    )

    [PSCustomObject]@{
        PSTypeName     = 'Sage.RemoteSession'
        TargetName     = $TargetName
        HostName       = $HostName
        Port           = $Port
        UserName       = $UserName
        Platform       = $Platform
        Session        = $Session
        VaultEntryName = $VaultEntryName
        ConnectedAt    = [datetime]::Now
        SessionId      = $Session.Id
    }
}
#pragma warning restore PSAvoidUsingPlainTextForPassword
