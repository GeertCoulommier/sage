#Requires -Version 7.5
<#
.SYNOPSIS
    Distributes SSH key-based authentication among computers in each set.
.DESCRIPTION
    For each computer set, ensures every computer has an SSH key pair and can
    authenticate to every other computer in the same set using key-based auth.

        Steps per set (delegated to Install-SshKeyForSet):
            1. Connect to all computers via SSH.
      2. Check for existing SSH key pairs; generate if missing.
      3. Collect all public keys from the set.
      4. Distribute public keys to every computer in the set.
      5. Fix file/directory permissions (Linux and Windows).
      6. Handle Windows administrator authorized_keys placement.
      7. Test SSH connectivity between all pairs in the set.

    Sets are processed in parallel up to ThrottleLimit.  Computers within a
    set are processed sequentially to ensure correct key distribution.

    When -ShareKeys is specified all sets must be identical (same usernames,
    platforms, ports) and the key pair generated for the first set is copied
    to every subsequent set instead of generating unique keys.
.PARAMETER ComputerSets
    Array of computer sets.  Each set is an array of hashtables with keys:
    HostName, Port, UserName, Platform ('Windows' or 'Linux'), and an
    optional Name for logging.
.PARAMETER ThrottleLimit
    Maximum number of sets processed concurrently.  Default 10.
.PARAMETER ShareKeys
    When specified, copies the key pair from the first set to all other sets
    instead of generating unique keys per set.  Only valid when all sets have
    identical structure (same usernames, platforms, ports).
.PARAMETER KeyType
    SSH key type to generate.  Default 'ed25519'.
.PARAMETER Force
    Overwrite existing SSH keys on remote computers.
.OUTPUTS
    [PSCustomObject[]] — One Sage.SshKeyResult per set with properties:
    SetIndex, Computers, KeysGenerated, KeysDistributed, TestResults, Errors.
.EXAMPLE
    $Set1 = @(
        @{ HostName = '192.168.1.2'; Port = 22; UserName = 'student'; Platform = 'Linux'; Name = 'Linux' }
        @{ HostName = '192.168.1.3'; Port = 22; UserName = 'administrator'; Platform = 'Windows'; Name = 'DC1' }
    )
    Install-SshKey -ComputerSets @(, $Set1)
.EXAMPLE
    # Build from werkcolleges roster — see tools/Install-SshKeys.ps1
    $Sets = ./tools/Install-SshKeys.ps1 -RosterPath ./data/exams/werkcolleges-2526/roster.csv
#>
function Install-SshKey {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                              [hashtable[][]] $ComputerSets,
        [Parameter()]         [ValidateRange(1, 50)]                                          [int] $ThrottleLimit = 10,
        [Parameter()]                                                                      [switch] $ShareKeys,
        [Parameter()]         [ValidateSet('ed25519', 'rsa')]                              [string] $KeyType = 'ed25519',
        [Parameter()]                                                                      [switch] $Force
    )

    $ErrorActionPreference = 'Stop'
    $UseParallel = $ComputerSets.Count -gt 2 -and $ThrottleLimit -gt 1
    $ForceEnabled = $Force.IsPresent

    # ── Validate ShareKeys requirement ─────────────────────────────────────────
    if ($ShareKeys -and $ComputerSets.Count -gt 1) {
        $Reference = $ComputerSets[0]
        for ($I = 1; $I -lt $ComputerSets.Count; $I++) {
            $Current = $ComputerSets[$I]
            if ($Current.Count -ne $Reference.Count) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            "ShareKeys requires identical set structures. Set 0 has $($Reference.Count) computers, set $I has $($Current.Count)."),
                        'InstallSshKey.MismatchedSets',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $ComputerSets
                    )
                )
            }
            for ($J = 0; $J -lt $Reference.Count; $J++) {
                if ($Current[$J].UserName -ne $Reference[$J].UserName -or
                    $Current[$J].Platform -ne $Reference[$J].Platform -or
                    $Current[$J].Port -ne $Reference[$J].Port) {
                    $PSCmdlet.ThrowTerminatingError(
                        [System.Management.Automation.ErrorRecord]::new(
                            [System.InvalidOperationException]::new(
                                "ShareKeys requires identical structure. Set $I computer $J differs from set 0."),
                            'InstallSshKey.MismatchedComputer',
                            [System.Management.Automation.ErrorCategory]::InvalidArgument,
                            $ComputerSets
                        )
                    )
                }
            }
        }
    }

    # ── Process sets ───────────────────────────────────────────────────────────
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($UseParallel) {
        # ── Parallel processing via ForEach-Object -Parallel ───────────
        $ModulePath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Sage.psd1')).Path
        $WriteLogPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Private' 'Write-Log.ps1')).Path
        $HelperPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Private' 'Install-SshKeyForSet.ps1')).Path
        $LogPath = $script:LogPath

        $ParallelResults = 0..($ComputerSets.Count - 1) | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            $Idx = $_
            $AllSets = $using:ComputerSets
            $Set = $AllSets[$Idx]
            $ModPath = $using:ModulePath
            $WriteLogFile = $using:WriteLogPath
            $HelperFile = $using:HelperPath
            $LogP = $using:LogPath
            $KType = $using:KeyType
            $ForceFlag = $using:ForceEnabled

            Import-Module $ModPath -Force
            . $WriteLogFile
            . $HelperFile
            $script:LogPath = $LogP

            $SetParams = @{
                ComputerSet = $Set
                SetIndex    = $Idx
                KeyType     = $KType
            }
            if ($ForceFlag) { $SetParams['Force'] = $true }

            Install-SshKeyForSet @SetParams
        }

        foreach ($R in $ParallelResults) {
            $Results.Add($R)
        }
    }
    else {
        # ── Sequential processing ──────────────────────────────────────
        for ($I = 0; $I -lt $ComputerSets.Count; $I++) {
            $SetParams = @{
                ComputerSet = $ComputerSets[$I]
                SetIndex    = $I
                KeyType     = $KeyType
            }
            if ($Force) { $SetParams['Force'] = $true }

            $Result = Install-SshKeyForSet @SetParams
            $Results.Add($Result)
        }
    }

    $Results.ToArray()
}
