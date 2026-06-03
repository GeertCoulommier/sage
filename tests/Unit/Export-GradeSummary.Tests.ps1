#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Export-GradeSummary (Public).
.DESCRIPTION
    Tests: JSON file creation/structure, -WhatIf support, CSV output,
    Excel output (ImportExcel available), missing ImportExcel warning,
    output path creation, return value (file paths).
.TAGS Unit
#>

BeforeAll {
    $PrivateDir = Join-Path $PSScriptRoot '..\..\Sage\Private'
    $PublicDir = Join-Path $PSScriptRoot '..\..\Sage\Public'
    . (Join-Path $PrivateDir 'Write-Log.ps1')
    . (Join-Path $PrivateDir 'New-GradeResult.ps1')
    . (Join-Path $PrivateDir 'ConvertTo-NormalizedGrade.ps1')
    . (Join-Path $PublicDir 'Get-GradeSummary.ps1')
    . (Join-Path $PublicDir 'Export-GradeSummary.ps1')

    # Temp directory for all test output
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sage-export-test-' + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    $script:HasExcel = $null -ne (Get-Command 'Export-Excel' -ErrorAction SilentlyContinue)

    # ── Build a representative StudentGradeSummary ─────────────────────────────
    function New-SampleSummary {
        $T1 = [PSCustomObject]@{
            PSTypeName           = 'Sage.TestResult'
            StudentEmail         = 'jan@ehb.be'
            StudentName          = 'Jan Appel'
            StudentData          = @{ pointer = '42' }
            TargetName           = 'WinSrv1'
            Category             = 'DNS'
            TestName             = 'A record exists'
            Context              = 'A Records'
            Passed               = $true
            PassGrade            = 3.0
            FailGrade            = 0.0
            AwardedGrade         = 3.0
            FinalGrade           = 3.0
            ManualOverrideGrade  = $null
            ManualOverrideReason = $null
            ActualValue          = $null
            ExpectedValue        = $null
            ErrorMessage         = $null
            ReviewContextName    = 'A Records'
            Timestamp            = [datetime]::Now
        }
        $T2 = [PSCustomObject]@{
            PSTypeName           = 'Sage.TestResult'
            StudentEmail         = 'jan@ehb.be'
            StudentName          = 'Jan Appel'
            StudentData          = @{ pointer = '42' }
            TargetName           = 'WinSrv1'
            Category             = 'DNS'
            TestName             = 'PTR record exists'
            Context              = 'PTR Records'
            Passed               = $false
            PassGrade            = 2.0
            FailGrade            = 0.0
            AwardedGrade         = 0.0
            FinalGrade           = 0.0
            ManualOverrideGrade  = $null
            ManualOverrideReason = $null
            ActualValue          = $null
            ExpectedValue        = '10.2.3.4'
            ErrorMessage         = "Expected '10.2.3.4', but got '\$null'."
            ReviewContextName    = 'PTR Records'
            Timestamp            = [datetime]::Now
        }

        $Params = @{
            StudentEmail = 'jan@ehb.be'
            StudentName  = 'Jan Appel'
            StudentData  = @{ pointer = '42' }
            ExamName     = 'TestExam'
        }
        Get-GradeSummary -TestResult @($T1, $T2) @Params
    }

    $script:Summary = New-SampleSummary
}

AfterAll {
    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item -Path $script:TempDir -Recurse -Force
    }
}

Describe 'Export-GradeSummary' -Tag 'Unit' {

    # ── JSON output ───────────────────────────────────────────────────────────────
    Context 'JSON export' {
        BeforeAll {
            $script:JsonDir = Join-Path $script:TempDir 'json-test'
            $ExportParams = @{
                GradeSummary = $script:Summary
                OutputPath   = $script:JsonDir
                Format       = 'Json'
            }
            $script:Files = Export-GradeSummary @ExportParams
            $script:JsonPath = Join-Path $script:JsonDir 'results.json'
        }

        It 'Creates the output directory if it does not exist' {
            Test-Path $script:JsonDir | Should -Be $true
        }

        It 'Creates results.json' {
            Test-Path $script:JsonPath | Should -Be $true
        }

        It 'Returns the file path as output' {
            $script:Files | Should -Not -BeNullOrEmpty
            @($script:Files) | Where-Object { $_ -like '*results.json' } |
                Should -Not -BeNullOrEmpty
        }

        It 'results.json is valid JSON' {
            { Get-Content $script:JsonPath | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'results.json contains _type field' {
            $Json = Get-Content $script:JsonPath | ConvertFrom-Json
            $Json._type | Should -Be 'Sage.StudentGradeSummary'
        }

        It 'results.json contains StudentEmail' {
            $Json = Get-Content $script:JsonPath | ConvertFrom-Json
            $Json.StudentEmail | Should -Be 'jan@ehb.be'
        }

        It 'results.json contains StudentName' {
            $Json = Get-Content $script:JsonPath | ConvertFrom-Json
            $Json.StudentName | Should -Be 'Jan Appel'
        }

        It 'results.json contains ExamName' {
            $Json = Get-Content $script:JsonPath | ConvertFrom-Json
            $Json.ExamName | Should -Be 'TestExam'
        }

        It 'results.json CategoryScores has correct count' {
            $Json = Get-Content $script:JsonPath | ConvertFrom-Json
            @($Json.CategoryScores).Count | Should -Be 1
        }

        It 'results.json CategoryScores[0] has required fields' {
            $Json = Get-Content $script:JsonPath | ConvertFrom-Json
            $Cs = $Json.CategoryScores[0]
            $Cs.Category | Should -Be 'DNS'
            $Cs.RawScore | Should -Be 3
            $Cs.MaxScore | Should -Be 5
            $Cs.NormalizedScore | Should -Be 12
        }

        It 'results.json TotalScore has required fields' {
            $Json = Get-Content $script:JsonPath | ConvertFrom-Json
            $Json.TotalScore.Raw | Should -Be 3
            $Json.TotalScore.Max | Should -Be 5
            $Json.TotalScore.Normalized | Should -Be 12
        }

        It 'results.json TestResults has correct count' {
            $Json = Get-Content $script:JsonPath | ConvertFrom-Json
            @($Json.TestResults).Count | Should -Be 2
        }

        It 'results.json TestResults contains Passed field' {
            $Json = Get-Content $script:JsonPath | ConvertFrom-Json
            $Passed = @($Json.TestResults | Where-Object { $_.Passed -eq $true })
            $Failed = @($Json.TestResults | Where-Object { $_.Passed -eq $false })
            $Passed.Count | Should -Be 1
            $Failed.Count | Should -Be 1
        }

        It 'results.json includes GradedAt as ISO 8601 string' {
            # Read the raw JSON to bypass ConvertFrom-Json date auto-conversion.
            # Export-GradeSummary writes GradedAt via DateTime.ToString('o'), so
            # we verify the literal string value in the file rather than a parsed object.
            $RawJson = Get-Content $script:JsonPath -Raw
            $RawJson | Should -Match '"GradedAt"\s*:\s*"\d{4}-\d{2}-\d{2}T'
        }
    }

    # ── WhatIf ────────────────────────────────────────────────────────────────────
    Context '-WhatIf does not write files' {
        BeforeAll {
            $script:WhatIfDir = Join-Path $script:TempDir 'whatif-test'
        }

        It 'Does not create the output directory when -WhatIf' {
            $ExportParams = @{
                GradeSummary = $script:Summary
                OutputPath   = $script:WhatIfDir
                Format       = 'Json'
                WhatIf       = $true
            }
            Export-GradeSummary @ExportParams
            Test-Path $script:WhatIfDir | Should -Be $false
        }
    }

    # ── CSV output ────────────────────────────────────────────────────────────────
    Context 'CSV export' {
        BeforeAll {
            $script:CsvDir = Join-Path $script:TempDir 'csv-test'
            $ExportParams = @{
                GradeSummary = $script:Summary
                OutputPath   = $script:CsvDir
                Format       = 'Json', 'Csv'
            }
            Export-GradeSummary @ExportParams
            $script:CsvPath = Join-Path $script:CsvDir 'results.csv'
        }

        It 'Creates results.csv' {
            Test-Path $script:CsvPath | Should -Be $true
        }

        It 'CSV has expected columns' {
            $Rows = Import-Csv $script:CsvPath
            $Rows[0].PSObject.Properties.Name | Should -Contain 'Category'
            $Rows[0].PSObject.Properties.Name | Should -Contain 'TestName'
            $Rows[0].PSObject.Properties.Name | Should -Contain 'Passed'
            $Rows[0].PSObject.Properties.Name | Should -Contain 'FinalGrade'
        }

        It 'CSV has 2 rows of test data' {
            $Rows = Import-Csv $script:CsvPath
            @($Rows).Count | Should -Be 2
        }
    }

    # ── Excel output ──────────────────────────────────────────────────────────────
    Context 'Excel export — ImportExcel available' -Skip:(-not $script:HasExcel) {
        BeforeAll {
            $script:XlsxDir = Join-Path $script:TempDir 'xlsx-test'
            $ExportParams = @{
                GradeSummary = $script:Summary
                OutputPath   = $script:XlsxDir
                Format       = 'Json', 'Excel'
            }
            Export-GradeSummary @ExportParams
            $script:XlsxPath = Join-Path $script:XlsxDir 'results.xlsx'
        }

        It 'Creates results.xlsx' {
            Test-Path $script:XlsxPath | Should -Be $true
        }

        It 'Excel file contains Results sheet' {
            $Sheets = (Open-ExcelPackage -Path $script:XlsxPath).Workbook.Worksheets.Name
            $Sheets | Should -Contain 'Results'
        }

        It 'Excel file contains Summary sheet' {
            $Sheets = (Open-ExcelPackage -Path $script:XlsxPath).Workbook.Worksheets.Name
            $Sheets | Should -Contain 'Summary'
        }
    }

    # ── Missing ImportExcel warning ────────────────────────────────────────────────
    Context 'Excel export — ImportExcel unavailable' -Skip:$script:HasExcel {
        It 'Emits a warning and does not throw when ImportExcel is missing' {
            $Dir = Join-Path $script:TempDir 'no-excel-test'
            {
                $ExportParams = @{
                    GradeSummary  = $script:Summary
                    OutputPath    = $Dir
                    Format        = 'Excel'
                    WarningAction = 'SilentlyContinue'
                }
                Export-GradeSummary @ExportParams
            } | Should -Not -Throw
        }
    }

    # ── Missing ImportExcel (always runs via mock) ─────────────────────────────────
    Context 'Excel export — ImportExcel mocked unavailable' {
        BeforeEach {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Export-Excel' }
        }

        It 'Emits a warning when ImportExcel module is not available' {
            $Dir = Join-Path $script:TempDir 'no-excel-mock'
            $ExportParams = @{
                GradeSummary    = $script:Summary
                OutputPath      = $Dir
                Format          = 'Json', 'Excel'
                WarningVariable = 'Warns'
                WarningAction   = 'SilentlyContinue'
            }
            Export-GradeSummary @ExportParams
            @($Warns) | Where-Object { $_ -match 'ImportExcel module is not available' } | Should -Not -BeNullOrEmpty
        }
    }

    # ── Multiple formats in one call ──────────────────────────────────────────────
    Context 'Multiple formats' {
        BeforeAll {
            $script:MultiDir = Join-Path $script:TempDir 'multi-test'
            $ExportParams = @{
                GradeSummary = $script:Summary
                OutputPath   = $script:MultiDir
                Format       = 'Json', 'Csv'
            }
            $script:MultiFiles = Export-GradeSummary @ExportParams
        }

        It 'Returns two file paths' {
            @($script:MultiFiles).Count | Should -Be 2
        }

        It 'One path ends with results.json' {
            ($script:MultiFiles | Where-Object { $_ -like '*results.json' }).Count |
                Should -Be 1
        }

        It 'One path ends with results.csv' {
            ($script:MultiFiles | Where-Object { $_ -like '*results.csv' }).Count |
                Should -Be 1
        }
    }
}
