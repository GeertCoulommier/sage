#Requires -Version 7.5
<#
.SYNOPSIS
    Aggregates Sage.TestResult objects into a Sage.StudentGradeSummary.
.DESCRIPTION
    Groups TestResult objects by Category and computes per-category scores:
      - RawScore  : sum of FinalGrade (reflects any manual overrides)
      - MaxScore  : sum of PassGrade  (maximum achievable per category)
      - NormalizedScore : RawScore/MaxScore * 20, rounded to 2 decimal places

    Also computes an overall TotalScore across all categories using the same
    normalization.  The full TestResult array is preserved in the returned
    Sage.StudentGradeSummary so that Export-GradeSummary and Edit-Grade can
    operate from a single structured object.

    Supports both direct array (`-TestResult`) and pipeline input.  An empty
    or null input produces a summary with zero scores and an empty TestResults
    array.
.PARAMETER TestResult
    One or more Sage.TestResult objects to aggregate.  Accepts pipeline input.
    Pass an empty array to produce a zero-score summary.
.PARAMETER StudentEmail
    Student email address — stored on the summary header for traceability.
.PARAMETER StudentName
    Student display name.
.PARAMETER StudentData
    Full CSV-row hashtable (all roster fields) carried through to the summary.
.PARAMETER ExamName
    Exam name from exam.psd1 — stored on the summary for context.
.OUTPUTS
    [PSCustomObject] typed as 'Sage.StudentGradeSummary'
.EXAMPLE
    $convertParams = @{
        PesterResult = $pr
        StudentEmail = 'a@ehb.be'
        StudentName  = 'Daan Banaan'
        StudentData  = $row
        TargetName   = 'WinSrv1'
        Category     = 'DNS'
    }
    $results = ConvertTo-GradeSummary @convertParams
    $summaryParams = @{
        StudentEmail = 'a@ehb.be'
        StudentName  = 'Daan Banaan'
        StudentData  = $row
        ExamName     = 'OSII-25-08'
    }
    $summary = Get-GradeSummary -TestResult $results @summaryParams
.EXAMPLE
    $summaryParams = @{
        StudentEmail = 'a@ehb.be'
        StudentName  = 'Daan Banaan'
        StudentData  = $row
        ExamName     = 'OSII-25-08'
    }
    $results | Get-GradeSummary @summaryParams
#>
function Get-GradeSummary {
    [CmdletBinding()]
    [OutputType('Sage.StudentGradeSummary')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowEmptyCollection()]                [object[]] $TestResult,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $StudentEmail,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $StudentName,
        [Parameter(Mandatory)]                                                          [hashtable] $StudentData,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ExamName
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $AllResults = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($R in $TestResult) {
            if ($null -ne $R) {
                $AllResults.Add($R)
            }
        }
    }

    end {
        # ── Per-category aggregation ───────────────────────────────────────────────
        $CategoryScores = [System.Collections.Generic.List[object]]::new()

        if ($AllResults.Count -gt 0) {
            $Groups = $AllResults | Group-Object -Property Category

            foreach ($Group in $Groups) {
                $RawScore = [double](($Group.Group |
                            Measure-Object -Property FinalGrade -Sum).Sum)
                $MaxScore = [double](($Group.Group |
                            Measure-Object -Property PassGrade -Sum).Sum)

                $Normalized = if ($MaxScore -gt 0) {
                    ConvertTo-NormalizedGrade -RawScore $RawScore -MaxScore $MaxScore
                }
                else { 0.0 }

                $PassedCount = @($Group.Group | Where-Object { $_.Passed -eq $true }).Count
                $FailedCount = @($Group.Group | Where-Object { $_.Passed -eq $false }).Count
                $TargetName = $Group.Group[0].TargetName

                $CategoryScores.Add([PSCustomObject]@{
                        PSTypeName      = 'Sage.CategoryGradeSummary'
                        Category        = $Group.Name
                        TargetName      = $TargetName
                        RawScore        = $RawScore
                        MaxScore        = $MaxScore
                        NormalizedScore = $Normalized
                        TestCount       = $Group.Count
                        PassedCount     = $PassedCount
                        FailedCount     = $FailedCount
                    })
            }
        }

        # ── Overall totals ─────────────────────────────────────────────────────────
        $TotalRaw = [double](($CategoryScores |
                    Measure-Object -Property RawScore -Sum).Sum)
        $TotalMax = [double](($CategoryScores |
                    Measure-Object -Property MaxScore -Sum).Sum)

        $TotalNorm = if ($TotalMax -gt 0) {
            ConvertTo-NormalizedGrade -RawScore $TotalRaw -MaxScore $TotalMax
        }
        else { 0.0 }

        $OverrideCount = @($AllResults |
                Where-Object { $null -ne $_.ManualOverrideGrade }).Count

        $TotalScore = [PSCustomObject]@{
            Raw        = $TotalRaw
            Max        = $TotalMax
            Normalized = $TotalNorm
        }

        $LogParams = @{
            Level    = 'Info'
            Category = 'Grading'
            Message  = "Grade summary computed for '$StudentName': $($CategoryScores.Count) categor$(if ($CategoryScores.Count -eq 1) {'y'} else {'ies'})."
            Student  = $StudentEmail
        }
        Write-Log @LogParams

        [PSCustomObject]@{
            PSTypeName     = 'Sage.StudentGradeSummary'
            StudentEmail   = $StudentEmail
            StudentName    = $StudentName
            StudentData    = $StudentData
            ExamName       = $ExamName
            GradedAt       = [datetime]::Now
            CategoryScores = $CategoryScores.ToArray()
            TotalScore     = $TotalScore
            OverrideCount  = $OverrideCount
            TestResults    = $AllResults.ToArray()
        }
    }
}
