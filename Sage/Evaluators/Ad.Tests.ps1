# Evaluations/Ad.Tests.ps1
# Active Directory evaluation — tests driven entirely by exam data.
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
    'Domain and Forest'    = {
        param($Data)
        [PSCustomObject]@{
            DomainName            = $Data.DomainName
            DomainFunctionalLevel = $Data.DomainFunctionalLevel
            ForestFunctionalLevel = $Data.ForestFunctionalLevel
            PartOfDomain          = $Data.PartOfDomain
        }
    }
    'Computers'            = {
        param($Data)
        $Data.Computers | ForEach-Object {
            [PSCustomObject]@{
                Name              = $_.Name
                DNSHostName       = $_.DNSHostName
                DistinguishedName = $_.DistinguishedName
            }
        }
    }
    'Organizational Units' = {
        param($Data)
        $Data.OUs | ForEach-Object {
            [PSCustomObject]@{
                Name              = $_.Name
                DistinguishedName = $_.DistinguishedName
            }
        }
    }
    'Users'                = {
        param($Data)
        $Data.Users | ForEach-Object {
            [PSCustomObject]@{
                GivenName      = $_.GivenName
                Surname        = $_.Surname
                SamAccountName = $_.SamAccountName
                Name           = $_.Name
            }
        }
    }
    'Group Membership'     = {
        param($Data)
        $Data.Groups | ForEach-Object {
            [PSCustomObject]@{
                Name       = $_.Name
                GroupScope = $_.GroupScope
                Members    = ($_.Members -join ', ')
            }
        }
    }
    'Sites'                = {
        param($Data)
        $Data.Sites | ForEach-Object {
            [PSCustomObject]@{
                Name              = $_.Name
                DistinguishedName = $_.DistinguishedName
            }
        }
    }
    'Subnets'              = {
        param($Data)
        $Data.Subnets | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.Name
                SiteName = $_.SiteName
            }
        }
    }
    'Site Links'           = {
        param($Data)
        $Data.SiteLinks | ForEach-Object {
            [PSCustomObject]@{
                Name                          = $_.Name
                Cost                          = $_.Cost
                ReplicationFrequencyInMinutes = $_.ReplicationFrequencyInMinutes
                SiteNames                     = ($_.SiteNames -join ', ')
            }
        }
    }
    'Domain Controllers'   = {
        param($Data)
        $Data.DomainControllers | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Site = $_.Site
            }
        }
    }
}

Describe 'Active Directory Configuration' -Tag 'Evaluation' {

    BeforeAll {
        <#
        .SYNOPSIS
            Normalises an AD group or NTFS identity name for convention-tolerant matching.
        .DESCRIPTION
            Strips optional well-known group-type prefixes (DL, DLG, L, SEC_DL, GG, G,
            Role, SEC_G, UG, U, Univ, SEC_U) and normalises all underscore separators to
            hyphens.  The domain portion of an IdentityReference (e.g. DOMAIN\Name) is
            discarded before processing.  Permission suffixes (-R, -FC, etc.) are left
            intact.  The Write variants -RW and -Modify are both normalised to -W so that
            DL_Opleidingen_RW and DL_Opleidingen_Modify both resolve to Opleidingen-W and
            match exam definitions that use the canonical -W suffix.
            Supported prefixes and separators (both - and _ accepted everywhere):
              Domain Local : D, DL, DLG, L, SEC_DL, SEC-DL
              Global       : GG, G, Role, SEC_G, SEC-G
              Universal    : UG, U, Univ, SEC_U, SEC-U
        .PARAMETER Name
            The raw group name or IdentityReference to normalise.
        .OUTPUTS
            [string] The normalised name, ready for case-insensitive equality comparison.
        .EXAMPLE
            Resolve-AdGroupName 'DL_Opleidingen_R'
            # Returns 'Opleidingen-R'
        .EXAMPLE
            Resolve-AdGroupName 'DL_Opleidingen_RW'
            # Returns 'Opleidingen-W'
        .EXAMPLE
            Resolve-AdGroupName 'GG_HR'
            # Returns 'HR'
        .EXAMPLE
            Resolve-AdGroupName 'PROEF\DL-Opleidingen-FC'
            # Returns 'Opleidingen-FC'
        #>
        function Resolve-AdGroupName {
            [CmdletBinding()]
            [OutputType([string])]
            param(
                [Parameter(Mandatory)][AllowEmptyString()] [string] $Name
            )
            $LocalName = if ($Name -match '\\(.+)$') { $Matches[1] } else { $Name }
            $Stripped = $LocalName -replace '(?i)^(?:SEC[-_]DL|SEC[-_]G|SEC[-_]U|DLG|DL|D|GG|UG|Univ|Role|L|G|U)[-_]', ''
            $Normalized = $Stripped -replace '_', '-'
            # Normalise Write-permission suffix variants: -RW and -Modify → -W
            return $Normalized -replace '(?i)-(?:RW|Modify)$', '-W'
        }
    }

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.DomainTests) { $V.DomainTests = @() }
        if (-not $V.ComputerTests) { $V.ComputerTests = @() }
        if (-not $V.OUTests) { $V.OUTests = @() }
        if (-not $V.UserTests) { $V.UserTests = @() }
        if (-not $V.GroupMembershipTests) { $V.GroupMembershipTests = @() }
        if (-not $V.SiteTests) { $V.SiteTests = @() }
        if (-not $V.SubnetTests) { $V.SubnetTests = @() }
        if (-not $V.SiteLinkExistenceTests) { $V.SiteLinkExistenceTests = @() }
        if (-not $V.SiteLinkCostTests) { $V.SiteLinkCostTests = @() }
        if (-not $V.SiteLinkReplIntervalTests) { $V.SiteLinkReplIntervalTests = @() }
        if (-not $V.SiteLinkScheduleTests) { $V.SiteLinkScheduleTests = @() }
        if (-not $V.DcSiteTests) { $V.DcSiteTests = @() }
        if (-not $V.DomainNameTests) { $V.DomainNameTests = @() }
        if (-not $V.GroupExistenceTests) { $V.GroupExistenceTests = @() }
        if (-not $V.GroupInGroupTests) { $V.GroupInGroupTests = @() }
        if (-not $V.GroupHasMembersTests) { $V.GroupHasMembersTests = @() }
    }

    Context 'Domain and Forest' {
        It 'Domain functional level should be <ExpectedDomainLevel>' -ForEach $V.DomainTests {
            $CollectedData.DomainFunctionalLevel | Should -Be $ExpectedDomainLevel
        }

        It 'Forest functional level should be <ExpectedForestLevel>' -ForEach ($V.DomainTests | Where-Object { $_.ExpectedForestLevel }) {
            $CollectedData.ForestFunctionalLevel | Should -Be $ExpectedForestLevel
        }
    }

    Context 'Computers' {
        It 'Computer <Name> should be a domain member' -ForEach $V.ComputerTests {
            $MatchingComputer = $CollectedData.Computers | Where-Object {
                $_.Name -eq $Name
            }
            $MatchingComputer | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Organizational Units' {
        It 'OU <Name> should exist at <ExpectedDN>' -ForEach ($V.OUTests | Where-Object { $_.ExpectedDN }) {
            $MatchingOU = $CollectedData.OUs | Where-Object {
                $_.DistinguishedName -eq $ExpectedDN
            }
            $MatchingOU | Should -Not -BeNullOrEmpty
        }

        It 'OU <Name> should exist' -ForEach ($V.OUTests | Where-Object { -not $_.ExpectedDN }) {
            $MatchingOU = $CollectedData.OUs | Where-Object {
                $_.Name -eq $Name
            }
            $MatchingOU | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Users' {
        It 'User <SamAccountName> should exist with GivenName <GivenName>' -ForEach ($V.UserTests | Where-Object { $_.GivenName }) {
            $MatchingUser = $CollectedData.Users | Where-Object {
                $_.SamAccountName -eq $SamAccountName -and
                $_.GivenName -eq $GivenName
            }
            $MatchingUser | Should -Not -BeNullOrEmpty
        }

        It 'User <SamAccountName> should exist with Surname <Surname>' -ForEach ($V.UserTests | Where-Object { $_.Surname }) {
            $MatchingUser = $CollectedData.Users | Where-Object {
                $_.SamAccountName -eq $SamAccountName -and
                $_.Surname -eq $Surname
            }
            $MatchingUser | Should -Not -BeNullOrEmpty
        }

        It 'User <SamAccountName> should exist' -ForEach ($V.UserTests | Where-Object { -not $_.GivenName -and -not $_.Surname }) {
            $MatchingUser = $CollectedData.Users | Where-Object {
                $_.SamAccountName -eq $SamAccountName
            }
            $MatchingUser | Should -Not -BeNullOrEmpty
        }

        It 'User <SamAccountName> should be located in OU path <ExpectedOU>' -ForEach ($V.UserTests | Where-Object { $_.ExpectedOU }) {
            $MatchingUser = $CollectedData.Users | Where-Object { $_.SamAccountName -eq $SamAccountName }
            $MatchingUser | Should -Not -BeNullOrEmpty
            $MatchingUser.DistinguishedName | Should -BeLike "*$ExpectedOU*"
        }
    }

    Context 'Group Membership' {
        It 'User <UserSamAccountName> should be member of group <GroupName>' -ForEach $V.GroupMembershipTests {
            $NormalizedGroupName = Resolve-AdGroupName $GroupName
            $Group = $CollectedData.Groups | Where-Object {
                (Resolve-AdGroupName $_.Name) -ieq $NormalizedGroupName
            }
            $Group | Should -Not -BeNullOrEmpty

            $User = $CollectedData.Users | Where-Object { $_.SamAccountName -eq $UserSamAccountName }
            $User | Should -Not -BeNullOrEmpty

            $User.MemberOf | Should -Contain $Group.DistinguishedName
        }
    }

    Context 'Domain Controllers' {
        It 'Domain controller <Name> should be in site <ExpectedSite>' -ForEach $V.DcSiteTests {
            $MatchingDC = $CollectedData.DomainControllers | Where-Object { $_.Name -eq $Name }
            $MatchingDC | Should -Not -BeNullOrEmpty
            $MatchingDC.Site | Should -Be $ExpectedSite
        }
    }

    Context 'Sites' {
        It 'AD site <Name> should exist' -ForEach $V.SiteTests {
            $MatchingSite = $CollectedData.Sites | Where-Object { $_.Name -eq $Name }
            $MatchingSite | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Subnets' {
        It 'Subnet <Subnet> should be assigned to site <SiteName>' -ForEach $V.SubnetTests {
            $MatchingSubnet = $CollectedData.Subnets | Where-Object { $_.Name -eq $Subnet }
            $MatchingSubnet | Should -Not -BeNullOrEmpty
            $MatchingSubnet.SiteName | Should -Be $SiteName
        }
    }

    Context 'Site Links' {
        It 'Site link <Name> should exist and include sites <Sites>' -ForEach $V.SiteLinkExistenceTests {
            $Link = $CollectedData.SiteLinks | Where-Object { $_.Name -eq $Name }
            $Link | Should -Not -BeNullOrEmpty
            foreach ($ExpectedSite in $Sites) {
                $Link.SiteNames | Should -Contain $ExpectedSite
            }
        }

        It 'Site link <Name> should have cost <ExpectedCost>' -ForEach $V.SiteLinkCostTests {
            $Link = $CollectedData.SiteLinks | Where-Object { $_.Name -eq $Name }
            $Link | Should -Not -BeNullOrEmpty
            $Link.Cost | Should -Be $ExpectedCost
        }

        It 'Site link <Name> should have replication interval <ExpectedInterval> minutes' -ForEach $V.SiteLinkReplIntervalTests {
            $Link = $CollectedData.SiteLinks | Where-Object { $_.Name -eq $Name }
            $Link | Should -Not -BeNullOrEmpty
            $Link.ReplicationFrequencyInMinutes | Should -Be $ExpectedInterval
        }

        It 'Site link <Name> should not sync on weekends' -ForEach ($V.SiteLinkScheduleTests | Where-Object { $_.ScheduleExcludeWeekends }) {
            $Link = $CollectedData.SiteLinks | Where-Object { $_.Name -eq $Name }
            $Link | Should -Not -BeNullOrEmpty
            $Link.ScheduleMatrix | Should -Not -BeNullOrEmpty

            # DayIndex 0=Sunday (indices 0-23), DayIndex 6=Saturday (indices 144-167)
            $SundayHours = 0..23 | ForEach-Object { $Link.ScheduleMatrix[$_] }
            $SaturdayHours = 0..23 | ForEach-Object { $Link.ScheduleMatrix[144 + $_] }
            $SundayHours | Should -Not -Contain { $_ -ne 0 }
            $SaturdayHours | Should -Not -Contain { $_ -ne 0 }

            # At least one weekday hour must be available (Mon-Fri = days 1-5)
            $WeekdayHours = 1..5 | ForEach-Object {
                $Day = $_
                0..23 | ForEach-Object { $Link.ScheduleMatrix[($Day * 24) + $_] }
            }
            $WeekdayHours | Should -Contain { $_ -ne 0 }
        }

        It 'Site link <Name> should not sync during excluded hours' -ForEach ($V.SiteLinkScheduleTests | Where-Object { $_.ScheduleExcludeHours.Count -gt 0 }) {
            $Link = $CollectedData.SiteLinks | Where-Object { $_.Name -eq $Name }
            $Link | Should -Not -BeNullOrEmpty
            $Link.ScheduleMatrix | Should -Not -BeNullOrEmpty

            foreach ($ExcludedHour in $ScheduleExcludeHours) {
                foreach ($Day in 0..6) {
                    $Idx = ($Day * 24) + $ExcludedHour
                    $Link.ScheduleMatrix[$Idx] | Should -Be 0 `
                        -Because "hour $ExcludedHour on day $Day should not be available"
                }
            }

            # At least one non-excluded hour must be available on at least one day
            $AllHours = 0..23
            $IncludedHours = $AllHours | Where-Object { $ScheduleExcludeHours -notcontains $_ }
            $HasAvailable = $false
            foreach ($Hour in $IncludedHours) {
                foreach ($Day in 0..6) {
                    if ($Link.ScheduleMatrix[($Day * 24) + $Hour] -ne 0) {
                        $HasAvailable = $true
                        break
                    }
                }
                if ($HasAvailable) { break }
            }
            $HasAvailable | Should -BeTrue -Because 'at least one non-excluded hour should allow replication'
        }
    }

    Context 'Domain Name' {
        It 'Domain name should be <ExpectedDomain>' -ForEach $V.DomainNameTests {
            $CollectedData.DomainName | Should -BeLike $ExpectedDomain
        }
    }

    Context 'Group Existence' {
        It 'Group <Name> or naming variant should exist with scope <GroupScope> and category <GroupCategory>' -ForEach (
            $V.GroupExistenceTests | Where-Object { $_.GroupScope -or $_.GroupCategory }
        ) {
            $NormalizedName = Resolve-AdGroupName $Name
            $MatchingGroup = $CollectedData.Groups | Where-Object {
                (Resolve-AdGroupName $_.Name) -ieq $NormalizedName
            }
            $MatchingGroup | Should -Not -BeNullOrEmpty
            if ($GroupScope) {
                $MatchingGroup.GroupScope | Should -Be $GroupScope
            }
            if ($GroupCategory) {
                $MatchingGroup.GroupCategory | Should -Be $GroupCategory
            }
        }

        It 'Group <Name> or naming variant should exist' -ForEach (
            $V.GroupExistenceTests | Where-Object { -not $_.GroupScope -and -not $_.GroupCategory }
        ) {
            $NormalizedName = Resolve-AdGroupName $Name
            $MatchingGroup = $CollectedData.Groups | Where-Object {
                (Resolve-AdGroupName $_.Name) -ieq $NormalizedName
            }
            $MatchingGroup | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Group Nesting' {
        It 'Group <ChildGroupName> or naming variant should be a member of group <ParentGroupName> or naming variant' -ForEach $V.GroupInGroupTests {
            $NormalizedParent = Resolve-AdGroupName $ParentGroupName
            $ParentGroup = $CollectedData.Groups | Where-Object {
                (Resolve-AdGroupName $_.Name) -ieq $NormalizedParent
            }
            $ParentGroup | Should -Not -BeNullOrEmpty
            $NormalizedChild = Resolve-AdGroupName $ChildGroupName
            $ChildGroup = $CollectedData.Groups | Where-Object {
                (Resolve-AdGroupName $_.Name) -ieq $NormalizedChild
            }
            if ($ChildGroup) {
                $ParentGroup.Members | Should -Contain $ChildGroup.DistinguishedName
            }
            else {
                $MatchingMember = $ParentGroup.Members | Where-Object {
                    $_ -like "*$ChildGroupName*" -or
                    ($_ -match '^CN=([^,]+),' -and (Resolve-AdGroupName $Matches[1]) -ieq $NormalizedChild)
                }
                $MatchingMember | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Group Member Count' {
        It 'Group <GroupName> or naming variant should have at least <MinMemberCount> member(s)' -ForEach $V.GroupHasMembersTests {
            $NormalizedGroupName = Resolve-AdGroupName $GroupName
            $MatchingGroup = $CollectedData.Groups | Where-Object {
                (Resolve-AdGroupName $_.Name) -ieq $NormalizedGroupName
            }
            $MatchingGroup | Should -Not -BeNullOrEmpty
            $Min = if ($MinMemberCount) { [int]$MinMemberCount } else { 1 }
            @($MatchingGroup.Members).Count | Should -BeGreaterOrEqual $Min
            if ($RequiredMemberOU) {
                $OuMembers = @($MatchingGroup.Members | Where-Object { $_ -like "*OU=$RequiredMemberOU,*" })
                $OuMembers.Count | Should -BeGreaterOrEqual 1 `
                    -Because "at least one member of '$GroupName' must be in OU '$RequiredMemberOU'"
            }
        }
    }
}
