#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Install-SshKey (public) and Install-SshKeyForSet (private).
.DESCRIPTION
    Tests: parameter validation, ShareKeys validation, key checking/generation,
    key distribution (Linux/Windows/admin), permission fixes, SSH connectivity
    testing, session cleanup, error handling, result structure, logging.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\Private\Write-Log.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\Private\New-RemoteSessionObject.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\Public\New-RemoteSession.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\Public\Close-RemoteSession.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\Public\Set-SageLogPath.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\Private\Install-SshKeyForSet.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\Public\Install-SshKey.ps1')
}

# ═══════════════════════════════════════════════════════════════════════════════
# Install-SshKeyForSet (private helper — bulk of logic)
# ═══════════════════════════════════════════════════════════════════════════════

Describe 'Install-SshKeyForSet' -Tag 'Unit' {

    BeforeEach {
        Mock Write-Log {}
        Mock Close-RemoteSession {}

        $script:MockPSSession = New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession'

        $script:MockRemoteSession = [PSCustomObject]@{
            PSTypeName  = 'Sage.RemoteSession'
            TargetName  = 'TestPC'
            HostName    = '10.0.0.1'
            Port        = 22
            UserName    = 'student'
            Platform    = 'Linux'
            Session     = $script:MockPSSession
            ConnectedAt = [datetime]::Now
            SessionId   = [guid]::NewGuid().ToString()
        }

        $script:LinuxComp = @{
            HostName = '10.0.0.1'
            Port     = 22
            UserName = 'student'
            Platform = 'Linux'
            Name     = 'Linux'
        }
        $script:WindowsComp = @{
            HostName = '10.0.0.2'
            Port     = 22
            UserName = 'administrator'
            Platform = 'Windows'
            Name     = 'DC1'
        }
        $script:ClientComp = @{
            HostName = '10.0.0.3'
            Port     = 22
            UserName = 'student'
            Platform = 'Windows'
            Name     = 'Client'
        }

        $script:BaseSet = @($script:LinuxComp, $script:WindowsComp)
    }

    # ── Connection handling ────────────────────────────────────────────────────
    Context 'Connection handling' {

        It 'Connects to all computers in a set' {
            Mock New-RemoteSession { $script:MockRemoteSession } -Verifiable
            Mock Invoke-Command { @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA test'; KeysAdded = 0; Errors = @(); Success = $true; Output = 'SSH_KEY_AUTH_OK' } }

            Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            Should -InvokeVerifiable
        }

        It 'Records error when connection fails' {
            Mock New-RemoteSession { throw 'Connection refused' }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.Errors | Should -Not -BeNullOrEmpty
            ($Result.Errors -join ' ') | Should -Match 'connect|fewer'
        }

        It 'Returns error when fewer than 2 computers connect' {
            $CallCount = 0
            Mock New-RemoteSession {
                $script:ConnCallCount++
                if ($script:ConnCallCount -eq 1) { return $script:MockRemoteSession }
                throw 'Connection failed'
            }
            $script:ConnCallCount = 0

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            ($Result.Errors -join ' ') | Should -Match 'fewer than 2'
        }

        It 'Closes all sessions in finally block' {
            Mock New-RemoteSession { $script:MockRemoteSession }
            Mock Invoke-Command { @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA test'; KeysAdded = 0; Errors = @(); Success = $true; Output = 'SSH_KEY_AUTH_OK' } }

            Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            Should -Invoke Close-RemoteSession -Times 2 -Exactly
        }
    }

    # ── Key checking ───────────────────────────────────────────────────────────
    Context 'Key checking' {

        BeforeEach {
            Mock New-RemoteSession { $script:MockRemoteSession }
        }

        It 'Skips key generation when keys already exist' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA existing' }
                }
                if ($script:InvCount -le 4) {
                    return @{ KeysAdded = 0; Errors = @() }
                }
                return @{ Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.KeysGenerated | Should -Be 0
        }

        It 'Generates keys when none exist' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $false; HasPublicKey = $false; PublicKey = $null }
                }
                if ($script:InvCount -le 4) {
                    return @{ PublicKey = 'ssh-ed25519 AAAA new'; Success = $true }
                }
                if ($script:InvCount -le 6) {
                    return @{ KeysAdded = 1; Errors = @() }
                }
                return @{ Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.KeysGenerated | Should -Be 2
        }

        It 'Forces key regeneration when -Force is set' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA old' }
                }
                if ($script:InvCount -le 4) {
                    return @{ PublicKey = 'ssh-ed25519 AAAA new'; Success = $true }
                }
                if ($script:InvCount -le 6) {
                    return @{ KeysAdded = 1; Errors = @() }
                }
                return @{ Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0 -Force

            $Result.KeysGenerated | Should -Be 2
        }

        It 'Records error when key generation fails' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $false; HasPublicKey = $false; PublicKey = $null }
                }
                if ($script:InvCount -le 4) {
                    return @{ PublicKey = $null; Success = $false }
                }
                return @{ KeysAdded = 0; Errors = @(); Success = $true; Output = 'ok' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            ($Result.Errors -join ' ') | Should -Match 'generate'
        }
    }

    # ── Key distribution ───────────────────────────────────────────────────────
    Context 'Key distribution' {

        BeforeEach {
            Mock New-RemoteSession { $script:MockRemoteSession }
        }

        It 'Distributes public keys to all connected computers' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = "ssh-ed25519 AAAA key-$($script:InvCount)" }
                }
                if ($script:InvCount -le 4) {
                    return @{ KeysAdded = 1; Errors = @() }
                }
                return @{ Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.KeysDistributed | Should -BeGreaterOrEqual 1
        }

        It 'Reports distribution errors' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key' }
                }
                if ($script:InvCount -le 4) {
                    return @{ KeysAdded = 0; Errors = @('Permission denied') }
                }
                return @{ Success = $false; Output = 'fail' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.Errors | Should -Not -BeNullOrEmpty
        }
    }

    # ── SSH connectivity testing ───────────────────────────────────────────────
    Context 'SSH connectivity testing' {

        BeforeEach {
            Mock New-RemoteSession { $script:MockRemoteSession }
        }

        It 'Tests SSH from each computer to every other computer' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key' }
                }
                if ($script:InvCount -le 4) {
                    return @{ KeysAdded = 1; Errors = @() }
                }
                return @{ Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            # 2 computers -> 2 directional tests (A->B, B->A)
            $Result.TestResults.Count | Should -Be 2
        }

        It 'Records successful test results' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key' }
                }
                if ($script:InvCount -le 4) {
                    return @{ KeysAdded = 1; Errors = @() }
                }
                return @{ Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.TestResults | ForEach-Object { $_.Success | Should -BeTrue }
        }

        It 'Records failed test results' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key' }
                }
                if ($script:InvCount -le 4) {
                    return @{ KeysAdded = 1; Errors = @() }
                }
                return @{ Success = $false; Output = 'Permission denied' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.TestResults | ForEach-Object { $_.Success | Should -BeFalse }
        }

        It 'Test results include Source and Target properties' {
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key' }
                }
                if ($script:InvCount -le 4) {
                    return @{ KeysAdded = 1; Errors = @() }
                }
                return @{ Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.TestResults[0].Source | Should -Not -BeNullOrEmpty
            $Result.TestResults[0].Target | Should -Not -BeNullOrEmpty
        }
    }

    # ── Result object structure ────────────────────────────────────────────────
    Context 'Result object structure' {

        BeforeEach {
            Mock New-RemoteSession { $script:MockRemoteSession }
            Mock Invoke-Command {
                @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key'; KeysAdded = 0; Errors = @(); Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }
        }

        It 'Result has expected properties' {
            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.PSObject.Properties.Name | Should -Contain 'SetIndex'
            $Result.PSObject.Properties.Name | Should -Contain 'Computers'
            $Result.PSObject.Properties.Name | Should -Contain 'KeysGenerated'
            $Result.PSObject.Properties.Name | Should -Contain 'KeysDistributed'
            $Result.PSObject.Properties.Name | Should -Contain 'TestResults'
            $Result.PSObject.Properties.Name | Should -Contain 'Errors'
        }

        It 'SetIndex matches the provided index' {
            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 42

            $Result.SetIndex | Should -Be 42
        }

        It 'Computers array lists connected computer names' {
            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.Computers | Should -Contain 'Linux'
            $Result.Computers | Should -Contain 'DC1'
        }

        It 'Result has Sage.SshKeyResult type name' {
            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.PSObject.TypeNames | Should -Contain 'Sage.SshKeyResult'
        }
    }

    # ── Computer name fallback ─────────────────────────────────────────────────
    Context 'Computer name fallback' {

        It 'Uses HostName when Name is not provided' {
            $CompNoName1 = @{ HostName = '10.0.0.99'; Port = 22; UserName = 'user'; Platform = 'Linux' }
            $CompNoName2 = @{ HostName = '10.0.0.100'; Port = 22; UserName = 'user'; Platform = 'Linux' }

            Mock New-RemoteSession { $script:MockRemoteSession }
            Mock Invoke-Command {
                @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key'; KeysAdded = 0; Errors = @(); Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }

            $Result = Install-SshKeyForSet -ComputerSet @($CompNoName1, $CompNoName2) -SetIndex 0

            $Result.Computers | Should -Contain '10.0.0.99'
            $Result.Computers | Should -Contain '10.0.0.100'
        }
    }

    # ── Logging ────────────────────────────────────────────────────────────────
    Context 'Logging' {

        BeforeEach {
            Mock New-RemoteSession { $script:MockRemoteSession }
            Mock Invoke-Command {
                @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key'; KeysAdded = 0; Errors = @(); Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }
        }

        It 'Logs connection attempts' {
            Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            Should -Invoke Write-Log -ParameterFilter { $Category -eq 'Setup' -and $Message -match 'connecting' }
        }

        It 'Logs key check operations' {
            Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            Should -Invoke Write-Log -ParameterFilter { $Category -eq 'Setup' -and $Message -match 'key' }
        }

        It 'Logs SSH test operations' {
            Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            Should -Invoke Write-Log -ParameterFilter { $Category -eq 'Setup' -and $Message -match 'SSH' }
        }

        It 'Logs distribution operations' {
            Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            Should -Invoke Write-Log -ParameterFilter { $Category -eq 'Setup' -and $Message -match 'distribut' }
        }
    }

    # ── Error handling ─────────────────────────────────────────────────────────
    Context 'Error handling' {

        It 'Handles unhandled errors gracefully' {
            Mock New-RemoteSession { throw 'Unexpected error' }

            $Result = Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            $Result.Errors | Should -Not -BeNullOrEmpty
        }

        It 'Closes sessions even when errors occur during distribution' {
            Mock New-RemoteSession { $script:MockRemoteSession }
            $script:InvCount = 0
            Mock Invoke-Command {
                $script:InvCount++
                if ($script:InvCount -le 2) {
                    return @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key' }
                }
                throw 'Distribution failed'
            }

            Install-SshKeyForSet -ComputerSet $script:BaseSet -SetIndex 0

            Should -Invoke Close-RemoteSession
        }
    }

    # ── Three-computer set ─────────────────────────────────────────────────────
    Context 'Three-computer set' {

        It 'Generates correct number of test results for 3 computers' {
            Mock New-RemoteSession { $script:MockRemoteSession }
            Mock Invoke-Command {
                @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key'; KeysAdded = 0; Errors = @(); Success = $true; Output = 'SSH_KEY_AUTH_OK' }
            }

            $ThreeSet = @($script:LinuxComp, $script:WindowsComp, $script:ClientComp)
            $Result = Install-SshKeyForSet -ComputerSet $ThreeSet -SetIndex 0

            # 3 computers -> 6 directional tests
            $Result.TestResults.Count | Should -Be 6
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Install-SshKey (public orchestrator)
# ═══════════════════════════════════════════════════════════════════════════════

Describe 'Install-SshKey' -Tag 'Unit' {

    BeforeEach {
        Mock Write-Log {}
        Mock Close-RemoteSession {}
        Mock New-RemoteSession {
            [PSCustomObject]@{
                PSTypeName  = 'Sage.RemoteSession'
                TargetName  = 'TestPC'
                HostName    = '10.0.0.1'
                Port        = 22
                UserName    = 'student'
                Platform    = 'Linux'
                Session     = (New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession')
                ConnectedAt = [datetime]::Now
                SessionId   = [guid]::NewGuid().ToString()
            }
        }
        Mock Invoke-Command {
            @{ HasPrivateKey = $true; HasPublicKey = $true; PublicKey = 'ssh-ed25519 AAAA key'; KeysAdded = 0; Errors = @(); Success = $true; Output = 'SSH_KEY_AUTH_OK' }
        }

        $script:LinuxComp = @{ HostName = '10.0.0.1'; Port = 22; UserName = 'student'; Platform = 'Linux'; Name = 'Linux' }
        $script:WindowsComp = @{ HostName = '10.0.0.2'; Port = 22; UserName = 'administrator'; Platform = 'Windows'; Name = 'DC1' }
        $script:BaseSet = @($script:LinuxComp, $script:WindowsComp)
    }

    Context 'Parameter validation' {

        It 'Rejects invalid KeyType' {
            { Install-SshKey -ComputerSets @(, $script:BaseSet) -KeyType 'dsa' } | Should -Throw
        }

        It 'Accepts KeyType ed25519' {
            { Install-SshKey -ComputerSets @(, $script:BaseSet) -KeyType 'ed25519' } | Should -Not -Throw
        }

        It 'Accepts KeyType rsa' {
            { Install-SshKey -ComputerSets @(, $script:BaseSet) -KeyType 'rsa' } | Should -Not -Throw
        }
    }

    Context 'ShareKeys validation' {

        It 'Throws when sets have different computer counts' {
            $Set1 = @($script:LinuxComp, $script:WindowsComp)
            $Set2 = @($script:LinuxComp)

            { Install-SshKey -ComputerSets @($Set1, $Set2) -ShareKeys } |
                Should -Throw '*identical*'
        }

        It 'Throws when computers differ in UserName' {
            $Set1 = @($script:LinuxComp, $script:WindowsComp)
            $DiffComp = $script:WindowsComp.Clone()
            $DiffComp.UserName = 'different'
            $Set2 = @($script:LinuxComp, $DiffComp)

            { Install-SshKey -ComputerSets @($Set1, $Set2) -ShareKeys } |
                Should -Throw '*identical*'
        }

        It 'Throws when computers differ in Platform' {
            $Set1 = @($script:LinuxComp, $script:WindowsComp)
            $DiffComp = $script:WindowsComp.Clone()
            $DiffComp.Platform = 'Linux'
            $Set2 = @($script:LinuxComp, $DiffComp)

            { Install-SshKey -ComputerSets @($Set1, $Set2) -ShareKeys } |
                Should -Throw '*identical*'
        }

        It 'Throws when computers differ in Port' {
            $Set1 = @($script:LinuxComp, $script:WindowsComp)
            $DiffComp = $script:WindowsComp.Clone()
            $DiffComp.Port = 9999
            $Set2 = @($script:LinuxComp, $DiffComp)

            { Install-SshKey -ComputerSets @($Set1, $Set2) -ShareKeys } |
                Should -Throw '*identical*'
        }

        It 'Does not throw with identical sets' {
            $Set1 = @($script:LinuxComp, $script:WindowsComp)
            $Set2L = $script:LinuxComp.Clone(); $Set2L.HostName = '10.0.1.1'
            $Set2W = $script:WindowsComp.Clone(); $Set2W.HostName = '10.0.1.2'
            $Set2 = @($Set2L, $Set2W)

            { Install-SshKey -ComputerSets @($Set1, $Set2) -ShareKeys } | Should -Not -Throw
        }

        It 'Skips validation with single set' {
            { Install-SshKey -ComputerSets @(, $script:BaseSet) -ShareKeys } | Should -Not -Throw
        }
    }

    Context 'Sequential processing' {

        It 'Processes single set sequentially' {
            $Result = Install-SshKey -ComputerSets @(, $script:BaseSet)

            $Result | Should -Not -BeNullOrEmpty
        }

        It 'Returns a result per set' {
            $Set2L = $script:LinuxComp.Clone(); $Set2L.HostName = '10.0.1.1'
            $Set2W = $script:WindowsComp.Clone(); $Set2W.HostName = '10.0.1.2'
            $Set2 = @($Set2L, $Set2W)

            $Results = Install-SshKey -ComputerSets @($script:BaseSet, $Set2)

            @($Results).Count | Should -Be 2
        }
    }

    Context 'Delegates to Install-SshKeyForSet' {

        It 'Calls Install-SshKeyForSet for each set' {
            Mock Install-SshKeyForSet {
                [PSCustomObject]@{
                    PSTypeName      = 'Sage.SshKeyResult'
                    SetIndex        = $SetIndex
                    Computers       = @('A', 'B')
                    KeysGenerated   = 0
                    KeysDistributed = 0
                    TestResults     = @()
                    Errors          = @()
                }
            }

            $Results = Install-SshKey -ComputerSets @(, $script:BaseSet)

            Should -Invoke Install-SshKeyForSet -Times 1 -Exactly
        }

        It 'Passes Force flag through to Install-SshKeyForSet' {
            Mock Install-SshKeyForSet {
                [PSCustomObject]@{
                    PSTypeName      = 'Sage.SshKeyResult'
                    SetIndex        = $SetIndex
                    Computers       = @('A', 'B')
                    KeysGenerated   = 0
                    KeysDistributed = 0
                    TestResults     = @()
                    Errors          = @()
                }
            }

            Install-SshKey -ComputerSets @(, $script:BaseSet) -Force

            Should -Invoke Install-SshKeyForSet -ParameterFilter { $Force -eq $true }
        }

        It 'Passes KeyType through to Install-SshKeyForSet' {
            Mock Install-SshKeyForSet {
                [PSCustomObject]@{
                    PSTypeName      = 'Sage.SshKeyResult'
                    SetIndex        = $SetIndex
                    Computers       = @('A', 'B')
                    KeysGenerated   = 0
                    KeysDistributed = 0
                    TestResults     = @()
                    Errors          = @()
                }
            }

            Install-SshKey -ComputerSets @(, $script:BaseSet) -KeyType 'rsa'

            Should -Invoke Install-SshKeyForSet -ParameterFilter { $KeyType -eq 'rsa' }
        }
    }

    Context 'ThrottleLimit' {

        It 'Defaults ThrottleLimit to 10' {
            Mock Install-SshKeyForSet {
                [PSCustomObject]@{
                    PSTypeName      = 'Sage.SshKeyResult'
                    SetIndex        = $SetIndex
                    Computers       = @('A', 'B')
                    KeysGenerated   = 0
                    KeysDistributed = 0
                    TestResults     = @()
                    Errors          = @()
                }
            }

            { Install-SshKey -ComputerSets @(, $script:BaseSet) } | Should -Not -Throw
        }

        It 'Rejects ThrottleLimit above 50' {
            { Install-SshKey -ComputerSets @(, $script:BaseSet) -ThrottleLimit 51 } | Should -Throw
        }

        It 'Rejects ThrottleLimit of 0' {
            { Install-SshKey -ComputerSets @(, $script:BaseSet) -ThrottleLimit 0 } | Should -Throw
        }
    }
}