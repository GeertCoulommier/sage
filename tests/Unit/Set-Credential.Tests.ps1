#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Set-Credential function.
.DESCRIPTION
    Tests: successful storage, auto-registration of vault, missing
    SecretManagement module, missing SecretStore, WhatIf support,
    and parameter validation.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Public\Set-Credential.ps1'
    $WriteLogPath = Join-Path $PSScriptRoot '..\..\Sage\Private\Write-Log.ps1'
    . $WriteLogPath
    . $Sut

    # Stubs for Microsoft.PowerShell.SecretManagement — not available on Linux CI.
    # Pester 5 requires a command to exist before it can be mocked, AND parameter
    # names must be declared so that Should -Invoke ParameterFilter expressions can
    # bind and evaluate correctly.
    function Get-SecretVault {
        [CmdletBinding()] param([string] $Name)
        throw "SecretManagement stub — should be mocked in each test (Name=$Name)"
    }
    function Set-Secret {
        [CmdletBinding()] param([string] $Name, $Secret, [string] $Vault)
        throw "SecretManagement stub — should be mocked in each test (Name=$Name, Vault=$Vault, Secret=$Secret)"
    }
    function Register-SecretVault {
        [CmdletBinding()] param([string] $Name, [string] $ModuleName)
        throw "SecretManagement stub — should be mocked in each test (Name=$Name, ModuleName=$ModuleName)"
    }
}

Describe 'Set-Credential' -Tag 'Unit' {

    BeforeEach {
        $script:TestCred = [System.Management.Automation.PSCredential]::new(
            'student',
            (ConvertTo-SecureString 'P@ss1' -AsPlainText -Force)
        )
        Mock Write-Log {}
    }

    Context 'SecretManagement not installed' {
        BeforeEach {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'Set-Secret' }
        }

        It 'Throws a terminating error' {
            { Set-Credential -Name 'Test' -Credential $script:TestCred -ErrorAction Stop } | Should -Throw '*SecretManagement*'
        }
    }

    Context 'Successful storage—vault exists' {
        BeforeEach {
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Set-Secret' }
            Mock Get-SecretVault { return [PSCustomObject]@{ Name = 'SageVault' } }
            Mock Set-Secret {}
        }

        It 'Calls Set-Secret with correct parameters' {
            Set-Credential -Name 'AdminPwd' -Credential $script:TestCred
            Should -Invoke Set-Secret -Times 1 -ParameterFilter { $Name -eq 'AdminPwd' -and $Vault -eq 'SageVault' }
        }

        It 'Logs the success' {
            Set-Credential -Name 'AdminPwd' -Credential $script:TestCred
            Should -Invoke Write-Log -ParameterFilter { $Message -match 'stored' }
        }
    }

    Context 'Auto-register vault when missing' {
        BeforeEach {
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Set-Secret' }
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Register-SecretVault' }
            Mock Get-SecretVault { return $null }
            Mock Get-Module { return [PSCustomObject]@{ Name = 'Microsoft.PowerShell.SecretStore' } }
            Mock Register-SecretVault {}
            Mock Set-Secret {}
        }

        It 'Registers the vault before storing' {
            Set-Credential -Name 'Test' -Credential $script:TestCred
            Should -Invoke Register-SecretVault -Times 1
            Should -Invoke Set-Secret -Times 1
        }
    }

    Context 'Vault missing and SecretStore not available' {
        BeforeEach {
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Set-Secret' }
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Register-SecretVault' }
            Mock Get-SecretVault { return $null }
            Mock Get-Module { return $null }
        }

        It 'Throws a terminating error about SecretStore' {
            { Set-Credential -Name 'Test' -Credential $script:TestCred -ErrorAction Stop } | Should -Throw '*SecretStore*'
        }
    }

    Context 'WhatIf support' {
        BeforeEach {
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Set-Secret' }
            Mock Get-SecretVault { return [PSCustomObject]@{ Name = 'SageVault' } }
            Mock Set-Secret {}
        }

        It 'Does not call Set-Secret with -WhatIf' {
            Set-Credential -Name 'Test' -Credential $script:TestCred -WhatIf
            Should -Invoke Set-Secret -Times 0
        }
    }

    Context 'Parameter validation' {
        It 'Throws when Name is empty' {
            { Set-Credential -Name '' -Credential $script:TestCred } | Should -Throw
        }
    }
}
