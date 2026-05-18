#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#!
.SYNOPSIS
    Unit tests for Save-TuiPreferencesInExam helper functions.
.DESCRIPTION
    Verifies target connection persistence writes valid PSD1 content and enforces
    numeric validation for port fields.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Save-TuiPreferencesInExam.ps1')
}

Describe 'Initialize-TuiUserConfig' -Tag 'Unit' {

    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
        New-Item -Path $script:TempDir -ItemType Directory -Force | Out-Null

        $script:VanillaConfigPath = Join-Path $script:TempDir 'tui-config.psd1'
        $script:UserConfigPath = Join-Path $script:TempDir 'data' 'config' 'tui-config-personal.psd1'
    }

    AfterEach {
        if (Test-Path $script:TempDir) {
            Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Repairs a stale personal exam definition path while preserving remembered settings' {
        $VanillaConfig = @'
@{
    ExamDefinitionPath = '../data/werkcolleges/Server-OS-werkcollege-labo5-7.psd1'
    Remembered         = @{
        Theme = '13. Nord Ice'
    }
}
'@
        $UserConfig = @'
@{
    ExamDefinitionPath = '../data/werkcolleges/werkcollege-labo5-6-group-policy-en-dhcp.psd1'
    Remembered         = @{
        Theme = '20. GitHub Dark'
    }
}
'@
        $ExpectedExamDir = Join-Path $script:TempDir 'data' 'werkcolleges'
        New-Item -Path $ExpectedExamDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $ExpectedExamDir 'Server-OS-werkcollege-labo5-7.psd1') -Value '@{}' -Encoding utf8

        New-Item -Path (Split-Path $script:UserConfigPath -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $script:VanillaConfigPath -Value $VanillaConfig -Encoding utf8
        Set-Content -Path $script:UserConfigPath -Value $UserConfig -Encoding utf8

        $ResolvedConfigPath = Initialize-TuiUserConfig -VanillaConfigPath $script:VanillaConfigPath -UserConfigPath $script:UserConfigPath
        $Config = Import-PowerShellDataFile -Path $ResolvedConfigPath

        $ResolvedConfigPath | Should -Be $script:UserConfigPath
        $Config.ExamDefinitionPath | Should -Be '../data/werkcolleges/Server-OS-werkcollege-labo5-7.psd1'
        $Config.Remembered.Theme | Should -Be '20. GitHub Dark'
    }
}

Describe 'Set-TargetConnectionInConfigFile' -Tag 'Unit' {

    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
        New-Item -Path $script:TempDir -ItemType Directory -Force | Out-Null

        $script:ConfigPath = Join-Path $script:TempDir 'tui-config-personal.psd1'
        $ConfigContent = @'
@{
    Targets = @{
        DC1 = @{
            PrimaryHostName  = '192.168.1.3'
            FallbackHostName = ''
            Port             = 22
            FallbackPort     = 30022
        }
    }
}
'@
        Set-Content -Path $script:ConfigPath -Value $ConfigContent -Encoding utf8
    }

    AfterEach {
        if (Test-Path $script:TempDir) {
            Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Updates fallback hostname and keeps PSD1 importable' {
        Set-TargetConnectionInConfigFile -ConfigPath $script:ConfigPath -TargetName 'DC1' -PropertyName 'FallbackHostName' -NewValue 'host-a.example.test'

        $Cfg = Import-PowerShellDataFile -Path $script:ConfigPath
        $Cfg.Targets.DC1.FallbackHostName | Should -Be 'host-a.example.test'
    }

    It 'Updates fallback hostname back and forth in the same file' {
        Set-TargetConnectionInConfigFile -ConfigPath $script:ConfigPath -TargetName 'DC1' -PropertyName 'FallbackHostName' -NewValue 'host-a.example.test'
        Set-TargetConnectionInConfigFile -ConfigPath $script:ConfigPath -TargetName 'DC1' -PropertyName 'FallbackHostName' -NewValue 'host-b.example.test'

        $Cfg = Import-PowerShellDataFile -Path $script:ConfigPath
        $Cfg.Targets.DC1.FallbackHostName | Should -Be 'host-b.example.test'
    }

    It 'Updates fallback port as integer literal' {
        Set-TargetConnectionInConfigFile -ConfigPath $script:ConfigPath -TargetName 'DC1' -PropertyName 'FallbackPort' -NewValue '40022'

        $Cfg = Import-PowerShellDataFile -Path $script:ConfigPath
        $Cfg.Targets.DC1.FallbackPort | Should -Be 40022
    }

    It 'Throws when non-numeric fallback port is provided' {
        { Set-TargetConnectionInConfigFile -ConfigPath $script:ConfigPath -TargetName 'DC1' -PropertyName 'FallbackPort' -NewValue 'srvos-2526.example.test' } | Should -Throw '*must be a whole number*'
    }

    It 'Throws when non-numeric default port is provided' {
        { Set-TargetConnectionInConfigFile -ConfigPath $script:ConfigPath -TargetName 'DC1' -PropertyName 'Port' -NewValue 'not-a-number' } | Should -Throw '*must be a whole number*'
    }
}
