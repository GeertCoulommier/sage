#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-DhcpCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with authorization state,
    scopes, exclusions, options, and reservations. Uses mocks.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-DhcpCollector.ps1'

    if (-not (Get-Command -Name Get-WindowsFeature -ErrorAction SilentlyContinue)) {
        function global:Get-WindowsFeature { }
    }
    if (-not (Get-Command -Name Get-DhcpServerSetting -ErrorAction SilentlyContinue)) {
        function global:Get-DhcpServerSetting { }
    }
    if (-not (Get-Command -Name Get-DhcpServerv4Scope -ErrorAction SilentlyContinue)) {
        function global:Get-DhcpServerv4Scope { }
    }
    if (-not (Get-Command -Name Get-DhcpServerv4ExclusionRange -ErrorAction SilentlyContinue)) {
        function global:Get-DhcpServerv4ExclusionRange { }
    }
    if (-not (Get-Command -Name Get-DhcpServerv4OptionValue -ErrorAction SilentlyContinue)) {
        function global:Get-DhcpServerv4OptionValue { }
    }
    if (-not (Get-Command -Name Get-DhcpServerv4Reservation -ErrorAction SilentlyContinue)) {
        function global:Get-DhcpServerv4Reservation { }
    }
    if (-not (Get-Command -Name Get-DhcpServerv4FilterList -ErrorAction SilentlyContinue)) {
        function global:Get-DhcpServerv4FilterList { }
    }
    if (-not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
        function global:Get-CimInstance { }
    }
}

Describe 'Invoke-DhcpCollector' -Tag 'Unit' {

    Context 'DHCP role not installed' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $false }
            }
        }

        It 'Returns Available=$true so role-install assertions can run' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Sets Reason to indicate DHCP not installed' {
            $Result = & $Sut -Variables @{}
            $Result.Reason | Should -Match 'DHCP Server role not installed'
        }

        It 'Marks role as not installed in collected data' {
            $Result = & $Sut -Variables @{}
            $Result.Data.RoleInstalled | Should -BeFalse
        }
    }

    Context 'DHCP feature query fails' {
        BeforeEach {
            Mock Get-WindowsFeature { throw 'Access denied' }
        }

        It 'Returns Available=$false with error reason' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
            $Result.Reason | Should -Match 'Cannot query DHCP feature'
        }
    }

    Context 'Successful DHCP collection' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $true }
            }
            Mock Get-DhcpServerSetting {
                [PSCustomObject]@{ IsAuthorized = $true }
            }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Domain = 'sage.local' }
            }
            Mock Get-DhcpServerv4FilterList {
                @(
                    [PSCustomObject]@{ List = 'Allow'; Enabled = $false }
                    [PSCustomObject]@{ List = 'Deny'; Enabled = $false }
                )
            }
            Mock Get-DhcpServerv4Scope {
                @(
                    [PSCustomObject]@{
                        ScopeId       = [System.Net.IPAddress]::Parse('192.168.1.0')
                        Name          = 'LAN Scope'
                        StartRange    = [System.Net.IPAddress]::Parse('192.168.1.1')
                        EndRange      = [System.Net.IPAddress]::Parse('192.168.1.200')
                        SubnetMask    = [System.Net.IPAddress]::Parse('255.255.255.0')
                        State         = 'Active'
                        LeaseDuration = [System.TimeSpan]::FromDays(4)
                    }
                )
            }
            Mock Get-DhcpServerv4ExclusionRange {
                @(
                    [PSCustomObject]@{
                        StartRange = [System.Net.IPAddress]::Parse('192.168.1.1')
                        EndRange   = [System.Net.IPAddress]::Parse('192.168.1.100')
                    }
                )
            }
            Mock Get-DhcpServerv4OptionValue {
                @(
                    [PSCustomObject]@{
                        OptionId = 3
                        Name     = 'Router'
                        Value    = @([System.Net.IPAddress]::Parse('192.168.1.1'))
                    }
                    [PSCustomObject]@{
                        OptionId = 6
                        Name     = 'DNS Servers'
                        Value    = @([System.Net.IPAddress]::Parse('192.168.1.3'))
                    }
                    [PSCustomObject]@{
                        OptionId = 15
                        Name     = 'DNS Domain Name'
                        Value    = @('zinneke.be')
                    }
                )
            }
            Mock Get-DhcpServerv4Reservation {
                @(
                    [PSCustomObject]@{
                        IPAddress = [System.Net.IPAddress]::Parse('192.168.1.5')
                        Name      = 'client'
                        ClientId  = 'AA-BB-CC-DD-EE-FF'
                    }
                )
            }
        }

        It 'Returns Available=$true' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Reports server as authorized' {
            $Result = & $Sut -Variables @{}
            $Result.Data.IsAuthorized | Should -BeTrue
        }

        It 'Reports role as installed' {
            $Result = & $Sut -Variables @{}
            $Result.Data.RoleInstalled | Should -BeTrue
        }

        It 'Collects the server domain name' {
            $Result = & $Sut -Variables @{}
            $Result.Data.DomainName | Should -Be 'sage.local'
        }

        It 'Collects allow/deny filter enabled states' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Filters.AllowEnabled | Should -BeFalse
            $Result.Data.Filters.DenyEnabled | Should -BeFalse
        }

        It 'Collects scopes with flattened IP strings' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Scopes.Count | Should -Be 1
            $Result.Data.Scopes[0].ScopeId | Should -Be '192.168.1.0'
            $Result.Data.Scopes[0].StartRange | Should -Be '192.168.1.1'
            $Result.Data.Scopes[0].EndRange | Should -Be '192.168.1.200'
            $Result.Data.Scopes[0].LeaseDurationDays | Should -Be 4
        }

        It 'Collects exclusion ranges' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Scopes[0].Exclusions.Count | Should -Be 1
            $Result.Data.Scopes[0].Exclusions[0].StartRange | Should -Be '192.168.1.1'
        }

        It 'Collects scope options' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Scopes[0].Options.Count | Should -Be 3
            $Router = $Result.Data.Scopes[0].Options | Where-Object { $_.Name -eq 'Router' }
            $Router.Value | Should -Contain '192.168.1.1'
        }

        It 'Collects reservations' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Scopes[0].Reservations.Count | Should -Be 1
            $Result.Data.Scopes[0].Reservations[0].IPAddress | Should -Be '192.168.1.5'
        }

        It 'Has empty Errors array on clean run' {
            $Result = & $Sut -Variables @{}
            $Result.Errors | Should -HaveCount 0
        }
    }

    Context 'Partial collection failure' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $true }
            }
            Mock Get-DhcpServerSetting { throw 'Setting query failed' }
            Mock Get-CimInstance { throw 'CIM query failed' }
            Mock Get-DhcpServerv4FilterList { throw 'Filter query failed' }
            Mock Get-DhcpServerv4Scope { throw 'Scope query failed' }
        }

        It 'Still returns Available=$true since DHCP role is installed' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Records errors for failed sub-operations' {
            $Result = & $Sut -Variables @{}
            $Result.Errors.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Result structure' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $true }
            }
            Mock Get-DhcpServerSetting {
                [PSCustomObject]@{ IsAuthorized = $false }
            }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Domain = 'sage.local' }
            }
            Mock Get-DhcpServerv4FilterList { @() }
            Mock Get-DhcpServerv4Scope { @() }
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
            $Result.Data.Keys | Should -Contain 'IsAuthorized'
            $Result.Data.Keys | Should -Contain 'RoleInstalled'
            $Result.Data.Keys | Should -Contain 'DomainName'
            $Result.Data.Keys | Should -Contain 'Filters'
            $Result.Data.Keys | Should -Contain 'Scopes'
        }
    }
}
