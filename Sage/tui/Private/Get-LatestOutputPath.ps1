#Requires -Version 7.5
<#
.SYNOPSIS
    Returns the most recent timestamped output directory path.
.DESCRIPTION
    Scans the output directory for timestamped subdirectories (yyyy-MM-dd_HHmmss
    format) and returns the path to the most recent one.  Returns $null if no
    output directories exist.
.PARAMETER OutputDir
    Root output directory to scan.
.OUTPUTS
    [string] — Path to the latest output directory, or $null if none exist.
.EXAMPLE
    $Latest = Get-LatestOutputPath -OutputDir './output'
#>
function Get-LatestOutputPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $OutputDir
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $OutputDir)) {
        return $null
    }

    $Dirs = Get-ChildItem -Path $OutputDir -Directory |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{6}$' } |
        Sort-Object -Property Name -Descending

    if ($Dirs.Count -eq 0) {
        return $null
    }

    return $Dirs[0].FullName
}
