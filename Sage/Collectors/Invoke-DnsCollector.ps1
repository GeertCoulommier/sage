# Collectors/Invoke-DnsCollector.ps1
# Runs ON the remote VM. Returns structured DNS data for evaluation.
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
        Zones      = @()
        Records    = @()
        Forwarders = @()
    }
    Errors    = @()
}

# ── Check DNS role availability ───────────────────────────────────────────────
try {
    $DnsFeature = Get-WindowsFeature -Name DNS -ErrorAction Stop
}
catch {
    $Result.Reason = "Cannot query DNS feature: $($_.Exception.Message)"
    return $Result
}

if (-not $DnsFeature.Installed) {
    $Result.Reason = 'DNS Server role not installed'
    return $Result
}
$Result.Available = $true

# ── Collect all DNS zones ─────────────────────────────────────────────────────
try {
    $RawZones = Get-DnsServerZone -ErrorAction Stop
    $Result.Data.Zones = @($RawZones | ForEach-Object {
            $Zone = $_
            $DynamicUpdateVal = try { $Zone.DynamicUpdate.ToString() }     catch { 'Unknown' }
            $SecureSecondariesVal = try { $Zone.SecureSecondaries.ToString() } catch { 'Unknown' }
            $SecondaryServersList = @(try { $Zone.SecondaryServers | ForEach-Object { $_.ToString() } } catch { Write-Debug "SecondaryServers not available: $($_.Exception.Message)" })
            @{
                ZoneName            = $Zone.ZoneName
                ZoneType            = $Zone.ZoneType.ToString()
                IsReverseLookupZone = $Zone.IsReverseLookupZone
                IsDsIntegrated      = $Zone.IsDsIntegrated
                DynamicUpdate       = $DynamicUpdateVal
                SecureSecondaries   = $SecureSecondariesVal
                SecondaryServers    = $SecondaryServersList
            }
        })
}
catch {
    $Result.Errors += "Zone enumeration failed: $($_.Exception.Message)"
    return $Result
}

# ── Collect resource records per zone (isolated errors) ───────────────────────
foreach ($Zone in $Result.Data.Zones) {
    try {
        $RawRecords = Get-DnsServerResourceRecord -ZoneName $Zone.ZoneName -ErrorAction Stop
        foreach ($Rr in $RawRecords) {
            $Value = $null
            switch ($Rr.RecordType) {
                'A' {
                    if ($Rr.RecordData.IPv4Address) {
                        $Value = $Rr.RecordData.IPv4Address.ToString()
                    }
                }
                'AAAA' {
                    if ($Rr.RecordData.IPv6Address) {
                        $Value = $Rr.RecordData.IPv6Address.ToString()
                    }
                }
                'CNAME' { $Value = $Rr.RecordData.HostNameAlias }
                'MX' { $Value = $Rr.RecordData.MailExchange }
                'NS' { $Value = $Rr.RecordData.NameServer }
                'PTR' { $Value = $Rr.RecordData.PtrDomainName }
                'SRV' { $Value = "$($Rr.RecordData.DomainName):$($Rr.RecordData.Port)" }
                'SOA' { $Value = $Rr.RecordData.PrimaryServer }
                'TXT' {
                    if ($Rr.RecordData.DescriptiveText) {
                        $Value = $Rr.RecordData.DescriptiveText -join ' '
                    }
                }
                default { $Value = $Rr.RecordData.ToString() }
            }

            $Result.Data.Records += @{
                ZoneName   = $Zone.ZoneName
                HostName   = $Rr.HostName
                RecordType = $Rr.RecordType.ToString()
                Value      = $Value
                TimeToLive = $Rr.TimeToLive.ToString()
            }
        }
    }
    catch {
        $Result.Errors += "Records for zone '$($Zone.ZoneName)': $($_.Exception.Message)"
    }
}

# ── Collect forwarders ────────────────────────────────────────────────────────
try {
    $Fwd = Get-DnsServerForwarder -ErrorAction Stop
    $Result.Data.Forwarders = @($Fwd.IPAddress | ForEach-Object {
            @{ IPAddress = $_.ToString() }
        })
}
catch {
    $Result.Errors += "Forwarders: $($_.Exception.Message)"
}

return $Result
