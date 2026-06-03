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

    Credential handling (non-interactive, via SSH_ASKPASS):
      1. If -KeyFilePath is supplied, key-based auth is used (preferred).
      2. If -Credential is supplied without -KeyFilePath, the credential password is
         passed to the SSH binary via the SSH_ASKPASS mechanism so the connection is
         non-interactive and suitable for automation.
      3. If -Password is supplied without -KeyFilePath, the SecureString is unwrapped
         and passed the same way.
      4. If neither a key nor a password is provided, key/agent auth is assumed.

    The SSH_ASKPASS mechanism creates a temporary shell script that echoes the
    password from a short-lived, uniquely-named environment variable.  The variable
    and the temp file are removed in a finally block after every attempt, even on
    failure.  The password is never written to disk in plain text.

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
    PSCredential whose password is used for SSH authentication when no
    -KeyFilePath is supplied.  The password is passed non-interactively via the
    SSH_ASKPASS mechanism.
.PARAMETER Password
    SecureString password for non-interactive SSH authentication when no
    -KeyFilePath is supplied.  The password is passed via the SSH_ASKPASS mechanism.
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

    # ── Build New-PSSession splatting ─────────────────────────────────────────────
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
    # LogLevel=ERROR suppresses the OpenSSH post-quantum key-exchange warning
    # ("store now, decrypt later") that fires in OpenSSH 9.9+ when the negotiated
    # KEX algorithm is not ML-KEM.  In a student lab context this is not a
    # meaningful security concern and the warning clutters TUI output.
    $DefaultSshOptions = @{
        ServerAliveInterval   = '15'
        ServerAliveCountMax   = '3'
        StrictHostKeyChecking = 'no'
        LogLevel              = 'ERROR'
    }
    $MergedOptions = $DefaultSshOptions.Clone()
    if ($SshOptions) {
        foreach ($Key in $SshOptions.Keys) {
            $MergedOptions[$Key] = $SshOptions[$Key]
        }
    }
    $SessionParams['Options'] = $MergedOptions

    # ── SSH_ASKPASS — password auth for New-PSSession -SSHTransport ──────────────
    # New-PSSession delegates SSH auth to the system ssh binary.  By setting
    # SSH_ASKPASS + SSH_ASKPASS_REQUIRE=force we can supply a password without an
    # interactive terminal.  The password lives only in an env var (named with a
    # fresh GUID per invocation); the askpass script file only contains the env var
    # name, never the password itself.  Both are cleaned up in the finally block.
    $AskpassScript = $null
    $AskpassEnvName = $null
    $SavedAskpass = $env:SSH_ASKPASS
    $SavedAskpassReq = $env:SSH_ASKPASS_REQUIRE

    if (-not $KeyFilePath) {
        $PasswordPlain = if ($PSCmdlet.ParameterSetName -eq 'WithCredential' -and $Credential) {
            $Credential.GetNetworkCredential().Password
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'WithPassword' -and $Password) {
            [System.Net.NetworkCredential]::new('', $Password).Password
        }
        else {
            $null
        }

        if ($PasswordPlain) {
            $AskpassEnvName = "SAGE_SSH_PW_$([System.Guid]::NewGuid().ToString('N'))"
            Set-Item -Path "Env:$AskpassEnvName" -Value $PasswordPlain

            $AskpassScript = [System.IO.Path]::GetTempFileName()
            # The script echoes the env var — the password is NOT written to the file.
            $AskpassLine = 'printf ''%s'' "${' + $AskpassEnvName + '}"'
            $ScriptLines = @('#!/bin/sh', $AskpassLine)
            Set-Content -Path $AskpassScript -Value ($ScriptLines -join "`n") -Encoding UTF8
            if ($IsLinux -or $IsMacOS) {
                & chmod 700 $AskpassScript
            }

            $env:SSH_ASKPASS = $AskpassScript
            $env:SSH_ASKPASS_REQUIRE = 'force'

            $LogParams = @{
                Level    = 'Debug'
                Category = 'Session'
                Message  = "Password auth via SSH_ASKPASS configured for '$TargetName'."
                Target   = $TargetName
            }
            Write-Log @LogParams
        }
    }

    # ── Retry loop ────────────────────────────────────────────────────────────────
    $Attempt = 0
    $LastError = $null
    try {
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
    }
    finally {
        # ── SSH_ASKPASS cleanup ────────────────────────────────────────────────────
        # Restore original env vars and remove the temp askpass script regardless of
        # whether the connection succeeded or failed.
        if ($AskpassScript) {
            $env:SSH_ASKPASS = $SavedAskpass
            $env:SSH_ASKPASS_REQUIRE = $SavedAskpassReq
            Remove-Item -Path $AskpassScript -Force -ErrorAction SilentlyContinue
        }
        if ($AskpassEnvName) {
            Remove-Item -Path "Env:$AskpassEnvName" -ErrorAction SilentlyContinue
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
