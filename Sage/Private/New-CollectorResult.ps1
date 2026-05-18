#Requires -Version 7.5
<#
.SYNOPSIS
    Creates a Sage.CollectorResult PSCustomObject.
.DESCRIPTION
    Factory function for collector output. Available=$false indicates that
    the target service/role is absent; the Reason property explains why.
    An available collector always returns a typed Data hashtable and an
    Errors array (zero-length on clean success).
.PARAMETER CollectorName
    Short name of the collector (e.g. 'Dns', 'Docker').
.PARAMETER Available
    Whether the target service/role was reachable and returned data.
.PARAMETER Reason
    Human-readable reason when Available is $false.
.PARAMETER Data
    Hashtable of structured data returned by the collector script.
.PARAMETER Errors
    Array of non-fatal error strings encountered during collection.
.PARAMETER Duration
    Elapsed time of the remote collection run.
.OUTPUTS
    [PSCustomObject] typed as 'Sage.CollectorResult'
.EXAMPLE
    $result = New-CollectorResult -CollectorName 'Dns' -Available $true -Data @{ Zones = @('zinneke.be') }
    # Returns a Sage.CollectorResult with Available=$true and the provided Data.
#>
function New-CollectorResult {
    [CmdletBinding()]
    [OutputType('Sage.CollectorResult')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $CollectorName,
        [Parameter(Mandatory)]                                                               [bool] $Available,
        [Parameter()]                                                                      [string] $Reason,
        [Parameter()]                                                                   [hashtable] $Data = @{},
        [Parameter()]                                                                    [string[]] $Errors = @(),
        [Parameter()]                                                                    [timespan] $Duration = [timespan]::Zero
    )

    [PSCustomObject]@{
        PSTypeName    = 'Sage.CollectorResult'
        CollectorName = $CollectorName
        Available     = $Available
        Reason        = $Reason
        Data          = $Data
        Errors        = $Errors
        Duration      = $Duration
    }
}
