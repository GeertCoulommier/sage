# Evaluations/GeneralConfig.Tests.ps1
# Comprehensive General Configuration evaluation — tests driven entirely by exam data.
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
    'Hostname' = {
        param($Data)
        @{
            ActualHostname = $Data.Hostname
        }
    }
    'Static IP Configuration' = {
        param($Data)
        $Data.IPAddresses | ForEach-Object {
            [PSCustomObject]@{
                IPAddress      = $_.IPAddress
                PrefixLength   = $_.PrefixLength
                PrefixOrigin   = $_.PrefixOrigin
                InterfaceAlias = $_.InterfaceAlias
            }
        }
    }
    'Gateway' = {
        param($Data)
        $Data.NetAdapters | ForEach-Object {
            [PSCustomObject]@{
                InterfaceAlias = $_.InterfaceAlias
                IPv4Address    = $_.IPv4Address
                Gateway        = $_.Gateway
            }
        }
    }
    'DNS Servers' = {
        param($Data)
        $Data.NetAdapters | ForEach-Object {
            [PSCustomObject]@{
                InterfaceAlias = $_.InterfaceAlias
                DnsServers     = ($_.DnsServers -join ', ')
            }
        }
    }
    'DNS Servers (allowed set)' = {
        param($Data)
        $Data.NetAdapters | ForEach-Object {
            [PSCustomObject]@{
                InterfaceAlias = $_.InterfaceAlias
                DnsServers     = ($_.DnsServers -join ', ')
            }
        }
    }
    'Ping' = {
        param($Data)
        @{
            PingEnabled = $Data.PingEnabled
        }
    }
    'Remote Desktop' = {
        param($Data)
        @{
            RdpEnabled = $Data.RdpEnabled
        }
    }
}

Describe 'General Configuration' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.HostnameTests) { $V.HostnameTests = @() }
        if (-not $V.StaticIPTests) { $V.StaticIPTests = @() }
        if (-not $V.AllowedDnsTests) { $V.AllowedDnsTests = @() }
        if (-not $V.PingTests) { $V.PingTests = @() }
        if (-not $V.RdpTests) { $V.RdpTests = @() }
    }

    Context 'Hostname' {
        It 'Hostname should be <ExpectedHostname>' -ForEach $V.HostnameTests {
            $CollectedData.Hostname | Should -Be $ExpectedHostname
        }
    }

    Context 'Static IP Configuration' {
        It 'Static IP <ExpectedIP> should be configured' -ForEach $V.StaticIPTests {
            $MatchingIp = $CollectedData.IPAddresses | Where-Object {
                $_.IPAddress -eq $ExpectedIP -and
                $_.PrefixOrigin -eq 'Manual'
            }
            $MatchingIp | Should -Not -BeNullOrEmpty
        }

        It 'Prefix length for <ExpectedIP> should be <ExpectedPrefix>' -ForEach ($V.StaticIPTests | Where-Object { $_.ExpectedPrefix }) {
            $MatchingIp = $CollectedData.IPAddresses | Where-Object {
                $_.IPAddress -eq $ExpectedIP -and
                $_.PrefixLength -eq $ExpectedPrefix -and
                $_.PrefixOrigin -eq 'Manual'
            }
            $MatchingIp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Gateway' {
        It 'Gateway should be <ExpectedGateway>' -ForEach ($V.StaticIPTests | Where-Object { $_.ExpectedGateway }) {
            $MatchingAdapter = $CollectedData.NetAdapters | Where-Object {
                $_.Gateway -eq $ExpectedGateway
            }
            $MatchingAdapter | Should -Not -BeNullOrEmpty
        }
    }

    Context 'DNS Servers' {
        It 'DNS server <DnsServer> should be configured' -ForEach (
            $V.StaticIPTests | Where-Object { $_.ExpectedDns } | ForEach-Object {
                $Test = $_
                $Test.ExpectedDns | ForEach-Object {
                    @{
                        DnsServer       = $_
                        ExpectedIP      = $Test.ExpectedIP
                        PassGrade       = $Test.PassGrade
                    }
                }
            }
        ) {
            $AllDns = $CollectedData.NetAdapters | ForEach-Object { $_.DnsServers } | ForEach-Object { $_ }
            $AllDns | Should -Contain $DnsServer
        }
    }

    Context 'DNS Servers (allowed set)' {
        It 'At least <RequiredDnsCount> DNS servers from the allowed set should be configured' -ForEach $V.AllowedDnsTests {
            $AllDns = @($CollectedData.NetAdapters | ForEach-Object { $_.DnsServers } | ForEach-Object { $_ })
            $ConfiguredCount = @($AllDns | Where-Object { $AllowedDns -contains $_ }).Count
            $ConfiguredCount | Should -BeGreaterOrEqual $RequiredDnsCount
        }
    }

    Context 'Ping' {
        It 'Machine should allow ICMP echo requests (ICMPv4 inbound rule enabled)' -ForEach $V.PingTests {
            $CollectedData.PingEnabled | Should -Be $true
        }
    }

    Context 'Remote Desktop' {
        It 'Remote Desktop (RDP) should be enabled' -ForEach $V.RdpTests {
            $CollectedData.RdpEnabled | Should -Be $true
        }
    }
}
