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
        # Reset the P8 module check cache so results do not bleed between tests.
        if ($null -ne $script:ModuleCheckCache) { $script:ModuleCheckCache.Clear() }
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

    Context 'Module check cache (P8)' -Tag 'Performance' {
        BeforeEach {
            # Reset the module check cache so cache hits do not bleed between tests.
            if ($null -ne $script:ModuleCheckCache) { $script:ModuleCheckCache.Clear() }
            $script:ModuleCheckCallCount = 0
            Mock Invoke-Command -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Module' } {
                $script:ModuleCheckCallCount++
                return $true
            }
        }

        It 'Makes the module check round-trip only once when called twice for the same target and module' {
            $Deps = @{ Modules = @('Pester') }
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -Dependencies $Deps
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -Dependencies $Deps
            $script:ModuleCheckCallCount | Should -Be 1
        }

        It 'Makes one module check per unique host:port when targets differ' {
            $Deps = @{ Modules = @('Pester') }
            $AltSession = [PSCustomObject]@{
                PSTypeName = 'Sage.RemoteSession'
                TargetName = 'OtherVM'
                HostName   = '10.0.0.2'
                Port       = 30022
                Platform   = 'Linux'
                Session    = $script:FakePsSession
            }
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -Dependencies $Deps
            Invoke-RemoteSetup -RemoteSession $AltSession -Dependencies $Deps
            $script:ModuleCheckCallCount | Should -Be 2
        }

        It 'Writes a Verbose log on a cache hit' {
            $Deps = @{ Modules = @('Pester') }
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -Dependencies $Deps
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -Dependencies $Deps
            Should -Invoke Write-Log -ParameterFilter {
                $Level -eq 'Verbose' -and $Message -match '[Cc]ache hit'
            }
        }
    }
    Context 'Hash-based file skip (P3)' -Tag 'Performance' {
        BeforeEach {
            $script:CopiedPaths = @()
            $script:HashQueryCount = 0
            Mock Copy-File { $script:CopiedPaths += $RemotePath }
            # Track calls to batched remote hash query (ScriptBlock contains Get-FileHash).
            # Default: return empty hashtable (no remote files) — all files need copying.
            Mock Invoke-Command -ParameterFilter { $ScriptBlock.ToString() -match 'Get-FileHash' } {
                $script:HashQueryCount++
                @{}
            }
        }

        It 'Does not call hash query when -ForceRefresh is set' {
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession -ForceRefresh
            $script:HashQueryCount | Should -Be 0
        }

        It 'Calls hash query once per copy loop (2 total) when ForceRefresh is not set' {
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession
            $script:HashQueryCount | Should -Be 2
        }

        It 'Copies all files when no remote hashes are returned' {
            # Default mock returns @{} — no remote hashes — all files treated as absent.
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession
            $script:CopiedPaths.Count | Should -BeGreaterThan 0
        }

        It 'Skips all files and writes Verbose log when local and remote hashes match' {
            # Mock Get-FileHash so every local file returns a known hash.
            Mock Get-FileHash { [PSCustomObject]@{ Hash = 'AABBCC'; Algorithm = 'SHA256' } }
            # Pre-compute the remote paths the production code will query for Linux targets.
            $CollDir = Join-Path $PSScriptRoot '..\..\Sage\Collectors'
            $EvalDir = Join-Path $PSScriptRoot '..\..\Sage\Evaluators'
            $MatchingHashes = @{}
            Get-ChildItem -Path $CollDir -Filter '*.ps1' | ForEach-Object {
                $MatchingHashes["/tmp/sage-collectors/$($_.Name)"] = 'AABBCC'
            }
            Get-ChildItem -Path $EvalDir -Filter '*.ps1' | ForEach-Object {
                $MatchingHashes["/tmp/sage-evaluations/$($_.Name)"] = 'AABBCC'
            }
            # Override the hash query mock to return matching hashes — closure captures $MatchingHashes.
            Mock Invoke-Command -ParameterFilter { $ScriptBlock.ToString() -match 'Get-FileHash' } {
                $MatchingHashes
            }
            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession
            $script:CopiedPaths.Count | Should -Be 0
            Should -Invoke Write-Log -ParameterFilter {
                $Level -eq 'Verbose' -and $Message -match '[Ss]kipped'
            }
        }

        It 'Skips files when remote hash payload is returned as deserialized object' {
            Mock Get-FileHash { [PSCustomObject]@{ Hash = 'AABBCC'; Algorithm = 'SHA256' } }

            $CollDir = Join-Path $PSScriptRoot '..\..\Sage\Collectors'
            $EvalDir = Join-Path $PSScriptRoot '..\..\Sage\Evaluators'
            $MatchingHashes = @{}
            Get-ChildItem -Path $CollDir -Filter '*.ps1' | ForEach-Object {
                $MatchingHashes["/tmp/sage-collectors/$($_.Name)"] = 'AABBCC'
            }
            Get-ChildItem -Path $EvalDir -Filter '*.ps1' | ForEach-Object {
                $MatchingHashes["/tmp/sage-evaluations/$($_.Name)"] = 'AABBCC'
            }

            Mock Invoke-Command -ParameterFilter { $ScriptBlock.ToString() -match 'Get-FileHash' } {
                [PSCustomObject] $MatchingHashes
            }

            Invoke-RemoteSetup -RemoteSession $script:FakeRemoteSession
            $script:CopiedPaths.Count | Should -Be 0
        }
    }
}