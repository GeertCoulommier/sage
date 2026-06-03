#Requires -Version 7.5
<#
.SYNOPSIS
    Processes SSH key distribution for a single computer set.
.DESCRIPTION
    Connects to all computers in a set, checks/generates SSH key pairs,
    distributes public keys, fixes permissions, handles Windows admin
    authorized_keys placement, and tests SSH connectivity between all pairs.

    This is an internal helper called by Install-SshKey for each set.
.PARAMETER ComputerSet
    Array of hashtables, each with: HostName, Port, UserName, Platform
    ('Windows' or 'Linux'), and optional Name and KeyFilePath.
.PARAMETER SetIndex
    Zero-based index of this set (for logging).
.PARAMETER KeyType
    SSH key type to generate.  Default 'ed25519'.
.PARAMETER Force
    Overwrite existing SSH keys.
.OUTPUTS
    [PSCustomObject] — Result with SetIndex, Computers, KeysGenerated,
    KeysDistributed, TestResults, Errors.
.EXAMPLE
    $Set = @(
        @{ HostName = '10.0.0.1'; Port = 22; UserName = 'student'; Platform = 'Linux'; Name = 'Linux' }
    )
    Install-SshKeyForSet -ComputerSet $Set -SetIndex 0
#>
function Install-SshKeyForSet {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                            [hashtable[]] $ComputerSet,
        [Parameter(Mandatory)]                                                            [int] $SetIndex,
        [Parameter()]         [ValidateSet('ed25519', 'rsa')]                           [string] $KeyType = 'ed25519',
        [Parameter()]                                                                   [switch] $Force
    )

    $ErrorActionPreference = 'Stop'

    $SetResult = [PSCustomObject]@{
        PSTypeName      = 'Sage.SshKeyResult'
        SetIndex        = $SetIndex
        Computers       = @()
        KeysGenerated   = 0
        KeysDistributed = 0
        TestResults     = @()
        Errors          = @()
    }

    $Sessions = @{}
    $PublicKeys = @{}

    try {
        # ── Step 1: Connect to all computers ──────────────────────────────
        foreach ($Computer in $ComputerSet) {
            $CompName = if ($Computer.Name) { $Computer.Name } else { $Computer.HostName }
            $SetResult.Computers += $CompName

            $LogParams = @{
                Level    = 'Info'
                Category = 'Setup'
                Message  = "Set $SetIndex — connecting to '$CompName' ($($Computer.HostName):$($Computer.Port))."
                Target   = $CompName
            }
            Write-Log @LogParams

            $SessionParams = @{
                HostName   = $Computer.HostName
                Port       = $Computer.Port
                UserName   = $Computer.UserName
                TargetName = $CompName
                Platform   = $Computer.Platform
                MaxRetries = 2
            }
            if ($Computer.KeyFilePath) {
                $SessionParams['KeyFilePath'] = $Computer.KeyFilePath
            }

            try {
                $Session = New-RemoteSession @SessionParams
                $Sessions[$CompName] = $Session
            }
            catch {
                $SetResult.Errors += "Failed to connect to '$CompName': $_"
                $LogParams = @{
                    Level    = 'Error'
                    Category = 'Setup'
                    Message  = "Set $SetIndex — connection to '$CompName' failed: $_"
                    Target   = $CompName
                }
                Write-Log @LogParams
            }
        }

        if ($Sessions.Count -lt 2) {
            $SetResult.Errors += "Set $SetIndex — fewer than 2 computers connected. Need at least 2 for key distribution."
            return $SetResult
        }

        # ── Step 2: Check/generate SSH keys ───────────────────────────────
        $PendingKeyGeneration = [System.Collections.Generic.List[object]]::new()
        foreach ($Computer in $ComputerSet) {
            $CompName = if ($Computer.Name) { $Computer.Name } else { $Computer.HostName }
            if (-not $Sessions.ContainsKey($CompName)) { continue }

            $Session = $Sessions[$CompName]
            $TargetIsWindows = $Computer.Platform -eq 'Windows'

            $LogParams = @{
                Level    = 'Info'
                Category = 'Setup'
                Message  = "Set $SetIndex — checking SSH keys on '$CompName'."
                Target   = $CompName
            }
            Write-Log @LogParams

            $KeyCheck = Invoke-Command -Session $Session.Session -ScriptBlock {
                param([bool]$IsWin, [string]$Type)
                $SshDir = if ($IsWin) {
                    Join-Path $env:USERPROFILE '.ssh'
                }
                else {
                    Join-Path $env:HOME '.ssh'
                }
                $PrivKeyPath = Join-Path $SshDir "id_$Type"
                $PubKeyPath = Join-Path $SshDir "id_$Type.pub"
                @{
                    SshDir        = $SshDir
                    HasPrivateKey = (Test-Path $PrivKeyPath)
                    HasPublicKey  = (Test-Path $PubKeyPath)
                    PublicKey     = if (Test-Path $PubKeyPath) { (Get-Content -Path $PubKeyPath -Raw).Trim() } else { $null }
                }
            } -ArgumentList $TargetIsWindows, $KeyType

            if ($KeyCheck.HasPublicKey -and $KeyCheck.HasPrivateKey -and -not $Force) {
                $PublicKeys[$CompName] = $KeyCheck.PublicKey
                $LogParams = @{
                    Level    = 'Info'
                    Category = 'Setup'
                    Message  = "Set $SetIndex — '$CompName' already has SSH keys."
                    Target   = $CompName
                }
                Write-Log @LogParams
                continue
            }

            $PendingKeyGeneration.Add([PSCustomObject]@{
                    Computer        = $Computer
                    CompName        = $CompName
                    Session         = $Session
                    TargetIsWindows = $TargetIsWindows
                })
        }

        foreach ($Pending in $PendingKeyGeneration) {
            $LogParams = @{
                Level    = 'Info'
                Category = 'Setup'
                Message  = "Set $SetIndex — generating SSH key pair on '$($Pending.CompName)'."
                Target   = $Pending.CompName
            }
            Write-Log @LogParams

            $GenResult = Invoke-Command -Session $Pending.Session.Session -ScriptBlock {
                param([string]$Type, [bool]$IsWin)
                $SshDir = if ($IsWin) {
                    Join-Path $env:USERPROFILE '.ssh'
                }
                else {
                    Join-Path $env:HOME '.ssh'
                }
                if (-not (Test-Path $SshDir)) {
                    New-Item -Path $SshDir -ItemType Directory -Force | Out-Null
                }
                $PrivKeyPath = Join-Path $SshDir "id_$Type"
                $PubKeyPath = Join-Path $SshDir "id_$Type.pub"
                if (Test-Path $PrivKeyPath) { Remove-Item -Path $PrivKeyPath -Force }
                if (Test-Path $PubKeyPath) { Remove-Item -Path $PubKeyPath -Force }
                $Null = & ssh-keygen -t $Type -f $PrivKeyPath -N '""' -q 2>&1
                if (-not (Test-Path $PubKeyPath)) {
                    $Null = & ssh-keygen -t $Type -f $PrivKeyPath -N '' -q 2>&1
                }
                @{
                    PublicKey = if (Test-Path $PubKeyPath) { (Get-Content -Path $PubKeyPath -Raw).Trim() } else { $null }
                    Success   = (Test-Path $PubKeyPath) -and (Test-Path $PrivKeyPath)
                }
            } -ArgumentList $KeyType, $Pending.TargetIsWindows

            if ($GenResult.Success) {
                $PublicKeys[$Pending.CompName] = $GenResult.PublicKey
                $SetResult.KeysGenerated++
            }
            else {
                $SetResult.Errors += "Failed to generate SSH keys on '$($Pending.CompName)'."
            }
        }

        # ── Step 3: Distribute public keys ────────────────────────────────
        $AllPublicKeys = ($PublicKeys.Values | Sort-Object -Unique) -join "`n"

        foreach ($Computer in $ComputerSet) {
            $CompName = if ($Computer.Name) { $Computer.Name } else { $Computer.HostName }
            if (-not $Sessions.ContainsKey($CompName)) { continue }
            if (-not $PublicKeys.ContainsKey($CompName)) { continue }

            $Session = $Sessions[$CompName]
            $TargetIsWindows = $Computer.Platform -eq 'Windows'
            $IsAdmin = $Computer.UserName -match '^[Aa]dministrator$'

            $LogParams = @{
                Level    = 'Info'
                Category = 'Setup'
                Message  = "Set $SetIndex — distributing keys to '$CompName'."
                Target   = $CompName
            }
            Write-Log @LogParams

            $DistResult = Invoke-Command -Session $Session.Session -ScriptBlock {
                param(
                    [string]$Keys,
                    [bool]$IsWin,
                    [bool]$IsAdminUser,
                    [string]$UserName
                )
                $Errors = @()
                $SshDir = if ($IsWin) {
                    Join-Path $env:USERPROFILE '.ssh'
                }
                else {
                    Join-Path $env:HOME '.ssh'
                }
                if (-not (Test-Path $SshDir)) {
                    New-Item -Path $SshDir -ItemType Directory -Force | Out-Null
                }

                $AuthKeysPath = Join-Path $SshDir 'authorized_keys'
                $ExistingKeys = @()
                if (Test-Path $AuthKeysPath) {
                    $ExistingKeys = @(Get-Content -Path $AuthKeysPath |
                            Where-Object { $_.Trim() -ne '' })
                }

                $NewKeys = $Keys -split "`n" | Where-Object { $_.Trim() -ne '' }
                $KeysToAdd = @()
                foreach ($Key in $NewKeys) {
                    $KeyTrimmed = $Key.Trim()
                    if ($KeyTrimmed -and $KeyTrimmed -notin $ExistingKeys) {
                        $KeysToAdd += $KeyTrimmed
                    }
                }

                if ($KeysToAdd.Count -gt 0) {
                    $AllKeys = ($ExistingKeys + $KeysToAdd) -join "`n"
                    Set-Content -Path $AuthKeysPath -Value $AllKeys -Force -NoNewline
                    Add-Content -Path $AuthKeysPath -Value ''
                }

                # ── Fix permissions ────────────────────────────────────────
                if ($IsWin) {
                    try {
                        $Null = & icacls $SshDir /inheritance:r /grant "${UserName}:(OI)(CI)F" /grant 'SYSTEM:(OI)(CI)F' 2>&1
                        $Null = & icacls $AuthKeysPath /inheritance:r /grant "${UserName}:F" /grant 'SYSTEM:F' 2>&1
                    }
                    catch {
                        $Errors += "Permission fix failed on $AuthKeysPath : $_"
                    }

                    if ($IsAdminUser) {
                        $AdminAuthKeys = 'C:\ProgramData\ssh\administrators_authorized_keys'
                        $AdminSshDir = 'C:\ProgramData\ssh'
                        if (-not (Test-Path $AdminSshDir)) {
                            New-Item -Path $AdminSshDir -ItemType Directory -Force | Out-Null
                        }
                        $ExistingAdmin = @()
                        if (Test-Path $AdminAuthKeys) {
                            $ExistingAdmin = @(Get-Content -Path $AdminAuthKeys |
                                    Where-Object { $_.Trim() -ne '' })
                        }
                        $AdminKeysToAdd = @()
                        foreach ($Key in $NewKeys) {
                            $KeyTrimmed = $Key.Trim()
                            if ($KeyTrimmed -and $KeyTrimmed -notin $ExistingAdmin) {
                                $AdminKeysToAdd += $KeyTrimmed
                            }
                        }
                        if ($AdminKeysToAdd.Count -gt 0) {
                            $AllAdminKeys = ($ExistingAdmin + $AdminKeysToAdd) -join "`n"
                            Set-Content -Path $AdminAuthKeys -Value $AllAdminKeys -Force -NoNewline
                            Add-Content -Path $AdminAuthKeys -Value ''
                        }
                        try {
                            $Null = & icacls $AdminAuthKeys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' 2>&1
                        }
                        catch {
                            $Errors += "Permission fix failed on $AdminAuthKeys : $_"
                        }
                    }
                }
                else {
                    try {
                        & chmod 700 $SshDir 2>&1 | Out-Null
                        & chmod 600 $AuthKeysPath 2>&1 | Out-Null
                        $PrivKeyFiles = Get-ChildItem -Path $SshDir -Filter 'id_*' |
                            Where-Object { $_.Extension -ne '.pub' }
                        foreach ($Pk in $PrivKeyFiles) {
                            & chmod 600 $Pk.FullName 2>&1 | Out-Null
                        }
                    }
                    catch {
                        $Errors += "Permission fix failed: $_"
                    }
                }

                @{
                    KeysAdded = $KeysToAdd.Count
                    Errors    = $Errors
                }
            } -ArgumentList $AllPublicKeys, $TargetIsWindows, $IsAdmin, $Computer.UserName

            $SetResult.KeysDistributed += $DistResult.KeysAdded
            if ($DistResult.Errors.Count -gt 0) {
                $SetResult.Errors += $DistResult.Errors
            }
        }

        # ── Step 4: Test SSH connectivity ──────────────────────────────────
        foreach ($SourceComp in $ComputerSet) {
            $SourceName = if ($SourceComp.Name) { $SourceComp.Name } else { $SourceComp.HostName }
            if (-not $Sessions.ContainsKey($SourceName)) { continue }

            $SourceSession = $Sessions[$SourceName]

            foreach ($TargetComp in $ComputerSet) {
                $TargetName = if ($TargetComp.Name) { $TargetComp.Name } else { $TargetComp.HostName }
                if ($SourceName -eq $TargetName) { continue }

                $LogParams = @{
                    Level    = 'Info'
                    Category = 'Setup'
                    Message  = "Set $SetIndex — testing SSH $SourceName -> $TargetName."
                    Target   = $SourceName
                }
                Write-Log @LogParams

                $TestResult = Invoke-Command -Session $SourceSession.Session -ScriptBlock {
                    param(
                        [string]$TargetHost,
                        [int]$TargetPort,
                        [string]$TargetUser
                    )
                    try {
                        $SshArgs = @(
                            '-o', 'StrictHostKeyChecking=no'
                            '-o', 'BatchMode=yes'
                            '-o', 'ConnectTimeout=10'
                            '-p', $TargetPort
                            "${TargetUser}@${TargetHost}"
                            'echo', 'SSH_KEY_AUTH_OK'
                        )
                        $Output = & ssh @SshArgs 2>&1
                        $Success = ($Output -join ' ') -match 'SSH_KEY_AUTH_OK'
                        @{
                            Success = $Success
                            Output  = ($Output -join "`n")
                        }
                    }
                    catch {
                        @{
                            Success = $false
                            Output  = "Error: $_"
                        }
                    }
                } -ArgumentList $TargetComp.HostName, $TargetComp.Port, $TargetComp.UserName

                $SetResult.TestResults += [PSCustomObject]@{
                    Source  = $SourceName
                    Target  = $TargetName
                    Success = $TestResult.Success
                    Output  = $TestResult.Output
                }

                $ResultLevel = if ($TestResult.Success) { 'Info' } else { 'Warning' }
                $ResultMsg = if ($TestResult.Success) { 'succeeded' } else { 'FAILED' }
                $LogParams = @{
                    Level    = $ResultLevel
                    Category = 'Setup'
                    Message  = "Set $SetIndex — SSH test $SourceName -> $TargetName $ResultMsg."
                    Target   = $SourceName
                }
                Write-Log @LogParams
            }
        }
    }
    catch {
        $SetResult.Errors += "Set $SetIndex — unhandled error: $_"
        $LogParams = @{
            Level    = 'Error'
            Category = 'Setup'
            Message  = "Set $SetIndex — unhandled error: $_"
        }
        Write-Log @LogParams
    }
    finally {
        foreach ($CompName in @($Sessions.Keys)) {
            try {
                Close-RemoteSession -Session $Sessions[$CompName]
            }
            catch {
                Write-Verbose "Best-effort session cleanup failed for '$CompName': $($_.Exception.Message)"
            }
        }
    }

    $SetResult
}
