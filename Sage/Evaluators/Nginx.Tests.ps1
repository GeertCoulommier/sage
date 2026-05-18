# Evaluations/Nginx.Tests.ps1
# Nginx evaluation — tests driven entirely by exam data.
# Contains ONLY assertion logic — no expected values hardcoded.
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
    'Nginx Service'                 = {
        param($Data)
        [PSCustomObject]@{
            ServiceEnabled = $Data.ServiceEnabled
            ServiceRunning = $Data.ServiceRunning
            SitesAvailable = $Data.SitesAvailable
            SitesEnabled   = $Data.SitesEnabled
        }
    }
    'Firewall'                      = {
        param($Data)
        [PSCustomObject]@{
            FirewallServices = ($Data.FirewallServices -join ', ')
        }
    }
    'Required Directories'          = {
        param($Data)
        $Data.Directories.GetEnumerator() | ForEach-Object {
            [PSCustomObject]@{
                Path   = $_.Key
                Exists = $_.Value
            }
        }
    }
    'nginx.conf Include Directives' = {
        param($Data)
        [PSCustomObject]@{
            IncludeLines = ($Data.NginxConfInclude -join ' | ')
        }
    }
    'nginx.conf Listen Directives'  = {
        param($Data)
        [PSCustomObject]@{
            ListenLines = ($Data.NginxConfListen -join ' | ')
        }
    }
    'Nginx Config Files'            = {
        param($Data)
        $Data.ConfFiles | ForEach-Object {
            [PSCustomObject]@{
                Name       = $_.Name
                ServerName = ($_.ServerName -join ', ')
                Listen     = ($_.Listen -join ', ')
                Root       = ($_.Root -join ', ')
            }
        }
    }
    'Symlink Files'                 = {
        param($Data)
        $Data.SymlinkFiles | ForEach-Object {
            [PSCustomObject]@{
                Name       = $_.Name
                Path       = $_.Path
                IsSymlink  = $_.IsSymlink
                LinkTarget = $_.LinkTarget
            }
        }
    }
    'Live Web Tests'                = {
        param($Data)
        $Data.CurlResults | ForEach-Object {
            [PSCustomObject]@{
                Url             = $_.Url
                Success         = $_.Success
                ExpectedContent = $_.ExpectedContent
                Content         = if ($_.Content) { $_.Content.Substring(0, [Math]::Min(200, $_.Content.Length)) } else { '' }
            }
        }
    }
    'PHP-FPM Service'               = {
        param($Data)
        [PSCustomObject]@{
            PhpFpmEnabled = $Data.PhpFpmEnabled
            PhpFpmRunning = $Data.PhpFpmRunning
        }
    }
    'PHP-FPM Config'                = {
        param($Data)
        [PSCustomObject]@{
            PhpFpmConfContent = if ($Data.PhpFpmConfContent) {
                $Data.PhpFpmConfContent.Substring(0, [Math]::Min(400, $Data.PhpFpmConfContent.Length))
            }
            else { '' }
        }
    }
    'PHP Files'                     = {
        param($Data)
        $Data.PhpFiles | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Dir  = $_.Dir
                Path = $_.Path
            }
        }
    }
    'Website Content'               = {
        param($Data)
        $Data.IndexFiles | ForEach-Object {
            [PSCustomObject]@{
                Path    = $_.Path
                Content = if ($_.Content) { $_.Content.Substring(0, [Math]::Min(200, $_.Content.Length)) } else { '' }
            }
        }
    }
}

Describe 'Nginx Configuration' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.ServiceTests) { $V.ServiceTests = @() }
        if (-not $V.FirewallTests) { $V.FirewallTests = @() }
        if (-not $V.DirectoryTests) { $V.DirectoryTests = @() }
        if (-not $V.NginxConfIncludeTests) { $V.NginxConfIncludeTests = @() }
        if (-not $V.NginxConfListenTests) { $V.NginxConfListenTests = @() }
        if (-not $V.NginxConfFileTests) { $V.NginxConfFileTests = @() }
        if (-not $V.SymlinkTests) { $V.SymlinkTests = @() }
        if (-not $V.ContentTests) { $V.ContentTests = @() }
        if (-not $V.CurlTests) { $V.CurlTests = @() }
        if (-not $V.PhpFpmTests) { $V.PhpFpmTests = @() }
        if (-not $V.PhpFpmConfTests) { $V.PhpFpmConfTests = @() }
        if (-not $V.PhpFileTests) { $V.PhpFileTests = @() }
    }

    Context 'Nginx Service' {
        It 'Nginx service should be <Property>' -ForEach $V.ServiceTests {
            switch ($Property) {
                'enabled' { $CollectedData.ServiceEnabled | Should -BeTrue }
                'running' { $CollectedData.ServiceRunning | Should -BeTrue }
                'sites-available' { $CollectedData.SitesAvailable | Should -BeTrue }
                'sites-enabled' { $CollectedData.SitesEnabled | Should -BeTrue }
            }
        }
    }

    Context 'Firewall' {
        It 'Firewall should allow service <Service>' -ForEach $V.FirewallTests {
            $CollectedData.FirewallServices | Should -Contain $Service
        }
    }

    Context 'Required Directories' {
        It 'Directory <Path> should exist' -ForEach $V.DirectoryTests {
            $CollectedData.Directories[$Path] | Should -BeTrue
        }
    }

    Context 'nginx.conf Include Directives' {
        It 'nginx.conf should contain include line <IncludeLine>' -ForEach $V.NginxConfIncludeTests {
            $Match = $CollectedData.NginxConfInclude |
                Where-Object { $_ -match [regex]::Escape($IncludeLine) }
            $Match | Should -Not -BeNullOrEmpty
        }
    }

    Context 'nginx.conf Listen Directives' {
        It 'nginx.conf should contain listen line <ListenLine>' -ForEach $V.NginxConfListenTests {
            $Match = $CollectedData.NginxConfListen |
                Where-Object { $_ -match [regex]::Escape($ListenLine) }
            $Match | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Nginx Config Files' {
        It 'Config <ConfFile> should contain line <ContainsLine>' -ForEach $V.NginxConfFileTests {
            $File = $CollectedData.ConfFiles | Where-Object { $_.Name -eq $ConfFile }
            $File | Should -Not -BeNullOrEmpty -Because "config file $ConfFile must exist"
            $File.Content | Should -Match ([regex]::Escape($ContainsLine))
        }
    }

    Context 'Symlink Files' {
        It 'Symlink <SymlinkPath> should point to <ExpectedTarget>' -ForEach $V.SymlinkTests {
            $Link = $CollectedData.SymlinkFiles | Where-Object { $_.Path -eq $SymlinkPath }
            $Link | Should -Not -BeNullOrEmpty -Because "symlink $SymlinkPath must exist"
            $Link.IsSymlink | Should -BeTrue -Because "$SymlinkPath must be a symbolic link"
            $Link.LinkTarget | Should -Match ([regex]::Escape($ExpectedTarget))
        }
    }

    Context 'Website Content' {
        It 'Index file should contain <ExpectedContent>' -ForEach $V.ContentTests {
            $AllContent = $CollectedData.IndexFiles | ForEach-Object { $_.Content }
            $MatchingContent = $AllContent | Where-Object { $_ -match [regex]::Escape($ExpectedContent) }
            $MatchingContent | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Live Web Tests' {
        It 'URL <Url> should return content containing <ExpectedContent>' -ForEach $V.CurlTests {
            $CurlResult = $CollectedData.CurlResults | Where-Object { $_.Url -eq $Url }
            $CurlResult | Should -Not -BeNullOrEmpty -Because "curl result for $Url must exist"
            $CurlResult.Success | Should -BeTrue -Because "curl to $Url must succeed"
            $CurlResult.Content | Should -Match ([regex]::Escape($ExpectedContent))
        }
    }

    Context 'PHP-FPM Service' {
        It 'PHP-FPM service should be <Property>' -ForEach $V.PhpFpmTests {
            switch ($Property) {
                'enabled' { $CollectedData.PhpFpmEnabled | Should -BeTrue }
                'running' { $CollectedData.PhpFpmRunning | Should -BeTrue }
            }
        }
    }

    Context 'PHP-FPM Config' {
        It 'PHP-FPM www.conf should contain line <ConfLine>' -ForEach $V.PhpFpmConfTests {
            $CollectedData.PhpFpmConfContent | Should -Match ([regex]::Escape($ConfLine))
        }
    }

    Context 'PHP Files' {
        It 'PHP file <FileName> in <Dir> should contain <ExpectedContent>' -ForEach $V.PhpFileTests {
            $File = $CollectedData.PhpFiles | Where-Object { $_.Name -eq $FileName -and $_.Dir -eq $Dir }
            $File | Should -Not -BeNullOrEmpty -Because "PHP file $FileName must exist in $Dir"
            $File.Content | Should -Match ([regex]::Escape($ExpectedContent))
        }
    }
}

