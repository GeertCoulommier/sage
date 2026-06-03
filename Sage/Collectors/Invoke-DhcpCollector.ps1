# Collectors/Invoke-DhcpCollector.ps1
# Runs ON the remote VM. Returns structured DHCP data for evaluation.
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
        RoleInstalled = $false
        IsAuthorized  = $false
        DomainName    = $null
        Filters       = @{
            AllowEnabled = $false
            DenyEnabled  = $false
        }
        Scopes        = @()
    }
    Errors    = @()
}

# ── Check DHCP role availability ──────────────────────────────────────────────
try {
    $DhcpFeature = Get-WindowsFeature -Name DHCP -ErrorAction Stop
}
catch {
    $Result.Reason = "Cannot query DHCP feature: $($_.Exception.Message)"
    return $Result
}

if (-not $DhcpFeature.Installed) {
    $Result.Available = $true
    $Result.Reason = 'DHCP Server role not installed'
    return $Result
}
$Result.Data.RoleInstalled = $true
$Result.Available = $true

# ── Server authorization ──────────────────────────────────────────────────────
try {
    $ServerSetting = Get-DhcpServerSetting -ErrorAction Stop
    $Result.Data.IsAuthorized = [bool]$ServerSetting.IsAuthorized
}
catch {
    $Result.Errors += "DHCP server setting query failed: $($_.Exception.Message)"
}

# ── Domain name (for dynamic DHCP option assertions) ─────────────────────────
try {
    $SystemInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $Result.Data.DomainName = $SystemInfo.Domain
}
catch {
    $Result.Errors += "DHCP domain query failed: $($_.Exception.Message)"
}

# ── Allow/Deny filter state ───────────────────────────────────────────────────
try {
    $FilterList = @(Get-DhcpServerv4FilterList -ErrorAction Stop)
    foreach ($FilterEntry in $FilterList) {
        $ListName = if ($FilterEntry.PSObject.Properties.Name -contains 'List') {
            $FilterEntry.List
        }
        elseif ($FilterEntry.PSObject.Properties.Name -contains 'ListType') {
            $FilterEntry.ListType
        }
        else {
            $null
        }

        $IsEnabled = if ($FilterEntry.PSObject.Properties.Name -contains 'Enabled') {
            [bool]$FilterEntry.Enabled
        }
        elseif ($FilterEntry.PSObject.Properties.Name -contains 'IsEnabled') {
            [bool]$FilterEntry.IsEnabled
        }
        else {
            $false
        }

        switch ($ListName) {
            'Allow' {
                $Result.Data.Filters.AllowEnabled = $IsEnabled
            }
            'Deny' {
                $Result.Data.Filters.DenyEnabled = $IsEnabled
            }
        }
    }
}
catch {
    $Result.Errors += "DHCP filter list query failed: $($_.Exception.Message)"
}

# ── Scopes ────────────────────────────────────────────────────────────────────
try {
    $RawScopes = Get-DhcpServerv4Scope -ErrorAction Stop
    foreach ($Scope in $RawScopes) {
        $ScopeEntry = @{
            ScopeId           = $Scope.ScopeId.ToString()
            Name              = $Scope.Name
            StartRange        = $Scope.StartRange.ToString()
            EndRange          = $Scope.EndRange.ToString()
            SubnetMask        = $Scope.SubnetMask.ToString()
            State             = $Scope.State.ToString()
            LeaseDuration     = if ($Scope.LeaseDuration) { $Scope.LeaseDuration.ToString() } else { $null }
            LeaseDurationDays = if ($Scope.LeaseDuration) { [int][math]::Round($Scope.LeaseDuration.TotalDays) } else { $null }
            Exclusions        = @()
            Options           = @()
            Reservations      = @()
        }

        # Exclusion ranges
        try {
            $Exclusions = Get-DhcpServerv4ExclusionRange -ScopeId $Scope.ScopeId -ErrorAction Stop
            $ScopeEntry.Exclusions = @($Exclusions | ForEach-Object {
                    @{
                        StartRange = $_.StartRange.ToString()
                        EndRange   = $_.EndRange.ToString()
                    }
                })
        }
        catch {
            $Result.Errors += "Scope '$($Scope.ScopeId)' exclusions: $($_.Exception.Message)"
        }

        # Scope options
        try {
            $Options = Get-DhcpServerv4OptionValue -ScopeId $Scope.ScopeId -ErrorAction Stop
            $ScopeEntry.Options = @($Options | ForEach-Object {
                    @{
                        OptionId = $_.OptionId
                        Name     = $_.Name
                        Value    = @($_.Value | ForEach-Object { $_.ToString() })
                    }
                })
        }
        catch {
            $Result.Errors += "Scope '$($Scope.ScopeId)' options: $($_.Exception.Message)"
        }

        # Reservations
        try {
            $Reservations = Get-DhcpServerv4Reservation -ScopeId $Scope.ScopeId -ErrorAction Stop
            $ScopeEntry.Reservations = @($Reservations | ForEach-Object {
                    @{
                        IPAddress = $_.IPAddress.ToString()
                        Name      = $_.Name
                        ClientId  = $_.ClientId
                    }
                })
        }
        catch {
            $Result.Errors += "Scope '$($Scope.ScopeId)' reservations: $($_.Exception.Message)"
        }

        $Result.Data.Scopes += $ScopeEntry
    }
}
catch {
    $Result.Errors += "DHCP scope enumeration failed: $($_.Exception.Message)"
}

return $Result
