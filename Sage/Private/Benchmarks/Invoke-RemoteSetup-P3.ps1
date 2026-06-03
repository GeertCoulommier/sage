#Requires -Version 7.5
<#
.SYNOPSIS
    P3 optimized Invoke-RemoteSetup: skips copying files that already exist
    on the remote VM with identical content.
.DESCRIPTION
    Drop-in replacement for Invoke-RemoteSetup that adds a hash-based file
    existence check before each Copy-File call.  If the remote VM already has
    a file at the destination path with the same hash as the local file,
    the copy is skipped.

    This is particularly effective in multi-student exams where all students
    share the same infrastructure (same VMs): after the first student's setup,
    all subsequent students skip 100% of file copies because the scripts
    are already present and unchanged.

    IMPLEMENTATION
    ──────────────
    1. Build a list of all collector and evaluator files to copy.
    2. Issue one batched Invoke-Command to retrieve hashes of all files
       that exist at the expected remote paths.
    3. Compare with local hashes; copy only files that differ or are absent.

    The batch hash check costs 1 Invoke-Command round-trip per target instead
    of N individual mkdir+copy round-trips.  Break-even: if more than ~2 files
    are already present and unchanged, this optimization is net positive.
.PARAMETER RemoteSession
    Active Sage.RemoteSession returned by New-RemoteSession.
.PARAMETER Dependencies
    Hashtable from exam.psd1 Dependencies key.
.PARAMETER EvaluationsPath
    Optional path to the directory containing evaluation scripts.
.OUTPUTS
    [void]
.EXAMPLE
    Invoke-RemoteSetup-P3 -RemoteSession $Session -Dependencies @{ Modules = @('Pester') }
#>
function Invoke-RemoteSetup-P3 {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '',
        Justification = '$env:TEMP inside Invoke-Command intentionally references the remote environment.')]
    param(
        [Parameter(Mandatory)][PSTypeName('Sage.RemoteSession')]                   [PSCustomObject] $RemoteSession,
        [Parameter()]                                                                   [hashtable] $Dependencies = @{ Modules = @() },
        [Parameter()][ValidateNotNullOrEmpty()]                                            [string] $EvaluationsPath
    )

    $ErrorActionPreference = 'Stop'

    $Session = $RemoteSession.Session
    $TargetName = $RemoteSession.TargetName
    $IsRemoteWindows = $RemoteSession.Platform -eq 'Windows'
    $RemoteTempBase = if ($IsRemoteWindows) { $null } else { '/tmp' }

    # ── 1. Module check (same as original) ──────────────────────────────────
    $ModuleList = $Dependencies.Modules
    if (-not $ModuleList) { $ModuleList = @() }

    foreach ($ModuleName in $ModuleList) {
        $Installed = Invoke-Command -Session $Session -ScriptBlock {
            $minVersion = if ($using:ModuleName -eq 'Pester') { [Version]'5.0.0' } else { [Version]'0.0.0' }
            $null -ne (Get-Module -Name $using:ModuleName -ListAvailable -ErrorAction SilentlyContinue |
                    Where-Object { [Version]$_.Version -ge $minVersion } |
                    Select-Object -First 1)
        }

        if (-not $Installed) {
            try {
                Invoke-Command -Session $Session -ScriptBlock {
                    Install-Module -Name $using:ModuleName -Force -Scope CurrentUser -ErrorAction Stop
                }
            }
            catch {
                Write-Warning "[P3] Install-Module '$ModuleName' failed on '$TargetName': $($_.Exception.Message)"
            }
        }
    }

    # ── Helper: compute local file hashes in batch ───────────────────────────
    function Get-LocalFileHash {
        [CmdletBinding()]
        [OutputType([hashtable])]
        param([Parameter(Mandatory)] [System.IO.FileInfo[]] $Files)
        $Hashes = @{}
        foreach ($File in $Files) {
            $Hashes[$File.Name] = (Get-FileHash -Path $File.FullName).Hash
        }
        $Hashes
    }

    # ── Helper: compute remote file hashes in one Invoke-Command ─────────────
    function Get-RemoteFileHash {
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $RemoteSession,
            [Parameter(Mandatory)] [string] $RemoteDir
        )
        $RemoteResult = Invoke-Command -Session $RemoteSession -ScriptBlock {
            $Dir = $using:RemoteDir
            if (-not (Test-Path $Dir)) { return @{} }
            $Result = @{}
            Get-ChildItem -Path $Dir -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
                $Result[$_.Name] = (Get-FileHash $_.FullName -ErrorAction SilentlyContinue).Hash
            }
            $Result
        }
        if (-not $RemoteResult) { return @{} }
        # Convert deserialized hashtable back to a plain hashtable
        $Plain = @{}
        foreach ($Key in $RemoteResult.Keys) { $Plain[$Key] = $RemoteResult[$Key] }
        $Plain
    }

    # ── Helper: copy only changed/missing files ───────────────────────────────
    function Copy-ChangedFile {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [System.IO.FileInfo[]] $LocalFiles,
            [Parameter(Mandatory)] [hashtable]            $LocalHashes,
            [Parameter(Mandatory)] [hashtable]            $RemoteHashes,
            [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $RemoteSession,
            [Parameter(Mandatory)] [string]               $RemoteDir,
            [Parameter(Mandatory)] [bool]                 $IsRemoteWindows,
            [Parameter(Mandatory)] [string]               $Label
        )
        $Copied = 0
        $Skipped = 0
        foreach ($File in $LocalFiles) {
            $FileName = $File.Name
            $RemoteHash = $RemoteHashes[$FileName]
            $LocalHash = $LocalHashes[$FileName]

            if ($RemoteHash -and $RemoteHash -eq $LocalHash) {
                $Skipped++
                continue
            }

            $RemotePath = if ($IsRemoteWindowsOS) {
                Invoke-Command -Session $RemoteSession -ScriptBlock { Join-Path $using:RemoteDir $using:FileName }
            }
            else {
                "$RemoteDir/$FileName"
            }
            Copy-File -Session $RemoteSession -LocalPath $File.FullName -RemotePath $RemotePath
            $Copied++
        }
        Write-Verbose "[P3] $Label — copied: $Copied, skipped (unchanged): $Skipped"
    }

    # ── 2. Copy collector scripts (P3 optimized) ──────────────────────────────
    $CollectorsPath = Join-Path $PSScriptRoot '..' '..' 'Collectors'
    if (Test-Path $CollectorsPath) {
        $RemoteCollectors = if ($IsRemoteWindows) {
            Invoke-Command -Session $Session -ScriptBlock { Join-Path $env:TEMP 'sage-collectors' }
        }
        else { "$RemoteTempBase/sage-collectors" }

        Invoke-Command -Session $Session -ScriptBlock {
            if (-not (Test-Path $using:RemoteCollectors)) {
                New-Item -ItemType Directory -Path $using:RemoteCollectors -Force | Out-Null
            }
        }

        $Collectors = @(Get-ChildItem -Path $CollectorsPath -Filter '*.ps1')
        $LocalHashes = Get-LocalFileHashes -Files $Collectors
        $RemoteHashes = Get-RemoteFileHashes -RemoteSession $Session -RemoteDir $RemoteCollectors

        $CopyParams = @{
            LocalFiles    = $Collectors
            LocalHashes   = $LocalHashes
            RemoteHashes  = $RemoteHashes
            RemoteSession = $Session
            RemoteDir     = $RemoteCollectors
            IsRemoteWindows     = $IsRemoteWindows
            Label         = "Collectors on '$TargetName'"
        }
        Copy-ChangedFiles @CopyParams
    }

    # ── 3. Copy evaluation scripts (P3 optimized) ──────────────────────────────
    if (-not $EvaluationsPath) {
        $EvaluationsPath = Join-Path $PSScriptRoot '..' '..' 'Evaluators'
    }
    if (Test-Path $EvaluationsPath) {
        $RemoteEvals = if ($IsRemoteWindows) {
            Invoke-Command -Session $Session -ScriptBlock { Join-Path $env:TEMP 'sage-evaluations' }
        }
        else { "$RemoteTempBase/sage-evaluations" }

        Invoke-Command -Session $Session -ScriptBlock {
            if (-not (Test-Path $using:RemoteEvals)) {
                New-Item -ItemType Directory -Path $using:RemoteEvals -Force | Out-Null
            }
        }

        $EvalFiles = @(Get-ChildItem -Path $EvaluationsPath -Filter '*.ps1')
        $LocalHashes = Get-LocalFileHashes -Files $EvalFiles
        $RemoteHashes = Get-RemoteFileHashes -RemoteSession $Session -RemoteDir $RemoteEvals

        $CopyParams = @{
            LocalFiles    = $EvalFiles
            LocalHashes   = $LocalHashes
            RemoteHashes  = $RemoteHashes
            RemoteSession = $Session
            RemoteDir     = $RemoteEvals
            IsRemoteWindows     = $IsRemoteWindows
            Label         = "Evaluators on '$TargetName'"
        }
        Copy-ChangedFiles @CopyParams
    }
}
