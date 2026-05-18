#Requires -Version 7.5
<#
.SYNOPSIS
    Formats raw collector data into a concise, human-readable text report.
.DESCRIPTION
    Transforms a Sage.CollectorResult into organized, readable output for
    manual verification during Edit-Grade reviews.  Groups data logically
    (e.g. DNS records by zone) and filters out noise (e.g. AD-created zones).
.PARAMETER CollectorResult
    A collector result object (hashtable or PSCustomObject) with Available,
    Data, Errors, and Reason properties.
.PARAMETER CollectorName
    Name of the collector (e.g. 'Dns', 'Ad', 'Docker').
.PARAMETER CategoryName
    Display name for the category header.
.PARAMETER TargetName
    Display name for the target VM.
.OUTPUTS
    [string]  Multi-line formatted text report.
.EXAMPLE
    Format-CollectorData -CollectorResult $result -CollectorName 'Dns' -CategoryName 'DNS DC1' -TargetName 'DC1'
#>
function Format-CollectorData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                                [object] $CollectorResult,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $CollectorName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $CategoryName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TargetName
    )

    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    # ── Header ─────────────────────────────────────────────────────────────────
    $null = $Sb.AppendLine('╔══════════════════════════════════════════════════════════════════════╗')
    $null = $Sb.AppendLine("║  $CategoryName  [$TargetName]".PadRight(70) + ' ' + '║')
    $null = $Sb.AppendLine('╚══════════════════════════════════════════════════════════════════════╝')
    $null = $Sb.AppendLine()

    if (-not $CollectorResult.Available) {
        $null = $Sb.AppendLine("  ⚠ Service unavailable: $($CollectorResult.Reason)")
        return $Sb.ToString()
    }

    $Data = if ($CollectorResult.Data -is [hashtable]) {
        $CollectorResult.Data
    }
    elseif ($CollectorResult.Data -is [PSCustomObject]) {
        $Ht = @{}
        foreach ($P in $CollectorResult.Data.PSObject.Properties) {
            $Ht[$P.Name] = $P.Value
        }
        $Ht
    }
    else { @{} }

    switch ($CollectorName) {
        'GeneralConfig' { $null = $Sb.Append((Format-GeneralConfigData $Data)) }
        'Dns' { $null = $Sb.Append((Format-DnsData $Data)) }
        'Ad' { $null = $Sb.Append((Format-AdData $Data)) }
        'Dhcp' { $null = $Sb.Append((Format-DhcpData $Data)) }
        'Gpo' { $null = $Sb.Append((Format-GpoData $Data)) }
        'FileServer' { $null = $Sb.Append((Format-FileServerData $Data)) }
        'Iis' { $null = $Sb.Append((Format-IisData $Data)) }
        'Docker' { $null = $Sb.Append((Format-DockerData $Data)) }
        'BashHistory' { $null = $Sb.Append((Format-BashHistoryData $Data)) }
        'Apache' { $null = $Sb.Append((Format-WebServerData $Data 'Apache')) }
        'Nginx' { $null = $Sb.Append((Format-WebServerData $Data 'Nginx')) }
        default { $null = $Sb.AppendLine("  (No custom formatter for collector '$CollectorName')") }
    }

    if ($CollectorResult.Errors -and $CollectorResult.Errors.Count -gt 0) {
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine('── Collector Errors ──')
        foreach ($Err in $CollectorResult.Errors) {
            $null = $Sb.AppendLine("  ! $Err")
        }
    }

    return $Sb.ToString()
}

# ── Formatters ─────────────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Formats GeneralConfig collector data into a human-readable text block.
.DESCRIPTION
    Renders hostname and network interface information from the GeneralConfig
    collector result into a multi-line string suitable for Edit-Grade review.
.PARAMETER Data
    Hashtable of structured data from the GeneralConfig collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-GeneralConfigData -Data $CollectorResult.Data
#>
function Format-GeneralConfigData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()
    $null = $Sb.AppendLine("  Hostname : $($Data.Hostname)")
    if ($Data.IpAddresses) {
        foreach ($Ip in $Data.IpAddresses) {
            $null = $Sb.AppendLine("  Interface: $($Ip.InterfaceAlias)")
            $null = $Sb.AppendLine("    IP     : $($Ip.IPAddress)/$($Ip.PrefixLength)")
            $null = $Sb.AppendLine("    Gateway: $($Ip.Gateway)")
            $null = $Sb.AppendLine("    DNS    : $(($Ip.DnsServers -join ', '))")
        }
    }
    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats DNS collector data into a human-readable text block.
.DESCRIPTION
    Renders forward zones, reverse zones, DNS records, and forwarders from the
    DNS collector result.  AD-internal zones are filtered out by default.
.PARAMETER Data
    Hashtable of structured data from the Dns collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-DnsData -Data $CollectorResult.Data
#>
function Format-DnsData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    # AD-internal zones to hide by default
    $AdZones = @(
        '_msdcs.*', 'TrustAnchors', 'RootDNSServers',
        '0.in-addr.arpa', '127.in-addr.arpa', '255.in-addr.arpa'
    )

    # ── Forward Zones ──
    $ForwardZones = @($Data.Zones | Where-Object {
            $Zone = $_
            -not $Zone.IsReverseLookupZone -and
            -not ($AdZones | Where-Object { $Zone.ZoneName -like $_ })
        })
    if ($ForwardZones.Count -gt 0) {
        $null = $Sb.AppendLine('  ── Forward Zones ──')
        foreach ($Z in $ForwardZones) {
            $DsFlag = if ($Z.IsDsIntegrated) { ' [AD-integrated]' } else { '' }
            $null = $Sb.AppendLine("    $($Z.ZoneName) ($($Z.ZoneType))$DsFlag")

            # Records grouped by type for this zone
            $ZoneRecords = @($Data.Records | Where-Object { $_.ZoneName -eq $Z.ZoneName })
            $Grouped = $ZoneRecords | Group-Object RecordType | Sort-Object Name
            foreach ($G in $Grouped) {
                if ($G.Name -eq 'SOA') { continue }
                $null = $Sb.AppendLine("      [$($G.Name)]")
                foreach ($R in ($G.Group | Sort-Object HostName)) {
                    $null = $Sb.AppendLine("        $($R.HostName.PadRight(20)) → $($R.Value)")
                }
            }
        }
    }

    # ── Reverse Zones ──
    $RevZones = @($Data.Zones | Where-Object {
            $_.IsReverseLookupZone -and
            $_.ZoneName -notin @('0.in-addr.arpa', '127.in-addr.arpa', '255.in-addr.arpa')
        })
    if ($RevZones.Count -gt 0) {
        $null = $Sb.AppendLine('  ── Reverse Zones ──')
        foreach ($Z in $RevZones) {
            $DsFlag = if ($Z.IsDsIntegrated) { ' [AD-integrated]' } else { '' }
            $null = $Sb.AppendLine("    $($Z.ZoneName) ($($Z.ZoneType))$DsFlag")
            $ZoneRecords = @($Data.Records | Where-Object {
                    $_.ZoneName -eq $Z.ZoneName -and $_.RecordType -eq 'PTR'
                })
            foreach ($R in ($ZoneRecords | Sort-Object HostName)) {
                $null = $Sb.AppendLine("        $($R.HostName.PadRight(20)) → $($R.Value)")
            }
        }
    }

    # ── Forwarders ──
    if ($Data.Forwarders -and $Data.Forwarders.Count -gt 0) {
        $null = $Sb.AppendLine('  ── Forwarders ──')
        foreach ($F in $Data.Forwarders) {
            $null = $Sb.AppendLine("    $($F.IPAddress)")
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats Active Directory collector data into a human-readable text block.
.DESCRIPTION
    Renders domain info, computers, OUs, users (with group memberships), and
    groups from the AD collector result.
.PARAMETER Data
    Hashtable of structured data from the Ad collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-AdData -Data $CollectorResult.Data
#>
function Format-AdData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    $PartOfDomain = if ($null -ne $Data.PartOfDomain) { $Data.PartOfDomain } else { 'N/A' }
    $null = $Sb.AppendLine("  Domain             : $($Data.DomainName)")
    $null = $Sb.AppendLine("  Part of Domain     : $PartOfDomain")
    $null = $Sb.AppendLine("  Domain Level       : $($Data.DomainFunctionalLevel)")
    $null = $Sb.AppendLine("  Forest Level       : $($Data.ForestFunctionalLevel)")

    if ($Data.Computers -and $Data.Computers.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Domain Computers ($($Data.Computers.Count)) ──")
        foreach ($C in ($Data.Computers | Sort-Object { $_.Name })) {
            $Dn = if ($C.DistinguishedName) { " ($($C.DistinguishedName))" } else { '' }
            $null = $Sb.AppendLine("    $($C.Name)$Dn")
        }
    }

    if ($Data.OUs -and $Data.OUs.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Organizational Units ($($Data.OUs.Count)) ──")
        foreach ($Ou in ($Data.OUs | Sort-Object { $_.DistinguishedName })) {
            $null = $Sb.AppendLine("    $($Ou.Name.PadRight(25)) $($Ou.DistinguishedName)")
        }
    }

    if ($Data.Users -and $Data.Users.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Users ($($Data.Users.Count)) ──")
        foreach ($U in ($Data.Users | Sort-Object { $_.SamAccountName })) {
            $Name = "$($U.GivenName) $($U.Surname)".Trim()
            $null = $Sb.AppendLine("    $($U.SamAccountName.PadRight(20)) $Name")
            if ($U.MemberOf -and $U.MemberOf.Count -gt 0) {
                foreach ($Group in $U.MemberOf) {
                    $null = $Sb.AppendLine("      MemberOf: $Group")
                }
            }
        }
    }

    if ($Data.Groups -and $Data.Groups.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Groups ($($Data.Groups.Count)) ──")
        foreach ($G in ($Data.Groups | Sort-Object { $_.Name })) {
            $MemberCount = if ($G.Members) { $G.Members.Count } else { 0 }
            $Scope = if ($G.GroupScope) { " [$($G.GroupScope)]" } else { '' }
            $null = $Sb.AppendLine("    $($G.Name.PadRight(25))$Scope ($MemberCount members)")
            if ($G.Members -and $G.Members.Count -gt 0) {
                foreach ($M in $G.Members) {
                    $null = $Sb.AppendLine("      - $M")
                }
            }
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats DHCP collector data into a human-readable text block.
.DESCRIPTION
    Renders DHCP scopes, ranges, exclusions, options, and reservations from the
    DHCP collector result.
.PARAMETER Data
    Hashtable of structured data from the Dhcp collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-DhcpData -Data $CollectorResult.Data
#>
function Format-DhcpData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    $null = $Sb.AppendLine("  Authorized: $($Data.IsAuthorized)")

    if ($Data.Scopes -and $Data.Scopes.Count -gt 0) {
        foreach ($S in $Data.Scopes) {
            $null = $Sb.AppendLine("  ── Scope: $($S.Name) ($($S.ScopeId)) ──")
            $null = $Sb.AppendLine("    Range      : $($S.StartRange) - $($S.EndRange)")
            $null = $Sb.AppendLine("    Subnet Mask: $($S.SubnetMask)")
            $null = $Sb.AppendLine("    State      : $($S.State)")

            if ($S.Exclusions -and $S.Exclusions.Count -gt 0) {
                $null = $Sb.AppendLine('    Exclusions:')
                foreach ($E in $S.Exclusions) {
                    $null = $Sb.AppendLine("      $($E.StartRange) - $($E.EndRange)")
                }
            }

            if ($S.Options -and $S.Options.Count -gt 0) {
                $null = $Sb.AppendLine('    Options:')
                foreach ($O in $S.Options) {
                    $null = $Sb.AppendLine("      $($O.Name.PadRight(25)) $(($O.Value -join ', '))")
                }
            }

            if ($S.Reservations -and $S.Reservations.Count -gt 0) {
                $null = $Sb.AppendLine('    Reservations:')
                foreach ($R in $S.Reservations) {
                    $null = $Sb.AppendLine("      $($R.IPAddress.PadRight(18)) $($R.Name)")
                }
            }
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats Group Policy Object collector data into a human-readable text block.
.DESCRIPTION
    Renders GPO names, status, links, and computer/user scope settings from the
    GPO collector result.
.PARAMETER Data
    Hashtable of structured data from the Gpo collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-GpoData -Data $CollectorResult.Data
#>
function Format-GpoData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    if ($Data.Gpos -and $Data.Gpos.Count -gt 0) {
        foreach ($Gpo in ($Data.Gpos | Sort-Object { $_.Name })) {
            $null = $Sb.AppendLine("  ── GPO: $($Gpo.Name) ──")
            $null = $Sb.AppendLine("    Status: $($Gpo.Status)")

            if ($Gpo.Links -and $Gpo.Links.Count -gt 0) {
                $null = $Sb.AppendLine('    Links:')
                foreach ($L in $Gpo.Links) {
                    $Enabled = if ($L.Enabled -eq 'true') { 'enabled' } else { 'disabled' }
                    $null = $Sb.AppendLine("      $($L.SOMPath) [$Enabled]")
                }
            }

            foreach ($ScopeType in @('ComputerScope', 'UserScope')) {
                $ScopeData = $Gpo.$ScopeType
                if (-not $ScopeData -or $ScopeData.Count -eq 0) { continue }
                $ScopeLabel = if ($ScopeType -eq 'ComputerScope') { 'Computer' } else { 'User' }

                $ByType = $ScopeData | Group-Object Type
                foreach ($G in $ByType) {
                    if ($G.Name -eq 'NoSettings') { continue }
                    $null = $Sb.AppendLine("    $ScopeLabel > $($G.Name):")
                    foreach ($Item in $G.Group) {
                        $SettingsLine = ($Item.Settings.PSObject.Properties |
                                Where-Object { $_.Name -ne 'PSTypeName' } |
                                ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
                        $null = $Sb.AppendLine("      $SettingsLine")
                    }
                }
            }
        }
    }
    else {
        $null = $Sb.AppendLine('  (No GPOs found)')
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats file-server collector data into a human-readable text block.
.DESCRIPTION
    Renders SMB shares, share permissions, and NTFS permissions from the
    FileServer collector result.
.PARAMETER Data
    Hashtable of structured data from the FileServer collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-FileServerData -Data $CollectorResult.Data
#>
function Format-FileServerData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    if ($Data.Shares -and $Data.Shares.Count -gt 0) {
        foreach ($S in ($Data.Shares | Sort-Object { $_.Name })) {
            $null = $Sb.AppendLine("  ── Share: $($S.Name) ──")
            $null = $Sb.AppendLine("    Path: $($S.Path)")

            if ($S.ShareAccess -and $S.ShareAccess.Count -gt 0) {
                $null = $Sb.AppendLine('    Share Permissions:')
                foreach ($A in $S.ShareAccess) {
                    $null = $Sb.AppendLine("      $($A.AccountName.PadRight(30)) $($A.AccessRight)")
                }
            }
        }
    }

    if ($Data.Permissions -and $Data.Permissions.Count -gt 0) {
        $null = $Sb.AppendLine('  ── NTFS Permissions ──')
        foreach ($P in $Data.Permissions) {
            $null = $Sb.AppendLine("    $($P.ShareName) ($($P.Path)):")
            if ($P.Permissions) {
                foreach ($Acl in ($P.Permissions | Where-Object { -not $_.IsInherited })) {
                    $null = $Sb.AppendLine("      $($Acl.IdentityReference.PadRight(30)) $($Acl.FileSystemRights) ($($Acl.AccessControlType))")
                }
            }
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats IIS collector data into a human-readable text block.
.DESCRIPTION
    Renders IIS websites (bindings, virtual directories) and application pools
    from the IIS collector result.
.PARAMETER Data
    Hashtable of structured data from the Iis collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-IisData -Data $CollectorResult.Data
#>
function Format-IisData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    if ($Data.Websites -and $Data.Websites.Count -gt 0) {
        foreach ($Site in ($Data.Websites | Sort-Object { $_.Name })) {
            $null = $Sb.AppendLine("  ── Website: $($Site.Name) [$($Site.State)] ──")
            $null = $Sb.AppendLine("    AppPool: $($Site.AppPoolName)")

            if ($Site.Bindings -and $Site.Bindings.Count -gt 0) {
                $null = $Sb.AppendLine('    Bindings:')
                foreach ($B in $Site.Bindings) {
                    $null = $Sb.AppendLine("      $($B.Uri)")
                }
            }

            if ($Site.VirtualDirectories -and $Site.VirtualDirectories.Count -gt 0) {
                $null = $Sb.AppendLine('    Virtual Directories / Applications:')
                foreach ($V in $Site.VirtualDirectories) {
                    $null = $Sb.AppendLine("      $($V.VDirPath.PadRight(20)) → $($V.PhysicalPath)")
                }
            }
        }
    }

    if ($Data.AppPools -and $Data.AppPools.Count -gt 0) {
        $null = $Sb.AppendLine('  ── App Pools ──')
        foreach ($P in ($Data.AppPools | Sort-Object { $_.Name })) {
            $null = $Sb.AppendLine("    $($P.Name.PadRight(25)) [$($P.State)] Pipeline=$($P.PipelineMode) Runtime=$($P.RuntimeVersion)")
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats Docker collector data into a human-readable text block.
.DESCRIPTION
    Renders Docker images, containers (with port mappings), Dockerfiles, and
    Compose files from the Docker collector result.
.PARAMETER Data
    Hashtable of structured data from the Docker collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-DockerData -Data $CollectorResult.Data
#>
function Format-DockerData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    if ($Data.Images -and $Data.Images.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Images ($($Data.Images.Count)) ──")
        foreach ($Img in ($Data.Images | Sort-Object { $_.Repository })) {
            $null = $Sb.AppendLine("    $($Img.Repository):$($Img.Tag)".PadRight(40) + " $($Img.Size)")
        }
    }

    if ($Data.Containers -and $Data.Containers.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Containers ($($Data.Containers.Count)) ──")
        foreach ($C in ($Data.Containers | Sort-Object { $_.Name })) {
            $null = $Sb.AppendLine("    $($C.Name.PadRight(25)) [$($C.State)] Image=$($C.Image)")
            if ($C.Ports) {
                $null = $Sb.AppendLine("      Ports: $($C.Ports)")
            }
        }
    }

    if ($Data.Dockerfile -and $Data.Dockerfile.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Dockerfiles ($($Data.Dockerfile.Count)) ──")
        foreach ($Df in $Data.Dockerfile) {
            $null = $Sb.AppendLine("    $($Df.Path)")
            $Lines = ($Df.Content -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            foreach ($Line in $Lines | Select-Object -First 10) {
                $null = $Sb.AppendLine("      $Line")
            }
            if ($Lines.Count -gt 10) {
                $null = $Sb.AppendLine("      ... ($($Lines.Count - 10) more lines)")
            }
        }
    }

    if ($Data.Compose -and $Data.Compose.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Compose Files ($($Data.Compose.Count)) ──")
        foreach ($Cf in $Data.Compose) {
            $null = $Sb.AppendLine("    $($Cf.Path)")
            $Lines = ($Cf.Content -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            foreach ($Line in $Lines | Select-Object -First 15) {
                $null = $Sb.AppendLine("      $Line")
            }
            if ($Lines.Count -gt 15) {
                $null = $Sb.AppendLine("      ... ($($Lines.Count - 15) more lines)")
            }
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats bash-history collector data into a human-readable text block.
.DESCRIPTION
    Renders bash command history and command log entries from the BashHistory
    collector result.
.PARAMETER Data
    Hashtable of structured data from the BashHistory collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-BashHistoryData -Data $CollectorResult.Data
#>
function Format-BashHistoryData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    if ($Data.BashHistory -and $Data.BashHistory.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Bash History ($($Data.BashHistory.Count) commands) ──")
        foreach ($Cmd in $Data.BashHistory) {
            $Ts = if ($Cmd.Timestamp) { "[$($Cmd.Timestamp)] " } else { '' }
            $null = $Sb.AppendLine("    ${Ts}$($Cmd.Command)")
        }
    }
    else {
        $null = $Sb.AppendLine('  (No bash history entries)')
    }

    if ($Data.CmdLog -and $Data.CmdLog.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Cmd Log ($($Data.CmdLog.Count) entries) ──")
        foreach ($Entry in $Data.CmdLog) {
            $Ts = if ($Entry.Timestamp) { "[$($Entry.Timestamp)] " } else { '' }
            $UserTag = if ($Entry.User) { "($($Entry.User)) " } else { '' }
            $Host2 = if ($Entry.RemoteHost) { " from $($Entry.RemoteHost)" } else { '' }
            $null = $Sb.AppendLine("    ${Ts}${UserTag}$($Entry.Command)${Host2}")
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats Apache or Nginx collector data into a human-readable text block.
.DESCRIPTION
    Renders service state, virtual host configuration files, and index file
    previews from the Apache or Nginx collector result.
.PARAMETER Data
    Hashtable of structured data from the Apache or Nginx collector.
.PARAMETER ServerType
    The web-server variant: 'Apache' or 'Nginx'.  Affects which config property
    is used for the document root (DocumentRoot vs Root).
.OUTPUTS
    [string]
.EXAMPLE
    Format-WebServerData -Data $CollectorResult.Data -ServerType 'Apache'
#>
function Format-WebServerData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data,
        [Parameter(Mandatory)][ValidateSet('Apache', 'Nginx')]                             [string] $ServerType
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    $null = $Sb.AppendLine("  Service Enabled: $($Data.ServiceEnabled)")
    $null = $Sb.AppendLine("  Service Running: $($Data.ServiceRunning)")
    $null = $Sb.AppendLine("  Sites Available: $($Data.SitesAvailable)")
    $null = $Sb.AppendLine("  Sites Enabled  : $($Data.SitesEnabled)")

    if ($Data.FirewallServices -and $Data.FirewallServices.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Firewall Services ──")
        $null = $Sb.AppendLine("    $($Data.FirewallServices -join '  ')")
    }

    if ($null -ne $Data.MariaDbEnabled -or $null -ne $Data.MariaDbRunning) {
        $null = $Sb.AppendLine("  ── MariaDB ──")
        $null = $Sb.AppendLine("    Enabled : $($Data.MariaDbEnabled)")
        $null = $Sb.AppendLine("    Running : $($Data.MariaDbRunning)")
    }

    if ($null -ne $Data.PhpFpmEnabled -or $null -ne $Data.PhpFpmRunning) {
        $null = $Sb.AppendLine("  ── PHP-FPM ──")
        $null = $Sb.AppendLine("    Enabled : $($Data.PhpFpmEnabled)")
        $null = $Sb.AppendLine("    Running : $($Data.PhpFpmRunning)")
    }

    if ($ServerType -eq 'Apache') {
        if ($Data.HttpdConfListen -and $Data.HttpdConfListen.Count -gt 0) {
            $null = $Sb.AppendLine("  ── httpd.conf Listen ──")
            foreach ($Line in $Data.HttpdConfListen) {
                $null = $Sb.AppendLine("    $Line")
            }
        }
        if ($Data.HttpdConfInclude -and $Data.HttpdConfInclude.Count -gt 0) {
            $null = $Sb.AppendLine("  ── httpd.conf IncludeOptional ──")
            foreach ($Line in $Data.HttpdConfInclude) {
                $null = $Sb.AppendLine("    $Line")
            }
        }
    }

    if ($Data.Directories -and $Data.Directories.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Directories ──")
        foreach ($Entry in $Data.Directories.GetEnumerator()) {
            $Marker = if ($Entry.Value) { 'OK' } else { 'MISSING' }
            $null = $Sb.AppendLine("    [$Marker]  $($Entry.Key)")
        }
    }

    if ($Data.ConfFiles -and $Data.ConfFiles.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Config Files ($($Data.ConfFiles.Count)) ──")
        foreach ($Cf in $Data.ConfFiles) {
            $null = $Sb.AppendLine("    $($Cf.Name)")
            if ($Cf.VirtualHost) {
                $null = $Sb.AppendLine("      VirtualHost : $(($Cf.VirtualHost -join ', '))")
            }
            if ($Cf.ServerName) {
                $null = $Sb.AppendLine("      ServerName  : $(($Cf.ServerName -join ', '))")
            }
            if ($Cf.ServerAlias) {
                $null = $Sb.AppendLine("      ServerAlias : $(($Cf.ServerAlias -join ', '))")
            }
            if ($Cf.Listen) {
                $null = $Sb.AppendLine("      Listen      : $(($Cf.Listen -join ', '))")
            }
            $RootProp = if ($ServerType -eq 'Nginx') { 'Root' } else { 'DocumentRoot' }
            if ($Cf.$RootProp) {
                $null = $Sb.AppendLine("      $($RootProp.PadRight(12)): $(($Cf.$RootProp -join ', '))")
            }
        }
    }

    if ($Data.SymlinkFiles -and $Data.SymlinkFiles.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Symlinks in sites-enabled ──")
        foreach ($Sym in $Data.SymlinkFiles) {
            $Marker = if ($Sym.IsSymlink) { '→' } else { 'FILE' }
            $Target = if ($Sym.LinkTarget) { $Sym.LinkTarget } else { '(not a symlink)' }
            $null = $Sb.AppendLine("    $($Sym.Name)  $Marker  $Target")
        }
    }

    if ($Data.CurlResults -and $Data.CurlResults.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Curl Results ──")
        foreach ($Curl in $Data.CurlResults) {
            $null = $Sb.AppendLine("    $($Curl.Url)")
            if ($Curl.Error) {
                $null = $Sb.AppendLine("      Error  : $($Curl.Error)")
            }
            elseif ($Curl.Content) {
                $Preview = ($Curl.Content -split "`n") | Select-Object -First 3 | ForEach-Object { $_.Trim() }
                foreach ($Line in $Preview) {
                    $null = $Sb.AppendLine("      $Line")
                }
            }
        }
    }

    if ($Data.IndexFiles -and $Data.IndexFiles.Count -gt 0) {
        $null = $Sb.AppendLine("  ── Index Files ($($Data.IndexFiles.Count)) ──")
        foreach ($Idx in $Data.IndexFiles) {
            $null = $Sb.AppendLine("    $($Idx.Path)")
            $Preview = ($Idx.Content -split "`n") | Select-Object -First 5 | ForEach-Object { $_.Trim() }
            foreach ($Line in $Preview) {
                $null = $Sb.AppendLine("      $Line")
            }
        }
    }

    return $Sb.ToString()
}

# ── Markdown Formatters ────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Formats raw collector data into a structured Markdown report.
.DESCRIPTION
    Transforms a Sage.CollectorResult into a readable Markdown document with
    headings, tables, bullet lists, and code blocks for maximum readability.
    Suitable for display in TUI panels, editors, or file export.
.PARAMETER CollectorResult
    A collector result object with Available, Data, Errors, and Reason properties.
.PARAMETER CollectorName
    Name of the collector (e.g. 'Dns', 'Ad', 'Docker').
.PARAMETER CategoryName
    Display name for the H1 heading.
.PARAMETER TargetName
    Display name for the target VM shown in the H1 heading.
.OUTPUTS
    [string]  Markdown-formatted multi-line report.
.EXAMPLE
    Format-CollectorDataMarkdown -CollectorResult $result -CollectorName 'Dns' -CategoryName 'DNS DC1' -TargetName 'DC1'
#>
function Format-CollectorDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                                [object] $CollectorResult,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $CollectorName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $CategoryName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TargetName
    )

    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()

    $null = $Sb.AppendLine("# $CategoryName [$TargetName]")
    $null = $Sb.AppendLine()

    if (-not $CollectorResult.Available) {
        $null = $Sb.AppendLine("> ⚠ Service unavailable: $($CollectorResult.Reason)")
        return $Sb.ToString()
    }

    $Data = if ($CollectorResult.Data -is [hashtable]) {
        $CollectorResult.Data
    }
    elseif ($CollectorResult.Data -is [PSCustomObject]) {
        $Ht = @{}
        foreach ($P in $CollectorResult.Data.PSObject.Properties) {
            $Ht[$P.Name] = $P.Value
        }
        $Ht
    }
    else { @{} }

    switch ($CollectorName) {
        'GeneralConfig' { $null = $Sb.Append((Format-GeneralConfigDataMarkdown $Data)) }
        'Dns' { $null = $Sb.Append((Format-DnsDataMarkdown $Data)) }
        'Ad' { $null = $Sb.Append((Format-AdDataMarkdown $Data)) }
        'Dhcp' { $null = $Sb.Append((Format-DhcpDataMarkdown $Data)) }
        'Gpo' { $null = $Sb.Append((Format-GpoDataMarkdown $Data)) }
        'FileServer' { $null = $Sb.Append((Format-FileServerDataMarkdown $Data)) }
        'Iis' { $null = $Sb.Append((Format-IisDataMarkdown $Data)) }
        'Docker' { $null = $Sb.Append((Format-DockerDataMarkdown $Data)) }
        'BashHistory' { $null = $Sb.Append((Format-BashHistoryDataMarkdown $Data)) }
        'Apache' { $null = $Sb.Append((Format-WebServerDataMarkdown $Data 'Apache')) }
        'Nginx' { $null = $Sb.Append((Format-WebServerDataMarkdown $Data 'Nginx')) }
        default { $null = $Sb.AppendLine("_(No custom formatter for collector '$CollectorName')_") }
    }

    if ($CollectorResult.Errors -and $CollectorResult.Errors.Count -gt 0) {
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine('## Collector Errors')
        $null = $Sb.AppendLine()
        foreach ($Err in $CollectorResult.Errors) {
            $null = $Sb.AppendLine("- ⚠ $Err")
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats GeneralConfig collector data as Markdown.
.DESCRIPTION
    Renders hostname and network interface information from the GeneralConfig
    collector result into a Markdown document with tables per interface.
.PARAMETER Data
    Hashtable of structured data from the GeneralConfig collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-GeneralConfigDataMarkdown -Data $CollectorResult.Data
#>
function Format-GeneralConfigDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Fence = '```'
    $Sb = [System.Text.StringBuilder]::new()

    $null = $Sb.AppendLine('## System Information')
    $null = $Sb.AppendLine()
    $null = $Sb.AppendLine($Fence + 'text')
    $null = $Sb.AppendLine("Hostname:  $($Data.Hostname)")
    $null = $Sb.AppendLine($Fence)
    $null = $Sb.AppendLine()

    if ($Data.IpAddresses) {
        $null = $Sb.AppendLine('## Network Interfaces')
        $null = $Sb.AppendLine()
        foreach ($Ip in $Data.IpAddresses) {
            $null = $Sb.AppendLine("### $($Ip.InterfaceAlias)")
            $null = $Sb.AppendLine()
            $IpPairs = @(
                @('IP Address', "$($Ip.IPAddress)/$($Ip.PrefixLength)"),
                @('Gateway', "$($Ip.Gateway)"),
                @('DNS Servers', "$(($Ip.DnsServers -join ', '))")
            )
            $MaxKeyLen = 0
            foreach ($P in $IpPairs) { if ($P[0].Length -gt $MaxKeyLen) { $MaxKeyLen = $P[0].Length } }
            $null = $Sb.AppendLine($Fence + 'text')
            foreach ($P in $IpPairs) {
                $Pad = ' ' * ($MaxKeyLen - $P[0].Length + 2)
                $null = $Sb.AppendLine("$($P[0]):$Pad$($P[1])")
            }
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats DNS collector data as Markdown.
.DESCRIPTION
    Renders forward zones, reverse zones, DNS records grouped by type, and
    forwarders from the DNS collector result.  AD-internal zones are filtered.
.PARAMETER Data
    Hashtable of structured data from the Dns collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-DnsDataMarkdown -Data $CollectorResult.Data
#>
function Format-DnsDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Fence = '```'
    $Sb = [System.Text.StringBuilder]::new()

    $AdZones = @(
        '_msdcs.*', 'TrustAnchors', 'RootDNSServers',
        '0.in-addr.arpa', '127.in-addr.arpa', '255.in-addr.arpa'
    )

    $ForwardZones = @($Data.Zones | Where-Object {
            $Zone = $_
            -not $Zone.IsReverseLookupZone -and
            -not ($AdZones | Where-Object { $Zone.ZoneName -like $_ })
        })

    if ($ForwardZones.Count -gt 0) {
        $null = $Sb.AppendLine('## Forward Zones')
        $null = $Sb.AppendLine()
        foreach ($Z in $ForwardZones) {
            $DsFlag = if ($Z.IsDsIntegrated) { ' [AD-integrated]' } else { '' }
            $null = $Sb.AppendLine("### $($Z.ZoneName) ($($Z.ZoneType))$DsFlag")
            $null = $Sb.AppendLine()
            $ZoneRecords = @($Data.Records | Where-Object { $_.ZoneName -eq $Z.ZoneName })
            $Grouped = $ZoneRecords | Group-Object RecordType | Sort-Object Name
            foreach ($G in $Grouped) {
                if ($G.Name -eq 'SOA') { continue }
                $null = $Sb.AppendLine("#### $($G.Name) Records")
                $null = $Sb.AppendLine()
                $SortedRecs = @($G.Group | Sort-Object HostName)
                $MaxHost = 0
                foreach ($R in $SortedRecs) { if ($R.HostName.Length -gt $MaxHost) { $MaxHost = $R.HostName.Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($R in $SortedRecs) {
                    $Pad = ' ' * ($MaxHost - $R.HostName.Length + 2)
                    $null = $Sb.AppendLine("$($R.HostName)$Pad$($R.Value)")
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }
        }
    }

    $RevZones = @($Data.Zones | Where-Object {
            $_.IsReverseLookupZone -and
            $_.ZoneName -notin @('0.in-addr.arpa', '127.in-addr.arpa', '255.in-addr.arpa')
        })
    if ($RevZones.Count -gt 0) {
        $null = $Sb.AppendLine('## Reverse Zones')
        $null = $Sb.AppendLine()
        foreach ($Z in $RevZones) {
            $DsFlag = if ($Z.IsDsIntegrated) { ' [AD-integrated]' } else { '' }
            $null = $Sb.AppendLine("### $($Z.ZoneName) ($($Z.ZoneType))$DsFlag")
            $null = $Sb.AppendLine()
            $ZoneRecords = @($Data.Records | Where-Object {
                    $_.ZoneName -eq $Z.ZoneName -and $_.RecordType -eq 'PTR'
                })
            if ($ZoneRecords.Count -gt 0) {
                $SortedPtr = @($ZoneRecords | Sort-Object HostName)
                $MaxHost = 0
                foreach ($R in $SortedPtr) { if ($R.HostName.Length -gt $MaxHost) { $MaxHost = $R.HostName.Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($R in $SortedPtr) {
                    $Pad = ' ' * ($MaxHost - $R.HostName.Length + 2)
                    $null = $Sb.AppendLine("$($R.HostName)$Pad$($R.Value)")
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }
        }
    }

    if ($Data.Forwarders -and $Data.Forwarders.Count -gt 0) {
        $null = $Sb.AppendLine('## Forwarders')
        $null = $Sb.AppendLine()
        foreach ($F in $Data.Forwarders) {
            $null = $Sb.AppendLine("- $($F.IPAddress)")
        }
        $null = $Sb.AppendLine()
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats Active Directory collector data as Markdown.
.DESCRIPTION
    Renders domain info, computers, OUs, users with group memberships, and
    groups from the AD collector result into a Markdown document with tables.
.PARAMETER Data
    Hashtable of structured data from the Ad collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-AdDataMarkdown -Data $CollectorResult.Data
#>
function Format-AdDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Fence = '```'
    $Sb = [System.Text.StringBuilder]::new()

    $PartOfDomain = if ($null -ne $Data.PartOfDomain) { $Data.PartOfDomain } else { 'N/A' }

    $null = $Sb.AppendLine('## Domain Information')
    $null = $Sb.AppendLine()
    $DomPairs = @(
        @('Domain Name', "$($Data.DomainName)"),
        @('Part of Domain', "$PartOfDomain"),
        @('Domain Functional Level', "$($Data.DomainFunctionalLevel)"),
        @('Forest Functional Level', "$($Data.ForestFunctionalLevel)")
    )
    $MaxKeyLen = 0
    foreach ($P in $DomPairs) { if ($P[0].Length -gt $MaxKeyLen) { $MaxKeyLen = $P[0].Length } }
    $null = $Sb.AppendLine($Fence + 'text')
    foreach ($P in $DomPairs) {
        $Pad = ' ' * ($MaxKeyLen - $P[0].Length + 2)
        $null = $Sb.AppendLine("$($P[0]):$Pad$($P[1])")
    }
    $null = $Sb.AppendLine($Fence)
    $null = $Sb.AppendLine()

    if ($Data.Computers -and $Data.Computers.Count -gt 0) {
        $null = $Sb.AppendLine("## Domain Computers ($($Data.Computers.Count))")
        $null = $Sb.AppendLine()
        $SortedComps = @($Data.Computers | Sort-Object { $_.Name })
        $MaxName = 0
        foreach ($C in $SortedComps) { if ($C.Name.Length -gt $MaxName) { $MaxName = $C.Name.Length } }
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($C in $SortedComps) {
            $Dn = if ($C.DistinguishedName) { $C.DistinguishedName } else { '' }
            $Pad = ' ' * ($MaxName - $C.Name.Length + 2)
            $null = $Sb.AppendLine("$($C.Name)$Pad$Dn")
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($Data.OUs -and $Data.OUs.Count -gt 0) {
        $null = $Sb.AppendLine("## Organizational Units ($($Data.OUs.Count))")
        $null = $Sb.AppendLine()
        $SortedOUs = @($Data.OUs | Sort-Object { $_.DistinguishedName })
        $MaxName = 0
        foreach ($Ou in $SortedOUs) { if ($Ou.Name.Length -gt $MaxName) { $MaxName = $Ou.Name.Length } }
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($Ou in $SortedOUs) {
            $Pad = ' ' * ($MaxName - $Ou.Name.Length + 2)
            $null = $Sb.AppendLine("$($Ou.Name)$Pad$($Ou.DistinguishedName)")
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($Data.Users -and $Data.Users.Count -gt 0) {
        $null = $Sb.AppendLine("## Users ($($Data.Users.Count))")
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($U in ($Data.Users | Sort-Object { $_.SamAccountName })) {
            $FullName = "$($U.GivenName) $($U.Surname)".Trim()
            $Groups = if ($U.MemberOf -and $U.MemberOf.Count -gt 0) {
                $GrpNames = $U.MemberOf | ForEach-Object {
                    if ($_ -match '^CN=([^,]+)') { $Matches[1] } else { $_ }
                }
                "[$($GrpNames -join ', ')]"
            }
            else { '' }
            $null = $Sb.AppendLine("$($U.SamAccountName.PadRight(20)) $FullName  $Groups".TrimEnd())
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($Data.Groups -and $Data.Groups.Count -gt 0) {
        $null = $Sb.AppendLine("## Groups ($($Data.Groups.Count))")
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($G in ($Data.Groups | Sort-Object { $_.Name })) {
            $Scope = if ($G.GroupScope) { " [$($G.GroupScope)]" } else { '' }
            $MemberCount = if ($G.Members) { $G.Members.Count } else { 0 }
            $Members = if ($G.Members -and $G.Members.Count -gt 0) {
                "  [$(($G.Members | Select-Object -First 5) -join ', ')]"
            }
            else { '' }
            $null = $Sb.AppendLine("$($G.Name)$Scope  ($MemberCount members)$Members")
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats DHCP collector data as Markdown.
.DESCRIPTION
    Renders DHCP server authorization status, scopes, exclusions, options,
    and reservations from the DHCP collector result into a Markdown document.
.PARAMETER Data
    Hashtable of structured data from the Dhcp collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-DhcpDataMarkdown -Data $CollectorResult.Data
#>
function Format-DhcpDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Fence = '```'
    $Sb = [System.Text.StringBuilder]::new()

    $null = $Sb.AppendLine('## DHCP Server')
    $null = $Sb.AppendLine()
    $null = $Sb.AppendLine($Fence + 'text')
    $null = $Sb.AppendLine("Authorized:  $($Data.IsAuthorized)")
    $null = $Sb.AppendLine($Fence)
    $null = $Sb.AppendLine()

    if ($Data.Scopes -and $Data.Scopes.Count -gt 0) {
        foreach ($S in $Data.Scopes) {
            $null = $Sb.AppendLine("## Scope: $($S.Name) ($($S.ScopeId))")
            $null = $Sb.AppendLine()
            $ScopePairs = @(
                @('Range', "$($S.StartRange) – $($S.EndRange)"),
                @('Subnet Mask', "$($S.SubnetMask)"),
                @('State', "$($S.State)")
            )
            $MaxKeyLen = 0
            foreach ($P in $ScopePairs) { if ($P[0].Length -gt $MaxKeyLen) { $MaxKeyLen = $P[0].Length } }
            $null = $Sb.AppendLine($Fence + 'text')
            foreach ($P in $ScopePairs) {
                $Pad = ' ' * ($MaxKeyLen - $P[0].Length + 2)
                $null = $Sb.AppendLine("$($P[0]):$Pad$($P[1])")
            }
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()

            if ($S.Exclusions -and $S.Exclusions.Count -gt 0) {
                $null = $Sb.AppendLine('### Exclusions')
                $null = $Sb.AppendLine()
                $MaxStart = 0
                foreach ($E in $S.Exclusions) { if ($E.StartRange.Length -gt $MaxStart) { $MaxStart = $E.StartRange.Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($E in $S.Exclusions) {
                    $Pad = ' ' * ($MaxStart - $E.StartRange.Length + 2)
                    $null = $Sb.AppendLine("$($E.StartRange)$Pad– $($E.EndRange)")
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }

            if ($S.Options -and $S.Options.Count -gt 0) {
                $null = $Sb.AppendLine('### Options')
                $null = $Sb.AppendLine()
                $MaxOpt = 0
                foreach ($O in $S.Options) { if ($O.Name.Length -gt $MaxOpt) { $MaxOpt = $O.Name.Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($O in $S.Options) {
                    $Pad = ' ' * ($MaxOpt - $O.Name.Length + 2)
                    $null = $Sb.AppendLine("$($O.Name):$Pad$(($O.Value -join ', '))")
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }

            if ($S.Reservations -and $S.Reservations.Count -gt 0) {
                $null = $Sb.AppendLine('### Reservations')
                $null = $Sb.AppendLine()
                $MaxIp = 0
                foreach ($Rv in $S.Reservations) { if ($Rv.IPAddress.Length -gt $MaxIp) { $MaxIp = $Rv.IPAddress.Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($Rv in $S.Reservations) {
                    $Pad = ' ' * ($MaxIp - $Rv.IPAddress.Length + 2)
                    $null = $Sb.AppendLine("$($Rv.IPAddress)$Pad$($Rv.Name)")
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Helper: formats a hashtable value as aligned key-value pairs for code blocks.
.PARAMETER Hash
    Hashtable to format.
.PARAMETER MaxKeyLen
    Maximum key length (for alignment). If 0, calculate from keys.
.OUTPUTS
    [string[]]  Array of formatted lines.
.EXAMPLE
    Format-HashtableAsCodeBlock -Hash $MyHash
#>
function Format-HashtableAsCodeBlock {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Hash,
        [Parameter()]                                                                              [int] $MaxKeyLen = 0
    )
    $ErrorActionPreference = 'Stop'

    if ($Hash.Count -eq 0) {
        return @()
    }

    # Calculate max key length if not provided
    if ($MaxKeyLen -eq 0) {
        foreach ($K in $Hash.Keys) {
            if ($K.Length -gt $MaxKeyLen) { $MaxKeyLen = $K.Length }
        }
    }

    $Lines = [System.Collections.Generic.List[string]]::new()
    foreach ($K in ($Hash.Keys | Sort-Object)) {
        $V = $Hash[$K]
        # If value is a hashtable, render recursively with 2-space extra indent
        if ($V -is [hashtable] -and $V.Count -gt 0) {
            $Lines.Add("${K}:")
            $NestedLines = Format-HashtableAsCodeBlock -Hash $V -MaxKeyLen 0
            foreach ($NLine in $NestedLines) {
                $Lines.Add("  $NLine")
            }
        }
        else {
            $Pad = ' ' * ($MaxKeyLen - $K.Length + 2)
            $Lines.Add("${K}:${Pad}$V")
        }
    }

    return $Lines.ToArray()
}

<#
.SYNOPSIS
    Formats Group Policy Object collector data as Markdown.
.DESCRIPTION
    Renders GPO names, status, links, and computer/user scope settings from the
    GPO collector result into a Markdown document with tables.
.PARAMETER Data
    Hashtable of structured data from the Gpo collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-GpoDataMarkdown -Data $CollectorResult.Data
#>
function Format-GpoDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Fence = '```'
    $Sb = [System.Text.StringBuilder]::new()

    if ($Data.Gpos -and $Data.Gpos.Count -gt 0) {
        foreach ($Gpo in ($Data.Gpos | Sort-Object { $_.Name })) {
            $null = $Sb.AppendLine("## GPO: $($Gpo.Name)")
            $null = $Sb.AppendLine()
            $null = $Sb.AppendLine($Fence + 'text')
            $null = $Sb.AppendLine("Status:  $($Gpo.Status)")
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()

            if ($Gpo.Links -and $Gpo.Links.Count -gt 0) {
                $null = $Sb.AppendLine('### Links')
                $null = $Sb.AppendLine()
                $MaxPath = 0
                foreach ($L in $Gpo.Links) { if ($L.SOMPath.Length -gt $MaxPath) { $MaxPath = $L.SOMPath.Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($L in $Gpo.Links) {
                    $En = if ($L.Enabled -eq 'true') { 'enabled' } else { 'disabled' }
                    $Pad = ' ' * ($MaxPath - $L.SOMPath.Length + 2)
                    $null = $Sb.AppendLine("$($L.SOMPath)$Pad$En")
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }

            foreach ($ScopeType in @('ComputerScope', 'UserScope')) {
                $ScopeData = $Gpo.$ScopeType
                if (-not $ScopeData -or $ScopeData.Count -eq 0) { continue }
                $ScopeLabel = if ($ScopeType -eq 'ComputerScope') { 'Computer Scope' } else { 'User Scope' }
                $ByType = $ScopeData | Group-Object Type
                foreach ($G in $ByType) {
                    if ($G.Name -eq 'NoSettings') { continue }
                    $null = $Sb.AppendLine("### $ScopeLabel — $($G.Name)")
                    $null = $Sb.AppendLine()
                    $MaxKey = 0
                    foreach ($Item in $G.Group) {
                        if ($Item.Settings -is [hashtable]) {
                            foreach ($K in $Item.Settings.Keys) {
                                if ($K.Length -gt $MaxKey) { $MaxKey = $K.Length }
                            }
                        }
                        else {
                            foreach ($Prop in ($Item.Settings.PSObject.Properties |
                                        Where-Object { $_.Name -ne 'PSTypeName' })) {
                                if ($Prop.Name.Length -gt $MaxKey) { $MaxKey = $Prop.Name.Length }
                            }
                        }
                    }
                    if ($MaxKey -gt 0) {
                        $null = $Sb.AppendLine($Fence + 'text')
                        $FirstItem = $true
                        foreach ($Item in $G.Group) {
                            if (-not $FirstItem) { $null = $Sb.AppendLine() }
                            $FirstItem = $false
                            if ($Item.Settings -is [hashtable]) {
                                $HashtableLines = Format-HashtableAsCodeBlock -Hash $Item.Settings -MaxKeyLen $MaxKey
                                foreach ($HLine in $HashtableLines) {
                                    $null = $Sb.AppendLine($HLine)
                                }
                            }
                            else {
                                foreach ($Prop in ($Item.Settings.PSObject.Properties |
                                            Where-Object { $_.Name -ne 'PSTypeName' })) {
                                    if ($Prop.Value -is [hashtable] -and $Prop.Value.Count -gt 0) {
                                        $null = $Sb.AppendLine("$($Prop.Name):")
                                        $NestedLines = Format-HashtableAsCodeBlock -Hash $Prop.Value
                                        foreach ($HLine in $NestedLines) {
                                            $null = $Sb.AppendLine("  $HLine")
                                        }
                                    }
                                    else {
                                        $Pad = ' ' * ($MaxKey - $Prop.Name.Length + 2)
                                        $null = $Sb.AppendLine("$($Prop.Name):$Pad$($Prop.Value)")
                                    }
                                }
                            }
                        }
                        $null = $Sb.AppendLine($Fence)
                        $null = $Sb.AppendLine()
                    }
                }
            }
        }
    }
    else {
        $null = $Sb.AppendLine('_No GPOs found._')
        $null = $Sb.AppendLine()
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats file-server collector data as Markdown.
.DESCRIPTION
    Renders SMB shares, share permissions, and non-inherited NTFS permissions
    from the FileServer collector result into a Markdown document with tables.
.PARAMETER Data
    Hashtable of structured data from the FileServer collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-FileServerDataMarkdown -Data $CollectorResult.Data
#>
function Format-FileServerDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Fence = '```'
    $Sb = [System.Text.StringBuilder]::new()

    if ($Data.Shares -and $Data.Shares.Count -gt 0) {
        foreach ($S in ($Data.Shares | Sort-Object { $_.Name })) {
            $null = $Sb.AppendLine("## Share: $($S.Name)")
            $null = $Sb.AppendLine()
            $null = $Sb.AppendLine($Fence + 'text')
            $null = $Sb.AppendLine("Path:  $($S.Path)")
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()

            if ($S.ShareAccess -and $S.ShareAccess.Count -gt 0) {
                $null = $Sb.AppendLine('### Share Permissions')
                $null = $Sb.AppendLine()
                $MaxAcc = 0
                foreach ($A in $S.ShareAccess) { if ($A.AccountName.Length -gt $MaxAcc) { $MaxAcc = $A.AccountName.Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($A in $S.ShareAccess) {
                    $Pad = ' ' * ($MaxAcc - $A.AccountName.Length + 2)
                    $null = $Sb.AppendLine("$($A.AccountName)$Pad$($A.AccessRight)")
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }
        }
    }

    if ($Data.Permissions -and $Data.Permissions.Count -gt 0) {
        $null = $Sb.AppendLine('## NTFS Permissions')
        $null = $Sb.AppendLine()
        foreach ($P in $Data.Permissions) {
            $null = $Sb.AppendLine("### $($P.ShareName) ($($P.Path))")
            $null = $Sb.AppendLine()
            $NonInherited = @($P.Permissions | Where-Object { -not $_.IsInherited })
            if ($NonInherited.Count -gt 0) {
                $MaxId = 0
                foreach ($Acl in $NonInherited) { if ($Acl.IdentityReference.Length -gt $MaxId) { $MaxId = $Acl.IdentityReference.Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($Acl in $NonInherited) {
                    $Pad = ' ' * ($MaxId - $Acl.IdentityReference.Length + 2)
                    $null = $Sb.AppendLine("$($Acl.IdentityReference)$Pad$($Acl.FileSystemRights) ($($Acl.AccessControlType))")
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats IIS collector data as Markdown.
.DESCRIPTION
    Renders IIS websites (with bindings and virtual directories) and application
    pools from the IIS collector result into a Markdown document with tables.
.PARAMETER Data
    Hashtable of structured data from the Iis collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-IisDataMarkdown -Data $CollectorResult.Data
#>
function Format-IisDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Fence = '```'
    $Sb = [System.Text.StringBuilder]::new()

    if ($Data.Websites -and $Data.Websites.Count -gt 0) {
        foreach ($Site in ($Data.Websites | Sort-Object { $_.Name })) {
            $null = $Sb.AppendLine("## Website: $($Site.Name) [$($Site.State)]")
            $null = $Sb.AppendLine()
            $null = $Sb.AppendLine($Fence + 'text')
            $null = $Sb.AppendLine("App Pool:  $($Site.AppPoolName)")
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()

            if ($Site.Bindings -and $Site.Bindings.Count -gt 0) {
                $null = $Sb.AppendLine('### Bindings')
                $null = $Sb.AppendLine()
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($B in $Site.Bindings) {
                    $null = $Sb.AppendLine($B.Uri)
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }

            if ($Site.VirtualDirectories -and $Site.VirtualDirectories.Count -gt 0) {
                $null = $Sb.AppendLine('### Virtual Directories')
                $null = $Sb.AppendLine()
                $MaxVd = 0
                foreach ($V in $Site.VirtualDirectories) { if ($V.VDirPath.Length -gt $MaxVd) { $MaxVd = $V.VDirPath.Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($V in $Site.VirtualDirectories) {
                    $Pad = ' ' * ($MaxVd - $V.VDirPath.Length + 2)
                    $null = $Sb.AppendLine("$($V.VDirPath)$Pad→ $($V.PhysicalPath)")
                }
                $null = $Sb.AppendLine($Fence)
                $null = $Sb.AppendLine()
            }
        }
    }

    if ($Data.AppPools -and $Data.AppPools.Count -gt 0) {
        $null = $Sb.AppendLine('## App Pools')
        $null = $Sb.AppendLine()
        $SortedPools = @($Data.AppPools | Sort-Object { $_.Name })
        $MaxPool = 0
        foreach ($Ap in $SortedPools) { if ($Ap.Name.Length -gt $MaxPool) { $MaxPool = $Ap.Name.Length } }
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($Ap in $SortedPools) {
            $Pad = ' ' * ($MaxPool - $Ap.Name.Length + 2)
            $null = $Sb.AppendLine("$($Ap.Name)$Pad[$($Ap.State)]  Pipeline=$($Ap.PipelineMode)  Runtime=$($Ap.RuntimeVersion)")
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats Docker collector data as Markdown.
.DESCRIPTION
    Renders Docker images, containers with port mappings, Dockerfile contents,
    and Compose file contents from the Docker collector result.
    File contents are wrapped in language-tagged code fences.
.PARAMETER Data
    Hashtable of structured data from the Docker collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-DockerDataMarkdown -Data $CollectorResult.Data
#>
function Format-DockerDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()
    $Fence = '```'

    if ($Data.Images -and $Data.Images.Count -gt 0) {
        $null = $Sb.AppendLine("## Images ($($Data.Images.Count))")
        $null = $Sb.AppendLine()
        $SortedImgs = @($Data.Images | Sort-Object { $_.Repository })
        $MaxImg = 0
        foreach ($Img in $SortedImgs) {
            $ImgKey = "$($Img.Repository):$($Img.Tag)"
            if ($ImgKey.Length -gt $MaxImg) { $MaxImg = $ImgKey.Length }
        }
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($Img in $SortedImgs) {
            $ImgKey = "$($Img.Repository):$($Img.Tag)"
            $Pad = ' ' * ($MaxImg - $ImgKey.Length + 2)
            $null = $Sb.AppendLine("$ImgKey$Pad$($Img.Size)")
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($Data.Containers -and $Data.Containers.Count -gt 0) {
        $null = $Sb.AppendLine("## Containers ($($Data.Containers.Count))")
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($C in ($Data.Containers | Sort-Object { $_.Name })) {
            $Ports = if ($C.Ports) { "  ports=$($C.Ports)" } else { '' }
            $null = $Sb.AppendLine("$($C.Name.PadRight(25)) [$($C.State)]  image=$($C.Image)$Ports")
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($Data.Dockerfile -and $Data.Dockerfile.Count -gt 0) {
        foreach ($Df in $Data.Dockerfile) {
            $null = $Sb.AppendLine("## Dockerfile: $($Df.Path)")
            $null = $Sb.AppendLine()
            $null = $Sb.AppendLine($Fence + 'dockerfile')
            $Lines = ($Df.Content -split "`n") | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ }
            foreach ($Line in ($Lines | Select-Object -First 20)) {
                $null = $Sb.AppendLine($Line)
            }
            if ($Lines.Count -gt 20) {
                $null = $Sb.AppendLine("# ... ($($Lines.Count - 20) more lines)")
            }
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()
        }
    }

    if ($Data.Compose -and $Data.Compose.Count -gt 0) {
        foreach ($Cf in $Data.Compose) {
            $null = $Sb.AppendLine("## Compose File: $($Cf.Path)")
            $null = $Sb.AppendLine()
            $null = $Sb.AppendLine($Fence + 'yaml')
            $Lines = ($Cf.Content -split "`n") | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ }
            foreach ($Line in ($Lines | Select-Object -First 30)) {
                $null = $Sb.AppendLine($Line)
            }
            if ($Lines.Count -gt 30) {
                $null = $Sb.AppendLine("# ... ($($Lines.Count - 30) more lines)")
            }
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()
        }
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats bash-history collector data as Markdown.
.DESCRIPTION
    Renders bash command history and command log entries from the BashHistory
    collector result into a Markdown document with numbered tables.
.PARAMETER Data
    Hashtable of structured data from the BashHistory collector.
.OUTPUTS
    [string]
.EXAMPLE
    Format-BashHistoryDataMarkdown -Data $CollectorResult.Data
#>
function Format-BashHistoryDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data
    )
    $ErrorActionPreference = 'Stop'
    $Fence = '```'
    $Sb = [System.Text.StringBuilder]::new()

    if ($Data.BashHistory -and $Data.BashHistory.Count -gt 0) {
        $null = $Sb.AppendLine("## Command History ($($Data.BashHistory.Count) commands)")
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        $I = 1
        foreach ($Cmd in $Data.BashHistory) {
            $Ts = if ($Cmd.Timestamp) { "[$($Cmd.Timestamp)] " } else { '' }
            $Num = "$I".PadLeft(4)
            $null = $Sb.AppendLine("$Num  $Ts$($Cmd.Command)")
            $I++
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }
    else {
        $null = $Sb.AppendLine('_No bash history entries._')
        $null = $Sb.AppendLine()
    }

    if ($Data.CmdLog -and $Data.CmdLog.Count -gt 0) {
        $null = $Sb.AppendLine("## Command Log ($($Data.CmdLog.Count) entries)")
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($Entry in $Data.CmdLog) {
            $Ts = if ($Entry.Timestamp) { "[$($Entry.Timestamp)] " } else { '' }
            $UserTag = if ($Entry.User) { "($($Entry.User)) " } else { '' }
            $Host2 = if ($Entry.RemoteHost) { " from $($Entry.RemoteHost)" } else { '' }
            $null = $Sb.AppendLine("${Ts}${UserTag}$($Entry.Command)${Host2}")
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    return $Sb.ToString()
}

<#
.SYNOPSIS
    Formats Apache or Nginx collector data as Markdown.
.DESCRIPTION
    Renders service state, virtual host configuration files, and index file
    contents (in language-tagged code fences) from the Apache or Nginx
    collector result.
.PARAMETER Data
    Hashtable of structured data from the Apache or Nginx collector.
.PARAMETER ServerType
    The web-server variant: 'Apache' or 'Nginx'.
.OUTPUTS
    [string]
.EXAMPLE
    Format-WebServerDataMarkdown -Data $CollectorResult.Data -ServerType 'Apache'
#>
function Format-WebServerDataMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                               [hashtable] $Data,
        [Parameter(Mandatory)][ValidateSet('Apache', 'Nginx')]                             [string] $ServerType
    )
    $ErrorActionPreference = 'Stop'
    $Sb = [System.Text.StringBuilder]::new()
    $Fence = '```'

    $null = $Sb.AppendLine('## Service Status')
    $null = $Sb.AppendLine()
    $SvcPairs = @(
        @('Service Enabled', "$($Data.ServiceEnabled)"),
        @('Service Running', "$($Data.ServiceRunning)"),
        @('Sites Available', "$($Data.SitesAvailable)"),
        @('Sites Enabled', "$($Data.SitesEnabled)")
    )
    $MaxKeyLen = 0
    foreach ($P in $SvcPairs) { if ($P[0].Length -gt $MaxKeyLen) { $MaxKeyLen = $P[0].Length } }
    $null = $Sb.AppendLine($Fence + 'text')
    foreach ($P in $SvcPairs) {
        $Pad = ' ' * ($MaxKeyLen - $P[0].Length + 2)
        $null = $Sb.AppendLine("$($P[0]):$Pad$($P[1])")
    }
    $null = $Sb.AppendLine($Fence)
    $null = $Sb.AppendLine()

    if ($Data.FirewallServices -and $Data.FirewallServices.Count -gt 0) {
        $null = $Sb.AppendLine('## Firewall Services')
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        $null = $Sb.AppendLine($Data.FirewallServices -join '  ')
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($null -ne $Data.MariaDbEnabled -or $null -ne $Data.MariaDbRunning) {
        $null = $Sb.AppendLine('## MariaDB')
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        $null = $Sb.AppendLine("Enabled:  $($Data.MariaDbEnabled)")
        $null = $Sb.AppendLine("Running:  $($Data.MariaDbRunning)")
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($null -ne $Data.PhpFpmEnabled -or $null -ne $Data.PhpFpmRunning) {
        $null = $Sb.AppendLine('## PHP-FPM')
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        $null = $Sb.AppendLine("Enabled:  $($Data.PhpFpmEnabled)")
        $null = $Sb.AppendLine("Running:  $($Data.PhpFpmRunning)")
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($ServerType -eq 'Apache') {
        if ($Data.HttpdConfListen -and $Data.HttpdConfListen.Count -gt 0) {
            $null = $Sb.AppendLine('## httpd.conf Listen')
            $null = $Sb.AppendLine()
            $null = $Sb.AppendLine($Fence + 'text')
            foreach ($Line in $Data.HttpdConfListen) {
                $null = $Sb.AppendLine($Line)
            }
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()
        }
        if ($Data.HttpdConfInclude -and $Data.HttpdConfInclude.Count -gt 0) {
            $null = $Sb.AppendLine('## httpd.conf IncludeOptional')
            $null = $Sb.AppendLine()
            $null = $Sb.AppendLine($Fence + 'text')
            foreach ($Line in $Data.HttpdConfInclude) {
                $null = $Sb.AppendLine($Line)
            }
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()
        }
    }

    if ($Data.Directories -and $Data.Directories.Count -gt 0) {
        $null = $Sb.AppendLine('## Directories')
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($Entry in $Data.Directories.GetEnumerator()) {
            $Marker = if ($Entry.Value) { 'OK     ' } else { 'MISSING' }
            $null = $Sb.AppendLine("[$Marker]  $($Entry.Key)")
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($Data.ConfFiles -and $Data.ConfFiles.Count -gt 0) {
        $null = $Sb.AppendLine("## Config Files ($($Data.ConfFiles.Count))")
        $null = $Sb.AppendLine()
        foreach ($Cf in $Data.ConfFiles) {
            $null = $Sb.AppendLine("### $($Cf.Name)")
            $null = $Sb.AppendLine()
            $ConfPairs = [System.Collections.Generic.List[string[]]]::new()
            if ($Cf.VirtualHost) { $null = $ConfPairs.Add(@('VirtualHost', ($Cf.VirtualHost -join ', '))) }
            if ($Cf.ServerName) { $null = $ConfPairs.Add(@('Server Name', ($Cf.ServerName -join ', '))) }
            if ($Cf.ServerAlias) { $null = $ConfPairs.Add(@('ServerAlias', ($Cf.ServerAlias -join ', '))) }
            if ($Cf.Listen) { $null = $ConfPairs.Add(@('Listen', ($Cf.Listen -join ', '))) }
            $RootProp = if ($ServerType -eq 'Nginx') { 'Root' } else { 'DocumentRoot' }
            if ($Cf.$RootProp) { $null = $ConfPairs.Add(@($RootProp, ($Cf.$RootProp -join ', '))) }
            if ($ConfPairs.Count -gt 0) {
                $MaxCk = 0
                foreach ($Cp in $ConfPairs) { if ($Cp[0].Length -gt $MaxCk) { $MaxCk = $Cp[0].Length } }
                $null = $Sb.AppendLine($Fence + 'text')
                foreach ($Cp in $ConfPairs) {
                    $Pad = ' ' * ($MaxCk - $Cp[0].Length + 2)
                    $null = $Sb.AppendLine("$($Cp[0]):$Pad$($Cp[1])")
                }
                $null = $Sb.AppendLine($Fence)
            }
            $null = $Sb.AppendLine()
        }
    }

    if ($Data.SymlinkFiles -and $Data.SymlinkFiles.Count -gt 0) {
        $null = $Sb.AppendLine('## Symlinks (sites-enabled)')
        $null = $Sb.AppendLine()
        $null = $Sb.AppendLine($Fence + 'text')
        foreach ($Sym in $Data.SymlinkFiles) {
            $Marker = if ($Sym.IsSymlink) { '→' } else { 'FILE' }
            $Target = if ($Sym.LinkTarget) { $Sym.LinkTarget } else { '(not a symlink)' }
            $null = $Sb.AppendLine("$($Sym.Name)  $Marker  $Target")
        }
        $null = $Sb.AppendLine($Fence)
        $null = $Sb.AppendLine()
    }

    if ($Data.CurlResults -and $Data.CurlResults.Count -gt 0) {
        $null = $Sb.AppendLine('## Curl Results')
        $null = $Sb.AppendLine()
        foreach ($Curl in $Data.CurlResults) {
            $null = $Sb.AppendLine("### $($Curl.Url)")
            $null = $Sb.AppendLine()
            if ($Curl.Error) {
                $null = $Sb.AppendLine("> Error: $($Curl.Error)")
            }
            elseif ($Curl.Content) {
                $Ext = if ($Curl.Url -match '\.php') { 'php' } else { 'html' }
                $null = $Sb.AppendLine($Fence + $Ext)
                $Preview = ($Curl.Content -split "`n") | Select-Object -First 10 |
                    ForEach-Object { $_.TrimEnd() }
                foreach ($Line in $Preview) {
                    $null = $Sb.AppendLine($Line)
                }
                $null = $Sb.AppendLine($Fence)
            }
            $null = $Sb.AppendLine()
        }
    }

    if ($Data.IndexFiles -and $Data.IndexFiles.Count -gt 0) {
        $null = $Sb.AppendLine("## Index Files ($($Data.IndexFiles.Count))")
        $null = $Sb.AppendLine()
        foreach ($Idx in $Data.IndexFiles) {
            $null = $Sb.AppendLine("### $($Idx.Path)")
            $null = $Sb.AppendLine()
            $Ext = [System.IO.Path]::GetExtension($Idx.Path).TrimStart('.').ToLower()
            $Lang = if ($Ext -in @('html', 'htm', 'php')) { $Ext } else { 'text' }
            $null = $Sb.AppendLine($Fence + $Lang)
            $Preview = ($Idx.Content -split "`n") | Select-Object -First 10 |
                ForEach-Object { $_.TrimEnd() }
            foreach ($Line in $Preview) {
                $null = $Sb.AppendLine($Line)
            }
            $null = $Sb.AppendLine($Fence)
            $null = $Sb.AppendLine()
        }
    }

    return $Sb.ToString()
}
