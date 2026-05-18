#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Invoke-RemoteSetup function.
.DESCRIPTION
    Tests: module install via Install-Module, fallback to local copy,
    module not found locally, collector/evaluation script copying,
    and no-dependency scenario.
.TAGS Unit
#>

BeforeAll {
    $WriteLogPath = Join-Path $PSScriptRoot '..\..\Sage\Private\Write-Log.ps1'
    $CopyFilePath = Join-Path $PSScriptRoot '..\..\Sage\Private\Copy-File.ps1'
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\Invoke-RemoteSetup.ps1'
    . $WriteLogPath
    . $CopyFilePath
    . $Sut
}

Describe 'Invoke-RemoteSetup' -Tag 'Unit' {

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
        Mock Invoke-Command {}
        Mock Copy-Item {}
    }

    Context 'No dependencies—no module install' {
        It 'Does not throw when Dependencies is empty' {
            { Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession } | Should -Not -Throw
        }
    }

    Context 'Module already installed remotely' {
        BeforeEach {
            # First Invoke-Command call checks if module is present → returns $true
            Mock Invoke-Command { return $true }
        }

        It 'Skips module installation when already present' {
            $Deps = @{ Modules = @('Pester') }
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -Dependencies $Deps
            # Invoke-Command called once for the check, not for install
            Should -Invoke Invoke-Command -Times 1
        }
    }

    Context 'Module install via Install-Module succeeds' {
        BeforeEach {
            $script:CallCount = 0
            Mock Invoke-Command {
                $script:CallCount++
                if ($script:CallCount -eq 1) { return $false }  # not installed
                # second call: Install-Module succeeds (no throw)
            }
        }

        It 'Calls Invoke-Command twice—check and install' {
            $Deps = @{ Modules = @('Pester') }
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -Dependencies $Deps
            Should -Invoke Invoke-Command -Times 2
        }
    }

    Context 'Module install fails—local fallback' {
        BeforeEach {
            $script:CallCount = 0
            Mock Invoke-Command {
                $script:CallCount++
                if ($script:CallCount -eq 1) { return $false }   # not installed
                if ($script:CallCount -eq 2) { throw 'no internet' }  # install fails
            }
            # Get-Module finds a local copy
            Mock Get-Module {
                return [PSCustomObject]@{
                    Name = 'Pester'
                    Path = (Join-Path ([System.IO.Path]::GetTempPath()) 'Pester' 'Pester.psd1')
                }
            }
        }

        It 'Falls back to Copy-Item when Install-Module fails' {
            $Deps = @{ Modules = @('Pester') }
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -Dependencies $Deps
            Should -Invoke Copy-Item -Times 1
        }
    }

    Context 'Module install fails—no local module available' {
        BeforeEach {
            $script:CallCount = 0
            Mock Invoke-Command {
                $script:CallCount++
                if ($script:CallCount -eq 1) { return $false }
                if ($script:CallCount -eq 2) { throw 'no internet' }
            }
            Mock Get-Module { return $null }
        }

        It 'Throws a terminating error' {
            $Deps = @{ Modules = @('Pester') }
            { Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -Dependencies $Deps -ErrorAction Stop } | Should -Throw '*not available locally*'
        }
    }

    Context 'Linux remote path uses forward slashes' {
        BeforeEach {
            # Simulate Linux session (Platform = Linux, no $env:TEMP)
            $script:LinuxSession = [PSCustomObject]@{
                PSTypeName = 'Sage.RemoteSession'
                TargetName = 'Linux'
                HostName   = '10.0.0.1'
                Port       = 20022
                Platform   = 'Linux'
                Session    = $script:FakePsSession
            }
            Mock Invoke-Command {}  # Pester already installed + dir creation

            $script:CopiedPaths = [System.Collections.Generic.List[string]]::new()
            Mock Copy-File {
                $script:CopiedPaths.Add($RemotePath)
            }
        }

        It 'Copies collector scripts to forward-slash path on Linux' {
            Invoke-RemoteSetup -RemoteSession $script:LinuxSession
            $CollectorPaths = $script:CopiedPaths | Where-Object { $_ -like '*/sage-collectors/*' }
            $CollectorPaths.Count | Should -BeGreaterThan 0
            foreach ($P in $CollectorPaths) {
                $P | Should -Match '^/tmp/sage-collectors/'
            }
        }

        It 'Copies evaluation scripts to forward-slash path on Linux' {
            Invoke-RemoteSetup -RemoteSession $script:LinuxSession
            $EvalPaths = $script:CopiedPaths | Where-Object { $_ -like '*/sage-evaluations/*' }
            $EvalPaths.Count | Should -BeGreaterThan 0
            foreach ($P in $EvalPaths) {
                $P | Should -Match '^/tmp/sage-evaluations/'
            }
        }

        It 'Does not use backslash paths for Linux remote target' {
            Invoke-RemoteSetup -RemoteSession $script:LinuxSession
            foreach ($P in $script:CopiedPaths) {
                $P | Should -Not -Match '\\'
            }
        }
    }

    Context 'Windows remote path uses Invoke-Command for path resolution' {
        BeforeEach {
            $script:WinSession = [PSCustomObject]@{
                PSTypeName = 'Sage.RemoteSession'
                TargetName = 'WinSrv1'
                HostName   = '10.0.0.1'
                Port       = 30022
                Platform   = 'Windows'
                Session    = $script:FakePsSession
            }

            $script:InvokeCalls = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-Command {
                $script:InvokeCalls.Add('called')
                # Return Windows-style paths for path resolution calls
                return 'C:\Users\admin\Documents\PowerShell\Modules\Pester'
            }

            $script:CopiedPaths = [System.Collections.Generic.List[string]]::new()
            Mock Copy-File {
                $script:CopiedPaths.Add($RemotePath)
            }
        }

        It 'Uses Invoke-Command to resolve remote paths for Windows targets' {
            Invoke-RemoteSetup -RemoteSession $script:WinSession
            # Multiple Invoke-Command calls for windows path resolution
            $script:InvokeCalls.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Module install—local fallback on Windows platform' {
        BeforeEach {
            $script:WinSession = [PSCustomObject]@{
                PSTypeName = 'Sage.RemoteSession'
                TargetName = 'WinSrv1'
                HostName   = '10.0.0.1'
                Port       = 30022
                Platform   = 'Windows'
                Session    = $script:FakePsSession
            }

            $script:CallCount = 0
            Mock Invoke-Command {
                $script:CallCount++
                if ($script:CallCount -eq 1) { return $false }   # not installed
                if ($script:CallCount -eq 2) { throw 'no internet' }  # install fails
                # Remaining calls: path resolution for module destination
                return 'C:\Users\admin\Documents\PowerShell\Modules\Pester'
            }
            Mock Get-Module {
                return [PSCustomObject]@{
                    Name = 'Pester'
                    Path = (Join-Path ([System.IO.Path]::GetTempPath()) 'Pester' 'Pester.psd1')
                }
            }
        }

        It 'Falls back to Copy-Item on Windows using remote path resolution' {
            $Deps = @{ Modules = @('Pester') }
            Invoke-RemoteSetup -RemoteSession $script:WinSession -Dependencies $Deps
            Should -Invoke Copy-Item -Times 1
            # More than 3 Invoke-Command calls: module check, install, path resolution,
            # plus collector/evaluation path resolution for each file on Windows
            Should -Invoke Invoke-Command -Times 3
        }
    }

    Context 'EvaluationsPath parameter' {
        BeforeEach {
            Mock Invoke-Command {}

            $script:CopiedPaths = [System.Collections.Generic.List[string]]::new()
            Mock Copy-File {
                $script:CopiedPaths.Add($RemotePath)
            }

            $script:TmpEvalDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-eval-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            New-Item -Path $script:TmpEvalDir -ItemType Directory -Force | Out-Null
            '# placeholder' | Set-Content -Path (Join-Path $script:TmpEvalDir 'Custom.Tests.ps1')
        }
        AfterEach {
            Remove-Item -Path $script:TmpEvalDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Uses the custom EvaluationsPath when provided' {
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -EvaluationsPath $script:TmpEvalDir
            $EvalPaths = $script:CopiedPaths | Where-Object { $_ -like '*/sage-evaluations/*' }
            $EvalPaths.Count | Should -Be 1
        }

        It 'Copies only files from the custom path, not the default' {
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -EvaluationsPath $script:TmpEvalDir
            $EvalPaths = $script:CopiedPaths | Where-Object { $_ -like '*/sage-evaluations/*' }
            foreach ($P in $EvalPaths) {
                $P | Should -Match 'Custom\.Tests\.ps1'
            }
        }

        It 'Falls back to default Evaluations/ when EvaluationsPath is not specified' {
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession
            $EvalPaths = $script:CopiedPaths | Where-Object { $_ -like '*/sage-evaluations/*' }
            $EvalPaths.Count | Should -BeGreaterThan 0
        }
    }
}
