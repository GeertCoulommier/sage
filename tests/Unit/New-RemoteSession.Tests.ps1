#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the New-RemoteSession function.
.DESCRIPTION
    Tests: successful connection, retry logic, password-without-key rejection,
    returned wrapper object type, and MaxRetries exhaustion.
.TAGS Unit
#>

BeforeAll {
    $WriteLogPath = Join-Path $PSScriptRoot '..\..\Sage\Private\Write-Log.ps1'
    $SessionObjPath = Join-Path $PSScriptRoot '..\..\Sage\Private\New-RemoteSessionObject.ps1'
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Public\New-RemoteSession.ps1'
    . $WriteLogPath
    . $SessionObjPath
    . $Sut
}

Describe 'New-RemoteSession' -Tag 'Unit' {

    BeforeEach {
        Mock Write-Log {}
        Mock Start-Sleep {}

        # Default: New-PSSession returns a properly-typed mock PSSession
        $script:FakePsSession = New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession'
        $script:FakePsSession | Add-Member -MemberType NoteProperty -Name Id -Value 7 -Force
        $script:FakePsSession | Add-Member -MemberType NoteProperty -Name Name -Value 'FakeSSH' -Force

        Mock New-PSSession { return $script:FakePsSession }

        $script:BaseParams = @{
            HostName   = '10.0.0.1'
            Port       = 20022
            UserName   = 'student'
            TargetName = 'LinuxVM'
            Platform   = 'Linux'
        }
    }

    Context 'Successful connection on first attempt' {
        It 'Returns a Sage.RemoteSession object' {
            $Result = New-RemoteSession @script:BaseParams
            $Result.PSObject.TypeNames | Should -Contain 'Sage.RemoteSession'
        }

        It 'Populates TargetName and HostName from parameters' {
            $Result = New-RemoteSession @script:BaseParams
            $Result.TargetName | Should -Be 'LinuxVM'
            $Result.HostName | Should -Be '10.0.0.1'
        }

        It 'Calls New-PSSession exactly once' {
            New-RemoteSession @script:BaseParams
            Should -Invoke New-PSSession -Times 1
        }
    }

    Context 'Retry logic—succeeds on second attempt' {
        BeforeEach {
            $script:Attempt = 0
            Mock New-PSSession {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw 'transient failure' }
                return $script:FakePsSession
            }
        }

        It 'Returns a session after retrying' {
            $Result = New-RemoteSession @script:BaseParams
            $Result.PSObject.TypeNames | Should -Contain 'Sage.RemoteSession'
        }

        It 'Called New-PSSession twice' {
            New-RemoteSession @script:BaseParams
            Should -Invoke New-PSSession -Times 2
        }

        It 'Called Start-Sleep between retries' {
            New-RemoteSession @script:BaseParams
            Should -Invoke Start-Sleep -Times 1
        }
    }

    Context 'All retries exhausted' {
        BeforeEach {
            Mock New-PSSession { throw 'connection refused' }
        }

        It 'Throws a terminating error after MaxRetries' {
            { New-RemoteSession @script:BaseParams -MaxRetries 2 -ErrorAction Stop } | Should -Throw '*Failed to connect*'
        }
    }

    Context 'Credential accepted without KeyFilePath' {
        It 'Does not throw when -Credential is supplied without -KeyFilePath' {
            # SSH transport does not support -Credential; the parameter is accepted
            # for audit purposes only and must not cause a validation error.
            $Cred = [System.Management.Automation.PSCredential]::new(
                'user',
                (ConvertTo-SecureString 'pw' -AsPlainText -Force)
            )
            { New-RemoteSession @script:BaseParams -Credential $Cred -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context 'KeyFilePath is passed through' {
        It 'Includes KeyFilePath in New-PSSession call' {
            New-RemoteSession @script:BaseParams -KeyFilePath '/home/user/.ssh/id_rsa'
            Should -Invoke New-PSSession -Times 1 -ParameterFilter { $KeyFilePath -eq '/home/user/.ssh/id_rsa' }
        }
    }

    Context 'VaultEntryName forwarded to wrapper' {
        It 'Sets VaultEntryName on the returned object' {
            $Result = New-RemoteSession @script:BaseParams -VaultEntryName 'LinuxStudentPassword'
            $Result.VaultEntryName | Should -Be 'LinuxStudentPassword'
        }
    }

    Context 'SSH keepalive defaults' {
        It 'Passes ServerAliveInterval and ServerAliveCountMax to New-PSSession -Options' {
            New-RemoteSession @script:BaseParams
            Should -Invoke New-PSSession -Times 1 -ParameterFilter {
                $Options -and
                $Options['ServerAliveInterval'] -eq '15' -and
                $Options['ServerAliveCountMax'] -eq '3'
            }
        }

        It 'Allows caller-supplied SshOptions to override defaults' {
            $CustomOptions = @{
                ServerAliveInterval = '30'
            }
            New-RemoteSession @script:BaseParams -SshOptions $CustomOptions
            Should -Invoke New-PSSession -Times 1 -ParameterFilter {
                $Options -and
                $Options['ServerAliveInterval'] -eq '30' -and
                $Options['ServerAliveCountMax'] -eq '3'
            }
        }
    }
}
