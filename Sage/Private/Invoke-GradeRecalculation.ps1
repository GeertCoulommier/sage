#Requires -Version 7.5
<#
.SYNOPSIS
    Recalculates category scores and total grade from TestResults.
.DESCRIPTION
    Pure helper function (no I/O, no side effects) that takes an array of
    TestResults and recomputes CategoryScores (one per unique Category),
    TotalScore (aggregated raw/max/normalized), and OverrideCount (count of
    tests with ManualOverrideGrade set). Used by Edit-Grade, Invoke-LocalEvaluation,
    and review workflows to keep grades in sync after overrides are applied.

    Returns a PSCustomObject with:
      CategoryScores  — array of objects, one per category, with:
        Category, RawScore, MaxScore, NormalizedScore, TestCount, PassedCount, FailedCount
      TotalScore     — object with: Raw, Max, Normalized
      OverrideCount  — integer count of non-null ManualOverrideGrade values
.PARAMETER TestResults
    Array of Sage.TestResult objects (from results.json or in-memory).
    TestResults must already have FinalGrade set (either from automatic
    evaluation or from a prior override). The function uses FinalGrade
    to compute category and total scores.
.OUTPUTS
    [PSCustomObject] with properties: CategoryScores, TotalScore, OverrideCount
.EXAMPLE
    $Recalc = Invoke-GradeRecalculation -TestResults $Data.TestResults
    Write-Host "Total: $($Recalc.TotalScore.Normalized)/20"
#>
function Invoke-GradeRecalculation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()]                                   [object[]] $TestResults
    )

    # ── Recalculate category scores ────────────────────────────────────────────────
    $Groups = $TestResults | Group-Object -Property Category
    $NewCategoryScores = foreach ($Group in $Groups) {
        $RawScore = [double](($Group.Group |
                    Measure-Object -Property FinalGrade -Sum).Sum)
        $MaxScore = [double](($Group.Group |
                    Measure-Object -Property PassGrade -Sum).Sum)
        $Normalized = if ($MaxScore -gt 0) {
            [Math]::Round(($RawScore / $MaxScore) * 20, 2)
        }
        else { 0.0 }

        [PSCustomObject]@{
            Category        = $Group.Name
            TargetName      = $Group.Group[0].TargetName
            RawScore        = $RawScore
            MaxScore        = $MaxScore
            NormalizedScore = $Normalized
            TestCount       = $Group.Count
            PassedCount     = @($Group.Group | Where-Object { $_.Passed }).Count
            FailedCount     = @($Group.Group | Where-Object { -not $_.Passed }).Count
        }
    }

    $TotalRaw = [double](($NewCategoryScores |
                Measure-Object -Property RawScore -Sum).Sum)
    $TotalMax = [double](($NewCategoryScores |
                Measure-Object -Property MaxScore -Sum).Sum)
    $TotalNorm = if ($TotalMax -gt 0) {
        [Math]::Round(($TotalRaw / $TotalMax) * 20, 2)
    }
    else { 0.0 }

    $OverrideCount = @($TestResults |
            Where-Object { $null -ne $_.ManualOverrideGrade }).Count

    [PSCustomObject]@{
        CategoryScores = $NewCategoryScores
        TotalScore     = [PSCustomObject]@{
            Raw        = $TotalRaw
            Max        = $TotalMax
            Normalized = $TotalNorm
        }
        OverrideCount  = $OverrideCount
    }
}
