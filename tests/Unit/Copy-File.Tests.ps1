#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Copy-File function.
.DESCRIPTION
    Tests: successful file copy, remote directory creation, and parameter
    validation for non-existent local files.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\Copy-File.ps1'
    . $Sut
}

Describe 'Copy-File' -Tag 'Unit' {

    BeforeEach {
        $script:FakeSession = New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession'
        $script:FakeSession | Add-Member -MemberType NoteProperty -Name Id -Value 1 -Force

        Mock Invoke-Command {}
        Mock Copy-Item {}
    }

    Context 'Successful copy' {
        BeforeAll {
            $script:TmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "sage-copyfile-test-$([guid]::NewGuid().ToString('N').Substring(0,8)).ps1"
            'fake-content' | Set-Content -Path $script:TmpFile
        }
        AfterAll {
            Remove-Item $script:TmpFile -Force -ErrorAction SilentlyContinue
        }

        It 'Calls Invoke-Command to create the remote directory' {
            Copy-File -Session $script:FakeSession -LocalPath $script:TmpFile -RemotePath '/tmp/sage-collectors/test.ps1'
            Should -Invoke Invoke-Command -Times 1
        }

        It 'Calls Copy-Item with -ToSession' {
            Copy-File -Session $script:FakeSession -LocalPath $script:TmpFile -RemotePath '/tmp/sage-collectors/test.ps1'
            Should -Invoke Copy-Item -Times 1
        }
    }

    Context 'Parameter validation' {
        It 'Throws when LocalPath does not exist' {
            { Copy-File -Session $script:FakeSession -LocalPath 'C:\nonexistent\file.ps1' -RemotePath '/tmp/x.ps1' } | Should -Throw
        }

        It 'Throws when RemotePath is empty' {
            { Copy-File -Session $script:FakeSession -LocalPath $PSCommandPath -RemotePath '' } | Should -Throw
        }
    }

    Context 'RemotePath with no parent directory' {
        BeforeAll {
            $script:TmpFile2 = Join-Path ([System.IO.Path]::GetTempPath()) "sage-copyfile-nodir-$([guid]::NewGuid().ToString('N').Substring(0,8)).ps1"
            'content' | Set-Content -Path $script:TmpFile2
        }
        AfterAll {
            Remove-Item $script:TmpFile2 -Force -ErrorAction SilentlyContinue
        }

        It 'Skips Invoke-Command when RemotePath has no parent' {
            Copy-File -Session $script:FakeSession -LocalPath $script:TmpFile2 -RemotePath 'justfile.ps1'
            Should -Invoke Invoke-Command -Times 0
            Should -Invoke Copy-Item -Times 1
        }
    }
}
