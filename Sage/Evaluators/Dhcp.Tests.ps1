# Evaluations/Dhcp.Tests.ps1
# DHCP evaluation — tests driven entirely by exam data.
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
    'DHCP Server' = {
        param($Data)
        [PSCustomObject]@{
            RoleInstalled      = $Data.RoleInstalled
            IsAuthorized       = $Data.IsAuthorized
            AllowFilterEnabled = $Data.Filters.AllowEnabled
            DenyFilterEnabled  = $Data.Filters.DenyEnabled
            ScopeCount         = $Data.Scopes.Count
        }
    }
    'DHCP Scopes' = {
        param($Data)
        $Data.Scopes | ForEach-Object {
            [PSCustomObject]@{
                ScopeId    = $_.ScopeId
                Name       = $_.Name
                StartRange = $_.StartRange
                EndRange          = $_.EndRange
                SubnetMask        = $_.SubnetMask
                State             = $_.State
                LeaseDurationDays = $_.LeaseDurationDays
            }
        }
    }
    'Exclusion Ranges' = {
        param($Data)
        $Data.Scopes | ForEach-Object {
            $Scope = $_
            $Scope.Exclusions | ForEach-Object {
                [PSCustomObject]@{
                    ScopeId    = $Scope.ScopeId
                    StartRange = $_.StartRange
                    EndRange   = $_.EndRange
                }
            }
        }
    }
    'Scope Options' = {
        param($Data)
        $Data.Scopes | ForEach-Object {
            $Scope = $_
            $Scope.Options | ForEach-Object {
                [PSCustomObject]@{
                    ScopeId = $Scope.ScopeId
                    Name    = $_.Name
                    Value   = ($_.Value -join ', ')
                }
            }
        }
    }
    'Reservations' = {
        param($Data)
        $Data.Scopes | ForEach-Object {
            $Scope = $_
            $Scope.Reservations | ForEach-Object {
                [PSCustomObject]@{
                    ScopeId   = $Scope.ScopeId
                    IPAddress = $_.IPAddress
                    Name      = $_.Name
                }
            }
        }
    }
}

Describe 'DHCP Configuration' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.RoleTests) { $V.RoleTests = @() }
        if (-not $V.ServerTests) { $V.ServerTests = @() }
        if (-not $V.ScopeTests) { $V.ScopeTests = @() }
        if (-not $V.ExclusionTests) { $V.ExclusionTests = @() }
        if (-not $V.OptionTests) { $V.OptionTests = @() }
        if (-not $V.ReservationTests) { $V.ReservationTests = @() }
        if (-not $V.FilterTests) { $V.FilterTests = @() }
    }

    Context 'DHCP Role' {
        It 'DHCP server role is installed' -ForEach $V.RoleTests {
            $CollectedData.RoleInstalled | Should -BeTrue
        }
    }

    Context 'DHCP Server' {
        It 'DHCP server is authorized' -ForEach $V.ServerTests {
            $Expected = if ($null -ne $ExpectedAuthorized) { [bool]$ExpectedAuthorized } else { $true }
            $CollectedData.IsAuthorized | Should -Be $Expected
        }
    }

    Context 'DHCP Scopes' {
        It 'Scope <ScopeId> should have range <StartRange> to <EndRange>' -ForEach $V.ScopeTests {
            $MatchingScope = $CollectedData.Scopes | Where-Object {
                $_.ScopeId -eq $ScopeId
            }
            $MatchingScope | Should -Not -BeNullOrEmpty
            $MatchingScope.StartRange | Should -Be $StartRange
            $MatchingScope.EndRange | Should -Be $EndRange
        }

        It 'Scope <ScopeId> should have subnet mask <SubnetMask>' -ForEach ($V.ScopeTests | Where-Object { $_.SubnetMask }) {
            $MatchingScope = $CollectedData.Scopes | Where-Object {
                $_.ScopeId -eq $ScopeId
            }
            $MatchingScope | Should -Not -BeNullOrEmpty
            $MatchingScope.SubnetMask | Should -Be $SubnetMask
        }

        It 'Scope <ScopeId> should be named <Name>' -ForEach ($V.ScopeTests | Where-Object { $_.Name }) {
            $MatchingScope = $CollectedData.Scopes | Where-Object {
                $_.ScopeId -eq $ScopeId
            }
            $MatchingScope | Should -Not -BeNullOrEmpty
            $MatchingScope.Name | Should -Be $Name
        }

        It 'Scope <ScopeId> should be in state <State>' -ForEach ($V.ScopeTests | Where-Object { $_.State }) {
            $MatchingScope = $CollectedData.Scopes | Where-Object {
                $_.ScopeId -eq $ScopeId
            }
            $MatchingScope | Should -Not -BeNullOrEmpty
            $MatchingScope.State | Should -Be $State
        }

        It 'Scope <ScopeId> should have lease duration of <LeaseDurationDays> days' -ForEach ($V.ScopeTests | Where-Object { $_.ContainsKey('LeaseDurationDays') }) {
            $MatchingScope = $CollectedData.Scopes | Where-Object {
                $_.ScopeId -eq $ScopeId
            }
            $MatchingScope | Should -Not -BeNullOrEmpty
            $MatchingScope.LeaseDurationDays | Should -Be $LeaseDurationDays
        }
    }

    Context 'Exclusion Ranges' {
        It 'Scope <ScopeId> should have exclusion <StartRange> to <EndRange>' -ForEach $V.ExclusionTests {
            $MatchingScope = $CollectedData.Scopes | Where-Object {
                $_.ScopeId -eq $ScopeId
            }
            $MatchingScope | Should -Not -BeNullOrEmpty
            $MatchingExclusion = $MatchingScope.Exclusions | Where-Object {
                $_.StartRange -eq $StartRange -and $_.EndRange -eq $EndRange
            }
            $MatchingExclusion | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Scope Options' {
        It 'Scope <ScopeId> option <OptionName> should contain <ExpectedValue>' -ForEach $V.OptionTests {
            $MatchingScope = $CollectedData.Scopes | Where-Object {
                $_.ScopeId -eq $ScopeId
            }
            $MatchingScope | Should -Not -BeNullOrEmpty
            $MatchingOption = $MatchingScope.Options | Where-Object {
                $_.Name -eq $OptionName
            }
            $MatchingOption | Should -Not -BeNullOrEmpty
            $ResolvedExpectedValue = $ExpectedValue
            if ($ExpectedValueFrom -eq 'DomainName') {
                $ResolvedExpectedValue = $CollectedData.DomainName
            }

            $ResolvedExpectedValue | Should -Not -BeNullOrEmpty
            $MatchingOption.Value | Should -Contain $ResolvedExpectedValue
        }
    }

    Context 'Reservations' {
        It 'Scope <ScopeId> should have reservation for <IPAddress>' -ForEach $V.ReservationTests {
            $MatchingScope = $CollectedData.Scopes | Where-Object {
                $_.ScopeId -eq $ScopeId
            }
            $MatchingScope | Should -Not -BeNullOrEmpty
            $MatchingReservation = $MatchingScope.Reservations | Where-Object {
                $_.IPAddress -eq $IPAddress
            }
            $MatchingReservation | Should -Not -BeNullOrEmpty

            if ($Name) {
                $MatchingReservation.Name | Should -Be $Name
            }
        }
    }

    Context 'Filters' {
        It '<FilterType> filter should be enabled = <ExpectedEnabled>' -ForEach $V.FilterTests {
            $Actual = switch ($FilterType) {
                'Allow' { $CollectedData.Filters.AllowEnabled }
                'Deny' { $CollectedData.Filters.DenyEnabled }
                default { throw "Unknown FilterType '$FilterType'. Use 'Allow' or 'Deny'." }
            }
            $Actual | Should -Be ([bool]$ExpectedEnabled)
        }
    }
}
