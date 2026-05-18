#Requires -Version 7.5
<#
.SYNOPSIS
    Builds werkcolleges target sets from a roster CSV and invokes Install-SshKey.
.DESCRIPTION
    Reads the werkcolleges roster CSV (semicolon-delimited with columns: ip, email,
    student) and the exam definition (Sage/data/werkcolleges/Server OS - labo 5 - Group Policy en DHCP.psd1) to construct one
    computer set per student.  Each set contains the 4 target VMs (Linux, DC1, DC2,
    Client) at the student's public hostname with the corresponding SSH ports.

    The script then calls Install-SshKey to distribute SSH keys among the computers
    in each set so they can authenticate to each other without passwords.
.PARAMETER RosterPath
    Path to the semicolon-delimited roster CSV.
.PARAMETER ThrottleLimit
    Maximum concurrent sets.  Default 10.
.PARAMETER ShareKeys
    Copy the key pair from the first set to all subsequent sets instead of
    generating unique keys per set.
.PARAMETER Force
    Overwrite existing SSH keys on remote computers.
.PARAMETER KeyFilePath
    Path to an SSH private key file for initial connection to the VMs.
.EXAMPLE
    ./tools/Install-SshKeys.ps1 -RosterPath ./Sage/data/exams/werkcolleges-2526/roster.csv
.EXAMPLE
    ./tools/Install-SshKeys.ps1 -RosterPath ./roster.csv -ShareKeys -ThrottleLimit 5
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })] [string] $RosterPath,
    [Parameter()]         [ValidateRange(1, 50)]                               [int] $ThrottleLimit = 10,
    [Parameter()]                                                           [switch] $ShareKeys,
    [Parameter()]                                                           [switch] $Force,
    [Parameter()]                                                           [string] $KeyFilePath
)

$ErrorActionPreference = 'Stop'

# ── Import SAGE module ─────────────────────────────────────────────────────────
$ModulePath = Join-Path $PSScriptRoot '..' 'Sage' 'Sage.psd1'
Import-Module $ModulePath -Force

# ── Target definition (from CLAUDE.md / data/werkcolleges/ exam) ──────────────
# Each student's public hostname is the 'ip' column.  The VMs are accessible
# on different SSH ports:
#   Linux  — port 20022, user student
#   DC1    — port 30022, user administrator
#   DC2    — port 40022, user administrator
#   Client — port 50022, user student
$TargetTemplates = @(
    @{
        Name     = 'Linux'
        Port     = 20022
        UserName = 'student'
        Platform = 'Linux'
    }
    @{
        Name     = 'DC1'
        Port     = 30022
        UserName = 'administrator'
        Platform = 'Windows'
    }
    @{
        Name     = 'DC2'
        Port     = 40022
        UserName = 'administrator'
        Platform = 'Windows'
    }
    @{
        Name     = 'Client'
        Port     = 50022
        UserName = 'student'
        Platform = 'Windows'
    }
)

# ── Read roster CSV ────────────────────────────────────────────────────────────
$CsvParams = @{
    Path      = $RosterPath
    Delimiter = ';'
    Encoding  = 'UTF8'
}
$Students = @(Import-Csv @CsvParams)

if ($Students.Count -eq 0) {
    throw "Roster CSV '$RosterPath' contains no student rows."
}

Write-Host "Found $($Students.Count) student(s) in roster." -ForegroundColor Cyan

# ── Build computer sets ────────────────────────────────────────────────────────
$ComputerSets = [System.Collections.Generic.List[hashtable[]]]::new()

foreach ($Student in $Students) {
    $HostName = $Student.ip
    $StudentName = $Student.student

    Write-Host "  Building set for '$StudentName' ($HostName)..." -ForegroundColor Gray

    $Set = @()
    foreach ($Template in $TargetTemplates) {
        $Computer = @{
            HostName = $HostName
            Port     = $Template.Port
            UserName = $Template.UserName
            Platform = $Template.Platform
            Name     = "$StudentName-$($Template.Name)"
        }
        if ($KeyFilePath) {
            $Computer['KeyFilePath'] = $KeyFilePath
        }
        $Set += $Computer
    }
    $ComputerSets.Add([hashtable[]]$Set)
}

Write-Host "`nDistributing SSH keys across $($ComputerSets.Count) set(s)..." -ForegroundColor Cyan

# ── Invoke Install-SshKey ──────────────────────────────────────────────────────
$Params = @{
    ComputerSets  = $ComputerSets.ToArray()
    ThrottleLimit = $ThrottleLimit
}
if ($ShareKeys) { $Params['ShareKeys'] = $true }
if ($Force) { $Params['Force'] = $true }

$Results = Install-SshKey @Params

# ── Display summary ────────────────────────────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   '║      SSH Key Distribution Summary     ║' -ForegroundColor Cyan
Write-Host   '╚══════════════════════════════════════╝' -ForegroundColor Cyan

foreach ($Result in $Results) {
    $Status = if ($Result.Errors.Count -eq 0) { 'OK' } else { 'ERRORS' }
    $Color = if ($Result.Errors.Count -eq 0) { 'Green' } else { 'Red' }
    $TestPass = ($Result.TestResults | Where-Object { $_.Success }).Count
    $TestTotal = $Result.TestResults.Count

    Write-Host "`n  Set $($Result.SetIndex): $($Result.Computers -join ', ')" -ForegroundColor White
    Write-Host "    Keys generated:   $($Result.KeysGenerated)" -ForegroundColor Gray
    Write-Host "    Keys distributed: $($Result.KeysDistributed)" -ForegroundColor Gray
    Write-Host "    SSH tests:        $TestPass/$TestTotal passed" -ForegroundColor Gray
    Write-Host "    Status:           $Status" -ForegroundColor $Color

    if ($Result.Errors.Count -gt 0) {
        foreach ($Err in $Result.Errors) {
            Write-Host "    ERROR: $Err" -ForegroundColor Red
        }
    }
}

$Results
