#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-FileServerCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with shares, permissions,
    and share access information. Uses mocks.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-FileServerCollector.ps1'

    if (-not (Get-Command -Name Get-WindowsFeature -ErrorAction SilentlyContinue)) {
        function global:Get-WindowsFeature { }
    }
    if (-not (Get-Command -Name Get-SmbShare -ErrorAction SilentlyContinue)) {
        function global:Get-SmbShare { }
    }
    if (-not (Get-Command -Name Get-SmbShareAccess -ErrorAction SilentlyContinue)) {
        function global:Get-SmbShareAccess { }
    }
    if (-not (Get-Command -Name Get-Acl -ErrorAction SilentlyContinue)) {
        function global:Get-Acl { }
    }
    if (-not (Get-Command -Name Get-ChildItem -ErrorAction SilentlyContinue)) {
        function global:Get-ChildItem { }
    }
}

Describe 'Invoke-FileServerCollector' -Tag 'Unit' {

    Context 'File Server role not installed' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $false }
            }
        }

        It 'Returns Available=$false' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
        }

        It 'Sets Reason to indicate File Server not installed' {
            $Result = & $Sut -Variables @{}
            $Result.Reason | Should -Match 'File Server role not installed'
        }
    }

    Context 'Feature query fails' {
        BeforeEach {
            Mock Get-WindowsFeature { throw 'Access denied' }
        }

        It 'Returns Available=$false with error reason' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
            $Result.Reason | Should -Match 'Cannot query File Server feature'
        }
    }

    Context 'Successful collection' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $true }
            }
            Mock Get-SmbShare {
                @(
                    [PSCustomObject]@{
                        Name        = 'shared'
                        Path        = 'C:\Shared'
                        Description = 'Shared folder'
                    }
                )
            }
            Mock Get-SmbShareAccess {
                @(
                    [PSCustomObject]@{
                        AccountName       = 'Everyone'
                        AccessControlType = 'Allow'
                        AccessRight       = 'Read'
                    }
                )
            }
            Mock Get-Acl {
                $MockAccess = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'BUILTIN\Users' }
                    FileSystemRights  = 'ReadAndExecute, Synchronize'
                    AccessControlType = 'Allow'
                    IsInherited       = $false
                    InheritanceFlags  = 'ContainerInherit, ObjectInherit'
                    PropagationFlags  = 'None'
                }
                # Add ToString methods to nested objects
                $MockAccess.IdentityReference | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Value } -Force

                [PSCustomObject]@{
                    Owner  = 'BUILTIN\Administrators'
                    Access = @($MockAccess)
                }
            }
            Mock Test-Path { $true }
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        FullName      = 'C:\Shared\public'
                        PSIsContainer = $true
                    }
                    [PSCustomObject]@{
                        Name          = 'wallpaper.jpg'
                        Extension     = '.jpg'
                        FullName      = 'C:\Shared\public\wallpaper.jpg'
                        PSIsContainer = $false
                    }
                )
            } -ParameterFilter {
                $Path -eq 'C:\Shared' -and $Recurse
            }
        }

        It 'Returns Available=$true' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Collects shares filtering system shares' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Shares.Count | Should -Be 1
            $Result.Data.Shares[0].Name | Should -Be 'shared'
        }

        It 'Collects share access' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Shares[0].ShareAccess.Count | Should -Be 1
            $Result.Data.Shares[0].ShareAccess[0].AccountName | Should -Be 'Everyone'
        }

        It 'Collects NTFS permissions' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Permissions.Count | Should -Be 2
            $Result.Data.Permissions[0].ShareName | Should -Be 'shared'
            $Result.Data.Permissions[0].Owner | Should -Be 'BUILTIN\Administrators'
        }

        It 'Collects folder inventory' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Folders | Should -Not -BeNullOrEmpty
            ($Result.Data.Folders | Where-Object { $_.RelativePath -match 'public$' }) | Should -Not -BeNullOrEmpty
        }

        It 'Collects file inventory' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Files | Should -Not -BeNullOrEmpty
            $Result.Data.Files[0].Extension | Should -Be '.jpg'
        }

        It 'Has empty Errors array on clean run' {
            $Result = & $Sut -Variables @{}
            $Result.Errors | Should -HaveCount 0
        }
    }

    Context 'Result structure' {
        BeforeEach {
            Mock Get-WindowsFeature {
                [PSCustomObject]@{ Installed = $true }
            }
            Mock Get-SmbShare { @() }
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
            $Result.Data.Keys | Should -Contain 'Shares'
            $Result.Data.Keys | Should -Contain 'Permissions'
            $Result.Data.Keys | Should -Contain 'Folders'
            $Result.Data.Keys | Should -Contain 'Files'
        }
    }
}
