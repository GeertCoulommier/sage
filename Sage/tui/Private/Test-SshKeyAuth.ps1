#Requires -Version 7.5
<#
.SYNOPSIS
    Tests whether SSH key authentication works for a remote target.
.DESCRIPTION
    Attempts an SSH connection using BatchMode (no password prompt) to verify
    that key-based authentication is configured and working.  Runs an echo
    command on the remote host and checks for the expected marker string.

    This is distinct from Test-SshConnection which only checks TCP
    reachability — this function verifies actual SSH key auth.
.PARAMETER HostName
    The hostname or IP address of the remote target.
.PARAMETER Port
    The SSH port number.  Default: 22.
.PARAMETER UserName
    The SSH user name on the remote host.
.PARAMETER KeyFilePath
    Path to the SSH private key file.  When omitted, SSH uses its default
    key discovery (agent, ~/.ssh/id_*).
.PARAMETER TimeoutSeconds
    Maximum seconds to wait for the SSH connection.  Default: 10.
.OUTPUTS
    [bool] — $true if key authentication succeeds; $false otherwise.
.EXAMPLE
    Test-SshKeyAuth -HostName '192.168.1.2' -Port 22 -UserName 'student' -KeyFilePath './keys/id_sage'
    # Returns $true if the id_sage key authenticates successfully.
#>
function Test-SshKeyAuth {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $HostName,
        [Parameter()]         [ValidateRange(1, 65535)]                                       [int] $Port = 22,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $UserName,
        [Parameter()]                                                                      [string] $KeyFilePath,
        [Parameter()]         [ValidateRange(1, 60)]                                          [int] $TimeoutSeconds = 10
    )

    $ErrorActionPreference = 'Stop'

    $SshArgs = @(
        '-o', 'BatchMode=yes'
        '-o', "ConnectTimeout=$TimeoutSeconds"
        '-o', 'StrictHostKeyChecking=no'
        '-p', $Port
    )
    if ($KeyFilePath) {
        $SshArgs += @('-i', $KeyFilePath, '-o', 'IdentitiesOnly=yes')
    }
    $SshArgs += @("${UserName}@${HostName}", 'echo', 'SSH_KEY_AUTH_OK')

    try {
        $Output = Invoke-SshCommand -ArgumentList $SshArgs
        $OutputText = ($Output | Out-String).Trim()
        return $OutputText -match 'SSH_KEY_AUTH_OK'
    }
    catch {
        Write-Verbose "SSH key auth test failed for ${UserName}@${HostName}:${Port}: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Wrapper around the ssh executable for testability.
.DESCRIPTION
    Invokes the ssh command with the given arguments.  Exists as a separate
    function so that Pester tests can mock it instead of the native executable.
.PARAMETER ArgumentList
    Arguments to pass to the ssh command.
.OUTPUTS
    [string[]] — Output lines from the ssh command.
.EXAMPLE
    Invoke-SshCommand -ArgumentList @('-p', '22', 'user@host', 'echo', 'hello')
#>
function Invoke-SshCommand {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]                                                           [string[]] $ArgumentList
    )

    & ssh @ArgumentList 2>&1
}
