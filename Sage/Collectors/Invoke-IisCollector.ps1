# Collectors/Invoke-IisCollector.ps1
# Runs ON the remote Windows VM. Returns structured IIS data for evaluation.
# Uses IISAdministration module — falls back to PS 5.1 if import fails on PS 7.
# All output is plain hashtables/strings — safe for CLIXML deserialization.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables',
    Justification = 'Variables consumed for exam-specific parameters.')]
param(
    [Parameter()][hashtable] $Variables = @{}
)

$Result = @{
    Available = $false
    Reason    = $null
    Data      = @{
        Websites    = @()
        AppPools    = @()
        CurlResults = @()
    }
    Errors    = @()
}

# ── Helper: Convert binding to URI ───────────────────────────────────────────
<#
.SYNOPSIS
    Converts an IIS binding entry to a URI string.
.DESCRIPTION
    Parses the IIS binding info format (IP:Port:HostHeader) together with the
    protocol and returns a formatted URI, omitting the default port when
    appropriate (80 for http, 443 for https).
.PARAMETER Protocol
    The binding protocol (e.g. 'http', 'https').
.PARAMETER BindingInfo
    The IIS binding info string in the format 'IP:Port:HostHeader'.
.OUTPUTS
    System.String
.EXAMPLE
    ConvertTo-BindingUri -Protocol 'http' -BindingInfo '*:80:'
#>
function ConvertTo-BindingUri {
    [CmdletBinding()]
    param(
        [Parameter()][string] $Protocol,
        [Parameter()][string] $BindingInfo
    )
    $Parts = $BindingInfo.Split(':')
    $Host_ = if ($Parts[2]) { $Parts[2] } elseif ($Parts[0] -eq '*') { '127.0.0.1' } else { $Parts[0] }
    $Port = $Parts[1]
    $Uri = "${Protocol}://${Host_}"
    if (($Protocol -eq 'http' -and $Port -ne '80') -or ($Protocol -eq 'https' -and $Port -ne '443')) {
        $Uri += ":$Port"
    }
    $Uri
}

# ── Collect IIS data ─────────────────────────────────────────────────────────
# Try PS 7 first with -SkipEditionCheck, fall back to PS 5.1 via powershell.exe
$IisJson = $null

try {
    Import-Module IISAdministration -SkipEditionCheck -ErrorAction Stop
    $IisJson = '__PS7_DIRECT__'
}
catch {
    # Module not available on PS 7 — try PS 5.1 fallback
    $Ps5Exe = if ($env:SystemRoot) {
        Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }
    else {
        $null
    }
    if ($Ps5Exe -and (Test-Path $Ps5Exe)) {
        try {
            $IisJson = & $Ps5Exe -NoProfile -Command {
                try {
                    Import-Module IISAdministration -ErrorAction Stop
                    $Mgr = Get-IISServerManager
                    $HostConfig = $Mgr.GetApplicationHostConfiguration()
                    $Sites = foreach ($Site in $Mgr.Sites) {
                        $VDirs = foreach ($App in $Site.Applications) {
                            foreach ($VDir in $App.VirtualDirectories) {
                                $AppRel = $App.Path.TrimStart('/')
                                $VDirRel = $VDir.Path.TrimStart('/')
                                $LocPath = $Site.Name
                                if ($AppRel) { $LocPath += "/$AppRel" }
                                if ($VDirRel) { $LocPath += "/$VDirRel" }
                                $AnonSec = try { $HostConfig.GetSection('system.webServer/security/authentication/anonymousAuthentication', $LocPath) } catch { $null }
                                $BasicSec = try { $HostConfig.GetSection('system.webServer/security/authentication/basicAuthentication', $LocPath) } catch { $null }
                                $WinSec = try { $HostConfig.GetSection('system.webServer/security/authentication/windowsAuthentication', $LocPath) } catch { $null }
                                $DirSec = try { $HostConfig.GetSection('system.webServer/directoryBrowse', $LocPath) } catch { $null }
                                $Auth = @(
                                    @{ Method = 'Anonymous'; Enabled = [bool]($AnonSec -and $AnonSec['enabled']) }
                                    @{ Method = 'Basic'; Enabled = [bool]($BasicSec -and $BasicSec['enabled']) }
                                    @{ Method = 'Windows'; Enabled = [bool]($WinSec -and $WinSec['enabled']) }
                                )
                                $VDirParts = @($AppRel, $VDirRel) | Where-Object { $_ }
                                $VDirVPath = if ($VDirParts.Count -gt 0) { '/' + ($VDirParts -join '/') } else { '/' }
                                $VDirCfg = try { $Mgr.GetWebConfiguration($Site.Name, $VDirVPath) } catch { $null }
                                $WebDirSec = if ($VDirCfg) { try { $VDirCfg.GetSection('system.webServer/directoryBrowse') } catch { $null } } else { $null }
                                $DirBrowsing = [bool](($DirSec -and $DirSec['enabled']) -or ($WebDirSec -and $WebDirSec['enabled']))
                                @{
                                    AppPath           = $App.Path
                                    VDirPath          = $VDir.Path
                                    PhysicalPath      = [System.Environment]::ExpandEnvironmentVariables($VDir.PhysicalPath)
                                    DirectoryBrowsing = $DirBrowsing
                                    Authentication    = $Auth
                                }
                            }
                        }
                        $RootPhysical = if ($Site.Applications['/'].VirtualDirectories['/']) {
                            [System.Environment]::ExpandEnvironmentVariables(
                                $Site.Applications['/'].VirtualDirectories['/'].PhysicalPath
                            )
                        }
                        else { '' }
                        $IndexHtml = ''
                        $IndexFilePath = ''
                        if ($RootPhysical) {
                            $IndexFilePath = [System.IO.Path]::Combine($RootPhysical, 'index.html')
                            if ([System.IO.File]::Exists($IndexFilePath)) {
                                $IndexHtml = [System.IO.File]::ReadAllText($IndexFilePath)
                            }
                        }
                        @{
                            Name               = $Site.Name
                            State              = "$($Site.State)"
                            Bindings           = @($Site.Bindings | ForEach-Object {
                                    @{ Protocol = $_.Protocol; BindingInformation = "$($_.BindingInformation)" }
                                })
                            VirtualDirectories = @($VDirs)
                            AppPoolName        = "$($Site.Applications['/'].ApplicationPoolName)"
                            IndexPath          = $IndexFilePath
                            IndexContent       = $IndexHtml
                        }
                    }
                    $Pools = foreach ($Pool in $Mgr.ApplicationPools) {
                        @{
                            Name           = $Pool.Name
                            State          = "$($Pool.State)"
                            PipelineMode   = "$($Pool.ManagedPipelineMode)"
                            RuntimeVersion = "$($Pool.ManagedRuntimeVersion)"
                        }
                    }
                    @{ Sites = @($Sites); AppPools = @($Pools) } | ConvertTo-Json -Depth 10
                }
                catch {
                    @{ Error = $_.Exception.Message } | ConvertTo-Json
                }
            }
        }
        catch {
            $Result.Reason = "PS 5.1 fallback failed: $($_.Exception.Message)"
            return $Result
        }
    }
    else {
        $Result.Reason = 'IISAdministration module not available and PS 5.1 not found'
        return $Result
    }
}

# ── Process results ──────────────────────────────────────────────────────────
try {
    if ($IisJson -eq '__PS7_DIRECT__') {
        # Direct PS 7 access
        $Mgr = Get-IISServerManager
        $HostConfig = $Mgr.GetApplicationHostConfiguration()
        foreach ($Site in $Mgr.Sites) {
            $Bindings = @($Site.Bindings | ForEach-Object {
                    @{
                        Protocol           = $_.Protocol
                        BindingInformation = "$($_.BindingInformation)"
                        Uri                = (ConvertTo-BindingUri -Protocol $_.Protocol -BindingInfo "$($_.BindingInformation)")
                    }
                })
            $VDirs = @(foreach ($App in $Site.Applications) {
                    foreach ($VDir in $App.VirtualDirectories) {
                        $AppRel = $App.Path.TrimStart('/')
                        $VDirRel = $VDir.Path.TrimStart('/')
                        $LocPath = $Site.Name
                        if ($AppRel) { $LocPath += "/$AppRel" }
                        if ($VDirRel) { $LocPath += "/$VDirRel" }
                        $AnonSec = try { $HostConfig.GetSection('system.webServer/security/authentication/anonymousAuthentication', $LocPath) } catch { $null }
                        $BasicSec = try { $HostConfig.GetSection('system.webServer/security/authentication/basicAuthentication', $LocPath) } catch { $null }
                        $WinSec = try { $HostConfig.GetSection('system.webServer/security/authentication/windowsAuthentication', $LocPath) } catch { $null }
                        $DirSec = try { $HostConfig.GetSection('system.webServer/directoryBrowse', $LocPath) } catch { $null }
                        $Auth = @(
                            @{ Method = 'Anonymous'; Enabled = [bool]($AnonSec -and $AnonSec['enabled']) }
                            @{ Method = 'Basic'; Enabled = [bool]($BasicSec -and $BasicSec['enabled']) }
                            @{ Method = 'Windows'; Enabled = [bool]($WinSec -and $WinSec['enabled']) }
                        )
                        $VDirParts = @($AppRel, $VDirRel) | Where-Object { $_ }
                        $VDirVPath = if ($VDirParts.Count -gt 0) { '/' + ($VDirParts -join '/') } else { '/' }
                        $VDirCfg = try { $Mgr.GetWebConfiguration($Site.Name, $VDirVPath) } catch { $null }
                        $WebDirSec = if ($VDirCfg) { try { $VDirCfg.GetSection('system.webServer/directoryBrowse') } catch { $null } } else { $null }
                        $DirBrowsing = [bool](($DirSec -and $DirSec['enabled']) -or ($WebDirSec -and $WebDirSec['enabled']))
                        @{
                            AppPath           = $App.Path
                            VDirPath          = $VDir.Path
                            PhysicalPath      = [System.Environment]::ExpandEnvironmentVariables($VDir.PhysicalPath)
                            DirectoryBrowsing = $DirBrowsing
                            Authentication    = $Auth
                        }
                    }
                })
            $RootApp = $Site.Applications['/']
            $RootVDir = if ($RootApp) { $RootApp.VirtualDirectories['/'] } else { $null }
            $RootPhysical = if ($RootVDir) {
                [System.Environment]::ExpandEnvironmentVariables($RootVDir.PhysicalPath)
            }
            else { '' }
            $IndexFilePath = ''
            $IndexContent = ''
            if ($RootPhysical) {
                $IndexFilePath = Join-Path $RootPhysical 'index.html'
                if (Test-Path $IndexFilePath) {
                    $IndexContent = Get-Content $IndexFilePath -Raw -ErrorAction SilentlyContinue
                }
            }
            $Result.Data.Websites += @{
                Name               = $Site.Name
                State              = "$($Site.State)"
                Bindings           = $Bindings
                VirtualDirectories = $VDirs
                AppPoolName        = "$($Site.Applications['/'].ApplicationPoolName)"
                IndexPath          = $IndexFilePath
                IndexContent       = $IndexContent
            }
        }
        foreach ($Pool in $Mgr.ApplicationPools) {
            $Result.Data.AppPools += @{
                Name           = $Pool.Name
                State          = "$($Pool.State)"
                PipelineMode   = "$($Pool.ManagedPipelineMode)"
                RuntimeVersion = "$($Pool.ManagedRuntimeVersion)"
            }
        }
    }
    else {
        # PS 5.1 fallback — parse JSON
        $Parsed = $IisJson | ConvertFrom-Json
        if ($Parsed.Error) {
            $Result.Reason = "IIS collection error: $($Parsed.Error)"
            return $Result
        }
        foreach ($Site in $Parsed.Sites) {
            $Bindings = @($Site.Bindings | ForEach-Object {
                    @{
                        Protocol           = $_.Protocol
                        BindingInformation = $_.BindingInformation
                        Uri                = (ConvertTo-BindingUri -Protocol $_.Protocol -BindingInfo $_.BindingInformation)
                    }
                })
            $VDirs = @($Site.VirtualDirectories | ForEach-Object {
                    @{
                        AppPath           = $_.AppPath
                        VDirPath          = $_.VDirPath
                        PhysicalPath      = $_.PhysicalPath
                        DirectoryBrowsing = [bool]$_.DirectoryBrowsing
                        Authentication    = @($_.Authentication | ForEach-Object {
                                @{ Method = $_.Method; Enabled = [bool]$_.Enabled }
                            })
                    }
                })
            $Result.Data.Websites += @{
                Name               = $Site.Name
                State              = "$($Site.State)"
                Bindings           = $Bindings
                VirtualDirectories = $VDirs
                AppPoolName        = "$($Site.AppPoolName)"
                IndexPath          = "$($Site.IndexPath)"
                IndexContent       = "$($Site.IndexContent)"
            }
        }
        foreach ($Pool in $Parsed.AppPools) {
            $Result.Data.AppPools += @{
                Name           = $Pool.Name
                State          = "$($Pool.State)"
                PipelineMode   = "$($Pool.PipelineMode)"
                RuntimeVersion = "$($Pool.RuntimeVersion)"
            }
        }
    }
    $Result.Available = $true
}
catch {
    $Result.Reason = "IIS data processing failed: $($_.Exception.Message)"
    $Result.Errors += $_.Exception.Message
    return $Result
}

# ── Collect curl / web request results ───────────────────────────────────────
if ($Variables.CurlTests) {
    foreach ($Test in $Variables.CurlTests) {
        try {
            $Response = Invoke-WebRequest -Uri $Test.Url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            $Result.Data.CurlResults += @{
                Url     = $Test.Url
                Content = $Response.Content
                Status  = [int]$Response.StatusCode
            }
        }
        catch {
            $Result.Data.CurlResults += @{
                Url     = $Test.Url
                Content = ''
                Status  = 0
                Error   = $_.Exception.Message
            }
        }
    }
}

return $Result
