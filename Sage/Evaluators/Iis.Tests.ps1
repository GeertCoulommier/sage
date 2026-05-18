# Evaluations/Iis.Tests.ps1
# IIS evaluation — tests driven entirely by exam data.
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
    'IIS Websites'  = {
        param($Data)
        $Data.Websites | ForEach-Object {
            [PSCustomObject]@{
                Name        = $_.Name
                State       = $_.State
                AppPoolName = $_.AppPoolName
                Bindings    = ($_.Bindings | ForEach-Object { $_.Uri }) -join ', '
            }
        }
    }
    'IIS App Pools' = {
        param($Data)
        $Data.AppPools | ForEach-Object {
            [PSCustomObject]@{
                Name           = $_.Name
                State          = $_.State
                PipelineMode   = $_.PipelineMode
                RuntimeVersion = $_.RuntimeVersion
            }
        }
    }
}

Describe 'IIS Configuration' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.WebsiteTests) { $V.WebsiteTests = @() }
        if (-not $V.BindingTests) { $V.BindingTests = @() }
        if (-not $V.VirtualDirectoryTests) { $V.VirtualDirectoryTests = @() }
        if (-not $V.AppPoolTests) { $V.AppPoolTests = @() }
    }

    Context 'IIS Websites' {
        It 'Website <Name> should exist and be <State>' -ForEach $V.WebsiteTests {
            $Site = $CollectedData.Websites | Where-Object { $_.Name -eq $Name }
            $Site | Should -Not -BeNullOrEmpty
            if ($State) {
                $Site.State | Should -Be $State
            }
        }
    }

    Context 'IIS Bindings' {
        It 'Website <SiteName> should have binding matching <ExpectedUri>' -ForEach $V.BindingTests {
            $Site = $CollectedData.Websites | Where-Object { $_.Name -eq $SiteName }
            $Site | Should -Not -BeNullOrEmpty
            $AllUris = $Site.Bindings | ForEach-Object { $_.Uri }
            $Match = $AllUris | Where-Object { $_ -match [regex]::Escape($ExpectedUri) }
            $Match | Should -Not -BeNullOrEmpty
        }
    }

    Context 'IIS Virtual Directories' {
        It 'Website <SiteName> should have virtual directory <VDirPath>' -ForEach $V.VirtualDirectoryTests {
            $Site = $CollectedData.Websites | Where-Object { $_.Name -eq $SiteName }
            $Site | Should -Not -BeNullOrEmpty
            $VDir = $Site.VirtualDirectories | Where-Object { $_.VDirPath -eq $VDirPath }
            $VDir | Should -Not -BeNullOrEmpty
            if ($PhysicalPath) {
                $VDir.PhysicalPath | Should -BeLike $PhysicalPath
            }
        }
    }

    Context 'IIS Application Pools' {
        It 'App pool <Name> should exist' -ForEach $V.AppPoolTests {
            $Pool = $CollectedData.AppPools | Where-Object { $_.Name -eq $Name }
            $Pool | Should -Not -BeNullOrEmpty
            if ($PipelineMode) {
                $Pool.PipelineMode | Should -Be $PipelineMode
            }
        }
    }
}
