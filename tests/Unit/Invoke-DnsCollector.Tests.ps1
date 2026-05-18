#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-DnsCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with zones, records,
    and forwarders. Uses mocks to avoid dependency on DNS Server cmdlets.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-DnsCollector.ps1'

    # Stub DNS Server cmdlets so Pester can mock them on machines without the DNS module
    if (-not (Get-Command -Name Get-WindowsFeature -ErrorAction SilentlyContinue)) {
        function global:Get-WindowsFeature { }
    }
    if (-not (Get-Command -Name Get-DnsServerZone -ErrorAction SilentlyContinue)) {
        function global:Get-DnsServerZone { }
    }
    if (-not (Get-Command -Name Get-DnsServerResourceRecord -ErrorAction SilentlyContinue)) {
        function global:Get-DnsServerResourceRecord { }
    }
    if (-not (Get-Command -Name Get-DnsServerForwarder -ErrorAction SilentlyContinue)) {
        function global:Get-DnsServerForwarder { }
    }
}

Describe 'Invoke-DnsCollector' -Tag 'Unit' {

    Context 'DNS role not installed' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $false }
            }
        }

        It 'Returns Available=$false' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
        }

        It 'Sets Reason to indicate DNS not installed' {
            $Result = & $Sut -Variables @{}
            $Result.Reason | Should -Match 'DNS Server role not installed'
        }
    }

    Context 'DNS feature query fails' {
        BeforeEach {
            Mock Get-WindowsFeature { throw 'Access denied' }
        }

        It 'Returns Available=$false with error reason' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
            $Result.Reason | Should -Match 'Cannot query DNS feature'
        }
    }

    Context 'Successful DNS collection' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $true }
            }
            Mock Get-DnsServerZone {
                @(
                    [PSCustomObject]@{
                        ZoneName            = 'zinneke.be'
                        ZoneType            = 'Primary'
                        IsReverseLookupZone = $false
                        IsDsIntegrated      = $true
                        DynamicUpdate       = 'NonsecureAndSecure'
                        SecureSecondaries   = 'TransferToZoneNameServer'
                        SecondaryServers    = @([System.Net.IPAddress]::Parse('192.168.1.4'))
                    }
                    [PSCustomObject]@{
                        ZoneName            = '1.168.192.in-addr.arpa'
                        ZoneType            = 'Primary'
                        IsReverseLookupZone = $true
                        IsDsIntegrated      = $true
                        DynamicUpdate       = 'NonsecureAndSecure'
                        SecureSecondaries   = 'TransferToZoneNameServer'
                        SecondaryServers    = @()
                    }
                )
            }
            Mock Get-DnsServerResourceRecord {
                param($ZoneName)
                if ($ZoneName -eq 'zinneke.be') {
                    @(
                        [PSCustomObject]@{
                            HostName   = 'dc1'
                            RecordType = 'A'
                            RecordData = [PSCustomObject]@{
                                IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.3')
                            }
                            TimeToLive = [timespan]::FromHours(1)
                        }
                        [PSCustomObject]@{
                            HostName   = 'www'
                            RecordType = 'CNAME'
                            RecordData = [PSCustomObject]@{
                                HostNameAlias = 'dc1.zinneke.be.'
                            }
                            TimeToLive = [timespan]::FromHours(1)
                        }
                    )
                }
                else {
                    @(
                        [PSCustomObject]@{
                            HostName   = '3'
                            RecordType = 'PTR'
                            RecordData = [PSCustomObject]@{
                                PtrDomainName = 'dc1.zinneke.be.'
                            }
                            TimeToLive = [timespan]::FromHours(1)
                        }
                    )
                }
            }
            Mock Get-DnsServerForwarder {
                [PSCustomObject]@{
                    IPAddress = @(
                        [System.Net.IPAddress]::Parse('8.8.8.8')
                        [System.Net.IPAddress]::Parse('1.1.1.1')
                    )
                }
            }
        }

        It 'Returns Available=$true' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Collects zones' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Zones.Count | Should -Be 2
            $Result.Data.Zones[0].ZoneName | Should -Be 'zinneke.be'
        }

        It 'Collects zone DynamicUpdate property' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Zones[0].DynamicUpdate | Should -Be 'NonsecureAndSecure'
        }

        It 'Collects zone SecureSecondaries property' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Zones[0].SecureSecondaries | Should -Be 'TransferToZoneNameServer'
        }

        It 'Collects zone SecondaryServers property' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Zones[0].SecondaryServers | Should -Contain '192.168.1.4'
        }

        It 'Collects resource records with flattened values' {
            $Result = & $Sut -Variables @{}
            $ARecords = @($Result.Data.Records | Where-Object { $_.RecordType -eq 'A' })
            $ARecords.Count | Should -BeGreaterThan 0
            $ARecords[0].Value | Should -Be '192.168.1.3'
        }

        It 'Collects CNAME records' {
            $Result = & $Sut -Variables @{}
            $CnameRecords = @($Result.Data.Records | Where-Object { $_.RecordType -eq 'CNAME' })
            $CnameRecords.Count | Should -BeGreaterThan 0
            $CnameRecords[0].Value | Should -Be 'dc1.zinneke.be.'
        }

        It 'Collects PTR records' {
            $Result = & $Sut -Variables @{}
            $PtrRecords = @($Result.Data.Records | Where-Object { $_.RecordType -eq 'PTR' })
            $PtrRecords.Count | Should -BeGreaterThan 0
        }

        It 'Collects forwarders' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Forwarders.Count | Should -Be 2
            $Result.Data.Forwarders[0].IPAddress | Should -Be '8.8.8.8'
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
            Mock Get-DnsServerZone {
                @(
                    [PSCustomObject]@{
                        ZoneName            = 'test.local'
                        ZoneType            = 'Primary'
                        IsReverseLookupZone = $false
                        IsDsIntegrated      = $false
                        DynamicUpdate       = 'None'
                        SecureSecondaries   = 'NoTransfer'
                        SecondaryServers    = @()
                    }
                )
            }
            Mock Get-DnsServerResourceRecord { throw 'Zone access denied' }
            Mock Get-DnsServerForwarder { throw 'Forwarder query failed' }
        }

        It 'Still returns Available=$true since DNS role is installed' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Records errors for failed sub-operations' {
            $Result = & $Sut -Variables @{}
            $Result.Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Result structure' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $true }
            }
            Mock Get-DnsServerZone { @() }
            Mock Get-DnsServerForwarder {
                [PSCustomObject]@{ IPAddress = @() }
            }
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
            $Result.Data.Keys | Should -Contain 'Zones'
            $Result.Data.Keys | Should -Contain 'Records'
            $Result.Data.Keys | Should -Contain 'Forwarders'
        }
    }
}
