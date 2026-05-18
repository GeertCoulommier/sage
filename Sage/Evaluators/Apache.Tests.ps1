# Evaluations/Apache.Tests.ps1
# Apache evaluation — tests driven entirely by exam data.
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
    'Apache Service'                = {
        param($Data)
        [PSCustomObject]@{
            ServiceEnabled = $Data.ServiceEnabled
            ServiceRunning = $Data.ServiceRunning
            SitesAvailable = $Data.SitesAvailable
            SitesEnabled   = $Data.SitesEnabled
        }
    }
    'Virtual Host Config Files'     = {
        param($Data)
        $Data.ConfFiles | ForEach-Object {
            [PSCustomObject]@{
                Name         = $_.Name
                VirtualHost  = ($_.VirtualHost -join ', ')
                ServerName   = ($_.ServerName -join ', ')
                ServerAlias  = ($_.ServerAlias -join ', ')
                Listen       = ($_.Listen -join ', ')
                DocumentRoot = ($_.DocumentRoot -join ', ')
            }
        }
    }
    'httpd.conf Include Directives' = {
        param($Data)
        [PSCustomObject]@{
            Listen          = ($Data.HttpdConfListen -join ', ')
            IncludeOptional = ($Data.HttpdConfInclude -join ', ')
        }
    }
    'Apache Virtual Hosts'          = {
        param($Data)
        $Data.ConfFiles | ForEach-Object {
            $Cf = $_
            $Cf.ServerName | ForEach-Object {
                [PSCustomObject]@{
                    File       = $Cf.Name
                    ServerName = $_
                }
            }
        }
    }
    'Website Content'               = {
        param($Data)
        $Data.IndexFiles | ForEach-Object {
            [PSCustomObject]@{
                Path    = $_.Path
                Preview = (($_.Content -split "`n") | Select-Object -First 3) -join ' | '
            }
        }
    }
    'Firewall'                      = {
        param($Data)
        [PSCustomObject]@{
            Services = ($Data.FirewallServices -join ', ')
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
    'Symlink Files'                 = {
        param($Data)
        $Data.SymlinkFiles | ForEach-Object {
            [PSCustomObject]@{
                Name       = $_.Name
                IsSymlink  = $_.IsSymlink
                LinkTarget = $_.LinkTarget
            }
        }
    }
    'Live Web Tests'                = {
        param($Data)
        $Data.CurlResults | ForEach-Object {
            [PSCustomObject]@{
                Url     = $_.Url
                Content = if ($_.Content) { ($_.Content | Select-Object -First 1) } else { $null }
                Error   = $_.Error
            }
        }
    }
    'MariaDB Service'               = {
        param($Data)
        [PSCustomObject]@{
            MariaDbEnabled = $Data.MariaDbEnabled
            MariaDbRunning = $Data.MariaDbRunning
        }
    }
    'PHP-FPM Service'               = {
        param($Data)
        [PSCustomObject]@{
            PhpFpmEnabled = $Data.PhpFpmEnabled
            PhpFpmRunning = $Data.PhpFpmRunning
        }
    }
    'PHP Info Files'                = {
        param($Data)
        $Data.PhpFiles | ForEach-Object {
            [PSCustomObject]@{
                Path    = $_.Path
                Preview = (($_.Content -split "`n") | Select-Object -First 3) -join ' | '
            }
        }
    }
}

Describe 'Apache Configuration' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.ServiceTests) { $V.ServiceTests = @() }
        if (-not $V.VirtualHostTests) { $V.VirtualHostTests = @() }
        if (-not $V.ContentTests) { $V.ContentTests = @() }
        if (-not $V.FirewallTests) { $V.FirewallTests = @() }
        if (-not $V.DirectoryTests) { $V.DirectoryTests = @() }
        if (-not $V.HttpdConfIncludeTests) { $V.HttpdConfIncludeTests = @() }
        if (-not $V.VirtualHostConfigTests) { $V.VirtualHostConfigTests = @() }
        if (-not $V.SymlinkTests) { $V.SymlinkTests = @() }
        if (-not $V.CurlTests) { $V.CurlTests = @() }
        if (-not $V.MariaDbTests) { $V.MariaDbTests = @() }
        if (-not $V.PhpFpmTests) { $V.PhpFpmTests = @() }
        if (-not $V.PhpFileTests) { $V.PhpFileTests = @() }
    }

    Context 'Apache Service' {
        It 'Apache service should be <Property>' -ForEach $V.ServiceTests {
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

    Context 'httpd.conf Include Directives' {
        It 'httpd.conf should contain include line <IncludeLine>' -ForEach $V.HttpdConfIncludeTests {
            $Match = $CollectedData.HttpdConfInclude |
                Where-Object { $_ -match [regex]::Escape($IncludeLine) }
            $Match | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Virtual Host Config Files' {
        It 'Config <ConfFile> should contain line <ContainsLine>' -ForEach $V.VirtualHostConfigTests {
            $File = $CollectedData.ConfFiles | Where-Object { $_.Name -eq $ConfFile }
            $File | Should -Not -BeNullOrEmpty -Because "config file $ConfFile must exist"
            $File.Content | Should -Match ([regex]::Escape($ContainsLine))
        }
    }

    Context 'Symlink Files' {
        It 'File <SymlinkPath> should be a symlink pointing to <ExpectedTarget>' -ForEach $V.SymlinkTests {
            $FileName = Split-Path $SymlinkPath -Leaf
            $Link = $CollectedData.SymlinkFiles | Where-Object { $_.Name -eq $FileName }
            $Link | Should -Not -BeNullOrEmpty -Because "symlink $FileName must exist in sites-enabled"
            $Link.IsSymlink | Should -BeTrue -Because "$FileName should be a symbolic link"
            $Link.LinkTarget | Should -Match ([regex]::Escape($ExpectedTarget))
        }
    }

    Context 'Live Web Tests' {
        It 'GET <Url> should return content matching <ExpectedContent>' -ForEach $V.CurlTests {
            $CurlResult = $CollectedData.CurlResults | Where-Object { $_.Url -eq $Url }
            $CurlResult | Should -Not -BeNullOrEmpty -Because "curl result for $Url must be present"
            $CurlResult.Content | Should -Match ([regex]::Escape($ExpectedContent))
        }
    }

    Context 'Apache Virtual Hosts' {
        It 'Config should contain ServerName matching <ServerName>' -ForEach $V.VirtualHostTests {
            $AllServerNames = $CollectedData.ConfFiles | ForEach-Object { $_.ServerName } | ForEach-Object { $_ }
            $MatchingName = $AllServerNames | Where-Object { $_ -match [regex]::Escape($ServerName) }
            $MatchingName | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Website Content' {
        It 'Index file should contain <ExpectedContent>' -ForEach $V.ContentTests {
            $AllContent = $CollectedData.IndexFiles | ForEach-Object { $_.Content }
            $MatchingContent = $AllContent | Where-Object { $_ -match [regex]::Escape($ExpectedContent) }
            $MatchingContent | Should -Not -BeNullOrEmpty
        }
    }

    Context 'MariaDB Service' {
        It 'MariaDB service should be <Property>' -ForEach $V.MariaDbTests {
            switch ($Property) {
                'enabled' { $CollectedData.MariaDbEnabled | Should -BeTrue }
                'running' { $CollectedData.MariaDbRunning | Should -BeTrue }
            }
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

    Context 'PHP Info Files' {
        It 'PHP file <FileName> in <Dir> should contain <ExpectedContent>' -ForEach $V.PhpFileTests {
            $File = $CollectedData.PhpFiles | Where-Object { $_.Name -eq $FileName -and $_.Dir -eq $Dir }
            $File | Should -Not -BeNullOrEmpty -Because "php file $FileName must exist in $Dir"
            $File.Content | Should -Match ([regex]::Escape($ExpectedContent))
        }
    }
}
