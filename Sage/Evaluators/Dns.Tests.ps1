# Evaluations/Dns.Tests.ps1
# Comprehensive DNS evaluation — tests driven entirely by exam data.
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
    'SOA Records' = {
        param($Data)
        $Data.Records | Where-Object { $_.RecordType -eq 'SOA' } | ForEach-Object {
            [PSCustomObject]@{
                ZoneName = $_.ZoneName
                Value    = $_.Value
            }
        }
    }
    'Subdomain' = {
        param($Data)
        $Data.Records | ForEach-Object {
            [PSCustomObject]@{
                ZoneName   = $_.ZoneName
                HostName   = $_.HostName
                RecordType = $_.RecordType
            }
        }
    }
    'Delegated Domain' = {
        param($Data)
        $Data.Records | Where-Object { $_.RecordType -eq 'NS' } | ForEach-Object {
            [PSCustomObject]@{
                ZoneName = $_.ZoneName
                HostName = $_.HostName
                Value    = $_.Value
            }
        }
    }
    'Forward Zones' = {
        param($Data)
        $Data.Zones | Where-Object { -not $_.IsReverseLookupZone } | ForEach-Object {
            [PSCustomObject]@{
                ZoneName       = $_.ZoneName
                ZoneType       = $_.ZoneType
                IsDsIntegrated = $_.IsDsIntegrated
            }
        }
    }
    'Reverse Zones' = {
        param($Data)
        $Data.Zones | Where-Object { $_.IsReverseLookupZone } | ForEach-Object {
            [PSCustomObject]@{
                ZoneName       = $_.ZoneName
                ZoneType       = $_.ZoneType
                IsDsIntegrated = $_.IsDsIntegrated
            }
        }
    }
    'A Records' = {
        param($Data)
        $Data.Records | Where-Object { $_.RecordType -eq 'A' } | ForEach-Object {
            [PSCustomObject]@{
                HostName = $_.HostName
                Value    = $_.Value
                ZoneName = $_.ZoneName
            }
        }
    }
    'CNAME Records' = {
        param($Data)
        $Data.Records | Where-Object { $_.RecordType -eq 'CNAME' } | ForEach-Object {
            [PSCustomObject]@{
                HostName = $_.HostName
                Value    = $_.Value
                ZoneName = $_.ZoneName
            }
        }
    }
    'MX Records' = {
        param($Data)
        $Data.Records | Where-Object { $_.RecordType -eq 'MX' } | ForEach-Object {
            [PSCustomObject]@{
                HostName = $_.HostName
                Value    = $_.Value
                ZoneName = $_.ZoneName
            }
        }
    }
    'NS Records' = {
        param($Data)
        $Data.Records | Where-Object { $_.RecordType -eq 'NS' } | ForEach-Object {
            [PSCustomObject]@{
                HostName = $_.HostName
                Value    = $_.Value
                ZoneName = $_.ZoneName
            }
        }
    }
    'PTR Records' = {
        param($Data)
        $Data.Records | Where-Object { $_.RecordType -eq 'PTR' } | ForEach-Object {
            [PSCustomObject]@{
                HostName = $_.HostName
                Value    = $_.Value
                ZoneName = $_.ZoneName
            }
        }
    }
    'Forwarders' = {
        param($Data)
        $Data.Forwarders | ForEach-Object {
            [PSCustomObject]@{
                IPAddress = $_.IPAddress
            }
        }
    }
}

Describe 'DNS Configuration' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.ForwardZones) { $V.ForwardZones = @() }
        if (-not $V.ReverseZones) { $V.ReverseZones = @() }
        if (-not $V.ARecords) { $V.ARecords = @() }
        if (-not $V.CnameRecords) { $V.CnameRecords = @() }
        if (-not $V.MxRecords) { $V.MxRecords = @() }
        if (-not $V.NsRecords) { $V.NsRecords = @() }
        if (-not $V.PtrRecords) { $V.PtrRecords = @() }
        if (-not $V.Forwarders) { $V.Forwarders = @() }
        if (-not $V.SoaTests) { $V.SoaTests = @() }
        if (-not $V.SubdomainTests) { $V.SubdomainTests = @() }
        if (-not $V.DelegationTests) { $V.DelegationTests = @() }
        if (-not $V.ForwarderSetTests) { $V.ForwarderSetTests = @() }
    }

    Context 'Forward Zones' {
        It 'Zone <ZoneName> exists as <ZoneType>' -ForEach $V.ForwardZones {
            $MatchingZone = $CollectedData.Zones | Where-Object {
                $_.ZoneName -eq $ZoneName -and
                $_.ZoneType -eq $ZoneType -and
                -not $_.IsReverseLookupZone
            }
            $MatchingZone | Should -Not -BeNullOrEmpty
        }

        It 'Zone <ZoneName> dynamic update is <DynamicUpdate>' -ForEach (
            $V.ForwardZones | Where-Object { $_.DynamicUpdate }
        ) {
            $MatchingZone = $CollectedData.Zones | Where-Object {
                $_.ZoneName -eq $ZoneName -and -not $_.IsReverseLookupZone
            }
            $MatchingZone | Should -Not -BeNullOrEmpty
            $MatchingZone.DynamicUpdate | Should -Be $DynamicUpdate
        }

        It 'Zone <ZoneName> zone transfer policy is <SecureSecondaries>' -ForEach (
            $V.ForwardZones | Where-Object { $_.SecureSecondaries }
        ) {
            $MatchingZone = $CollectedData.Zones | Where-Object {
                $_.ZoneName -eq $ZoneName -and -not $_.IsReverseLookupZone
            }
            $MatchingZone | Should -Not -BeNullOrEmpty
            $MatchingZone.SecureSecondaries | Should -Be $SecureSecondaries
        }
    }

    Context 'Reverse Zones' {
        It 'Reverse zone <ZoneName> exists as <ZoneType>' -ForEach $V.ReverseZones {
            $MatchingZone = $CollectedData.Zones | Where-Object {
                $_.ZoneName -eq $ZoneName -and
                $_.ZoneType -eq $ZoneType -and
                $_.IsReverseLookupZone -eq $true
            }
            $MatchingZone | Should -Not -BeNullOrEmpty
        }

        It 'Reverse zone <ZoneName> dynamic update is <DynamicUpdate>' -ForEach (
            $V.ReverseZones | Where-Object { $_.DynamicUpdate }
        ) {
            $MatchingZone = $CollectedData.Zones | Where-Object {
                $_.ZoneName -eq $ZoneName -and $_.IsReverseLookupZone -eq $true
            }
            $MatchingZone | Should -Not -BeNullOrEmpty
            $MatchingZone.DynamicUpdate | Should -Be $DynamicUpdate
        }

        It 'Reverse zone <ZoneName> zone transfer policy is <SecureSecondaries>' -ForEach (
            $V.ReverseZones | Where-Object { $_.SecureSecondaries }
        ) {
            $MatchingZone = $CollectedData.Zones | Where-Object {
                $_.ZoneName -eq $ZoneName -and $_.IsReverseLookupZone -eq $true
            }
            $MatchingZone | Should -Not -BeNullOrEmpty
            $MatchingZone.SecureSecondaries | Should -Be $SecureSecondaries
        }
    }

    Context 'A Records' {
        It 'A record <Name> should be <IP> in zone <Zone>' -ForEach $V.ARecords {
            $MatchingRecord = $CollectedData.Records | Where-Object {
                $_.RecordType -eq 'A' -and
                $_.HostName -eq $Name -and
                $_.Value -eq $IP -and
                $_.ZoneName -eq $Zone
            }
            $MatchingRecord | Should -Not -BeNullOrEmpty
        }
    }

    Context 'CNAME Records' {
        It 'CNAME <Name> should point to <Target> in zone <Zone>' -ForEach $V.CnameRecords {
            $MatchingRecord = $CollectedData.Records | Where-Object {
                $_.RecordType -eq 'CNAME' -and
                $_.HostName -eq $Name -and
                $_.ZoneName -eq $Zone
            }
            $MatchingRecord | Should -Not -BeNullOrEmpty
            # CNAME values may have trailing dot — normalise for comparison
            $ActualTarget = $MatchingRecord.Value -replace '\.$', ''
            $ExpectedTarget = $Target -replace '\.$', ''
            $ActualTarget | Should -Be $ExpectedTarget
        }
    }

    Context 'MX Records' {
        It 'MX record in zone <Zone> should point to <Target>' -ForEach $V.MxRecords {
            $MatchingRecord = $CollectedData.Records | Where-Object {
                $_.RecordType -eq 'MX' -and
                $_.ZoneName -eq $Zone
            }
            $MatchingRecord | Should -Not -BeNullOrEmpty
            $ActualTarget = $MatchingRecord.Value -replace '\.$', ''
            $ExpectedTarget = $Target -replace '\.$', ''
            $ActualTarget | Should -Be $ExpectedTarget
        }
    }

    Context 'NS Records' {
        It 'NS record <Expected> should exist in zone <Zone>' -ForEach $V.NsRecords {
            $MatchingRecord = $CollectedData.Records | Where-Object {
                $_.RecordType -eq 'NS' -and
                $_.ZoneName -eq $Zone -and
                (
                    ($_.Value -replace '\.$', '') -eq $Expected -or
                    ($_.Value -replace '\.$', '') -eq "$Expected.$Zone" -or
                    $_.Value -eq "$Expected." -or
                    $_.Value -eq "$Expected.$Zone."
                )
            }
            $MatchingRecord | Should -Not -BeNullOrEmpty
        }
    }

    Context 'PTR Records' {
        It 'PTR record <Name> should resolve to <ExpectedPtr> in zone <Zone>' -ForEach $V.PtrRecords {
            $MatchingRecord = $CollectedData.Records | Where-Object {
                $_.RecordType -eq 'PTR' -and
                $_.HostName -eq $Name -and
                $_.ZoneName -eq $Zone
            }
            $MatchingRecord | Should -Not -BeNullOrEmpty
            $ActualValue = $MatchingRecord.Value -replace '\.$', ''
            # PTR values often contain the full FQDN — match the hostname part
            $ActualValue | Should -Match ([regex]::Escape($ExpectedPtr))
        }
    }

    Context 'Forwarders' {
        It 'Forwarder <IPAddress> should be configured' -ForEach $V.Forwarders {
            $MatchingForwarder = $CollectedData.Forwarders | Where-Object {
                $_.IPAddress -eq $IPAddress
            }
            $MatchingForwarder | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Forwarder Set' {
        It 'At least <RequiredCount> forwarders from the allowed set should be configured' -ForEach $V.ForwarderSetTests {
            $ConfiguredCount = @(
                $CollectedData.Forwarders | Where-Object { $AllowedForwarders -contains $_.IPAddress }
            ).Count
            $ConfiguredCount | Should -BeGreaterOrEqual $RequiredCount
        }
    }

    Context 'SOA Records' {
        It 'SOA record in zone <Zone> should have primary server matching <PrimaryServer>' -ForEach $V.SoaTests {
            $MatchingRecord = $CollectedData.Records | Where-Object {
                $_.RecordType -eq 'SOA' -and $_.ZoneName -eq $Zone
            }
            $MatchingRecord | Should -Not -BeNullOrEmpty
            $NormalizedValue = $MatchingRecord.Value -replace '\.$', ''
            $NormalizedValue | Should -Match ([regex]::Escape($PrimaryServer))
        }
    }

    Context 'Subdomain' {
        It 'Subdomain <SubdomainName> should have records in zone <ZoneName>' -ForEach $V.SubdomainTests {
            $SubRecords = $CollectedData.Records | Where-Object {
                $_.ZoneName -eq $ZoneName -and (
                    $_.HostName -eq $SubdomainName -or
                    $_.HostName -like "*.$SubdomainName"
                )
            }
            $SubRecords | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Delegated Domain' {
        It 'Delegation <DelegatedName> in zone <ZoneName> should point to <DelegatedTo>' -ForEach $V.DelegationTests {
            $DelegationRecord = $CollectedData.Records | Where-Object {
                $_.RecordType -eq 'NS' -and
                $_.ZoneName -eq $ZoneName -and
                $_.HostName -eq $DelegatedName
            }
            $DelegationRecord | Should -Not -BeNullOrEmpty
            $NormalizedValue = $DelegationRecord.Value -replace '\.$', ''
            $NormalizedValue | Should -Match ([regex]::Escape($DelegatedTo))
        }
    }
}
