# Collectors/Invoke-FileServerCollector.ps1
# Runs ON the remote VM. Returns structured file server data for evaluation.
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
        Shares      = @()
        Permissions = @()
        Folders     = @()
        Files       = @()
    }
    Errors    = @()
}

<#
.SYNOPSIS
    Converts a path string to a canonical lowercase form.
.DESCRIPTION
    Normalises forward slashes to backslashes, trims trailing separators,
    and lowercases the result for case-insensitive comparisons.
.PARAMETER Path
    The path string to canonicalise.
.OUTPUTS
    System.String
.EXAMPLE
    ConvertTo-CanonicalPath -Path 'C:/Shared/Folder/'
#>
function ConvertTo-CanonicalPath {
    [CmdletBinding()]
    param(
        [Parameter()][string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    return ($Path -replace '/', '\').TrimEnd('\').ToLowerInvariant()
}

<#
.SYNOPSIS
    Returns the relative path of a child path under a share root.
.DESCRIPTION
    Computes the portion of ChildPath that is relative to RootPath after
    canonicalising both. Returns '.' if they are equal or the child is empty.
.PARAMETER RootPath
    The share root path.
.PARAMETER ChildPath
    The full child path to make relative.
.OUTPUTS
    System.String
.EXAMPLE
    Get-RelativeSharePath -RootPath 'C:\Shared' -ChildPath 'C:\Shared\public'
#>
function Get-RelativeSharePath {
    [CmdletBinding()]
    param(
        [Parameter()][string] $RootPath,
        [Parameter()][string] $ChildPath
    )

    $CanonicalRoot = ConvertTo-CanonicalPath -Path $RootPath
    $CanonicalChild = ConvertTo-CanonicalPath -Path $ChildPath

    if ([string]::IsNullOrWhiteSpace($CanonicalChild)) {
        return '.'
    }

    if ($CanonicalChild -eq $CanonicalRoot) {
        return '.'
    }

    if ($CanonicalChild.StartsWith("$CanonicalRoot\")) {
        return $CanonicalChild.Substring($CanonicalRoot.Length + 1)
    }

    return $CanonicalChild
}

# ── Check File Services role ──────────────────────────────────────────────────
try {
    $FsFeature = Get-WindowsFeature -Name FS-FileServer -ErrorAction Stop
}
catch {
    $Result.Reason = "Cannot query File Server feature: $($_.Exception.Message)"
    return $Result
}

if (-not $FsFeature.Installed) {
    $Result.Reason = 'File Server role not installed'
    return $Result
}
$Result.Available = $true

# ── Collect SMB shares ────────────────────────────────────────────────────────
try {
    $RawShares = Get-SmbShare -ErrorAction Stop | Where-Object {
        $_.Name -notmatch '^(ADMIN|C|IPC|NETLOGON|SYSVOL|print)\$'
    }
    $Result.Data.Shares = @($RawShares | ForEach-Object {
            $ShareName = $_.Name
            $SharePath = $_.Path

            # Collect share-level permissions
            $ShareAccess = @()
            try {
                $RawAccess = Get-SmbShareAccess -Name $ShareName -ErrorAction Stop
                $ShareAccess = @($RawAccess | ForEach-Object {
                        @{
                            AccountName = $_.AccountName
                            AccessRight = $_.AccessControlType.ToString() + ':' + $_.AccessRight.ToString()
                        }
                    })
            }
            catch {
                $Result.Errors += "Share '$ShareName' access: $($_.Exception.Message)"
            }

            @{
                Name        = $ShareName
                Path        = $SharePath
                Description = $_.Description
                ShareAccess = $ShareAccess
            }
        })
}
catch {
    $Result.Errors += "SMB share enumeration failed: $($_.Exception.Message)"
}

# ── Collect NTFS permissions for share paths ──────────────────────────────────
foreach ($Share in $Result.Data.Shares) {
    if (-not $Share.Path -or -not (Test-Path $Share.Path -ErrorAction SilentlyContinue)) {
        continue
    }

    $ShareRootPath = $Share.Path.TrimEnd('\\')
    $DirectoryPaths = @($ShareRootPath)

    try {
        $ChildDirectories = Get-ChildItem -Path $ShareRootPath -Recurse -ErrorAction Stop |
            Where-Object { $_.PSIsContainer } |
            Select-Object -ExpandProperty FullName
        $DirectoryPaths += @($ChildDirectories)
    }
    catch {
        $Result.Errors += "Directory inventory for '$($Share.Path)': $($_.Exception.Message)"
    }

    foreach ($DirectoryPath in $DirectoryPaths) {
        $RelativePath = Get-RelativeSharePath -RootPath $ShareRootPath -ChildPath $DirectoryPath

        $Result.Data.Folders += @{
            ShareName    = $Share.Name
            Path         = $DirectoryPath
            RelativePath = $RelativePath
        }

        try {
            $Acl = Get-Acl -Path $DirectoryPath -ErrorAction Stop
            $NtfsPerms = @($Acl.Access | ForEach-Object {
                    @{
                        IdentityReference = $_.IdentityReference.ToString()
                        FileSystemRights  = $_.FileSystemRights.ToString()
                        AccessControlType = $_.AccessControlType.ToString()
                        IsInherited       = $_.IsInherited
                        InheritanceFlags  = $_.InheritanceFlags.ToString()
                        PropagationFlags  = $_.PropagationFlags.ToString()
                    }
                })

            $Result.Data.Permissions += @{
                Path         = $DirectoryPath
                RelativePath = $RelativePath
                ShareName    = $Share.Name
                Owner        = $Acl.Owner
                Permissions  = $NtfsPerms
            }
        }
        catch {
            $Result.Errors += "NTFS ACL for '$DirectoryPath': $($_.Exception.Message)"
        }
    }

    try {
        $ShareFiles = Get-ChildItem -Path $ShareRootPath -Recurse -ErrorAction Stop |
            Where-Object { -not $_.PSIsContainer }
        $Result.Data.Files += @($ShareFiles | ForEach-Object {
                $FileRelativePath = Get-RelativeSharePath -RootPath $ShareRootPath -ChildPath $_.FullName
                @{
                    ShareName    = $Share.Name
                    Name         = $_.Name
                    Extension    = $_.Extension
                    Path         = $_.FullName
                    RelativePath = $FileRelativePath
                }
            })
    }
    catch {
        $Result.Errors += "File inventory for '$($Share.Path)': $($_.Exception.Message)"
    }
}

return $Result
