#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Invoke-Diagnostic function.
.DESCRIPTION
    Tests: TCP port check, SSH session establishment, remote PowerShell version,
    module availability, cascading step skips, and result structure.
.TAGS Unit
#>

BeforeAll {
    $PrivateDir = Join-Path $PSScriptRoot '..\..\Sage\Private'
    $PublicDir = Join-Path $PSScriptRoot '..\..\Sage\Public'

    . (Join-Path $PrivateDir 'Write-Log.ps1')
    . (Join-Path $PrivateDir 'New-RemoteSessionObject.ps1')
    . (Join-Path $PublicDir 'New-RemoteSession.ps1')
    . (Join-Path $PublicDir 'Close-RemoteSession.ps1')
    . (Join-Path $PublicDir 'Invoke-Diagnostic.ps1')

    function New-FakeDiagSession {
        $FakePsSession = New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession'
        [PSCustomObject]@{
            PSTypeName  = 'Sage.RemoteSession'
            TargetName  = 'LinuxVM'
            HostName    = '10.0.0.1'
            Port        = 20022
            UserName    = 'student'
            Platform    = 'Linux'
            Session     = $FakePsSession
            ConnectedAt = [datetime]::Now
            SessionId   = 1
        }
    }
}

Describe 'Invoke-Diagnostic' -Tag 'Unit' {

    BeforeEach {
        Mock Write-Log {}
        Mock Close-RemoteSession {}

        $script:BaseParams = @{
            HostName   = '10.0.0.1'
            Port       = 20022
            UserName   = 'student'
            TargetName = 'LinuxVM'
            Platform   = 'Linux'
        }
    }

    Context 'All steps pass' {
        BeforeEach {
            Mock New-RemoteSession { New-FakeDiagSession }
            Mock Invoke-Command {
                if ($ScriptBlock.ToString() -match 'PSVersionTable') {
                    return '7.5.0'
                }
                if ($ScriptBlock.ToString() -match 'Get-Module') {
                    return @()
                }
                return $null
            }

            $script:Listener = [System.Net.Sockets.TcpListener]::new(
                [System.Net.IPAddress]::Loopback, 0)
            $script:Listener.Start()
            $ListenPort = $script:Listener.LocalEndpoint.Port
            $script:LocalParams = @{
                HostName   = '127.0.0.1'
                Port       = $ListenPort
                UserName   = 'student'
                TargetName = 'LinuxVM'
                Platform   = 'Linux'
            }
        }

        AfterEach {
            $script:Listener.Stop()
        }

        It 'Returns a Sage.DiagnosticResult object' {
            $Result = Invoke-Diagnostic @script:LocalParams
            $Result.PSObject.TypeNames | Should -Contain 'Sage.DiagnosticResult'
        }

        It 'Has correct TargetName' {
            $Result = Invoke-Diagnostic @script:LocalParams
            $Result.TargetName | Should -Be 'LinuxVM'
        }

        It 'Returns 4 steps' {
            $Result = Invoke-Diagnostic @script:LocalParams
            $Result.Steps.Count | Should -Be 4
        }

        It 'Step names match expected sequence' {
            $Result = Invoke-Diagnostic @script:LocalParams
            $Result.Steps[0].Name | Should -Be 'TCP Port Reachability'
            $Result.Steps[1].Name | Should -Be 'SSH Session'
            $Result.Steps[2].Name | Should -Be 'Remote PowerShell Version'
            $Result.Steps[3].Name | Should -Be 'Required Modules'
        }
    }

    Context 'TCP port unreachable' {
        BeforeEach {
            # Open and immediately close a listener to get a known-unused port
            $TmpListener = [System.Net.Sockets.TcpListener]::new(
                [System.Net.IPAddress]::Loopback, 0)
            $TmpListener.Start()
            $ClosedPort = $TmpListener.LocalEndpoint.Port
            $TmpListener.Stop()

            $script:UnreachableParams = @{
                HostName   = '127.0.0.1'
                Port       = $ClosedPort
                UserName   = 'student'
                TargetName = 'Unreachable'
                Platform   = 'Linux'
            }
            Mock New-RemoteSession { New-FakeDiagSession }
        }

        It 'TCP step fails and subsequent steps are skipped' {
            $Result = Invoke-Diagnostic @script:UnreachableParams
            $Result.Steps[0].Passed | Should -BeFalse
            $Result.Steps[1].Message | Should -BeLike '*Skipped*'
            $Result.Steps[2].Message | Should -BeLike '*Skipped*'
            $Result.Passed | Should -BeFalse
        }
    }

    Context 'SSH session failure' {
        BeforeEach {
            # TCP succeeds (we'll use localhost on a known port)
            # But SSH fails
            Mock New-RemoteSession { throw 'SSH handshake failed' }
        }

        It 'SSH step fails; remote PS and module steps are skipped' {
            # Use localhost:$port where port is likely open (or skip TCP with a mock)
            # For deterministic tests, use a port we know is open
            # Use a local TCP listener approach:
            $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $ListenPort = $Listener.LocalEndpoint.Port
            try {
                $Params = @{
                    HostName   = '127.0.0.1'
                    Port       = $ListenPort
                    UserName   = 'student'
                    TargetName = 'TestVM'
                    Platform   = 'Linux'
                }
                $Result = Invoke-Diagnostic @Params
                $Result.Steps[0].Passed | Should -BeTrue
                $Result.Steps[1].Passed | Should -BeFalse
                $Result.Steps[2].Message | Should -BeLike '*Skipped*'
                $Result.Passed | Should -BeFalse
            }
            finally {
                $Listener.Stop()
            }
        }
    }

    Context 'Module check — missing modules' {
        BeforeEach {
            Mock New-RemoteSession { New-FakeDiagSession }
            Mock Invoke-Command {
                if ($ScriptBlock.ToString() -match 'PSVersionTable') {
                    return '7.5.0'
                }
                if ($ScriptBlock.ToString() -match 'Get-Module') {
                    return @('Pester')
                }
                return $null
            }
        }

        It 'Reports missing modules when they are not installed' {
            $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $ListenPort = $Listener.LocalEndpoint.Port
            try {
                $Params = @{
                    HostName     = '127.0.0.1'
                    Port         = $ListenPort
                    UserName     = 'student'
                    TargetName   = 'TestVM'
                    Platform     = 'Linux'
                    Dependencies = @{ Modules = @('Pester') }
                }
                $Result = Invoke-Diagnostic @Params
                $Result.Steps[3].Passed | Should -BeFalse
                $Result.Steps[3].Message | Should -BeLike '*Missing*Pester*'
            }
            finally {
                $Listener.Stop()
            }
        }
    }

    Context 'No dependencies specified' {
        BeforeEach {
            Mock New-RemoteSession { New-FakeDiagSession }
            Mock Invoke-Command {
                if ($ScriptBlock.ToString() -match 'PSVersionTable') {
                    return '7.5.0'
                }
                return $null
            }
        }

        It 'Module step passes when no modules required' {
            $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $ListenPort = $Listener.LocalEndpoint.Port
            try {
                $Params = @{
                    HostName     = '127.0.0.1'
                    Port         = $ListenPort
                    UserName     = 'student'
                    TargetName   = 'TestVM'
                    Platform     = 'Linux'
                    Dependencies = @{ Modules = @() }
                }
                $Result = Invoke-Diagnostic @Params
                $Result.Steps[3].Passed | Should -BeTrue
                $Result.Steps[3].Message | Should -BeLike '*No required modules*'
            }
            finally {
                $Listener.Stop()
            }
        }
    }

    Context 'Result includes Timestamp' {
        BeforeEach {
            Mock New-RemoteSession { New-FakeDiagSession }
            Mock Invoke-Command { return '7.5.0' }

            $script:TsListener = [System.Net.Sockets.TcpListener]::new(
                [System.Net.IPAddress]::Loopback, 0)
            $script:TsListener.Start()
            $ListenPort = $script:TsListener.LocalEndpoint.Port
            $script:TsParams = @{
                HostName   = '127.0.0.1'
                Port       = $ListenPort
                UserName   = 'student'
                TargetName = 'LinuxVM'
                Platform   = 'Linux'
            }
        }

        AfterEach {
            $script:TsListener.Stop()
        }

        It 'Has a Timestamp within the last minute' {
            $Result = Invoke-Diagnostic @script:TsParams
            $Result.Timestamp | Should -BeOfType [datetime]
            ($Result.Timestamp - [datetime]::Now).TotalMinutes |
                Should -BeLessThan 1
        }
    }

    Context 'Session is cleaned up after diagnostics' {
        BeforeEach {
            Mock New-RemoteSession { New-FakeDiagSession }
            Mock Invoke-Command { return '7.5.0' }
        }

        It 'Calls Close-RemoteSession after completing checks' {
            $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $ListenPort = $Listener.LocalEndpoint.Port
            try {
                $Params = @{
                    HostName   = '127.0.0.1'
                    Port       = $ListenPort
                    UserName   = 'student'
                    TargetName = 'TestVM'
                    Platform   = 'Linux'
                }
                Invoke-Diagnostic @Params
                Should -Invoke Close-RemoteSession -Times 1
            }
            finally {
                $Listener.Stop()
            }
        }
    }

    Context 'Close-RemoteSession failure is logged as warning' {
        BeforeEach {
            Mock New-RemoteSession { New-FakeDiagSession }
            Mock Invoke-Command { return '7.5.0' }
            Mock Close-RemoteSession { throw 'session already closed' }
        }

        It 'Does not throw when Close-RemoteSession fails' {
            $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $ListenPort = $Listener.LocalEndpoint.Port
            try {
                $Params = @{
                    HostName   = '127.0.0.1'
                    Port       = $ListenPort
                    UserName   = 'student'
                    TargetName = 'TestVM'
                    Platform   = 'Linux'
                }
                { Invoke-Diagnostic @Params } | Should -Not -Throw
                Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'Failed to close' }
            }
            finally {
                $Listener.Stop()
            }
        }
    }

    Context 'Remote PowerShell version check failure' {
        BeforeEach {
            Mock New-RemoteSession { New-FakeDiagSession }
            Mock Invoke-Command { throw 'permission denied' }
        }

        It 'PS version step fails and overall result is FAIL' {
            $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $ListenPort = $Listener.LocalEndpoint.Port
            try {
                $Params = @{
                    HostName   = '127.0.0.1'
                    Port       = $ListenPort
                    UserName   = 'student'
                    TargetName = 'TestVM'
                    Platform   = 'Linux'
                }
                $Result = Invoke-Diagnostic @Params
                $Result.Steps[2].Passed | Should -BeFalse
                $Result.Steps[2].Message | Should -BeLike '*Failed to query*'
                $Result.Passed | Should -BeFalse
            }
            finally {
                $Listener.Stop()
            }
        }
    }

    Context 'Module check — all modules present' {
        BeforeEach {
            Mock New-RemoteSession { New-FakeDiagSession }
            Mock Invoke-Command {
                if ($ScriptBlock.ToString() -match 'PSVersionTable') {
                    return '7.5.0'
                }
                if ($ScriptBlock.ToString() -match 'Get-Module') {
                    return @()  # No missing modules
                }
                return $null
            }
        }

        It 'Module step passes when all required modules are installed' {
            $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $ListenPort = $Listener.LocalEndpoint.Port
            try {
                $Params = @{
                    HostName     = '127.0.0.1'
                    Port         = $ListenPort
                    UserName     = 'student'
                    TargetName   = 'TestVM'
                    Platform     = 'Linux'
                    Dependencies = @{ Modules = @('Pester') }
                }
                $Result = Invoke-Diagnostic @Params
                $Result.Steps[3].Passed | Should -BeTrue
                $Result.Steps[3].Message | Should -BeLike '*All required modules*'
            }
            finally {
                $Listener.Stop()
            }
        }
    }

    Context 'Module check failure' {
        BeforeEach {
            Mock New-RemoteSession { New-FakeDiagSession }
            Mock Invoke-Command {
                if ($ScriptBlock.ToString() -match 'PSVersionTable') {
                    return '7.5.0'
                }
                if ($ScriptBlock.ToString() -match 'Get-Module') {
                    throw 'module check error'
                }
                return $null
            }
        }

        It 'Module step fails when Invoke-Command throws' {
            $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $ListenPort = $Listener.LocalEndpoint.Port
            try {
                $Params = @{
                    HostName     = '127.0.0.1'
                    Port         = $ListenPort
                    UserName     = 'student'
                    TargetName   = 'TestVM'
                    Platform     = 'Linux'
                    Dependencies = @{ Modules = @('Pester') }
                }
                $Result = Invoke-Diagnostic @Params
                $Result.Steps[3].Passed | Should -BeFalse
                $Result.Steps[3].Message | Should -BeLike '*Module check failed*'
            }
            finally {
                $Listener.Stop()
            }
        }
    }
}
