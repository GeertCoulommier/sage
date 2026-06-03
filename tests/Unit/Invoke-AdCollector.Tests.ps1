#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-AdCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with domain info, computers,
    OUs, users, and groups. Uses mocks to avoid dependency on AD cmdlets.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-AdCollector.ps1'

    # Stub AD cmdlets so Pester can mock them on machines without RSAT
    if (-not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
        function global:Get-CimInstance { }
    }
    if (-not (Get-Command -Name Get-ADDomain -ErrorAction SilentlyContinue)) {
        function global:Get-ADDomain { }
    }
    if (-not (Get-Command -Name Get-ADForest -ErrorAction SilentlyContinue)) {
        function global:Get-ADForest { }
    }
    if (-not (Get-Command -Name Get-ADComputer -ErrorAction SilentlyContinue)) {
        function global:Get-ADComputer { }
    }
    if (-not (Get-Command -Name Get-ADOrganizationalUnit -ErrorAction SilentlyContinue)) {
        function global:Get-ADOrganizationalUnit { }
    }
    if (-not (Get-Command -Name Get-ADUser -ErrorAction SilentlyContinue)) {
        function global:Get-ADUser { }
    }
    if (-not (Get-Command -Name Get-ADGroup -ErrorAction SilentlyContinue)) {
        function global:Get-ADGroup { }
    }
    if (-not (Get-Command -Name Get-ADReplicationSite -ErrorAction SilentlyContinue)) {
        function global:Get-ADReplicationSite { }
    }
    if (-not (Get-Command -Name Get-ADReplicationSubnet -ErrorAction SilentlyContinue)) {
        function global:Get-ADReplicationSubnet { }
    }
    if (-not (Get-Command -Name Get-ADReplicationSiteLink -ErrorAction SilentlyContinue)) {
        function global:Get-ADReplicationSiteLink { }
    }
    if (-not (Get-Command -Name Get-ADDomainController -ErrorAction SilentlyContinue)) {
        function global:Get-ADDomainController { }
    }
}

Describe 'Invoke-AdCollector' -Tag 'Unit' {

    Context 'Not part of a domain' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $false }
            }
        }

        It 'Returns Available=$false' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
        }

        It 'Sets Reason to indicate not domain-joined' {
            $Result = & $Sut -Variables @{}
            $Result.Reason | Should -Match 'not part of a domain'
        }
    }

    Context 'WMI query fails' {
        BeforeEach {
            Mock Get-CimInstance { throw 'WMI access denied' }
        }

        It 'Returns Available=$false with error reason' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
            $Result.Reason | Should -Match 'Cannot query WMI'
        }
    }

    Context 'Successful AD collection' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true }
            }
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DNSRoot           = 'zinneke.be'
                    DistinguishedName = 'DC=zinneke,DC=be'
                    DomainMode        = 'Windows2016Domain'
                }
            }
            Mock Get-ADForest {
                [PSCustomObject]@{
                    ForestMode = 'Windows2016Forest'
                }
            }
            Mock Get-ADComputer {
                @(
                    [PSCustomObject]@{
                        Name              = 'client'
                        DNSHostName       = 'client.zinneke.be'
                        DistinguishedName = 'CN=client,CN=Computers,DC=zinneke,DC=be'
                    }
                )
            }
            Mock Get-ADOrganizationalUnit {
                @(
                    [PSCustomObject]@{
                        Name              = 'Marketing'
                        DistinguishedName = 'OU=Marketing,DC=zinneke,DC=be'
                    }
                )
            }
            Mock Get-ADUser {
                @(
                    [PSCustomObject]@{
                        GivenName         = 'Daan'
                        Surname           = 'Banaan'
                        SamAccountName    = 'daan.banaan'
                        Name              = 'Daan Banaan'
                        DistinguishedName = 'CN=Daan Banaan,OU=Marketing,DC=zinneke,DC=be'
                        MemberOf          = @('CN=Domain Users,CN=Users,DC=zinneke,DC=be')
                    }
                )
            }
            Mock Get-ADGroup {
                @(
                    [PSCustomObject]@{
                        Name              = 'Domain Users'
                        SamAccountName    = 'Domain Users'
                        GroupScope        = 'Global'
                        GroupCategory     = 'Security'
                        DistinguishedName = 'CN=Domain Users,CN=Users,DC=zinneke,DC=be'
                        Members           = @('CN=Daan Banaan,OU=Marketing,DC=zinneke,DC=be')
                    }
                )
            }
            Mock Get-ADReplicationSite {
                @(
                    [PSCustomObject]@{
                        Name              = 'Kaai'
                        DistinguishedName = 'CN=Kaai,CN=Sites,CN=Configuration,DC=zinneke,DC=be'
                    }
                    [PSCustomObject]@{
                        Name              = 'Jette'
                        DistinguishedName = 'CN=Jette,CN=Sites,CN=Configuration,DC=zinneke,DC=be'
                    }
                )
            }
            Mock Get-ADReplicationSubnet {
                @(
                    [PSCustomObject]@{
                        Name = '192.168.1.0/24'
                        Site = 'CN=Kaai,CN=Sites,CN=Configuration,DC=zinneke,DC=be'
                    }
                )
            }
            Mock Get-ADReplicationSiteLink {
                # Build a 188-byte schedule: Monday (day 1) hour 10 = 0x0F, all else 0
                $TestSchedule = [byte[]]::new(188)
                $TestSchedule[20 + (1 * 24) + 10] = [byte]0x0F
                @(
                    [PSCustomObject]@{
                        Name                          = 'Kaai-Jette'
                        Cost                          = 10
                        ReplicationFrequencyInMinutes = 60
                        SitesIncluded                 = @(
                            'CN=Kaai,CN=Sites,CN=Configuration,DC=zinneke,DC=be',
                            'CN=Jette,CN=Sites,CN=Configuration,DC=zinneke,DC=be'
                        )
                        Schedule                      = $TestSchedule
                    }
                )
            }
            Mock Get-ADDomainController {
                @(
                    [PSCustomObject]@{
                        Name = 'DC1'
                        Site = 'Kaai'
                    }
                    [PSCustomObject]@{
                        Name = 'DC2'
                        Site = 'Bloemenhof'
                    }
                )
            }
        }

        It 'Returns Available=$true' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Collects domain info' {
            $Result = & $Sut -Variables @{}
            $Result.Data.DomainName | Should -Be 'zinneke.be'
            $Result.Data.DomainFunctionalLevel | Should -Be 'Windows2016Domain'
            $Result.Data.ForestFunctionalLevel | Should -Be 'Windows2016Forest'
        }

        It 'Collects computers' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Computers.Count | Should -Be 1
            $Result.Data.Computers[0].Name | Should -Be 'client'
        }

        It 'Collects OUs' {
            $Result = & $Sut -Variables @{}
            $Result.Data.OUs.Count | Should -Be 1
            $Result.Data.OUs[0].Name | Should -Be 'Marketing'
        }

        It 'Collects users' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Users.Count | Should -Be 1
            $Result.Data.Users[0].SamAccountName | Should -Be 'daan.banaan'
            $Result.Data.Users[0].GivenName | Should -Be 'Daan'
        }

        It 'Collects groups with flattened Members array' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Groups.Count | Should -Be 1
            $Result.Data.Groups[0].Name | Should -Be 'Domain Users'
            $Result.Data.Groups[0].GroupScope | Should -Be 'Global'
        }

        It 'Has empty Errors array on clean run' {
            $Result = & $Sut -Variables @{}
            $Result.Errors | Should -HaveCount 0
        }

        It 'Collects sites' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Sites.Count | Should -Be 2
            $Result.Data.Sites[0].Name | Should -Be 'Kaai'
        }

        It 'Collects subnets with resolved site name' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Subnets.Count | Should -Be 1
            $Result.Data.Subnets[0].Name | Should -Be '192.168.1.0/24'
            $Result.Data.Subnets[0].SiteName | Should -Be 'Kaai'
        }

        It 'Collects site links with resolved site names' {
            $Result = & $Sut -Variables @{}
            $Result.Data.SiteLinks.Count | Should -Be 1
            $Result.Data.SiteLinks[0].Name | Should -Be 'Kaai-Jette'
            $Result.Data.SiteLinks[0].Cost | Should -Be 10
            $Result.Data.SiteLinks[0].ReplicationFrequencyInMinutes | Should -Be 60
            $Result.Data.SiteLinks[0].SiteNames | Should -Contain 'Kaai'
            $Result.Data.SiteLinks[0].SiteNames | Should -Contain 'Jette'
        }

        It 'Decodes schedule bytes into a 168-element matrix' {
            $Result = & $Sut -Variables @{}
            $Matrix = $Result.Data.SiteLinks[0].ScheduleMatrix
            $Matrix | Should -Not -BeNullOrEmpty
            $Matrix.Count | Should -Be 168
            # Monday (day 1) hour 10 = index 1*24+10 = 34 should be 0x0F
            $Matrix[34] | Should -Be 0x0F
            # Monday hour 0 = index 24 should be 0
            $Matrix[24] | Should -Be 0
        }

        It 'Collects domain controllers with site membership' {
            $Result = & $Sut -Variables @{}
            $Result.Data.DomainControllers.Count | Should -Be 2
            $DC1 = $Result.Data.DomainControllers | Where-Object { $_.Name -eq 'DC1' }
            $DC1 | Should -Not -BeNullOrEmpty
            $DC1.Site | Should -Be 'Kaai'
            $DC2 = $Result.Data.DomainControllers | Where-Object { $_.Name -eq 'DC2' }
            $DC2 | Should -Not -BeNullOrEmpty
            $DC2.Site | Should -Be 'Bloemenhof'
        }
    }

    Context 'Partial collection failure' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true }
            }
            Mock Get-ADDomain { throw 'Domain query failed' }
            Mock Get-ADForest { throw 'Forest query failed' }
            Mock Get-ADComputer { throw 'Computers query failed' }
            Mock Get-ADOrganizationalUnit { throw 'OUs query failed' }
            Mock Get-ADUser { throw 'Users query failed' }
            Mock Get-ADGroup { throw 'Groups query failed' }
            Mock Get-ADReplicationSite { throw 'Sites query failed' }
            Mock Get-ADReplicationSubnet { throw 'Subnets query failed' }
            Mock Get-ADReplicationSiteLink { throw 'Site links query failed' }
            Mock Get-ADDomainController { throw 'DomainControllers query failed' }
        }

        It 'Still returns Available=$true since machine is domain-joined' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Records errors for each failed sub-operation' {
            $Result = & $Sut -Variables @{}
            $Result.Errors.Count | Should -BeGreaterOrEqual 7
        }
    }

    Context 'Result structure' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true }
            }
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DNSRoot           = 'test.local'
                    DistinguishedName = 'DC=test,DC=local'
                    DomainMode        = 'Windows2016Domain'
                }
            }
            Mock Get-ADForest {
                [PSCustomObject]@{ ForestMode = 'Windows2016Forest' }
            }
            Mock Get-ADComputer { @() }
            Mock Get-ADOrganizationalUnit { @() }
            Mock Get-ADUser { @() }
            Mock Get-ADGroup { @() }
            Mock Get-ADReplicationSite { @() }
            Mock Get-ADReplicationSubnet { @() }
            Mock Get-ADReplicationSiteLink { @() }
            Mock Get-ADDomainController { @() }
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
            $Result.Data.Keys | Should -Contain 'DomainName'
            $Result.Data.Keys | Should -Contain 'DomainFunctionalLevel'
            $Result.Data.Keys | Should -Contain 'ForestFunctionalLevel'
            $Result.Data.Keys | Should -Contain 'Computers'
            $Result.Data.Keys | Should -Contain 'OUs'
            $Result.Data.Keys | Should -Contain 'Users'
            $Result.Data.Keys | Should -Contain 'Groups'
            $Result.Data.Keys | Should -Contain 'Sites'
            $Result.Data.Keys | Should -Contain 'Subnets'
            $Result.Data.Keys | Should -Contain 'SiteLinks'
            $Result.Data.Keys | Should -Contain 'DomainControllers'
        }
    }
}
