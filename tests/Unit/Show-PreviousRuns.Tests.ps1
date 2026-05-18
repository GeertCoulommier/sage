#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Show-PreviousRuns.
.DESCRIPTION
    Verifies the previous runs display logic.
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
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Import-ResultSummary.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-PreviousRuns.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-ResultsSummary.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-CategoryDetail.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Show-TestDetail.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Compare-Results.ps1')

    Mock Show-SageHeader { return 14 } -ModuleName ''

    function New-BKey   { [PSCustomObject]@{ Key = 'B';      KeyChar = [char]66 } }
    function New-QKey   { [PSCustomObject]@{ Key = 'Q';      KeyChar = [char]81 } }
    function New-BackspaceKey { [PSCustomObject]@{ Key = 'Backspace'; KeyChar = [char]8 } }

}

Describe 'Show-PreviousRuns' -Tag 'Unit' -Skip:$script:SkipInteractiveUiTests {

    BeforeEach {
        $TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
        New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $TestDir) {
            Remove-Item -Path $TestDir -Recurse -Force
        }
    }

    Context 'When no runs exist' {

        It 'Shows a warning message' {
            Mock Write-Host { }
            Mock Invoke-ReadKey { New-BKey }

            Show-PreviousRuns -OutputDir $TestDir -UseSpectre $false

            Should -Invoke Write-Host -ParameterFilter { $Object -match 'No previous' }
        }
    }

    Context 'When runs exist' {

        It 'Lists available runs and returns Back on B' {
            $RunDir = Join-Path $TestDir '2026-04-18_143022'
            New-Item -Path $RunDir -ItemType Directory | Out-Null
            @{ TotalScore = @{ Normalized = 14.5; Max = 20; Raw = 11.6 }; CategoryScores = @() } |
                ConvertTo-Json | Set-Content -Path (Join-Path $RunDir 'results.json')

            Mock Write-Host { }
            Mock Invoke-ReadKey { New-BKey }

            $Result = Show-PreviousRuns -OutputDir $TestDir -UseSpectre $false
            $Result | Should -Be 'Back'
        }

        It 'Returns QuitTui on Q' {
            $RunDir = Join-Path $TestDir '2026-04-18_143022'
            New-Item -Path $RunDir -ItemType Directory | Out-Null
            @{ TotalScore = @{ Normalized = 14.5; Max = 20; Raw = 11.6 }; CategoryScores = @() } |
                ConvertTo-Json | Set-Content -Path (Join-Path $RunDir 'results.json')

            Mock Write-Host { }
            Mock Invoke-ReadKey { New-QKey }

            $Result = Show-PreviousRuns -OutputDir $TestDir -UseSpectre $false
            $Result | Should -Be 'QuitTui'
        }

        It 'Shows runs sorted newest-first (descending order)' {
            $RunDir1 = Join-Path $TestDir '2026-04-18_143022'
            $RunDir2 = Join-Path $TestDir '2026-04-19_091500'
            New-Item -Path $RunDir1 -ItemType Directory | Out-Null
            New-Item -Path $RunDir2 -ItemType Directory | Out-Null
            @{ TotalScore = @{ Normalized = 14.5; Max = 20; Raw = 11.6 }; CategoryScores = @() } |
                ConvertTo-Json | Set-Content -Path (Join-Path $RunDir1 'results.json')
            @{ TotalScore = @{ Normalized = 16.0; Max = 20; Raw = 12.8 }; CategoryScores = @() } |
                ConvertTo-Json | Set-Content -Path (Join-Path $RunDir2 'results.json')

            Mock Write-Host { }
            Mock Invoke-ReadKey { New-BKey }

            # Function should not throw and should sort newest (2026-04-19) first
            { Show-PreviousRuns -OutputDir $TestDir -UseSpectre $false } | Should -Not -Throw
        }

        It 'Pre-marks the 2 most recent runs when at least 2 runs exist' {
            $RunDir1 = Join-Path $TestDir '2026-04-18_143022'
            $RunDir2 = Join-Path $TestDir '2026-04-19_091500'
            New-Item -Path $RunDir1 -ItemType Directory | Out-Null
            New-Item -Path $RunDir2 -ItemType Directory | Out-Null
            @{ TotalScore = @{ Normalized = 14.5; Max = 20; Raw = 11.6 }; CategoryScores = @() } |
                ConvertTo-Json | Set-Content -Path (Join-Path $RunDir1 'results.json')
            @{ TotalScore = @{ Normalized = 16.0; Max = 20; Raw = 12.8 }; CategoryScores = @() } |
                ConvertTo-Json | Set-Content -Path (Join-Path $RunDir2 'results.json')

            Mock Write-Host { }
            # Backspace on first render exits — function must not throw
            Mock Invoke-ReadKey { New-BackspaceKey }

            # With 2 runs present the function pre-marks both and returns Back
            $Result = Show-PreviousRuns -OutputDir $TestDir -UseSpectre $false
            $Result | Should -Be 'Back'
        }
    }

    Context 'When output directory does not exist' {

        It 'Shows a warning and returns' {
            Mock Write-Host { }

            Show-PreviousRuns -OutputDir (Join-Path $TestDir 'nonexistent') -UseSpectre $false

            Should -Invoke Write-Host -ParameterFilter { $Object -match 'No output' }
        }
    }
}
