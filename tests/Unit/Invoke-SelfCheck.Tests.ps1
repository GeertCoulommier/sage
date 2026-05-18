#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Invoke-SelfCheck - TUI entry point.
.DESCRIPTION
    Verifies parameter validation, TUI directory resolution, and error handling
    for the self-check entry point.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\Public\Invoke-SelfCheck.ps1')

    # Stub out dependencies
    function Import-ExamDefinition {
        param($Path)

        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            $null = $Path.Length
        }
        return @{ Categories = @(); Targets = @{} }
    }
    function Show-MainMenu { return 'Quit' }
    function Show-TargetSelector { return @() }
    function Show-CategorySelector { return @() }
    function Get-ConnectionFallback { return @{} }
    function Invoke-SshKeySetup { return @{} }
    function Invoke-LocalEvaluation { return [PSCustomObject]@{ Summary = $null; Error = $null; OutputPath = '' } }
    function Show-ResultsSummary { return 'Back' }
    function Show-PreviousRun { return 'Back' }
    function Show-Setting {
        param(
            [string] $TuiPath,
            [string] $OutputDir,
            [bool]   $UseSpectre,
            [string] $ConfigPath
        )
        $null = @($TuiPath, $OutputDir, $UseSpectre, $ConfigPath)
        return 'Back'
    }
    function Get-LatestOutputPath { return $null }
    function Import-ResultSummary { return $null }
    function Initialize-TuiUserConfig {
        param([string] $VanillaConfigPath, [string] $UserConfigPath)
        return $VanillaConfigPath
    }

    function Invoke-InstallModuleStub {
        param(
            [string] $Name,
            [string] $Scope,
            [switch] $Force,
            [switch] $AllowClobber,
            [string] $ErrorAction
        )

        $null = @($Name, $Scope, $ErrorAction)
        $null = @($Force.IsPresent, $AllowClobber.IsPresent)
    }

    Set-Alias -Name 'Show-PreviousRuns' -Value 'Show-PreviousRun' -Scope Script -Force
    Set-Alias -Name 'Show-Settings' -Value 'Show-Setting' -Scope Script -Force
    Set-Alias -Name 'Install-Module' -Value 'Invoke-InstallModuleStub' -Scope Script -Force

    function Get-SageTheme { param([string] $ThemeName) return @{ Primary = [System.ConsoleColor]::Cyan; Accent = [System.ConsoleColor]::DarkCyan; Header = [System.ConsoleColor]::Cyan; Pass = [System.ConsoleColor]::Green; Fail = [System.ConsoleColor]::Red; Warn = [System.ConsoleColor]::Yellow; Muted = [System.ConsoleColor]::DarkGray } }
    function Get-SageThemeNames { return @('Default') }
}

Describe 'Invoke-SelfCheck' -Tag 'Unit' {

    Context 'TUI directory validation' {

        It 'Throws when TUI directory does not exist' {
            { Invoke-SelfCheck -TuiPath '/nonexistent/path/to/tui' } |
                Should -Throw '*TUI directory not found*'
        }

        It 'Throws DirectoryNotFoundException for missing TUI path' {
            $Error.Clear()
            try { Invoke-SelfCheck -TuiPath '/nonexistent/path/to/tui' } catch { $Caught = $_ }
            $Caught.Exception | Should -BeOfType [System.IO.DirectoryNotFoundException]
        }
    }

    Context 'TUI config validation' {

        It 'Throws when tui-config.psd1 is missing from TUI directory' {
            $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
            $PrivateDir = Join-Path $TempDir 'Private'
            New-Item -Path $PrivateDir -ItemType Directory -Force | Out-Null
            Mock Get-Module { return $null }
            Mock Install-Module { }
            Mock Write-Host { }

            try {
                { Invoke-SelfCheck -TuiPath $TempDir } | Should -Throw '*TUI exam config not found*'
            }
            finally {
                Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Menu loop' {

        It 'Exits cleanly when Show-MainMenu returns Quit' {
            # Create a minimal TUI directory with config
            $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
            $PrivateDir = Join-Path $TempDir 'Private'
            New-Item -Path $PrivateDir -ItemType Directory -Force | Out-Null

            $ConfigContent = @'
@{
    ExamDefinitionPath    = 'fake.psd1'
    Targets               = @{}
    DomainNamePlaceholder = '<domainname>'
}
'@
            Set-Content -Path (Join-Path $TempDir 'tui-config.psd1') -Value $ConfigContent

            Mock Import-ExamDefinition { return @{ Categories = @(); Targets = @{} } }
            Mock Import-PowerShellDataFile {
                return @{
                    ExamDefinitionPath    = 'fake.psd1'
                    Targets               = @{}
                    DomainNamePlaceholder = '<domainname>'
                }
            }
            Mock Show-MainMenu { return 'Quit' }
            Mock Write-Host { }
            Mock Get-Module { return $null }
            Mock Install-Module { }

            try {
                { Invoke-SelfCheck -TuiPath $TempDir } | Should -Not -Throw
            }
            finally {
                Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'SSH key gating' {

        It 'Disables targets that still fail SSH key authentication' {
            $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
            $PrivateDir = Join-Path $TempDir 'Private'
            New-Item -Path $PrivateDir -ItemType Directory -Force | Out-Null

            $ConfigContent = @'
@{
    ExamDefinitionPath    = 'fake.psd1'
    Targets               = @{}
    TargetOrder           = @('Linux', 'DC1')
    DomainNamePlaceholder = '<domainname>'
}
'@
            Set-Content -Path (Join-Path $TempDir 'tui-config.psd1') -Value $ConfigContent

            $script:MainMenuCallCount = 0
            $script:CapturedEnabledTargets = $null
            $script:CapturedConnectionInfo = $null

            Mock Import-ExamDefinition {
                return @{
                    Categories = @(
                        @{
                            Name      = 'General Configuration Linux'
                            Target    = 'Linux'
                            Variables = @{}
                        }
                        @{
                            Name      = 'DNS DC1'
                            Target    = 'DC1'
                            Variables = @{}
                        }
                    )
                    Targets    = @{
                        Linux = @{
                            Platform = 'Linux'
                            UserName = 'student'
                        }
                        DC1   = @{
                            Platform = 'Windows'
                            UserName = 'administrator'
                        }
                    }
                }
            }
            Mock Import-PowerShellDataFile {
                return @{
                    ExamDefinitionPath    = 'fake.psd1'
                    Targets               = @{}
                    TargetOrder           = @('Linux', 'DC1')
                    DomainNamePlaceholder = '<domainname>'
                }
            }
            Mock Show-MainMenu {
                $script:MainMenuCallCount++
                if ($script:MainMenuCallCount -eq 1) {
                    return 'RunEvaluation'
                }

                return 'Quit'
            }
            Mock Show-TargetSelector { return @('Linux', 'DC1') }
            Mock Get-ConnectionFallback {
                return @{
                    Linux = [PSCustomObject]@{
                        HostName = '192.168.1.2'
                        Port     = 22
                    }
                    DC1   = [PSCustomObject]@{
                        HostName = '192.168.1.3'
                        Port     = 22
                    }
                }
            }
            Mock Invoke-SshKeySetup {
                return @{
                    Linux = [PSCustomObject]@{
                        KeyAuthWorks = $false
                        Message      = 'Key installation failed.'
                    }
                    DC1   = [PSCustomObject]@{
                        KeyAuthWorks = $true
                        Message      = 'Key authentication verified.'
                    }
                }
            }
            Mock Show-CategorySelector {
                param($EnabledTargets)

                $script:CapturedEnabledTargets = @($EnabledTargets)
                return @('DNS DC1')
            }
            Mock Invoke-LocalEvaluation {
                param($ConnectionInfo)

                $script:CapturedConnectionInfo = $ConnectionInfo
                return [PSCustomObject]@{
                    Summary    = [PSCustomObject]@{}
                    Error      = $null
                    OutputPath = ''
                }
            }
            Mock Show-ResultsSummary { return 'Back' }
            Mock Write-Host { }
            Mock Get-Module { return $null }
            Mock Install-Module { }

            try {
                Invoke-SelfCheck -TuiPath $TempDir
            }
            finally {
                Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            $script:CapturedEnabledTargets | Should -HaveCount 1
            $script:CapturedEnabledTargets[0] | Should -Be 'DC1'
            $script:CapturedConnectionInfo.Keys | Should -HaveCount 1
            $script:CapturedConnectionInfo.Keys | Should -Contain 'DC1'
            $script:CapturedConnectionInfo.Keys | Should -Not -Contain 'Linux'
        }
    }

    Context 'SageQuit propagation' {

        It 'Does not call Invoke-LocalEvaluation when SageQuit is set in TargetSelector' {
            $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
            $PrivateDir = Join-Path $TempDir 'Private'
            New-Item -Path $PrivateDir -ItemType Directory -Force | Out-Null

            $ConfigContent = "@{ ExamDefinitionPath = 'fake.psd1'; Targets = @{}; DomainNamePlaceholder = '<domainname>' }"
            Set-Content -Path (Join-Path $TempDir 'tui-config.psd1') -Value $ConfigContent

            Mock Import-PowerShellDataFile {
                return @{ ExamDefinitionPath = 'fake.psd1'; Targets = @{}; DomainNamePlaceholder = '<domainname>' }
            }
            Mock Import-ExamDefinition { return @{ Categories = @(); Targets = @{} } }
            Mock Show-MainMenu {
                $script:MainMenuCallCount++
                if ($script:MainMenuCallCount -eq 1) { return 'RunEvaluation' }
                return 'Quit'
            }
            Mock Show-TargetSelector {
                $script:SageQuit = $true
                return @()
            }
            Mock Invoke-LocalEvaluation { return [PSCustomObject]@{ Summary = $null; Error = $null; OutputPath = '' } }
            Mock Get-Module { return $null }
            Mock Install-Module { }
            Mock Write-Host { }

            $script:MainMenuCallCount = 0
            $script:SageQuit = $false

            try {
                Invoke-SelfCheck -TuiPath $TempDir
            }
            finally {
                Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            Should -Not -Invoke Invoke-LocalEvaluation
        }
    }

    Context 'Domain name validation' {

        BeforeEach {
            $script:TempDirDomain = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
            $PrivateDirDomain = Join-Path $script:TempDirDomain 'Private'
            New-Item -Path $PrivateDirDomain -ItemType Directory -Force | Out-Null

            $ConfigContent = "@{ ExamDefinitionPath = 'fake.psd1'; Targets = @{}; DomainNamePlaceholder = '<domainname>' }"
            Set-Content -Path (Join-Path $script:TempDirDomain 'tui-config.psd1') -Value $ConfigContent

            Mock Import-PowerShellDataFile {
                return @{ ExamDefinitionPath = 'fake.psd1'; Targets = @{}; DomainNamePlaceholder = '<domainname>' }
            }
            Mock Import-ExamDefinition {
                return @{
                    Categories = @(
                        @{ Name = 'DNS DC1'; Target = 'DC1'; Variables = @{ Zone = '<domainname>.local' } }
                    )
                    Targets    = @{}
                }
            }
            Mock Show-MainMenu { return 'Quit' }
            Mock Write-Host { }
            Mock Get-Module { return $null }
            Mock Install-Module { }
        }

        AfterEach {
            Remove-Item -Path $script:TempDirDomain -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Accepts two-part domain (voornaam.local) and extracts base name' {
            $script:CapturedDomainName = $null
            $script:MenuCallCount3 = 0
            Mock Read-Host { return 'geert.local' }
            Mock Show-MainMenu {
                $script:MenuCallCount3++
                if ($script:MenuCallCount3 -eq 1) { return 'RunEvaluation' }
                return 'Quit'
            }
            Mock Show-TargetSelector { return @('DC1') }
            Mock Get-ConnectionFallback {
                return @{ DC1 = [PSCustomObject]@{ HostName = '1.2.3.4'; Port = 22 } }
            }
            Mock Invoke-SshKeySetup {
                return @{ DC1 = [PSCustomObject]@{ KeyAuthWorks = $true; Message = 'ok' } }
            }
            Mock Show-CategorySelector { return @('DNS DC1') }
            Mock Invoke-LocalEvaluation {
                param($DomainName)

                $script:CapturedDomainName = $DomainName
                return [PSCustomObject]@{ Summary = $null; Error = $null; OutputPath = '' }
            }
            Mock Show-ResultsSummary { return 'Back' }

            Invoke-SelfCheck -TuiPath $script:TempDirDomain

            # Domain name passed to evaluation should be just 'geert' (the base name)
            $script:CapturedDomainName | Should -Be 'geert'
        }

        It 'Prompts for confirmation when single-word domain entered, then accepts' {
            $script:MenuCallCount4 = 0
            $script:ReadHostCallCount = 0
            Mock Read-Host {
                $script:ReadHostCallCount++
                if ($script:ReadHostCallCount -eq 1) { return 'geert' }   # single word
                return 'Y'                                                  # confirm voornaam.local
            }
            Mock Show-MainMenu {
                $script:MenuCallCount4++
                if ($script:MenuCallCount4 -eq 1) { return 'RunEvaluation' }
                return 'Quit'
            }
            Mock Show-TargetSelector { return @('DC1') }
            Mock Get-ConnectionFallback {
                return @{ DC1 = [PSCustomObject]@{ HostName = '1.2.3.4'; Port = 22 } }
            }
            Mock Invoke-SshKeySetup {
                return @{ DC1 = [PSCustomObject]@{ KeyAuthWorks = $true; Message = 'ok' } }
            }
            Mock Show-CategorySelector { return @('DNS DC1') }
            Mock Invoke-LocalEvaluation {
                return [PSCustomObject]@{ Summary = $null; Error = $null; OutputPath = '' }
            }
            Mock Show-ResultsSummary { return 'Back' }

            { Invoke-SelfCheck -TuiPath $script:TempDirDomain } | Should -Not -Throw

            $script:ReadHostCallCount | Should -BeGreaterOrEqual 2
        }

        It 'Warns and prompts for confirmation when 3-part domain entered' {
            $script:WarnShown = $false
            $script:MenuCallCount5 = 0
            $script:ReadHostCallCount = 0
            Mock Write-Host {
                param($Object)
                if ($Object -match 'more than two parts') { $script:WarnShown = $true }
            }
            Mock Read-Host {
                $script:ReadHostCallCount++
                if ($script:ReadHostCallCount -eq 1) { return 'student.geert.local' }  # 3-part
                return 'Y'                                                               # confirm
            }
            Mock Show-MainMenu {
                $script:MenuCallCount5++
                if ($script:MenuCallCount5 -eq 1) { return 'RunEvaluation' }
                return 'Quit'
            }
            Mock Show-TargetSelector { return @('DC1') }
            Mock Get-ConnectionFallback {
                return @{ DC1 = [PSCustomObject]@{ HostName = '1.2.3.4'; Port = 22 } }
            }
            Mock Invoke-SshKeySetup {
                return @{ DC1 = [PSCustomObject]@{ KeyAuthWorks = $true; Message = 'ok' } }
            }
            Mock Show-CategorySelector { return @('DNS DC1') }
            Mock Invoke-LocalEvaluation {
                return [PSCustomObject]@{ Summary = $null; Error = $null; OutputPath = '' }
            }
            Mock Show-ResultsSummary { return 'Back' }

            { Invoke-SelfCheck -TuiPath $script:TempDirDomain } | Should -Not -Throw

            $script:WarnShown | Should -BeTrue
        }
    }
}
