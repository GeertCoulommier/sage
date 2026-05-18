# Collectors/Invoke-NginxCollector.ps1
# Runs ON the remote Linux VM. Returns structured Nginx data for evaluation.
# All output is plain hashtables/strings — safe for CLIXML deserialization.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables',
    Justification = 'Variables consumed for password (sudo) and test parameters.')]
param(
    [Parameter()][hashtable] $Variables = @{}
)

$Result = @{
    Available = $false
    Reason    = $null
    Data      = @{
        ServiceEnabled    = $false
        ServiceRunning    = $false
        SitesAvailable    = $false
        SitesEnabled      = $false
        NginxConfListen   = @()
        NginxConfInclude  = @()
        ConfFiles         = @()
        IndexFiles        = @()
        FirewallServices  = @()
        Directories       = @{}
        SymlinkFiles      = @()
        CurlResults       = @()
        PhpFpmEnabled     = $false
        PhpFpmRunning     = $false
        PhpFpmConfContent = ''
        PhpFiles          = @()
    }
    Errors    = @()
}

$Password = if ($Variables.Password) { $Variables.Password } else { $null }

# ── Check Nginx availability ──────────────────────────────────────────────────
try {
    $NginxBin = Get-Command nginx -ErrorAction SilentlyContinue
    if (-not $NginxBin) {
        $Result.Reason = 'Nginx is not installed'
        return $Result
    }
}
catch {
    $Result.Reason = "Nginx check failed: $($_.Exception.Message)"
    return $Result
}
$Result.Available = $true

# ── Service status ────────────────────────────────────────────────────────────
try {
    $StatusOutput = if ($Password) {
        Write-Output $Password | sudo -S systemctl status nginx 2>/dev/null
    }
    else {
        systemctl status nginx 2>/dev/null
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

# ── Firewall services ─────────────────────────────────────────────────────────
try {
    $FirewallOutput = if ($Password) {
        Write-Output $Password | sudo -S firewall-cmd --list-services 2>/dev/null
    }
    else {
        firewall-cmd --list-services 2>/dev/null
    }
    if ($FirewallOutput) {
        $Result.Data.FirewallServices = @($FirewallOutput -split '\s+' | Where-Object { $_ -ne '' })
    }
}
catch {
    $Result.Errors += "Firewall check failed: $($_.Exception.Message)"
}

# ── Sites-enabled / sites-available ───────────────────────────────────────────
try {
    $SiteDirs = Get-ChildItem -Recurse -Path '/etc/nginx' -Filter '*sites*' -Directory -ErrorAction SilentlyContinue
    foreach ($Dir in $SiteDirs) {
        if ($Dir.Name -eq 'sites-available') { $Result.Data.SitesAvailable = $true }
        if ($Dir.Name -eq 'sites-enabled') { $Result.Data.SitesEnabled = $true }
    }
}
catch {
    $Result.Errors += "Sites directory check failed: $($_.Exception.Message)"
}

# ── Parse nginx.conf ──────────────────────────────────────────────────────────
try {
    $NginxConfPath = '/etc/nginx/nginx.conf'
    if (Test-Path $NginxConfPath) {
        $NginxConf = Get-Content $NginxConfPath -ErrorAction Stop
        $Result.Data.NginxConfListen = @(
            ($NginxConf | Select-String -Pattern 'listen' |
                Where-Object { $_.Line -notmatch '^\s*#' }) |
                    ForEach-Object { ($_.Line.Trim() -replace '\s+', ' ') }
        )
        $Result.Data.NginxConfInclude = @(
            ($NginxConf | Select-String -Pattern 'include' |
                Where-Object { $_.Line -notmatch '^\s*#' }) |
                    ForEach-Object { ($_.Line.Trim() -replace '\s+', ' ') }
        )
    }
}
catch {
    $Result.Errors += "nginx.conf parse failed: $($_.Exception.Message)"
}

# ── Collect virtual host config files ─────────────────────────────────────────
$ConfSearchPaths = @('/etc/nginx/conf.d')
if ($Result.Data.SitesAvailable) { $ConfSearchPaths += '/etc/nginx/sites-available' }
if ($Result.Data.SitesEnabled) { $ConfSearchPaths += '/etc/nginx/sites-enabled' }

foreach ($ConfPath in $ConfSearchPaths) {
    try {
        if (Test-Path $ConfPath) {
            $ConfFiles = Get-ChildItem -Path $ConfPath -Filter '*.conf' -ErrorAction SilentlyContinue
            foreach ($ConfFile in $ConfFiles) {
                # Skip symbolic links to avoid duplicates
                if ($ConfFile.LinkType) { continue }

                $Content = Get-Content $ConfFile.FullName -ErrorAction Stop
                $ListenLines = @(($Content | Select-String -Pattern 'listen' |
                            Where-Object { $_.Line -notmatch '^\s*#' }) |
                            ForEach-Object { ($_.Line.Trim() -replace '\s+', ' ') })
                $ServerNameLines = @(($Content | Select-String -Pattern 'server_name' |
                            Where-Object { $_.Line -notmatch '^\s*#' }) |
                            ForEach-Object { ($_.Line.Trim() -replace '\s+', ' ') })
                $RootLines = @(($Content | Select-String -Pattern '^\s*root\s' |
                            Where-Object { $_.Line -notmatch '^\s*#' }) |
                            ForEach-Object { ($_.Line.Trim() -replace '\s+', ' ') })

                $Result.Data.ConfFiles += @{
                    Name       = $ConfFile.Name
                    Path       = $ConfFile.FullName
                    Location   = $ConfFile.DirectoryName
                    Listen     = $ListenLines
                    ServerName = $ServerNameLines
                    Root       = $RootLines
                    Content    = (($Content | ForEach-Object { ($_ -replace '\s+', ' ').Trim() }) -join "`n")
                }
            }
        }
    }
    catch {
        $Result.Errors += "Config scan '$ConfPath': $($_.Exception.Message)"
    }
}

# ── Collect symlinks in sites-enabled ─────────────────────────────────────────
try {
    if (Test-Path '/etc/nginx/sites-enabled') {
        $SitesItems = Get-ChildItem -Path '/etc/nginx/sites-enabled' -Filter '*.conf' -ErrorAction SilentlyContinue
        foreach ($Item in $SitesItems) {
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
    $Result.Errors += "Symlink scan failed: $($_.Exception.Message)"
}

# ── Collect index.html files ──────────────────────────────────────────────────
try {
    $IndexItems = Get-ChildItem -Recurse -Path '/var/www' -Include 'index.html' -ErrorAction SilentlyContinue
    foreach ($Idx in $IndexItems) {
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

# ── Directory existence tests ─────────────────────────────────────────────────
if ($Variables.DirectoryTests) {
    foreach ($Test in $Variables.DirectoryTests) {
        $Path = $Test.Path
        $Result.Data.Directories[$Path] = (Test-Path $Path -PathType Container)
    }
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
    if ($PhpFpmStatus -like '*enabled*') {
        $Result.Data.PhpFpmEnabled = $true
    }
}
catch {
    $Result.Errors += "PHP-FPM service check failed: $($_.Exception.Message)"
}

# ── PHP-FPM config content ────────────────────────────────────────────────────
try {
    $PhpFpmConfPath = '/etc/php-fpm.d/www.conf'
    if (Test-Path $PhpFpmConfPath) {
        $PhpFpmConf = Get-Content $PhpFpmConfPath -ErrorAction Stop
        $Result.Data.PhpFpmConfContent = (
            ($PhpFpmConf | ForEach-Object { ($_ -replace '\s+', ' ').Trim() }) -join "`n"
        )
    }
}
catch {
    $Result.Errors += "PHP-FPM config read failed: $($_.Exception.Message)"
}

# ── Collect PHP files ─────────────────────────────────────────────────────────
try {
    $PhpItems = Get-ChildItem -Recurse -Path '/var/www' -Include '*.php' -ErrorAction SilentlyContinue
    foreach ($PhpFile in $PhpItems) {
        $Content = Get-Content $PhpFile.FullName -ErrorAction SilentlyContinue
        $Result.Data.PhpFiles += @{
            Name    = $PhpFile.Name
            Path    = $PhpFile.FullName
            Dir     = $PhpFile.DirectoryName
            Content = ($Content -join "`n")
        }
    }
}
catch {
    $Result.Errors += "PHP file scan failed: $($_.Exception.Message)"
}

# ── Live curl tests ───────────────────────────────────────────────────────────
if ($Variables.CurlTests) {
    foreach ($Test in $Variables.CurlTests) {
        $CurlArgs = @('--silent', '--max-time', '5', '--output', '-')
        if ($Test.ResolveHost -and $Test.ResolvePort -and $Test.ResolveAddress) {
            $CurlArgs += '--resolve'
            $CurlArgs += "$($Test.ResolveHost):$($Test.ResolvePort):$($Test.ResolveAddress)"
        }
        $CurlArgs += $Test.Url

        $CurlOutput = ''
        $CurlSuccess = $false
        try {
            $CurlOutput = curl @CurlArgs 2>/dev/null
            $CurlSuccess = $true
        }
        catch {
            $CurlOutput = ''
        }

        $Result.Data.CurlResults += @{
            Url             = $Test.Url
            Success         = $CurlSuccess
            Content         = $CurlOutput
            ExpectedContent = $Test.ExpectedContent
        }
    }
}

return $Result
