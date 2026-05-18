# Collectors/Invoke-ApacheCollector.ps1
# Runs ON the remote Linux VM. Returns structured Apache (httpd) data for evaluation.
# All output is plain hashtables/strings — safe for CLIXML deserialization.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables',
    Justification = 'Variables consumed for password (sudo) access.')]
param(
    [Parameter()][hashtable] $Variables = @{}
)

$Result = @{
    Available = $false
    Reason    = $null
    Data      = @{
        ServiceEnabled   = $false
        ServiceRunning   = $false
        SitesAvailable   = $false
        SitesEnabled     = $false
        HttpdConfListen  = @()
        HttpdConfInclude = @()
        ConfFiles        = @()
        IndexFiles       = @()
        FirewallServices = @()
        Directories      = @{}
        SymlinkFiles     = @()
        CurlResults      = @()
        MariaDbEnabled   = $false
        MariaDbRunning   = $false
        PhpFpmEnabled    = $false
        PhpFpmRunning    = $false
        PhpFiles         = @()
    }
    Errors    = @()
}

$Password = if ($Variables.Password) { $Variables.Password } else { $null }

# ── Check Apache (httpd) availability ─────────────────────────────────────────
try {
    $HttpdBin = Get-Command httpd -ErrorAction SilentlyContinue
    if (-not $HttpdBin) {
        $Result.Reason = 'Apache (httpd) is not installed'
        return $Result
    }
}
catch {
    $Result.Reason = "Apache check failed: $($_.Exception.Message)"
    return $Result
}
$Result.Available = $true

# ── Service status ────────────────────────────────────────────────────────────
try {
    $StatusOutput = if ($Password) {
        Write-Output $Password | sudo -S systemctl status httpd 2>/dev/null
    }
    else {
        systemctl status httpd 2>/dev/null
    }

    if ($StatusOutput -like '*Active: active (running)*') {
        $Result.Data.ServiceRunning = $true
    }
    if ($StatusOutput -like '*enabled*') {
        $Result.Data.ServiceEnabled = $true
    }
}
catch {
    $Result.Errors += "Service status check failed: $($_.Exception.Message)"
}

# ── Sites-enabled / sites-available ───────────────────────────────────────────
try {
    $SiteDirs = Get-ChildItem -Path '/etc/httpd/' -Filter '*sites*' -Recurse -Directory -ErrorAction SilentlyContinue
    foreach ($Dir in $SiteDirs) {
        if ($Dir.Name -eq 'sites-available') { $Result.Data.SitesAvailable = $true }
        if ($Dir.Name -eq 'sites-enabled') { $Result.Data.SitesEnabled = $true }
    }
}
catch {
    $Result.Errors += "Sites directory check failed: $($_.Exception.Message)"
}

# ── Parse httpd.conf ──────────────────────────────────────────────────────────
try {
    $HttpdConfPath = '/etc/httpd/conf/httpd.conf'
    if (Test-Path $HttpdConfPath) {
        $HttpdConf = Get-Content $HttpdConfPath -ErrorAction Stop

        $Result.Data.HttpdConfListen = @(
            ($HttpdConf | Select-String -Pattern 'Listen' |
                Where-Object { $_.Line -notmatch '^\s*#' }) |
                    ForEach-Object { $_.Line.Trim() }
        )

        $Result.Data.HttpdConfInclude = @(
            ($HttpdConf | Select-String -Pattern 'IncludeOptional' |
                Where-Object { $_.Line -notmatch '^\s*#' -and $_.Line -match '\.conf' }) |
                    ForEach-Object { $_.Line.Trim() }
        )
    }
}
catch {
    $Result.Errors += "httpd.conf parse failed: $($_.Exception.Message)"
}

# ── Collect virtual host config files ─────────────────────────────────────────
$ExcludeConfFiles = @('autoindex.conf', 'userdir.conf', 'welcome.conf')
$ConfSearchPaths = @('/etc/httpd/conf.d')
if ($Result.Data.SitesAvailable) { $ConfSearchPaths += '/etc/httpd/sites-available' }
if ($Result.Data.SitesEnabled) { $ConfSearchPaths += '/etc/httpd/sites-enabled' }

foreach ($ConfPath in $ConfSearchPaths) {
    try {
        if (Test-Path $ConfPath) {
            $ConfFiles = Get-ChildItem -Path $ConfPath -Filter '*.conf' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin $ExcludeConfFiles }

            foreach ($ConfFile in $ConfFiles) {
                # Skip symbolic links to avoid duplicates
                if ($ConfFile.LinkType) { continue }

                $Content = Get-Content $ConfFile.FullName -ErrorAction Stop
                $VirtualHostLines = @(($Content | Select-String -Pattern 'VirtualHost') |
                        ForEach-Object { $_.Line.Trim() })
                $ListenLines = @(($Content | Select-String -Pattern 'Listen' |
                            Where-Object { $_.Line -notmatch '^\s*#' }) | ForEach-Object { $_.Line.Trim() })
                $ServerNameLines = @(($Content | Select-String -Pattern 'ServerName' |
                            Where-Object { $_.Line -notmatch '^\s*#' }) | ForEach-Object { $_.Line.Trim() })
                $DocumentRootLines = @(($Content | Select-String -Pattern 'DocumentRoot' |
                            Where-Object { $_.Line -notmatch '^\s*#' }) | ForEach-Object { $_.Line.Trim() })
                $ServerAliasLines = @(($Content | Select-String -Pattern 'ServerAlias' |
                            Where-Object { $_.Line -notmatch '^\s*#' }) | ForEach-Object { $_.Line.Trim() })

                $Result.Data.ConfFiles += @{
                    Name         = $ConfFile.Name
                    Path         = $ConfFile.FullName
                    Location     = $ConfFile.DirectoryName
                    VirtualHost  = $VirtualHostLines
                    Listen       = $ListenLines
                    ServerName   = $ServerNameLines
                    DocumentRoot = $DocumentRootLines
                    ServerAlias  = $ServerAliasLines
                    Content      = ($Content -replace '\s+', ' ') -join "`n"
                }
            }
        }
    }
    catch {
        $Result.Errors += "Config scan '$ConfPath': $($_.Exception.Message)"
    }
}

# ── Collect index.html files ──────────────────────────────────────────────────
try {
    $IndexFiles = Get-ChildItem -Recurse -Path '/var/www' -Include 'index.html' -ErrorAction SilentlyContinue
    foreach ($Idx in $IndexFiles) {
        $Content = Get-Content $Idx.FullName -ErrorAction SilentlyContinue
        $Result.Data.IndexFiles += @{
            Path    = $Idx.FullName
            Dir     = $Idx.DirectoryName
            Content = ($Content -join "`n")
        }
    }
}
catch {
    $Result.Errors += "Index file scan failed: $($_.Exception.Message)"
}

# ── Collect php.info files ───────────────────────────────────────────────────
try {
    $PhpInfoFiles = Get-ChildItem -Recurse -Path '/var/www' -Include 'php.info' -ErrorAction SilentlyContinue
    foreach ($PhpFile in $PhpInfoFiles) {
        $Content = Get-Content $PhpFile.FullName -ErrorAction SilentlyContinue
        $Result.Data.PhpFiles += @{
            Path    = $PhpFile.FullName
            Dir     = $PhpFile.DirectoryName
            Name    = $PhpFile.Name
            Content = ($Content -join "`n")
        }
    }
}
catch {
    $Result.Errors += "PHP file scan failed: $($_.Exception.Message)"
}

# ── Firewall services ─────────────────────────────────────────────────────────
try {
    $FwCommand = Get-Command 'firewall-cmd' -ErrorAction SilentlyContinue
    if ($FwCommand) {
        $FwOutput = if ($Password) {
            Write-Output $Password | sudo -S firewall-cmd --list-services 2>/dev/null
        }
        else {
            # Use non-interactive sudo (NOPASSWD) — required on Rocky Linux where
            # firewall-cmd --list-services needs elevated D-Bus access.
            sudo -n firewall-cmd --list-services 2>/dev/null
        }
        if ($FwOutput) {
            $Result.Data.FirewallServices = @($FwOutput -split '\s+' | Where-Object { $_ -ne '' })
        }
    }
}
catch {
    $Result.Errors += "Firewall check failed: $($_.Exception.Message)"
}

# ── Directory existence checks ────────────────────────────────────────────────
$DirsToCheck = if ($Variables.DirectoryTests) {
    @($Variables.DirectoryTests | ForEach-Object { $_.Path })
}
else { @() }

foreach ($DirPath in $DirsToCheck) {
    try {
        $Result.Data.Directories[$DirPath] = (Test-Path $DirPath -PathType Container)
    }
    catch {
        $Result.Data.Directories[$DirPath] = $false
        $Result.Errors += "Directory check '$DirPath': $($_.Exception.Message)"
    }
}

# ── Symlink files in sites-enabled ───────────────────────────────────────────
try {
    if (Test-Path '/etc/httpd/sites-enabled') {
        $SitesEnabledItems = Get-ChildItem -Path '/etc/httpd/sites-enabled' -Filter '*.conf' -ErrorAction SilentlyContinue
        foreach ($Item in $SitesEnabledItems) {
            $Result.Data.SymlinkFiles += @{
                Name       = $Item.Name
                Path       = $Item.FullName
                IsSymlink  = [bool]$Item.LinkType
                LinkTarget = if ($Item.Target) { $Item.Target } else { $null }
            }
        }
    }
}
catch {
    $Result.Errors += "Symlink collection failed: $($_.Exception.Message)"
}

# ── Curl live tests ───────────────────────────────────────────────────────────
$CurlCommand = Get-Command 'curl' -ErrorAction SilentlyContinue
$CurlTargetList = if ($Variables.CurlTests) { $Variables.CurlTests } else { @() }

foreach ($Target in $CurlTargetList) {
    if (-not $CurlCommand) {
        $Result.Data.CurlResults += @{
            Url     = $Target.Url
            Content = $null
            Error   = 'curl not available'
        }
        continue
    }
    try {
        $CurlArgs = @('--silent', '--max-time', '5', '--location')
        if ($Target.ResolveHost -and $Target.ResolvePort -and $Target.ResolveAddress) {
            $CurlArgs += '--resolve'
            $CurlArgs += "$($Target.ResolveHost):$($Target.ResolvePort):$($Target.ResolveAddress)"
        }
        $CurlArgs += $Target.Url
        $Response = & curl @CurlArgs 2>/dev/null
        $Result.Data.CurlResults += @{
            Url     = $Target.Url
            Content = ($Response -join "`n")
            Error   = $null
        }
    }
    catch {
        $Result.Data.CurlResults += @{
            Url     = $Target.Url
            Content = $null
            Error   = $_.Exception.Message
        }
        $Result.Errors += "Curl test '$($Target.Url)': $($_.Exception.Message)"
    }
}

# ── MariaDB service status ────────────────────────────────────────────────────
try {
    $MariaDbStatus = if ($Password) {
        Write-Output $Password | sudo -S systemctl status mariadb 2>/dev/null
    }
    else {
        systemctl status mariadb 2>/dev/null
    }
    if ($MariaDbStatus -like '*Active: active (running)*') {
        $Result.Data.MariaDbRunning = $true
    }
    if ($MariaDbStatus -like '*; enabled;*' -or $MariaDbStatus -like '*enabled;*') {
        $Result.Data.MariaDbEnabled = $true
    }
}
catch {
    $Result.Errors += "MariaDB status check failed: $($_.Exception.Message)"
}

# ── PHP-FPM service status ────────────────────────────────────────────────────
try {
    $PhpFpmStatus = if ($Password) {
        Write-Output $Password | sudo -S systemctl status php-fpm 2>/dev/null
    }
    else {
        systemctl status php-fpm 2>/dev/null
    }
    if ($PhpFpmStatus -like '*Active: active (running)*') {
        $Result.Data.PhpFpmRunning = $true
    }
    if ($PhpFpmStatus -like '*; enabled;*' -or $PhpFpmStatus -like '*enabled;*') {
        $Result.Data.PhpFpmEnabled = $true
    }
}
catch {
    $Result.Errors += "PHP-FPM status check failed: $($_.Exception.Message)"
}

return $Result
