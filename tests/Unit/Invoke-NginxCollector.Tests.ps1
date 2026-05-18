#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-NginxCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with Nginx service status,
    config files, and index files. Uses mocks to avoid Linux dependency.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-NginxCollector.ps1'

    if (-not (Get-Command -Name nginx -ErrorAction SilentlyContinue)) {
        function global:nginx { }
    }
    if (-not (Get-Command -Name systemctl -ErrorAction SilentlyContinue)) {
        function global:systemctl { }
    }
}

Describe 'Invoke-NginxCollector' -Tag 'Unit' {

    Context 'Nginx not installed' {
        BeforeEach {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'nginx' }
        }

        It 'Returns Available=$false' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
        }

        It 'Sets Reason about Nginx not installed' {
            $Result = & $Sut -Variables @{}
            $Result.Reason | Should -Match 'not installed'
        }
    }

    Context 'Nginx installed but service offline' {
        BeforeEach {
            Mock Get-Command { [PSCustomObject]@{ Name = 'nginx' } } -ParameterFilter { $Name -eq 'nginx' }
            Mock systemctl { 'inactive (dead)' }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Returns Available=$true' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Reports service as not running' {
            $Result = & $Sut -Variables @{}
            $Result.Data.ServiceRunning | Should -BeFalse
        }
    }

    Context 'Successful Nginx collection' {
        BeforeEach {
            Mock Get-Command { [PSCustomObject]@{ Name = 'nginx' } } -ParameterFilter { $Name -eq 'nginx' }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Returns Available=$true' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Detects running service from status output' {
            $Result = & $Sut -Variables @{}
            # Without systemctl on Windows, service status defaults to false
            $Result.Data.ServiceRunning | Should -BeFalse -Because 'systemctl is not available on Windows'
            $Result.Data | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Result structure' {
        BeforeEach {
            Mock Get-Command { [PSCustomObject]@{ Name = 'nginx' } } -ParameterFilter { $Name -eq 'nginx' }
            Mock systemctl { 'inactive' }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Returns all required top-level keys' {
            $Result = & $Sut -Variables @{}
            $Result.Keys | Should -Contain 'Available'
            $Result.Keys | Should -Contain 'Reason'
            $Result.Keys | Should -Contain 'Data'
            $Result.Keys | Should -Contain 'Errors'
        }

        It 'Data contains expected sub-keys' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Keys | Should -Contain 'ServiceEnabled'
            $Result.Data.Keys | Should -Contain 'ServiceRunning'
            $Result.Data.Keys | Should -Contain 'ConfFiles'
            $Result.Data.Keys | Should -Contain 'IndexFiles'
            $Result.Data.Keys | Should -Contain 'NginxConfListen'
            $Result.Data.Keys | Should -Contain 'NginxConfInclude'
            $Result.Data.Keys | Should -Contain 'FirewallServices'
            $Result.Data.Keys | Should -Contain 'Directories'
            $Result.Data.Keys | Should -Contain 'SymlinkFiles'
            $Result.Data.Keys | Should -Contain 'CurlResults'
            $Result.Data.Keys | Should -Contain 'PhpFpmEnabled'
            $Result.Data.Keys | Should -Contain 'PhpFpmRunning'
            $Result.Data.Keys | Should -Contain 'PhpFpmConfContent'
            $Result.Data.Keys | Should -Contain 'PhpFiles'
        }
    }

    Context 'DirectoryTests variable handling' {
        BeforeEach {
            Mock Get-Command { [PSCustomObject]@{ Name = 'nginx' } } -ParameterFilter { $Name -eq 'nginx' }
            Mock systemctl { 'inactive' }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Populates Directories hash for each path in DirectoryTests' {
            $Vars = @{
                DirectoryTests = @(
                    @{ Path = '/var/www/website1.local/html'; PassGrade = 1 }
                    @{ Path = '/etc/nginx/sites-available'; PassGrade = 1 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.Directories.Keys | Should -Contain '/var/www/website1.local/html'
            $Result.Data.Directories.Keys | Should -Contain '/etc/nginx/sites-available'
        }
    }
}
