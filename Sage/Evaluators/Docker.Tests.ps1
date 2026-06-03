# Evaluations/Docker.Tests.ps1
# Docker evaluation — tests driven entirely by exam data.
# Contains ONLY assertion logic — no expected values hardcoded.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExamVariables',
    Justification = 'Injected by the evaluation framework; consumed by Pester test blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CollectedData',
    Justification = 'Injected by the evaluation framework; consumed by Pester test blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ReviewContextMap',
    Justification = 'Consumed by ConvertTo-GradeSummary via Get-Variable after dot-sourcing this file.')]
param(
    [Parameter(Mandatory)][hashtable] $ExamVariables,
    [Parameter(Mandatory)][hashtable] $CollectedData
)

# ── Review Context Map (for Edit-Grade) ──────────────────────────────────────
$ReviewContextMap = @{
    'Docker Images'     = {
        param($Data)
        $Data.Images | ForEach-Object {
            [PSCustomObject]@{
                Repository = $_.Repository
                Tag        = $_.Tag
                Size       = $_.Size
            }
        }
    }
    'Docker Containers' = {
        param($Data)
        $Data.Containers | ForEach-Object {
            [PSCustomObject]@{
                Name  = $_.Name
                Image = $_.Image
                State = $_.State
                Ports = $_.Ports
            }
        }
    }
    'Dockerfiles'       = {
        param($Data)
        $Data.Dockerfile | ForEach-Object {
            [PSCustomObject]@{
                Path    = $_.Path
                Content = $_.Content
            }
        }
    }
    'Compose Files'     = {
        param($Data)
        $Data.Compose | ForEach-Object {
            [PSCustomObject]@{
                Path    = $_.Path
                Content = $_.Content
            }
        }
    }
}

Describe 'Docker Configuration' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.ImageTests) { $V.ImageTests = @() }
        if (-not $V.ContainerTests) { $V.ContainerTests = @() }
        if (-not $V.DockerfileTests) { $V.DockerfileTests = @() }
        if (-not $V.ComposeTests) { $V.ComposeTests = @() }
        if (-not $V.ContainerPortTests) { $V.ContainerPortTests = @() }
        if (-not $V.ContainerVolumeTests) { $V.ContainerVolumeTests = @() }
        if (-not $V.ComposeContentTests) { $V.ComposeContentTests = @() }
        if (-not $V.CurlTests) { $V.CurlTests = @() }
        if (-not $V.FileContentTests) { $V.FileContentTests = @() }
    }

    Context 'Docker Images' {
        It 'Image <Repository>:<Tag> should exist' -ForEach $V.ImageTests {
            $ExpectedTag = if ($Tag) { $Tag } else { 'latest' }
            $MatchingImage = $CollectedData.Images | Where-Object {
                $_.Repository -eq $Repository -and $_.Tag -eq $ExpectedTag
            }
            $MatchingImage | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Docker Containers' {
        It 'Container <Name> should exist with image <Image>' -ForEach ($V.ContainerTests | Where-Object { $_.Image }) {
            $MatchingContainer = $CollectedData.Containers | Where-Object {
                $_.Name -eq $Name -and $_.Image -match [regex]::Escape($Image)
            }
            $MatchingContainer | Should -Not -BeNullOrEmpty
        }

        It 'Container <Name> should be in state <State>' -ForEach ($V.ContainerTests | Where-Object { $_.State }) {
            $MatchingContainer = $CollectedData.Containers | Where-Object { $_.Name -eq $Name }
            $MatchingContainer | Should -Not -BeNullOrEmpty
            $MatchingContainer.State | Should -Be $State
        }
    }

    Context 'Dockerfiles' {
        It 'Dockerfile at <Path> should contain FROM <ExpectedFrom>' -ForEach ($V.DockerfileTests | Where-Object { $_.ExpectedFrom }) {
            $MatchingFile = $CollectedData.Dockerfile | Where-Object { $_.Path -eq $Path }
            $MatchingFile | Should -Not -BeNullOrEmpty
            @($MatchingFile.FROM) | Where-Object { $_ -match $ExpectedFrom } | Should -Not -BeNullOrEmpty -Because "FROM $ExpectedFrom was not found in Dockerfile at $Path"
        }

        It 'Dockerfile at <Path> should contain COPY <ExpectedCopy>' -ForEach ($V.DockerfileTests | Where-Object { $_.ExpectedCopy }) {
            $MatchingFile = $CollectedData.Dockerfile | Where-Object { $_.Path -eq $Path }
            $MatchingFile | Should -Not -BeNullOrEmpty
            @($MatchingFile.COPY) | Where-Object { $_ -match ([regex]::Escape($ExpectedCopy)) } | Should -Not -BeNullOrEmpty -Because "COPY $ExpectedCopy was not found in Dockerfile at $Path"
        }
    }

    Context 'Docker Compose' {
        It 'Compose file at <Path> should define services <ExpectedServices>' -ForEach $V.ComposeTests {
            $AllowedComposeNames = @('compose.yml', 'compose.yaml', 'docker-compose.yml', 'docker-compose.yaml')
            $Dir = [System.IO.Path]::GetDirectoryName($Path)
            $MatchingFile = $CollectedData.Compose | Where-Object {
                $FName = [System.IO.Path]::GetFileName($_.Path)
                $FDir  = [System.IO.Path]::GetDirectoryName($_.Path)
                $FDir -eq $Dir -and $AllowedComposeNames -contains $FName.ToLower()
            }
            $MatchingFile | Should -Not -BeNullOrEmpty -Because "No compose file found in $Dir"

            foreach ($Service in $ExpectedServices) {
                @($MatchingFile.services.Keys) | Should -Contain $Service
            }
        }
    }

    Context 'Container Ports' {
        It 'Container <Name> should map host port <HostPort> to container port <ContainerPort>' -ForEach $V.ContainerPortTests {
            $MatchingContainer = $CollectedData.Containers | Where-Object { $_.Name -eq $Name }
            $MatchingContainer | Should -Not -BeNullOrEmpty
            $MatchingContainer.Ports | Should -Match "$([regex]::Escape($HostPort))->$([regex]::Escape($ContainerPort))"
        }
    }

    Context 'Container Volumes' {
        It 'Container <Name> should mount <HostPath> at <ContainerPath>' -ForEach $V.ContainerVolumeTests {
            $MatchingContainer = $CollectedData.Containers | Where-Object { $_.Name -eq $Name }
            $MatchingContainer | Should -Not -BeNullOrEmpty
            $AllowedSources = if ($AllowedHostPaths) { @($AllowedHostPaths) } else { @($HostPath) }
            if ($MatchingContainer.VolumeMounts -and @($MatchingContainer.VolumeMounts).Count -gt 0) {
                $MatchingMount = $MatchingContainer.VolumeMounts | Where-Object {
                    $_.Destination -eq $ContainerPath -and $_.Source -in $AllowedSources
                }
                $MatchingMount | Should -Not -BeNullOrEmpty -Because "Expected a bind mount from one of [$($AllowedSources -join ', ')] to $ContainerPath"
            }
            else {
                # Fallback when docker inspect data is unavailable: check Mounts string (host path only)
                $SourceMatch = $AllowedSources | Where-Object { $MatchingContainer.Mounts -match [regex]::Escape($_) }
                $SourceMatch | Should -Not -BeNullOrEmpty -Because "Expected Mounts to match one of: $($AllowedSources -join ', ')"
            }
        }
    }

    Context 'Compose File Content' {
        It 'Compose file at <Path> should have key <Key> containing <ContainsValue>' -ForEach $V.ComposeContentTests {
            $AllowedComposeNames = @('compose.yml', 'compose.yaml', 'docker-compose.yml', 'docker-compose.yaml')
            $Dir = [System.IO.Path]::GetDirectoryName($Path)
            $MatchingFile = $CollectedData.Compose | Where-Object {
                $FName = [System.IO.Path]::GetFileName($_.Path)
                $FDir  = [System.IO.Path]::GetDirectoryName($_.Path)
                $FDir -eq $Dir -and $AllowedComposeNames -contains $FName.ToLower()
            }
            $MatchingFile | Should -Not -BeNullOrEmpty -Because "No compose file found in $Dir"

            $Found = $false
            if ($MatchingFile.services -is [hashtable]) {
                foreach ($SvcName in $MatchingFile.services.Keys) {
                    $SvcData = $MatchingFile.services[$SvcName]
                    if ($SvcData -is [hashtable] -and $SvcData.ContainsKey($Key)) {
                        $Val = $SvcData[$Key]
                        if ($Val -is [array]) {
                            if ($Val | Where-Object { $_ -eq $ContainsValue -or $_ -match [regex]::Escape($ContainsValue) }) {
                                $Found = $true
                                break
                            }
                        } else {
                            if ($Val -eq $ContainsValue -or ($Val -and $Val -match [regex]::Escape($ContainsValue))) {
                                $Found = $true
                                break
                            }
                        }
                    }
                }
            }
            $Found | Should -BeTrue -Because "Expected to find key '$Key' containing '$ContainsValue' in any service of the compose file"
        }
    }

    Context 'Docker Curl Tests' {
        It 'GET <Url> should return expected content' -ForEach $V.CurlTests {
            $MatchingResult = $CollectedData.CurlResults | Where-Object { $_.Url -eq $Url }
            $MatchingResult | Should -Not -BeNullOrEmpty
            $MatchingResult.Content | Should -Match ([regex]::Escape($ExpectedContent))
        }
    }

    Context 'Docker File Content Tests' {
        It 'File at <Path> should contain expected content' -ForEach $V.FileContentTests {
            $MatchingFile = $CollectedData.FileContents | Where-Object { $_.Path -eq $Path }
            $MatchingFile | Should -Not -BeNullOrEmpty
            $MatchingFile.Content | Should -Match ([regex]::Escape($ExpectedContent))
        }
    }
}
