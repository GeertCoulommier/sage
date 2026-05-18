#Requires -Version 7.5
<#
.SYNOPSIS
    Stores a PSCredential in the SAGE SecretManagement vault.
.DESCRIPTION
    Thin wrapper around Set-Secret from the Microsoft.PowerShell.SecretManagement
    module.  The credential is stored by name in a named vault (default: SageVault).

    If the named vault does not exist and Microsoft.PowerShell.SecretStore is
    available, it is registered automatically as a SecretStore-backed vault.

    Requires the Microsoft.PowerShell.SecretManagement module
    (Install-Module Microsoft.PowerShell.SecretManagement).
.PARAMETER Name
    Logical name for the credential entry (e.g. 'LinuxStudentPassword').
.PARAMETER Credential
    The PSCredential to store.
.PARAMETER Vault
    Vault name.  Defaults to 'SageVault'.
.OUTPUTS
    [void]  Emits an Info log entry on success.
.EXAMPLE
    $cred = Get-Credential -UserName 'student'
    Set-Credential -Name 'LinuxStudentPassword' -Credential $cred
#>
function Set-Credential {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $Name,
        [Parameter(Mandatory)]                          [System.Management.Automation.PSCredential] $Credential,
        [Parameter()]         [ValidateNotNullOrEmpty()]                                   [string] $Vault = 'SageVault'
    )

    $ErrorActionPreference = 'Stop'

    # ── Require SecretManagement ───────────────────────────────────────────────────
    if (-not (Get-Command 'Set-Secret' -ErrorAction SilentlyContinue)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    'Microsoft.PowerShell.SecretManagement is not installed. ' +
                    'Run: Install-Module Microsoft.PowerShell.SecretManagement'),
                'SetCredential.SecretManagementNotAvailable',
                [System.Management.Automation.ErrorCategory]::NotInstalled,
                $null
            )
        )
    }

    # ── Auto-register vault if not present ────────────────────────────────────────
    $VaultExists = Get-SecretVault -Name $Vault -ErrorAction SilentlyContinue
    if (-not $VaultExists) {
        if (Get-Command 'Register-SecretVault' -ErrorAction SilentlyContinue) {
            if (-not (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretStore' -ErrorAction SilentlyContinue)) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            "Vault '$Vault' does not exist and Microsoft.PowerShell.SecretStore is not installed. " +
                            'Run: Install-Module Microsoft.PowerShell.SecretStore, then re-run Set-Credential.'),
                        'SetCredential.SecretStoreNotAvailable',
                        [System.Management.Automation.ErrorCategory]::NotInstalled,
                        $null
                    )
                )
            }

            if ($PSCmdlet.ShouldProcess("vault '$Vault'", 'Register SecretStore vault')) {
                $RegisterParams = @{
                    Name        = $Vault
                    ModuleName  = 'Microsoft.PowerShell.SecretStore'
                    ErrorAction = 'Stop'
                }
                Register-SecretVault @RegisterParams
                $LogParams = @{
                    Level    = 'Info'
                    Category = 'Setup'
                    Message  = "Registered new SecretStore vault: $Vault"
                }
                Write-Log @LogParams
            }
        }
    }

    # ── Store the secret ──────────────────────────────────────────────────────────
    if ($PSCmdlet.ShouldProcess("'$Name' in vault '$Vault'", 'Store credential')) {
        $SetParams = @{
            Name        = $Name
            Secret      = $Credential
            Vault       = $Vault
            ErrorAction = 'Stop'
        }
        Set-Secret @SetParams
        $LogParams = @{
            Level    = 'Info'
            Category = 'Setup'
            Message  = "Credential '$Name' stored in vault '$Vault'."
        }
        Write-Log @LogParams
    }
}
