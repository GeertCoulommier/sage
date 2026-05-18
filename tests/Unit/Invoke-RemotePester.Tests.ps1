#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Invoke-RemotePester function.
.DESCRIPTION
    Tests: evaluation script not found, successful execution returning
    Pester-like result, platform-based remote path selection, and logging.
.TAGS Unit
#>

BeforeAll {
    $WriteLogPath = Join-Path $PSScriptRoot '..\..\Sage\Private\Write-Log.ps1'
    $CopyFilePath = Join-Path $PSScriptRoot '..\..\Sage\Private\Copy-File.ps1'
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\Invoke-RemotePester.ps1'
    . $WriteLogPath
    . $CopyFilePath
    . $Sut
}

Describe 'Invoke-RemotePester' -Tag 'Unit' {

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

    Context 'Evaluation script not found' {
        It 'Throws a terminating error' {
            { Invoke-RemotePester -EvaluationName 'NonExistent' -RemoteSession $script:FakeRemoteSession -ErrorAction Stop } | Should -Throw '*not found*'
        }
    }

    Context 'Successful evaluation execution' {
        BeforeEach {
            $script:EvalsDir = Join-Path $PSScriptRoot '..\..\Sage\Evaluators'
            $script:TmpEvalFile = Join-Path $script:EvalsDir 'UnitTestEval.Tests.ps1'
            if (-not (Test-Path $script:EvalsDir)) {
                New-Item -ItemType Directory -Path $script:EvalsDir -Force | Out-Null
            }
            '# placeholder eval' | Set-Content -Path $script:TmpEvalFile

            $script:FakePesterResult = [PSCustomObject]@{
                PassedCount  = 3
                FailedCount  = 1
                SkippedCount = 0
                TotalCount   = 4
                Duration     = [timespan]::FromSeconds(1.5)
                Tests        = @(
                    [PSCustomObject]@{ Name = 'T1'; Result = 'Passed' }
                    [PSCustomObject]@{ Name = 'T2'; Result = 'Failed' }
                )
            }
            Mock Invoke-Command { return $script:FakePesterResult }
        }
        AfterEach {
            Remove-Item $script:TmpEvalFile -Force -ErrorAction SilentlyContinue
        }

        It 'Returns a Pester result object with PassedCount and FailedCount' {
            $Result = Invoke-RemotePester -EvaluationName 'UnitTestEval' -RemoteSession $script:FakeRemoteSession
            $Result.PassedCount | Should -Be 3
            $Result.FailedCount | Should -Be 1
        }

        It 'Copies the evaluation file before running' {
            Invoke-RemotePester -EvaluationName 'UnitTestEval' -RemoteSession $script:FakeRemoteSession
            Should -Invoke Copy-File -Times 1
        }

        It 'Logs start and finish messages' {
            Invoke-RemotePester -EvaluationName 'UnitTestEval' -RemoteSession $script:FakeRemoteSession
            Should -Invoke Write-Log -Times 2 -ParameterFilter { $Category -eq 'Pester' }
        }
    }

    Context 'Windows platform remote path' {
        BeforeEach {
            $script:FakeRemoteSession.Platform = 'Windows'
            $script:EvalsDir = Join-Path $PSScriptRoot '..\..\Sage\Evaluators'
            $script:TmpEvalFile = Join-Path $script:EvalsDir 'WinEval.Tests.ps1'
            if (-not (Test-Path $script:EvalsDir)) {
                New-Item -ItemType Directory -Path $script:EvalsDir -Force | Out-Null
            }
            '# placeholder' | Set-Content -Path $script:TmpEvalFile

            # First Invoke-Command call resolves the remote path (returns a string).
            # Subsequent calls run Pester (returns a result object).
            $script:InvokeCommandCallCount = 0
            Mock Invoke-Command {
                $script:InvokeCommandCallCount++
                if ($script:InvokeCommandCallCount -eq 1) {
                    return 'C:\TEMP\sage-evaluations\WinEval.Tests.ps1'
                }
                return [PSCustomObject]@{ PassedCount = 1; FailedCount = 0; TotalCount = 1 }
            }
        }
        AfterEach {
            Remove-Item $script:TmpEvalFile -Force -ErrorAction SilentlyContinue
        }

        It 'Uses Windows remote path for Windows platform' {
            Invoke-RemotePester -EvaluationName 'WinEval' -RemoteSession $script:FakeRemoteSession
            Should -Invoke Copy-File -Times 1 -ParameterFilter { $RemotePath -match 'sage-evaluations' }
        }
    }

    Context 'Container and block errors are logged' {
        BeforeEach {
            $script:EvalsDir = Join-Path $PSScriptRoot '..\..\Sage\Evaluators'
            $script:TmpEvalFile = Join-Path $script:EvalsDir 'ErrEval.Tests.ps1'
            if (-not (Test-Path $script:EvalsDir)) {
                New-Item -ItemType Directory -Path $script:EvalsDir -Force | Out-Null
            }
            '# placeholder' | Set-Content -Path $script:TmpEvalFile

            Mock Invoke-Command {
                return @{
                    PassedCount     = 0
                    FailedCount     = 0
                    SkippedCount    = 0
                    TotalCount      = 0
                    Duration        = '00:00:01'
                    Tests           = @()
                    ContainerErrors = @('Discovery failed: syntax error')
                    BlockErrors     = @('[DNS]: BeforeAll threw an exception')
                }
            }
        }
        AfterEach {
            Remove-Item $script:TmpEvalFile -Force -ErrorAction SilentlyContinue
        }

        It 'Logs container errors via Write-Log' {
            Invoke-RemotePester -EvaluationName 'ErrEval' -RemoteSession $script:FakeRemoteSession
            Should -Invoke Write-Log -ParameterFilter {
                $Level -eq 'Error' -and $Message -match 'Container error'
            }
        }

        It 'Logs block errors via Write-Log' {
            Invoke-RemotePester -EvaluationName 'ErrEval' -RemoteSession $script:FakeRemoteSession
            Should -Invoke Write-Log -ParameterFilter {
                $Level -eq 'Error' -and $Message -match 'Block error'
            }
        }

        It 'Still returns the result object' {
            $Result = Invoke-RemotePester -EvaluationName 'ErrEval' -RemoteSession $script:FakeRemoteSession
            $Result.TotalCount | Should -Be 0
        }
    }

    Context 'Variables and CollectedData are passed through' {
        BeforeEach {
            $script:EvalsDir = Join-Path $PSScriptRoot '..\..\Sage\Evaluators'
            $script:TmpEvalFile = Join-Path $script:EvalsDir 'VarEval.Tests.ps1'
            if (-not (Test-Path $script:EvalsDir)) {
                New-Item -ItemType Directory -Path $script:EvalsDir -Force | Out-Null
            }
            '# placeholder' | Set-Content -Path $script:TmpEvalFile

            Mock Invoke-Command {
                return @{
                    PassedCount     = 1
                    FailedCount     = 0
                    SkippedCount    = 0
                    TotalCount      = 1
                    Duration        = '00:00:01'
                    Tests           = @()
                    ContainerErrors = @()
                    BlockErrors     = @()
                }
            }
        }
        AfterEach {
            Remove-Item $script:TmpEvalFile -Force -ErrorAction SilentlyContinue
        }

        It 'Accepts Variables and CollectedData parameters without error' {
            $Params = @{
                EvaluationName = 'VarEval'
                RemoteSession  = $script:FakeRemoteSession
                Variables      = @{ Ip = '10.0.0.1' }
                CollectedData  = @{ Zones = @() }
            }
            { Invoke-RemotePester @Params } | Should -Not -Throw
            Should -Invoke Invoke-Command -Times 1
        }
    }

    Context 'EvaluationsPath parameter' {
        BeforeEach {
            $script:TmpEvalDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-pester-eval-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            New-Item -Path $script:TmpEvalDir -ItemType Directory -Force | Out-Null
            '# custom placeholder' | Set-Content -Path (Join-Path $script:TmpEvalDir 'CustomEval.Tests.ps1')

            Mock Invoke-Command {
                return @{
                    PassedCount     = 1
                    FailedCount     = 0
                    SkippedCount    = 0
                    TotalCount      = 1
                    Duration        = '00:00:01'
                    Tests           = @()
                    ContainerErrors = @()
                    BlockErrors     = @()
                }
            }
        }
        AfterEach {
            Remove-Item -Path $script:TmpEvalDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Finds the evaluation file in custom EvaluationsPath' {
            $Params = @{
                EvaluationName  = 'CustomEval'
                RemoteSession   = $script:FakeRemoteSession
                EvaluationsPath = $script:TmpEvalDir
            }
            { Invoke-RemotePester @Params } | Should -Not -Throw
            Should -Invoke Copy-File -Times 1
        }

        It 'Throws when evaluation file is not in the custom path' {
            $Params = @{
                EvaluationName  = 'DoesNotExist'
                RemoteSession   = $script:FakeRemoteSession
                EvaluationsPath = $script:TmpEvalDir
            }
            { Invoke-RemotePester @Params -ErrorAction Stop } | Should -Throw '*not found*'
        }

        It 'Uses default Evaluations/ directory when EvaluationsPath is not specified' {
            $EvalsDir = Join-Path $PSScriptRoot '..\..\Sage\Evaluators'
            $TmpFile = Join-Path $EvalsDir 'DefaultPathEval.Tests.ps1'
            '# placeholder' | Set-Content -Path $TmpFile
            try {
                $Params = @{
                    EvaluationName = 'DefaultPathEval'
                    RemoteSession  = $script:FakeRemoteSession
                }
                { Invoke-RemotePester @Params } | Should -Not -Throw
            }
            finally {
                Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
