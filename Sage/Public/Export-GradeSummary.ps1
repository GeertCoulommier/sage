#Requires -Version 7.5
<#
.SYNOPSIS
    Exports a Sage.StudentGradeSummary to JSON, Excel, and/or CSV files.
.DESCRIPTION
    Writes the full student grade summary — including all TestResult rows,
    per-category scores, and the overall total — into one or more output files
    in the specified directory.

    JSON is the primary format and is always recommended.  Excel (ImportExcel
    module) and CSV are optional secondary formats.  If ImportExcel is not
    available when 'Excel' is requested, a warning is emitted and the format is
    skipped without error.

    Output files are placed directly inside -OutputPath:
      results.json   (always)
      results.xlsx   (when 'Excel' is in -Format)
      results.csv    (when 'Csv' is in -Format)

    Supports -WhatIf: no files are written when -WhatIf is active.
.PARAMETER GradeSummary
    A Sage.StudentGradeSummary object, typically produced by Get-GradeSummary.
    Accepts pipeline input.
.PARAMETER OutputPath
    Target directory for output files.  Created if it does not exist.
.PARAMETER Format
    One or more export formats to produce.  Defaults to 'Json'.
    Valid values: 'Json', 'Excel', 'Csv'.
.OUTPUTS
    [string[]]  Absolute paths of all files successfully written.
.EXAMPLE
    $summary | Export-GradeSummary -OutputPath './results/OSII-25-08/Banaan_Daan'
.EXAMPLE
    $exportParams = @{
        GradeSummary = $summary
        OutputPath   = './results/OSII-25-08/Banaan_Daan'
        Format       = 'Json', 'Excel'
    }
    Export-GradeSummary @exportParams
#>
function Export-GradeSummary {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][PSTypeName('Sage.StudentGradeSummary')]
                                                                                    [PSCustomObject] $GradeSummary,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                    [string] $OutputPath,
        [Parameter()]         [ValidateSet('Json', 'Excel', 'Csv')]                       [string[]] $Format = @('Json')
    )

    process {
        $ErrorActionPreference = 'Stop'
        $WrittenFiles = [System.Collections.Generic.List[string]]::new()
        $ResolvedPath = $OutputPath

        # ── Ensure output directory exists ─────────────────────────────────────────
        if (-not (Test-Path $ResolvedPath)) {
            if ($PSCmdlet.ShouldProcess($ResolvedPath, 'Create output directory')) {
                New-Item -Path $ResolvedPath -ItemType Directory -Force | Out-Null
            }
        }

        foreach ($Fmt in $Format) {
            switch ($Fmt) {

                # ── JSON ───────────────────────────────────────────────────────────
                'Json' {
                    $JsonPath = Join-Path $ResolvedPath 'results.json'
                    if ($PSCmdlet.ShouldProcess($JsonPath, 'Write JSON results')) {
                        # Build a plain structure — PSTypeName is not serialized by
                        # ConvertTo-Json, so we use an explicit _type field for round-trip.
                        $Document = [ordered]@{
                            _type          = 'Sage.StudentGradeSummary'
                            StudentEmail   = $GradeSummary.StudentEmail
                            StudentName    = $GradeSummary.StudentName
                            StudentData    = $GradeSummary.StudentData
                            ExamName       = $GradeSummary.ExamName
                            GradedAt       = $GradeSummary.GradedAt.ToString('o')
                            CategoryScores = @($GradeSummary.CategoryScores |
                                ForEach-Object {
                                    [ordered]@{
                                        Category        = $_.Category
                                        TargetName      = $_.TargetName
                                        RawScore        = $_.RawScore
                                        MaxScore        = $_.MaxScore
                                        NormalizedScore = $_.NormalizedScore
                                        TestCount       = $_.TestCount
                                        PassedCount     = $_.PassedCount
                                        FailedCount     = $_.FailedCount
                                    }
                                }
                            )
                            TotalScore     = [ordered]@{
                                Raw        = $GradeSummary.TotalScore.Raw
                                Max        = $GradeSummary.TotalScore.Max
                                Normalized = $GradeSummary.TotalScore.Normalized
                            }
                            OverrideCount  = $GradeSummary.OverrideCount
                            TestResults    = @($GradeSummary.TestResults |
                                ForEach-Object {
                                    [ordered]@{
                                        StudentEmail         = $_.StudentEmail
                                        StudentName          = $_.StudentName
                                        StudentData          = $_.StudentData
                                        TargetName           = $_.TargetName
                                        Category             = $_.Category
                                        TestName             = $_.TestName
                                        Context              = $_.Context
                                        Passed               = $_.Passed
                                        PassGrade            = $_.PassGrade
                                        FailGrade            = $_.FailGrade
                                        AwardedGrade         = $_.AwardedGrade
                                        ActualValue          = $_.ActualValue
                                        ExpectedValue        = $_.ExpectedValue
                                        ManualOverrideGrade  = $_.ManualOverrideGrade
                                        ManualOverrideReason = $_.ManualOverrideReason
                                        FinalGrade           = $_.FinalGrade
                                        ErrorMessage         = $_.ErrorMessage
                                        ReviewContextName    = $_.ReviewContextName
                                        Timestamp            = if ($_.Timestamp -is [datetime]) {
                                            $_.Timestamp.ToString('o')
                                        }
                                        else { $_.Timestamp }
                                    }
                                }
                            )
                        }

                        $JsonParams = @{
                            InputObject = $Document
                            Depth       = 10
                        }
                        ConvertTo-Json @JsonParams |
                            Set-Content -Path $JsonPath -Encoding UTF8

                        $WrittenFiles.Add((Resolve-Path $JsonPath).Path)
                        $LogParams = @{
                            Level    = 'Info'
                            Category = 'Export'
                            Message  = "JSON results written to: $JsonPath"
                            Student  = $GradeSummary.StudentEmail
                        }
                        Write-Log @LogParams
                    }
                }

                # ── Excel ──────────────────────────────────────────────────────────
                'Excel' {
                    if (-not (Get-Command 'Export-Excel' -ErrorAction SilentlyContinue)) {
                        Write-Warning '[Export] ImportExcel module is not available. Skipping Excel export.'
                        break
                    }

                    $XlsxPath = Join-Path $ResolvedPath 'results.xlsx'
                    if ($PSCmdlet.ShouldProcess($XlsxPath, 'Write Excel results')) {
                        # ── Sheet 1: Test details ──────────────────────────────────
                        $DetailRows = $GradeSummary.TestResults | ForEach-Object {
                            [PSCustomObject]@{
                                Category     = $_.Category
                                Target       = $_.TargetName
                                Context      = $_.Context
                                TestName     = $_.TestName
                                Passed       = $_.Passed
                                PassGrade    = $_.PassGrade
                                FinalGrade   = $_.FinalGrade
                                Override     = if ($null -ne $_.ManualOverrideGrade) {
                                    $_.ManualOverrideGrade
                                }
                                else { '' }
                                OverrideNote = $_.ManualOverrideReason
                                Expected     = $_.ExpectedValue
                                Actual       = $_.ActualValue
                                Error        = $_.ErrorMessage
                            }
                        }

                        $DetailParams = @{
                            Path          = $XlsxPath
                            WorksheetName = 'Results'
                            AutoSize      = $true
                            FreezeTopRow  = $true
                            BoldTopRow    = $true
                            AutoFilter    = $true
                            ClearSheet    = $true
                        }
                        $DetailRows | Export-Excel @DetailParams

                        # ── Sheet 2: Category summary ──────────────────────────────
                        # Wrap in @() to guarantee an array even when there is only
                        # one category — ForEach-Object returns a bare PSCustomObject
                        # for a single element, and += on a PSObject throws.
                        $SummaryRows = @($GradeSummary.CategoryScores | ForEach-Object {
                            [PSCustomObject]@{
                                Category        = $_.Category
                                Target          = $_.TargetName
                                RawScore        = $_.RawScore
                                MaxScore        = $_.MaxScore
                                NormalizedScore = $_.NormalizedScore
                                PassedCount     = $_.PassedCount
                                FailedCount     = $_.FailedCount
                            }
                        })
                        # Add total row
                        $SummaryRows += [PSCustomObject]@{
                            Category        = 'TOTAL'
                            Target          = ''
                            RawScore        = $GradeSummary.TotalScore.Raw
                            MaxScore        = $GradeSummary.TotalScore.Max
                            NormalizedScore = $GradeSummary.TotalScore.Normalized
                            PassedCount     = ($GradeSummary.CategoryScores |
                                Measure-Object PassedCount -Sum).Sum
                            FailedCount     = ($GradeSummary.CategoryScores |
                                Measure-Object FailedCount -Sum).Sum
                        }

                        $SummaryParams = @{
                            Path          = $XlsxPath
                            WorksheetName = 'Summary'
                            AutoSize      = $true
                            FreezeTopRow  = $true
                            BoldTopRow    = $true
                        }
                        $SummaryRows | Export-Excel @SummaryParams

                        $WrittenFiles.Add((Resolve-Path $XlsxPath).Path)
                        $LogParams = @{
                            Level    = 'Info'
                            Category = 'Export'
                            Message  = "Excel results written to: $XlsxPath"
                            Student  = $GradeSummary.StudentEmail
                        }
                        Write-Log @LogParams
                    }
                }

                # ── CSV ────────────────────────────────────────────────────────────
                'Csv' {
                    $CsvPath = Join-Path $ResolvedPath 'results.csv'
                    if ($PSCmdlet.ShouldProcess($CsvPath, 'Write CSV results')) {
                        $CsvRows = $GradeSummary.TestResults | ForEach-Object {
                            [PSCustomObject]@{
                                Category     = $_.Category
                                Target       = $_.TargetName
                                Context      = $_.Context
                                TestName     = $_.TestName
                                Passed       = $_.Passed
                                PassGrade    = $_.PassGrade
                                FinalGrade   = $_.FinalGrade
                                Override     = if ($null -ne $_.ManualOverrideGrade) {
                                    $_.ManualOverrideGrade
                                }
                                else { '' }
                                OverrideNote = $_.ManualOverrideReason
                            }
                        }

                        $CsvParams = @{
                            Path             = $CsvPath
                            NoTypeInformation = $true
                            Encoding          = 'UTF8'
                        }
                        $CsvRows | Export-Csv @CsvParams
                        $WrittenFiles.Add((Resolve-Path $CsvPath).Path)
                        $LogParams = @{
                            Level    = 'Info'
                            Category = 'Export'
                            Message  = "CSV results written to: $CsvPath"
                            Student  = $GradeSummary.StudentEmail
                        }
                        Write-Log @LogParams
                    }
                }
            }
        }

        $WrittenFiles.ToArray()
    }
}
