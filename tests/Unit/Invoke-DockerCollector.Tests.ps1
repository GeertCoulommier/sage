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
                elseif ($args[0] -eq 'inspect') {
                    '[]'
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

        It 'Reads Dockerfile from explicit path in DockerfileTests when search finds nothing' {
            Mock Test-Path {
                param($Path)
                $Path -eq '/home/student/httpd_docker/Dockerfile'
            }
            Mock Get-Content {
                param($Path)
                @('FROM httpd:latest', 'COPY ./index.html /usr/local/apache2/htdocs/')
            } -ParameterFilter { $Path -eq '/home/student/httpd_docker/Dockerfile' }

            $Vars = @{
                DockerfileTests = @(
                    @{ Path = '/home/student/httpd_docker/Dockerfile'; ExpectedFrom = 'httpd'; PassGrade = 5 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.Dockerfile | Should -HaveCount 1
            $Result.Data.Dockerfile[0].Path    | Should -Be '/home/student/httpd_docker/Dockerfile'
            $Result.Data.Dockerfile[0].Content | Should -Match 'FROM httpd'
            $Result.Data.Dockerfile[0].FROM    | Should -Be 'httpd:latest'
            $Result.Data.Dockerfile[0].COPY    | Should -Be './index.html /usr/local/apache2/htdocs/'
        }

        It 'Deduplicates Dockerfile paths when same path appears in multiple DockerfileTests entries' {
            Mock Test-Path {
                param($Path)
                $Path -eq '/home/student/httpd_docker/Dockerfile'
            }
            Mock Get-Content {
                param($Path)
                @('FROM httpd:latest')
            } -ParameterFilter { $Path -eq '/home/student/httpd_docker/Dockerfile' }

            $Vars = @{
                DockerfileTests = @(
                    @{ Path = '/home/student/httpd_docker/Dockerfile'; ExpectedFrom = 'httpd'; PassGrade = 5 }
                    @{ Path = '/home/student/httpd_docker/Dockerfile'; ExpectedCopy = 'index.html /usr/local/apache2/htdocs/'; PassGrade = 4 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.Dockerfile | Should -HaveCount 1
        }

        It 'Reads compose file from explicit path in ComposeTests when search finds nothing' {
            Mock Test-Path {
                param($Path)
                $Path -eq '/home/student/volumetest/docker-compose.yml'
            }
            Mock Get-Content {
                param($Path)
                @('services:', '  volumetest:', '    image: nginx')
            } -ParameterFilter { $Path -eq '/home/student/volumetest/docker-compose.yml' }

            $Vars = @{
                ComposeTests = @(
                    @{ Path = '/home/student/volumetest/docker-compose.yml'; ExpectedServices = @('volumetest'); PassGrade = 5 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.Compose | Should -HaveCount 1
            $Result.Data.Compose[0].Path | Should -Be '/home/student/volumetest/docker-compose.yml'
        }

        It 'Parses Dockerfile instructions as individual structured keys' {
            Mock Test-Path {
                param($Path)
                $Path -eq '/home/student/app/Dockerfile'
            }
            Mock Get-Content {
                param($Path)
                @('FROM node:20-alpine', 'COPY package.json /app/', 'COPY src/ /app/src/')
            } -ParameterFilter { $Path -eq '/home/student/app/Dockerfile' }

            $Vars = @{
                DockerfileTests = @(
                    @{ Path = '/home/student/app/Dockerfile'; ExpectedFrom = 'node'; PassGrade = 3 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.Dockerfile[0].FROM | Should -Be 'node:20-alpine'
            $Result.Data.Dockerfile[0].COPY | Should -HaveCount 2
            @($Result.Data.Dockerfile[0].COPY) | Should -Contain 'package.json /app/'
        }

        It 'Parses compose YAML services via native PowerShell parser' {
            Mock Test-Path {
                param($Path)
                $Path -eq '/home/student/volumetest/compose.yml'
            }
            Mock Get-Content {
                param($Path)
                @('services:', '  nginx:', '    image: nginx:latest', '    container_name: volumetest')
            } -ParameterFilter { $Path -eq '/home/student/volumetest/compose.yml' }

            $Vars = @{
                ComposeTests = @(
                    @{ Path = '/home/student/volumetest/compose.yml'; ExpectedServices = @('nginx'); PassGrade = 0 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.Compose | Should -HaveCount 1
            @($Result.Data.Compose[0].services.Keys) | Should -Contain 'nginx'
            $Result.Data.Compose[0].services['nginx']['image'] | Should -Be 'nginx:latest'
        }

        It 'Parses compose service list properties (ports, volumes) as arrays' {
            Mock Test-Path {
                param($Path)
                $Path -eq '/home/student/volumetest/compose.yml'
            }
            Mock Get-Content {
                param($Path)
                @(
                    'services:',
                    '  nginx:',
                    '    image: nginx:latest',
                    '    container_name: volumetest',
                    '    ports:',
                    '      - "8082:80"',
                    '    volumes:',
                    '      - /home/student/volumetest/html:/usr/share/nginx/html'
                )
            } -ParameterFilter { $Path -eq '/home/student/volumetest/compose.yml' }

            $Vars = @{
                ComposeTests = @(
                    @{ Path = '/home/student/volumetest/compose.yml'; ExpectedServices = @('nginx'); PassGrade = 0 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $SvcData = $Result.Data.Compose[0].services['nginx']
            $SvcData['ports'] | Should -HaveCount 1
            @($SvcData['ports']) | Should -Contain '8082:80'
            $SvcData['volumes'] | Should -HaveCount 1
            @($SvcData['volumes']) | Should -Contain '/home/student/volumetest/html:/usr/share/nginx/html'
        }

        It 'Collects compose file discovered under alternate filename (docker-compose.yml)' {
            Mock Test-Path {
                param($Path)
                $Path -eq '/home/student' -or $Path -eq '/home/student/volumetest/docker-compose.yml'
            }
            Mock Get-ChildItem {
                param($Path, $Recurse, $Include, $ErrorAction)
                if ($Include -contains 'compose.yml') {
                    [PSCustomObject]@{ FullName = '/home/student/volumetest/docker-compose.yml' }
                }
            }
            Mock Get-Content {
                param($Path)
                @('services:', '  nginx:', '    image: nginx:latest')
            } -ParameterFilter { $Path -eq '/home/student/volumetest/docker-compose.yml' }

            $Result = & $Sut -Variables @{}
            $Result.Data.Compose | Should -HaveCount 1
            $Result.Data.Compose[0].Path | Should -Be '/home/student/volumetest/docker-compose.yml'
        }
    }

    Context 'Volume mount enrichment' {
        BeforeEach {
            Mock docker {
                $global:LASTEXITCODE = 0
                if ($args[0] -eq 'version') { '24.0.7' }
                elseif ($args[0] -eq 'container') {
                    '{"Names":"volumetest","Image":"nginx:latest","State":"running","Status":"Up 1 hour","Ports":"8082->80/tcp","Mounts":"/home/student/volumetest/html","LocalVolumes":"0"}'
                }
                elseif ($args[0] -eq 'inspect') {
                    '[{"Type":"bind","Source":"/home/student/volumetest/html","Destination":"/usr/share/nginx/html"}]'
                }
            }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Enriches containers with VolumeMounts from docker inspect' {
            $Result = & $Sut -Variables @{}
            $Result.Data.Containers | Should -HaveCount 1
            $Result.Data.Containers[0].VolumeMounts | Should -HaveCount 1
            $Result.Data.Containers[0].VolumeMounts[0].Source | Should -Be '/home/student/volumetest/html'
            $Result.Data.Containers[0].VolumeMounts[0].Destination | Should -Be '/usr/share/nginx/html'
        }

        It 'Sets VolumeMounts to empty array when docker inspect returns empty' {
            Mock docker {
                $global:LASTEXITCODE = 0
                if ($args[0] -eq 'version') { '24.0.7' }
                elseif ($args[0] -eq 'container') {
                    '{"Names":"bare-ctr","Image":"alpine","State":"running","Status":"Up 1 min","Ports":"","Mounts":"","LocalVolumes":"0"}'
                }
                elseif ($args[0] -eq 'inspect') { '[]' }
            }
            $Result = & $Sut -Variables @{}
            $Result.Data.Containers[0].VolumeMounts | Should -HaveCount 0
        }
    }

    Context 'File content AllowedPaths' {
        BeforeEach {
            Mock docker {
                $global:LASTEXITCODE = 0
                if ($args[0] -eq 'version') { '24.0.7' }
            }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Reads file from second AllowedPath when primary does not exist' {
            Mock Test-Path {
                param($Path)
                $Path -eq '/home/student/volumetest/html/index.html'
            }
            Mock Get-Content {
                'volumetest content'
            } -ParameterFilter { $Path -eq '/home/student/volumetest/html/index.html' }

            $Vars = @{
                FileContentTests = @(
                    @{
                        Path            = '/home/student/volumetest/index.html'
                        AllowedPaths    = @('/home/student/volumetest/index.html', '/home/student/volumetest/html/index.html')
                        ExpectedContent = 'volumetest'
                        PassGrade       = 5
                    }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.FileContents | Should -HaveCount 1
            $Result.Data.FileContents[0].Path    | Should -Be '/home/student/volumetest/index.html'
            $Result.Data.FileContents[0].Content | Should -Match 'volumetest'
        }

        It 'Falls back to empty content when no AllowedPath exists' {
            $Vars = @{
                FileContentTests = @(
                    @{
                        Path            = '/home/student/volumetest/index.html'
                        AllowedPaths    = @('/home/student/volumetest/index.html', '/home/student/volumetest/html/index.html')
                        ExpectedContent = 'volumetest'
                        PassGrade       = 5
                    }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.FileContents | Should -HaveCount 1
            $Result.Data.FileContents[0].Path    | Should -Be '/home/student/volumetest/index.html'
            $Result.Data.FileContents[0].Content | Should -Be ''
        }
    }

    Context 'Curl tests' {
        BeforeEach {
            Mock docker {
                $global:LASTEXITCODE = 0
                if ($args[0] -eq 'version') { '24.0.7' }
            }
            Mock Test-Path { $false }
            Mock Get-ChildItem { @() }
        }

        It 'Stores curl output as a single joined string' {
            Mock curl { @('<html>', '<body>apache in docker</body>', '</html>') }

            $Vars = @{
                CurlTests = @(
                    @{ Url = 'http://192.168.1.2:8081'; ExpectedContent = 'apache in docker'; PassGrade = 12 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.CurlResults | Should -HaveCount 1
            $Result.Data.CurlResults[0].Content | Should -BeOfType [string]
            $Result.Data.CurlResults[0].Content | Should -Match 'apache in docker'
        }

        It 'Sets Success=$true when curl succeeds' {
            Mock curl { 'OK' }

            $Vars = @{
                CurlTests = @(
                    @{ Url = 'http://192.168.1.2:8081'; ExpectedContent = 'OK'; PassGrade = 5 }
                )
            }
            $Result = & $Sut -Variables $Vars
            $Result.Data.CurlResults[0].Success | Should -BeTrue
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
