#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Close-RemoteSession function.
.DESCRIPTION
    Tests: successful session closure, idempotent handling of already-closed
    sessions, error handling when Remove-PSSession fails, ShouldProcess
    support, and pipeline input.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Public\Close-RemoteSession.ps1'
    $WriteLogPath = Join-Path $PSScriptRoot '..\..\Sage\Private\Write-Log.ps1'
    . $WriteLogPath
    . $Sut
}

Describe 'Close-RemoteSession' -Tag 'Unit' {

    BeforeEach {
        # Build a fake Sage.RemoteSession wrapping a properly-typed mock PSSession.
        # State returns $null (Runspace is null) which satisfies ($null -ne 'Closed') = $true.
        $FakePsSession = New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession'
        $script:MockSession = [PSCustomObject]@{
            PSTypeName = 'Sage.RemoteSession'
            TargetName = 'LinuxVM'
            HostName   = '10.0.0.1'
            Port       = 20022
            Session    = $FakePsSession
        }

        Mock Write-Log {}
        Mock Remove-PSSession {}
    }

    Context 'Successful session closure' {
        It 'Calls Remove-PSSession for an opened session' {
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Remove-PSSession -Times 1
        }

        It 'Logs closure via Write-Log' {
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Write-Log -Times 1 -ParameterFilter { $Level -eq 'Info' }
        }
    }

    Context 'Idempotent—already closed session' {
        It 'Skips Remove-PSSession when session state is Closed' {
            $script:MockSession.Session = [PSCustomObject]@{ State = 'Closed' }
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Remove-PSSession -Times 0
        }

        It 'Skips Remove-PSSession when Session is null' {
            $script:MockSession.Session = $null
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Remove-PSSession -Times 0
        }
    }

    Context 'Error handling' {
        It 'Logs a warning when Remove-PSSession throws' {
            Mock Remove-PSSession { throw 'connection lost' }
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warning' }
        }

        It 'Does not throw when Remove-PSSession fails' {
            Mock Remove-PSSession { throw 'connection lost' }
            { Close-RemoteSession -Session $script:MockSession -Confirm:$false } | Should -Not -Throw
        }
    }

    Context 'WhatIf support' {
        It 'Does not call Remove-PSSession with -WhatIf' {
            Close-RemoteSession -Session $script:MockSession -WhatIf
            Should -Invoke Remove-PSSession -Times 0
        }
    }

    Context 'Multiple sessions' {
        It 'Closes each session in the array' {
            $Session2 = [PSCustomObject]@{
                PSTypeName = 'Sage.RemoteSession'
                TargetName = 'WinSrv1'
                HostName   = '10.0.0.2'
                Port       = 30022
                Session    = (New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession')
            }
            Close-RemoteSession -Session @($script:MockSession, $Session2) -Confirm:$false
            Should -Invoke Remove-PSSession -Times 2
        }
    }

    Context 'Temp file cleanup' {
        BeforeEach {
            Mock Invoke-Command {}
        }

        It 'Calls Invoke-Command to clean up temp files before closing' {
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Invoke-Command -Times 1
        }

        It 'Logs verbose message on successful cleanup' {
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Verbose' -and $Message -match 'Cleaned up temp files' }
        }

        It 'Logs a warning when cleanup fails but does not throw' {
            Mock Invoke-Command { throw 'network error' }
            { Close-RemoteSession -Session $script:MockSession -Confirm:$false } | Should -Not -Throw
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'Failed to clean up temp files' }
        }

        It 'Skips cleanup when session is already closed' {
            $script:MockSession.Session = [PSCustomObject]@{ State = 'Closed' }
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Invoke-Command -Times 0
        }

        It 'Skips cleanup when session is null' {
            $script:MockSession.Session = $null
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Invoke-Command -Times 0
        }

        It 'Still closes the PSSession after cleanup completes' {
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Remove-PSSession -Times 1
        }

        It 'Still closes the PSSession even when cleanup throws' {
            Mock Invoke-Command { throw 'cleanup failed' }
            Close-RemoteSession -Session $script:MockSession -Confirm:$false
            Should -Invoke Remove-PSSession -Times 1
        }
    }
}
