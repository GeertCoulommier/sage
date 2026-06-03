#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Test-SshKeyAuth.
.DESCRIPTION
    Verifies SSH key authentication testing logic using mocked ssh command.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Test-SshKeyAuth.ps1')
}

Describe 'Test-SshKeyAuth' -Tag 'Unit' {

    BeforeEach {
        # Default mock: Invoke-SshCommand returns success marker
        Mock Invoke-SshCommand {
            'SSH_KEY_AUTH_OK'
        }
    }

    Context 'When key auth succeeds' {

        It 'Returns true when ssh outputs the success marker' {
            $Result = Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'student'
            $Result | Should -BeTrue
        }

        It 'Returns true with a KeyFilePath specified' {
            $Result = Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'student' -KeyFilePath '/tmp/id_test'
            $Result | Should -BeTrue
        }

        It 'Returns true when output contains the marker among other text' {
            Mock Invoke-SshCommand {
                @('Welcome to Ubuntu', 'SSH_KEY_AUTH_OK')
            }

            $Result = Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'student'
            $Result | Should -BeTrue
        }
    }

    Context 'When key auth fails' {

        It 'Returns false when ssh outputs an error' {
            Mock Invoke-SshCommand {
                'Permission denied (publickey).'
            }

            $Result = Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'student'
            $Result | Should -BeFalse
        }

        It 'Returns false when ssh outputs nothing' {
            Mock Invoke-SshCommand {}

            $Result = Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'student'
            $Result | Should -BeFalse
        }

        It 'Returns false when ssh throws an exception' {
            Mock Invoke-SshCommand { throw 'Connection refused' }

            $Result = Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'student'
            $Result | Should -BeFalse
        }
    }

    Context 'SSH argument construction' {

        It 'Passes BatchMode=yes in the argument list' {
            Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'student'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                ($ArgumentList -join ' ') -match 'BatchMode=yes'
            }
        }

        It 'Passes correct port in the argument list' {
            Test-SshKeyAuth -HostName '10.0.0.1' -Port 2222 -UserName 'student'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                ($ArgumentList -join ' ') -match '2222'
            }
        }

        It 'Passes key file with -i when KeyFilePath is specified' {
            Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'admin' -KeyFilePath '/keys/id_sage'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                ($ArgumentList -join ' ') -match '/keys/id_sage'
            }
        }

        It 'Passes IdentitiesOnly=yes when KeyFilePath is specified' {
            Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'admin' -KeyFilePath '/keys/id_sage'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                ($ArgumentList -join ' ') -match 'IdentitiesOnly=yes'
            }
        }

        It 'Does not pass IdentitiesOnly when KeyFilePath is omitted' {
            Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'admin'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                ($ArgumentList -join ' ') -notmatch 'IdentitiesOnly'
            }
        }

        It 'Does not pass -i when KeyFilePath is omitted' {
            Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'admin'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                $ArgumentList -notcontains '-i'
            }
        }

        It 'Passes the correct user@host format' {
            Test-SshKeyAuth -HostName '192.168.1.5' -Port 22 -UserName 'student'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                ($ArgumentList -join ' ') -match 'student@192\.168\.1\.5'
            }
        }

        It 'Passes StrictHostKeyChecking=no' {
            Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'student'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                ($ArgumentList -join ' ') -match 'StrictHostKeyChecking=no'
            }
        }

        It 'Uses the specified timeout in ConnectTimeout option' {
            Test-SshKeyAuth -HostName '10.0.0.1' -Port 22 -UserName 'student' -TimeoutSeconds 5

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                ($ArgumentList -join ' ') -match 'ConnectTimeout=5'
            }
        }
    }

    Context 'Parameter validation' {

        It 'Requires HostName parameter' {
            { Test-SshKeyAuth -HostName '' -UserName 'student' } | Should -Throw
        }

        It 'Requires UserName parameter' {
            { Test-SshKeyAuth -HostName '10.0.0.1' -UserName '' } | Should -Throw
        }

        It 'Rejects port 0' {
            { Test-SshKeyAuth -HostName '10.0.0.1' -Port 0 -UserName 'student' } | Should -Throw
        }

        It 'Rejects port above 65535' {
            { Test-SshKeyAuth -HostName '10.0.0.1' -Port 70000 -UserName 'student' } | Should -Throw
        }

        It 'Rejects timeout of 0' {
            { Test-SshKeyAuth -HostName '10.0.0.1' -UserName 'student' -TimeoutSeconds 0 } | Should -Throw
        }

        It 'Rejects timeout above 60' {
            { Test-SshKeyAuth -HostName '10.0.0.1' -UserName 'student' -TimeoutSeconds 61 } | Should -Throw
        }

        It 'Defaults port to 22' {
            Test-SshKeyAuth -HostName '10.0.0.1' -UserName 'student'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                $ArgumentList -contains '22'
            }
        }

        It 'Defaults timeout to 10 seconds' {
            Test-SshKeyAuth -HostName '10.0.0.1' -UserName 'student'

            Should -Invoke Invoke-SshCommand -Times 1 -ParameterFilter {
                $ArgumentList -contains 'ConnectTimeout=10'
            }
        }
    }
}
