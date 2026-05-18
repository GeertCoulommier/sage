# Evaluations/Gpo.Tests.ps1
# GPO evaluation — tests driven entirely by exam data.
# Contains ONLY assertion logic — no expected values hardcoded.
# Data from exam.psd1 via $ExamVariables; collected data via $CollectedData.
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
    'GPOs'                      = {
        param($Data)
        $Data.Gpos | ForEach-Object {
            [PSCustomObject]@{
                Name   = $_.Name
                Status = $_.Status
                Links  = ($_.Links | ForEach-Object { $_.SOMPath }) -join ', '
            }
        }
    }
    'GPO Software Installation' = {
        param($Data)
        $Data.Gpos | ForEach-Object {
            $GpoName = $_.Name
            ($_.ComputerScope + $_.UserScope) | Where-Object { $_.Type -eq 'SoftwareInstallation' } | ForEach-Object {
                [PSCustomObject]@{
                    GPO            = $GpoName
                    Name           = $_.Settings.Name
                    Path           = $_.Settings.Path
                    DeploymentType = $_.Settings.DeploymentType
                }
            }
        }
    }
    'GPO Drive Maps'            = {
        param($Data)
        $Data.Gpos | ForEach-Object {
            $GpoName = $_.Name
            ($_.ComputerScope + $_.UserScope) | Where-Object { $_.Type -eq 'DriveMap' } | ForEach-Object {
                [PSCustomObject]@{
                    GPO    = $GpoName
                    Name   = $_.Settings.Name
                    Path   = $_.Settings.Path
                    Letter = $_.Settings.Letter
                }
            }
        }
    }
    'GPO Policies'              = {
        param($Data)
        $Data.Gpos | ForEach-Object {
            $GpoName = $_.Name
            ($_.ComputerScope + $_.UserScope) | Where-Object { $_.Type -eq 'Policy' } | ForEach-Object {
                [PSCustomObject]@{
                    GPO      = $GpoName
                    Name     = $_.Settings.Name
                    Category = $_.Settings.Category
                    State    = $_.Settings.State
                }
            }
        }
    }
    'GPO Permissions'           = {
        param($Data)
        $Data.Gpos | ForEach-Object {
            $GpoName = $_.Name
            $_.Permissions | ForEach-Object {
                [PSCustomObject]@{
                    GPO        = $GpoName
                    Trustee    = $_.Trustee
                    Permission = $_.Permission
                }
            }
        }
    }
}

Describe 'GPO Configuration' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.GpoExistenceTests) { $V.GpoExistenceTests = @() }
        if (-not $V.GpoLinkTests) { $V.GpoLinkTests = @() }
        if (-not $V.GpoSoftwareTests) { $V.GpoSoftwareTests = @() }
        if (-not $V.GpoPolicyTests) { $V.GpoPolicyTests = @() }
        if (-not $V.GpoDriveMapTests) { $V.GpoDriveMapTests = @() }
        if (-not $V.GpoScopeTests) { $V.GpoScopeTests = @() }
        if (-not $V.GpoPermissionTests) { $V.GpoPermissionTests = @() }
    }

    Context 'GPO Existence' {
        It 'GPO <GpoName> should exist' -ForEach $V.GpoExistenceTests {
            $MatchingGpo = $CollectedData.Gpos | Where-Object { $_.Name -eq $GpoName }
            $MatchingGpo | Should -Not -BeNullOrEmpty
        }
    }

    Context 'GPO Links' {
        It 'GPO <GpoName> should be linked to <ExpectedLink> and enabled' -ForEach $V.GpoLinkTests {
            $MatchingGpo = $CollectedData.Gpos | Where-Object { $_.Name -eq $GpoName }
            $MatchingGpo | Should -Not -BeNullOrEmpty

            $DomainName = $CollectedData.DomainName
            $EnabledLinks = @($MatchingGpo.Links | Where-Object { $_.Enabled -eq 'true' } | ForEach-Object { $_.SOMPath })

            $RequiredLinks = @()
            if ($ExpectedLinksAll) {
                $RequiredLinks = @($ExpectedLinksAll)
            }
            elseif ($DomainRootLink) {
                $RequiredLinks = @($DomainName)
            }
            elseif ($ExpectedLink) {
                $RequiredLinks = @($ExpectedLink)
            }

            foreach ($RequiredLink in $RequiredLinks) {
                $RequiredLinkMatch = $EnabledLinks | Where-Object {
                    $EnabledPath = ($_ -replace '\\', '/').Trim('/').ToLowerInvariant()
                    $ExpectedPath = ($RequiredLink -replace '\\', '/').Trim('/').ToLowerInvariant()
                    $NormalizedDomain = if ($DomainName) { ($DomainName -replace '\\', '/').Trim('/').ToLowerInvariant() } else { '' }

                    $EnabledPath -eq $ExpectedPath -or
                    ($NormalizedDomain -and $EnabledPath -eq "$NormalizedDomain/$ExpectedPath") -or
                    $EnabledPath -like "*/$ExpectedPath"
                }
                $RequiredLinkMatch | Should -Not -BeNullOrEmpty
            }

            if ($ExpectedLinksAny) {
                $AnyMatch = @($EnabledLinks | Where-Object {
                        $EnabledPath = $_
                        @($ExpectedLinksAny) | Where-Object {
                            $NormalizedEnabled = ($EnabledPath -replace '\\', '/').Trim('/').ToLowerInvariant()
                            $NormalizedExpected = ($_ -replace '\\', '/').Trim('/').ToLowerInvariant()
                            $NormalizedDomain = if ($DomainName) { ($DomainName -replace '\\', '/').Trim('/').ToLowerInvariant() } else { '' }

                            $NormalizedEnabled -eq $NormalizedExpected -or
                            ($NormalizedDomain -and $NormalizedEnabled -eq "$NormalizedDomain/$NormalizedExpected") -or
                            $NormalizedEnabled -like "*/$NormalizedExpected"
                        }
                    })
                $AnyMatch | Should -Not -BeNullOrEmpty
            }

            if ($ForbiddenLinks) {
                foreach ($ForbiddenLink in @($ForbiddenLinks)) {
                    $ForbiddenMatch = $EnabledLinks | Where-Object {
                        $EnabledPath = ($_ -replace '\\', '/').Trim('/').ToLowerInvariant()
                        $ExpectedPath = ($ForbiddenLink -replace '\\', '/').Trim('/').ToLowerInvariant()
                        $NormalizedDomain = if ($DomainName) { ($DomainName -replace '\\', '/').Trim('/').ToLowerInvariant() } else { '' }

                        $EnabledPath -eq $ExpectedPath -or
                        ($NormalizedDomain -and $EnabledPath -eq "$NormalizedDomain/$ExpectedPath") -or
                        $EnabledPath -like "*/$ExpectedPath"
                    }
                    $ForbiddenMatch | Should -BeNullOrEmpty
                }
            }

            if ($ForbiddenDomainRootLink) {
                ($EnabledLinks | Where-Object {
                    $NormalizedEnabled = ($_ -replace '\\', '/').Trim('/').ToLowerInvariant()
                    $NormalizedDomain = if ($DomainName) { ($DomainName -replace '\\', '/').Trim('/').ToLowerInvariant() } else { '' }
                    $NormalizedEnabled -eq $NormalizedDomain
                }) | Should -BeNullOrEmpty
            }
        }
    }

    Context 'GPO Software Installation' {
        It 'GPO <GpoName> should deploy application <AppName>' -ForEach $V.GpoSoftwareTests {
            $MatchingGpo = $CollectedData.Gpos | Where-Object { $_.Name -eq $GpoName }
            $MatchingGpo | Should -Not -BeNullOrEmpty

            $Scope = if ($ScopeType -eq 'Computer') { $MatchingGpo.ComputerScope } else { $MatchingGpo.UserScope }
            $AppPatterns = if ($AppNamePatterns) { @($AppNamePatterns) } elseif ($AppName) { @($AppName) } else { @() }

            $MatchingApp = $Scope | Where-Object {
                if ($_.Type -ne 'SoftwareInstallation') {
                    return $false
                }

                if ($AppPatterns.Count -eq 0) {
                    return $true
                }

                foreach ($Pattern in $AppPatterns) {
                    if ($_.Settings.Name -eq $Pattern -or $_.Settings.Name -like "*$Pattern*") {
                        return $true
                    }
                }

                return $false
            }
            $MatchingApp | Should -Not -BeNullOrEmpty

            $SelectedApp = @($MatchingApp)[0]

            if ($ExpectedPath) {
                foreach ($PathPart in @($ExpectedPath)) {
                    $SelectedApp.Settings.Path | Should -Match ([regex]::Escape($PathPart))
                }
            }

            if ($ExpectedPathRegex) {
                $SelectedApp.Settings.Path | Should -Match $ExpectedPathRegex
            }

            if ($ExpectedFileExtension) {
                $SelectedApp.Settings.Path | Should -Match ([regex]::Escape($ExpectedFileExtension) + '$')
            }

            if ($RequirePathExists) {
                $SelectedApp.Settings.PathExists | Should -BeTrue
            }

            if ($ExpectedDeploymentType) {
                $ActualDeploymentType = if ($SelectedApp.Settings.DeploymentType) {
                    $SelectedApp.Settings.DeploymentType.Trim().ToLowerInvariant()
                }
                else {
                    ''
                }
                $ExpectedDeploymentTypeNormalized = if ($ExpectedDeploymentType) {
                    $ExpectedDeploymentType.Trim().ToLowerInvariant()
                }
                else {
                    ''
                }

                if ($ActualDeploymentType -eq 'assign') {
                    $ActualDeploymentType = 'assigned'
                }
                if ($ExpectedDeploymentTypeNormalized -eq 'assign') {
                    $ExpectedDeploymentTypeNormalized = 'assigned'
                }

                $ActualDeploymentType | Should -Be $ExpectedDeploymentTypeNormalized
            }
        }
    }

    Context 'GPO Administrative Policies' {
        It 'GPO <GpoName> should have policy <PolicyName> in state <ExpectedState>' -ForEach $V.GpoPolicyTests {
            $MatchingGpo = $CollectedData.Gpos | Where-Object { $_.Name -eq $GpoName }
            $MatchingGpo | Should -Not -BeNullOrEmpty

            # If ScopeType is specified, restrict search to that scope; otherwise search both.
            $AllSettings = switch ($ScopeType) {
                'Computer' { $MatchingGpo.ComputerScope }
                'User' { $MatchingGpo.UserScope }
                default { $MatchingGpo.ComputerScope + $MatchingGpo.UserScope }
            }
            $MatchingPolicy = $AllSettings | Where-Object {
                $_.Type -eq 'Policy' -and $_.Settings.Name -eq $PolicyName
            }

            if ($Optional -and -not $MatchingPolicy) {
                Set-ItResult -Skipped -Because "Optional policy '$PolicyName' not configured in GPO '$GpoName'."
                return
            }

            $MatchingPolicy | Should -Not -BeNullOrEmpty

            $SelectedPolicy = @($MatchingPolicy)[0]
            $SelectedPolicy.Settings.State | Should -Be $ExpectedState

            if ($ExpectedPath) {
                $PolicyEvidence = @(
                    $SelectedPolicy.Settings.Path
                    $SelectedPolicy.Settings.RawXml
                ) -join ' '
                foreach ($PathPart in @($ExpectedPath)) {
                    $PolicyEvidence | Should -Match ([regex]::Escape($PathPart))
                }
            }

            if ($ExpectedPathRegex) {
                $PolicyEvidence = @(
                    $SelectedPolicy.Settings.Path
                    $SelectedPolicy.Settings.RawXml
                ) -join ' '
                $PolicyEvidence | Should -Match $ExpectedPathRegex
            }

            if ($RequirePathExists) {
                $SelectedPolicy.Settings.PathExists | Should -BeTrue
            }
        }
    }

    Context 'GPO Drive Mappings' {
        It 'GPO <GpoName> should map drive <DriveLetter> to <DrivePath>' -ForEach $V.GpoDriveMapTests {
            $MatchingGpo = $CollectedData.Gpos | Where-Object { $_.Name -eq $GpoName }
            $MatchingGpo | Should -Not -BeNullOrEmpty

            $AllSettings = $MatchingGpo.ComputerScope + $MatchingGpo.UserScope
            $MatchingDrive = $AllSettings | Where-Object {
                $_.Type -eq 'DriveMap' -and $_.Settings.Letter -eq $DriveLetter
            }
            $MatchingDrive | Should -Not -BeNullOrEmpty

            $SelectedDrive = @($MatchingDrive)[0]

            if ($RequirePathExists) {
                $SelectedDrive.Settings.PathExists | Should -BeTrue
            }

            $ActualDrivePath = (($SelectedDrive.Settings.Path -replace '[\\/]+', '\').Trim()).ToLowerInvariant()
            $ExpectedDrivePath = (($DrivePath -replace '[\\/]+', '\').Trim()).ToLowerInvariant()
            $ActualDrivePath | Should -Be $ExpectedDrivePath
        }
    }

    Context 'GPO Scope Settings' {
        It 'GPO <GpoName> <ScopeType> scope should have <ExpectedSetting>' -ForEach $V.GpoScopeTests {
            $MatchingGpo = $CollectedData.Gpos | Where-Object { $_.Name -eq $GpoName }
            $MatchingGpo | Should -Not -BeNullOrEmpty

            $Scope = if ($ScopeType -eq 'Computer') { $MatchingGpo.ComputerScope } else { $MatchingGpo.UserScope }

            if ($ExpectedSetting -eq 'no settings') {
                $NoSettings = $Scope | Where-Object { $_.Type -eq 'NoSettings' }
                $NoSettings | Should -Not -BeNullOrEmpty
            }
            else {
                $Scope | Where-Object { $_.Type -ne 'NoSettings' } | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'GPO Permissions' {
        It 'GPO <GpoName> should grant <ExpectedPermission> to <TrusteeName>' -ForEach $V.GpoPermissionTests {
            $MatchingGpo = $CollectedData.Gpos | Where-Object { $_.Name -eq $GpoName }
            $MatchingGpo | Should -Not -BeNullOrEmpty

            $MatchingPermission = $MatchingGpo.Permissions | Where-Object {
                $_.Trustee -eq $TrusteeName -and $_.Permission -eq $ExpectedPermission
            }
            $MatchingPermission | Should -Not -BeNullOrEmpty
        }
    }
}
