# Proefexamen ServerOS 2525-2526
# 300 raw points → /20   (150 Windows + 150 Linux)
@{
    Name                    = 'Proefexamen ServerOS 2025-26'
    Version                 = '1.0.0'
    Description             = 'Proefexamen ServerOS – academiejaar 2025-26. 300 punten totaal (150 Windows + 150 Linux) → /20.'
    Author                  = 'SAGE'
    ExamStart               = '2026-05-26T08:00:00'
    ExamEnd                 = '2026-05-26T12:00:00'

    Targets                 = @{
        Linux  = @{
            Port             = 20022
            UserName         = 'student'
            Platform         = 'Linux'
            CredentialSecret = 'LinuxStudentUser'
        }
        DC1    = @{
            Port             = 30022
            UserName         = 'administrator'
            Platform         = 'Windows'
            CredentialSecret = 'WindowsAdminUser'
        }
        Client = @{
            Port             = 50022
            UserName         = 'student'
            Platform         = 'Windows'
            CredentialSecret = 'WindowsStudentUser'
        }
    }

    DefaultCredentialSecret = 'DefaultCredential'

    Roster                  = @{
        IPField    = 'ip'
        EmailField = 'StudentEmail'
        NameField  = 'student'
        Delimiter  = ';'
    }

    Export                  = @{
        PrimaryFormat    = 'Json'
        SecondaryFormats = @('Excel', 'Csv')
    }

    Dependencies            = @{
        Modules = @('Pester')
    }

    AllowedNetworkRanges    = @('10.0.0.0/8', '192.168.0.0/16', '172.16.0.0/12')
    # When $true, preserves temporary script files on remote VMs for inspection
    # (useful for lab scenarios where manual testing is needed).
    # Default: $false (cleanup after evaluation, standard behavior).
    KeepTempFiles           = $true

    Categories              = @(

        # ══════════════════════════════════════════════════════════════════════
        # C1 — General Configuration DC1  (9 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'General Configuration DC1'
            Target     = 'DC1'
            Evaluation = 'GeneralConfig'
            Collector  = 'GeneralConfig'
            Variables  = @{
                HostnameTests   = @(
                    @{ ExpectedHostname = 'DC1'; PassGrade = 4 }
                )
                StaticIPTests   = @(
                    @{
                        ExpectedIP      = '192.168.1.3'
                        ExpectedPrefix  = 24
                        ExpectedGateway = '192.168.1.1'
                        PassGrade       = 2
                    }
                )
                AllowedDnsTests = @(
                    @{
                        AllowedDns       = @('127.0.0.1', '::1')
                        RequiredDnsCount = 1
                        PassGrade        = 3
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C2 — General Configuration Client  (6 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'General Configuration Client'
            Target     = 'Client'
            Evaluation = 'GeneralConfig'
            Collector  = 'GeneralConfig'
            Variables  = @{
                HostnameTests   = @(
                    @{ ExpectedHostname = 'client'; PassGrade = 4 }
                )
                AllowedDnsTests = @(
                    @{
                        AllowedDns       = @('192.168.1.3')
                        RequiredDnsCount = 1
                        PassGrade        = 2
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C3 — DNS DC1  (27 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'DNS DC1'
            Target     = 'DC1'
            Evaluation = 'Dns'
            Collector  = 'Dns'
            Variables  = @{
                ForwardZones = @(
                    @{
                        ZoneName  = 'proef.be'
                        ZoneType  = 'Primary'
                        PassGrade = 5
                    }
                )
                NsRecords    = @(
                    @{ Zone = 'proef.be'; Expected = 'dc2.proef.be'; PassGrade = 2 }
                )
                ARecords     = @(
                    @{ Name = 'dc1'; IP = '192.168.1.3'; Zone = 'proef.be'; PassGrade = 3 }
                    @{ Name = 'client'; IP = '192.168.1.5'; Zone = 'proef.be'; PassGrade = 1 }
                    @{ Name = 'dc2'; IP = '192.168.1.4'; Zone = 'proef.be'; PassGrade = 1 }
                    @{
                        AnyOfNames = @('linux', 'rockylinux')
                        IP         = '192.168.1.2'
                        Zone       = 'proef.be'
                        PassGrade  = 1
                    }
                    @{ Name = '@'; IP = '192.168.1.5'; Zone = 'proef.be'; PassGrade = 1 }
                )
                CnameRecords = @(
                    @{ Name = 'www'; Target = 'client.proef.be'; Zone = 'proef.be'; PassGrade = 1 }
                )
                MxRecords    = @(
                    @{ Zone = 'proef.be'; Target = 'dc1.proef.be'; PassGrade = 2 }
                )
                ReverseZones = @(
                    @{ ZoneName = '1.168.192.in-addr.arpa'; ZoneType = 'Primary'; PassGrade = 2 }
                )
                PtrRecords   = @(
                    @{ Name = '2'; AnyOfExpectedPtr = @('linux.proef.be', 'rockylinux.proef.be'); Zone = '1.168.192.in-addr.arpa'; PassGrade = 1 }
                    @{ Name = '3'; ExpectedPtr = 'dc1.proef.be'; Zone = '1.168.192.in-addr.arpa'; PassGrade = 1 }
                    @{ Name = '4'; ExpectedPtr = 'dc2.proef.be'; Zone = '1.168.192.in-addr.arpa'; PassGrade = 1 }
                    @{
                        Name             = '5'
                        AnyOfExpectedPtr = @(
                            'client.proef.be'
                            'client.proef.local'
                            'www.proef.be'
                            'www.proef.local'
                            'proef.be'
                            'proef.local'
                        )
                        Zone             = '1.168.192.in-addr.arpa'
                        PassGrade        = 1
                    }
                )
                Forwarders   = @(
                    @{ IPAddress = '1.1.1.1'; PassGrade = 2 }
                    @{ IPAddress = '1.0.0.1'; PassGrade = 2 }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C4 — Active Directory DC1  (18 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'Active Directory DC1'
            Target     = 'DC1'
            Evaluation = 'Ad'
            Collector  = 'Ad'
            Variables  = @{
                DomainTests          = @()
                DomainNameTests      = @(
                    @{ ExpectedDomain = 'proef.local'; PassGrade = 5 }
                )
                ComputerTests        = @(
                    @{ Name = 'client'; PassGrade = 4 }
                )
                OUTests              = @(
                    @{ Name = 'Marketing'; PassGrade = 2 }
                    @{
                        Name       = 'Pers'
                        ExpectedDN = 'OU=Pers,OU=Marketing,DC=proef,DC=local'
                        PassGrade  = 2
                    }
                )
                UserTests            = @(
                    @{ SamAccountName = 'docent'; PassGrade = 2 }
                    @{
                        SamAccountName = 'Daan.Banaan'
                        GivenName      = 'Daan'
                        Surname        = 'Banaan'
                        ExpectedOU     = 'OU=Pers,OU=Marketing'
                        PassGrade      = 1
                    }
                )
                GroupMembershipTests = @(
                    @{ UserSamAccountName = 'docent'; GroupName = 'Domain Admins'; PassGrade = 2 }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C5a — File Server DC1  (27 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'File Server DC1'
            Target     = 'DC1'
            Evaluation = 'FileServer'
            Collector  = 'FileServer'
            Variables  = @{
                ShareTests       = @(
                    @{ ShareName = 'Shared'; PassGrade = 3 }
                )
                ShareAccessTests = @(
                    @{
                        ShareName       = 'Shared'
                        ExpectedAccount = 'Everyone'
                        ExpectedAccess  = 'Full'
                        PassGrade       = 2
                    }
                )
                FolderTests      = @(
                    @{ ShareName = 'Shared'; RelativePath = 'Opleidingen'; PassGrade = 4 }
                )
                NtfsTests        = @(
                    @{
                        ShareName        = 'Shared'
                        RelativePath     = 'Opleidingen'
                        ExpectedIdentity = 'Opleidingen-R'
                        ExpectedRights   = 'ReadAndExecute'
                        PassGrade        = 6
                    }
                    @{
                        ShareName        = 'Shared'
                        RelativePath     = 'Opleidingen'
                        ExpectedIdentity = 'Opleidingen-W'
                        ExpectedRights   = 'Modify'
                        PassGrade        = 6
                    }
                    @{
                        ShareName        = 'Shared'
                        RelativePath     = 'Opleidingen'
                        ExpectedIdentity = 'Opleidingen-FC'
                        ExpectedRights   = 'FullControl'
                        PassGrade        = 6
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C5b — AD Groups DC1  (9 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'Active Directory Groups DC1'
            Target     = 'DC1'
            Evaluation = 'Ad'
            Collector  = 'Ad'
            Variables  = @{
                DomainTests          = @()
                DomainNameTests      = @()
                ComputerTests        = @()
                OUTests              = @()
                UserTests            = @()
                GroupMembershipTests = @()
                GroupExistenceTests  = @(
                    @{ Name = 'Opleidingen-R'; GroupScope = 'DomainLocal'; GroupCategory = 'Security'; PassGrade = 1 }
                    @{ Name = 'Opleidingen-W'; GroupScope = 'DomainLocal'; GroupCategory = 'Security'; PassGrade = 1 }
                    @{ Name = 'Opleidingen-FC'; GroupScope = 'DomainLocal'; GroupCategory = 'Security'; PassGrade = 0 }
                    @{ Name = 'HR'; GroupScope = 'Global'; GroupCategory = 'Security'; PassGrade = 1 }
                    @{ Name = 'Pers'; GroupScope = 'Global'; GroupCategory = 'Security'; PassGrade = 1 }
                    @{ Name = 'Public-R'; GroupScope = 'DomainLocal'; GroupCategory = 'Security'; PassGrade = 1 }
                )
                GroupHasMembersTests = @(
                    @{ GroupName = 'HR'; MinMemberCount = 1; RequiredMemberOU = 'HR'; PassGrade = 1 }
                    @{ GroupName = 'Pers'; MinMemberCount = 1; RequiredMemberOU = 'Pers'; PassGrade = 0 }
                )
                GroupInGroupTests    = @(
                    @{ ParentGroupName = 'Opleidingen-FC'; ChildGroupName = 'Pers'; PassGrade = 2 }
                    @{ ParentGroupName = 'Opleidingen-W'; ChildGroupName = 'HR'; PassGrade = 2 }
                    @{ ParentGroupName = 'Public-R'; ChildGroupName = 'Domain Users'; PassGrade = 2 }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C6 — GPO DC1  (27 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'GPO DC1'
            Target     = 'DC1'
            Evaluation = 'Gpo'
            Collector  = 'Gpo'
            Variables  = @{
                GpoExistenceTests  = @(
                    @{ GpoName = 'X-drive-mapping-Opleidingen'; PassGrade = 4 }
                    @{ GpoName = 'ehb-background'; PassGrade = 3 }
                )
                GpoLinkTests       = @(
                    @{
                        GpoName          = 'X-drive-mapping-Opleidingen'
                        LinkExpectation  = 'be linked to Marketing, HR, Directie, Productie, Sales and be enabled'
                        ExpectedLinksAll = @(
                            'Marketing'
                            'HR'
                            'Directie'
                            'Productie'
                            'Sales'
                        )
                        PassGrade        = 5
                    }
                    @{
                        GpoName         = 'X-drive-mapping-Opleidingen'
                        LinkExpectation = 'NOT be linked to IT'
                        ForbiddenLinks  = @('IT')
                        PassGrade       = 2
                    }
                    @{
                        GpoName         = 'ehb-background'
                        LinkExpectation = 'be linked to domain root (proef.local) and be enabled'
                        DomainRootLink  = $true
                        PassGrade       = 3
                    }
                )
                GpoDriveMapTests   = @(
                    @{
                        GpoName           = 'X-drive-mapping-Opleidingen'
                        DriveLetter       = 'X'
                        DrivePath         = '\\dc1.proef.local\Shared\Opleidingen'
                        ExpectedPathRegex = '(?i)\\\\dc1(\.proef\.local)?\\[Ss]hared\\[Oo]pleidingen\\?'
                        PassGrade         = 7
                    }
                )
                GpoPolicyTests     = @(
                    @{
                        GpoName               = 'ehb-background'
                        PolicyName            = 'Desktop Wallpaper'
                        ExpectedState         = 'Enabled'
                        ExpectedPathRegex     = '(?i)Shared[\\\/]+Public[\\\/]+background[\\\/]+ehb\.jpg'
                        ScopeType             = 'User'
                        AlternativePolicySets = @(
                            @(
                                @{
                                    PolicyName    = 'Enable Active Desktop'
                                    ExpectedState = 'Enabled'
                                    ScopeType     = 'User'
                                }
                                @{
                                    PolicyName        = 'Active Desktop Wallpaper'
                                    ExpectedState     = 'Enabled'
                                    ExpectedPathRegex = '(?i)Shared[\\\/]+Public[\\\/]+background[\\\/]+ehb\.jpg'
                                    ScopeType         = 'User'
                                }
                            )
                        )
                        PassGrade             = 3
                    }
                )
                GpoSoftwareTests   = @()
                GpoScopeTests      = @()
                GpoPermissionTests = @()
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C6-bg — File Server Background  (9 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'File Server Background DC1'
            Target     = 'DC1'
            Evaluation = 'FileServer'
            Collector  = 'FileServer'
            Variables  = @{
                ShareTests  = @()
                FolderTests = @(
                    @{ ShareName = 'Shared'; RelativePath = 'Public\background'; PassGrade = 3 }
                )
                FileTests   = @(
                    @{
                        ShareName       = 'Shared'
                        RelativePath    = 'Public\background'
                        ExpectedPattern = 'ehb\.jpg'
                        PassGrade       = 3
                    }
                )
                NtfsTests   = @(
                    @{
                        ShareName               = 'Shared'
                        RelativePath            = 'Public'
                        AnyOfExpectedIdentities = @('Public-R', 'Public-Read', 'Public-Lezen')
                        ExpectedRights          = 'ReadAndExecute'
                        PassGrade               = 3
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C7 — DHCP DC1  (18 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'DHCP DC1'
            Target     = 'DC1'
            Evaluation = 'Dhcp'
            Collector  = 'Dhcp'
            Variables  = @{
                ServerTests      = @(
                    @{ PassGrade = 4 }
                )
                ScopeTests       = @(
                    @{
                        ScopeId    = '192.168.1.0'
                        Name       = 'scope_clients'
                        StartRange = '192.168.1.1'
                        EndRange   = '192.168.1.200'
                        SubnetMask = '255.255.255.0'
                        PassGrade  = 4
                    }
                )
                ExclusionTests   = @(
                    @{
                        ScopeId    = '192.168.1.0'
                        StartRange = '192.168.1.1'
                        EndRange   = '192.168.1.50'
                        PassGrade  = 2
                    }
                )
                OptionTests      = @(
                    @{ ScopeId = '192.168.1.0'; OptionName = 'Router'; ExpectedValue = '192.168.1.1'; PassGrade = 2 }
                    @{ ScopeId = '192.168.1.0'; OptionName = 'DNS Domain Name'; ExpectedValue = 'proef.local'; PassGrade = 2 }
                    @{ ScopeId = '192.168.1.0'; OptionName = 'DNS Servers'; ExpectedValue = '192.168.1.3'; PassGrade = 2 }
                )
                ReservationTests = @(
                    @{ ScopeId = '192.168.1.0'; IPAddress = '192.168.1.5'; PassGrade = 2 }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C8 — IIS Client  (36 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'IIS Client'
            Target     = 'Client'
            Evaluation = 'Iis'
            Collector  = 'Iis'
            Variables  = @{
                WebsiteTests           = @(
                    @{
                        Name        = 'proef.be'
                        State       = 'Started'
                        AppPoolName = 'DefaultAppPool'
                        PassGrade   = 10
                    }
                )
                BindingTests           = @(
                    @{ SiteName = 'proef.be'; ExpectedUri = 'http://proef.be:8080'; PassGrade = 2 }
                    @{ SiteName = 'proef.be'; ExpectedUri = 'http://www.proef.be:8080'; PassGrade = 2 }
                )
                AppPoolTests           = @(
                    @{ Name = 'DefaultAppPool'; PassGrade = 0 }
                )
                VirtualDirectoryTests  = @(
                    @{ SiteName = 'proef.be'; VDirPath = '/vDir1'; PassGrade = 5 }
                )
                DirectoryBrowsingTests = @(
                    @{ SiteName = 'proef.be'; VDirPath = '/vDir1'; Enabled = $true; PassGrade = 2 }
                )
                AuthTests              = @(
                    @{ SiteName = 'proef.be'; VDirPath = '/vDir1'; AuthMethod = 'Basic'; Enabled = $true; PassGrade = 4 }
                )
                SiteFileContentTests   = @(
                    @{ SiteName = 'proef.be'; ExpectedContent = 'proef.be'; PassGrade = 5 }
                )
                CurlTests              = @(
                    @{ Url = 'http://proef.be:8080'; ExpectedContent = 'proef.be'; PassGrade = 6 }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C9 — Nginx Linux  (42 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'Nginx Linux'
            Target     = 'Linux'
            Evaluation = 'Nginx'
            Collector  = 'Nginx'
            Variables  = @{
                ServiceTests          = @(
                    @{ Property = 'enabled'; PassGrade = 2 }
                    @{ Property = 'running'; PassGrade = 2 }
                    @{ Property = 'sites-available'; PassGrade = 2 }
                    @{ Property = 'sites-enabled'; PassGrade = 2 }
                )
                NginxConfListenTests  = @(
                    @{ ListenLine = '80'; PassGrade = 2 }
                    @{ ListenLine = '443'; PassGrade = 2 }
                )
                NginxConfIncludeTests = @(
                    @{ IncludeLine = 'sites-enabled'; PassGrade = 2 }
                )
                NginxConfFileTests    = @(
                    @{
                        ConfFile     = 'nginx.proef.be.conf'
                        ContainsLine = 'server {'
                        PassGrade    = 2
                    }
                    @{
                        ConfFile     = 'nginx.proef.be.conf'
                        ContainsLine = 'listen 80;'
                        PassGrade    = 5
                    }
                    @{
                        ConfFile       = 'nginx.proef.be.conf'
                        ContainsTokens = @(
                            'server_name'
                            'nginx.proef.be'
                        )
                        PassGrade      = 3
                    }
                    @{
                        ConfFile       = 'nginx.proef.be.conf'
                        ContainsTokens = @(
                            'server_name'
                            'www2.proef.be'
                        )
                        PassGrade      = 3
                    }
                )
                SymlinkTests          = @(
                    @{
                        SymlinkPath    = '/etc/nginx/sites-enabled/nginx.proef.be.conf'
                        ExpectedTarget = '/etc/nginx/sites-available/nginx.proef.be.conf'
                        PassGrade      = 3
                    }
                )
                DirectoryTests        = @(
                    @{ Path = '/var/www/nginx.proef.be'; PassGrade = 3 }
                )
                ContentTests          = @(
                    @{ ExpectedContent = 'nginx.proef.be'; PassGrade = 3 }
                )
                CurlTests             = @(
                    @{
                        Url             = 'http://nginx.proef.be'
                        ResolveHost     = 'nginx.proef.be'
                        ResolvePort     = 80
                        ResolveAddress  = '192.168.1.2'
                        ExpectedContent = 'nginx.proef.be'
                        PassGrade       = 5
                    }
                    @{
                        Url             = 'http://www2.proef.be'
                        ResolveHost     = 'www2.proef.be'
                        ResolvePort     = 80
                        ResolveAddress  = '192.168.1.2'
                        ExpectedContent = 'nginx.proef.be'
                        PassGrade       = 4
                    }
                )
            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C10 — Docker Images Linux  (36 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'Docker Images Linux'
            Target     = 'Linux'
            Evaluation = 'Docker'
            Collector  = 'Docker'
            Variables  = @{
                ImageTests           = @(
                    @{ Repository = 'httpd_docker'; Tag = 'latest'; PassGrade = 5 }
                )
                ContainerTests       = @(
                    @{ Name = 'httpd_docker'; State = 'running'; PassGrade = 5 }
                )
                DockerfileTests      = @(
                    @{
                        Path         = '/home/student/httpd_docker/Dockerfile'
                        ExpectedFrom = 'httpd'
                        PassGrade    = 5
                    }
                    @{
                        # Allow any source path: ./index.html, absolute, or sub-dir
                        Path         = '/home/student/httpd_docker/Dockerfile'
                        ExpectedCopy = 'index.html /usr/local/apache2/htdocs/'
                        PassGrade    = 4
                    }
                )
                ContainerPortTests   = @(
                    @{
                        Name          = 'httpd_docker'
                        HostPort      = '8081'
                        ContainerPort = '80'
                        PassGrade     = 5
                    }
                )
                CurlTests            = @(
                    @{
                        Url             = 'http://192.168.1.2:8081'
                        ExpectedContent = 'apache in docker'
                        PassGrade       = 12
                    }
                )
                ComposeTests         = @()
                ComposeContentTests  = @()
                FileContentTests     = @()
                ContainerVolumeTests = @()

            }
        }

        # ══════════════════════════════════════════════════════════════════════
        # C11 — Docker Compose Linux  (36 pts)
        # ══════════════════════════════════════════════════════════════════════
        @{
            Name       = 'Docker Compose Linux'
            Target     = 'Linux'
            Evaluation = 'Docker'
            Collector  = 'Docker'
            Variables  = @{
                ImageTests           = @()
                DockerfileTests      = @()
                ContainerTests       = @(
                    @{ Name = 'volumetest'; State = 'running'; PassGrade = 5 }
                )
                ComposeTests         = @(
                    @{
                        Path             = '/home/student/volumetest/compose.yml'
                        ExpectedServices = @('nginx')
                        PassGrade        = 0
                    }
                )
                ComposeContentTests  = @(
                    @{
                        Path          = '/home/student/volumetest/compose.yml'
                        Key           = 'ports'
                        ContainsValue = '8082:80'
                        PassGrade     = 7
                    }
                )
                ContainerVolumeTests = @(
                    @{
                        Name             = 'volumetest'
                        HostPath         = '/home/student/volumetest'
                        AllowedHostPaths = @('/home/student/volumetest', '/home/student/volumetest/html')
                        ContainerPath    = '/usr/share/nginx/html'
                        PassGrade        = 5
                    }
                )
                ContainerPortTests   = @(
                    @{
                        Name          = 'volumetest'
                        HostPort      = '8082'
                        ContainerPort = '80/tcp'
                        PassGrade     = 2
                    }
                )
                FileContentTests     = @(
                    @{
                        Path            = '/home/student/volumetest/index.html'
                        AllowedPaths    = @('/home/student/volumetest/index.html', '/home/student/volumetest/html/index.html')
                        ExpectedContent = 'volumetest'
                        PassGrade       = 5
                    }
                )
                CurlTests            = @(
                    @{
                        Url             = 'http://192.168.1.2:8082'
                        ExpectedContent = 'volumetest'
                        PassGrade       = 12
                    }
                )
            }
        }
    )
}

