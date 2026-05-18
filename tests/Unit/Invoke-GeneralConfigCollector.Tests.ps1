#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-GeneralConfigCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with hostname, IP addresses,
    and net adapter data. Uses mocks to avoid dependency on actual Windows
    networking cmdlets.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-GeneralConfigCollector.ps1'

    # Stubs for Windows-only NetTCPIP and security cmdlets — not available on Linux CI.
    # Pester 5 requires a command to exist before it can be mocked.
    function Get-NetIPAddress { throw 'NetTCPIP stub — should be mocked in each test' }
    function Get-NetIPConfiguration { throw 'NetTCPIP stub — should be mocked in each test' }
    function Get-NetFirewallRule { throw 'NetSecurity stub — should be mocked in each test' }
}

Describe 'Invoke-GeneralConfigCollector' -Tag 'Unit' {

    Context 'Cross-platform result structure' {
        BeforeEach {
            # Mocks only apply on Windows; on Linux the .NET path is used
            Mock Get-NetIPAddress { @() }
            Mock Get-NetIPConfiguration { @() }
            Mock Get-NetFirewallRule { @() }
        }

        It 'Returns Available=$true' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Returns the hostname via cross-platform DNS resolution' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Hostname | Should -Be ([System.Net.Dns]::GetHostName())
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
            $Result.Data.Keys | Should -Contain 'Hostname'
            $Result.Data.Keys | Should -Contain 'IPAddresses'
            $Result.Data.Keys | Should -Contain 'NetAdapters'
            $Result.Data.Keys | Should -Contain 'RdpEnabled'
            $Result.Data.Keys | Should -Contain 'PingEnabled'
        }

        It 'IPAddresses entries have required fields when data is present' {
            $Result = & $Sut -Variables @{}
            if ($Result.Data.IPAddresses.Count -gt 0) {
                $Entry = $Result.Data.IPAddresses[0]
                $Entry.Keys | Should -Contain 'IPAddress'
                $Entry.Keys | Should -Contain 'PrefixLength'
                $Entry.Keys | Should -Contain 'PrefixOrigin'
                $Entry.Keys | Should -Contain 'InterfaceAlias'
            }
            else {
                Set-ItResult -Skipped -Because 'No non-loopback IPv4 interfaces found in this environment'
            }
        }

        It 'NetAdapters entries have required fields when data is present' {
            $Result = & $Sut -Variables @{}
            if ($Result.Data.NetAdapters.Count -gt 0) {
                $Entry = $Result.Data.NetAdapters[0]
                $Entry.Keys | Should -Contain 'InterfaceAlias'
                $Entry.Keys | Should -Contain 'IPv4Address'
                $Entry.Keys | Should -Contain 'Gateway'
                $Entry.Keys | Should -Contain 'DnsServers'
            }
            else {
                Set-ItResult -Skipped -Because 'No non-loopback IPv4 interfaces found in this environment'
            }
        }
    }

    Context 'Windows path - successful collection' -Skip:$IsLinux {
        BeforeEach {
            Mock Get-NetIPAddress {
                @(
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.3'
                        PrefixLength   = 24
                        PrefixOrigin   = 'Manual'
                        InterfaceAlias = 'Ethernet'
                        AddressFamily  = 2
                    }
                )
            }
            Mock Get-NetIPConfiguration {
                @(
                    [PSCustomObject]@{
                        InterfaceAlias     = 'Ethernet'
                        IPv4Address        = [PSCustomObject]@{ IPAddress = '192.168.1.3' }
                        IPv4DefaultGateway = [PSCustomObject]@{ NextHop = '192.168.1.1' }
                        DNSServer          = @(
                            [PSCustomObject]@{
                                AddressFamily   = 2
                                ServerAddresses = @('192.168.1.3', '127.0.0.1')
                            }
                        )
                    }
                )
            }
            Mock Get-ItemProperty {
                [PSCustomObject]@{ fDenyTSConnections = 0 }
            }
            Mock Get-NetFirewallRule {
                @(
                    [PSCustomObject]@{
                        Direction   = 'Inbound'
                        Action      = 'Allow'
                        Enabled     = 'True'
                        DisplayName = 'File and Printer Sharing (Echo Request - ICMPv4-In)'
                    }
                )
            }
        }

        It 'Returns IPv4 address shape and prefix metadata' {
            $Result = & $Sut -Variables @{}
            $Result.Data.IPAddresses.Count | Should -BeGreaterThan 0
            $Result.Data.IPAddresses[0].IPAddress | Should -Match '^\d{1,3}(\.\d{1,3}){3}$'
            $Result.Data.IPAddresses[0].PrefixLength | Should -BeOfType ([int])
            $Result.Data.IPAddresses[0].PrefixOrigin | Should -Not -BeNullOrEmpty
        }

        It 'Returns gateway property with a valid value or null' {
            $Result = & $Sut -Variables @{}
            $Result.Data.NetAdapters.Count | Should -BeGreaterThan 0
            $Gateway = $Result.Data.NetAdapters[0].Gateway
            if ($null -ne $Gateway -and $Gateway -ne '') {
                $Gateway | Should -Match '^\d{1,3}(\.\d{1,3}){3}$'
            }
        }

        It 'Returns RdpEnabled=$true when RDP registry key allows connections' {
            $Result = & $Sut -Variables @{}
            $Result.Data.RdpEnabled | Should -BeTrue
        }

        It 'Returns PingEnabled=$true when ICMPv4 allow rule exists' {
            $Result = & $Sut -Variables @{}
            $Result.Data.PingEnabled | Should -BeTrue
        }

        It 'Has empty Errors array on success' {
            $Result = & $Sut -Variables @{}
            $Result.Errors | Should -HaveCount 0
        }
    }

    Context 'Windows path - IP collection failure' -Skip:$IsLinux {
        BeforeEach {
            Mock Get-NetIPAddress { throw 'Network unavailable' }
            Mock Get-NetIPConfiguration {
                @(
                    [PSCustomObject]@{
                        InterfaceAlias     = 'Ethernet'
                        IPv4Address        = [PSCustomObject]@{ IPAddress = '192.168.1.3' }
                        IPv4DefaultGateway = $null
                        DNSServer          = @()
                    }
                )
            }
            Mock Get-ItemProperty {
                [PSCustomObject]@{ fDenyTSConnections = 0 }
            }
            Mock Get-NetFirewallRule { @() }
        }

        It 'Still returns Available=$true because hostname collection succeeds' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Records the IP error in Errors array' {
            $Result = & $Sut -Variables @{}
            $Result.Errors.Count | Should -BeGreaterThan 0
            $Result.Errors[0] | Should -Match 'IP address collection failed'
        }
    }
}
