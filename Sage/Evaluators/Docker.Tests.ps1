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
            $MatchingFile.Content | Should -Match "FROM\s+$([regex]::Escape($ExpectedFrom))"
        }

        It 'Dockerfile at <Path> should contain COPY <ExpectedCopy>' -ForEach ($V.DockerfileTests | Where-Object { $_.ExpectedCopy }) {
            $MatchingFile = $CollectedData.Dockerfile | Where-Object { $_.Path -eq $Path }
            $MatchingFile | Should -Not -BeNullOrEmpty
            $MatchingFile.Content | Should -Match "COPY.*$([regex]::Escape($ExpectedCopy))"
        }
    }

    Context 'Docker Compose' {
        It 'Compose file at <Path> should define services <ExpectedServices>' -ForEach $V.ComposeTests {
            $MatchingFile = $CollectedData.Compose | Where-Object { $_.Path -eq $Path }
            $MatchingFile | Should -Not -BeNullOrEmpty

            foreach ($Service in $ExpectedServices) {
                $MatchingFile.Content | Should -Match "$([regex]::Escape($Service)):"
            }
        }
    }
}
