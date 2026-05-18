#Requires -Version 7.5
<#
.SYNOPSIS
    Installs the originating machine's SSH public key on a single remote target.
.DESCRIPTION
    Copies the specified public key to the correct authorized_keys file on the
    remote target, depending on the target's operating system and whether the
    user is an administrator.

    For Linux targets:
      - Appends to ~/.ssh/authorized_keys
      - Sets chmod 700 on ~/.ssh and chmod 600 on authorized_keys

    For Windows non-admin targets:
      - Appends to $env:USERPROFILE\.ssh\authorized_keys
      - Runs icacls to restrict permissions

    For Windows admin targets (username matches 'administrator' or user is
    in the Administrators group):
      - Also appends to C:\ProgramData\ssh\administrators_authorized_keys
      - Runs icacls to grant Administrators and SYSTEM access only

    Password-based SSH is used to connect:
      - If sshpass is available on the originating machine, it is used for
        non-interactive password authentication.
      - Otherwise, SSH is invoked directly and the user must type the
        password at the interactive prompt.
.PARAMETER HostName
    The hostname or IP address of the remote target.
.PARAMETER Port
    The SSH port number.  Default: 22.
.PARAMETER UserName
    The SSH user name on the remote host.
.PARAMETER Password
    SecureString password used when sshpass is available locally.
    When sshpass is unavailable, SSH runs interactively and the user enters the
    password at the terminal prompt.
.PARAMETER PublicKeyContent
    The full content of the public key file (e.g. 'ssh-ed25519 AAAA... comment').
.PARAMETER Platform
    The remote operating system: 'Windows' or 'Linux'.
.OUTPUTS
    [PSCustomObject] — Result with Success (bool), HostName, Port, Message.
.EXAMPLE
    $CredentialInput = Read-Host 'Password' -AsSecureString
    $PubKey = Get-Content './keys/id_sage.pub' -Raw
    Install-SshKeyOnTarget -HostName '192.168.1.2' -Port 22 -UserName 'student' -Password $CredentialInput -PublicKeyContent $PubKey -Platform 'Linux'
#>
function Install-SshKeyOnTarget {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $HostName,
        [Parameter()]         [ValidateRange(1, 65535)]                                       [int] $Port = 22,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $UserName,
        [Parameter(Mandatory)][ValidateNotNull()]                             [System.Security.SecureString] $Password,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $PublicKeyContent,
        [Parameter(Mandatory)][ValidateSet('Windows', 'Linux')]                            [string] $Platform
    )

    $ErrorActionPreference = 'Stop'

    $PublicKeyContent = $PublicKeyContent.Trim()
    $IsAdmin = $UserName -match '^[Aa]dministrator$'

    # ── Build the remote command ───────────────────────────────────────────────
    $RemoteCommand = switch ($Platform) {
        'Linux' {
            # Escape single quotes in the public key content for safe shell embedding
            $EscapedKey = $PublicKeyContent -replace "'", "'\\''"
            @(
                'mkdir -p ~/.ssh'
                'chmod 700 ~/.ssh'
                "grep -qxF '$EscapedKey' ~/.ssh/authorized_keys 2>/dev/null || echo '$EscapedKey' >> ~/.ssh/authorized_keys"
                'chmod 600 ~/.ssh/authorized_keys'
                'echo SSH_KEY_INSTALL_OK'
            ) -join ' && '
        }
        'Windows' {
            # Build script as statement list — no here-strings or embedded quotes
            # to avoid cmd.exe misinterpreting double quotes when the command is
            # passed via SSH. The script is Base64/UTF-16LE encoded and executed
            # with powershell -EncodedCommand (no shell escaping needed).
            $EscapedKey = $PublicKeyContent -replace "'", "''"
            $Stmts = [System.Collections.Generic.List[string]]::new()

            # User authorized_keys
            $Stmts.Add('if (-not (Test-Path "$env:USERPROFILE\.ssh")) { New-Item "$env:USERPROFILE\.ssh" -ItemType Directory -Force | Out-Null }')
            $Stmts.Add("`$Key = '$EscapedKey'")
            $Stmts.Add('$UserFile = "$env:USERPROFILE\.ssh\authorized_keys"')
            $Stmts.Add('if (-not (Test-Path $UserFile) -or -not (Select-String -Path $UserFile -SimpleMatch $Key -Quiet)) { Add-Content -Path $UserFile -Value $Key }')
            $Stmts.Add("icacls `"`$env:USERPROFILE\.ssh\authorized_keys`" /inheritance:r /grant `"${UserName}:F`" /grant `"SYSTEM:F`" 2>`$null | Out-Null")

            if ($IsAdmin) {
                $Stmts.Add('if (-not (Test-Path ''C:\ProgramData\ssh'')) { New-Item ''C:\ProgramData\ssh'' -ItemType Directory -Force | Out-Null }')
                $Stmts.Add('$AdminFile = ''C:\ProgramData\ssh\administrators_authorized_keys''')
                $Stmts.Add('if (-not (Test-Path $AdminFile) -or -not (Select-String -Path $AdminFile -SimpleMatch $Key -Quiet)) { Add-Content -Path $AdminFile -Value $Key }')
                $Stmts.Add('icacls ''C:\ProgramData\ssh\administrators_authorized_keys'' /inheritance:r /grant ''Administrators:F'' /grant ''SYSTEM:F'' 2>$null | Out-Null')
            }
            else {
                # Non-admin user: check if in Administrators group (e.g. Win11 'student')
                $Stmts.Add('$InAdminGroup = $null -ne ((& net localgroup Administrators 2>$null) | Where-Object { $_ -match [regex]::Escape($env:USERNAME) })')
                $Stmts.Add('if ($InAdminGroup) { if (-not (Test-Path ''C:\ProgramData\ssh'')) { New-Item ''C:\ProgramData\ssh'' -ItemType Directory -Force | Out-Null }; $AdminFile = ''C:\ProgramData\ssh\administrators_authorized_keys''; if (-not (Test-Path $AdminFile) -or -not (Select-String -Path $AdminFile -SimpleMatch $Key -Quiet)) { Add-Content -Path $AdminFile -Value $Key }; icacls ''C:\ProgramData\ssh\administrators_authorized_keys'' /inheritance:r /grant ''Administrators:F'' /grant ''SYSTEM:F'' 2>$null | Out-Null }')
            }

            $Stmts.Add("Write-Output 'SSH_KEY_INSTALL_OK'")
            $Stmts -join '; '
        }
    }

    # ── Connect via SSH with password and run the command ──────────────────────
    $SshCommonArgs = @(
        '-o', 'StrictHostKeyChecking=no'
        '-o', 'ConnectTimeout=20'
        '-p', $Port
    )

    $HasSshpass = $null -ne (Get-Command 'sshpass' -ErrorAction SilentlyContinue)
    $ResultObj = [PSCustomObject]@{
        Success  = $false
        HostName = $HostName
        Port     = $Port
        Message  = ''
    }

    try {
        $Target = "${UserName}@${HostName}"

        # For Windows targets, encode the script as Base64/UTF-16LE and use
        # powershell -EncodedCommand to bypass cmd.exe quote-parsing entirely.
        # For Linux targets, use the plain bash command string directly.
        if ($Platform -eq 'Windows') {
            $Bytes = [System.Text.Encoding]::Unicode.GetBytes($RemoteCommand)
            $EncodedCmd = [Convert]::ToBase64String($Bytes)
            $FullCommand = "powershell -NoProfile -EncodedCommand $EncodedCmd"
        }
        else {
            $FullCommand = $RemoteCommand
        }

        if ($HasSshpass) {
            $AuthText = [System.Net.NetworkCredential]::new('', $Password).Password
            try {
                $SshpassArgs = @('-p', $AuthText, 'ssh') + $SshCommonArgs + @($Target, $FullCommand)
                $Output = Invoke-SshPassCommand -ArgumentList $SshpassArgs
            }
            finally {
                $AuthText = $null
            }
        }
        else {
            Write-Host "  Enter password for ${UserName}@${HostName}:${Port} when prompted:" -ForegroundColor Yellow
            $SshArgs = $SshCommonArgs + @($Target, $FullCommand)
            $Output = Invoke-SshCommand -ArgumentList $SshArgs
        }

        $OutputText = ($Output | Out-String).Trim()
        if ($OutputText -match 'SSH_KEY_INSTALL_OK') {
            $ResultObj.Success = $true
            $ResultObj.Message = "Public key installed on ${UserName}@${HostName}:${Port}."
        }
        else {
            $ResultObj.Message = "Key install command did not return success marker. Output: $OutputText"
        }
    }
    catch {
        $ResultObj.Message = "Failed to install key on ${UserName}@${HostName}:${Port}: $_"
    }

    return $ResultObj
}

<#
.SYNOPSIS
    Wrapper around the sshpass executable for testability.
.DESCRIPTION
    Invokes sshpass with the given arguments.  Exists as a separate function
    so that Pester tests can mock it instead of the native executable.
.PARAMETER ArgumentList
    Arguments to pass to the sshpass command.
.OUTPUTS
    [string[]] — Output lines from the sshpass command.
.EXAMPLE
    Invoke-SshPassCommand -ArgumentList @('-p', 'pass', 'ssh', 'user@host', 'echo hello')
#>
function Invoke-SshPassCommand {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]                                                           [string[]] $ArgumentList
    )

    & sshpass @ArgumentList 2>&1
}
