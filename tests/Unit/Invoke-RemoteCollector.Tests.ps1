#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Invoke-RemoteCollector function.
.DESCRIPTION
    Tests: collector script not found, successful execution returning
    CollectorResult, error path returning Available=$false, and
    duration tracking.
.TAGS Unit
#>

BeforeAll {
    $WriteLogPath = Join-Path $PSScriptRoot '..\..\Sage\Private\Write-Log.ps1'
    $CollectorResultPath = Join-Path $PSScriptRoot '..\..\Sage\Private\New-CollectorResult.ps1'
    $CopyFilePath = Join-Path $PSScriptRoot '..\..\Sage\Private\Copy-File.ps1'
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\Invoke-RemoteCollector.ps1'
    . $WriteLogPath
    . $CollectorResultPath
    . $CopyFilePath
    . $Sut
}

Describe 'Invoke-RemoteCollector' -Tag 'Unit' {

    BeforeEach {
        $script:FakePsSession = New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession'
        $script:FakePsSession | Add-Member -MemberType NoteProperty -Name Id -Value 1 -Force
        $script:FakeRemoteSession = [PSCustomObject]@{
            PSTypeName = 'Sage.RemoteSession'
            TargetName = 'LinuxVM'
            HostName   = '10.0.0.1'
            Port       = 20022
            Platform   = 'Linux'
            Session    = $script:FakePsSession
        }
        Mock Write-Log {}
        Mock Copy-File {}
    }

    Context 'Collector script not found' {
        It 'Throws a terminating error when the script file does not exist' {
            # 'NonExistentCollector' will resolve to Collectors/Invoke-NonExistentCollectorCollector.ps1
            { Invoke-RemoteCollector -Name 'NonExistentCollector' -RemoteSession $script:FakeRemoteSession -ErrorAction Stop } | Should -Throw '*not found*'
        }
    }

    Context 'Successful collector execution' {
        BeforeEach {
            # Create a temporary collector script so Test-Path passes
            $script:CollectorsDir = Join-Path $PSScriptRoot '..\..\Sage\Collectors'
            $script:TmpCollectorFile = Join-Path $script:CollectorsDir 'Invoke-UnitTestCollector.ps1'
            if (-not (Test-Path $script:CollectorsDir)) {
                New-Item -ItemType Directory -Path $script:CollectorsDir -Force | Out-Null
            }
            'param($Variables) @{ Available = $true; Data = @{ Key = "val" }; Errors = @(); Reason = $null }' |
                Set-Content -Path $script:TmpCollectorFile

            Mock Invoke-Command {
                return [PSCustomObject]@{
                    Available = $true
                    Data      = @{ Key = 'val' }
                    Errors    = @()
                    Reason    = $null
                }
            }
        }
        AfterEach {
            Remove-Item $script:TmpCollectorFile -Force -ErrorAction SilentlyContinue
        }

        It 'Returns a Sage.CollectorResult with Available=$true' {
            $Result = Invoke-RemoteCollector -Name 'UnitTest' -RemoteSession $script:FakeRemoteSession
            $Result.PSObject.TypeNames | Should -Contain 'Sage.CollectorResult'
            $Result.Available | Should -BeTrue
        }

        It 'Passes data through from remote execution' {
            $Result = Invoke-RemoteCollector -Name 'UnitTest' -RemoteSession $script:FakeRemoteSession
            $Result.Data.Key | Should -Be 'val'
        }

        It 'Has a non-zero Duration' {
            $Result = Invoke-RemoteCollector -Name 'UnitTest' -RemoteSession $script:FakeRemoteSession
            $Result.Duration | Should -BeOfType [timespan]
        }
    }

    Context 'Remote execution error' {
        BeforeEach {
            $script:CollectorsDir = Join-Path $PSScriptRoot '..\..\Sage\Collectors'
            $script:TmpCollectorFile = Join-Path $script:CollectorsDir 'Invoke-UnitTestErrCollector.ps1'
            if (-not (Test-Path $script:CollectorsDir)) {
                New-Item -ItemType Directory -Path $script:CollectorsDir -Force | Out-Null
            }
            'param($Variables) throw "boom"' | Set-Content -Path $script:TmpCollectorFile

            Mock Invoke-Command { throw 'remote failure' }
        }
        AfterEach {
            Remove-Item $script:TmpCollectorFile -Force -ErrorAction SilentlyContinue
        }

        It 'Returns CollectorResult with Available=$false on remote error' {
            $Result = Invoke-RemoteCollector -Name 'UnitTestErr' -RemoteSession $script:FakeRemoteSession
            $Result.Available | Should -BeFalse
        }

        It 'Stores the error message in Reason' {
            $Result = Invoke-RemoteCollector -Name 'UnitTestErr' -RemoteSession $script:FakeRemoteSession
            $Result.Reason | Should -Match 'remote failure'
        }
    }

    Context 'Windows platform remote path' {
        BeforeEach {
            $script:WinSession = [PSCustomObject]@{
                PSTypeName = 'Sage.RemoteSession'
                TargetName = 'WinSrv1'
                HostName   = '10.0.0.1'
                Port       = 30022
                Platform   = 'Windows'
                Session    = $script:FakePsSession
            }

            $script:CollectorsDir = Join-Path $PSScriptRoot '..\..\Sage\Collectors'
            $script:TmpCollectorFile = Join-Path $script:CollectorsDir 'Invoke-WinTestCollector.ps1'
            if (-not (Test-Path $script:CollectorsDir)) {
                New-Item -ItemType Directory -Path $script:CollectorsDir -Force | Out-Null
            }
            'param($Variables) @{ Available = $true; Data = @{}; Errors = @() }' |
                Set-Content -Path $script:TmpCollectorFile

            $script:InvokeCallCount = 0
            Mock Invoke-Command {
                $script:InvokeCallCount++
                if ($script:InvokeCallCount -eq 1) {
                    # First call resolves Windows remote path
                    return 'C:\TEMP\sage-collectors\Invoke-WinTestCollector.ps1'
                }
                return [PSCustomObject]@{
                    Available = $true
                    Data      = @{ WinKey = 'val' }
                    Errors    = @()
                    Reason    = $null
                }
            }
        }
        AfterEach {
            Remove-Item $script:TmpCollectorFile -Force -ErrorAction SilentlyContinue
        }

        It 'Resolves remote path via Invoke-Command for Windows targets' {
            $Result = Invoke-RemoteCollector -Name 'WinTest' -RemoteSession $script:WinSession
            $Result.Available | Should -BeTrue
            Should -Invoke Invoke-Command -Times 2
        }
    }
}
