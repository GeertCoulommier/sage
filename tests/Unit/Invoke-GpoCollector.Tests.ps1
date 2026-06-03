#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-GpoCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with GPO data including
    links, permissions, and scope settings. Uses mocks to avoid AD dependency.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-GpoCollector.ps1'

    # Stub cmdlets so Pester can mock them on machines without RSAT
    if (-not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
        function global:Get-CimInstance { }
    }
    if (-not (Get-Command -Name Get-ADDomain -ErrorAction SilentlyContinue)) {
        function global:Get-ADDomain { }
    }
    if (-not (Get-Command -Name Import-Module -ErrorAction SilentlyContinue)) {
        function global:Import-Module { }
    }
    if (-not (Get-Command -Name Get-GPO -ErrorAction SilentlyContinue)) {
        function global:Get-GPO { }
    }
    if (-not (Get-Command -Name Get-GPOReport -ErrorAction SilentlyContinue)) {
        function global:Get-GPOReport { }
    }
    if (-not (Get-Command -Name Get-GPPermission -ErrorAction SilentlyContinue)) {
        function global:Get-GPPermission { }
    }
}

Describe 'Invoke-GpoCollector' -Tag 'Unit' {

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

    Context 'GroupPolicy module unavailable' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true; Domain = 'zinneke.be' }
            }
            Mock Import-Module { throw 'Module not found' } -ParameterFilter { $Name -eq 'GroupPolicy' }
        }

        It 'Returns Available=$false with module error' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
            $Result.Reason | Should -Match 'GroupPolicy module unavailable'
        }
    }

    Context 'Successful GPO collection' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true; Domain = 'zinneke.be' }
            }
            Mock Import-Module { } -ParameterFilter { $Name -eq 'GroupPolicy' }
            Mock Get-ADDomain {
                [PSCustomObject]@{ DNSRoot = 'zinneke.be' }
            }
            Mock Get-GPO {
                @(
                    [PSCustomObject]@{
                        DisplayName = 'secured desktop'
                        Id          = [guid]::NewGuid()
                        Description = 'Locks down desktop for users'
                        GpoStatus   = 'AllSettingsEnabled'
                    }
                )
            }
            Mock Get-GPOReport {
                @'
<gpo xmlns="http://www.microsoft.com/GroupPolicy/Settings" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <LinksTo>
    <SOMPath>zinneke.be/Marketing</SOMPath>
    <Enabled>true</Enabled>
  </LinksTo>
  <Computer>
    <extensionData>
    </extensionData>
  </Computer>
  <User>
    <extensionData>
      <Extension>
        <Policy>
          <Name>Prohibit access to Control Panel</Name>
          <Category>Control Panel</Category>
          <State>Enabled</State>
        </Policy>
      </Extension>
      <Name>Administrative Templates</Name>
    </extensionData>
  </User>
</gpo>
'@
            }
            Mock Get-GPPermission {
                @(
                    [PSCustomObject]@{
                        Trustee    = [PSCustomObject]@{
                            Name    = 'Authenticated Users'
                            SidType = 'WellKnownGroup'
                        }
                        Permission = 'GpoApply'
                    }
                )
            }
        }

        It 'Returns Available=$true' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Collects domain name' {
            $Result = & $Sut -Variables @{}
            $Result.Data.DomainName | Should -Be 'zinneke.be'
        }

        It 'Collects GPO names' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Gpos.Count | Should -Be 1
            $Result.Data.Gpos[0].Name | Should -Be 'secured desktop'
        }

        It 'Collects GPO links' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Gpos[0].Links.Count | Should -BeGreaterOrEqual 1
            $Result.Data.Gpos[0].Links[0].SOMPath | Should -Be 'zinneke.be/Marketing'
        }

        It 'Collects GPO permissions' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Gpos[0].Permissions.Count | Should -Be 1
            $Result.Data.Gpos[0].Permissions[0].Trustee | Should -Be 'Authenticated Users'
        }

        It 'Has empty Errors array on clean run' {
            $Result = & $Sut -Variables @{}
            $Result.Errors | Should -HaveCount 0
        }
    }

    Context 'GPO enumeration fails' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true; Domain = 'zinneke.be' }
            }
            Mock Import-Module { } -ParameterFilter { $Name -eq 'GroupPolicy' }
            Mock Get-ADDomain {
                [PSCustomObject]@{ DNSRoot = 'zinneke.be' }
            }
            Mock Get-GPO { throw 'Access denied' }
        }

        It 'Records error and returns empty Gpos' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
            $Result.Data.Gpos | Should -HaveCount 0
            $Result.Errors.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Result structure' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true; Domain = 'zinneke.be' }
            }
            Mock Import-Module { } -ParameterFilter { $Name -eq 'GroupPolicy' }
            Mock Get-ADDomain {
                [PSCustomObject]@{ DNSRoot = 'zinneke.be' }
            }
            Mock Get-GPO { @() }
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
            $Result.Data.Keys | Should -Contain 'Gpos'
        }
    }

    Context 'Drive Maps collection' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true; Domain = 'zinneke.be' }
            }
            Mock Import-Module { } -ParameterFilter { $Name -eq 'GroupPolicy' }
            Mock Get-ADDomain { [PSCustomObject]@{ DNSRoot = 'zinneke.be' } }
            Mock Get-GPO {
                @([PSCustomObject]@{
                    DisplayName = 'X-Drive mapping'
                    Id          = [guid]::NewGuid()
                    Description = ''
                    GpoStatus   = 'AllSettingsEnabled'
                })
            }
            Mock Get-GPPermission { @() }
            Mock Get-GPOReport {
                @'
<gpo xmlns="http://www.microsoft.com/GroupPolicy/Settings">
  <Computer><extensionData/></Computer>
  <User>
    <extensionData>
      <Extension>
        <DriveMapSettings>
          <Drive>
            <Name>X-Drive</Name>
            <Properties action="R" letter="X" path="\\dc1\algemene_informatie" label="Algemeen"/>
          </Drive>
        </DriveMapSettings>
      </Extension>
      <Name>Drive Maps</Name>
    </extensionData>
  </User>
</gpo>
'@
            }
        }

        It 'Collects DriveMap type in UserScope' {
            $Result = & $Sut -Variables @{}
            $DriveMap = $Result.Data.Gpos[0].UserScope | Where-Object { $_.Type -eq 'DriveMap' }
            $DriveMap | Should -Not -BeNullOrEmpty
        }

        It 'Collects drive letter with colon suffix' {
            $Result = & $Sut -Variables @{}
            $DriveMap = $Result.Data.Gpos[0].UserScope | Where-Object { $_.Type -eq 'DriveMap' }
            $DriveMap.Settings.Letter | Should -Be 'X:'
        }

        It 'Collects drive UNC path' {
            $Result = & $Sut -Variables @{}
            $DriveMap = $Result.Data.Gpos[0].UserScope | Where-Object { $_.Type -eq 'DriveMap' }
            $DriveMap.Settings.Path | Should -Be '\\dc1\algemene_informatie'
        }

        It 'Collects drive action as descriptive string' {
            $Result = & $Sut -Variables @{}
            $DriveMap = $Result.Data.Gpos[0].UserScope | Where-Object { $_.Type -eq 'DriveMap' }
            $DriveMap.Settings.Action | Should -Be 'Replace'
        }
    }

    Context 'Software Installation collection' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true; Domain = 'zinneke.be' }
            }
            Mock Import-Module { } -ParameterFilter { $Name -eq 'GroupPolicy' }
            Mock Get-ADDomain { [PSCustomObject]@{ DNSRoot = 'zinneke.be' } }
            Mock Get-GPO {
                @([PSCustomObject]@{
                    DisplayName = '7-zip install'
                    Id          = [guid]::NewGuid()
                    Description = ''
                    GpoStatus   = 'AllSettingsEnabled'
                })
            }
            Mock Get-GPPermission { @() }
            Mock Get-GPOReport {
                @'
<gpo xmlns="http://www.microsoft.com/GroupPolicy/Settings">
  <Computer>
    <extensionData>
      <Extension>
        <msiApplication>
          <Name>7-Zip 24.08 (x64 edition)</Name>
          <Path>\\dc1\software\7z2408-x64.msi</Path>
          <DeploymentType>Assigned</DeploymentType>
        </msiApplication>
      </Extension>
      <Name>Software Installation</Name>
    </extensionData>
  </Computer>
  <User><extensionData/></User>
</gpo>
'@
            }
        }

        It 'Collects SoftwareInstallation type in ComputerScope' {
            $Result = & $Sut -Variables @{}
            $App = $Result.Data.Gpos[0].ComputerScope | Where-Object { $_.Type -eq 'SoftwareInstallation' }
            $App | Should -Not -BeNullOrEmpty
        }

        It 'Collects application name' {
            $Result = & $Sut -Variables @{}
            $App = $Result.Data.Gpos[0].ComputerScope | Where-Object { $_.Type -eq 'SoftwareInstallation' }
            $App.Settings.Name | Should -Be '7-Zip 24.08 (x64 edition)'
        }

        It 'Collects MSI path' {
            $Result = & $Sut -Variables @{}
            $App = $Result.Data.Gpos[0].ComputerScope | Where-Object { $_.Type -eq 'SoftwareInstallation' }
            $App.Settings.Path | Should -BeLike '*7z2408-x64.msi'
        }

        It 'Collects deployment type' {
            $Result = & $Sut -Variables @{}
            $App = $Result.Data.Gpos[0].ComputerScope | Where-Object { $_.Type -eq 'SoftwareInstallation' }
            $App.Settings.DeploymentType | Should -Be 'Assigned'
        }
    }

    Context 'Administrative policy collection' {
        BeforeEach {
            Mock Get-CimInstance {
                [PSCustomObject]@{ PartOfDomain = $true; Domain = 'zinneke.be' }
            }
            Mock Import-Module { } -ParameterFilter { $Name -eq 'GroupPolicy' }
            Mock Get-ADDomain { [PSCustomObject]@{ DNSRoot = 'zinneke.be' } }
            Mock Get-GPO {
                @([PSCustomObject]@{
                    DisplayName = 'Lockdown'
                    Id          = [guid]::NewGuid()
                    Description = ''
                    GpoStatus   = 'AllSettingsEnabled'
                })
            }
            Mock Get-GPPermission { @() }
            Mock Get-GPOReport {
                @'
<gpo xmlns="http://www.microsoft.com/GroupPolicy/Settings">
  <Computer><extensionData/></Computer>
  <User>
    <extensionData>
      <Extension>
        <Policy>
          <Name>Remove Task Manager</Name>
          <Category>System/Ctrl+Alt+Del Options</Category>
          <State>Enabled</State>
        </Policy>
        <Policy>
          <Name>Prevent access to the command prompt</Name>
          <Category>System</Category>
          <State>Enabled</State>
        </Policy>
      </Extension>
      <Name>Administrative Templates</Name>
    </extensionData>
  </User>
</gpo>
'@
            }
        }

        It 'Collects Policy type entries in UserScope' {
            $Result = & $Sut -Variables @{}
            $Policies = $Result.Data.Gpos[0].UserScope | Where-Object { $_.Type -eq 'Policy' }
            @($Policies).Count | Should -BeGreaterOrEqual 2
        }

        It 'Collects policy name' {
            $Result = & $Sut -Variables @{}
            $Policies = $Result.Data.Gpos[0].UserScope | Where-Object { $_.Type -eq 'Policy' }
            $Policies.Settings.Name | Should -Contain 'Remove Task Manager'
        }

        It 'Collects policy state' {
            $Result = & $Sut -Variables @{}
            $Policy = $Result.Data.Gpos[0].UserScope |
                Where-Object { $_.Type -eq 'Policy' -and $_.Settings.Name -eq 'Remove Task Manager' }
            $Policy.Settings.State | Should -Be 'Enabled'
        }

        It 'ComputerScope has NoSettings when empty' {
            $Result = & $Sut -Variables @{}
            $NoSettings = $Result.Data.Gpos[0].ComputerScope | Where-Object { $_.Type -eq 'NoSettings' }
            $NoSettings | Should -Not -BeNullOrEmpty
        }
    }
}
