# Collectors/Invoke-GpoCollector.ps1
# Runs ON the remote VM. Returns structured GPO data for evaluation.
# All output is plain hashtables/strings — safe for CLIXML deserialization.
# Requires GroupPolicy module (RSAT) and AD-Domain-Services role.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables',
    Justification = 'Reserved for future use; collector behaviour is data-independent.')]
param(
    [Parameter()][hashtable] $Variables = @{}
)

$Result = @{
    Available = $false
    Reason    = $null
    Data      = @{
        DomainName = $null
        Gpos       = @()
    }
    Errors    = @()
}

# ── Check domain membership ───────────────────────────────────────────────────
try {
    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
}
catch {
    $Result.Reason = "Cannot query WMI: $($_.Exception.Message)"
    return $Result
}

if (-not $ComputerSystem.PartOfDomain) {
    $Result.Reason = 'Machine is not part of a domain'
    return $Result
}

# ── Import GroupPolicy module ─────────────────────────────────────────────────
try {
    Import-Module GroupPolicy -SkipEditionCheck -ErrorAction Stop
}
catch {
    $Result.Reason = "GroupPolicy module unavailable: $($_.Exception.Message)"
    return $Result
}
$Result.Available = $true

# ── Get domain name ───────────────────────────────────────────────────────────
try {
    $AdDomain = (Get-ADDomain -ErrorAction Stop).DNSRoot
    $Result.Data.DomainName = $AdDomain
}
catch {
    $Result.Errors += "AD Domain query failed: $($_.Exception.Message)"
    $AdDomain = $ComputerSystem.Domain
    $Result.Data.DomainName = $AdDomain
}

# ── Action codes used in GPO preferences ─────────────────────────────────────
$Actions = @{
    'C' = 'Create'
    'R' = 'Replace'
    'U' = 'Update'
    'D' = 'Delete'
}

<#
.SYNOPSIS
    Returns the first UNC path found in a string.
.DESCRIPTION
    Extracts the first UNC path pattern from the given string using regex.
.PARAMETER Text
    The string to search for a UNC path.
.OUTPUTS
    System.String
.EXAMPLE
    Get-UncPathFromText -Text '\\dc1\shared\file.txt'
#>
function Get-UncPathFromText {
    [CmdletBinding()]
    param(
        [Parameter()][string] $Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $Match = [regex]::Match($Text, '\\\\[^\\\s"''<>]+\\[^"''<>\r\n]+')
    if ($Match.Success) {
        return $Match.Value
    }

    return $null
}

<#
.SYNOPSIS
    Returns all UNC paths found in a string.
.DESCRIPTION
    Extracts every UNC path pattern from the given string using regex.
.PARAMETER Text
    The string to search for UNC paths.
.OUTPUTS
    System.String[]
.EXAMPLE
    Get-UncPathMatch -Text '\\dc1\shared\a.msi \\dc1\shared\b.msi'
#>
function Get-UncPathMatch {
    [CmdletBinding()]
    param(
        [Parameter()][string] $Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $PathMatches = [regex]::Matches($Text, '\\\\[^\\\s"''<>]+\\[^"''<>\r\n]+')
    return @($PathMatches | ForEach-Object { $_.Value })
}

<#
.SYNOPSIS
    Returns the configured UNC path from a GPO policy XML node.
.DESCRIPTION
    Parses the policy XML to extract a configured UNC path value from EditText
    nodes, falling back to a text-based regex search when XML parsing fails.
.PARAMETER Policy
    The GPO policy XML node to inspect.
.OUTPUTS
    System.String
.EXAMPLE
    Get-ConfiguredPolicyPath -Policy $PolicyNode
#>
function Get-ConfiguredPolicyPath {
    [CmdletBinding()]
    param(
        [Parameter()] $Policy
    )

    if (-not $Policy) {
        return $null
    }

    try {
        [xml] $PolicyXml = $Policy.OuterXml
        $ValueNodes = $PolicyXml.SelectNodes("//*[local-name()='EditText']/*[local-name()='Value']")
        foreach ($Node in @($ValueNodes)) {
            $Candidate = [string]$Node.InnerText
            if ($Candidate -match '^\\\\' -and $Candidate -notmatch '^\\\\Server\\Share\\') {
                return $Candidate
            }
        }
    }
    catch {
        $Result.Errors += "Policy path XML parse fallback for policy '$($Policy.Name)': $($_.Exception.Message)"
    }

    $Candidates = Get-UncPathMatch -Text "$($Policy.InnerText) $($Policy.OuterXml)"
    $Preferred = @($Candidates | Where-Object { $_ -notmatch '^\\\\Server\\Share\\' })
    if ($Preferred.Count -gt 0) {
        return $Preferred[0]
    }

    if ($Candidates.Count -gt 0) {
        return $Candidates[0]
    }

    return $null
}

<#
.SYNOPSIS
    Tests whether a UNC path exists on the remote system.
.DESCRIPTION
    Validates that the string is a UNC path and that the target path is accessible.
.PARAMETER Path
    The UNC path to test.
.OUTPUTS
    System.Boolean
.EXAMPLE
    Test-UncPath -Path '\\dc1\shared\public'
#>
function Test-UncPath {
    [CmdletBinding()]
    param(
        [Parameter()][string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if ($Path -notmatch '^\\\\') {
        return $false
    }

    return (Test-Path -Path $Path -ErrorAction SilentlyContinue)
}

# ── Collect all GPOs ──────────────────────────────────────────────────────────
try {
    $AllGpos = Get-GPO -Domain $AdDomain -All -ErrorAction Stop |
        Where-Object { $_.DisplayName -notin 'Default Domain Controllers Policy', 'Default Domain Policy' }
}
catch {
    $Result.Errors += "GPO enumeration failed: $($_.Exception.Message)"
    return $Result
}

foreach ($Gpo in $AllGpos) {
    try {
        [xml]$GpoReport = Get-GPOReport -Guid $Gpo.Id -ReportType Xml -ErrorAction Stop

        $GpoEntry = @{
            Name          = $Gpo.DisplayName
            Links         = @()
            Description   = $Gpo.Description
            Status        = $Gpo.GpoStatus.ToString()
            ComputerScope = @()
            UserScope     = @()
        }

        # ── Links ─────────────────────────────────────────────────────────────
        if ($GpoReport.gpo.LinksTo) {
            $LinkItems = @($GpoReport.gpo.LinksTo)
            foreach ($Link in $LinkItems) {
                $GpoEntry.Links += @{
                    SOMPath = $Link.SOMPath
                    Enabled = $Link.Enabled
                }
            }
        }

        # ── Permissions ───────────────────────────────────────────────────────
        try {
            $GpoPermissions = Get-GPPermission -Guid $Gpo.Id -All -ErrorAction Stop
            $GpoEntry['Permissions'] = @($GpoPermissions | ForEach-Object {
                    @{
                        Trustee     = $_.Trustee.Name
                        TrusteeType = $_.Trustee.SidType.ToString()
                        Permission  = $_.Permission.ToString()
                    }
                })
        }
        catch {
            $GpoEntry['Permissions'] = @()
            $Result.Errors += "Permissions for GPO '$($Gpo.DisplayName)': $($_.Exception.Message)"
        }

        # ── Scope parsing (Computer + User) ───────────────────────────────────
        foreach ($ScopeName in @('Computer', 'User')) {
            $ScopeKey = "${ScopeName}Scope"
            $ExtensionData = $GpoReport.gpo.$ScopeName.extensionData

            if (-not $ExtensionData) {
                $GpoEntry.$ScopeKey = @(@{ Type = 'NoSettings'; Settings = 'no settings' })
                continue
            }

            foreach ($ExtItem in @($ExtensionData)) {
                $ExtName = $ExtItem.Name

                # Software Installation
                if ($ExtName -eq 'Software Installation') {
                    foreach ($App in @($ExtItem.Extension.msiApplication)) {
                        $GpoEntry.$ScopeKey += @{
                            Type     = 'SoftwareInstallation'
                            Settings = @{
                                Name           = $App.Name
                                Path           = $App.Path
                                PathExists     = (Test-UncPath -Path $App.Path)
                                DeploymentType = $App.DeploymentType
                            }
                        }
                    }
                }
                # Scripts
                elseif ($ExtName -eq 'Scripts') {
                    foreach ($Script in @($ExtItem.Extension.Script)) {
                        $GpoEntry.$ScopeKey += @{
                            Type     = 'Script'
                            Settings = @{
                                Command    = $Script.Command
                                Parameters = $Script.Parameters
                                ScriptType = $Script.Type
                            }
                        }
                    }
                }
                # Folder Redirection
                elseif ($ExtName -eq 'Folder Redirection') {
                    foreach ($Redir in @($ExtItem.Extension.Folder)) {
                        $GpoEntry.$ScopeKey += @{
                            Type     = 'FolderRedirection'
                            Settings = @{
                                FolderId        = $Redir.Id
                                DestinationPath = $Redir.Location.DestinationPath
                            }
                        }
                    }
                }
                # Drive Maps
                elseif ($ExtName -eq 'Drive Maps') {
                    foreach ($Drive in @($ExtItem.Extension.DriveMapSettings.Drive)) {
                        $DrivePath = $Drive.Properties.path
                        $GpoEntry.$ScopeKey += @{
                            Type     = 'DriveMap'
                            Settings = @{
                                Name       = $Drive.Name
                                Path       = $DrivePath
                                PathExists = (Test-UncPath -Path $DrivePath)
                                Letter     = "$($Drive.Properties.letter):"
                                Label      = $Drive.Properties.label
                                Action     = $Actions[$Drive.Properties.action]
                            }
                        }
                    }
                }
                # Local Users and Groups
                elseif ($ExtName -eq 'Local Users and Groups') {
                    $LocalUsers = $ExtItem.Extension.LocalUsersAndGroups.User
                    $LocalGroups = $ExtItem.Extension.LocalUsersAndGroups.group

                    if ($LocalUsers) {
                        foreach ($Lu in @($LocalUsers)) {
                            $GpoEntry.$ScopeKey += @{
                                Type     = 'LocalUser'
                                Settings = @{
                                    Name            = $Lu.name
                                    NewName         = $Lu.Properties.newName
                                    FullName        = $Lu.Properties.fullName
                                    Description     = $Lu.Properties.Description
                                    AccountDisabled = $Lu.Properties.acctDisabled
                                    Action          = $Actions[$Lu.Properties.action]
                                }
                            }
                        }
                    }

                    if ($LocalGroups) {
                        foreach ($Lg in @($LocalGroups)) {
                            $Members = @()
                            if ($Lg.Properties.Members.Member) {
                                $Members = @($Lg.Properties.Members.Member | ForEach-Object { $_.name })
                            }
                            $GpoEntry.$ScopeKey += @{
                                Type     = 'LocalGroup'
                                Settings = @{
                                    Name           = $Lg.name
                                    NewName        = $Lg.Properties.newName
                                    Description    = $Lg.Properties.Description
                                    Members        = $Members
                                    DeleteAllUsers = $Lg.Properties.deleteAllUsers
                                    Action         = $Actions[$Lg.Properties.action]
                                }
                            }
                        }
                    }
                }
                # Administrative Templates / Registry Policies
                else {
                    foreach ($Policy in @($ExtItem.Extension.Policy)) {
                        $PolicyRawXml = $Policy.OuterXml
                        $PolicyPath = Get-ConfiguredPolicyPath -Policy $Policy
                        $GpoEntry.$ScopeKey += @{
                            Type     = 'Policy'
                            Settings = @{
                                Name       = $Policy.Name
                                Category   = $Policy.Category
                                State      = $Policy.State
                                Path       = $PolicyPath
                                PathExists = (Test-UncPath -Path $PolicyPath)
                                RawXml     = $PolicyRawXml
                            }
                        }
                    }
                }
            }
        }

        $Result.Data.Gpos += $GpoEntry
    }
    catch {
        $Result.Errors += "GPO '$($Gpo.DisplayName)': $($_.Exception.Message)"
    }
}

return $Result
