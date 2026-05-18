#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'Sut',
    Justification = '$Sut is assigned in BeforeAll and consumed inside It blocks; PSScriptAnalyzer cannot see cross-block Pester variable usage.')]
param()
<#
.SYNOPSIS
    Unit tests for the Invoke-DockerCollector script.
.DESCRIPTION
    Tests the collector returns a valid structure with Docker images, containers,
    Dockerfiles, and compose files. Uses mocks to avoid Docker dependency.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Collectors\Invoke-DockerCollector.ps1'

    # Stub docker command
    if (-not (Get-Command -Name docker -ErrorAction SilentlyContinue)) {
        function global:docker { }
    }
}

Describe 'Invoke-DockerCollector' -Tag 'Unit' {

    Context 'Docker not available' {
        BeforeEach {
            Mock docker { $global:LASTEXITCODE = 1; 'Cannot connect to the Docker daemon' } -ParameterFilter { $args[0] -eq 'version' }
        }

        It 'Returns Available=$false' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeFalse
        }

        It 'Sets Reason about Docker unavailability' {
            $Result = & $Sut -Variables @{}
            $Result.Reason | Should -Match 'Docker not available'
        }
    }

    Context 'Successful Docker collection' {
        BeforeEach {
            Mock docker {
                $global:LASTEXITCODE = 0
                if ($args[0] -eq 'version') {
                    '24.0.7'
                }
                elseif ($args[0] -eq 'image') {
                    '{"Repository":"myapp","Tag":"latest","ID":"sha256:abc123","CreatedAt":"2024-01-01 12:00:00","Size":"150MB"}'
                }
                elseif ($args[0] -eq 'container') {
                    '{"Names":"myapp-ctr","Image":"myapp:latest","State":"running","Status":"Up 2 hours","Ports":"0.0.0.0:8080->80/tcp","Mounts":"","LocalVolumes":"0"}'
                }
            }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Returns Available=$true' {
            $Result = & $Sut -Variables @{}
            $Result.Available | Should -BeTrue
        }

        It 'Collects Docker images' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Images.Count | Should -Be 1
            $Result.Data.Images[0].Repository | Should -Be 'myapp'
        }

        It 'Collects Docker containers' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Containers.Count | Should -Be 1
            $Result.Data.Containers[0].Name | Should -Be 'myapp-ctr'
            $Result.Data.Containers[0].State | Should -Be 'running'
        }
    }

    Context 'Dockerfile and compose collection' {
        BeforeEach {
            Mock docker {
                $global:LASTEXITCODE = 0
                if ($args[0] -eq 'version') { '24.0.7' }
            }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Returns empty arrays when no files found' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Dockerfile | Should -HaveCount 0
            $Result.Data.Compose | Should -HaveCount 0
        }
    }

    Context 'Result structure' {
        BeforeEach {
            Mock docker {
                $global:LASTEXITCODE = 0
                if ($args[0] -eq 'version') { '24.0.7' }
            }
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
            $Result.Data.Keys | Should -Contain 'Images'
            $Result.Data.Keys | Should -Contain 'Containers'
            $Result.Data.Keys | Should -Contain 'Dockerfile'
            $Result.Data.Keys | Should -Contain 'Compose'
        }
    }
}
