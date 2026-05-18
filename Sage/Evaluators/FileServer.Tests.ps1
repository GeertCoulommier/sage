# Evaluations/FileServer.Tests.ps1
# File Server evaluation — tests driven entirely by exam data.
# Contains ONLY assertion logic — no expected values hardcoded.
# Data from exam.psd1 via $ExamVariables; collected data via $CollectedData.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExamVariables',
    Justification = 'Injected by the evaluation framework; consumed by Pester test blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CollectedData',
    Justification = 'Injected by the evaluation framework; consumed by Pester test blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ReviewContextMap',
    Justification = 'Consumed by ConvertTo-GradeSummary via Get-Variable after dot-sourcing this file.')]
param(
    [Parameter(Mandatory)][hashtable] $ExamVariables,
    [Parameter(Mandatory)][hashtable] $CollectedData
)

# ── Review Context Map (for Edit-Grade) ──────────────────────────────────────
$ReviewContextMap = @{
    'SMB Shares'       = {
        param($Data)
        $Data.Shares | ForEach-Object {
            [PSCustomObject]@{
                Name        = $_.Name
                Path        = $_.Path
                Description = $_.Description
            }
        }
    }
    'NTFS Permissions' = {
        param($Data)
        $Data.Permissions | ForEach-Object {
            $Entry = $_
            $Entry.Permissions | ForEach-Object {
                [PSCustomObject]@{
                    ShareName         = $Entry.ShareName
                    Path              = $Entry.Path
                    IdentityReference = $_.IdentityReference
                    FileSystemRights  = $_.FileSystemRights
                    AccessControlType = $_.AccessControlType
                    IsInherited       = $_.IsInherited
                }
            }
        }
    }
    'Share Access'     = {
        param($Data)
        $Data.Shares | ForEach-Object {
            $Share = $_
            $Share.ShareAccess | ForEach-Object {
                [PSCustomObject]@{
                    ShareName   = $Share.Name
                    AccountName = $_.AccountName
                    AccessRight = $_.AccessRight
                }
            }
        }
    }
}

Describe 'File Server Configuration' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.ShareTests) { $V.ShareTests = @() }
        if (-not $V.NtfsTests) { $V.NtfsTests = @() }
        if (-not $V.ShareAccessTests) { $V.ShareAccessTests = @() }
        if (-not $V.FolderTests) { $V.FolderTests = @() }
        if (-not $V.FileTests) { $V.FileTests = @() }
    }

    Context 'SMB Shares' {
        It 'Share <ShareName> should exist' -ForEach $V.ShareTests {
            $MatchingShare = $CollectedData.Shares | Where-Object {
                $_.Name -ieq $ShareName
            }
            $MatchingShare | Should -Not -BeNullOrEmpty
        }

        It 'Share <ShareName> should have path <ExpectedPath>' -ForEach ($V.ShareTests | Where-Object { $_.ExpectedPath }) {
            $MatchingShare = $CollectedData.Shares | Where-Object {
                $_.Name -ieq $ShareName
            }
            $MatchingShare | Should -Not -BeNullOrEmpty

            $ActualPath = (($MatchingShare.Path -replace '[\\/]+', '\').TrimEnd('\\')).ToLowerInvariant()
            $ExpectedPathNormalized = (($ExpectedPath -replace '[\\/]+', '\').TrimEnd('\\')).ToLowerInvariant()
            $ActualPath | Should -Be $ExpectedPathNormalized
        }
    }

    Context 'NTFS Permissions' {
        It 'Path for share <ShareName> should grant <ExpectedIdentity> <ExpectedRights>' -ForEach $V.NtfsTests {
            $PermEntries = $CollectedData.Permissions | Where-Object {
                $_.ShareName -ieq $ShareName
            }

            if ($RelativePath) {
                $ExpectedRelativePath = (($RelativePath -replace '[\\/]+', '\').Trim('\\')).ToLowerInvariant()
                $PermEntries = $PermEntries | Where-Object {
                    $CurrentRelativePath = if ($_.RelativePath -eq '.') {
                        '.'
                    }
                    else {
                        (($_.RelativePath -replace '[\\/]+', '\').Trim('\\')).ToLowerInvariant()
                    }
                    $CurrentRelativePath -eq $ExpectedRelativePath
                }
            }

            $PermEntries | Should -Not -BeNullOrEmpty

            $MatchingAce = if ($AnyOfExpectedIdentities) {
                $PermEntries.Permissions | Where-Object {
                    $Ace = $_
                    $IdentityMatch = @($AnyOfExpectedIdentities) | Where-Object {
                        $Ace.IdentityReference -ilike "*$_*"
                    }
                    $Ace.FileSystemRights -match [regex]::Escape($ExpectedRights) -and
                    $Ace.AccessControlType -eq 'Allow' -and
                    $IdentityMatch
                }
            }
            else {
                $PermEntries.Permissions | Where-Object {
                    $_.IdentityReference -ilike "*$ExpectedIdentity*" -and
                    $_.FileSystemRights -match [regex]::Escape($ExpectedRights) -and
                    $_.AccessControlType -eq 'Allow'
                }
            }
            $MatchingAce | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Folder Structure' {
        It 'Share <ShareName> should contain folder <RelativePath>' -ForEach $V.FolderTests {
            $ExpectedRelativePath = (($RelativePath -replace '[\\/]+', '\').Trim('\\')).ToLowerInvariant()
            $MatchingFolder = $CollectedData.Folders | Where-Object {
                $_.ShareName -ieq $ShareName -and
                (($_.RelativePath -replace '[\\/]+', '\').Trim('\\').ToLowerInvariant()) -eq $ExpectedRelativePath
            }
            $MatchingFolder | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Files' {
        It 'Share <ShareName> should contain required files in <RelativePath>' -ForEach $V.FileTests {
            $MatchingFiles = $CollectedData.Files | Where-Object {
                $_.ShareName -ieq $ShareName
            }

            if ($RelativePath) {
                $ExpectedRelativePath = (($RelativePath -replace '[\\/]+', '\').Trim('\\')).ToLowerInvariant()
                $MatchingFiles = $MatchingFiles | Where-Object {
                    $CurrentRelativePath = (($_.RelativePath -replace '[\\/]+', '\').Trim('\\').ToLowerInvariant())
                    $CurrentRelativePath -eq $ExpectedRelativePath -or
                    $CurrentRelativePath.StartsWith("$ExpectedRelativePath\")
                }
            }

            if ($ExpectedPattern) {
                $MatchingFiles = $MatchingFiles | Where-Object {
                    $_.Name -match $ExpectedPattern -or $_.RelativePath -match $ExpectedPattern
                }
            }

            if ($ExpectedExtensions) {
                $Extensions = @($ExpectedExtensions) | ForEach-Object { $_.ToLowerInvariant() }
                $MatchingFiles = $MatchingFiles | Where-Object {
                    $_.Extension.ToLowerInvariant() -in $Extensions
                }
            }

            $MatchingFiles | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Share Access' {
        It 'Share <ShareName> should grant <ExpectedAccount> <ExpectedAccess>' -ForEach $V.ShareAccessTests {
            $MatchingShare = $CollectedData.Shares | Where-Object {
                $_.Name -ieq $ShareName
            }
            $MatchingShare | Should -Not -BeNullOrEmpty
            $MatchingAccess = $MatchingShare.ShareAccess | Where-Object {
                $_.AccountName -ilike "*$ExpectedAccount*" -and
                $_.AccessRight -match [regex]::Escape($ExpectedAccess)
            }
            $MatchingAccess | Should -Not -BeNullOrEmpty
        }
    }
}
