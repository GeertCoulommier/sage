#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Integration tests for Edit-Grade (Public).
.DESCRIPTION
    Tests: non-interactive override (-Overrides), FinalGrade updated, category
    scores recalculated, TotalScore recalculated, OverrideCount incremented,
    file written back, -WhatIf does not modify file, invalid grade rejected,
    unknown TestName skipped, and idempotency.
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
    . (Join-Path $PublicDir 'Edit-Grade.ps1')

    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sage-editgrade-' + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    # ── Build a results.json with known test data ─────────────────────────────
    # DNS: 2 tests  — passed(3) + failed(2)  → raw=3, max=5
    # AD:  1 test   — failed(4)              → raw=0, max=4
    # Total: raw=3, max=9
    function New-SampleResult {
        param([string] $SubDir = 'base')
        $Dir = Join-Path $script:TempDir $SubDir
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null

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
        $T3 = [PSCustomObject]@{
            PSTypeName           = 'Sage.TestResult'
            StudentEmail         = 'jan@ehb.be'
            StudentName          = 'Jan Appel'
            StudentData          = @{ pointer = '42' }
            TargetName           = 'WinSrv1'
            Category             = 'AD'
            TestName             = 'Domain exists'
            Context              = 'Domain'
            Passed               = $false
            PassGrade            = 4.0
            FailGrade            = 0.0
            AwardedGrade         = 0.0
            FinalGrade           = 0.0
            ManualOverrideGrade  = $null
            ManualOverrideReason = $null
            ActualValue          = $null
            ExpectedValue        = 'zinneke.be'
            ErrorMessage         = "Expected 'zinneke.be', but got '\$null'."
            ReviewContextName    = 'Domain'
            Timestamp            = [datetime]::Now
        }

        $Params = @{
            StudentEmail = 'jan@ehb.be'
            StudentName  = 'Jan Appel'
            StudentData  = @{ pointer = '42' }
            ExamName     = 'TestExam'
        }
        $Summary = Get-GradeSummary -TestResult @($T1, $T2, $T3) @Params
        Export-GradeSummary -GradeSummary $Summary -OutputPath $Dir -Format 'Json' | Out-Null

        return (Join-Path $Dir 'results.json')
    }
}

AfterAll {
    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item -Path $script:TempDir -Recurse -Force
    }
}

Describe 'Edit-Grade' -Tag 'Unit' {

    # ── Override applied correctly ────────────────────────────────────────────────
    Context 'Non-interactive single override' {
        BeforeAll {
            $Path = New-SampleResult -SubDir 'single-override'

            $Override = @{
                'PTR record exists' = @{
                    Grade  = 1.5
                    Reason = 'partial credit'
                }
            }
            $script:Result = Edit-Grade -ResultsPath $Path -Overrides $Override
        }

        It 'Returns the updated summary' {
            $script:Result | Should -Not -BeNullOrEmpty
        }

        It 'FinalGrade of overridden test is updated' {
            $Updated = @($script:Result.TestResults |
                    Where-Object { $_.TestName -eq 'PTR record exists' })
            $Updated[0].FinalGrade | Should -Be 1.5
        }

        It 'ManualOverrideGrade is set on overridden test' {
            $Updated = @($script:Result.TestResults |
                    Where-Object { $_.TestName -eq 'PTR record exists' })
            $Updated[0].ManualOverrideGrade | Should -Be 1.5
        }

        It 'ManualOverrideReason is set on overridden test' {
            $Updated = @($script:Result.TestResults |
                    Where-Object { $_.TestName -eq 'PTR record exists' })
            $Updated[0].ManualOverrideReason | Should -Be 'partial credit'
        }

        It 'DNS CategoryScore RawScore is recalculated (3+1.5=4.5)' {
            $Dns = @($script:Result.CategoryScores |
                    Where-Object { $_.Category -eq 'DNS' })
            $Dns[0].RawScore | Should -Be 4.5
        }

        It 'DNS CategoryScore NormalizedScore is recalculated (4.5/5*20=18)' {
            $Dns = @($script:Result.CategoryScores |
                    Where-Object { $_.Category -eq 'DNS' })
            $Dns[0].NormalizedScore | Should -Be 18.0
        }

        It 'TotalScore.Raw is recalculated (4.5+0=4.5)' {
            $script:Result.TotalScore.Raw | Should -Be 4.5
        }

        It 'TotalScore.Normalized is recalculated (4.5/9*20=10)' {
            $script:Result.TotalScore.Normalized | Should -Be 10.0
        }

        It 'OverrideCount is 1' {
            $script:Result.OverrideCount | Should -Be 1
        }

        It 'Updated values are written back to the JSON file' {
            $OnDisk = Get-Content (Join-Path $script:TempDir 'single-override\results.json') |
                ConvertFrom-Json
            $OnDisk.OverrideCount | Should -Be 1
            $Ptr = @($OnDisk.TestResults | Where-Object { $_.TestName -eq 'PTR record exists' })
            $Ptr[0].FinalGrade | Should -Be 1.5
        }
    }

    # ── Multiple overrides ────────────────────────────────────────────────────────
    Context 'Multiple non-interactive overrides' {
        BeforeAll {
            $Path = New-SampleResult -SubDir 'multi-override'
            $Overrides = @{
                'PTR record exists' = @{
                    Grade  = 1.0
                    Reason = 'partial'
                }
                'Domain exists'     = @{
                    Grade  = 2.0
                    Reason = 'misconfigured'
                }
            }
            $script:R2 = Edit-Grade -ResultsPath $Path -Overrides $Overrides
        }

        It 'OverrideCount is 2' {
            $script:R2.OverrideCount | Should -Be 2
        }

        It 'TotalScore.Raw is correct (3+1+2=6)' {
            $script:R2.TotalScore.Raw | Should -Be 6
        }
    }

    # ── Unknown TestName is silently skipped ──────────────────────────────────────
    Context 'Override with unknown TestName is skipped gracefully' {
        BeforeAll {
            $Path = New-SampleResult -SubDir 'unknown-test'
            $Overrides = @{
                'This test does not exist' = @{
                    Grade  = 1.0
                    Reason = 'ghost'
                }
            }
            $script:R3 = Edit-Grade -ResultsPath $Path -Overrides $Overrides
        }

        It 'OverrideCount remains 0' {
            $script:R3.OverrideCount | Should -Be 0
        }

        It 'TotalScore.Raw is unchanged' {
            $script:R3.TotalScore.Raw | Should -Be 3
        }
    }

    # ── Grade out of range is skipped ──────────────────────────────────────────────
    Context 'Override grade exceeding PassGrade is rejected' {
        BeforeAll {
            $Path = New-SampleResult -SubDir 'out-of-range'
            # PTR record exists has PassGrade=2; try to override with 10
            $Overrides = @{
                'PTR record exists' = @{
                    Grade  = 10.0
                    Reason = 'too high'
                }
            }
            $EditParams = @{
                ResultsPath   = $Path
                Overrides     = $Overrides
                WarningAction = 'SilentlyContinue'
            }
            $script:R4 = Edit-Grade @EditParams
        }

        It 'OverrideCount remains 0 when grade out of range' {
            $script:R4.OverrideCount | Should -Be 0
        }

        It 'FinalGrade unchanged when grade out of range' {
            $Ptr = @($script:R4.TestResults |
                    Where-Object { $_.TestName -eq 'PTR record exists' })
            $Ptr[0].FinalGrade | Should -Be 0
        }
    }

    # ── WhatIf does not write to disk ─────────────────────────────────────────────
    Context '-WhatIf does not write changes back' {
        BeforeAll {
            $script:WiPath = New-SampleResult -SubDir 'whatif-editgrade'
            $script:Before = Get-Content $script:WiPath -Raw

            $EditParams = @{
                ResultsPath = $script:WiPath
                Overrides   = @{
                    'PTR record exists' = @{
                        Grade  = 1.0
                        Reason = 'test'
                    }
                }
                WhatIf      = $true
            }
            Edit-Grade @EditParams

            $script:AfterContent = Get-Content $script:WiPath -Raw
        }

        It 'File content is unchanged after -WhatIf' {
            # Normalize line endings for comparison
            $script:AfterContent.Trim() | Should -Be $script:Before.Trim()
        }
    }

    # ── Empty overrides (no-op) ────────────────────────────────────────────────────
    Context 'Empty overrides hashtable — no changes applied' {
        BeforeAll {
            $Path = New-SampleResult -SubDir 'empty-overrides'
            $script:R5 = Edit-Grade -ResultsPath $Path -Overrides @{}
        }

        It 'OverrideCount is 0' {
            $script:R5.OverrideCount | Should -Be 0
        }

        It 'TotalScore.Raw unchanged' {
            $script:R5.TotalScore.Raw | Should -Be 3
        }
    }
    # ── No TestResults in JSON ─────────────────────────────────────────────────
    Context 'results.json with no TestResults' {
        BeforeAll {
            $Dir = Join-Path $script:TempDir 'no-testresults'
            New-Item -ItemType Directory -Path $Dir -Force | Out-Null
            $Path = Join-Path $Dir 'results.json'
            @{ StudentName = 'Ghost'; StudentEmail = 'ghost@ehb.be' } |
                ConvertTo-Json | Set-Content -Path $Path -Encoding UTF8
            $script:RNoTR = Edit-Grade -ResultsPath $Path -Overrides @{} -WarningAction SilentlyContinue
        }

        It 'Returns the data unchanged without error' {
            $script:RNoTR | Should -Not -BeNullOrEmpty
            $script:RNoTR.StudentName | Should -Be 'Ghost'
        }
    }

    # ── Override with missing Grade key ────────────────────────────────────────
    Context 'Override entry missing Grade key is skipped' {
        BeforeAll {
            $Path = New-SampleResult -SubDir 'missing-grade-key'
            $Overrides = @{
                'PTR record exists' = @{
                    Reason = 'no grade specified'
                }
            }
            $script:RMissingKey = Edit-Grade -ResultsPath $Path -Overrides $Overrides -WarningAction SilentlyContinue
        }

        It 'OverrideCount remains 0 when Grade key is missing' {
            $script:RMissingKey.OverrideCount | Should -Be 0
        }
    }

    # ── Negative grade is rejected ──────────────────────────────────────────────
    Context 'Negative override grade is rejected' {
        BeforeAll {
            $Path = New-SampleResult -SubDir 'negative-grade'
            $Overrides = @{
                'PTR record exists' = @{
                    Grade  = -1.0
                    Reason = 'negative'
                }
            }
            $script:RNeg = Edit-Grade -ResultsPath $Path -Overrides $Overrides -WarningAction SilentlyContinue
        }

        It 'OverrideCount remains 0 for negative grade' {
            $script:RNeg.OverrideCount | Should -Be 0
        }
    }

    # ── Override with blank Reason defaults to empty string ────────────────────
    Context 'Override entry without Reason key uses empty string' {
        BeforeAll {
            $Path = New-SampleResult -SubDir 'no-reason'
            $Overrides = @{
                'PTR record exists' = @{
                    Grade = 1.0
                }
            }
            $script:RNoReason = Edit-Grade -ResultsPath $Path -Overrides $Overrides
        }

        It 'Applies the override with an empty reason' {
            $Updated = @($script:RNoReason.TestResults |
                    Where-Object { $_.TestName -eq 'PTR record exists' })
            $Updated[0].FinalGrade | Should -Be 1.0
            $Updated[0].ManualOverrideReason | Should -Be ''
        }
    }
    # ── Idempotency ───────────────────────────────────────────────────────────────
    Context 'Applying same override twice is idempotent' {
        BeforeAll {
            $Path = New-SampleResult -SubDir 'idempotent'
            $Ov = @{
                'PTR record exists' = @{
                    Grade  = 1.0
                    Reason = 'first'
                }
            }
            $null = Edit-Grade -ResultsPath $Path -Overrides $Ov
            $script:R6 = Edit-Grade -ResultsPath $Path -Overrides $Ov
        }

        It 'OverrideCount is 1 after two identical applications' {
            $script:R6.OverrideCount | Should -Be 1
        }

        It 'FinalGrade stays at override value after re-apply' {
            $Ptr = @($script:R6.TestResults |
                    Where-Object { $_.TestName -eq 'PTR record exists' })
            $Ptr[0].FinalGrade | Should -Be 1.0
        }
    }
}
