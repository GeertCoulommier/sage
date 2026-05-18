#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Get-GradeSummary (Public).
.DESCRIPTION
    Tests: PSTypeName, CategoryScores, TotalScore, NormalizedScore, OverrideCount,
    empty/null input, pipeline input, and TestResults pass-through.
.TAGS Unit
#>

BeforeAll {
    $PrivateDir = Join-Path $PSScriptRoot '..\..\Sage\Private'
    $PublicDir = Join-Path $PSScriptRoot '..\..\Sage\Public'
    . (Join-Path $PrivateDir 'Write-Log.ps1')
    . (Join-Path $PrivateDir 'New-GradeResult.ps1')
    . (Join-Path $PrivateDir 'ConvertTo-NormalizedGrade.ps1')
    . (Join-Path $PublicDir 'Get-GradeSummary.ps1')

    # ── Helper: build a minimal Sage.TestResult ───────────────────────────────────
    function New-TestResult {
        param(
            [string] $Category = 'DNS',
            [string] $TargetName = 'WinSrv1',
            [string] $TestName = 'A record exists',
              [bool] $Passed = $true,
            [double] $PassGrade = 2.0,
            [double] $FailGrade = 0.0,
            [object] $FinalGrade = $null,   # Must be [object] so $null is NOT coerced to 0.0
            [object] $Override = $null
        )
        $Fg = if ($null -ne $FinalGrade) { $FinalGrade } elseif ($Passed) { $PassGrade } else { $FailGrade }
        [PSCustomObject]@{
            PSTypeName           = 'Sage.TestResult'
            StudentEmail         = 'test@ehb.be'
            StudentName          = 'Test Student'
            StudentData          = @{ pointer = '99' }
            TargetName           = $TargetName
            Category             = $Category
            TestName             = $TestName
            Passed               = $Passed
            PassGrade            = $PassGrade
            FailGrade            = $FailGrade
            AwardedGrade         = if ($Passed) { $PassGrade } else { $FailGrade }
            FinalGrade           = $Fg
            ManualOverrideGrade  = $Override
            ManualOverrideReason = $null
            ErrorMessage         = $null
        }
    }

    $script:CommonParams = @{
        StudentEmail = 'test@ehb.be'
        StudentName  = 'Test Student'
        StudentData  = @{ pointer = '99' }
        ExamName     = 'TestExam'
    }
}

Describe 'Get-GradeSummary' -Tag 'Unit' {

    # ── Output type ───────────────────────────────────────────────────────────────
    Context 'Output type and PSTypeName' {
        BeforeAll {
            $TestResult = New-TestResult -Passed $true -PassGrade 2
            $script:Summary = Get-GradeSummary -TestResult @($TestResult) @script:CommonParams
        }

        It 'Returns exactly one object' {
            @($script:Summary).Count | Should -Be 1
        }

        It 'Stamps PSTypeName as Sage.StudentGradeSummary' {
            $script:Summary.PSObject.TypeNames | Should -Contain 'Sage.StudentGradeSummary'
        }

        It 'Includes StudentEmail' {
            $script:Summary.StudentEmail | Should -Be 'test@ehb.be'
        }

        It 'Includes StudentName' {
            $script:Summary.StudentName | Should -Be 'Test Student'
        }

        It 'Includes ExamName' {
            $script:Summary.ExamName | Should -Be 'TestExam'
        }

        It 'GradedAt is a datetime close to now' {
            $script:Summary.GradedAt | Should -BeOfType [datetime]
            $script:Summary.GradedAt | Should -BeGreaterThan ([datetime]::Now.AddSeconds(-5))
        }
    }

    # ── Single category ───────────────────────────────────────────────────────────
    Context 'Single category — 2 passed, 1 failed' {
        BeforeAll {
            $T1 = New-TestResult -Category 'DNS' -Passed $true -PassGrade 2
            $T2 = New-TestResult -Category 'DNS' -Passed $true -PassGrade 3
            $T3 = New-TestResult -Category 'DNS' -Passed $false -PassGrade 4 -FailGrade 1
            # FinalGrade: 2 + 3 + 1 = 6   MaxScore: 2+3+4 = 9
            $script:S1 = Get-GradeSummary -TestResult @($T1, $T2, $T3) @script:CommonParams
        }

        It 'Produces one CategoryScore entry' {
            @($script:S1.CategoryScores).Count | Should -Be 1
        }

        It 'CategoryScore.RawScore is sum of FinalGrade' {
            $script:S1.CategoryScores[0].RawScore | Should -Be 6
        }

        It 'CategoryScore.MaxScore is sum of PassGrade' {
            $script:S1.CategoryScores[0].MaxScore | Should -Be 9
        }

        It 'CategoryScore.NormalizedScore is correct /20' {
            # 6/9 * 20 = 13.33
            $script:S1.CategoryScores[0].NormalizedScore | Should -Be 13.33
        }

        It 'CategoryScore.PassedCount is 2' {
            $script:S1.CategoryScores[0].PassedCount | Should -Be 2
        }

        It 'CategoryScore.FailedCount is 1' {
            $script:S1.CategoryScores[0].FailedCount | Should -Be 1
        }

        It 'TotalScore.Raw equals CategoryScore.RawScore' {
            $script:S1.TotalScore.Raw | Should -Be 6
        }

        It 'TotalScore.Max equals CategoryScore.MaxScore' {
            $script:S1.TotalScore.Max | Should -Be 9
        }

        It 'TotalScore.Normalized equals CategoryScore.NormalizedScore' {
            $script:S1.TotalScore.Normalized | Should -Be 13.33
        }
    }

    # ── Multiple categories ───────────────────────────────────────────────────────
    Context 'Multiple categories' {
        BeforeAll {
            $Dns1 = New-TestResult -Category 'DNS' -Passed $true -PassGrade 5 -TargetName 'WinSrv1'
            $Dns2 = New-TestResult -Category 'DNS' -Passed $false -PassGrade 5 -TargetName 'WinSrv1'
            $Ad1 = New-TestResult -Category 'AD' -Passed $true -PassGrade 10 -TargetName 'WinSrv1'
            # DNS: 5+0=5 raw, 10 max  |  AD: 10 raw, 10 max
            $script:S2 = Get-GradeSummary -TestResult @($Dns1, $Dns2, $Ad1) @script:CommonParams
        }

        It 'Produces two CategoryScore entries' {
            @($script:S2.CategoryScores).Count | Should -Be 2
        }

        It 'TotalScore.Raw is sum across categories (5+10=15)' {
            $script:S2.TotalScore.Raw | Should -Be 15
        }

        It 'TotalScore.Max is sum across categories (10+10=20)' {
            $script:S2.TotalScore.Max | Should -Be 20
        }

        It 'TotalScore.Normalized is correct (15/20*20=15.0)' {
            $script:S2.TotalScore.Normalized | Should -Be 15.0
        }
    }

    # ── Override counting ─────────────────────────────────────────────────────────
    Context 'Manual override counting' {
        It 'OverrideCount is 0 when no overrides' {
            $TestResult = New-TestResult -Passed $true -PassGrade 1
            $Summary = Get-GradeSummary -TestResult @($TestResult) @script:CommonParams
            $Summary.OverrideCount | Should -Be 0
        }

        It 'OverrideCount reflects ManualOverrideGrade entries' {
            $T1 = New-TestResult -Passed $false -PassGrade 2 -Override 1.0
            $T2 = New-TestResult -Passed $false -PassGrade 2 -Override 0.5
            $T3 = New-TestResult -Passed $true -PassGrade 2
            $Summary = Get-GradeSummary -TestResult @($T1, $T2, $T3) @script:CommonParams
            $Summary.OverrideCount | Should -Be 2
        }
    }

    # ── Empty / null input ────────────────────────────────────────────────────────
    Context 'Empty input' {
        BeforeAll {
            $script:EmptyS = Get-GradeSummary -TestResult @() @script:CommonParams
        }

        It 'Returns one summary object even with empty input' {
            $script:EmptyS | Should -Not -BeNullOrEmpty
        }

        It 'CategoryScores is empty array' {
            @($script:EmptyS.CategoryScores).Count | Should -Be 0
        }

        It 'TotalScore.Raw is 0' {
            $script:EmptyS.TotalScore.Raw | Should -Be 0
        }

        It 'TotalScore.Max is 0' {
            $script:EmptyS.TotalScore.Max | Should -Be 0
        }

        It 'TotalScore.Normalized is 0 when MaxScore is 0' {
            $script:EmptyS.TotalScore.Normalized | Should -Be 0
        }

        It 'TestResults is an empty array' {
            @($script:EmptyS.TestResults).Count | Should -Be 0
        }
    }

    # ── Pipeline input ────────────────────────────────────────────────────────────
    Context 'Pipeline input' {
        It 'Accepts TestResult objects via pipeline' {
            $T1 = New-TestResult -Passed $true -PassGrade 3
            $T2 = New-TestResult -Passed $false -PassGrade 3
            $Summary = $T1, $T2 | Get-GradeSummary @script:CommonParams
            $Summary | Should -Not -BeNullOrEmpty
            $Summary.TotalScore.Max | Should -Be 6
        }
    }

    # ── TestResults pass-through ──────────────────────────────────────────────────
    Context 'TestResults array preserved' {
        It 'Returns all TestResult objects in TestResults property' {
            $T1 = New-TestResult -TestName 'T1' -Passed $true -PassGrade 1
            $T2 = New-TestResult -TestName 'T2' -Passed $false -PassGrade 1
            $Summary = Get-GradeSummary -TestResult @($T1, $T2) @script:CommonParams
            @($Summary.TestResults).Count | Should -Be 2
        }
    }

    # ── FinalGrade used (not AwardedGrade) ────────────────────────────────────────
    Context 'FinalGrade reflects overrides in RawScore' {
        It 'RawScore uses FinalGrade, not AwardedGrade' {
            # Failed test with FailGrade=0, but FinalGrade overridden to 1.5
            $TestResult = [PSCustomObject]@{
                PSTypeName           = 'Sage.TestResult'
                Category             = 'DNS'
                TargetName           = 'WinSrv1'
                TestName             = 'Override test'
                Passed               = $false
                PassGrade            = 2.0
                FailGrade            = 0.0
                AwardedGrade         = 0.0
                FinalGrade           = 1.5   # override applied before Get-GradeSummary
                ManualOverrideGrade  = 1.5
                ManualOverrideReason = 'partial'
            }
            $Summary = Get-GradeSummary -TestResult @($TestResult) @script:CommonParams
            $Summary.CategoryScores[0].RawScore | Should -Be 1.5
        }
    }
}
