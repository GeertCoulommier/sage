#Requires -Version 7.5
<#
.SYNOPSIS
    Performs connectivity and environment diagnostics for a remote evaluation target.
.DESCRIPTION
    Runs a sequence of pre-flight checks against a single target VM:
      1. TCP port reachability test (Test-Connection / TcpClient).
      2. SSH session establishment via New-RemoteSession.
      3. PowerShell version check on the remote host.
      4. Required module availability (Pester) on the remote host.

    Each step results in a pass/fail entry in the returned Sage.DiagnosticResult
    object.  The function does NOT throw on individual step failures — it records
    all outcomes so the caller can review the full diagnostic report.
.PARAMETER HostName
    DNS name or IP address of the target VM.
.PARAMETER Port
    SSH port number (1–65535).
.PARAMETER UserName
    SSH user name on the remote host.
.PARAMETER TargetName
    Logical target name, used for logging and result identification.
.PARAMETER Platform
    Operating system of the remote target.  'Windows' or 'Linux'.
.PARAMETER Credential
    Optional PSCredential for authentication.
.PARAMETER KeyFilePath
    Path to an SSH private key file.
.PARAMETER Dependencies
    Hashtable from exam.psd1 Dependencies key.  Expected shape:
      @{ Modules = @('Pester') }
.OUTPUTS
    [PSCustomObject] typed as 'Sage.DiagnosticResult'
.EXAMPLE
    $diagParams = @{
        HostName    = '10.2.3.4'
        Port        = 20022
        UserName    = 'student'
        TargetName  = 'LinuxVM'
        Platform    = 'Linux'
        KeyFilePath = '~/.ssh/id_rsa'
    }
    $result = Invoke-Diagnostic @diagParams
    $result.Steps | Format-Table Name, Passed, Message
#>
function Invoke-Diagnostic {
    [CmdletBinding()]
    [OutputType('Sage.DiagnosticResult')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $HostName,
        [Parameter(Mandatory)][ValidateRange(1, 65535)]                                       [int] $Port,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $UserName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TargetName,
        [Parameter(Mandatory)][ValidateSet('Windows', 'Linux')]                            [string] $Platform,
        [Parameter()][System.Management.Automation.PSCredential]                                    $Credential,
        [Parameter()]                                                                      [string] $KeyFilePath,
        [Parameter()]                                                                   [hashtable] $Dependencies = @{ Modules = @() }
    )

    $ErrorActionPreference = 'Stop'

    $Steps = [System.Collections.Generic.List[object]]::new()
    $OverallPassed = $true
    $Session = $null

    $LogParams = @{
        Level    = 'Info'
        Category = 'Diagnostic'
        Message  = "Starting diagnostics for '$TargetName' (${HostName}:$Port)."
        Target   = $TargetName
    }
    Write-Log @LogParams

    # ── Step 1: TCP port reachability ──────────────────────────────────────────
    $Step1 = [PSCustomObject]@{
        Name    = 'TCP Port Reachability'
        Passed  = $false
        Message = ''
    }
    try {
        $TcpClient = [System.Net.Sockets.TcpClient]::new()
        $ConnectTask = $TcpClient.ConnectAsync($HostName, $Port)
        $Completed = $ConnectTask.Wait(5000)
        if ($Completed -and $TcpClient.Connected) {
            $Step1.Passed = $true
            $Step1.Message = "Port $Port is reachable on $HostName."
        }
        else {
            $Step1.Message = "Port $Port is not reachable on $HostName (timeout after 5s)."
            $OverallPassed = $false
        }
        $TcpClient.Dispose()
    }
    catch {
        $Step1.Message = "TCP connection to ${HostName}:$Port failed: $($_.Exception.Message)"
        $OverallPassed = $false
    }
    $Steps.Add($Step1)

    # ── Step 2: SSH session ────────────────────────────────────────────────────
    $Step2 = [PSCustomObject]@{
        Name    = 'SSH Session'
        Passed  = $false
        Message = ''
    }
    if ($Step1.Passed) {
        try {
            $SessionParams = @{
                HostName   = $HostName
                Port       = $Port
                UserName   = $UserName
                TargetName = $TargetName
                Platform   = $Platform
                MaxRetries = 1
            }
            if ($Credential) {
                $SessionParams['Credential'] = $Credential
            }
            if ($KeyFilePath) {
                $SessionParams['KeyFilePath'] = $KeyFilePath
            }

            $RemoteSession = New-RemoteSession @SessionParams
            $Session = $RemoteSession.Session
            $Step2.Passed = $true
            $Step2.Message = "SSH session established to ${HostName}:$Port as '$UserName'."
        }
        catch {
            $Step2.Message = "SSH session failed: $($_.Exception.Message)"
            $OverallPassed = $false
        }
    }
    else {
        $Step2.Message = 'Skipped — TCP port not reachable.'
        $OverallPassed = $false
    }
    $Steps.Add($Step2)

    # ── Step 3: Remote PowerShell version ──────────────────────────────────────
    $Step3 = [PSCustomObject]@{
        Name    = 'Remote PowerShell Version'
        Passed  = $false
        Message = ''
    }
    if ($Step2.Passed) {
        try {
            $RemoteVersion = Invoke-Command -Session $Session -ScriptBlock {
                $PSVersionTable.PSVersion.ToString()
            }
            $Step3.Passed = $true
            $Step3.Message = "Remote PowerShell version: $RemoteVersion."
        }
        catch {
            $Step3.Message = "Failed to query PowerShell version: $($_.Exception.Message)"
            $OverallPassed = $false
        }
    }
    else {
        $Step3.Message = 'Skipped — no SSH session available.'
        $OverallPassed = $false
    }
    $Steps.Add($Step3)

    # ── Step 4: Required module availability ───────────────────────────────────
    $ModuleList = @()
    if ($Dependencies -and $Dependencies.Modules) {
        $ModuleList = @($Dependencies.Modules)
    }

    $Step4 = [PSCustomObject]@{
        Name    = 'Required Modules'
        Passed  = $false
        Message = ''
    }
    if ($Step2.Passed -and $ModuleList.Count -gt 0) {
        try {
            $MissingModules = Invoke-Command -Session $Session -ScriptBlock {
                $Missing = @()
                foreach ($M in $using:ModuleList) {
                    $Found = Get-Module -Name $M -ListAvailable -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    if (-not $Found) { $Missing += $M }
                }
                $Missing
            }
            if ($MissingModules.Count -eq 0) {
                $Step4.Passed = $true
                $Step4.Message = "All required modules present: $($ModuleList -join ', ')."
            }
            else {
                $Step4.Message = "Missing modules: $($MissingModules -join ', ')."
                $OverallPassed = $false
            }
        }
        catch {
            $Step4.Message = "Module check failed: $($_.Exception.Message)"
            $OverallPassed = $false
        }
    }
    elseif ($Step2.Passed -and $ModuleList.Count -eq 0) {
        $Step4.Passed = $true
        $Step4.Message = 'No required modules specified.'
    }
    else {
        $Step4.Message = 'Skipped — no SSH session available.'
        $OverallPassed = $false
    }
    $Steps.Add($Step4)

    # ── Cleanup session ────────────────────────────────────────────────────────
    if ($RemoteSession) {
        try {
            Close-RemoteSession -Session $RemoteSession
        }
        catch {
            $LogParams = @{
                Level    = 'Warning'
                Category = 'Diagnostic'
                Message  = "Failed to close diagnostic session for '$TargetName': $($_.Exception.Message)"
                Target   = $TargetName
            }
            Write-Log @LogParams
        }
    }

    $LogParams = @{
        Level    = 'Info'
        Category = 'Diagnostic'
        Message  = "Diagnostics for '$TargetName' completed. Overall: $(if ($OverallPassed) { 'PASS' } else { 'FAIL' })."
        Target   = $TargetName
    }
    Write-Log @LogParams

    [PSCustomObject]@{
        PSTypeName = 'Sage.DiagnosticResult'
        TargetName = $TargetName
        HostName   = $HostName
        Port       = $Port
        Platform   = $Platform
        Passed     = $OverallPassed
        Steps      = $Steps.ToArray()
        Timestamp  = [datetime]::Now
    }
}
