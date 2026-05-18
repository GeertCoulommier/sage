#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the New-RemoteSessionObject factory function.
.DESCRIPTION
    Tests: PSTypeName stamping, all metadata properties, ConnectedAt
    timestamp, SessionId extraction, optional VaultEntryName, and
    parameter validation.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\New-RemoteSessionObject.ps1'
    . $Sut
}

Describe 'New-RemoteSessionObject' -Tag 'Unit' {

    BeforeAll {
        # Create a properly-typed mock PSSession. New-MockObject creates a Castle proxy
        # that satisfies [PSSession] type constraints. Add-Member -Force overrides
        # native CLR properties (Id, Name) but not ETS ScriptProperties (State).
        $script:FakeSession = New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession'
        $script:FakeSession | Add-Member -MemberType NoteProperty -Name Id -Value 42 -Force
        $script:FakeSession | Add-Member -MemberType NoteProperty -Name Name -Value 'FakeSession' -Force
    }

    Context 'Output type and PSTypeName' {
        BeforeAll {
            $Params = @{
                TargetName = 'LinuxVM'
                HostName   = '10.0.0.1'
                Port       = 20022
                UserName   = 'student'
                Platform   = 'Linux'
                Session    = $script:FakeSession
            }
            $script:Result = New-RemoteSessionObject @Params
        }

        It 'Returns exactly one object' {
            @($script:Result).Count | Should -Be 1
        }

        It 'Has PSTypeName Sage.RemoteSession' {
            $script:Result.PSObject.TypeNames | Should -Contain 'Sage.RemoteSession'
        }
    }

    Context 'Metadata properties' {
        BeforeAll {
            $Params = @{
                TargetName     = 'WinSrv1'
                HostName       = 'srv.example.com'
                Port           = 30022
                UserName       = 'administrator'
                Platform       = 'Windows'
                Session        = $script:FakeSession
                VaultEntryName = 'AdminPassword'
            }
            $script:Result = New-RemoteSessionObject @Params
        }

        It 'TargetName matches input' {
            $script:Result.TargetName | Should -Be 'WinSrv1'
        }

        It 'HostName matches input' {
            $script:Result.HostName | Should -Be 'srv.example.com'
        }

        It 'Port matches input' {
            $script:Result.Port | Should -Be 30022
        }

        It 'UserName matches input' {
            $script:Result.UserName | Should -Be 'administrator'
        }

        It 'Platform matches input' {
            $script:Result.Platform | Should -Be 'Windows'
        }

        It 'Session property is the supplied PSSession' {
            $script:Result.Session | Should -Be $script:FakeSession
        }

        It 'VaultEntryName matches input' {
            $script:Result.VaultEntryName | Should -Be 'AdminPassword'
        }

        It 'SessionId is extracted from the Session object' {
            $script:Result.SessionId | Should -Be 42
        }
    }

    Context 'ConnectedAt timestamp' {
        BeforeAll {
            $script:Before = [datetime]::Now
            $Params = @{
                TargetName = 'LinuxVM'
                HostName   = '10.0.0.1'
                Port       = 20022
                UserName   = 'student'
                Platform   = 'Linux'
                Session    = $script:FakeSession
            }
            $script:Result = New-RemoteSessionObject @Params
            $script:After = [datetime]::Now
        }

        It 'ConnectedAt is a [datetime]' {
            $script:Result.ConnectedAt | Should -BeOfType [datetime]
        }

        It 'ConnectedAt is close to now' {
            $script:Result.ConnectedAt | Should -BeGreaterOrEqual $script:Before
            $script:Result.ConnectedAt | Should -BeLessOrEqual $script:After
        }
    }

    Context 'VaultEntryName is optional' {
        BeforeAll {
            $Params = @{
                TargetName = 'LinuxVM'
                HostName   = '10.0.0.1'
                Port       = 20022
                UserName   = 'student'
                Platform   = 'Linux'
                Session    = $script:FakeSession
            }
            $script:Result = New-RemoteSessionObject @Params
        }

        It 'VaultEntryName is null when not provided' {
            $script:Result.VaultEntryName | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {
        It 'Throws when TargetName is empty' {
            { New-RemoteSessionObject -TargetName '' -HostName '10.0.0.1' -Port 22 -UserName 'u' -Platform 'Linux' -Session $script:FakeSession } | Should -Throw
        }

        It 'Throws when Port is 0' {
            { New-RemoteSessionObject -TargetName 'X' -HostName '10.0.0.1' -Port 0 -UserName 'u' -Platform 'Linux' -Session $script:FakeSession } | Should -Throw
        }

        It 'Throws when Platform is invalid' {
            { New-RemoteSessionObject -TargetName 'X' -HostName '10.0.0.1' -Port 22 -UserName 'u' -Platform 'MacOS' -Session $script:FakeSession } | Should -Throw
        }
    }
}
