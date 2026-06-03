#Requires -Version 7.5
<#
.SYNOPSIS
    Tests TCP connectivity to an SSH port.
.DESCRIPTION
    Attempts a TCP connection to the specified host and port within the given
    timeout.  Returns $true if the port is reachable, $false otherwise.

    This is a lightweight check — it does NOT perform SSH authentication.
.PARAMETER HostName
    The hostname or IP address to test.
.PARAMETER Port
    The SSH port number to test.  Default: 22.
.PARAMETER TimeoutSeconds
    Maximum seconds to wait for the connection.  Default: 5.
.OUTPUTS
    [bool] — $true if the TCP connection succeeds; $false otherwise.
.EXAMPLE
    Test-SshConnection -HostName '192.168.1.2' -Port 22
    # Returns $true if port 22 is reachable on 192.168.1.2.
#>
function Test-SshConnection {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $HostName,
        [Parameter()]         [ValidateRange(1, 65535)]                                       [int] $Port = 22,
        [Parameter()]         [ValidateRange(1, 60)]                                          [int] $TimeoutSeconds = 5
    )

    $ErrorActionPreference = 'Stop'

    try {
        $TcpClient = [System.Net.Sockets.TcpClient]::new()
        $ConnectTask = $TcpClient.ConnectAsync($HostName, $Port)
        $Completed = $ConnectTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))

        if ($Completed -and -not $ConnectTask.IsFaulted) {
            $TcpClient.Close()
            return $true
        }
        $TcpClient.Close()
        return $false
    }
    catch {
        try { $TcpClient.Close() } catch { Write-Verbose "TcpClient already disposed: $_" }
        return $false
    }
}
