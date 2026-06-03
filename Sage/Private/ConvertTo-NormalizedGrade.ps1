#Requires -Version 7.5
<#
.SYNOPSIS
    Converts a raw score to a normalized grade on a configurable scale.
.DESCRIPTION
    Divides RawScore by MaxScore and multiplies by Scale (default 20),
    rounding to two decimal places. Used by Get-GradeSummary to convert
    per-category raw scores to /20 values and to compute the total /20.
.PARAMETER RawScore
    The raw score achieved (sum of PassGrade for passing tests). Must be
    between 0 and MaxScore (inclusive).
.PARAMETER MaxScore
    The maximum achievable raw score (sum of all PassGrades). Must be > 0.
.PARAMETER Scale
    Target scale for the normalized grade. Defaults to 20.
.OUTPUTS
    [double]
.EXAMPLE
    ConvertTo-NormalizedGrade -RawScore 12 -MaxScore 15
    # Returns 16.0
.EXAMPLE
    ConvertTo-NormalizedGrade -RawScore 6 -MaxScore 14
    # Returns 8.57
#>
function ConvertTo-NormalizedGrade {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)][ValidateRange(0, [double]::MaxValue)]                        [double] $RawScore,
        [Parameter(Mandatory)][ValidateRange(1, [double]::MaxValue)]                        [double] $MaxScore,
        [Parameter()]         [ValidateRange(1, 100)]                                       [double] $Scale = 20
    )

    [Math]::Round(($RawScore / $MaxScore) * $Scale, 2)
}
