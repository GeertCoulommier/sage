#Requires -Version 7.5
<#
.SYNOPSIS
    Orchestrates SSH key setup for TUI evaluation targets.
.DESCRIPTION
    Ensures that SSH key-based authentication works for all reachable targets
    before the SAGE evaluation begins.  This avoids interactive password
    prompts during the automated collector and evaluation pipeline.

    Steps:
      1. Checks if the SAGE SSH key pair exists (tui/keys/id_sage). If not,
         generates a new ed25519 key pair.
      2. Tests key authentication to each reachable target.
      3. If any targets fail key auth, prompts the user for a password once.
      4. Distributes the public key to each failing target using the password.
      5. Re-tests key authentication on targets that received the key.

    Returns a hashtable mapping target names to their key auth status.
.PARAMETER ConnectionInfo
    Hashtable from Get-ConnectionFallback mapping target names to connection
    details (HostName, Port, Status).
.PARAMETER Exam
    Validated exam definition hashtable from Import-ExamDefinition.
.PARAMETER KeyDir
    Path to the directory containing the SAGE key pair.  Defaults to
    tui/keys/ relative to the TUI Private directory.
.OUTPUTS
    [hashtable] — Keys are target names; values are PSCustomObjects with
    KeyAuthWorks (bool), PasswordUsed (bool), Message (string).
.EXAMPLE
    $AuthStatus = Invoke-SshKeySetup -ConnectionInfo $ConnInfo -Exam $Exam
    if ($AuthStatus['Linux'].KeyAuthWorks) { 'Linux key auth works' }
#>
function Invoke-SshKeySetup {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]                                                          [hashtable] $ConnectionInfo,
        [Parameter(Mandatory)]                                                          [hashtable] $Exam,
        [Parameter()]                                                                      [string] $KeyDir
    )

    $ErrorActionPreference = 'Stop'

    # ── Resolve key directory ──────────────────────────────────────────────────
    if (-not $KeyDir) {
        $KeyDir = Join-Path $PSScriptRoot '..' 'keys'
    }
    $KeyDir = [System.IO.Path]::GetFullPath($KeyDir)

    $PrivateKeyPath = Join-Path $KeyDir 'id_sage'
    $PublicKeyPath = Join-Path $KeyDir 'id_sage.pub'

    $Result = @{}

    # ── Step 1: Ensure SAGE key pair exists ────────────────────────────────────
    if (-not (Test-Path $PrivateKeyPath) -or -not (Test-Path $PublicKeyPath)) {
        Write-Host ''
        Write-Host '  No SAGE SSH key pair found. Generating new ed25519 key...' -ForegroundColor Cyan

        if (-not (Test-Path $KeyDir)) {
            $null = New-Item -Path $KeyDir -ItemType Directory -Force
        }

        # Remove partial key files if only one exists
        if (Test-Path $PrivateKeyPath) { Remove-Item -Path $PrivateKeyPath -Force }
        if (Test-Path $PublicKeyPath) { Remove-Item -Path $PublicKeyPath -Force }

        $null = & ssh-keygen -t ed25519 -f $PrivateKeyPath -N '' -q 2>&1

        if (-not (Test-Path $PublicKeyPath) -or -not (Test-Path $PrivateKeyPath)) {
            Write-Host '  Failed to generate SSH key pair.' -ForegroundColor Red
            foreach ($TargetName in $ConnectionInfo.Keys) {
                $Result[$TargetName] = [PSCustomObject]@{
                    KeyAuthWorks = $false
                    PasswordUsed = $false
                    Message      = 'Key generation failed.'
                }
            }
            return $Result
        }

        # Ensure private key has correct permissions (600)
        if ($PSVersionTable.Platform -eq 'Unix' -or $PSVersionTable.OS -match 'Darwin') {
            & chmod 600 $PrivateKeyPath | Out-Null
        }

        Write-Host '  SSH key pair generated successfully.' -ForegroundColor Green
    }

    $PublicKeyContent = (Get-Content -Path $PublicKeyPath -Raw).Trim()

    # ── Step 2: Test key auth for each reachable target ────────────────────────
    Write-Host ''
    Write-Host '  Testing SSH key authentication...' -ForegroundColor Cyan

    $FailingTargets = [System.Collections.Generic.List[string]]::new()

    foreach ($TargetName in $ConnectionInfo.Keys) {
        $ConnInfo = $ConnectionInfo[$TargetName]
        if (-not $ConnInfo.HostName) {
            $Result[$TargetName] = [PSCustomObject]@{
                KeyAuthWorks = $false
                PasswordUsed = $false
                Message      = 'Target unreachable.'
            }
            continue
        }

        $ExamTarget = $Exam.Targets[$TargetName]
        if (-not $ExamTarget) { continue }

        $AuthParams = @{
            HostName       = $ConnInfo.HostName
            Port           = $ConnInfo.Port
            UserName       = $ExamTarget.UserName
            KeyFilePath    = $PrivateKeyPath
            TimeoutSeconds = 10
        }
        $AuthWorks = Test-SshKeyAuth @AuthParams

        if ($AuthWorks) {
            Write-Host "    $TargetName — key auth OK" -ForegroundColor Green
            $Result[$TargetName] = [PSCustomObject]@{
                KeyAuthWorks = $true
                PasswordUsed = $false
                Message      = 'Key authentication verified.'
            }
        }
        else {
            Write-Host "    $TargetName — key auth FAILED (key not yet installed)" -ForegroundColor Yellow
            $FailingTargets.Add($TargetName)
        }
    }

    # ── Step 3: If all targets pass, we are done ───────────────────────────────
    if ($FailingTargets.Count -eq 0) {
        Write-Host '  All targets authenticated successfully.' -ForegroundColor Green
        return $Result
    }

    # ── Step 4: Ask for password once ──────────────────────────────────────────
    Write-Host ''
    Write-Host "  $($FailingTargets.Count) target(s) need SSH key installation." -ForegroundColor Yellow
    Write-Host '  A password is required to copy the public key to these machines.' -ForegroundColor Yellow
    Write-Host ''

    $PasswordInput = Read-Host '  Enter SSH password for the remote machines' -MaskInput

    if ([string]::IsNullOrWhiteSpace($PasswordInput)) {
        Write-Host '  No password provided. Skipping key installation.' -ForegroundColor Yellow
        foreach ($TargetName in $FailingTargets) {
            $Result[$TargetName] = [PSCustomObject]@{
                KeyAuthWorks = $false
                PasswordUsed = $false
                Message      = 'No password provided for key installation.'
            }
        }
        return $Result
    }

    $SecureCredential = ConvertTo-SecureString -String $PasswordInput -AsPlainText -Force

    # ── Step 5: Distribute key to failing targets ──────────────────────────────
    Write-Host ''
    Write-Host '  Installing SSH public key on remote targets...' -ForegroundColor Cyan

    foreach ($TargetName in $FailingTargets) {
        $ConnInfo = $ConnectionInfo[$TargetName]
        $ExamTarget = $Exam.Targets[$TargetName]

        Write-Host "    $TargetName ($($ConnInfo.HostName):$($ConnInfo.Port))..." -ForegroundColor DarkGray

        $InstallParams = @{
            HostName         = $ConnInfo.HostName
            Port             = $ConnInfo.Port
            UserName         = $ExamTarget.UserName
            PublicKeyContent = $PublicKeyContent
            Platform         = $ExamTarget.Platform
        }
        $ParamPasswordName = 'Password'
        $InstallParams[$ParamPasswordName] = $SecureCredential
        $InstallResult = Install-SshKeyOnTarget @InstallParams

        if ($InstallResult.Success) {
            Write-Host "    $TargetName — key installed" -ForegroundColor Green
        }
        else {
            Write-Host "    $TargetName — install FAILED: $($InstallResult.Message)" -ForegroundColor Red
        }
    }

    # ── Step 6: Re-test key auth on targets that received the key ──────────────
    Write-Host ''
    Write-Host '  Re-testing SSH key authentication...' -ForegroundColor Cyan

    foreach ($TargetName in $FailingTargets) {
        $ConnInfo = $ConnectionInfo[$TargetName]
        $ExamTarget = $Exam.Targets[$TargetName]

        $AuthParams = @{
            HostName       = $ConnInfo.HostName
            Port           = $ConnInfo.Port
            UserName       = $ExamTarget.UserName
            KeyFilePath    = $PrivateKeyPath
            TimeoutSeconds = 10
        }
        $AuthWorks = Test-SshKeyAuth @AuthParams

        if ($AuthWorks) {
            Write-Host "    $TargetName — key auth OK" -ForegroundColor Green
            $Result[$TargetName] = [PSCustomObject]@{
                KeyAuthWorks = $true
                PasswordUsed = $true
                Message      = 'Key installed and verified.'
            }
        }
        else {
            Write-Host "    $TargetName — key auth still FAILED" -ForegroundColor Red
            $Result[$TargetName] = [PSCustomObject]@{
                KeyAuthWorks = $false
                PasswordUsed = $true
                Message      = 'Key installed but verification failed.'
            }
        }
    }

    return $Result
}
