#Requires -Version 7.5
<#
.SYNOPSIS
    Creates a Sage.TestResult PSCustomObject.
.DESCRIPTION
    Factory function for grading results. Every row in the output set is a
    TestResult. The FinalGrade property reflects any manual override when one
    has been applied; otherwise it equals AwardedGrade.
.PARAMETER StudentEmail
    Student email address for traceability.
.PARAMETER StudentName
    Student display name.
.PARAMETER StudentData
    Full CSV-row hashtable — all roster fields preserved on each result.
.PARAMETER TargetName
    Logical target name (from exam.psd1) this test ran against.
.PARAMETER Category
    Category name from exam.psd1.
.PARAMETER TestName
    Pester test description string.
.PARAMETER Context
    Pester Context (Describe/Context block name) this test belongs to.
.PARAMETER Passed
    Whether the Pester test passed.
.PARAMETER PassGrade
    Points awarded when the test passes.
.PARAMETER FailGrade
    Points awarded when the test fails (default 0).
.PARAMETER ActualValue
    Actual value produced by the system under test (from Pester error message).
.PARAMETER ExpectedValue
    Expected value declared in the test assertion (from Pester error message).
.PARAMETER ErrorMessage
    Full error message from a failed Pester assertion.
.PARAMETER ReviewData
    Structured data extracted by a ReviewContextMap scriptblock for manual review.
.PARAMETER ReviewContextName
    Pester Context name used to look up the ReviewContextMap entry.
.OUTPUTS
    [PSCustomObject] typed as 'Sage.TestResult'
.EXAMPLE
    $gradeParams = @{
        StudentEmail = 'jan@ehb.be'
        StudentName  = 'Jan Appel'
        StudentData  = @{ pointer = '42' }
        TargetName   = 'WinSrv1'
        Category     = 'DNS'
        TestName     = 'A record dc1 resolves'
        Passed       = $true
        PassGrade    = 3
    }
    $result = New-GradeResult @gradeParams
    # Returns a Sage.TestResult with AwardedGrade=3 and FinalGrade=3.
#>
function New-GradeResult {
    [CmdletBinding()]
    [OutputType('Sage.TestResult')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $StudentEmail,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $StudentName,
        [Parameter(Mandatory)]                                                          [hashtable] $StudentData,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TargetName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $Category,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TestName,
        [Parameter()]                                                                      [string] $Context,
        [Parameter(Mandatory)]                                                               [bool] $Passed,
        [Parameter(Mandatory)][ValidateRange(0, 100)]                                      [double] $PassGrade,
        [Parameter()]         [ValidateRange(0, 100)]                                      [double] $FailGrade = 0,
        [Parameter()]                                                                      [string] $ActualValue,
        [Parameter()]                                                                      [string] $ExpectedValue,
        [Parameter()]                                                                      [string] $ErrorMessage,
        [Parameter()]                                                                      [object] $ReviewData,
        [Parameter()]                                                                      [string] $ReviewContextName
    )

    $Awarded = if ($Passed) { $PassGrade } else { $FailGrade }

    [PSCustomObject]@{
        PSTypeName           = 'Sage.TestResult'
        StudentEmail         = $StudentEmail
        StudentName          = $StudentName
        StudentData          = $StudentData
        TargetName           = $TargetName
        Category             = $Category
        TestName             = $TestName
        Context              = $Context
        Passed               = $Passed
        PassGrade            = $PassGrade
        FailGrade            = $FailGrade
        AwardedGrade         = $Awarded
        ActualValue          = $ActualValue
        ExpectedValue        = $ExpectedValue
        ManualOverrideGrade  = $null
        ManualOverrideReason = $null
        FinalGrade           = $Awarded   # updated by Edit-Grade when overridden
        ErrorMessage         = $ErrorMessage
        ReviewData           = $ReviewData
        ReviewContextName    = $ReviewContextName
        Timestamp            = [datetime]::Now
    }
}
