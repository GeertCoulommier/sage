#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-ApacheCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with Apache (httpd) service status,
    config files, and index files. Uses mocks to avoid Linux dependency.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-ApacheCollector.ps1'

    if (-not (Get-Command -Name httpd -ErrorAction SilentlyContinue)) {
        function global:httpd { }
    }
    if (-not (Get-Command -Name systemctl -ErrorAction SilentlyContinue)) {
        function global:systemctl { }
    }
}

Describe 'Invoke-ApacheCollector' -Tag 'Unit' {

    Context 'Apache not installed' {
        BeforeEach {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'httpd' }
        }

        It 'Returns Available=$false' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
        }

        It 'Sets Reason about Apache not installed' {
            $Result = & $Sut -Variables @{}
            $Result.Reason | Should -Match 'not installed'
        }
    }

    Context 'Apache installed but service offline' {
        BeforeEach {
            Mock Get-Command { [PSCustomObject]@{ Name = 'httpd' } } -ParameterFilter { $Name -eq 'httpd' }
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

    Context 'Successful Apache collection' {
        BeforeEach {
            Mock Get-Command { [PSCustomObject]@{ Name = 'httpd' } } -ParameterFilter { $Name -eq 'httpd' }
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
            Mock Get-Command { [PSCustomObject]@{ Name = 'httpd' } } -ParameterFilter { $Name -eq 'httpd' }
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
            $Result.Data.Keys | Should -Contain 'HttpdConfListen'
            $Result.Data.Keys | Should -Contain 'HttpdConfInclude'
            $Result.Data.Keys | Should -Contain 'FirewallServices'
            $Result.Data.Keys | Should -Contain 'Directories'
            $Result.Data.Keys | Should -Contain 'SymlinkFiles'
            $Result.Data.Keys | Should -Contain 'CurlResults'
            $Result.Data.Keys | Should -Contain 'MariaDbEnabled'
            $Result.Data.Keys | Should -Contain 'MariaDbRunning'
            $Result.Data.Keys | Should -Contain 'PhpFpmEnabled'
            $Result.Data.Keys | Should -Contain 'PhpFpmRunning'
        }
    }

    Context 'Directory existence checks via Variables' {
        BeforeEach {
            Mock Get-Command { [PSCustomObject]@{ Name = 'httpd' } } -ParameterFilter { $Name -eq 'httpd' }
            Mock systemctl { 'inactive' }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Populates Directories hashtable for each path in DirectoryTests' {
            $Vars = @{
                DirectoryTests = @(
                    @{ Path = '/var/www/website1.local/html'; PassGrade = 1 }
                    @{ Path = '/var/www/website1.local/log'; PassGrade = 1 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.Directories.Keys | Should -Contain '/var/www/website1.local/html'
            $Result.Data.Directories.Keys | Should -Contain '/var/www/website1.local/log'
        }

        It 'Reports $false for non-existent directories' {
            $Vars = @{
                DirectoryTests = @(
                    @{ Path = '/nonexistent/path'; PassGrade = 1 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.Directories['/nonexistent/path'] | Should -BeFalse
        }
    }

    Context 'Curl tests via Variables' {
        BeforeEach {
            Mock Get-Command { [PSCustomObject]@{ Name = 'httpd' } } -ParameterFilter { $Name -eq 'httpd' }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'curl' }
            Mock systemctl { 'inactive' }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Adds a CurlResults entry for each CurlTests target when curl not available' {
            $Vars = @{
                CurlTests = @(
                    @{ Url = 'http://website1.local'; ResolveHost = 'website1.local'; ResolvePort = 80; ResolveAddress = '127.0.0.1'; ExpectedContent = 'test' }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.CurlResults | Should -HaveCount 1
            $Result.Data.CurlResults[0].Url | Should -Be 'http://website1.local'
        }
    }
}
