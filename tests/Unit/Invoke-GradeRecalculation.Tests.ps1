#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Tests for Invoke-GradeRecalculation (Private).
.DESCRIPTION
    Tests the pure recalculation helper: single category, multi-category,
    override counting, zero-max scenarios, and normalization accuracy.
.TAGS Unit
#>

BeforeAll {
    $PrivateDir = Join-Path $PSScriptRoot '..\..\Sage\Private'
    . (Join-Path $PrivateDir 'ConvertTo-NormalizedGrade.ps1')
    . (Join-Path $PrivateDir 'Invoke-GradeRecalculation.ps1')

    function New-TestResult {
        param(
            [string]     $Category,
            [string]     $TestName,
            [double]     $PassGrade,
            [double]     $FinalGrade,
            [AllowNull()]
            [object]     $ManualOverrideGrade = $null,
            [bool]       $Passed = $false
        )

        [PSCustomObject]@{
            PSTypeName           = 'Sage.TestResult'
            StudentEmail         = 'test@example.com'
            StudentName          = 'Test Student'
            TargetName           = 'Target1'
            Category             = $Category
            TestName             = $TestName
            Context              = 'TestContext'
            Passed               = $Passed
            PassGrade            = $PassGrade
            FinalGrade           = $FinalGrade
            ManualOverrideGrade  = $ManualOverrideGrade
            ManualOverrideReason = $null
        }
    }
}

Describe 'Invoke-GradeRecalculation' -Tag 'Unit' {

    # ── Single category with one passing test ─────────────────────────────────────
    Context 'Single category, one passing test' {
        BeforeAll {
            $Tests = @(
                New-TestResult -Category 'DNS' -TestName 'Test1' -PassGrade 3.0 -FinalGrade 3.0 -Passed $true
            )
            $script:Result = Invoke-GradeRecalculation -TestResults $Tests
        }

        It 'Returns PSCustomObject with CategoryScores, TotalScore, OverrideCount' {
            $script:Result | Should -Not -BeNullOrEmpty
            $script:Result.PSObject.Properties.Name | Should -Contain 'CategoryScores'
            $script:Result.PSObject.Properties.Name | Should -Contain 'TotalScore'
            $script:Result.PSObject.Properties.Name | Should -Contain 'OverrideCount'
        }

        It 'CategoryScores contains one entry for DNS' {
            $script:Result.CategoryScores.Count | Should -Be 1
            $script:Result.CategoryScores[0].Category | Should -Be 'DNS'
        }

        It 'CategoryScores[0].RawScore is 3.0' {
            $script:Result.CategoryScores[0].RawScore | Should -Be 3.0
        }

        It 'CategoryScores[0].MaxScore is 3.0' {
            $script:Result.CategoryScores[0].MaxScore | Should -Be 3.0
        }

        It 'CategoryScores[0].NormalizedScore is 20.0 (3/3*20)' {
            $script:Result.CategoryScores[0].NormalizedScore | Should -Be 20.0
        }

        It 'TotalScore.Raw is 3.0' {
            $script:Result.TotalScore.Raw | Should -Be 3.0
        }

        It 'TotalScore.Max is 3.0' {
            $script:Result.TotalScore.Max | Should -Be 3.0
        }

        It 'TotalScore.Normalized is 20.0' {
            $script:Result.TotalScore.Normalized | Should -Be 20.0
        }

        It 'OverrideCount is 0' {
            $script:Result.OverrideCount | Should -Be 0
        }
    }

    # ── Debug test to inspect ManualOverrideGrade ─────────────────────────────────
    Context 'Debug: ManualOverrideGrade inspection' {
        BeforeAll {
            $Tests = @(
                New-TestResult -Category 'DNS' -TestName 'Test1' -PassGrade 3.0 -FinalGrade 3.0 -Passed $true
            )
            # Explicitly verify the property exists and value
            $T = $Tests[0]
        }

        It 'Test object has ManualOverrideGrade property' {
            $T.PSObject.Properties.Name | Should -Contain 'ManualOverrideGrade'
        }

        It 'ManualOverrideGrade value is $null' {
            [object]::Equals($T.ManualOverrideGrade, $null) | Should -Be $true
        }

        It 'Where-Object filtering by null works' {
            $Filtered = @($Tests | Where-Object { [object]::Equals($_.ManualOverrideGrade, $null) })
            $Filtered.Count | Should -Be 1
        }

        It 'Where-Object filtering by not-null works' {
            $Filtered = @($Tests | Where-Object { -not [object]::Equals($_.ManualOverrideGrade, $null) })
            $Filtered.Count | Should -Be 0
        }
    }

    # ── Multi-category with mixed results ─────────────────────────────────────────
    Context 'Multi-category: DNS (3+2) + AD (0+4)' {
        BeforeAll {
            $Tests = @(
                New-TestResult -Category 'DNS' -TestName 'A record' -PassGrade 3.0 -FinalGrade 3.0 -Passed $true
                New-TestResult -Category 'DNS' -TestName 'PTR record' -PassGrade 2.0 -FinalGrade 0.0 -Passed $false
                New-TestResult -Category 'AD' -TestName 'Domain' -PassGrade 4.0 -FinalGrade 0.0 -Passed $false
            )
            $script:R = Invoke-GradeRecalculation -TestResults $Tests
        }

        It 'CategoryScores has two entries' {
            $script:R.CategoryScores.Count | Should -Be 2
        }

        It 'DNS raw is 3, max is 5, normalized is 12.0 (3/5*20)' {
            $Dns = @($script:R.CategoryScores | Where-Object { $_.Category -eq 'DNS' })[0]
            $Dns.RawScore | Should -Be 3.0
            $Dns.MaxScore | Should -Be 5.0
            $Dns.NormalizedScore | Should -Be 12.0
        }

        It 'AD raw is 0, max is 4, normalized is 0.0 (0/4*20)' {
            $Ad = @($script:R.CategoryScores | Where-Object { $_.Category -eq 'AD' })[0]
            $Ad.RawScore | Should -Be 0.0
            $Ad.MaxScore | Should -Be 4.0
            $Ad.NormalizedScore | Should -Be 0.0
        }

        It 'TotalScore.Raw is 3.0' {
            $script:R.TotalScore.Raw | Should -Be 3.0
        }

        It 'TotalScore.Max is 9.0' {
            $script:R.TotalScore.Max | Should -Be 9.0
        }

        It 'TotalScore.Normalized is 6.67 (3/9*20)' {
            $script:R.TotalScore.Normalized | Should -Be 6.67
        }
    }

    # ── Override counting ─────────────────────────────────────────────────────────
    Context 'Override counting' {
        BeforeAll {
            $Tests = @(
                New-TestResult -Category 'DNS' -TestName 'T1' -PassGrade 2.0 -FinalGrade 2.0 -ManualOverrideGrade $null
                New-TestResult -Category 'DNS' -TestName 'T2' -PassGrade 2.0 -FinalGrade 1.5 -ManualOverrideGrade 1.5
                New-TestResult -Category 'DNS' -TestName 'T3' -PassGrade 1.0 -FinalGrade 0.5 -ManualOverrideGrade 0.5
            )
            $script:R = Invoke-GradeRecalculation -TestResults $Tests
        }

        It 'OverrideCount is 2 (T2 and T3 have ManualOverrideGrade set)' {
            $script:R.OverrideCount | Should -Be 2
        }
    }

    # ── Zero-max category (no tests available) ────────────────────────────────────
    Context 'Zero-max category protection' {
        BeforeAll {
            $Tests = @(
                New-TestResult -Category 'DNS' -TestName 'T1' -PassGrade 0.0 -FinalGrade 0.0
            )
            $script:R = Invoke-GradeRecalculation -TestResults $Tests
        }

        It 'Normalized score is 0.0 when MaxScore is 0 (no division by zero)' {
            $script:R.CategoryScores[0].NormalizedScore | Should -Be 0.0
        }

        It 'TotalScore.Normalized is 0.0 when TotalMax is 0' {
            $script:R.TotalScore.Normalized | Should -Be 0.0
        }
    }

    # ── CategoryScores has all required fields ────────────────────────────────────
    Context 'CategoryScores object structure' {
        BeforeAll {
            $Tests = @(
                New-TestResult -Category 'DNS' -TestName 'Pass' -PassGrade 2.0 -FinalGrade 2.0 -Passed $true
                New-TestResult -Category 'DNS' -TestName 'Fail' -PassGrade 3.0 -FinalGrade 0.0 -Passed $false
            )
            $script:R = Invoke-GradeRecalculation -TestResults $Tests
            $script:CatScore = $script:R.CategoryScores[0]
        }

        It 'Has Category property' {
            $script:CatScore.PSObject.Properties.Name | Should -Contain 'Category'
        }

        It 'Has RawScore property' {
            $script:CatScore.PSObject.Properties.Name | Should -Contain 'RawScore'
        }

        It 'Has MaxScore property' {
            $script:CatScore.PSObject.Properties.Name | Should -Contain 'MaxScore'
        }

        It 'Has NormalizedScore property' {
            $script:CatScore.PSObject.Properties.Name | Should -Contain 'NormalizedScore'
        }

        It 'Has TestCount property' {
            $script:CatScore.PSObject.Properties.Name | Should -Contain 'TestCount'
        }

        It 'Has PassedCount property' {
            $script:CatScore.PSObject.Properties.Name | Should -Contain 'PassedCount'
        }

        It 'Has FailedCount property' {
            $script:CatScore.PSObject.Properties.Name | Should -Contain 'FailedCount'
        }

        It 'TestCount is 2' {
            $script:CatScore.TestCount | Should -Be 2
        }

        It 'PassedCount is 1' {
            $script:CatScore.PassedCount | Should -Be 1
        }

        It 'FailedCount is 1' {
            $script:CatScore.FailedCount | Should -Be 1
        }
    }

    # ── Empty array input ─────────────────────────────────────────────────────────
    Context 'Empty TestResults array' {
        BeforeAll {
            $Tests = @()
            $script:R = Invoke-GradeRecalculation -TestResults $Tests
        }

        It 'CategoryScores is empty' {
            $script:R.CategoryScores.Count | Should -Be 0
        }

        It 'TotalScore.Raw is 0' {
            $script:R.TotalScore.Raw | Should -Be 0
        }

        It 'TotalScore.Max is 0' {
            $script:R.TotalScore.Max | Should -Be 0
        }

        It 'TotalScore.Normalized is 0' {
            $script:R.TotalScore.Normalized | Should -Be 0
        }

        It 'OverrideCount is 0' {
            $script:R.OverrideCount | Should -Be 0
        }
    }

}

