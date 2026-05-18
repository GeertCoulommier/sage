#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Format-CollectorData function and all sub-formatters.
.DESCRIPTION
    Tests: header rendering, unavailable service path, all 11 collector formatters,
    default/unknown collector fallback, error section, and PSCustomObject data coercion.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\Format-CollectorData.ps1'
    . $Sut
}

Describe 'Format-CollectorData' -Tag 'Unit' {

    # ── Shared helpers ────────────────────────────────────────────────────────────
    BeforeEach {
        $script:BaseParams = @{
            CollectorName = 'Dns'
            CategoryName  = 'DNS DC1'
            TargetName    = 'DC1'
        }
    }

    Context 'Header rendering' {
        It 'Includes the category name and target in the header' {
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true
                Data      = @{}
                Errors    = @()
            }
            $Result | Should -Match 'DNS DC1'
            $Result | Should -Match 'DC1'
        }

        It 'Renders box-drawing characters in the header' {
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true
                Data      = @{}
                Errors    = @()
            }
            $Result | Should -Match '╔'
            $Result | Should -Match '╚'
        }
    }

    Context 'Unavailable service' {
        It 'Shows unavailable reason when Available is false' {
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $false
                Reason    = 'DNS service not running'
                Data      = @{}
                Errors    = @()
            }
            $Result | Should -Match 'Service unavailable'
            $Result | Should -Match 'DNS service not running'
        }

        It 'Returns early without formatting data when unavailable' {
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $false
                Reason    = 'Not installed'
                Data      = @{}
                Errors    = @()
            }
            $Result | Should -Not -Match 'Forward Zones'
        }
    }

    Context 'PSCustomObject data coercion' {
        It 'Converts PSCustomObject Data to hashtable before formatting' {
            $DataObj = [PSCustomObject]@{
                Hostname    = 'TEST-SRV'
                IpAddresses = @()
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true
                Data      = $DataObj
                Errors    = @()
            } -CollectorName 'GeneralConfig' -CategoryName 'General' -TargetName 'SRV1'
            $Result | Should -Match 'TEST-SRV'
        }
    }

    Context 'Collector errors section' {
        It 'Appends error lines when Errors array is non-empty' {
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true
                Data      = @{}
                Errors    = @('Timeout on query', 'Access denied')
            }
            $Result | Should -Match 'Collector Errors'
            $Result | Should -Match 'Timeout on query'
            $Result | Should -Match 'Access denied'
        }

        It 'Does not show errors section when Errors is empty' {
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true
                Data      = @{}
                Errors    = @()
            }
            $Result | Should -Not -Match 'Collector Errors'
        }
    }

    Context 'Unknown collector fallback' {
        It 'Shows fallback message for unrecognized collector name' {
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true
                Data      = @{}
                Errors    = @()
            } -CollectorName 'UnknownCollector' -CategoryName 'Test' -TargetName 'VM1'
            $Result | Should -Match "No custom formatter for collector 'UnknownCollector'"
        }
    }

    # ── GeneralConfig formatter ───────────────────────────────────────────────────
    Context 'GeneralConfig formatter' {
        It 'Renders hostname and IP address details' {
            $Data = @{
                Hostname    = 'DC1'
                IpAddresses = @(
                    @{
                        InterfaceAlias = 'Ethernet'
                        IPAddress      = '192.168.1.10'
                        PrefixLength   = 24
                        Gateway        = '192.168.1.1'
                        DnsServers     = @('192.168.1.1', '8.8.8.8')
                    }
                )
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'GeneralConfig' -CategoryName 'General' -TargetName 'DC1'
            $Result | Should -Match 'Hostname : DC1'
            $Result | Should -Match 'Ethernet'
            $Result | Should -Match '192.168.1.10/24'
            $Result | Should -Match 'Gateway: 192.168.1.1'
            $Result | Should -Match '192.168.1.1, 8.8.8.8'
        }

        It 'Renders hostname alone when IpAddresses is null' {
            $Data = @{ Hostname = 'SRV01'; IpAddresses = $null }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'GeneralConfig' -CategoryName 'General' -TargetName 'SRV01'
            $Result | Should -Match 'Hostname : SRV01'
        }
    }

    # ── DNS formatter ─────────────────────────────────────────────────────────────
    Context 'Dns formatter' {
        It 'Renders forward zones with records grouped by type' {
            $Data = @{
                Zones      = @(
                    @{
                        ZoneName            = 'example.com'
                        IsReverseLookupZone = $false
                        IsDsIntegrated      = $true
                        ZoneType            = 'Primary'
                    }
                )
                Records    = @(
                    @{
                        ZoneName   = 'example.com'
                        RecordType = 'A'
                        HostName   = 'dc1'
                        Value      = '192.168.1.10'
                    },
                    @{
                        ZoneName   = 'example.com'
                        RecordType = 'CNAME'
                        HostName   = 'www'
                        Value      = 'dc1.example.com'
                    }
                )
                Forwarders = @()
            }
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            }
            $Result | Should -Match 'Forward Zones'
            $Result | Should -Match 'example.com \(Primary\)'
            $Result | Should -Match 'AD-integrated'
            $Result | Should -Match '\[A\]'
            $Result | Should -Match 'dc1'
            $Result | Should -Match '\[CNAME\]'
        }

        It 'Filters out AD-internal zones' {
            $Data = @{
                Zones      = @(
                    @{
                        ZoneName            = '_msdcs.example.com'
                        IsReverseLookupZone = $false
                        IsDsIntegrated      = $true
                        ZoneType            = 'Primary'
                    },
                    @{
                        ZoneName            = 'TrustAnchors'
                        IsReverseLookupZone = $false
                        IsDsIntegrated      = $false
                        ZoneType            = 'Primary'
                    }
                )
                Records    = @()
                Forwarders = @()
            }
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            }
            $Result | Should -Not -Match 'Forward Zones'
        }

        It 'Skips SOA records' {
            $Data = @{
                Zones      = @(@{
                        ZoneName            = 'example.com'
                        IsReverseLookupZone = $false
                        IsDsIntegrated      = $false
                        ZoneType            = 'Primary'
                    })
                Records    = @(@{
                        ZoneName   = 'example.com'
                        RecordType = 'SOA'
                        HostName   = '@'
                        Value      = 'ns1.example.com'
                    })
                Forwarders = @()
            }
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            }
            $Result | Should -Not -Match '\[SOA\]'
        }

        It 'Renders reverse zones with PTR records' {
            $Data = @{
                Zones      = @(
                    @{
                        ZoneName            = '1.168.192.in-addr.arpa'
                        IsReverseLookupZone = $true
                        IsDsIntegrated      = $false
                        ZoneType            = 'Primary'
                    }
                )
                Records    = @(
                    @{
                        ZoneName   = '1.168.192.in-addr.arpa'
                        RecordType = 'PTR'
                        HostName   = '10'
                        Value      = 'dc1.example.com'
                    }
                )
                Forwarders = @()
            }
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            }
            $Result | Should -Match 'Reverse Zones'
            $Result | Should -Match '1.168.192.in-addr.arpa'
            $Result | Should -Match 'dc1.example.com'
        }

        It 'Filters out standard reverse zones from reverse section' {
            $Data = @{
                Zones      = @(
                    @{
                        ZoneName            = '0.in-addr.arpa'
                        IsReverseLookupZone = $true
                        ZoneType            = 'Primary'
                    },
                    @{
                        ZoneName            = '127.in-addr.arpa'
                        IsReverseLookupZone = $true
                        ZoneType            = 'Primary'
                    }
                )
                Records    = @()
                Forwarders = @()
            }
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            }
            $Result | Should -Not -Match 'Reverse Zones'
        }

        It 'Renders forwarders when present' {
            $Data = @{
                Zones      = @()
                Records    = @()
                Forwarders = @(
                    @{ IPAddress = '8.8.8.8' },
                    @{ IPAddress = '1.1.1.1' }
                )
            }
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            }
            $Result | Should -Match 'Forwarders'
            $Result | Should -Match '8.8.8.8'
            $Result | Should -Match '1.1.1.1'
        }

        It 'Renders non-AD-integrated zone without the AD tag' {
            $Data = @{
                Zones      = @(@{
                        ZoneName            = 'example.com'
                        IsReverseLookupZone = $false
                        IsDsIntegrated      = $false
                        ZoneType            = 'Secondary'
                    })
                Records    = @()
                Forwarders = @()
            }
            $Result = Format-CollectorData @script:BaseParams -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            }
            $Result | Should -Not -Match 'AD-integrated'
        }
    }

    # ── AD formatter ──────────────────────────────────────────────────────────────
    Context 'Ad formatter' {
        It 'Renders domain info, computers, OUs, users, and groups' {
            $Data = @{
                DomainName            = 'example.com'
                PartOfDomain          = $true
                DomainFunctionalLevel = 'Windows2016Domain'
                ForestFunctionalLevel = 'Windows2016Forest'
                Computers             = @(@{ Name = 'DC1'; DistinguishedName = 'CN=DC1,OU=DCs,DC=example,DC=com' })
                OUs                   = @(@{ Name = 'Users'; DistinguishedName = 'OU=Users,DC=example,DC=com' })
                Users                 = @(@{
                        SamAccountName = 'jdoe'
                        GivenName      = 'John'
                        Surname        = 'Doe'
                        MemberOf       = @('Domain Admins', 'IT Staff')
                    })
                Groups                = @(@{
                        Name       = 'IT Staff'
                        GroupScope = 'Global'
                        Members    = @('jdoe', 'jsmith')
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Ad' -CategoryName 'Active Directory' -TargetName 'DC1'
            $Result | Should -Match 'example.com'
            $Result | Should -Match 'Part of Domain.*True'
            $Result | Should -Match 'Domain Computers'
            $Result | Should -Match 'DC1'
            $Result | Should -Match 'Organizational Units'
            $Result | Should -Match 'Users'
            $Result | Should -Match 'jdoe'
            $Result | Should -Match 'John Doe'
            $Result | Should -Match 'MemberOf: Domain Admins'
            $Result | Should -Match 'IT Staff.*Global.*2 members'
            $Result | Should -Match '- jdoe'
        }

        It 'Handles null PartOfDomain as N/A' {
            $Data = @{
                DomainName            = 'test.com'
                PartOfDomain          = $null
                DomainFunctionalLevel = 'Level'
                ForestFunctionalLevel = 'Level'
                Computers             = @()
                OUs                   = @()
                Users                 = @()
                Groups                = @()
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Ad' -CategoryName 'AD' -TargetName 'DC1'
            $Result | Should -Match 'Part of Domain.*N/A'
        }

        It 'Handles Computer without DistinguishedName' {
            $Data = @{
                DomainName            = 'test.com'
                PartOfDomain          = $true
                DomainFunctionalLevel = 'Level'
                ForestFunctionalLevel = 'Level'
                Computers             = @(@{ Name = 'SRV1' })
                OUs                   = @()
                Users                 = @()
                Groups                = @()
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Ad' -CategoryName 'AD' -TargetName 'DC1'
            $Result | Should -Match 'SRV1'
        }

        It 'Handles Group without GroupScope and no Members' {
            $Data = @{
                DomainName            = 'test.com'
                PartOfDomain          = $true
                DomainFunctionalLevel = 'Level'
                ForestFunctionalLevel = 'Level'
                Computers             = @()
                OUs                   = @()
                Users                 = @()
                Groups                = @(@{
                        Name       = 'EmptyGroup'
                        GroupScope = $null
                        Members    = $null
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Ad' -CategoryName 'AD' -TargetName 'DC1'
            $Result | Should -Match 'EmptyGroup'
            $Result | Should -Match '0 members'
        }

        It 'Handles User without MemberOf' {
            $Data = @{
                DomainName            = 'test.com'
                PartOfDomain          = $true
                DomainFunctionalLevel = 'Level'
                ForestFunctionalLevel = 'Level'
                Computers             = @()
                OUs                   = @()
                Users                 = @(@{
                        SamAccountName = 'jdoe'
                        GivenName      = 'John'
                        Surname        = 'Doe'
                        MemberOf       = @()
                    })
                Groups                = @()
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Ad' -CategoryName 'AD' -TargetName 'DC1'
            $Result | Should -Match 'jdoe'
            $Result | Should -Not -Match 'MemberOf:'
        }
    }

    # ── DHCP formatter ────────────────────────────────────────────────────────────
    Context 'Dhcp formatter' {
        It 'Renders scopes with exclusions, options, and reservations' {
            $Data = @{
                IsAuthorized = $true
                Scopes       = @(@{
                        Name         = 'LAN'
                        ScopeId      = '192.168.1.0'
                        StartRange   = '192.168.1.100'
                        EndRange     = '192.168.1.200'
                        SubnetMask   = '255.255.255.0'
                        State        = 'Active'
                        Exclusions   = @(@{ StartRange = '192.168.1.150'; EndRange = '192.168.1.160' })
                        Options      = @(@{ Name = 'Router'; Value = @('192.168.1.1') })
                        Reservations = @(@{ IPAddress = '192.168.1.50'; Name = 'Printer' })
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Dhcp' -CategoryName 'DHCP' -TargetName 'DC1'
            $Result | Should -Match 'Authorized: True'
            $Result | Should -Match 'Scope: LAN'
            $Result | Should -Match '192.168.1.100 - 192.168.1.200'
            $Result | Should -Match 'Exclusions'
            $Result | Should -Match '192.168.1.150 - 192.168.1.160'
            $Result | Should -Match 'Router'
            $Result | Should -Match 'Reservations'
            $Result | Should -Match 'Printer'
        }

        It 'Renders authorized flag with no scopes' {
            $Data = @{ IsAuthorized = $false; Scopes = @() }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Dhcp' -CategoryName 'DHCP' -TargetName 'DC1'
            $Result | Should -Match 'Authorized: False'
        }

        It 'Scope without optional blocks' {
            $Data = @{
                IsAuthorized = $true
                Scopes       = @(@{
                        Name         = 'Basic'
                        ScopeId      = '10.0.0.0'
                        StartRange   = '10.0.0.10'
                        EndRange     = '10.0.0.100'
                        SubnetMask   = '255.255.255.0'
                        State        = 'Active'
                        Exclusions   = @()
                        Options      = @()
                        Reservations = @()
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Dhcp' -CategoryName 'DHCP' -TargetName 'DC1'
            $Result | Should -Match 'Scope: Basic'
            $Result | Should -Not -Match 'Exclusions'
            $Result | Should -Not -Match 'Reservations:'
        }
    }

    # ── GPO formatter ─────────────────────────────────────────────────────────────
    Context 'Gpo formatter' {
        It 'Renders GPOs with links and scoped settings' {
            $Data = @{
                Gpos = @(@{
                        Name          = 'Password Policy'
                        Status        = 'AllSettingsEnabled'
                        Links         = @(@{ SOMPath = 'example.com'; Enabled = 'true' })
                        ComputerScope = @(@{
                                Type     = 'SecurityPolicy'
                                Settings = [PSCustomObject]@{
                                    MinPasswordLength = 8
                                    MaxPasswordAge    = 90
                                }
                            })
                        UserScope     = @(@{
                                Type     = 'Registry'
                                Settings = [PSCustomObject]@{
                                    WallpaperPath = 'C:\bg.jpg'
                                }
                            })
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Gpo' -CategoryName 'GPO' -TargetName 'DC1'
            $Result | Should -Match 'Password Policy'
            $Result | Should -Match 'AllSettingsEnabled'
            $Result | Should -Match 'example.com \[enabled\]'
            $Result | Should -Match 'Computer > SecurityPolicy'
            $Result | Should -Match 'MinPasswordLength=8'
            $Result | Should -Match 'User > Registry'
            $Result | Should -Match 'WallpaperPath='
        }

        It 'Shows no GPOs message when Gpos is empty' {
            $Data = @{ Gpos = @() }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Gpo' -CategoryName 'GPO' -TargetName 'DC1'
            $Result | Should -Match 'No GPOs found'
        }

        It 'Renders disabled link correctly' {
            $Data = @{
                Gpos = @(@{
                        Name          = 'Test GPO'
                        Status        = 'Enabled'
                        Links         = @(@{ SOMPath = 'test.com'; Enabled = 'false' })
                        ComputerScope = @()
                        UserScope     = @()
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Gpo' -CategoryName 'GPO' -TargetName 'DC1'
            $Result | Should -Match '\[disabled\]'
        }

        It 'Skips NoSettings scope type' {
            $Data = @{
                Gpos = @(@{
                        Name          = 'EmptyGPO'
                        Status        = 'Enabled'
                        Links         = @()
                        ComputerScope = @(@{ Type = 'NoSettings'; Settings = [PSCustomObject]@{} })
                        UserScope     = @()
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Gpo' -CategoryName 'GPO' -TargetName 'DC1'
            $Result | Should -Not -Match 'Computer > NoSettings'
        }
    }

    # ── FileServer formatter ──────────────────────────────────────────────────────
    Context 'FileServer formatter' {
        It 'Renders shares with permissions and NTFS ACLs' {
            $Data = @{
                Shares      = @(@{
                        Name        = 'Data$'
                        Path        = 'D:\Data'
                        ShareAccess = @(@{
                                AccountName = 'DOMAIN\Users'
                                AccessRight = 'Read'
                            })
                    })
                Permissions = @(@{
                        ShareName   = 'Data$'
                        Path        = 'D:\Data'
                        Permissions = @(
                            @{
                                IdentityReference = 'DOMAIN\Admins'
                                FileSystemRights  = 'FullControl'
                                AccessControlType = 'Allow'
                                IsInherited       = $false
                            },
                            @{
                                IdentityReference = 'BUILTIN\Users'
                                FileSystemRights  = 'Read'
                                AccessControlType = 'Allow'
                                IsInherited       = $true
                            }
                        )
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'FileServer' -CategoryName 'File Server' -TargetName 'SRV1'
            $Result | Should -Match 'Share: Data\$'
            $Result | Should -Match 'D:\\Data'
            $Result | Should -Match 'Share Permissions'
            $Result | Should -Match 'DOMAIN\\Users.*Read'
            $Result | Should -Match 'NTFS Permissions'
            $Result | Should -Match 'DOMAIN\\Admins.*FullControl.*Allow'
            # Inherited ACL should be filtered out
            $Result | Should -Not -Match 'BUILTIN\\Users'
        }
    }

    # ── IIS formatter ─────────────────────────────────────────────────────────────
    Context 'Iis formatter' {
        It 'Renders websites with bindings, vdirs, and app pools' {
            $Data = @{
                Websites = @(@{
                        Name               = 'Default Web Site'
                        State              = 'Started'
                        AppPoolName        = 'DefaultAppPool'
                        Bindings           = @(@{ Uri = 'http://*:80' })
                        VirtualDirectories = @(@{
                                VDirPath     = '/app'
                                PhysicalPath = 'C:\inetpub\app'
                            })
                    })
                AppPools = @(@{
                        Name           = 'DefaultAppPool'
                        State          = 'Started'
                        PipelineMode   = 'Integrated'
                        RuntimeVersion = 'v4.0'
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Iis' -CategoryName 'IIS' -TargetName 'WEB1'
            $Result | Should -Match 'Website: Default Web Site \[Started\]'
            $Result | Should -Match 'AppPool: DefaultAppPool'
            $Result | Should -Match 'http://\*:80'
            $Result | Should -Match '/app.*C:\\inetpub\\app'
            $Result | Should -Match 'App Pools'
            $Result | Should -Match 'DefaultAppPool.*Started.*Integrated.*v4.0'
        }
    }

    # ── Docker formatter ──────────────────────────────────────────────────────────
    Context 'Docker formatter' {
        It 'Renders images, containers, compose files, and dockerfiles' {
            $Data = @{
                Images     = @(@{ Repository = 'nginx'; Tag = 'latest'; Size = '142MB' })
                Containers = @(@{
                        Name  = 'web'
                        State = 'Running'
                        Image = 'nginx:latest'
                        Ports = '0.0.0.0:80->80/tcp'
                    })
                Dockerfile = @(@{
                        Path    = '/app/Dockerfile'
                        Content = "FROM nginx:latest`nCOPY . /usr/share/nginx`nEXPOSE 80"
                    })
                Compose    = @(@{
                        Path    = '/app/docker-compose.yml'
                        Content = "version: '3'`nservices:`n  web:`n    image: nginx"
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Docker' -CategoryName 'Docker' -TargetName 'LNX1'
            $Result | Should -Match 'Images \(1\)'
            $Result | Should -Match 'nginx:latest'
            $Result | Should -Match 'Containers \(1\)'
            $Result | Should -Match 'web.*Running.*Image=nginx:latest'
            $Result | Should -Match '0.0.0.0:80->80/tcp'
            $Result | Should -Match 'Dockerfiles \(1\)'
            $Result | Should -Match 'FROM nginx:latest'
            $Result | Should -Match 'Compose Files \(1\)'
        }

        It 'Handles container without Ports' {
            $Data = @{
                Images     = @()
                Containers = @(@{
                        Name  = 'app'
                        State = 'Exited'
                        Image = 'myapp:1.0'
                        Ports = $null
                    })
                Dockerfile = @()
                Compose    = @()
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Docker' -CategoryName 'Docker' -TargetName 'LNX1'
            $Result | Should -Match 'app.*Exited'
            $Result | Should -Not -Match 'Ports:'
        }

        It 'Truncates Dockerfile content beyond 10 lines' {
            $Lines = (1..15 | ForEach-Object { "RUN echo line$_" }) -join "`n"
            $Data = @{
                Images     = @()
                Containers = @()
                Dockerfile = @(@{ Path = '/Dockerfile'; Content = $Lines })
                Compose    = @()
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Docker' -CategoryName 'Docker' -TargetName 'LNX1'
            $Result | Should -Match '5 more lines'
        }

        It 'Truncates Compose content beyond 15 lines' {
            $Lines = (1..20 | ForEach-Object { "  line${_}: value" }) -join "`n"
            $Data = @{
                Images     = @()
                Containers = @()
                Dockerfile = @()
                Compose    = @(@{ Path = '/compose.yml'; Content = $Lines })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Docker' -CategoryName 'Docker' -TargetName 'LNX1'
            $Result | Should -Match '5 more lines'
        }
    }

    # ── BashHistory formatter ─────────────────────────────────────────────────────
    Context 'BashHistory formatter' {
        It 'Renders bash history entries with timestamps' {
            $Data = @{
                BashHistory = @(
                    @{ Timestamp = '2026-01-01 10:00'; Command = 'apt update' },
                    @{ Timestamp = $null; Command = 'ls -la' }
                )
                CmdLog      = @(
                    @{
                        Timestamp  = '2026-01-01 11:00'
                        User       = 'root'
                        Command    = 'visudo'
                        RemoteHost = '10.0.0.5'
                    }
                )
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'BashHistory' -CategoryName 'Bash History' -TargetName 'LNX1'
            $Result | Should -Match 'Bash History \(2 commands\)'
            $Result | Should -Match '\[2026-01-01 10:00\] apt update'
            $Result | Should -Match 'ls -la'
            $Result | Should -Match 'Cmd Log \(1 entries\)'
            $Result | Should -Match '\[2026-01-01 11:00\]'
            $Result | Should -Match '\(root\)'
            $Result | Should -Match 'visudo'
            $Result | Should -Match 'from 10.0.0.5'
        }

        It 'Shows empty history message when BashHistory is empty' {
            $Data = @{ BashHistory = @(); CmdLog = @() }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'BashHistory' -CategoryName 'Bash History' -TargetName 'LNX1'
            $Result | Should -Match 'No bash history entries'
        }

        It 'Handles CmdLog entry without optional fields' {
            $Data = @{
                BashHistory = @()
                CmdLog      = @(@{
                        Timestamp  = $null
                        User       = $null
                        Command    = 'hostname'
                        RemoteHost = $null
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'BashHistory' -CategoryName 'Bash History' -TargetName 'LNX1'
            $Result | Should -Match 'hostname'
            $Result | Should -Not -Match 'from '
        }
    }

    # ── Apache formatter (WebServer) ──────────────────────────────────────────────
    Context 'Apache formatter' {
        It 'Renders Apache web server data with config files and index files' {
            $Data = @{
                ServiceEnabled = $true
                ServiceRunning = $true
                SitesAvailable = 2
                SitesEnabled   = 1
                ConfFiles      = @(@{
                        Name         = '000-default.conf'
                        ServerName   = @('www.example.com')
                        Listen       = @('80')
                        DocumentRoot = @('/var/www/html')
                    })
                IndexFiles     = @(@{
                        Path    = '/var/www/html/index.html'
                        Content = "<html>`n<body>`nHello`n</body>`n</html>"
                    })
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Apache' -CategoryName 'Apache' -TargetName 'LNX1'
            $Result | Should -Match 'Service Enabled: True'
            $Result | Should -Match 'Service Running: True'
            $Result | Should -Match 'Sites Available: 2'
            $Result | Should -Match 'Sites Enabled  : 1'
            $Result | Should -Match '000-default.conf'
            $Result | Should -Match 'ServerName.*www.example.com'
            $Result | Should -Match 'Listen.*80'
            $Result | Should -Match 'DocumentRoot.*/var/www/html'
            $Result | Should -Match 'Index Files'
            $Result | Should -Match 'Hello'
        }
    }

    # ── Nginx formatter (WebServer) ───────────────────────────────────────────────
    Context 'Nginx formatter' {
        It 'Uses Root property instead of DocumentRoot for Nginx' {
            $Data = @{
                ServiceEnabled = $true
                ServiceRunning = $true
                SitesAvailable = 1
                SitesEnabled   = 1
                ConfFiles      = @(@{
                        Name       = 'default'
                        ServerName = @('example.com')
                        Listen     = @('80')
                        Root       = @('/var/www/html')
                    })
                IndexFiles     = @()
            }
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Nginx' -CategoryName 'Nginx' -TargetName 'LNX1'
            $Result | Should -Match 'Root.*/var/www/html'
        }
    }

    # ── Null/empty Data edge case ────────────────────────────────────────────────
    Context 'Non-hashtable/non-PSCustomObject data' {
        It 'Uses empty hashtable when Data is neither hashtable nor PSCustomObject' {
            $Result = Format-CollectorData -CollectorResult @{
                Available = $true
                Data      = 'just-a-string'
                Errors    = @()
            } -CollectorName 'GeneralConfig' -CategoryName 'General' -TargetName 'SRV'
            $Result | Should -Match 'Hostname :'
        }
    }
}

Describe 'Format-CollectorDataMarkdown' -Tag 'Unit' {

    BeforeEach {
        $script:MdBaseParams = @{
            CollectorName = 'Dns'
            CategoryName  = 'DNS DC1'
            TargetName    = 'DC1'
        }
    }

    Context 'H1 heading' {
        It 'Produces an H1 heading with category and target' {
            $Result = Format-CollectorDataMarkdown @script:MdBaseParams -CollectorResult @{
                Available = $true
                Data      = @{}
                Errors    = @()
            }
            $Result | Should -Match '^# DNS DC1 \[DC1\]'
        }
    }

    Context 'Unavailable service' {
        It 'Renders a blockquote warning when Available is false' {
            $Result = Format-CollectorDataMarkdown @script:MdBaseParams -CollectorResult @{
                Available = $false
                Reason    = 'DNS not running'
                Data      = @{}
                Errors    = @()
            }
            $Result | Should -Match '> ⚠ Service unavailable'
            $Result | Should -Match 'DNS not running'
        }

        It 'Does not render body content when unavailable' {
            $Result = Format-CollectorDataMarkdown @script:MdBaseParams -CollectorResult @{
                Available = $false
                Reason    = 'Off'
                Data      = @{}
                Errors    = @()
            }
            $Result | Should -Not -Match '## '
        }
    }

    Context 'PSCustomObject data coercion' {
        It 'Converts PSCustomObject Data to hashtable before formatting' {
            $DataObj = [PSCustomObject]@{
                Hostname    = 'TEST-SRV'
                IpAddresses = @()
            }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true
                Data      = $DataObj
                Errors    = @()
            } -CollectorName 'GeneralConfig' -CategoryName 'General' -TargetName 'SRV1'
            $Result | Should -Match 'TEST-SRV'
        }
    }

    Context 'Collector errors section' {
        It 'Renders an H2 Collector Errors heading and bullet items' {
            $Result = Format-CollectorDataMarkdown @script:MdBaseParams -CollectorResult @{
                Available = $true
                Data      = @{}
                Errors    = @('Timeout', 'Access denied')
            }
            $Result | Should -Match '## Collector Errors'
            $Result | Should -Match '- ⚠ Timeout'
            $Result | Should -Match '- ⚠ Access denied'
        }

        It 'Does not show errors section when Errors is empty' {
            $Result = Format-CollectorDataMarkdown @script:MdBaseParams -CollectorResult @{
                Available = $true
                Data      = @{}
                Errors    = @()
            }
            $Result | Should -Not -Match 'Collector Errors'
        }
    }

    Context 'Unknown collector fallback' {
        It 'Shows italic fallback message for unrecognised collector' {
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true
                Data      = @{}
                Errors    = @()
            } -CollectorName 'UnknownXyz' -CategoryName 'Test' -TargetName 'VM1'
            $Result | Should -Match "No custom formatter for collector 'UnknownXyz'"
        }
    }

    # ── GeneralConfig Markdown ────────────────────────────────────────────────────
    Context 'GeneralConfig Markdown formatter' {
        It 'Renders hostname in a code block' {
            $Data = @{
                Hostname    = 'DC1'
                IpAddresses = @(
                    @{
                        InterfaceAlias = 'Ethernet'
                        IPAddress      = '192.168.1.10'
                        PrefixLength   = 24
                        Gateway        = '192.168.1.1'
                        DnsServers     = @('192.168.1.1', '8.8.8.8')
                    }
                )
            }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'GeneralConfig' -CategoryName 'General' -TargetName 'DC1'
            $Result | Should -Match 'Hostname:.*DC1'
            $Result | Should -Match '### Ethernet'
            $Result | Should -Match 'IP Address:.*192.168.1.10/24'
            $Result | Should -Match 'Gateway:.*192.168.1.1'
            $Result | Should -Match '192.168.1.1, 8.8.8.8'
        }
    }

    # ── DNS Markdown ──────────────────────────────────────────────────────────────
    Context 'Dns Markdown formatter' {
        It 'Renders forward zone headings and record tables' {
            $Data = @{
                Zones      = @(@{
                    ZoneName = 'example.com'; IsReverseLookupZone = $false
                    IsDsIntegrated = $true;   ZoneType = 'Primary'
                })
                Records    = @(@{
                    ZoneName = 'example.com'; RecordType = 'A'
                    HostName = 'dc1';          Value = '192.168.1.10'
                })
                Forwarders = @()
            }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Dns' -CategoryName 'DNS DC1' -TargetName 'DC1'
            $Result | Should -Match '## Forward Zones'
            $Result | Should -Match '### example.com \(Primary\) \[AD-integrated\]'
            $Result | Should -Match '#### A Records'
            $Result | Should -Match 'dc1.*192.168.1.10'
        }

        It 'Renders forwarders as bullet list' {
            $Data = @{
                Zones      = @()
                Records    = @()
                Forwarders = @(@{ IPAddress = '8.8.8.8' }, @{ IPAddress = '8.8.4.4' })
            }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Dns' -CategoryName 'DNS DC1' -TargetName 'DC1'
            $Result | Should -Match '## Forwarders'
            $Result | Should -Match '- 8.8.8.8'
            $Result | Should -Match '- 8.8.4.4'
        }
    }

    # ── Docker Markdown code fences ───────────────────────────────────────────────
    Context 'Docker Markdown formatter' {
        It 'Wraps Dockerfile content in a code fence' {
            $Data = @{
                Images     = @()
                Containers = @()
                Dockerfile = @(@{
                    Path    = '/home/student/Dockerfile'
                    Content = "FROM nginx:latest`nCOPY index.html /usr/share/nginx/html/"
                })
                Compose    = @()
            }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Docker' -CategoryName 'Docker' -TargetName 'Linux'
            $Result | Should -Match '## Dockerfile: /home/student/Dockerfile'
            $Result | Should -Match '```dockerfile'
            $Result | Should -Match 'FROM nginx:latest'
        }
    }

    # ── BashHistory Markdown ──────────────────────────────────────────────────────
    Context 'BashHistory Markdown formatter' {
        It 'Renders command history as a code block' {
            $Data = @{
                BashHistory = @(
                    @{ Timestamp = '2026-01-01 10:00'; Command = 'apt-get update' }
                )
                CmdLog = @()
            }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'BashHistory' -CategoryName 'BashHistory' -TargetName 'Linux'
            $Result | Should -Match '## Command History \(1 commands\)'
            $Result | Should -Match 'apt-get update'
        }

        It 'Renders italic message when BashHistory is empty' {
            $Data = @{ BashHistory = @(); CmdLog = @() }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'BashHistory' -CategoryName 'BashHistory' -TargetName 'Linux'
            $Result | Should -Match '_No bash history entries._'
        }
    }

    # ── GPO Markdown ──────────────────────────────────────────────────────────────
    Context 'Gpo Markdown formatter' {

        It 'Renders SoftwareInstallation hashtable settings as aligned key-value pairs' {
            $Data = @{
                Gpos = @(@{
                    Name          = '7-zip install'
                    Status        = 'AllSettingsEnabled'
                    Links         = @(@{ SOMPath = 'voornaam.local/Gebouw A/Lokaal A01'; Enabled = 'true' })
                    ComputerScope = @(@{
                        Type     = 'SoftwareInstallation'
                        Settings = @{
                            Name           = '7-Zip 26.00 (x64 edition)'
                            Path           = '\\dc1\Shared\public\software\7-zip\7z2600-x64.msi'
                            PathExists     = $true
                            DeploymentType = 'Assign'
                        }
                    })
                    UserScope     = @()
                })
            }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Gpo' -CategoryName 'Group Policy' -TargetName 'DC1'
            # Must contain the GPO and scope heading
            $Result | Should -Match '## GPO: 7-zip install'
            $Result | Should -Match '### Computer Scope'
            # Key-value pairs must appear, NOT internal hashtable properties
            $Result | Should -Match 'DeploymentType'
            $Result | Should -Match 'Assign'
            $Result | Should -Match '7-Zip 26.00'
            $Result | Should -Not -Match 'IsReadOnly'
            $Result | Should -Not -Match 'IsFixedSize'
            $Result | Should -Not -Match 'SyncRoot'
        }

        It 'Renders PSCustomObject settings as key-value pairs' {
            $Data = @{
                Gpos = @(@{
                    Name          = 'Password Policy'
                    Status        = 'AllSettingsEnabled'
                    Links         = @()
                    ComputerScope = @(@{
                        Type     = 'SecurityPolicy'
                        Settings = [PSCustomObject]@{
                            MinPasswordLength = 8
                            MaxPasswordAge    = 90
                        }
                    })
                    UserScope     = @()
                })
            }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Gpo' -CategoryName 'Group Policy' -TargetName 'DC1'
            $Result | Should -Match '## GPO: Password Policy'
            $Result | Should -Match 'MinPasswordLength'
            $Result | Should -Match '8'
            $Result | Should -Match 'MaxPasswordAge'
        }

        It 'Shows no GPOs message when Gpos is empty' {
            $Data = @{ Gpos = @() }
            $Result = Format-CollectorDataMarkdown -CollectorResult @{
                Available = $true; Data = $Data; Errors = @()
            } -CollectorName 'Gpo' -CategoryName 'Group Policy' -TargetName 'DC1'
            $Result | Should -Match '_No GPOs found._'
        }
    }
}
