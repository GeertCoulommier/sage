#Requires -Version 7.5
<#
.SYNOPSIS
    Retrieves a PSCredential from the SAGE SecretManagement vault.
.DESCRIPTION
    Thin wrapper around Get-Secret from the Microsoft.PowerShell.SecretManagement
    module.  The credential is retrieved by name from a named vault (default:
    SageVault).

    If SecretManagement is not installed or the secret is not found:
      - When -AllowPrompt is specified: falls back to an interactive Get-Credential
        prompt so the caller can still proceed.
      - When -AllowPrompt is omitted: throws a terminating error.

    Requires the Microsoft.PowerShell.SecretManagement module
    (Install-Module Microsoft.PowerShell.SecretManagement).
.PARAMETER Name
    Logical name of the stored credential (e.g. 'LinuxStudentPassword').
.PARAMETER Vault
    Vault name.  Defaults to 'SageVault'.
.PARAMETER AllowPrompt
    When specified, falls back to Get-Credential if the secret cannot be
    retrieved from the vault (module missing, vault missing, secret not found).
.OUTPUTS
    [System.Management.Automation.PSCredential]
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
    New-RemoteSession @sessionParams
.EXAMPLE
    $cred = Import-Credential -Name 'AdminPassword' -AllowPrompt
#>
function Import-Credential {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCredential])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $Name,
        [Parameter()]         [ValidateNotNullOrEmpty()]                                   [string] $Vault = 'SageVault',
        [Parameter()]                                                                      [switch] $AllowPrompt
    )

    $ErrorActionPreference = 'Stop'

    # ── Attempt vault retrieval ────────────────────────────────────────────────────
    if (Get-Command 'Get-Secret' -ErrorAction SilentlyContinue) {
        try {
            $GetParams = @{
                Name        = $Name
                Vault       = $Vault
                ErrorAction = 'Stop'
            }
            $Secret = Get-Secret @GetParams

            # Get-Secret may return a SecureString instead of a PSCredential when
            # the stored type differs.  Wrap it if necessary.
            if ($Secret -is [System.Management.Automation.PSCredential]) {
                $LogParams = @{
                    Level    = 'Info'
                    Category = 'Setup'
                    Message  = "Credential '$Name' retrieved from vault '$Vault'."
                }
                Write-Log @LogParams
                return $Secret
            }

            if ($Secret -is [System.Security.SecureString]) {
                $LogParams = @{
                    Level    = 'Info'
                    Category = 'Setup'
                    Message  = "Credential '$Name' retrieved as SecureString from vault '$Vault'. Wrapping as PSCredential."
                }
                Write-Log @LogParams
                return [System.Management.Automation.PSCredential]::new($Name, $Secret)
            }

            $LogParams = @{
                Level    = 'Warning'
                Category = 'Setup'
                Message  = "Unexpected secret type '$($secret.GetType().Name)' for '$Name'. Falling back to prompt if allowed."
            }
            Write-Log @LogParams
        }
        catch {
            if (-not $AllowPrompt) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            "Failed to retrieve credential '$Name' from vault '$Vault': $($_.Exception.Message)"),
                        'ImportCredential.RetrievalFailed',
                        [System.Management.Automation.ErrorCategory]::SecurityError,
                        $null
                    )
                )
            }
            $LogParams = @{
                Level    = 'Warning'
                Category = 'Setup'
                Message  = "Vault retrieval failed for '$Name': $($_.Exception.Message). Falling back to Get-Credential prompt."
            }
            Write-Log @LogParams
        }
    }
    else {
        if (-not $AllowPrompt) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'Microsoft.PowerShell.SecretManagement is not installed. ' +
                        'Run: Install-Module Microsoft.PowerShell.SecretManagement, ' +
                        'or re-run with -AllowPrompt to use an interactive credential prompt.'),
                    'ImportCredential.SecretManagementNotAvailable',
                    [System.Management.Automation.ErrorCategory]::NotInstalled,
                    $null
                )
            )
        }
        $LogParams = @{
            Level    = 'Warning'
            Category = 'Setup'
            Message  = "Microsoft.PowerShell.SecretManagement not available for '$Name'. Falling back to Get-Credential prompt."
        }
        Write-Log @LogParams
    }

    # ── Fallback: interactive prompt ───────────────────────────────────────────────
    $PromptMessage = "Enter credentials for '$Name' (vault '$Vault' unavailable)"
    return (Get-Credential -Message $PromptMessage)
}
