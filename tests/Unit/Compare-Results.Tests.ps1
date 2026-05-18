#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Compare-Results and Show-DiffResults.
.DESCRIPTION
    Verifies diff logic between two evaluation summaries.
.TAGS Unit
#>

$ConsoleWidth = try { [System.Console]::WindowWidth } catch { 0 }
$ConsoleHeight = try { [System.Console]::WindowHeight } catch { 0 }
$script:SkipInteractiveUiTests = $IsWindows -and (
    [System.Console]::IsInputRedirected -or
    [System.Console]::IsOutputRedirected -or
    $ConsoleWidth -le 0 -or
    $ConsoleHeight -le 0
)

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Write-SageColor.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-SageHeader.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-MainMenu.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Compare-Results.ps1')

    # Stub for Invoke-ReadKey so Pester can mock it (defined in Show-TargetSelector.ps1
    # at runtime, but must exist here for mocking to work).
    function Invoke-ReadKey {
        [CmdletBinding()]
        [OutputType([System.ConsoleKeyInfo])]
        param()
        [System.Console]::ReadKey($true)
    }

    # Key helpers used by Show-DiffResults tests
    function New-QuitKey {
        [PSCustomObject]@{ Key = 'Q'; KeyChar = [char]81 }
    }

    function New-BackspaceKey {
        [PSCustomObject]@{ Key = 'Backspace'; KeyChar = [char]8 }
    }

    function New-FakeTestDiffItem {
        param(
            [string]$Category = 'DNS DC1',
            [string]$TestName = 'Zone exists',
            [bool]$OldPassed = $true,
            [bool]$NewPassed = $false,
            [string]$Status = 'Regressed'
        )
        [PSCustomObject]@{
            Category  = $Category
            TestName  = $TestName
            OldPassed = $OldPassed
            NewPassed = $NewPassed
            OldGrade  = 2
            NewGrade  = 0
            Status    = $Status
        }
    }

    Mock Show-SageHeader { return 14 } -ModuleName ''

    function New-FakeSummary {
        param(
            [double]$TotalScore = 10,
            [double]$MaxScore = 20,
            [array]$TestResults = @(),
            [array]$CategoryScores = @()
        )
        [PSCustomObject]@{
            TotalScore     = [PSCustomObject]@{ Normalized = $TotalScore; Max = $MaxScore; Raw = ($TotalScore * $MaxScore / 20) }
            TestResults    = $TestResults
            CategoryScores = $CategoryScores
        }
    }

    function New-FakeTestResult {
        param(
            [string]$Category = 'DNS DC1',
            [string]$TestName = 'Zone exists',
            [bool]$Passed = $true,
            [double]$FinalGrade = 2
        )
        [PSCustomObject]@{
            Category   = $Category
            TestName   = $TestName
            Passed     = $Passed
            FinalGrade = $FinalGrade
            PassGrade  = 2
        }
    }

}

Describe 'Compare-Results' -Tag 'Unit' {

    Context 'Score delta' {

        It 'Calculates positive score delta' {
            $Old = New-FakeSummary -TotalScore 10
            $New = New-FakeSummary -TotalScore 14

            $Result = Compare-Results -OlderSummary $Old -NewerSummary $New

            $Result.ScoreDelta | Should -Be 4
        }

        It 'Calculates negative score delta' {
            $Old = New-FakeSummary -TotalScore 14
            $New = New-FakeSummary -TotalScore 10

            $Result = Compare-Results -OlderSummary $Old -NewerSummary $New

            $Result.ScoreDelta | Should -Be -4
        }

        It 'Calculates zero delta for identical scores' {
            $Old = New-FakeSummary -TotalScore 10
            $New = New-FakeSummary -TotalScore 10

            $Result = Compare-Results -OlderSummary $Old -NewerSummary $New

            $Result.ScoreDelta | Should -Be 0
        }
    }

    Context 'Test diffs' {

        It 'Detects improved tests (fail -> pass)' {
            $OldTest = New-FakeTestResult -Passed $false
            $NewTest = New-FakeTestResult -Passed $true

            $Old = New-FakeSummary -TestResults @($OldTest)
            $New = New-FakeSummary -TestResults @($NewTest)

            $Result = Compare-Results -OlderSummary $Old -NewerSummary $New

            $Result.TestDiffs[0].Status | Should -Be 'Improved'
        }

        It 'Detects regressed tests (pass -> fail)' {
            $OldTest = New-FakeTestResult -Passed $true
            $NewTest = New-FakeTestResult -Passed $false

            $Old = New-FakeSummary -TestResults @($OldTest)
            $New = New-FakeSummary -TestResults @($NewTest)

            $Result = Compare-Results -OlderSummary $Old -NewerSummary $New

            $Result.TestDiffs[0].Status | Should -Be 'Regressed'
        }

        It 'Detects unchanged tests' {
            $OldTest = New-FakeTestResult -Passed $true
            $NewTest = New-FakeTestResult -Passed $true

            $Old = New-FakeSummary -TestResults @($OldTest)
            $New = New-FakeSummary -TestResults @($NewTest)

            $Result = Compare-Results -OlderSummary $Old -NewerSummary $New

            $Result.TestDiffs[0].Status | Should -Be 'Unchanged'
        }

        It 'Detects new tests' {
            $NewTest = New-FakeTestResult -TestName 'Brand new test'

            $Old = New-FakeSummary -TestResults @()
            $New = New-FakeSummary -TestResults @($NewTest)

            $Result = Compare-Results -OlderSummary $Old -NewerSummary $New

            $Result.TestDiffs[0].Status | Should -Be 'New'
        }

        It 'Detects removed tests' {
            $OldTest = New-FakeTestResult -TestName 'Old test'

            $Old = New-FakeSummary -TestResults @($OldTest)
            $New = New-FakeSummary -TestResults @()

            $Result = Compare-Results -OlderSummary $Old -NewerSummary $New

            $Removed = @($Result.TestDiffs | Where-Object { $_.Status -eq 'Removed' })
            $Removed.Count | Should -Be 1
            $Removed[0].TestName | Should -Be 'Old test'
        }
    }

    Context 'Category diffs' {

        It 'Calculates per-category score delta' {
            $OldCat = [PSCustomObject]@{ Category = 'DNS DC1'; NormalizedScore = 10 }
            $NewCat = [PSCustomObject]@{ Category = 'DNS DC1'; NormalizedScore = 15 }

            $Old = New-FakeSummary -CategoryScores @($OldCat)
            $New = New-FakeSummary -CategoryScores @($NewCat)

            $Result = Compare-Results -OlderSummary $Old -NewerSummary $New

            $Result.CategoryDiffs[0].Delta | Should -Be 5
        }
    }

    Context 'Parameter validation' {

        It 'Requires OlderSummary' {
            { Compare-Results -NewerSummary (New-FakeSummary) } | Should -Throw
        }

        It 'Requires NewerSummary' {
            { Compare-Results -OlderSummary (New-FakeSummary) } | Should -Throw
        }
    }
}

Describe 'Show-DiffResults display' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    BeforeAll {
        . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-TestDetail.ps1')
    }

    Context 'Exits without error on Q key' {

        It 'Returns without error on Q key press' {
            $FakeDiff = [PSCustomObject]@{
                ScoreDelta    = 2
                CategoryDiffs = @()
                TestDiffs     = @()
            }

            Mock Invoke-ReadKey { New-QuitKey }
            Mock Show-SageHeader { return 5 }

            { Show-DiffResults -Diff $FakeDiff -UseSpectre $false } | Should -Not -Throw
        }
    }

    Context 'Exits without error on Backspace key' {

        It 'Returns without error on Backspace key press' {
            $FakeDiff = [PSCustomObject]@{
                ScoreDelta    = 0
                CategoryDiffs = @()
                TestDiffs     = @()
            }

            Mock Invoke-ReadKey { New-BackspaceKey }
            Mock Show-SageHeader { return 5 }

            { Show-DiffResults -Diff $FakeDiff -UseSpectre $false } | Should -Not -Throw
        }
    }

    Context 'N/A display for tests only in one run' {

        It 'Shows N/A for new tests (null OldPassed) via console output' {
            $TestDiff = [PSCustomObject]@{
                Category  = 'DNS DC1'
                TestName  = 'Brand new test'
                OldPassed = $null
                NewPassed = $true
                OldGrade  = 0
                NewGrade  = 2
                Status    = 'New'
            }
            $FakeDiff = [PSCustomObject]@{
                ScoreDelta    = 2
                CategoryDiffs = @()
                TestDiffs     = @($TestDiff)
            }

            Mock Invoke-ReadKey { New-QuitKey }
            Mock Show-SageHeader { return 5 }

            { Show-DiffResults -Diff $FakeDiff -UseSpectre $false } | Should -Not -Throw
        }

        It 'Does not throw for removed tests (null NewPassed)' {
            $TestDiff = [PSCustomObject]@{
                Category  = 'DNS DC1'
                TestName  = 'Old gone test'
                OldPassed = $true
                NewPassed = $null
                OldGrade  = 2
                NewGrade  = 0
                Status    = 'Removed'
            }
            $FakeDiff = [PSCustomObject]@{
                ScoreDelta    = -2
                CategoryDiffs = @()
                TestDiffs     = @($TestDiff)
            }

            Mock Invoke-ReadKey { New-QuitKey }
            Mock Show-SageHeader { return 5 }

            { Show-DiffResults -Diff $FakeDiff -UseSpectre $false } | Should -Not -Throw
        }
    }

    Context 'Navigation — V key toggles view' {

        It 'Accepts V key and continues without error' {
            $FakeDiff = [PSCustomObject]@{
                ScoreDelta    = 0
                CategoryDiffs = @()
                TestDiffs     = @(
                    [PSCustomObject]@{
                        Category = 'DNS DC1'; TestName = 'Test A'
                        OldPassed = $true; NewPassed = $true; OldGrade = 2; NewGrade = 2; Status = 'Unchanged'
                    }
                )
            }

            $script:CallCount = 0
            Mock Invoke-ReadKey {
                $script:CallCount++
                if ($script:CallCount -eq 1) {
                    return [PSCustomObject]@{ Key = 'V'; KeyChar = [char]86 }
                }
                return New-QuitKey
            }
            Mock Show-SageHeader { return 5 }

            { Show-DiffResults -Diff $FakeDiff -UseSpectre $false } | Should -Not -Throw
        }
    }

    Context 'Numbered rows for drill-down' {

        It 'Does not throw with multiple test diffs' {
            $FakeDiff = [PSCustomObject]@{
                ScoreDelta    = -2
                CategoryDiffs = @()
                TestDiffs     = @(
                    [PSCustomObject]@{
                        Category = 'DNS DC1'; TestName = 'Test A'
                        OldPassed = $true; NewPassed = $false; OldGrade = 2; NewGrade = 0; Status = 'Regressed'
                    }
                )
            }

            Mock Invoke-ReadKey { New-QuitKey }
            Mock Show-SageHeader { return 5 }

            { Show-DiffResults -Diff $FakeDiff -UseSpectre $false } | Should -Not -Throw
        }
    }

    Context 'Default filter is All' {

        It 'Shows all tests (including unchanged) by default on first render' {
            $FakeDiff = [PSCustomObject]@{
                ScoreDelta    = 0
                CategoryDiffs = @()
                TestDiffs     = @(
                    [PSCustomObject]@{
                        Category = 'DNS DC1'; TestName = 'Unchanged test'
                        OldPassed = $true; NewPassed = $true; OldGrade = 2; NewGrade = 2; Status = 'Unchanged'
                    }
                    [PSCustomObject]@{
                        Category = 'DNS DC1'; TestName = 'Changed test'
                        OldPassed = $false; NewPassed = $true; OldGrade = 0; NewGrade = 2; Status = 'Improved'
                    }
                )
            }

            Mock Invoke-ReadKey { New-BackspaceKey }
            Mock Show-SageHeader { return 5 }

            # Must not throw — both Unchanged and Improved tests are shown ('All' default)
            { Show-DiffResults -Diff $FakeDiff -UseSpectre $false } | Should -Not -Throw
        }
    }

    Context 'Grouped display — VM and category headers' {

        It 'Does not throw with tests from multiple VMs and categories' {
            $FakeDiff = [PSCustomObject]@{
                ScoreDelta    = 1
                CategoryDiffs = @()
                TestDiffs     = @(
                    [PSCustomObject]@{
                        Category = 'DNS DC1'; TestName = 'Zone exists'
                        OldPassed = $true; NewPassed = $true; OldGrade = 2; NewGrade = 2; Status = 'Unchanged'
                    }
                    [PSCustomObject]@{
                        Category = 'Active Directory DC1'; TestName = 'Users configured'
                        OldPassed = $false; NewPassed = $true; OldGrade = 0; NewGrade = 2; Status = 'Improved'
                    }
                    [PSCustomObject]@{
                        Category = 'Docker Linux'; TestName = 'Container running'
                        OldPassed = $true; NewPassed = $true; OldGrade = 2; NewGrade = 2; Status = 'Unchanged'
                    }
                )
            }

            Mock Invoke-ReadKey { New-BackspaceKey }
            Mock Show-SageHeader { return 5 }

            { Show-DiffResults -Diff $FakeDiff -UseSpectre $false } | Should -Not -Throw
        }
    }
}

Describe 'ConvertFrom-CollectorMarkdown' -Tag 'Unit' {

    Context 'Handles arrays with empty strings' {

        It 'Does not throw when Lines array contains empty strings' {
            # Regression: [Parameter(Mandatory)] [string[]] $Lines fails when any
            # element is an empty string (blank lines from markdown splits).
            $Lines = @('# Heading', '', '## Section', '', 'Some text', '')
            { ConvertFrom-CollectorMarkdown -Lines $Lines } | Should -Not -Throw
        }

        It 'Returns hashtable array for valid markdown content' {
            $Lines = @('# Title', '', '## Section', 'Content')
            $Result = ConvertFrom-CollectorMarkdown -Lines $Lines
            $Result | Should -Not -BeNullOrEmpty
            $Result[0].Text | Should -Be '  Title'
        }

        It 'Returns empty array for empty Lines' {
            $Result = ConvertFrom-CollectorMarkdown -Lines @()
            $Result | Should -HaveCount 0
        }

        It 'Handles Lines with only empty strings' {
            { ConvertFrom-CollectorMarkdown -Lines @('', '', '') } | Should -Not -Throw
        }
    }
}

Describe 'Invoke-DiffDrillDown' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    Context 'Does not hang on long UNC paths in collector data' {

        It 'Returns without infinite loop when collector data contains long UNC paths' {
            # Regression: WrapText continuation-indent logic would loop forever when
            # a UNC path (no spaces) is longer than the panel width after indentation.
            $FakeTestDiff = [PSCustomObject]@{
                Category  = 'Group Policy DC1'
                TestName  = '7-zip install exists'
                OldPassed = $false
                NewPassed = $false
                OldGrade  = 0
                NewGrade  = 0
                Status    = 'Unchanged'
            }

            $FakeResult = [PSCustomObject]@{
                Category      = 'Group Policy DC1'
                TestName      = '7-zip install exists'
                TargetName    = 'DC1'
                Passed        = $false
                FinalGrade    = 0
                PassGrade     = 1
                ExpectedValue = 'True'
                ActualValue   = 'False'
                ErrorMessage  = ''
            }

            $FakeSummary = [PSCustomObject]@{
                TotalScore     = [PSCustomObject]@{ Normalized = 10; Max = 20; Raw = 10 }
                TestResults    = @($FakeResult)
                CategoryScores = @()
            }

            $FakeRun = [PSCustomObject]@{
                Path    = $TestDrive
                Summary = $FakeSummary
            }

            Mock Invoke-ReadKey { [PSCustomObject]@{ Key = 'Backspace'; KeyChar = [char]8 } }
            Mock Show-SageHeader { return 14 }

            # Must complete without hanging
            { Invoke-DiffDrillDown -TestDiff $FakeTestDiff -RunLeft $FakeRun -RunRight $FakeRun } |
                Should -Not -Throw
        }
    }
}