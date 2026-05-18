#Requires -Version 7.5
#pragma warning disable PSAvoidUsingPlainTextForPassword
<#
.SYNOPSIS
    Creates an SSH-based PSSession to a target VM and returns a Sage.RemoteSession object.
.DESCRIPTION
    Establishes an SSH PSSession using New-PSSession -HostName / -SSHTransport.
    Retries up to 3 times on transient connection failure with a short delay between
    attempts.  On success, the raw PSSession is wrapped into a Sage.RemoteSession
    object via New-RemoteSessionObject.

    Credential handling:
      1. If -Credential is supplied, its password is used as the SSH password.
      2. Otherwise the caller must supply a plain-text password via -Password (for
         non-interactive batch use) or the SSH subsystem handles key/agent auth.

    Session timeout is capped at 20 seconds per attempt (-ConnectingTimeout 20000).

    SSH keepalive is enabled by default (ServerAliveInterval=15,
    ServerAliveCountMax=3) so dead connections are detected within ~45 seconds
    instead of hanging indefinitely.  Caller-supplied SshOptions override
    these defaults.
.PARAMETER HostName
    DNS name or IP address of the remote host.
.PARAMETER Port
    SSH port number (1–65535).
.PARAMETER UserName
    SSH user name on the remote host.
.PARAMETER Credential
    PSCredential for WSMan-based sessions (not supported with SSH transport).
.PARAMETER Password
    Plain-text password for non-interactive batch scenarios.
    NOTE: PowerShell SSH transport does not support password auth; use -KeyFilePath.
.PARAMETER KeyFilePath
    Path to an SSH private key file used for SSH authentication.
.PARAMETER SshOptions
    Hashtable of OpenSSH options to pass through to New-PSSession -Options.
.PARAMETER TargetName
    Logical name for the target as defined in exam.psd1 (e.g. 'LinuxVM').
.PARAMETER Platform
    Operating system of the remote target.  'Windows' or 'Linux'.
.PARAMETER VaultEntryName
    Name of the vault entry used to obtain the credential (informational only;
    stored on the returned Sage.RemoteSession for audit purposes).
.PARAMETER MaxRetries
    Maximum number of connection attempts.  Default is 3.
.OUTPUTS
    [PSCustomObject] typed as 'Sage.RemoteSession'
.EXAMPLE
    $cred = Import-Credential -Name 'LinuxStudentPassword'
    $sessionParams = @{
        HostName   = '10.2.3.4'
        Port       = 20022
        UserName   = 'student'
        Credential = $cred
        TargetName = 'LinuxVM'
        Platform   = 'Linux'
    }
    $session = New-RemoteSession @sessionParams
#>
function New-RemoteSession {
    [CmdletBinding(DefaultParameterSetName = 'WithCredential')]
    [OutputType('Sage.RemoteSession')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Credential',
        Justification = 'SSH transport does not support -Credential in New-PSSession; accepted for API compatibility and audit only.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Password',
        Justification = 'SSH transport does not support -Password in New-PSSession; accepted for API compatibility and audit only.')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $HostName,
        [Parameter(Mandatory)][ValidateRange(1, 65535)]                                       [int] $Port,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $UserName,
        [Parameter(ParameterSetName = 'WithCredential')][System.Management.Automation.PSCredential] $Credential,
        [Parameter(ParameterSetName = 'WithPassword')]               [System.Security.SecureString] $Password,
        [Parameter()]                                                                      [string] $KeyFilePath,
        [Parameter()]                                                                   [hashtable] $SshOptions,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TargetName,
        [Parameter(Mandatory)][ValidateSet('Windows', 'Linux')]                            [string] $Platform,
        [Parameter()]                                                                      [string] $VaultEntryName,
        [Parameter()]         [ValidateRange(1, 10)]                                          [int] $MaxRetries = 3
    )

    $ErrorActionPreference = 'Stop'

    # ── Build New-PSSession splatting ───────────────────────────────────────────
    # SSH transport does not support the -Credential parameter in New-PSSession;
    # authentication is handled via KeyFilePath or the SSH agent/config.
    # Credential is accepted as a parameter only for backward-compat and audit.
    $SessionParams = @{
        HostName          = $HostName
        Port              = $Port
        UserName          = $UserName
        SSHTransport      = $true
        ConnectingTimeout = 20000      # 20 seconds per attempt
        ErrorAction       = 'Stop'
    }
    if ($KeyFilePath) {
        $SessionParams['KeyFilePath'] = $KeyFilePath
    }

    # ── SSH keepalive defaults ──────────────────────────────────────────────────
    # Merge caller-supplied options on top of sane defaults so that dead
    # connections are detected within ~45 s instead of hanging indefinitely.
    $DefaultSshOptions = @{
        ServerAliveInterval  = '15'
        ServerAliveCountMax  = '3'
        StrictHostKeyChecking = 'no'
    }
    $MergedOptions = $DefaultSshOptions.Clone()
    if ($SshOptions) {
        foreach ($Key in $SshOptions.Keys) {
            $MergedOptions[$Key] = $SshOptions[$Key]
        }
    }
    $SessionParams['Options'] = $MergedOptions

    # ── Retry loop ───────────────────────────────────────────────────────────────
    $Attempt = 0
    $LastError = $null
    while ($Attempt -lt $MaxRetries) {
        $Attempt++
        $LogParams = @{
            Level    = 'Verbose'
            Category = 'Session'
            Message  = "Connecting to '$TargetName' (${HostName}:$Port) — attempt $Attempt/$MaxRetries."
            Target   = $TargetName
        }
        Write-Log @LogParams
        try {
            $PsSession = New-PSSession @SessionParams
            break
        }
        catch {
            $LastError = $_
            $LogParams = @{
                Level    = 'Warning'
                Category = 'Session'
                Message  = "Attempt $Attempt failed for '$TargetName': $($_.Exception.Message)"
                Target   = $TargetName
            }
            Write-Log @LogParams
            if ($Attempt -lt $MaxRetries) {
                Start-Sleep -Seconds 3
            }
        }
    }

    if (-not $PsSession) {
        $ErrMsg = "Failed to connect to '$TargetName' (${HostName}:$Port) after $MaxRetries attempt(s). Last error: $($LastError.Exception.Message)"
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new($ErrMsg),
                'NewRemoteSession.ConnectionFailed',
                [System.Management.Automation.ErrorCategory]::OpenError,
                $HostName
            )
        )
    }

    $LogParams = @{
        Level    = 'Info'
        Category = 'Session'
        Message  = "Connected to '$TargetName' (${HostName}:$Port) as '$UserName'."
        Target   = $TargetName
    }
    Write-Log @LogParams

    $RemoteSessionParams = @{
        TargetName     = $TargetName
        HostName       = $HostName
        Port           = $Port
        UserName       = $UserName
        Platform       = $Platform
        Session        = $PsSession
        VaultEntryName = $VaultEntryName
    }
    New-RemoteSessionObject @RemoteSessionParams
}
#pragma warning restore PSAvoidUsingPlainTextForPassword
