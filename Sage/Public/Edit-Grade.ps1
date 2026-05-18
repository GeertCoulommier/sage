#Requires -Version 7.5
<#
.SYNOPSIS
    Interactively reviews failed tests and applies manual grade overrides.
.DESCRIPTION
    Reads a results.json file produced by Export-GradeSummary.  Presents each
    failed test with its details (Category, Context, TestName, Expected, Actual,
    Error, ReviewData) and prompts the teacher for an optional override grade
    and reason.

    After all reviews the overridden TestResults are written back to the JSON
    file with updated FinalGrade, ManualOverrideGrade, and ManualOverrideReason.
    CategoryScores and TotalScore are recalculated from the updated FinalGrade
    values.  The updated Sage.StudentGradeSummary-shaped object is returned.

    Non-interactive mode:
        Passing -Overrides @{
            'TestName' = @{
                Grade  = X
                Reason = '...'
            }
        }
    suppresses all prompts.  Only listed test names are overridden; all others
    are left unchanged.  This mode is ideal for scripted or test-driven use.

    Supports -WhatIf: reads and displays results but does not write back to disk.
.PARAMETER ResultsPath
    Absolute or relative path to a results.json file.
.PARAMETER Overrides
    Optional hashtable for non-interactive mode.
    Keys   : TestName strings (exact match).
    Values : @{
        Grade  = [double]
        Reason = [string]
    }
    When omitted (null), the function runs interactively via Read-Host.
.OUTPUTS
    [PSCustomObject]  Updated grade summary (same structure as results.json).
.EXAMPLE
    Edit-Grade -ResultsPath './results/OSII-25-08/Banaan_Daan/results.json'
.EXAMPLE
    $overrideParams = @{
        ResultsPath = './results/OSII-25-08/Banaan_Daan/results.json'
        Overrides   = @{
            'A record dc1 should resolve to 192.168.1.3' = @{
                Grade  = 0.5
                Reason = 'Last octet typo — award partial credit'
            }
        }
    }
    Edit-Grade @overrideParams
#>
function Edit-Grade {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })]                           [string] $ResultsPath,
        [Parameter()]                                                                   [hashtable] $Overrides = $null
    )

    $ErrorActionPreference = 'Stop'
    $Interactive = $null -eq $Overrides

    # ── Read & parse results.json ──────────────────────────────────────────────────
    $ResolvedPath = (Resolve-Path $ResultsPath).Path
    $JsonContent = Get-Content -Path $ResolvedPath -Raw -Encoding UTF8
    $Data = $JsonContent | ConvertFrom-Json

    if (-not $Data.TestResults) {
        Write-Warning '[Edit-Grade] results.json contains no TestResults.'
        return $Data
    }

    $FailedTests = @($Data.TestResults | Where-Object { -not $_.Passed })

    # ── Interactive header ─────────────────────────────────────────────────────────
    if ($Interactive) {
        Write-Host ''
        Write-Host "Loading: $($Data.TestResults.Count) total tests, $($FailedTests.Count) failed." -ForegroundColor Cyan
        Write-Host 'Category scores (raw → /20):'
        foreach ($Cs in $Data.CategoryScores) {
            Write-Host "  $($Cs.Category.PadRight(30)) $($Cs.RawScore)/$($Cs.MaxScore)  → $($Cs.NormalizedScore)/20"
        }
        Write-Host "  $('TOTAL'.PadRight(30)) $($Data.TotalScore.Raw)/$($Data.TotalScore.Max)  → $($Data.TotalScore.Normalized)/20" -ForegroundColor Yellow
        Write-Host ''
    }

    $AppliedCount = 0
    $SkippedCount = 0

    # ── Review loop ────────────────────────────────────────────────────────────────
    $Index = 0
    foreach ($Test in $FailedTests) {
        $Index++

        if ($Interactive) {
            # Display test details
            Write-Host ('━' * 70) -ForegroundColor DarkGray
            Write-Host "[$Index/$($FailedTests.Count)] $($Test.Category) > $($Test.Context) > $($Test.TestName)" -ForegroundColor White
            if ($Test.ExpectedValue) {
                Write-Host "Expected : $($Test.ExpectedValue)" -ForegroundColor Green
            }
            if ($Test.ActualValue) {
                Write-Host "Actual   : $($Test.ActualValue)" -ForegroundColor Red
            }
            if ($Test.ErrorMessage) {
                Write-Host "Error    : $($Test.ErrorMessage)" -ForegroundColor DarkYellow
            }
            Write-Host "Grade    : $($Test.FinalGrade) / $($Test.PassGrade)"

            # Show ReviewData if available
            if ($Test.ReviewData) {
                Write-Host ''
                Write-Host "── Context: $($Test.ReviewContextName) ──" -ForegroundColor DarkCyan
                $Test.ReviewData | Format-Table -AutoSize | Out-String |
                    ForEach-Object { Write-Host $_ }
            }

            Write-Host ''
            $RawInput = Read-Host "Override grade (0-$($Test.PassGrade)), Enter to skip"

            if ($RawInput -match '^\s*$') {
                $SkippedCount++
                continue
            }

            if (-not ([double]::TryParse($RawInput, [ref]$null))) {
                Write-Warning "Invalid grade '$RawInput' — skipping."
                $SkippedCount++
                continue
            }

            $NewGrade = [double]$RawInput

            if ($NewGrade -lt 0 -or $NewGrade -gt $Test.PassGrade) {
                Write-Warning "Grade $NewGrade is outside the valid range 0-$($Test.PassGrade) — skipping."
                $SkippedCount++
                continue
            }

            $Reason = Read-Host 'Reason'
        }
        else {
            # Non-interactive: look up in $Overrides by TestName
            if (-not $Overrides.ContainsKey($Test.TestName)) {
                $SkippedCount++
                continue
            }

            $Entry = $Overrides[$Test.TestName]

            if (-not $Entry.ContainsKey('Grade')) {
                Write-Warning "[Edit-Grade] Override for '$($Test.TestName)' is missing 'Grade' key — skipping."
                $SkippedCount++
                continue
            }

            $NewGrade = [double]$Entry.Grade
            $Reason = if ($Entry.ContainsKey('Reason')) { $Entry.Reason } else { '' }

            if ($NewGrade -lt 0 -or $NewGrade -gt $Test.PassGrade) {
                Write-Warning "[Edit-Grade] Override grade $NewGrade for '$($Test.TestName)' is outside valid range 0-$($Test.PassGrade) — skipping."
                $SkippedCount++
                continue
            }
        }

        # ── Apply override to the matching entry in $data.TestResults ─────────────
        # Find the test by walking the full list (the $test reference from
        # $failedTests is the same object reference since ConvertFrom-Json creates
        # mutable PSCustomObjects — mutating it mutates the item in $data.TestResults).
        $Test.ManualOverrideGrade = $NewGrade
        $Test.ManualOverrideReason = $Reason
        $Test.FinalGrade = $NewGrade

        $AppliedCount++

        if ($Interactive) {
            Write-Host "Applied: $($Test.TestName) → $NewGrade  ($Reason)" -ForegroundColor Green
        }
    }

    # ── Recalculate category scores ────────────────────────────────────────────────
    $Groups = $Data.TestResults | Group-Object -Property Category
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

    $OverrideCount = @($Data.TestResults |
            Where-Object { $null -ne $_.ManualOverrideGrade }).Count

    # ── Mutate the parsed document and write back ──────────────────────────────────
    $Data.CategoryScores = $NewCategoryScores
    $Data.TotalScore = [PSCustomObject]@{
        Raw        = $TotalRaw
        Max        = $TotalMax
        Normalized = $TotalNorm
    }
    $Data.OverrideCount = $OverrideCount

    if ($PSCmdlet.ShouldProcess($ResolvedPath, 'Write updated results.json')) {
        $WriteParams = @{
            InputObject = $Data
            Depth       = 10
        }
        ConvertTo-Json @WriteParams |
            Set-Content -Path $ResolvedPath -Encoding UTF8

        $LogParams = @{
            Level    = 'Info'
            Category = 'Export'
            Message  = "Grade overrides applied ($AppliedCount changed, $SkippedCount skipped). File: $ResolvedPath"
        }
        Write-Log @LogParams
    }

    # ── Interactive summary ────────────────────────────────────────────────────────
    if ($Interactive) {
        Write-Host ''
        Write-Host ('━' * 70) -ForegroundColor DarkGray
        Write-Host "Done. $AppliedCount override(s) applied, $SkippedCount unchanged." -ForegroundColor Cyan
        Write-Host 'Updated scores (raw → /20):'
        foreach ($Cs in $NewCategoryScores) {
            Write-Host "  $($Cs.Category.PadRight(30)) $($Cs.RawScore)/$($Cs.MaxScore)  → $($Cs.NormalizedScore)/20"
        }
        Write-Host "  $('TOTAL'.PadRight(30)) $TotalRaw/$TotalMax  → $TotalNorm/20" -ForegroundColor Yellow
        Write-Host "Updated: $ResolvedPath" -ForegroundColor DarkGreen
        Write-Host ''
    }

    return $Data
}
