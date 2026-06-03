#Requires -Version 7.5
<#
.SYNOPSIS
    Interactively reviews failed tests and applies manual grade overrides.
.DESCRIPTION
    Reads a results.json file produced by Export-GradeSummary.  Presents each
    failed test with its details (Category, Context, TestName, Expected, Actual,
    Error, ReviewData) and prompts the teacher for an optional override grade,
    reason, and reviewer note.

    After all reviews the overridden TestResults are written back to the JSON
    file with updated FinalGrade, ManualOverrideGrade, ManualOverrideReason,
    and ReviewerNote. CategoryScores and TotalScore are recalculated from the
    updated FinalGrade values. The updated Sage.StudentGradeSummary-shaped
    object is returned.

    Non-interactive mode:
        Passing -Overrides @{
            'TestName' = @{
                Grade  = X
                Reason = '...'
                Note   = '...'  # Optional ReviewerNote
            }
        }
    suppresses all prompts. Only listed test names are overridden; all others
    are left unchanged. This mode is ideal for scripted or test-driven use.
    When Note is supplied, it will be applied regardless of whether a grade
    override is applied.

    Supports -WhatIf: reads and displays results but does not write back to disk.
.PARAMETER ResultsPath
    Absolute or relative path to a results.json file.
.PARAMETER Overrides
    Optional hashtable for non-interactive mode.
    Keys   : TestName strings (exact match).
    Values : @{
        Grade  = [double]
        Reason = [string]
        Note   = [string]  # Optional ReviewerNote
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
                Note   = 'Common off-by-one in subnet'
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
            $Note = Read-Host 'Note (optional)'
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
            $Note = if ($Entry.ContainsKey('Note')) { $Entry.Note } else { $null }

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

        # Apply ReviewerNote if provided (can be applied to any test, regardless of override)
        if ($null -ne $Note) {
            $Test.ReviewerNote = $Note
        }

        $AppliedCount++

        if ($Interactive) {
            Write-Host "Applied: $($Test.TestName) → $NewGrade  ($Reason)" -ForegroundColor Green
        }
    }

    # ── Recalculate category scores and total using helper ──────────────────────────
    $RecalcParams = @{
        TestResults = $Data.TestResults
    }
    $Recalc = Invoke-GradeRecalculation @RecalcParams

    # ── Mutate the parsed document and write back ──────────────────────────────────
    $Data.CategoryScores = $Recalc.CategoryScores
    $Data.TotalScore      = $Recalc.TotalScore
    $Data.OverrideCount   = $Recalc.OverrideCount

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
        foreach ($Cs in $Recalc.CategoryScores) {
            Write-Host "  $($Cs.Category.PadRight(30)) $($Cs.RawScore)/$($Cs.MaxScore)  → $($Cs.NormalizedScore)/20"
        }
        Write-Host "  $('TOTAL'.PadRight(30)) $($Recalc.TotalScore.Raw)/$($Recalc.TotalScore.Max)  → $($Recalc.TotalScore.Normalized)/20" -ForegroundColor Yellow
        Write-Host "Updated: $ResolvedPath" -ForegroundColor DarkGreen
        Write-Host ''
    }

    return $Data
}
