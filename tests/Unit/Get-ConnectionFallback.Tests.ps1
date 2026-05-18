#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Get-ConnectionFallback.
.DESCRIPTION
    Verifies the connection fallback logic: primary success, primary failure
    with fallback, both fail, and target-not-found scenarios.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Test-SshConnection.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Save-TuiPreferencesInExam.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Get-ConnectionFallback.ps1')

    $script:FakeTuiConfigPath = '/fake/tui-config.psd1'

    function New-FakeTuiConfig {
        @{
            Targets = @{
                Linux = @{
                    PrimaryHostName = '192.168.1.2'
                    Port            = 22
                }
                DC1   = @{
                    PrimaryHostName = '192.168.1.3'
                    Port            = 22
                }
            }
            Remembered = @{
                PreferFallbackTargets = @()
            }
        }
    }

    function New-FakeExamTargets {
        @{
            Targets = @{
                Linux = @{
                    Port     = 22
                    UserName = 'student'
                    Platform = 'Linux'
                }
                DC1   = @{
                    Port     = 22
                    UserName = 'administrator'
                    Platform = 'Windows'
                }
            }
        }
    }
}

Describe 'Get-ConnectionFallback' -Tag 'Unit' {

    BeforeEach {
        $TuiConfig = New-FakeTuiConfig
        $Exam      = New-FakeExamTargets
        Mock Import-PowerShellDataFile { return $TuiConfig }
        Mock Save-FallbackInExamConfig { }
        Mock Save-PreferFallbackTargetsInExamConfig { }
    }

    Context 'When primary host is reachable' {

        It 'Returns Primary status for reachable targets' {
            Mock Test-SshConnection { return $true }

            $Result = Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $script:FakeTuiConfigPath -Exam $Exam -EnabledTargets @('Linux')

            $Result['Linux'].HostName | Should -Be '192.168.1.2'
            $Result['Linux'].Port     | Should -Be 22
            $Result['Linux'].Status   | Should -Be 'Primary'
        }

        It 'Tests each enabled target independently' {
            Mock Test-SshConnection { return $true }

            $Result = Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $script:FakeTuiConfigPath -Exam $Exam -EnabledTargets @('Linux', 'DC1')

            $Result.Keys.Count | Should -Be 2
            $Result['Linux'].Status | Should -Be 'Primary'
            $Result['DC1'].Status   | Should -Be 'Primary'
        }
    }

    Context 'When primary fails and fallback is provided' {

        It 'Uses fallback hostname when primary fails' {
            $script:SshCallCount = 0
            Mock Test-SshConnection {
                $script:SshCallCount++
                if ($script:SshCallCount -eq 1) { return $false }  # primary fails
                return $true  # fallback succeeds
            }
            Mock Read-Host {
                param($Prompt)
                if ($Prompt -match 'hostname') { return 'public.example.com' }
                return ''  # accept default port
            }

            $Result = Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $script:FakeTuiConfigPath -Exam $Exam -EnabledTargets @('Linux')

            $Result['Linux'].HostName | Should -Be 'public.example.com'
            $Result['Linux'].Status   | Should -Be 'UserInput'
        }

        It 'Allows custom fallback port' {
            $script:SshCallCount = 0
            Mock Test-SshConnection {
                $script:SshCallCount++
                if ($script:SshCallCount -eq 1) { return $false }
                return $true
            }
            Mock Read-Host {
                param($Prompt)
                if ($Prompt -match 'hostname') { return 'public.example.com' }
                if ($Prompt -match 'Port') { return '20022' }
                return ''
            }

            $Result = Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $script:FakeTuiConfigPath -Exam $Exam -EnabledTargets @('Linux')

            $Result['Linux'].Port | Should -Be 20022
        }
    }

    Context 'When both primary and fallback fail' {

        It 'Returns Unreachable when fallback also fails' {
            Mock Test-SshConnection { return $false }
            Mock Read-Host {
                param($Prompt)
                if ($Prompt -match 'hostname') { return 'bad.host.com' }
                return ''
            }

            $Result = Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $script:FakeTuiConfigPath -Exam $Exam -EnabledTargets @('Linux')

            $Result['Linux'].HostName | Should -BeNullOrEmpty
            $Result['Linux'].Status   | Should -Be 'Unreachable'
        }

        It 'Returns Unreachable when no fallback is provided' {
            Mock Test-SshConnection { return $false }
            Mock Read-Host { return '' }

            $Result = Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $script:FakeTuiConfigPath -Exam $Exam -EnabledTargets @('Linux')

            $Result['Linux'].HostName | Should -BeNullOrEmpty
            $Result['Linux'].Status   | Should -Be 'Unreachable'
        }
    }

    Context 'When target is not found' {

        It 'Returns NotFound for missing targets' {
            $Result = Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $script:FakeTuiConfigPath -Exam $Exam -EnabledTargets @('NonExistent')

            $Result['NonExistent'].HostName | Should -BeNullOrEmpty
            $Result['NonExistent'].Status   | Should -Be 'NotFound'
        }
    }

    Context 'Parameter validation' {

        It 'Requires TuiConfig' {
            { Get-ConnectionFallback -Exam $Exam -TuiConfigPath $script:FakeTuiConfigPath -EnabledTargets @('Linux') } | Should -Throw
        }

        It 'Requires TuiConfigPath' {
            { Get-ConnectionFallback -TuiConfig $TuiConfig -Exam $Exam -EnabledTargets @('Linux') } | Should -Throw
        }

        It 'Requires Exam' {
            { Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $script:FakeTuiConfigPath -EnabledTargets @('Linux') } | Should -Throw
        }

        It 'Requires non-empty EnabledTargets' {
            { Get-ConnectionFallback -TuiConfig $TuiConfig -TuiConfigPath $script:FakeTuiConfigPath -Exam $Exam -EnabledTargets @() } | Should -Throw
        }
    }
}
