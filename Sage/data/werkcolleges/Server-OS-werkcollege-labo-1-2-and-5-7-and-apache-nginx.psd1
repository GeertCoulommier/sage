# data/werkcolleges/Server-OS-werkcollege-labo-1-2-and-5-7-and-apache-nginx.psd1
# Werkcollege exam for Lab 1 (Windows Server setup), Lab 2 (DNS),
# Lab 5 (Group Policy), Lab 6 (DHCP), Lab 7 (AD Sites & Services), and Lab 8 (Apache & Nginx).
#
# Evaluates Lab 1, Lab 2, Lab 5, Lab 6, Lab 7, and Lab 8 assignments:
#   Lab 1 — General configuration: hostname, static IP, gateway, DNS, RDP, ping
#   Lab 2 — DNS: forward/reverse zones, dynamic updates, NS/MX/CNAME/A/PTR/SOA records,
#            subdomain, delegated domain, forwarders, DNS client settings
#   Lab 5 — OU structure, 6 GPOs (Sign-out, Background, Lockdown, drive mappings, 7-zip)
#   Lab 6 — DHCP role, scope Kaai, exclusions, options, reservation, filters
#   Lab 7 — AD sites (Kaai, Bloemenhof, Jette, Ritcs), subnets, site links with costs and schedules
#   Lab 8 — Apache tutorial (Virtual Hosts, sites-available/enabled), exercises 1 & 2, LAMP stack
#         — Nginx tutorial, PHP-FPM, exercises 1, 2 & 3 (server blocks)
#
# Targets:  DC1    (port 30022, user administrator, Windows Server 2025)
#           DC2    (port 40022, user administrator, Windows Server 2025)
#           Client (port 50022, user student,        Windows 11)
#           Linux  (port 20022, user student,        Rocky Linux)
#
# To run:
#   $p = @{
#       ExamPath          = './data/werkcolleges/Server-OS-werkcollege-labo-1-2-and-5-7-and-apache-nginx.psd1'
#       HostName          = 'srvos-2526s2-geertcoulommier.westeurope.cloudapp.azure.com'
#       OutputDir         = './output'
#       KeyFilePath       = "$env:USERPROFILE\.ssh\id_rsa"
#       SaveCollectorData = $true
#   }
#   Invoke-Evaluation @p

@{
    # ── Metadata ──────────────────────────────────────────────────────────────────
    Name         = 'Werkcolleges Lab 1, 2, 5, 6, 7 & 8 — Windows Server Setup, DNS, Group Policy, DHCP, AD Sites & Services, Apache en Nginx Webservers'
    Version      = '6.0.0'
    Description  = 'Evaluates Lab 1 general configuration (hostname, static IP, gateway, DNS, RDP, ping) for DC1, DC2 and Client; Lab 2 DNS (forward/reverse zones, dynamic updates, records, subdomain, delegated domain, forwarders, DNS client settings); Lab 5 Group Policy (OU structure, 6 GPOs); Lab 6 DHCP (scope Kaai, exclusions, options, reservation, filters); Lab 7 AD Sites & Services (sites, subnets, site links with costs and schedules); Lab 8 Apache Webservers (tutorial, exercises 1 & 2, LAMP stack), and Lab 8 Nginx (tutorial, PHP-FPM, exercises 1, 2 & 3 with server blocks).'
    Author       = 'SAGE'

    # ── Exam time window ──────────────────────────────────────────────────────────
    ExamStart    = '2026-01-01T08:00:00'
    ExamEnd      = '2026-12-31T23:59:00'

    # ── Named Targets ─────────────────────────────────────────────────────────────
    Targets      = @{
        DC1    = @{
            Port     = 30022
            UserName = 'administrator'
            Platform = 'Windows'
        }
        DC2    = @{
            Port     = 40022
            UserName = 'administrator'
            Platform = 'Windows'
        }
        Client = @{
            Port     = 50022
            UserName = 'student'
            Platform = 'Windows'
        }
        Linux  = @{
            Port     = 20022
            UserName = 'student'
            Platform = 'Linux'
        }
    }

    # ── Student roster CSV mapping ────────────────────────────────────────────────
    Roster       = @{
        IPField    = 'ip'
        EmailField = 'email'
        NameField  = 'student'
        Delimiter  = ';'
    }

    # ── Export settings ───────────────────────────────────────────────────────────
    Export       = @{
        PrimaryFormat    = 'Json'
        SecondaryFormats = @('Excel', 'Csv')
    }

    # ── Remote dependencies ───────────────────────────────────────────────────────
    Dependencies = @{
        Modules = @('Pester')
    }

    # ── Evaluation categories ─────────────────────────────────────────────────────
    Categories   = @(

        # ══════════════════════════════════════════════════════════════════════════
        # General Configuration — Lab 1 (Windows Server setup)
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 1: Rename VMs, configure static IP addresses, enable RDP, and allow
        # ping for all three Windows machines (DC1, DC2, and Client).
        # Allowed DNS: any 2 from the public resolver set used in the lab.
        @{
            Name       = 'General Configuration — DC1'
            Target     = 'DC1'
            Evaluation = 'GeneralConfig'
            Collector  = 'GeneralConfig'
            Variables  = @{
                HostnameTests   = @(
                    @{ ExpectedHostname = 'dc1'; PassGrade = 1 }
                )
                StaticIPTests   = @(
                    @{
                        ExpectedIP      = '192.168.1.3'
                        ExpectedPrefix  = 24
                        ExpectedGateway = '192.168.1.1'
                        PassGrade       = 1
                    }
                )
                AllowedDnsTests = @(
                    @{
                        AllowedDns       = @('8.8.8.8', '8.8.4.4', '1.1.1.1', '1.0.0.1', '9.9.9.9', '149.112.112.112')
                        RequiredDnsCount = 2
                        PassGrade        = 1
                    }
                )
                PingTests       = @(
                    @{ PassGrade = 1 }
                )
                RdpTests        = @(
                    @{ PassGrade = 1 }
                )
            }
        }

        @{
            Name       = 'General Configuration — DC2'
            Target     = 'DC2'
            Evaluation = 'GeneralConfig'
            Collector  = 'GeneralConfig'
            Variables  = @{
                HostnameTests   = @(
                    @{ ExpectedHostname = 'dc2'; PassGrade = 1 }
                )
                StaticIPTests   = @(
                    @{
                        ExpectedIP      = '192.168.1.4'
                        ExpectedPrefix  = 24
                        ExpectedGateway = '192.168.1.1'
                        PassGrade       = 1
                    }
                )
                AllowedDnsTests = @(
                    @{
                        AllowedDns       = @('8.8.8.8', '8.8.4.4', '1.1.1.1', '1.0.0.1', '9.9.9.9', '149.112.112.112')
                        RequiredDnsCount = 2
                        PassGrade        = 1
                    }
                )
                PingTests       = @(
                    @{ PassGrade = 1 }
                )
                RdpTests        = @(
                    @{ PassGrade = 1 }
                )
            }
        }

        @{
            Name       = 'General Configuration — Client'
            Target     = 'Client'
            Evaluation = 'GeneralConfig'
            Collector  = 'GeneralConfig'
            Variables  = @{
                HostnameTests   = @(
                    @{ ExpectedHostname = 'client'; PassGrade = 1 }
                )
                StaticIPTests   = @(
                    @{
                        ExpectedIP      = '192.168.1.5'
                        ExpectedPrefix  = 24
                        ExpectedGateway = '192.168.1.1'
                        PassGrade       = 1
                    }
                )
                AllowedDnsTests = @(
                    @{
                        AllowedDns       = @('8.8.8.8', '8.8.4.4', '1.1.1.1', '1.0.0.1', '9.9.9.9', '149.112.112.112')
                        RequiredDnsCount = 2
                        PassGrade        = 1
                    }
                )
                PingTests       = @(
                    @{ PassGrade = 1 }
                )
                RdpTests        = @(
                    @{ PassGrade = 1 }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # DNS — Lab 2
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 2: Install DNS role on DC1 and DC2, create forward/reverse zones,
        # configure dynamic updates, zone transfers, NS/A/MX/CNAME/PTR/SOA records,
        # subdomain 'sub', delegated domain 'deleg', forwarders, and DNS client
        # settings on all machines.

        @{
            Name       = 'DNS — DC1'
            Target     = 'DC1'
            Evaluation = 'Dns'
            Collector  = 'Dns'
            Variables  = @{

                # ── Forward zone (primary, dynamic updates, zone transfer to NS) ──
                ForwardZones = @(
                    @{
                        ZoneName          = '<domainname>.be'
                        ZoneType          = 'Primary'
                        DynamicUpdate     = 'NonsecureAndSecure'
                        SecureSecondaries = 'TransferToZoneNameServer'
                        PassGrade         = 2
                    }
                )

                # ── Reverse zone (primary, dynamic updates, zone transfer to NS) ──
                ReverseZones = @(
                    @{
                        ZoneName          = '1.168.192.in-addr.arpa'
                        ZoneType          = 'Primary'
                        DynamicUpdate     = 'NonsecureAndSecure'
                        SecureSecondaries = 'TransferToZoneNameServer'
                        PassGrade         = 2
                    }
                )

                # ── A records (dc1, dc2, client, linux) ───────────────────────────
                ARecords     = @(
                    @{ Name = 'dc1';    IP = '192.168.1.3'; Zone = '<domainname>.be'; PassGrade = 1 }
                    @{ Name = 'dc2';    IP = '192.168.1.4'; Zone = '<domainname>.be'; PassGrade = 1 }
                    @{ Name = 'client'; IP = '192.168.1.5'; Zone = '<domainname>.be'; PassGrade = 1 }
                    @{ Name = 'linux';  IP = '192.168.1.2'; Zone = '<domainname>.be'; PassGrade = 1 }
                )

                # ── NS records (dc1 auto-created; dc2 added in nameservers tab) ───
                NsRecords    = @(
                    @{ Zone = '<domainname>.be'; Expected = 'dc1'; PassGrade = 1 }
                    @{ Zone = '<domainname>.be'; Expected = 'dc2'; PassGrade = 2 }
                    @{ Zone = '1.168.192.in-addr.arpa'; Expected = 'dc1'; PassGrade = 1 }
                    @{ Zone = '1.168.192.in-addr.arpa'; Expected = 'dc2'; PassGrade = 2 }
                )

                # ── SOA record (auto-created; primary server = dc1) ───────────────
                SoaTests     = @(
                    @{ Zone = '<domainname>.be'; PrimaryServer = 'dc1'; PassGrade = 1 }
                )

                # ── MX record pointing to dc1 ────────────────────────────────────
                MxRecords    = @(
                    @{ Zone = '<domainname>.be'; Target = 'dc1.<domainname>.be'; PassGrade = 2 }
                )

                # ── CNAME 'server' pointing to dc1 A-record ──────────────────────
                CnameRecords = @(
                    @{ Name = 'server'; Target = 'dc1.<domainname>.be'; Zone = '<domainname>.be'; PassGrade = 2 }
                )

                # ── PTR records (dc1, dc2, client, linux) ────────────────────────
                PtrRecords   = @(
                    @{ Name = '3'; ExpectedPtr = 'dc1';    Zone = '1.168.192.in-addr.arpa'; PassGrade = 1 }
                    @{ Name = '4'; ExpectedPtr = 'dc2';    Zone = '1.168.192.in-addr.arpa'; PassGrade = 1 }
                    @{ Name = '5'; ExpectedPtr = 'client'; Zone = '1.168.192.in-addr.arpa'; PassGrade = 1 }
                    @{ Name = '2'; ExpectedPtr = 'linux';  Zone = '1.168.192.in-addr.arpa'; PassGrade = 1 }
                )

                # ── Subdomain 'sub' (records added under sub domain) ─────────────
                SubdomainTests = @(
                    @{ SubdomainName = 'sub'; ZoneName = '<domainname>.be'; PassGrade = 1 }
                )

                # ── Delegated domain 'deleg' pointing to dc2 ────────────────────
                DelegationTests = @(
                    @{ DelegatedName = 'deleg'; ZoneName = '<domainname>.be'; DelegatedTo = 'dc2'; PassGrade = 2 }
                )

                # ── Forwarders: any 2 from the public resolver set ───────────────
                Forwarders      = @()
                ForwarderSetTests = @(
                    @{
                        AllowedForwarders = @('8.8.8.8', '8.8.4.4', '1.1.1.1', '1.0.0.1', '9.9.9.9', '149.112.112.112')
                        RequiredCount     = 2
                        PassGrade         = 2
                    }
                )
            }
        }

        @{
            Name       = 'DNS — DC2'
            Target     = 'DC2'
            Evaluation = 'Dns'
            Collector  = 'Dns'
            Variables  = @{

                # ── Secondary forward zone (transferred from dc1) ─────────────────
                ForwardZones = @(
                    @{ ZoneName = '<domainname>.be'; ZoneType = 'Secondary'; PassGrade = 2 }
                )

                # ── Secondary reverse zone (transferred from dc1) ─────────────────
                ReverseZones = @(
                    @{ ZoneName = '1.168.192.in-addr.arpa'; ZoneType = 'Secondary'; PassGrade = 2 }
                )

                # ── Records are replicated — verify key A records exist ───────────
                ARecords     = @(
                    @{ Name = 'dc1'; IP = '192.168.1.3'; Zone = '<domainname>.be'; PassGrade = 1 }
                    @{ Name = 'dc2'; IP = '192.168.1.4'; Zone = '<domainname>.be'; PassGrade = 1 }
                )

                CnameRecords    = @()
                MxRecords       = @()
                NsRecords       = @()
                PtrRecords      = @()
                SoaTests        = @()
                SubdomainTests  = @()
                DelegationTests = @()

                # ── Forwarder: dc1 as forwarder on dc2 ──────────────────────────
                Forwarders        = @(
                    @{ IPAddress = '192.168.1.3'; PassGrade = 2 }
                )
                ForwarderSetTests = @()
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # DNS Client Settings — Lab 2
        # ══════════════════════════════════════════════════════════════════════════
        # After Lab 2, all machines point to the internal DNS servers dc1 and dc2.
        # Uses AllowedDnsTests: two entries per machine —
        #   1. The machine's own address (or loopback) must appear
        #   2. The partner DC's address must appear

        @{
            Name       = 'DNS Client Settings — DC1'
            Target     = 'DC1'
            Evaluation = 'GeneralConfig'
            Collector  = 'GeneralConfig'
            Variables  = @{
                HostnameTests   = @()
                StaticIPTests   = @()
                PingTests       = @()
                RdpTests        = @()
                AllowedDnsTests = @(
                    # dc1 points to itself (by IP or loopback) as preferred DNS
                    @{
                        AllowedDns       = @('192.168.1.3', '127.0.0.1')
                        RequiredDnsCount = 1
                        PassGrade        = 1
                    }
                    # dc1 must also have dc2 as secondary DNS
                    @{
                        AllowedDns       = @('192.168.1.4')
                        RequiredDnsCount = 1
                        PassGrade        = 1
                    }
                )
            }
        }

        @{
            Name       = 'DNS Client Settings — DC2'
            Target     = 'DC2'
            Evaluation = 'GeneralConfig'
            Collector  = 'GeneralConfig'
            Variables  = @{
                HostnameTests   = @()
                StaticIPTests   = @()
                PingTests       = @()
                RdpTests        = @()
                AllowedDnsTests = @(
                    # dc2 points to itself (by IP or loopback) as preferred DNS
                    @{
                        AllowedDns       = @('192.168.1.4', '127.0.0.1')
                        RequiredDnsCount = 1
                        PassGrade        = 1
                    }
                    # dc2 must also have dc1 as secondary DNS
                    @{
                        AllowedDns       = @('192.168.1.3')
                        RequiredDnsCount = 1
                        PassGrade        = 1
                    }
                )
            }
        }

        @{
            Name       = 'DNS Client Settings — Client'
            Target     = 'Client'
            Evaluation = 'GeneralConfig'
            Collector  = 'GeneralConfig'
            Variables  = @{
                HostnameTests   = @()
                StaticIPTests   = @()
                PingTests       = @()
                RdpTests        = @()
                AllowedDnsTests = @(
                    # client must have dc1 in its DNS list
                    @{
                        AllowedDns       = @('192.168.1.3')
                        RequiredDnsCount = 1
                        PassGrade        = 1
                    }
                    # client must have dc2 in its DNS list
                    @{
                        AllowedDns       = @('192.168.1.4')
                        RequiredDnsCount = 1
                        PassGrade        = 1
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Active Directory — OU Structure
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 5 step 1: Create building/room OUs under domain root.
        # Department OUs (from Lab 4) are verified here too because GPO links depend
        # on them existing (Marketing for Sign-out, IT for Y-Drive Mapping, etc.).
        @{
            Name       = 'Active Directory — OU Structure'
            Target     = 'DC1'
            Evaluation = 'Ad'
            Collector  = 'Ad'
            Variables  = @{
                DomainTests          = @()
                ComputerTests        = @()
                UserTests            = @()
                GroupMembershipTests = @()
                OUTests              = @(
                    # Lab 5: Building OUs
                    @{ Name = 'Gebouw A'; PassGrade = 1 }
                    @{ Name = 'Lokaal A01'; PassGrade = 1 }
                    @{ Name = 'Lokaal A02'; PassGrade = 1 }
                    @{ Name = 'Gebouw B'; PassGrade = 1 }
                    @{ Name = 'Lokaal B01'; PassGrade = 1 }
                    @{ Name = 'Lokaal B02'; PassGrade = 1 }
                    @{ Name = 'Gebouw C'; PassGrade = 1 }
                    @{ Name = 'Lokaal C01'; PassGrade = 1 }
                    @{ Name = 'Lokaal C02'; PassGrade = 1 }
                    # Lab 4 department OUs — required for GPO link targets
                    @{ Name = 'Ontwikkeling'; PassGrade = 1 }
                    @{ Name = 'IT'; PassGrade = 1 }
                    @{ Name = 'Boekhouding'; PassGrade = 1 }
                    @{ Name = 'Inkomsten'; PassGrade = 1 }
                    @{ Name = 'Uitgaven'; PassGrade = 1 }
                    @{ Name = 'Marketing'; PassGrade = 1 }
                    @{ Name = 'HR'; PassGrade = 1 }
                    @{ Name = 'Aanwerving'; PassGrade = 1 }
                    @{ Name = 'Personeelsdienst'; PassGrade = 1 }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # File Server — Shared Folders for Drive Map GPOs
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 4 + Lab 5: single SMB share (Shared) with subfolders.
        # - \dc1\shared\algemene_informatie
        # - \dc1\shared\algemene_informatie_IT
        # - \dc1\shared\public (for wallpaper/software distribution)
        @{
            Name       = 'File Server — GPO Shares'
            Target     = 'DC1'
            Evaluation = 'FileServer'
            Collector  = 'FileServer'
            Variables  = @{
                ShareTests       = @(
                    @{ ShareName = 'Shared'; ExpectedPath = 'C:\Shared'; PassGrade = 2 }
                )
                FolderTests      = @(
                    @{ ShareName = 'Shared'; RelativePath = 'algemene_informatie'; PassGrade = 2 }
                    @{ ShareName = 'Shared'; RelativePath = 'algemene_informatie_IT'; PassGrade = 2 }
                    @{ ShareName = 'Shared'; RelativePath = 'public'; PassGrade = 2 }
                    @{ ShareName = 'Shared'; RelativePath = 'public\software'; PassGrade = 2 }
                )
                NtfsTests        = @(
                    @{ ShareName = 'Shared'; RelativePath = 'public'; ExpectedIdentity = 'public-R'; ExpectedRights = 'ReadAndExecute'; PassGrade = 2 }
                    @{ ShareName = 'Shared'; RelativePath = 'algemene_informatie'; ExpectedIdentity = 'algemene_informatie-R'; ExpectedRights = 'ReadAndExecute'; PassGrade = 2 }
                    @{ ShareName = 'Shared'; RelativePath = 'algemene_informatie_IT'; ExpectedIdentity = 'algemene_informatie_IT-W'; ExpectedRights = 'Modify'; PassGrade = 2 }
                )
                FileTests        = @(
                    @{ ShareName = 'Shared'; RelativePath = 'public'; ExpectedExtensions = @('.bmp', '.jpg', '.jpeg', '.png'); PassGrade = 2 }
                    @{ ShareName = 'Shared'; RelativePath = 'public\software'; ExpectedPattern = '(?i)7(-| )?zip|7z'; ExpectedExtensions = @('.msi'); PassGrade = 2 }
                )
                ShareAccessTests = @(
                    @{ ShareName = 'Shared'; ExpectedAccount = 'Everyone'; ExpectedAccess = 'Allow:Full'; PassGrade = 2 }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Group Policy — All 6 Lab 5 GPOs
        # ══════════════════════════════════════════════════════════════════════════
        @{
            Name       = 'Group Policy'
            Target     = 'DC1'
            Evaluation = 'Gpo'
            Collector  = 'Gpo'
            Variables  = @{

                # ── Existence: all 6 GPOs must exist by exact name ─────────────────
                GpoExistenceTests = @(
                    # Lab 5 ex.1: Remove Sign Out from CTRL+ALT+DEL for Marketing
                    @{ GpoName = 'Sign-out'; PassGrade = 1 }
                    # Lab 5 ex.2: Same desktop wallpaper for all domain users
                    @{ GpoName = 'Background'; PassGrade = 1 }
                    # Lab 5 ex.3: Disable Task Manager + Command Prompt (except IT + Ontwikkeling)
                    @{ GpoName = 'Lockdown'; PassGrade = 1 }
                    # Lab 5 ex.4: Map X: -> \\dc1\algemene_informatie for all users
                    @{ GpoName = 'X-Drive mapping'; PassGrade = 1 }
                    # Lab 5 ex.5: Map Y: -> \\dc1\algemene_informatie_IT for IT only
                    @{ GpoName = 'Y-Drive Mapping'; PassGrade = 1 }
                    # Lab 5 ex.6: Deploy 7-Zip MSI to Lokaal A01 computers
                    @{ GpoName = '7-zip install'; PassGrade = 1 }
                )

                # ── Links: each GPO must be linked to the correct OU and enabled ──
                # DomainRootLink = $true means the GPO must be linked to the domain
                # root (the student's own domain, e.g. jan.local). This cannot be
                # expressed as a fixed string because every student has a different
                # domain name.
                GpoLinkTests      = @(
                    # Sign-out applies only to Marketing users → link to Marketing OU
                    @{
                        GpoName      = 'Sign-out'
                        ExpectedLink = 'Marketing'
                        PassGrade    = 2
                    }
                    # Background applies to all departmental OUs, excluding IT.
                    @{
                        GpoName                 = 'Background'
                        ExpectedLinksAny        = @('Marketing', 'Boekhouding', 'HR', 'Ontwikkeling')
                        ForbiddenLinks          = @('IT')
                        ForbiddenDomainRootLink = $true
                        PassGrade               = 2
                    }
                    # Lockdown applies to all departmental OUs, excluding IT + Ontwikkeling.
                    @{
                        GpoName                 = 'Lockdown'
                        ExpectedLinksAny        = @('Marketing', 'Boekhouding', 'HR')
                        ForbiddenLinks          = @('IT', 'Ontwikkeling')
                        ForbiddenDomainRootLink = $true
                        PassGrade               = 2
                    }
                    # X-Drive mapping for all users → link to domain root
                    @{
                        GpoName        = 'X-Drive mapping'
                        ExpectedLink   = 'domain root'
                        DomainRootLink = $true
                        PassGrade      = 2
                    }
                    # Y-Drive Mapping for IT only → link to IT OU
                    @{
                        GpoName      = 'Y-Drive Mapping'
                        ExpectedLink = 'IT'
                        PassGrade    = 2
                    }
                    # 7-zip installs on Lokaal A01 computers → link to Lokaal A01
                    @{
                        GpoName      = '7-zip install'
                        ExpectedLink = 'Lokaal A01'
                        PassGrade    = 2
                    }
                )

                # ── Administrative Template Policies ──────────────────────────────
                GpoPolicyTests    = @(
                    # Sign-out ex.1: Remove the "Sign out" option from CTRL+ALT+DEL
                    # This is a User Configuration > Admin Templates setting.
                    @{
                        GpoName       = 'Sign-out'
                        PolicyName    = 'Remove Logoff'
                        ScopeType     = 'User'
                        ExpectedState = 'Enabled'
                        PassGrade     = 5
                    }
                    # Background ex.2: Enforce desktop wallpaper path
                    # This is a User Configuration > Admin Templates > Desktop setting.
                    @{
                        GpoName           = 'Background'
                        PolicyName        = 'Desktop Wallpaper'
                        ScopeType         = 'User'
                        ExpectedState     = 'Enabled'
                        ExpectedPath      = @('\\dc1\shared\public\')
                        ExpectedPathRegex = '(?i)\\\\dc1\\shared\\public\\.+\.(bmp|jpg|jpeg|png)'
                        RequirePathExists = $true
                        PassGrade         = 5
                    }
                    # Background ex.2: Enable Active Desktop for users.
                    @{
                        GpoName       = 'Background'
                        PolicyName    = 'Enable Active Desktop'
                        ScopeType     = 'User'
                        ExpectedState = 'Enabled'
                        Optional      = $true
                        PassGrade     = 5
                    }
                    # Lockdown ex.3: Disable Task Manager
                    # This is a User Configuration > Admin Templates > System setting.
                    @{
                        GpoName       = 'Lockdown'
                        PolicyName    = 'Remove Task Manager'
                        ScopeType     = 'User'
                        ExpectedState = 'Enabled'
                        PassGrade     = 5
                    }
                    # Lockdown ex.3: Disable Command Prompt
                    # This is a User Configuration > Admin Templates > System setting.
                    @{
                        GpoName       = 'Lockdown'
                        PolicyName    = 'Prevent access to the command prompt'
                        ScopeType     = 'User'
                        ExpectedState = 'Enabled'
                        PassGrade     = 5
                    }
                )

                # ── Drive Mappings ────────────────────────────────────────────────
                GpoDriveMapTests  = @(
                    # X-Drive mapping ex.4: X: -> \\dc1\algemene_informatie
                    @{
                        GpoName           = 'X-Drive mapping'
                        DriveLetter       = 'X:'
                        DrivePath         = '\\dc1\Shared\algemene_informatie'
                        RequirePathExists = $true
                        PassGrade         = 5
                    }
                    # Y-Drive Mapping ex.5: Y: -> \\dc1\algemene_informatie_IT
                    @{
                        GpoName           = 'Y-Drive Mapping'
                        DriveLetter       = 'Y:'
                        DrivePath         = '\\dc1\Shared\algemene_informatie_IT'
                        RequirePathExists = $true
                        PassGrade         = 5
                    }
                )

                # ── Software Installation ─────────────────────────────────────────
                GpoSoftwareTests  = @(
                    # 7-zip install ex.6: 7-Zip deployed via MSI to Computer scope.
                    # AppName uses partial matching: the full MSI name includes version,
                    # e.g. "7-Zip 24.08 (x64 edition)" — matching on "7-Zip" is sufficient.
                    @{
                        GpoName                = '7-zip install'
                        AppNamePatterns        = @('7-Zip', '7zip', '7z')
                        ScopeType              = 'Computer'
                        ExpectedPath           = @('\\dc1\shared\public\software\', '.msi')
                        ExpectedPathRegex      = '(?i)\\\\dc1\\shared\\public\\software\\.*(7-?zip|7z).+\.msi$'
                        ExpectedFileExtension  = '.msi'
                        RequirePathExists      = $true
                        ExpectedDeploymentType = 'Assigned'
                        PassGrade              = 5
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # DHCP — Lab 6
        # ══════════════════════════════════════════════════════════════════════════
        @{
            Name       = 'DHCP'
            Target     = 'DC1'
            Evaluation = 'Dhcp'
            Collector  = 'Dhcp'
            Variables  = @{
                # DHCP role must be installed
                RoleTests        = @(
                    @{ PassGrade = 1 }
                )

                # Server must be authorized in Active Directory
                ServerTests      = @(
                    @{ ExpectedAuthorized = $true; PassGrade = 1 }
                )

                # Scope Kaai with correct range/mask, active state, and 4-day lease
                ScopeTests       = @(
                    @{
                        ScopeId           = '192.168.1.0'
                        Name              = 'Kaai'
                        StartRange        = '192.168.1.1'
                        EndRange          = '192.168.1.100'
                        SubnetMask        = '255.255.255.0'
                        State             = 'Active'
                        LeaseDurationDays = 4
                        PassGrade         = 4
                    }
                )

                # Required exclusions
                ExclusionTests   = @(
                    @{ ScopeId = '192.168.1.0'; StartRange = '192.168.1.81'; EndRange = '192.168.1.100'; PassGrade = 1 }
                    @{ ScopeId = '192.168.1.0'; StartRange = '192.168.1.1'; EndRange = '192.168.1.10'; PassGrade = 1 }
                )

                # Required scope options
                OptionTests      = @(
                    @{ ScopeId = '192.168.1.0'; OptionName = 'Router'; ExpectedValue = '192.168.1.1'; PassGrade = 1 }
                    @{ ScopeId = '192.168.1.0'; OptionName = 'DNS Domain Name'; ExpectedValueFrom = 'DomainName'; PassGrade = 1 }
                    @{ ScopeId = '192.168.1.0'; OptionName = 'DNS Servers'; ExpectedValue = '192.168.1.3'; PassGrade = 1 }
                    @{ ScopeId = '192.168.1.0'; OptionName = 'DNS Servers'; ExpectedValue = '192.168.1.4'; PassGrade = 1 }
                )

                # Reservation client = 192.168.1.5
                ReservationTests = @(
                    @{ ScopeId = '192.168.1.0'; IPAddress = '192.168.1.5'; Name = 'client'; PassGrade = 3 }
                )

                # Allow and deny filters must not be enabled
                FilterTests      = @(
                    @{ FilterType = 'Allow'; ExpectedEnabled = $false; PassGrade = 1 }
                    @{ FilterType = 'Deny'; ExpectedEnabled = $false; PassGrade = 1 }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Active Directory — Sites & Services (Lab 7)
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 7: Rename Default-First-Site-Name → Kaai, add Bloemenhof/Jette/Ritcs,
        # assign subnets, create site links with costs and schedules.
        @{
            Name       = 'Active Directory — Sites & Services'
            Target     = 'DC1'
            Evaluation = 'Ad'
            Collector  = 'Ad'
            Variables  = @{
                DomainTests               = @()
                ComputerTests             = @()
                UserTests                 = @()
                GroupMembershipTests      = @()
                OUTests                   = @()

                # ── Sites: all 4 sites must exist ─────────────────────────────────
                SiteTests                 = @(
                    @{ Name = 'Kaai'; PassGrade = 1 }
                    @{ Name = 'Bloemenhof'; PassGrade = 1 }
                    @{ Name = 'Jette'; PassGrade = 1 }
                    @{ Name = 'Ritcs'; PassGrade = 1 }
                )

                # ── Subnets: each subnet must be assigned to the correct site ─────
                SubnetTests               = @(
                    @{ Subnet = '192.168.1.0/24'; SiteName = 'Kaai'; PassGrade = 1 }
                    @{ Subnet = '192.168.2.0/24'; SiteName = 'Kaai'; PassGrade = 1 }
                    @{ Subnet = '192.168.3.0/24'; SiteName = 'Bloemenhof'; PassGrade = 1 }
                    @{ Subnet = '192.168.4.0/24'; SiteName = 'Bloemenhof'; PassGrade = 1 }
                    @{ Subnet = '192.168.5.0/24'; SiteName = 'Jette'; PassGrade = 1 }
                    @{ Subnet = '192.168.6.0/24'; SiteName = 'Jette'; PassGrade = 1 }
                    @{ Subnet = '192.168.7.0/24'; SiteName = 'Ritcs'; PassGrade = 1 }
                    @{ Subnet = '192.168.8.0/24'; SiteName = 'Ritcs'; PassGrade = 1 }
                )

                # ── Site links: existence and sites included ──────────────────────
                SiteLinkExistenceTests    = @(
                    @{ Name = 'Kaai-Jette'; Sites = @('Kaai', 'Jette'); PassGrade = 1 }
                    @{ Name = 'Kaai-Ritcs'; Sites = @('Kaai', 'Ritcs'); PassGrade = 1 }
                    @{ Name = 'Kaai-Bloemenhof'; Sites = @('Kaai', 'Bloemenhof'); PassGrade = 1 }
                    @{ Name = 'Jette-Bloemenhof'; Sites = @('Jette', 'Bloemenhof'); PassGrade = 1 }
                )

                # ── Site links: cost ──────────────────────────────────────────────
                SiteLinkCostTests         = @(
                    @{ Name = 'Kaai-Jette'; ExpectedCost = 10; PassGrade = 1 }
                    @{ Name = 'Kaai-Ritcs'; ExpectedCost = 20; PassGrade = 1 }
                    @{ Name = 'Kaai-Bloemenhof'; ExpectedCost = 100; PassGrade = 1 }
                    @{ Name = 'Jette-Bloemenhof'; ExpectedCost = 100; PassGrade = 1 }
                )

                # ── Site links: replication interval ─────────────────────────────
                # Only Kaai-Jette (60 min) and Jette-Bloemenhof (120 min) are specified.
                SiteLinkReplIntervalTests = @(
                    @{ Name = 'Kaai-Jette'; ExpectedInterval = 60; PassGrade = 1 }
                    @{ Name = 'Jette-Bloemenhof'; ExpectedInterval = 120; PassGrade = 1 }
                )

                # ── Domain Controller site membership ────────────────────────────────────
                # DC1 belongs to Kaai, DC2 belongs to Bloemenhof.
                DcSiteTests               = @(
                    @{ Name = 'DC1'; ExpectedSite = 'Kaai'; PassGrade = 1 }
                    @{ Name = 'DC2'; ExpectedSite = 'Bloemenhof'; PassGrade = 1 }
                )

                # ── Site links: schedule ──────────────────────────────────────────
                # ScheduleExcludeWeekends: weekends (Sat/Sun) must have no sync windows.
                # ScheduleExcludeHours: listed hours (0-based, 0=midnight) must have no
                # sync windows on any day.
                # The schedule matrix (ScheduleMatrix) in collected data is a flat
                # 168-integer array: index = DayIndex*24 + HourIndex,
                # DayIndex: 0=Sunday,1=Monday,...,6=Saturday.  Non-zero = available.
                SiteLinkScheduleTests     = @(
                    @{
                        Name                    = 'Kaai-Jette'
                        ScheduleExcludeWeekends = $true
                        ScheduleExcludeHours    = @()
                        PassGrade               = 2
                    }
                    @{
                        Name                    = 'Jette-Bloemenhof'
                        ScheduleExcludeWeekends = $false
                        ScheduleExcludeHours    = @(22, 23, 0, 1, 2, 3, 4, 5)
                        PassGrade               = 2
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Apache — Tutorial
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 8 tutorial: install httpd, enable + start service, configure firewall,
        # create Virtual Host for website1.local using sites-available/sites-enabled.
        @{
            Name       = 'Apache — Tutorial'
            Target     = 'Linux'
            Evaluation = 'Apache'
            Collector  = 'Apache'
            Variables  = @{
                # ── Sudo password for firewall-cmd on Rocky Linux ──────────────────
                Password               = 'Student1'

                # ── Service: httpd must be enabled and running ─────────────────────
                ServiceTests           = @(
                    @{ Property = 'enabled'; PassGrade = 1 }
                    @{ Property = 'running'; PassGrade = 1 }
                )

                # ── Firewall: http and https must be allowed ───────────────────────
                FirewallTests          = @(
                    @{ Service = 'http'; PassGrade = 1 }
                    @{ Service = 'https'; PassGrade = 1 }
                )

                # ── Directory structure for website1.local ─────────────────────────
                DirectoryTests         = @(
                    @{ Path = '/var/www/website1.local/html'; PassGrade = 1 }
                    @{ Path = '/var/www/website1.local/log'; PassGrade = 1 }
                    @{ Path = '/etc/httpd/sites-available'; PassGrade = 1 }
                    @{ Path = '/etc/httpd/sites-enabled'; PassGrade = 1 }
                )

                # ── httpd.conf include directive ──────────────────────────────────
                HttpdConfIncludeTests  = @(
                    @{ IncludeLine = 'IncludeOptional sites-enabled/*.conf'; PassGrade = 1 }
                )

                # ── website1.local.conf content (in sites-available) ──────────────
                VirtualHostConfigTests = @(
                    @{ ConfFile = 'website1.local.conf'; ContainsLine = '<VirtualHost *:80>'; PassGrade = 1 }
                    @{ ConfFile = 'website1.local.conf'; ContainsLine = 'ServerName website1.local'; PassGrade = 1 }
                    @{ ConfFile = 'website1.local.conf'; ContainsLine = 'ServerAlias www.website1.local'; PassGrade = 1 }
                    @{ ConfFile = 'website1.local.conf'; ContainsLine = 'DocumentRoot /var/www/website1.local/html'; PassGrade = 1 }
                )

                # ── Symlink: sites-enabled/website1.local.conf → sites-available ──
                SymlinkTests           = @(
                    @{
                        SymlinkPath    = '/etc/httpd/sites-enabled/website1.local.conf'
                        ExpectedTarget = '/etc/httpd/sites-available/website1.local.conf'
                        PassGrade      = 2
                    }
                )

                # ── Index file content ─────────────────────────────────────────────
                ContentTests           = @(
                    @{ ExpectedContent = 'website1.local'; PassGrade = 1 }
                )

                # ── Live test: curl http://website1.local → expected page content ──
                CurlTests              = @(
                    @{
                        Url             = 'http://website1.local'
                        ResolveHost     = 'website1.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website1.local.'
                        PassGrade       = 3
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Apache — Exercise 1 (conf.d Virtual Hosts)
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 8 exercise 1: create website2.local in /etc/httpd/conf.d;
        # restore IncludeOptional conf.d/*.conf in httpd.conf;
        # website1.local and website2.local must both work.
        @{
            Name       = 'Apache — Exercise 1'
            Target     = 'Linux'
            Evaluation = 'Apache'
            Collector  = 'Apache'
            Variables  = @{
                # ── Sudo password for firewall-cmd on Rocky Linux ──────────────────
                Password               = 'Student1'

                # ── httpd.conf: both include lines must be present ─────────────────
                HttpdConfIncludeTests  = @(
                    @{ IncludeLine = 'IncludeOptional conf.d/*.conf'; PassGrade = 1 }
                    @{ IncludeLine = 'IncludeOptional sites-enabled/*.conf'; PassGrade = 1 }
                )

                # ── Directory structure for website2.local ─────────────────────────
                DirectoryTests         = @(
                    @{ Path = '/var/www/website2.local/html'; PassGrade = 1 }
                    @{ Path = '/var/www/website2.local/log'; PassGrade = 1 }
                )

                # ── website2.local.conf content (in conf.d) ───────────────────────
                VirtualHostConfigTests = @(
                    @{ ConfFile = 'website2.local.conf'; ContainsLine = '<VirtualHost *:80>'; PassGrade = 1 }
                    @{ ConfFile = 'website2.local.conf'; ContainsLine = 'ServerName website2.local'; PassGrade = 1 }
                    @{ ConfFile = 'website2.local.conf'; ContainsLine = 'ServerAlias www.website2.local'; PassGrade = 1 }
                    @{ ConfFile = 'website2.local.conf'; ContainsLine = 'DocumentRoot /var/www/website2.local/html'; PassGrade = 1 }
                )

                # ── Index file content ─────────────────────────────────────────────
                ContentTests           = @(
                    @{ ExpectedContent = 'website2.local'; PassGrade = 1 }
                )

                # ── Live tests: both websites must respond correctly ───────────────
                CurlTests              = @(
                    @{
                        Url             = 'http://website1.local'
                        ResolveHost     = 'website1.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website1.local.'
                        PassGrade       = 2
                    }
                    @{
                        Url             = 'http://website2.local'
                        ResolveHost     = 'website2.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website2.local.'
                        PassGrade       = 3
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Apache — Exercise 2 (Port Redirection)
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 8 exercise 2: create website3.local on port 443 (plain HTTP) in conf.d;
        # all three websites must respond correctly.
        @{
            Name       = 'Apache — Exercise 2'
            Target     = 'Linux'
            Evaluation = 'Apache'
            Collector  = 'Apache'
            Variables  = @{
                # ── Sudo password for firewall-cmd on Rocky Linux ──────────────────
                Password               = 'Student1'

                # ── Directory structure for website3.local ─────────────────────────
                DirectoryTests         = @(
                    @{ Path = '/var/www/website3.local/html'; PassGrade = 1 }
                    @{ Path = '/var/www/website3.local/log'; PassGrade = 1 }
                )

                # ── website3.local.conf content (in conf.d, port 443) ─────────────
                VirtualHostConfigTests = @(
                    @{ ConfFile = 'website3.local.conf'; ContainsLine = '<VirtualHost *:443>'; PassGrade = 1 }
                    @{ ConfFile = 'website3.local.conf'; ContainsLine = 'ServerName website3.local'; PassGrade = 1 }
                    @{ ConfFile = 'website3.local.conf'; ContainsLine = 'ServerAlias www.website3.local'; PassGrade = 1 }
                    @{ ConfFile = 'website3.local.conf'; ContainsLine = 'DocumentRoot /var/www/website3.local/html'; PassGrade = 1 }
                )

                # ── Index file content ─────────────────────────────────────────────
                ContentTests           = @(
                    @{ ExpectedContent = 'website3.local'; PassGrade = 1 }
                )

                # ── Live tests: all three websites must respond correctly ──────────
                CurlTests              = @(
                    @{
                        Url             = 'http://website1.local'
                        ResolveHost     = 'website1.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website1.local.'
                        PassGrade       = 1
                    }
                    @{
                        Url             = 'http://website2.local'
                        ResolveHost     = 'website2.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website2.local.'
                        PassGrade       = 1
                    }
                    @{
                        Url             = 'http://website3.local:443'
                        ResolveHost     = 'website3.local'
                        ResolvePort     = 443
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website3.local.'
                        PassGrade       = 3
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Apache — LAMP (MariaDB + PHP-FPM)
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 8 LAMP section: MariaDB and PHP-FPM must be installed,
        # enabled, and running alongside the Apache httpd service.
        # A php.local virtual host with a php.info file must also be configured.
        @{
            Name       = 'Apache — LAMP'
            Target     = 'Linux'
            Evaluation = 'Apache'
            Collector  = 'Apache'
            Variables  = @{
                # ── Sudo password for firewall-cmd on Rocky Linux ──────────────────
                Password               = 'Student1'

                # ── MariaDB: installed, enabled and running ────────────────────────
                MariaDbTests           = @(
                    @{ Property = 'enabled'; PassGrade = 1 }
                    @{ Property = 'running'; PassGrade = 1 }
                )

                # ── PHP-FPM: installed, enabled and running ────────────────────────
                PhpFpmTests            = @(
                    @{ Property = 'enabled'; PassGrade = 1 }
                    @{ Property = 'running'; PassGrade = 1 }
                )

                # ── php.local directory must exist ────────────────────────────────
                DirectoryTests         = @(
                    @{ Path = '/var/www/php.local/html'; PassGrade = 1 }
                )

                # ── php.local.conf in conf.d: VirtualHost *:80, ServerName php.local
                VirtualHostConfigTests = @(
                    @{ ConfFile = 'php.local.conf'; ContainsLine = '<VirtualHost *:80>'; PassGrade = 1 }
                    @{ ConfFile = 'php.local.conf'; ContainsLine = 'ServerName php.local'; PassGrade = 1 }
                )

                # ── php.info file must exist and contain phpinfo() call ────────────
                PhpFileTests           = @(
                    @{
                        FileName        = 'php.info'
                        Dir             = '/var/www/php.local/html'
                        ExpectedContent = 'phpinfo()'
                        PassGrade       = 2
                    }
                )

                # ── php.local/php.info must return the PHP overview page ───────────
                CurlTests              = @(
                    @{
                        Url             = 'http://php.local/php.info'
                        ResolveHost     = 'php.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'PHP Version'
                        PassGrade       = 3
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Nginx — Tutorial
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 8 section 5.1-5.2: install nginx, enable + start service, configure
        # firewall, verify the default nginx welcome page is reachable.
        @{
            Name       = 'Nginx — Tutorial'
            Target     = 'Linux'
            Evaluation = 'Nginx'
            Collector  = 'Nginx'
            Variables  = @{
                # ── Sudo password for firewall-cmd on Rocky Linux ──────────────────
                Password      = 'Student1'

                # ── Service: nginx must be enabled and running ─────────────────────
                ServiceTests  = @(
                    @{ Property = 'enabled'; PassGrade = 1 }
                    @{ Property = 'running'; PassGrade = 1 }
                )

                # ── Firewall: http and https must be allowed ───────────────────────
                FirewallTests = @(
                    @{ Service = 'http'; PassGrade = 1 }
                    @{ Service = 'https'; PassGrade = 1 }
                )

                # ── Live test: default nginx welcome page must load ────────────────
                CurlTests     = @(
                    @{
                        Url             = 'http://127.0.0.1'
                        ExpectedContent = 'Welcome to nginx'
                        PassGrade       = 2
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Nginx — PHP-FPM
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 8 section 5.2-5.3: install php-fpm, configure nginx to pass PHP to
        # php-fpm via unix socket, create php-nginx.local server block.
        @{
            Name       = 'Nginx — PHP-FPM'
            Target     = 'Linux'
            Evaluation = 'Nginx'
            Collector  = 'Nginx'
            Variables  = @{
                # ── Sudo password for firewall-cmd on Rocky Linux ──────────────────
                Password           = 'Student1'

                # ── PHP-FPM service: installed, enabled and running ────────────────
                PhpFpmTests        = @(
                    @{ Property = 'enabled'; PassGrade = 1 }
                    @{ Property = 'running'; PassGrade = 1 }
                )

                # ── PHP-FPM config lines in /etc/php-fpm.d/www.conf ───────────────
                PhpFpmConfTests    = @(
                    @{ ConfLine = 'listen = /run/php-fpm/www.sock'; PassGrade = 1 }
                    @{ ConfLine = 'user = www-data'; PassGrade = 1 }
                    @{ ConfLine = 'group = www-data'; PassGrade = 1 }
                    @{ ConfLine = 'listen.allowed_clients = 127.0.0.1'; PassGrade = 1 }
                    @{ ConfLine = 'pm = dynamic'; PassGrade = 1 }
                )

                # ── php-nginx.local directory must exist ──────────────────────────
                DirectoryTests     = @(
                    @{ Path = '/var/www/php-nginx.local/html'; PassGrade = 1 }
                )

                # ── info.php must exist and contain phpinfo() ─────────────────────
                PhpFileTests       = @(
                    @{
                        FileName        = 'info.php'
                        Dir             = '/var/www/php-nginx.local/html'
                        ExpectedContent = 'phpinfo()'
                        PassGrade       = 2
                    }
                )

                # ── php-nginx.conf server block in /etc/nginx/conf.d ─────────────
                NginxConfFileTests = @(
                    @{ ConfFile = 'php-nginx.conf'; ContainsLine = 'server {'; PassGrade = 1 }
                    @{ ConfFile = 'php-nginx.conf'; ContainsLine = 'listen 80;'; PassGrade = 1 }
                    @{ ConfFile = 'php-nginx.conf'; ContainsLine = 'server_name php-nginx.local www.php-nginx.local;'; PassGrade = 1 }
                    @{ ConfFile = 'php-nginx.conf'; ContainsLine = 'root /var/www/php-nginx.local/html;'; PassGrade = 1 }
                    @{ ConfFile = 'php-nginx.conf'; ContainsLine = 'fastcgi_pass unix:/run/php-fpm/www.sock;'; PassGrade = 2 }
                )

                # ── Live tests: PHP info page must respond on both dns names ──────
                CurlTests          = @(
                    @{
                        Url             = 'http://php-nginx.local'
                        ResolveHost     = 'php-nginx.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'PHP Version'
                        PassGrade       = 2
                    }
                    @{
                        Url             = 'http://www.php-nginx.local'
                        ResolveHost     = 'www.php-nginx.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'PHP Version'
                        PassGrade       = 1
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Nginx — Exercise 1 (website1.local via sites-available/sites-enabled)
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 8 exercise 5.4: create website1.local server block using the
        # sites-available/sites-enabled pattern with a symbolic link.
        @{
            Name       = 'Nginx — Exercise 1'
            Target     = 'Linux'
            Evaluation = 'Nginx'
            Collector  = 'Nginx'
            Variables  = @{
                # ── Sudo password for firewall-cmd on Rocky Linux ──────────────────
                Password              = 'Student1'

                # ── Directory structure ────────────────────────────────────────────
                DirectoryTests        = @(
                    @{ Path = '/var/www/website1.local/html'; PassGrade = 1 }
                    @{ Path = '/etc/nginx/sites-available'; PassGrade = 1 }
                    @{ Path = '/etc/nginx/sites-enabled'; PassGrade = 1 }
                )

                # ── nginx.conf must include sites-enabled ─────────────────────────
                NginxConfIncludeTests = @(
                    @{ IncludeLine = 'include /etc/nginx/sites-enabled/*.conf;'; PassGrade = 1 }
                )

                # ── website1.local.conf in sites-available ────────────────────────
                NginxConfFileTests    = @(
                    @{ ConfFile = 'website1.local.conf'; ContainsLine = 'server {'; PassGrade = 1 }
                    @{ ConfFile = 'website1.local.conf'; ContainsLine = 'listen 80;'; PassGrade = 1 }
                    @{ ConfFile = 'website1.local.conf'; ContainsLine = 'server_name website1.local www.website1.local;'; PassGrade = 1 }
                    @{ ConfFile = 'website1.local.conf'; ContainsLine = 'root /var/www/website1.local/html;'; PassGrade = 1 }
                )

                # ── Symlink: sites-enabled/website1.local.conf → sites-available ──
                SymlinkTests          = @(
                    @{
                        SymlinkPath    = '/etc/nginx/sites-enabled/website1.local.conf'
                        ExpectedTarget = '/etc/nginx/sites-available/website1.local.conf'
                        PassGrade      = 2
                    }
                )

                # ── Index file must contain the nginx-specific text ────────────────
                ContentTests          = @(
                    @{ ExpectedContent = 'You have reached the indexpage of website1.local on nginx.'; PassGrade = 1 }
                )

                # ── Live test ─────────────────────────────────────────────────────
                CurlTests             = @(
                    @{
                        Url             = 'http://website1.local'
                        ResolveHost     = 'website1.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website1.local on nginx.'
                        PassGrade       = 3
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Nginx — Exercise 2 (website2.local via conf.d)
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 8 exercise 5.4: create website2.local server block in /etc/nginx/conf.d;
        # both website1.local and website2.local must respond.
        @{
            Name       = 'Nginx — Exercise 2'
            Target     = 'Linux'
            Evaluation = 'Nginx'
            Collector  = 'Nginx'
            Variables  = @{
                # ── Sudo password for firewall-cmd on Rocky Linux ──────────────────
                Password              = 'Student1'

                # ── nginx.conf must include conf.d ─────────────────────────────────
                NginxConfIncludeTests = @(
                    @{ IncludeLine = 'include /etc/nginx/conf.d/*.conf;'; PassGrade = 1 }
                )

                # ── Directory structure ────────────────────────────────────────────
                DirectoryTests        = @(
                    @{ Path = '/var/www/website2.local/html'; PassGrade = 1 }
                )

                # ── website2.local.conf in conf.d ─────────────────────────────────
                NginxConfFileTests    = @(
                    @{ ConfFile = 'website2.local.conf'; ContainsLine = 'server {'; PassGrade = 1 }
                    @{ ConfFile = 'website2.local.conf'; ContainsLine = 'listen 80;'; PassGrade = 1 }
                    @{ ConfFile = 'website2.local.conf'; ContainsLine = 'server_name website2.local www.website2.local;'; PassGrade = 1 }
                    @{ ConfFile = 'website2.local.conf'; ContainsLine = 'root /var/www/website2.local/html;'; PassGrade = 1 }
                )

                # ── Index file content ─────────────────────────────────────────────
                ContentTests          = @(
                    @{ ExpectedContent = 'You have reached the indexpage of website2.local on nginx.'; PassGrade = 1 }
                )

                # ── Live tests: both websites must respond ─────────────────────────
                CurlTests             = @(
                    @{
                        Url             = 'http://website1.local'
                        ResolveHost     = 'website1.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website1.local on nginx.'
                        PassGrade       = 2
                    }
                    @{
                        Url             = 'http://website2.local'
                        ResolveHost     = 'website2.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website2.local on nginx.'
                        PassGrade       = 3
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════════
        # Nginx — Exercise 3 (website3.local on port 443 via conf.d)
        # ══════════════════════════════════════════════════════════════════════════
        # Lab 8 exercise 5.4: create website3.local server block on port 443;
        # nginx.conf must also listen on port 443; all three sites must respond.
        @{
            Name       = 'Nginx — Exercise 3'
            Target     = 'Linux'
            Evaluation = 'Nginx'
            Collector  = 'Nginx'
            Variables  = @{
                # ── Sudo password for firewall-cmd on Rocky Linux ──────────────────
                Password              = 'Student1'

                # ── nginx.conf listen directives: must include port 80 AND 443 ─────
                NginxConfListenTests  = @(
                    @{ ListenLine = 'listen 80;'; PassGrade = 1 }
                    @{ ListenLine = 'listen 443;'; PassGrade = 1 }
                )

                # ── nginx.conf must include conf.d ─────────────────────────────────
                NginxConfIncludeTests = @(
                    @{ IncludeLine = 'include /etc/nginx/conf.d/*.conf;'; PassGrade = 1 }
                )

                # ── Directory structure ────────────────────────────────────────────
                DirectoryTests        = @(
                    @{ Path = '/var/www/website3.local/html'; PassGrade = 1 }
                    @{ Path = '/var/www/website3.local/log'; PassGrade = 1 }
                )

                # ── website3.local.conf in conf.d (served on port 443) ────────────
                NginxConfFileTests    = @(
                    @{ ConfFile = 'website3.local.conf'; ContainsLine = 'server {'; PassGrade = 1 }
                    @{ ConfFile = 'website3.local.conf'; ContainsLine = 'listen 443;'; PassGrade = 1 }
                    @{ ConfFile = 'website3.local.conf'; ContainsLine = 'server_name website3.local www.website3.local;'; PassGrade = 1 }
                    @{ ConfFile = 'website3.local.conf'; ContainsLine = 'root /var/www/website3.local/html;'; PassGrade = 1 }
                )

                # ── Index file content ─────────────────────────────────────────────
                ContentTests          = @(
                    @{ ExpectedContent = 'You have reached the indexpage of website3.local on nginx.'; PassGrade = 1 }
                )

                # ── Live tests: all three websites must respond correctly ──────────
                CurlTests             = @(
                    @{
                        Url             = 'http://website1.local'
                        ResolveHost     = 'website1.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website1.local on nginx.'
                        PassGrade       = 1
                    }
                    @{
                        Url             = 'http://website2.local'
                        ResolveHost     = 'website2.local'
                        ResolvePort     = 80
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website2.local on nginx.'
                        PassGrade       = 1
                    }
                    @{
                        Url             = 'http://website3.local:443'
                        ResolveHost     = 'website3.local'
                        ResolvePort     = 443
                        ResolveAddress  = '127.0.0.1'
                        ExpectedContent = 'You have reached the indexpage of website3.local on nginx.'
                        PassGrade       = 3
                    }
                )
            }
        }
    )
}
