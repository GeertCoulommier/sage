#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for ConvertTo-GradeSummary (Private).
.DESCRIPTION
    Tests: PSTypeName, grade logic (pass/fail/skip), ActualValue/ExpectedValue parsing,
    PassGrade from test Data, ReviewContextMap invocation, context name extraction,
    empty result set, and StudentData pass-through.
.TAGS Unit
#>

BeforeAll {
    # Load private functions needed by the SUT
    $PrivateDir = Join-Path $PSScriptRoot '..\..\Sage\Private'
    . (Join-Path $PrivateDir 'New-GradeResult.ps1')
    . (Join-Path $PrivateDir 'Write-Log.ps1')
    . (Join-Path $PrivateDir 'ConvertTo-GradeSummary.ps1')

    # ── Helper: build a minimal mock Pester test hashtable ────────────────────
    # Matches the plain-hashtable structure returned by Invoke-RemotePester
    # after CLIXML-safe extraction on the remote side.
    function New-MockTest {
        param(
            [string] $Name = 'Test Name',
            [string] $Result = 'Passed',    # Passed / Failed / Skipped / NotRun
            [double] $PassGrade = 1.0,
            [string] $ErrorMsg = $null,
            [string] $ContextName = 'Test Context'
        )
        # Return a plain hashtable matching the structure produced by
        # Invoke-RemotePester on the remote side (safe for CLIXML).
        @{
            Name         = $Name
            ExpandedName = $Name
            Result       = $Result
            Data         = @{ PassGrade = $PassGrade }
            ErrorMessage = $ErrorMsg
            Context      = $ContextName
        }
    }

    function New-MockPesterResult {
        param([object[]]$Tests = @())
        [PSCustomObject]@{ Tests = $Tests }
    }

    # Shared student data
    $script:CommonParams = @{
        StudentEmail = 'test@ehb.be'
        StudentName  = 'Test Student'
        StudentData  = @{ pointer = '99' }
        TargetName   = 'WinSrv1'
        Category     = 'DNS'
    }
}

Describe 'ConvertTo-GradeSummary' -Tag 'Unit' {

    Context 'Empty result set' {
        It 'Returns empty array when no tests' {
            $Pr = New-MockPesterResult -Tests @()
            $Results = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams
            @($Results).Count | Should -Be 0
        }

        It 'Returns empty array when all tests are Skipped' {
            $Pr = New-MockPesterResult -Tests @(
                (New-MockTest -Result 'Skipped')
                (New-MockTest -Result 'Skipped')
            )
            $Results = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams
            @($Results).Count | Should -Be 0
        }

        It 'Returns empty array when all tests are NotRun' {
            $Pr = New-MockPesterResult -Tests @(
                (New-MockTest -Result 'NotRun')
            )
            $Results = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams
            @($Results).Count | Should -Be 0
        }
    }

    Context 'PSTypeName and metadata stamping' {
        BeforeAll {
            $Pr = New-MockPesterResult -Tests @(New-MockTest -Result 'Passed' -PassGrade 2)
            $script:Result = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams |
                Select-Object -First 1
        }
        It 'Stamps PSTypeName as Sage.TestResult' {
            $script:Result.PSObject.TypeNames | Should -Contain 'Sage.TestResult'
        }
        It 'Stamps StudentEmail' {
            $script:Result.StudentEmail | Should -Be 'test@ehb.be'
        }
        It 'Stamps StudentName' {
            $script:Result.StudentName | Should -Be 'Test Student'
        }
        It 'Stamps TargetName' {
            $script:Result.TargetName | Should -Be 'WinSrv1'
        }
        It 'Stamps Category' {
            $script:Result.Category | Should -Be 'DNS'
        }
        It 'Stamps TestName from Pester test' {
            $script:Result.TestName | Should -Be 'Test Name'
        }
    }

    Context 'Passed test grading' {
        BeforeAll {
            $Pr = New-MockPesterResult -Tests @(New-MockTest -Result 'Passed' -PassGrade 3)
            $script:R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams |
                Select-Object -First 1
        }
        It 'Passed is $true' { $script:R.Passed | Should -Be $true }
        It 'AwardedGrade equals PassGrade' { $script:R.AwardedGrade | Should -Be 3 }
        It 'FinalGrade equals PassGrade' { $script:R.FinalGrade | Should -Be 3 }
        It 'PassGrade stored correctly' { $script:R.PassGrade | Should -Be 3 }
        It 'ErrorMessage is null for passed test' { $script:R.ErrorMessage | Should -BeNullOrEmpty }
    }

    Context 'Failed test grading' {
        BeforeAll {
            $Pr = New-MockPesterResult -Tests @(
                New-MockTest -Result 'Failed' -PassGrade 2 -ErrorMsg "Expected '192.168.1.3', but got '192.168.1.4'."
            )
            $script:R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams |
                Select-Object -First 1
        }
        It 'Passed is $false' { $script:R.Passed | Should -Be $false }
        It 'AwardedGrade is 0 (FailGrade default)' { $script:R.AwardedGrade | Should -Be 0 }
        It 'FinalGrade is 0' { $script:R.FinalGrade | Should -Be 0 }
        It 'ErrorMessage is populated' { $script:R.ErrorMessage | Should -Not -BeNullOrEmpty }
    }

    Context 'ActualValue / ExpectedValue parsing' {
        It "Parses 'Expected X, but got Y' error message" {
            $Pr = New-MockPesterResult -Tests @(
                New-MockTest -Result 'Failed' -PassGrade 1 -ErrorMsg "Expected '192.168.1.3', but got '192.168.1.4'."
            )
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams |
                Select-Object -First 1
            $R.ExpectedValue | Should -Be '192.168.1.3'
            $R.ActualValue | Should -Be '192.168.1.4'
        }

        It 'Leaves ActualValue/ExpectedValue null for passed test' {
            $Pr = New-MockPesterResult -Tests @(New-MockTest -Result 'Passed' -PassGrade 1)
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams |
                Select-Object -First 1
            $R.ActualValue | Should -BeNullOrEmpty
            $R.ExpectedValue | Should -BeNullOrEmpty
        }

        It 'Leaves ActualValue null when error message does not match known pattern' {
            $Pr = New-MockPesterResult -Tests @(
                New-MockTest -Result 'Failed' -PassGrade 1 -ErrorMsg 'Some unexpected error'
            )
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams |
                Select-Object -First 1
            $R.ActualValue | Should -BeNullOrEmpty
        }

        It "Parses 'Expected X to ...' style error message" {
            $Pr = New-MockPesterResult -Tests @(
                New-MockTest -Result 'Failed' -PassGrade 1 -ErrorMsg 'Expected $true to be exactly $false.'
            )
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams |
                Select-Object -First 1
            $R.ExpectedValue | Should -Be '$true'
            $R.ActualValue | Should -BeNullOrEmpty
        }
    }

    Context 'Context name extraction' {
        It 'Populates Context from Context key' {
            $Pr = New-MockPesterResult -Tests @(
                New-MockTest -Result 'Passed' -ContextName 'A Records'
            )
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams |
                Select-Object -First 1
            $R.Context | Should -Be 'A Records'
        }
    }

    Context 'ReviewContextMap' {
        It 'Attaches ReviewData from ReviewContextMap for failed test' {
            $Pr = New-MockPesterResult -Tests @(
                New-MockTest -Result 'Failed' -ContextName 'Forward Zones' -ErrorMsg "Expected 'Primary', but got 'Secondary'."
            )
            $Map = @{
                'Forward Zones' = {
                    param($Data)
                    @{
                        ReviewKey = if ($Data -and $Data.ContainsKey('ReviewKey')) { $Data.ReviewKey } else { 'ReviewValue' }
                    }
                }
            }
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams -ReviewContextMap $Map -CollectedData @{ ReviewKey = 'ReviewValue' } | Select-Object -First 1
            $R.ReviewData | Should -Not -BeNullOrEmpty
            $R.ReviewData.ReviewKey | Should -Be 'ReviewValue'
        }

        It 'Does not attach ReviewData for passed test (no review needed)' {
            $Pr = New-MockPesterResult -Tests @(
                New-MockTest -Result 'Passed' -ContextName 'Forward Zones'
            )
            $Map = @{
                'Forward Zones' = {
                    param($Data)
                    @{
                        ReviewKey = if ($Data -and $Data.ContainsKey('ReviewKey')) { $Data.ReviewKey } else { 'ReviewValue' }
                    }
                }
            }
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams -ReviewContextMap $Map -CollectedData @{ ReviewKey = 'ReviewValue' } | Select-Object -First 1
            $R.ReviewData | Should -BeNullOrEmpty
        }

        It 'Handles missing ReviewContextMap entry gracefully' {
            $Pr = New-MockPesterResult -Tests @(
                New-MockTest -Result 'Failed' -ContextName 'Some Unknown Context' -ErrorMsg 'Some error'
            )
            { ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams } |
                Should -Not -Throw
        }

        It 'Logs warning when ReviewContextMap scriptblock throws' {
            Mock Write-Log {}
            $Pr = New-MockPesterResult -Tests @(
                New-MockTest -Result 'Failed' -ContextName 'Broken Context' -ErrorMsg 'Some error'
            )
            $Map = @{
                'Broken Context' = { throw 'scriptblock crashed' }
            }
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams -ReviewContextMap $Map | Select-Object -First 1
            $R.ReviewData | Should -BeNullOrEmpty
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'ReviewContextMap scriptblock failed' }
        }
    }

    Context 'TestName fallback' {
        It 'Falls back to raw Name when ExpandedName is empty' {
            $Test = @{
                Name         = 'RawTestName'
                ExpandedName = ''
                Result       = 'Passed'
                Data         = @{ PassGrade = 1 }
                ErrorMessage = $null
                Context      = 'Ctx'
            }
            $Pr = New-MockPesterResult -Tests @($Test)
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams | Select-Object -First 1
            $R.TestName | Should -Be 'RawTestName'
        }

        It 'Falls back to category index when ExpandedName and Name are both empty' {
            $Test = @{
                Name         = ''
                ExpandedName = ''
                Result       = 'Passed'
                Data         = @{ PassGrade = 1 }
                ErrorMessage = $null
                Context      = 'Ctx'
            }
            $Pr = New-MockPesterResult -Tests @($Test)
            $R = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams | Select-Object -First 1
            $R.TestName | Should -BeLike 'DNS*Test 1'
        }
    }

    Context 'Multiple tests — mixed pass/fail/skip' {
        BeforeAll {
            $Pr = New-MockPesterResult -Tests @(
                (New-MockTest -Name 'Test1' -Result 'Passed' -PassGrade 2),
                (New-MockTest -Name 'Test2' -Result 'Failed' -PassGrade 3 -ErrorMsg 'err'),
                (New-MockTest -Name 'Test3' -Result 'Skipped' -PassGrade 1),
                (New-MockTest -Name 'Test4' -Result 'Passed' -PassGrade 1)
            )
            $script:Results = ConvertTo-GradeSummary -PesterResult $Pr @script:CommonParams
        }
        It 'Only includes Passed and Failed tests (3 results — skip excluded)' {
            @($script:Results).Count | Should -Be 3
        }
        It 'Correct total AwardedGrade (2 + 0 + 1 = 3)' {
            ($script:Results | Measure-Object -Property AwardedGrade -Sum).Sum | Should -Be 3
        }
    }

    Context 'StudentData pass-through' {
        It 'Preserves all StudentData keys on each result' {
            $StudentData = @{
                pointer  = '12345'
                subgroep = 'A'
                custom   = 'extra'
            }
            $Pr = New-MockPesterResult -Tests @(New-MockTest -Result 'Passed')
            $CallParams = @{
                PesterResult = $Pr
                StudentEmail = 'x@ehb.be'
                StudentName  = 'X'
                StudentData  = $StudentData
                TargetName   = 'T'
                Category     = 'C'
            }
            $Results = ConvertTo-GradeSummary @CallParams
            $R = $Results | Select-Object -First 1
            $R.StudentData.pointer | Should -Be '12345'
            $R.StudentData.subgroep | Should -Be 'A'
            $R.StudentData.custom | Should -Be 'extra'
        }
    }
}
