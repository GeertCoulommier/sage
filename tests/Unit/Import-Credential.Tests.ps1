#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Import-Credential function.
.DESCRIPTION
    Tests: successful PSCredential retrieval, SecureString wrapping,
    unexpected secret type handling, -AllowPrompt fallback, missing
    SecretManagement module, and parameter validation.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Public\Import-Credential.ps1'
    $WriteLogPath = Join-Path $PSScriptRoot '..\..\Sage\Private\Write-Log.ps1'
    . $WriteLogPath
    . $Sut

    # Stub for Microsoft.PowerShell.SecretManagement — not available on Linux CI.
    # Pester 5 requires a command to exist before it can be mocked.
    function Get-Secret { throw 'SecretManagement stub — should be mocked in each test' }
}

Describe 'Import-Credential' -Tag 'Unit' {

    BeforeEach {
        Mock Write-Log {}
    }

    Context 'Vault returns PSCredential' {
        BeforeEach {
            $script:FakeCred = [System.Management.Automation.PSCredential]::new(
                'student',
                (ConvertTo-SecureString 'P@ss1' -AsPlainText -Force)
            )
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Get-Secret' }
            Mock Get-Secret { return $script:FakeCred }
        }

        It 'Returns the PSCredential from the vault' {
            $Result = Import-Credential -Name 'LinuxStudentPassword'
            $Result | Should -BeOfType [System.Management.Automation.PSCredential]
            $Result.UserName | Should -Be 'student'
        }

        It 'Logs the retrieval' {
            Import-Credential -Name 'LinuxStudentPassword'
            Should -Invoke Write-Log -ParameterFilter { $Message -match 'retrieved' }
        }
    }

    Context 'Vault returns SecureString—wraps as PSCredential' {
        BeforeEach {
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Get-Secret' }
            Mock Get-Secret { return (ConvertTo-SecureString 'P@ss2' -AsPlainText -Force) }
        }

        It 'Returns a PSCredential with Name as UserName' {
            $Result = Import-Credential -Name 'AdminPwd'
            $Result | Should -BeOfType [System.Management.Automation.PSCredential]
            $Result.UserName | Should -Be 'AdminPwd'
        }
    }

    Context 'SecretManagement not installed—no AllowPrompt' {
        BeforeEach {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'Get-Secret' }
        }

        It 'Throws a terminating error' {
            { Import-Credential -Name 'Missing' -ErrorAction Stop } | Should -Throw '*SecretManagement*'
        }
    }

    Context 'Vault retrieval fails—no AllowPrompt' {
        BeforeEach {
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Get-Secret' }
            Mock Get-Secret { throw 'secret not found' }
        }

        It 'Throws a terminating error referencing the vault failure' {
            { Import-Credential -Name 'Bad' -ErrorAction Stop } | Should -Throw '*Failed to retrieve*'
        }
    }

    Context 'AllowPrompt fallback—SecretManagement missing' {
        BeforeEach {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'Get-Secret' }
            $DummyPw = 'pw'
            $script:PromptCred = [System.Management.Automation.PSCredential]::new(
                'fallback',
                (ConvertTo-SecureString $DummyPw -AsPlainText -Force)
            )
            Mock Get-Credential { return $script:PromptCred }
        }

        It 'Falls back to Get-Credential prompt' {
            $Result = Import-Credential -Name 'Test' -AllowPrompt
            $Result.UserName | Should -Be 'fallback'
            Should -Invoke Get-Credential -Times 1
        }
    }

    Context 'AllowPrompt fallback—vault error' {
        BeforeEach {
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Get-Secret' }
            Mock Get-Secret { throw 'vault locked' }
            $DummyPw = 'pw'
            $script:PromptCred = [System.Management.Automation.PSCredential]::new(
                'prompted',
                (ConvertTo-SecureString $DummyPw -AsPlainText -Force)
            )
            Mock Get-Credential { return $script:PromptCred }
        }

        It 'Falls back to Get-Credential and logs a warning' {
            $Result = Import-Credential -Name 'Locked' -AllowPrompt
            $Result.UserName | Should -Be 'prompted'
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warning' }
        }
    }

    Context 'Vault returns unexpected type—falls back to prompt' {
        BeforeEach {
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Get-Secret' }
            Mock Get-Secret { return 'plain-string-not-credential' }
            $DummyPw = 'pw'
            $script:PromptCred = [System.Management.Automation.PSCredential]::new(
                'fallback-user',
                (ConvertTo-SecureString $DummyPw -AsPlainText -Force)
            )
            Mock Get-Credential { return $script:PromptCred }
        }

        It 'Logs a warning about the unexpected type and falls back' {
            $Result = Import-Credential -Name 'Unexpected' -AllowPrompt
            $Result.UserName | Should -Be 'fallback-user'
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'Unexpected secret type' }
        }
    }

    Context 'Parameter validation' {
        It 'Throws when Name is empty' {
            { Import-Credential -Name '' } | Should -Throw
        }
    }
}
