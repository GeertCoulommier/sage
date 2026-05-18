# Collectors/Invoke-AdCollector.ps1
# Runs ON the remote VM. Returns structured Active Directory data for evaluation.
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
        DomainName              = $null
        DomainDistinguishedName = $null
        DomainFunctionalLevel   = $null
        ForestFunctionalLevel   = $null
        PartOfDomain            = $false
        Computers               = @()
        OUs                     = @()
        Users                   = @()
        Groups                  = @()
        Sites                   = @()
        Subnets                 = @()
        SiteLinks               = @()
        DomainControllers       = @()
    }
    Errors    = @()
}

# ── Check domain membership ───────────────────────────────────────────────────
try {
    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $Result.Data.PartOfDomain = [bool]$ComputerSystem.PartOfDomain
}
catch {
    $Result.Reason = "Cannot query WMI: $($_.Exception.Message)"
    return $Result
}

if (-not $Result.Data.PartOfDomain) {
    $Result.Reason = 'Machine is not part of a domain'
    return $Result
}
$Result.Available = $true

# ── Domain & forest functional levels ─────────────────────────────────────────
try {
    $Domain = Get-ADDomain -ErrorAction Stop
    $Result.Data.DomainName = $Domain.DNSRoot
    $Result.Data.DomainDistinguishedName = $Domain.DistinguishedName
    $Result.Data.DomainFunctionalLevel = $Domain.DomainMode.ToString()
}
catch {
    $Result.Errors += "AD Domain query failed: $($_.Exception.Message)"
}

try {
    $Forest = Get-ADForest -ErrorAction Stop
    $Result.Data.ForestFunctionalLevel = $Forest.ForestMode.ToString()
}
catch {
    $Result.Errors += "AD Forest query failed: $($_.Exception.Message)"
}

# ── Computers ─────────────────────────────────────────────────────────────────
try {
    $Computers = Get-ADComputer -Filter * -Properties Name, DNSHostName, DistinguishedName -ErrorAction Stop
    $Result.Data.Computers = @($Computers | ForEach-Object {
            @{
                Name              = $_.Name
                DNSHostName       = $_.DNSHostName
                DistinguishedName = $_.DistinguishedName
            }
        })
}
catch {
    $Result.Errors += "AD Computers query failed: $($_.Exception.Message)"
}

# ── Organizational Units ──────────────────────────────────────────────────────
try {
    $OUs = Get-ADOrganizationalUnit -Filter * -Properties Name, DistinguishedName -ErrorAction Stop
    $Result.Data.OUs = @($OUs | ForEach-Object {
            @{
                Name              = $_.Name
                DistinguishedName = $_.DistinguishedName
            }
        })
}
catch {
    $Result.Errors += "AD OUs query failed: $($_.Exception.Message)"
}

# ── Users ─────────────────────────────────────────────────────────────────────
try {
    $Users = Get-ADUser -Filter * -Properties GivenName, Surname, SamAccountName, Name, DistinguishedName, MemberOf -ErrorAction Stop
    $Result.Data.Users = @($Users | ForEach-Object {
            @{
                GivenName         = $_.GivenName
                Surname           = $_.Surname
                SamAccountName    = $_.SamAccountName
                Name              = $_.Name
                DistinguishedName = $_.DistinguishedName
                MemberOf          = @($_.MemberOf | ForEach-Object { $_ })
            }
        })
}
catch {
    $Result.Errors += "AD Users query failed: $($_.Exception.Message)"
}

# ── Groups ────────────────────────────────────────────────────────────────────
try {
    $Groups = Get-ADGroup -Filter * -Properties Name, SamAccountName, GroupScope, GroupCategory, DistinguishedName, Members -ErrorAction Stop
    $Result.Data.Groups = @($Groups | ForEach-Object {
            @{
                Name              = $_.Name
                SamAccountName    = $_.SamAccountName
                GroupScope        = $_.GroupScope.ToString()
                GroupCategory     = $_.GroupCategory.ToString()
                DistinguishedName = $_.DistinguishedName
                Members           = @($_.Members | ForEach-Object { $_ })
            }
        })
}
catch {
    $Result.Errors += "AD Groups query failed: $($_.Exception.Message)"
}

# ── AD Sites ──────────────────────────────────────────────────────────────────
try {
    $AdSites = Get-ADReplicationSite -Filter * -Properties Name, DistinguishedName -ErrorAction Stop
    $Result.Data.Sites = @($AdSites | ForEach-Object {
            @{
                Name              = $_.Name
                DistinguishedName = $_.DistinguishedName
            }
        })
}
catch {
    $Result.Errors += "AD Sites query failed: $($_.Exception.Message)"
}

# ── AD Subnets ────────────────────────────────────────────────────────────────
try {
    $AdSubnets = Get-ADReplicationSubnet -Filter * -Properties Name, Site -ErrorAction Stop
    $Result.Data.Subnets = @($AdSubnets | ForEach-Object {
            $SiteDN = if ($_.Site) { $_.Site.ToString() } else { $null }
            $SiteName = if ($SiteDN -and $SiteDN -match '^CN=([^,]+)') { $Matches[1] } else { $null }
            @{
                Name     = $_.Name
                SiteName = $SiteName
                SiteDN   = $SiteDN
            }
        })
}
catch {
    $Result.Errors += "AD Subnets query failed: $($_.Exception.Message)"
}

# ── AD Site Links ─────────────────────────────────────────────────────────────
try {
    $AdSiteLinks = Get-ADReplicationSiteLink -Filter * -Properties Name, Cost, ReplicationFrequencyInMinutes, SitesIncluded, Schedule -ErrorAction Stop
    $Result.Data.SiteLinks = @($AdSiteLinks | ForEach-Object {
            # Resolve site names from SitesIncluded DNs (e.g. CN=Kaai,CN=Sites,...)
            $SiteNames = @($_.SitesIncluded | ForEach-Object {
                    $Dn = $_.ToString()
                    if ($Dn -match '^CN=([^,]+)') { $Matches[1] } else { $Dn }
                })

            # Decode schedule bytes to a flat 168-integer availability matrix.
            # Format: 188 bytes total — first 20 bytes are the SCHEDULE header;
            # bytes 20-187 are 7 days x 24 hours (DayIndex*24+HourIndex),
            # DayIndex: 0=Sunday, 1=Monday, ..., 6=Saturday.
            # Lower nibble of each byte: 4 quarter-hour availability bits.
            # 0x0F = full hour available, 0x00 = no sync.
            $ScheduleMatrix = $null
            if ($null -ne $_.Schedule) {
                $Bytes = [byte[]]$_.Schedule
                $ScheduleMatrix = [int[]]::new(168)
                for ($Idx = 0; $Idx -lt 168; $Idx++) {
                    $BytePos = 20 + $Idx
                    if ($BytePos -lt $Bytes.Length) {
                        $ScheduleMatrix[$Idx] = [int]($Bytes[$BytePos] -band 0x0F)
                    }
                }
            }

            @{
                Name                          = $_.Name
                Cost                          = [int]$_.Cost
                ReplicationFrequencyInMinutes = [int]$_.ReplicationFrequencyInMinutes
                SiteNames                     = $SiteNames
                ScheduleMatrix                = $ScheduleMatrix
            }
        })
}
catch {
    $Result.Errors += "AD Site Links query failed: $($_.Exception.Message)"
}

# ── Domain Controllers (site membership) ──────────────────────────────────────
try {
    $DCs = Get-ADDomainController -Filter * -ErrorAction Stop
    $Result.Data.DomainControllers = @($DCs | ForEach-Object {
            @{
                Name = $_.Name
                Site = $_.Site
            }
        })
}
catch {
    $Result.Errors += "AD DomainControllers query failed: $($_.Exception.Message)"
}

return $Result
