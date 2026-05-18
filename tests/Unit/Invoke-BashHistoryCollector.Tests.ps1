#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-BashHistoryCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with bash history and cmd.log data.
    Uses mocks to avoid dependency on Linux filesystem.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-BashHistoryCollector.ps1'
}

Describe 'Invoke-BashHistoryCollector' -Tag 'Unit' {

    Context 'Bash history file not found' {
        BeforeEach {
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*/home/*/.bash_history' }
        }

        It 'Returns Available=$true with error about missing file' {
            $Result = & $Sut -Variables @{ UserName = 'student' }
            $Result.Available | Should -BeTrue
            $Result.Errors | Should -Not -BeNullOrEmpty
            $Result.Errors[0] | Should -Match 'not found'
        }
    }

    Context 'Bash history with timestamps' {
        BeforeEach {
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*/home/*/.bash_history' }
            Mock Get-Content {
                @(
                    '#1704067200'
                    'sudo dnf update'
                    '#1704067260'
                    'sudo systemctl start nginx'
                    '#1704067320'
                    'docker build -t myapp .'
                )
            } -ParameterFilter { $Path -like '*/home/*/.bash_history' }
        }

        It 'Parses timestamped entries' {
            $Result = & $Sut -Variables @{ UserName = 'student' }
            $Result.Data.BashHistory.Count | Should -Be 3
            $Result.Data.BashHistory[0].Command | Should -Be 'sudo dnf update'
        }

        It 'Includes timestamps in output' {
            $Result = & $Sut -Variables @{ UserName = 'student' }
            $Result.Data.BashHistory[0].Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Bash history without timestamps' {
        BeforeEach {
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*/home/*/.bash_history' }
            Mock Get-Content {
                @(
                    'ls -la'
                    'cd /etc'
                    'cat hosts'
                )
            } -ParameterFilter { $Path -like '*/home/*/.bash_history' }
        }

        It 'Returns entries with null timestamps' {
            $Result = & $Sut -Variables @{ UserName = 'student' }
            $Result.Data.BashHistory.Count | Should -Be 3
            $Result.Data.BashHistory[0].Timestamp | Should -BeNullOrEmpty
            $Result.Data.BashHistory[0].Command | Should -Be 'ls -la'
        }
    }

    Context 'Time window filtering' {
        BeforeEach {
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*/home/*/.bash_history' }
            # 1704110400 = 2024-01-01T12:00:00 UTC  (safely in window for any timezone)
            # 1672531200 = 2023-01-01T00:00:00 UTC  (clearly before window)
            Mock Get-Content {
                @(
                    '#1704110400'
                    'inside window'
                    '#1672531200'
                    'outside window'
                )
            } -ParameterFilter { $Path -like '*/home/*/.bash_history' }
        }

        It 'Filters entries by exam time window' {
            $Params = @{
                UserName  = 'student'
                ExamStart = '2024-01-01T00:00:00'
                ExamEnd   = '2024-01-02T23:59:59'
            }
            $Result = & $Sut -Variables $Params
            $Result.Data.BashHistory | Where-Object { $_.Command -eq 'inside window' } |
                Should -Not -BeNullOrEmpty
            $Result.Data.BashHistory | Where-Object { $_.Command -eq 'outside window' } |
                Should -BeNullOrEmpty
        }
    }

    Context 'Result structure' {
        BeforeEach {
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*/home/*/.bash_history' }
        }

        It 'Returns all required top-level keys' {
            $Result = & $Sut -Variables @{}
            $Result.Keys | Should -Contain 'Available'
            $Result.Keys | Should -Contain 'Reason'
            $Result.Keys | Should -Contain 'Data'
            $Result.Keys | Should -Contain 'Errors'
        }

        It 'Data contains expected sub-keys' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Keys | Should -Contain 'BashHistory'
            $Result.Data.Keys | Should -Contain 'CmdLog'
        }
    }
}
