#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Invoke-SshKeySetup.
.DESCRIPTION
    Verifies the SSH key setup orchestration: key generation, auth testing,
    password prompting, key distribution, and re-testing logic.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Test-SshKeyAuth.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Install-SshKeyOnTarget.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Invoke-SshKeySetup.ps1')
}

Describe 'Invoke-SshKeySetup' -Tag 'Unit' {

    BeforeEach {
        # Create a temporary key directory
        $script:TempKeyDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-keys-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -Path $script:TempKeyDir -ItemType Directory -Force | Out-Null

        $script:PrivKeyPath = Join-Path $script:TempKeyDir 'id_sage'
        $script:PubKeyPath  = Join-Path $script:TempKeyDir 'id_sage.pub'

        # Pre-create mock key files
        Set-Content -Path $script:PrivKeyPath -Value 'MOCK_PRIVATE_KEY'
        Set-Content -Path $script:PubKeyPath -Value 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey sage@test'

        $script:MockExam = @{
            Targets = @{
                Linux  = @{ Port = 22; UserName = 'student'; Platform = 'Linux' }
                DC1    = @{ Port = 22; UserName = 'administrator'; Platform = 'Windows' }
                Client = @{ Port = 22; UserName = 'student'; Platform = 'Windows' }
            }
        }

        $script:MockConnInfo = @{
            Linux  = [PSCustomObject]@{ HostName = '192.168.1.2'; Port = 22; Status = 'Primary' }
            DC1    = [PSCustomObject]@{ HostName = '192.168.1.3'; Port = 22; Status = 'Primary' }
            Client = [PSCustomObject]@{ HostName = '192.168.1.5'; Port = 22; Status = 'Primary' }
        }

        Mock Write-Host {}
    }

    AfterEach {
        if (Test-Path $script:TempKeyDir) {
            Remove-Item -Path $script:TempKeyDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ── All targets pass key auth immediately ──────────────────────────────────
    Context 'When all targets pass key auth' {

        BeforeEach {
            Mock Test-SshKeyAuth { $true }
        }

        It 'Returns all targets as KeyAuthWorks = true' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].KeyAuthWorks | Should -BeTrue
            $Result['DC1'].KeyAuthWorks | Should -BeTrue
            $Result['Client'].KeyAuthWorks | Should -BeTrue
        }

        It 'Does not prompt for a password' {
            Mock Read-Host { 'should-not-be-called' }

            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Read-Host -Times 0
        }

        It 'Does not call Install-SshKeyOnTarget' {
            Mock Install-SshKeyOnTarget {}

            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Install-SshKeyOnTarget -Times 0
        }

        It 'Sets PasswordUsed to false for all targets' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].PasswordUsed | Should -BeFalse
            $Result['DC1'].PasswordUsed | Should -BeFalse
            $Result['Client'].PasswordUsed | Should -BeFalse
        }
    }

    # ── Some targets fail key auth ─────────────────────────────────────────────
    Context 'When some targets fail key auth' {

        BeforeEach {
            # Linux passes, DC1 and Client fail initially
            $script:AuthCallCount = @{}
            Mock Test-SshKeyAuth {
                $Key = "${HostName}:${Port}"
                if (-not $script:AuthCallCount.ContainsKey($Key)) {
                    $script:AuthCallCount[$Key] = 0
                }
                $script:AuthCallCount[$Key]++

                if ($UserName -eq 'student' -and $Port -eq 22 -and $HostName -eq '192.168.1.2') {
                    return $true
                }
                # DC1 and Client fail on first call, succeed on second (after key install)
                return ($script:AuthCallCount[$Key] -gt 1)
            }

            Mock Read-Host { 'Student1' }
            Mock Install-SshKeyOnTarget { [PSCustomObject]@{ Success = $true; HostName = $HostName; Port = $Port; Message = 'Key installed' } }
        }

        It 'Prompts for password exactly once' {
            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Read-Host -Times 1
        }

        It 'Calls Install-SshKeyOnTarget for each failing target' {
            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Install-SshKeyOnTarget -Times 2
        }

        It 'Returns KeyAuthWorks = true after successful re-test' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].KeyAuthWorks | Should -BeTrue
            $Result['DC1'].KeyAuthWorks | Should -BeTrue
            $Result['Client'].KeyAuthWorks | Should -BeTrue
        }

        It 'Sets PasswordUsed = true for targets that needed key install' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].PasswordUsed | Should -BeFalse
            $Result['DC1'].PasswordUsed | Should -BeTrue
            $Result['Client'].PasswordUsed | Should -BeTrue
        }

        It 'Passes the user password to Install-SshKeyOnTarget as a SecureString' {
            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Install-SshKeyOnTarget -Times 2 -ParameterFilter {
                $Password -is [System.Security.SecureString] -and
                ([System.Net.NetworkCredential]::new('', $Password).Password) -eq 'Student1'
            }
        }

        It 'Passes the correct platform to Install-SshKeyOnTarget' {
            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Install-SshKeyOnTarget -Times 1 -ParameterFilter {
                $Platform -eq 'Windows' -and $UserName -eq 'administrator'
            }
            Should -Invoke Install-SshKeyOnTarget -Times 1 -ParameterFilter {
                $Platform -eq 'Windows' -and $UserName -eq 'student'
            }
        }
    }

    # ── Key auth still fails after installation ────────────────────────────────
    Context 'When key auth still fails after installation' {

        BeforeEach {
            Mock Test-SshKeyAuth { $false }
            Mock Read-Host { 'Student1' }
            Mock Install-SshKeyOnTarget { [PSCustomObject]@{ Success = $true; HostName = $HostName; Port = $Port; Message = 'Key installed' } }
        }

        It 'Returns KeyAuthWorks = false for persistently failing targets' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].KeyAuthWorks | Should -BeFalse
            $Result['DC1'].KeyAuthWorks | Should -BeFalse
            $Result['Client'].KeyAuthWorks | Should -BeFalse
        }

        It 'Sets PasswordUsed = true even when auth still fails' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].PasswordUsed | Should -BeTrue
            $Result['DC1'].PasswordUsed | Should -BeTrue
        }

        It 'Sets message indicating verification failed' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].Message | Should -Match 'verification failed'
        }
    }

    # ── Unreachable targets ────────────────────────────────────────────────────
    Context 'When some targets are unreachable' {

        BeforeEach {
            Mock Test-SshKeyAuth { $true }

            $script:MixedConnInfo = @{
                Linux = [PSCustomObject]@{ HostName = '192.168.1.2'; Port = 22; Status = 'Primary' }
                DC1   = [PSCustomObject]@{ HostName = $null; Port = 22; Status = 'Unreachable' }
            }
        }

        It 'Marks unreachable targets as KeyAuthWorks = false' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MixedConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['DC1'].KeyAuthWorks | Should -BeFalse
            $Result['DC1'].Message | Should -Match 'unreachable'
        }

        It 'Still tests reachable targets' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MixedConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].KeyAuthWorks | Should -BeTrue
        }

        It 'Does not attempt Install-SshKeyOnTarget for unreachable targets' {
            Mock Install-SshKeyOnTarget {}

            Invoke-SshKeySetup -ConnectionInfo $script:MixedConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Install-SshKeyOnTarget -Times 0
        }
    }

    # ── No password provided ──────────────────────────────────────────────────
    Context 'When user provides no password' {

        BeforeEach {
            Mock Test-SshKeyAuth { $false }
            Mock Read-Host { '' }
        }

        It 'Returns KeyAuthWorks = false for all failing targets' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].KeyAuthWorks | Should -BeFalse
            $Result['DC1'].KeyAuthWorks | Should -BeFalse
        }

        It 'Does not call Install-SshKeyOnTarget' {
            Mock Install-SshKeyOnTarget {}

            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Install-SshKeyOnTarget -Times 0
        }

        It 'Sets PasswordUsed = false' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].PasswordUsed | Should -BeFalse
        }

        It 'Sets message about no password provided' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].Message | Should -Match 'No password'
        }
    }

    # ── Key generation ─────────────────────────────────────────────────────────
    Context 'When SAGE key pair does not exist' {

        BeforeEach {
            # Remove the pre-created key files
            Remove-Item -Path $script:PrivKeyPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $script:PubKeyPath -Force -ErrorAction SilentlyContinue

            Mock Test-SshKeyAuth { $true }
        }

        It 'Calls ssh-keygen to generate a new key pair' {
            # Mock ssh-keygen to create the key files
            Mock ssh-keygen {
                Set-Content -Path (Join-Path $script:TempKeyDir 'id_sage') -Value 'MOCK_PRIVATE_KEY'
                Set-Content -Path (Join-Path $script:TempKeyDir 'id_sage.pub') -Value 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGenerated sage@test'
            }

            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke ssh-keygen -Times 1
        }

        It 'Returns failure result when key generation fails' {
            Mock ssh-keygen {}

            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result['Linux'].KeyAuthWorks | Should -BeFalse
            $Result['Linux'].Message | Should -Match 'generation failed'
        }
    }

    Context 'When only private key exists (partial key pair)' {

        BeforeEach {
            Remove-Item -Path $script:PubKeyPath -Force -ErrorAction SilentlyContinue

            Mock Test-SshKeyAuth { $true }
            Mock ssh-keygen {
                Set-Content -Path (Join-Path $script:TempKeyDir 'id_sage') -Value 'MOCK_PRIVATE_KEY'
                Set-Content -Path (Join-Path $script:TempKeyDir 'id_sage.pub') -Value 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGenerated sage@test'
            }
        }

        It 'Regenerates the key pair' {
            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke ssh-keygen -Times 1
        }
    }

    # ── Result structure ───────────────────────────────────────────────────────
    Context 'Result object structure' {

        BeforeEach {
            Mock Test-SshKeyAuth { $true }
        }

        It 'Returns a hashtable' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result | Should -BeOfType [hashtable]
        }

        It 'Has entries for all targets in ConnectionInfo' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result.Keys | Should -Contain 'Linux'
            $Result.Keys | Should -Contain 'DC1'
            $Result.Keys | Should -Contain 'Client'
        }

        It 'Each entry has KeyAuthWorks, PasswordUsed, Message properties' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            foreach ($TargetName in $Result.Keys) {
                $Entry = $Result[$TargetName]
                $Entry.PSObject.Properties.Name | Should -Contain 'KeyAuthWorks'
                $Entry.PSObject.Properties.Name | Should -Contain 'PasswordUsed'
                $Entry.PSObject.Properties.Name | Should -Contain 'Message'
            }
        }
    }

    # ── Test-SshKeyAuth invocation ─────────────────────────────────────────────
    Context 'Test-SshKeyAuth invocation' {

        BeforeEach {
            Mock Test-SshKeyAuth { $true }
        }

        It 'Passes the correct key file path to Test-SshKeyAuth' {
            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Test-SshKeyAuth -ParameterFilter {
                $KeyFilePath -eq $script:PrivKeyPath
            }
        }

        It 'Passes the correct hostname and port from ConnectionInfo' {
            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Test-SshKeyAuth -ParameterFilter {
                $HostName -eq '192.168.1.2' -and $Port -eq 22
            }
        }

        It 'Passes the correct username from Exam targets' {
            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Test-SshKeyAuth -ParameterFilter {
                $UserName -eq 'administrator'
            }
        }
    }

    # ── Key directory resolution ───────────────────────────────────────────────
    Context 'Key directory parameter' {

        BeforeEach {
            Mock Test-SshKeyAuth { $true }
        }

        It 'Uses the specified KeyDir' {
            $Result = Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            $Result | Should -Not -BeNullOrEmpty
        }
    }

    # ── Install-SshKeyOnTarget parameters ──────────────────────────────────────
    Context 'Install-SshKeyOnTarget parameter passing' {

        BeforeEach {
            Mock Test-SshKeyAuth { $false }
            Mock Read-Host { 'TestPassword' }
            Mock Install-SshKeyOnTarget { [PSCustomObject]@{ Success = $true; HostName = $HostName; Port = $Port; Message = 'OK' } }
        }

        It 'Passes the public key content to Install-SshKeyOnTarget' {
            Invoke-SshKeySetup -ConnectionInfo $script:MockConnInfo -Exam $script:MockExam -KeyDir $script:TempKeyDir

            Should -Invoke Install-SshKeyOnTarget -ParameterFilter {
                $PublicKeyContent -eq 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey sage@test'
            }
        }

        It 'Passes correct HostName from ConnectionInfo' {
            $SingleConn = @{
                Linux = [PSCustomObject]@{ HostName = '10.0.0.99'; Port = 2022; Status = 'Primary' }
            }
            $SingleExam = @{
                Targets = @{
                    Linux = @{ Port = 22; UserName = 'student'; Platform = 'Linux' }
                }
            }

            Invoke-SshKeySetup -ConnectionInfo $SingleConn -Exam $SingleExam -KeyDir $script:TempKeyDir

            Should -Invoke Install-SshKeyOnTarget -ParameterFilter {
                $HostName -eq '10.0.0.99' -and $Port -eq 2022
            }
        }
    }
}
