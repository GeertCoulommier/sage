# Collectors/Invoke-GeneralConfigCollector.ps1
# Runs ON the remote VM. Returns structured data for GeneralConfig evaluation.
# All output is plain hashtables/strings — safe for CLIXML deserialization.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables',
    Justification = 'Reserved for future use; collector behaviour is data-independent.')]
param(
    [Parameter()][hashtable] $Variables = @{}
)

$Result = @{
    Available = $false
    Reason    = $null
    Data      = @{
        Hostname    = $null
        IPAddresses = @()
        NetAdapters = @()
        RdpEnabled  = $null
        PingEnabled = $null
    }
    Errors    = @()
}

# ── Collect hostname ──────────────────────────────────────────────────────────
try {
    $Result.Data.Hostname = [System.Net.Dns]::GetHostName()
    $Result.Available = $true
}
catch {
    $Result.Reason = "Cannot determine hostname: $($_.Exception.Message)"
    return $Result
}

# ── Detect OS platform ────────────────────────────────────────────────────────
$IsLinuxOS = $IsLinux -or ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows)

# ── Collect IP configuration ──────────────────────────────────────────────────
if ($IsLinuxOS) {
    # Linux: use .NET NetworkInterface (cross-platform, no external commands needed)
    try {
        $Interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
        $Result.Data.IPAddresses = @(
            $Interfaces | ForEach-Object {
                $Iface = $_
                $Iface.GetIPProperties().UnicastAddresses |
                    Where-Object { $_.Address -ne $null -and
                                   $_.Address.AddressFamily -eq 'InterNetwork' -and
                                   $_.Address.ToString() -ne '127.0.0.1' } |
                    ForEach-Object {
                        @{
                            IPAddress      = $_.Address.ToString()
                            PrefixLength   = $_.PrefixLength
                            PrefixOrigin   = if ($_.PrefixOrigin -ne $null) { $_.PrefixOrigin.ToString() } else { 'Unknown' }
                            InterfaceAlias = $Iface.Name
                        }
                    }
            }
        )
    }
    catch {
        $Result.Errors += "IP address collection failed (Linux): $($_.Exception.Message)"
    }

    # Linux gateway and DNS from /proc/net/route and /etc/resolv.conf
    try {
        $GatewayIp = $null
        $DnsServers = @()

        # Parse default gateway from /proc/net/route (hex encoded)
        $RouteLines = Get-Content '/proc/net/route' -ErrorAction SilentlyContinue |
            Select-Object -Skip 1 |
            Where-Object { ($_ -split '\s+')[1] -eq '00000000' }
        if ($RouteLines) {
            $FirstRoute = ($RouteLines | Select-Object -First 1)
            $HexGw = ($FirstRoute -split '\s+')[2]
            # Convert hex little-endian to IP
            $Bytes = @(
                [Convert]::ToInt32($HexGw.Substring(6, 2), 16)
                [Convert]::ToInt32($HexGw.Substring(4, 2), 16)
                [Convert]::ToInt32($HexGw.Substring(2, 2), 16)
                [Convert]::ToInt32($HexGw.Substring(0, 2), 16)
            )
            $GatewayIp = $Bytes -join '.'
        }

        # Parse DNS from /etc/resolv.conf
        if (Test-Path '/etc/resolv.conf') {
            $DnsServers = @(
                Get-Content '/etc/resolv.conf' |
                    Where-Object { $_ -match '^\s*nameserver\s+(\S+)' } |
                    ForEach-Object { $Matches[1] }
            )
        }

        # Build NetAdapters from the unicast addresses we already have
        $Result.Data.NetAdapters = @(
            $Result.Data.IPAddresses | ForEach-Object {
                @{
                    InterfaceAlias = $_.InterfaceAlias
                    IPv4Address    = $_.IPAddress
                    Gateway        = $GatewayIp
                    DnsServers     = $DnsServers
                }
            }
        )
    }
    catch {
        $Result.Errors += "Network adapter configuration failed (Linux): $($_.Exception.Message)"
    }
}
else {
    # Windows: use standard networking cmdlets
    try {
        $IpAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -ne '127.0.0.1' }

        $Result.Data.IPAddresses = @($IpAddresses | ForEach-Object {
            @{
                IPAddress      = $_.IPAddress
                PrefixLength   = $_.PrefixLength
                PrefixOrigin   = $_.PrefixOrigin.ToString()
                InterfaceAlias = $_.InterfaceAlias
            }
        })
    }
    catch {
        $Result.Errors += "IP address collection failed: $($_.Exception.Message)"
    }

    # ── Collect network adapter configuration (gateway, DNS) ─────────────────────
    try {
        $NetConfigs = Get-NetIPConfiguration -ErrorAction Stop |
            Where-Object { $_.IPv4Address.IPAddress -ne '127.0.0.1' -and $null -ne $_.IPv4Address }

        $Result.Data.NetAdapters = @($NetConfigs | ForEach-Object {
            @{
                InterfaceAlias = $_.InterfaceAlias
                IPv4Address    = $_.IPv4Address.IPAddress
                Gateway        = if ($_.IPv4DefaultGateway) { $_.IPv4DefaultGateway.NextHop } else { $null }
                DnsServers     = @($_.DNSServer | Where-Object { $_.AddressFamily -eq 2 } |
                    ForEach-Object { $_.ServerAddresses } |
                    ForEach-Object { $_ })
            }
        })
    }
    catch {
        $Result.Errors += "Network adapter configuration failed: $($_.Exception.Message)"
    }

    # ── Collect Remote Desktop (RDP) enabled state ────────────────────────────────
    try {
        $RdpKey = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction Stop
        $Result.Data.RdpEnabled = ($RdpKey.fDenyTSConnections -eq 0)
    }
    catch {
        $Result.Errors += "RDP configuration collection failed: $($_.Exception.Message)"
    }

    # ── Collect ICMP echo (ping) inbound firewall rule state ──────────────────────
    try {
        $IcmpRules = @(Get-NetFirewallRule -Direction Inbound -ErrorAction Stop |
            Where-Object {
                $_.Action -eq 'Allow' -and
                $_.Enabled.ToString() -eq 'True' -and
                $_.DisplayName -match 'ICMPv4'
            })
        $Result.Data.PingEnabled = $IcmpRules.Count -gt 0
    }
    catch {
        $Result.Errors += "ICMP firewall rule collection failed: $($_.Exception.Message)"
    }
}

return $Result
