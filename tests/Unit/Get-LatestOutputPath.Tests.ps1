#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Get-LatestOutputPath.
.DESCRIPTION
    Verifies the logic for finding the most recent timestamped output directory.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Get-LatestOutputPath.ps1')
}

Describe 'Get-LatestOutputPath' -Tag 'Unit' {

    BeforeEach {
        $TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
        New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $TestDir) {
            Remove-Item -Path $TestDir -Recurse -Force
        }
    }

    Context 'When output directories exist' {

        It 'Returns the latest timestamped directory' {
            New-Item -Path (Join-Path $TestDir '2026-04-17_100000') -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $TestDir '2026-04-18_143022') -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $TestDir '2026-04-18_120000') -ItemType Directory | Out-Null

            $Result = Get-LatestOutputPath -OutputDir $TestDir

            $Result | Should -BeLike '*2026-04-18_143022*'
        }

        It 'Ignores non-timestamped directories' {
            New-Item -Path (Join-Path $TestDir '2026-04-17_100000') -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $TestDir 'not-a-timestamp') -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $TestDir '.gitkeep') -ItemType File | Out-Null

            $Result = Get-LatestOutputPath -OutputDir $TestDir

            $Result | Should -BeLike '*2026-04-17_100000*'
        }
    }

    Context 'When no output directories exist' {

        It 'Returns null for empty directory' {
            $Result = Get-LatestOutputPath -OutputDir $TestDir
            $Result | Should -BeNullOrEmpty
        }

        It 'Returns null for non-existent directory' {
            $Result = Get-LatestOutputPath -OutputDir (Join-Path $TestDir 'nonexistent')
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It 'Requires OutputDir' {
            { Get-LatestOutputPath } | Should -Throw
        }
    }
}
