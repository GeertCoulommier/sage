#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Test-ExamDefinition.
.DESCRIPTION
    Covers: valid minimal exam, valid full exam, missing top-level keys, invalid
    Target definitions, invalid Category definitions, Roster validation,
    ExamStart/ExamEnd parsing, -PassThru mode, and loading from a .psd1 file.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Public\Test-ExamDefinition.ps1'
    . $Sut

    # ── Minimal valid exam definition shared across tests ─────────────────────────
    function New-ValidExam {
        @{
            Name       = 'Test Exam'
            Targets    = @{
                WinSrv1 = @{
                    Port             = 30022
                    UserName         = 'administrator'
                    Platform         = 'Windows'
                    CredentialSecret = 'AdminPwd'
                }
            }
            Categories = @(
                @{
                    Name       = 'DNS'
                    Target     = 'WinSrv1'
                    Evaluation = 'Dns'
                    Collector  = 'Dns'
                }
            )
        }
    }
}

Describe 'Test-ExamDefinition' -Tag 'Unit' {

    # ── Valid schemas ─────────────────────────────────────────────────────────────
    Context 'Valid exam definitions' {
        It 'Returns $true for a minimal valid exam' {
            Test-ExamDefinition -ExamDefinition (New-ValidExam) | Should -Be $true
        }

        It 'Returns $true when DefaultCredentialSecret is used instead of per-target' {
            $Exam = New-ValidExam
            $Exam.DefaultCredentialSecret = 'SharedPwd'
            $Exam.Targets.WinSrv1.Remove('CredentialSecret')
            Test-ExamDefinition -ExamDefinition $Exam | Should -Be $true
        }

        It 'Returns $true with a Linux target' {
            $Exam = New-ValidExam
            $Exam.Targets.LinuxVM = @{
                Port             = 20022
                UserName         = 'student'
                Platform         = 'Linux'
                CredentialSecret = 'LinuxPwd'
            }
            Test-ExamDefinition -ExamDefinition $Exam | Should -Be $true
        }

        It 'Returns $true with valid ExamStart and ExamEnd' {
            $Exam = New-ValidExam
            $Exam.ExamStart = '2025-08-20T09:00:00'
            $Exam.ExamEnd = '2025-08-20T13:00:00'
            Test-ExamDefinition -ExamDefinition $Exam | Should -Be $true
        }

        It 'Returns $true with a valid Roster section' {
            $Exam = New-ValidExam
            $Exam.Roster = @{
                IPField    = 'ip'
                EmailField = 'school e-mail'
                NameField  = 'student'
            }
            Test-ExamDefinition -ExamDefinition $Exam | Should -Be $true
        }

        It 'Returns $true with Variables containing PassGrade > 0' {
            $Exam = New-ValidExam
            $Exam.Categories[0].Variables = @{
                ARecords = @(
                    @{
                        Name = 'dc1'
                        IP = '192.168.1.3'
                        Zone = 'zinneke.be'
                        PassGrade = 1
                    }
                )
            }
            Test-ExamDefinition -ExamDefinition $Exam | Should -Be $true
        }
    }

    # ── Missing required top-level keys ──────────────────────────────────────────
    Context 'Missing required top-level keys' {
        It 'Throws when Name is missing' {
            $Exam = New-ValidExam; $Exam.Remove('Name')
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Returns $false when Name is missing (-PassThru)' {
            $Exam = New-ValidExam; $Exam.Remove('Name')
            $Result = Test-ExamDefinition -ExamDefinition $Exam -PassThru -ErrorAction SilentlyContinue
            $Result | Should -Be $false
        }
        It 'Throws when Targets is missing' {
            $Exam = New-ValidExam; $Exam.Remove('Targets')
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when Categories is missing' {
            $Exam = New-ValidExam; $Exam.Remove('Categories')
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
    }

    # ── Target validation ─────────────────────────────────────────────────────────
    Context 'Target validation' {
        It 'Throws when Target has an invalid Platform' {
            $Exam = New-ValidExam
            $Exam.Targets.WinSrv1.Platform = 'MacOS'
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when Target Port is out of range' {
            $Exam = New-ValidExam
            $Exam.Targets.WinSrv1.Port = 99999
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when Target Port is 0' {
            $Exam = New-ValidExam
            $Exam.Targets.WinSrv1.Port = 0
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when UserName is missing' {
            $Exam = New-ValidExam
            $Exam.Targets.WinSrv1.Remove('UserName')
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Does not throw when no credential is available (SSH key auth path)' {
            # Targets without CredentialSecret are valid when SSH key auth is used.
            $Exam = New-ValidExam
            $Exam.Targets.WinSrv1.Remove('CredentialSecret')
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Not -Throw
        }
    }

    # ── Category validation ───────────────────────────────────────────────────────
    Context 'Category validation' {
        It 'Throws when Category Name is missing' {
            $Exam = New-ValidExam
            $Exam.Categories[0].Remove('Name')
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when Category Target does not match a defined Target key' {
            $Exam = New-ValidExam
            $Exam.Categories[0].Target = 'NonExistentVM'
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when Category Evaluation is missing' {
            $Exam = New-ValidExam
            $Exam.Categories[0].Remove('Evaluation')
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when Category Collector is missing' {
            $Exam = New-ValidExam
            $Exam.Categories[0].Remove('Collector')
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when a Variables item has PassGrade = 0' {
            $Exam = New-ValidExam
            $Exam.Categories[0].Variables = @{
                ARecords = @(
                    @{
                        Name = 'dc1'
                        PassGrade = 0
                    }
                )
            }
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when a Variables item has PassGrade < 0' {
            $Exam = New-ValidExam
            $Exam.Categories[0].Variables = @{
                ARecords = @(
                    @{
                        Name = 'dc1'
                        PassGrade = -1
                    }
                )
            }
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
    }

    # ── Roster validation ─────────────────────────────────────────────────────────
    Context 'Roster validation' {
        It 'Throws when Roster is present but IPField is missing' {
            $Exam = New-ValidExam
            $Exam.Roster = @{
                EmailField = 'email'
                NameField = 'name'
            }
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when Roster EmailField is empty string' {
            $Exam = New-ValidExam
            $Exam.Roster = @{
                IPField = 'ip'
                EmailField = ''
                NameField = 'name'
            }
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
    }

    # ── ExamStart / ExamEnd ───────────────────────────────────────────────────────
    Context 'ExamStart and ExamEnd validation' {
        It 'Throws when ExamStart is not a valid date string' {
            $Exam = New-ValidExam
            $Exam.ExamStart = 'not-a-date'
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when ExamEnd is before ExamStart' {
            $Exam = New-ValidExam
            $Exam.ExamStart = '2025-08-20T13:00:00'
            $Exam.ExamEnd = '2025-08-20T09:00:00'
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
        It 'Throws when ExamEnd equals ExamStart' {
            $Exam = New-ValidExam
            $Exam.ExamStart = '2025-08-20T09:00:00'
            $Exam.ExamEnd = '2025-08-20T09:00:00'
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw
        }
    }

    # ── Loading from file ─────────────────────────────────────────────────────────
    Context 'Loading from a psd1 file' {
        BeforeAll {
            $script:TmpPsd1 = Join-Path ([System.IO.Path]::GetTempPath()) "exam-test-$([System.Guid]::NewGuid().ToString('N')[0..7] -join '').psd1"
            @'
@{
    Name       = 'FileTest'
    Targets    = @{
        T1 = @{
            Port = 22
            UserName = 'u'
            Platform = 'Linux'
            CredentialSecret = 'S'
        }
    }
    Categories = @(
        @{
            Name = 'C'
            Target = 'T1'
            Evaluation = 'E'
            Collector = 'C'
        }
    )
}
'@ | Set-Content $script:TmpPsd1 -Encoding UTF8
        }
        AfterAll {
            Remove-Item $script:TmpPsd1 -Force -ErrorAction SilentlyContinue
        }
        It 'Returns $true when loading a valid psd1 file via -Path' {
            Test-ExamDefinition -Path $script:TmpPsd1 | Should -Be $true
        }
        It 'Throws on a non-existent file path' {
            { Test-ExamDefinition -Path 'C:\DoesNotExist\exam.psd1' } | Should -Throw
        }
    }

    # ── -PassThru mode emits non-terminating errors ───────────────────────────────
    Context '-PassThru error output' {
        It 'Emits a Write-Error for each issue when -PassThru is used' {
            $Exam = New-ValidExam
            $Exam.Remove('Name')
            $Exam.Remove('Targets')
            $Errors = @()
            $TestParams = @{
                ExamDefinition = $Exam
                PassThru = $true
                ErrorVariable = 'errors'
                ErrorAction = 'SilentlyContinue'
            }
            Test-ExamDefinition @TestParams
            $Errors.Count | Should -BeGreaterOrEqual 2
        }
    }

    # ── Line number tracking from .psd1 files ────────────────────────────────────
    Context 'Line number tracking in validation errors' {
        BeforeAll {
            # Create a deliberately faulty exam.psd1 with specific line breaks
            $script:FaultyPsd1 = Join-Path ([System.IO.Path]::GetTempPath()) "exam-faulty-$([System.Guid]::NewGuid().ToString('N')[0..7] -join '').psd1"
            @'
@{
    # Line 2 comment
    Name = ""

    Targets = @{
        lab01 = @{
            Port = 0
            UserName = ""
            Platform = 'Solaris'
            CredentialSecret = ""
        }
    }

    Categories = @(
        @{
            Name = 'Docker'
            Target = 'nonexistent'
            Evaluation = ''
            Collector = ''
            Variables = @{
                V = @(
                    @{
                        PassGrade = 0
                    }
                )
            }
        }
    )

    Roster = @{
        IPField = ""
        EmailField = ""
        NameField = ""
    }

    ExamStart = 'not-a-date'
}
'@ | Set-Content $script:FaultyPsd1 -Encoding UTF8
        }
        AfterAll {
            Remove-Item $script:FaultyPsd1 -Force -ErrorAction SilentlyContinue
        }

        It 'Includes line numbers in terminating error message for Name validation' {
            $Err = $null
            try {
                Test-ExamDefinition -Path $script:FaultyPsd1 -ErrorAction Stop
            }
            catch {
                $Err = $_
            }
            $Err.Exception.Message | Should -Match "Line \d+: Key 'Name' must be a non-empty string\."
        }

        It 'Includes line numbers for Target validation errors' {
            $Err = $null
            try {
                Test-ExamDefinition -Path $script:FaultyPsd1 -ErrorAction Stop
            }
            catch {
                $Err = $_
            }
            $Err.Exception.Message | Should -Match "Line \d+: Target 'lab01': 'Port' must be an integer"
        }

        It 'Includes line numbers for Category validation errors' {
            $Err = $null
            try {
                Test-ExamDefinition -Path $script:FaultyPsd1 -ErrorAction Stop
            }
            catch {
                $Err = $_
            }
            $Err.Exception.Message | Should -Match "Line \d+: Category 'Docker': 'Target' value 'nonexistent'"
        }

        It 'Includes line numbers for Roster validation errors' {
            $Err = $null
            try {
                Test-ExamDefinition -Path $script:FaultyPsd1 -ErrorAction Stop
            }
            catch {
                $Err = $_
            }
            $Err.Exception.Message | Should -Match 'Line \d+: Roster: missing or empty'
        }

        It 'Includes line numbers for ExamStart validation errors' {
            $Err = $null
            try {
                Test-ExamDefinition -Path $script:FaultyPsd1 -ErrorAction Stop
            }
            catch {
                $Err = $_
            }
            $Err.Exception.Message | Should -Match "Line \d+: 'ExamStart' value 'not-a-date' is not a valid datetime"
        }

        It 'Returns $false with -PassThru and includes line numbers in error messages' {
            $Errors = @()
            $TestParams = @{
                Path = $script:FaultyPsd1
                PassThru = $true
                ErrorVariable = 'errors'
                ErrorAction = 'SilentlyContinue'
            }
            $Result = Test-ExamDefinition @TestParams
            $Result | Should -Be $false
            $Errors.Count | Should -BeGreaterThan 0
            # Most errors should contain line numbers (those with specific locations in psd1)
            $ErrorsWithLines = $Errors | Where-Object { $_ -match '^Line \d+' }
            $ErrorsWithLines.Count | Should -BeGreaterThan 0
        }
    }

    # ── Missing top-level keys have no line number ──────────────────────────────
    Context 'Top-level missing keys (no line numbers)' {
        It 'Does not include Line prefix for missing required top-level keys' {
            $Exam = New-ValidExam; $Exam.Remove('Name')
            $Err = $null
            try {
                Test-ExamDefinition -ExamDefinition $Exam -ErrorAction Stop
            }
            catch {
                $Err = $_
            }
            # Missing top-level keys don't have line numbers
            $Err.Exception.Message | Should -Match 'Missing required top-level key'
        }
    }

    # ── ByPath load failure with -PassThru ────────────────────────────────────
    Context 'ByPath load failure with -PassThru' {
        BeforeAll {
            $script:BadPsd1 = Join-Path ([System.IO.Path]::GetTempPath()) "exam-bad-$([guid]::NewGuid().ToString('N')[0..7] -join '').psd1"
            # Write syntactically invalid PowerShell data so Import-PowerShellDataFile fails
            'THIS IS NOT VALID PSD1 {{{{' | Set-Content $script:BadPsd1 -Encoding UTF8
        }
        AfterAll {
            Remove-Item $script:BadPsd1 -Force -ErrorAction SilentlyContinue
        }

        It 'Returns $false and emits Write-Error when file cannot be parsed' {
            $Result = Test-ExamDefinition -Path $script:BadPsd1 -PassThru -ErrorAction SilentlyContinue
            $Result | Should -Be $false
        }

        It 'Throws terminating error without -PassThru' {
            { Test-ExamDefinition -Path $script:BadPsd1 } | Should -Throw '*Cannot load exam file*'
        }
    }

    # ── Name is non-string type ───────────────────────────────────────────────
    Context 'Name is non-string type' {
        It 'Throws when Name is an integer instead of a string' {
            $Exam = New-ValidExam
            $Exam.Name = 42
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw "*'Name' must be a non-empty string*"
        }
    }

    # ── Target value not a hashtable ──────────────────────────────────────────
    Context 'Target value not a hashtable' {
        It 'Throws when a target entry is a string instead of hashtable' {
            $Exam = New-ValidExam
            $Exam.Targets.WinSrv1 = 'not-a-hashtable'
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw "*Target 'WinSrv1': must be a hashtable*"
        }
    }

    # ── Port is not an integer ────────────────────────────────────────────────
    Context 'Port is not an integer' {
        It 'Throws when Port is a string' {
            $Exam = New-ValidExam
            $Exam.Targets.WinSrv1.Port = 'abc'
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw "*'Port' must be an integer*"
        }
    }

    # ── Category Variables item not a hashtable ───────────────────────────────
    Context 'Category Variables item not a hashtable' {
        It 'Throws when a Variables array item is a string' {
            $Exam = New-ValidExam
            $Exam.Categories[0].Variables = @{
                ARecords = @('just-a-string')
            }
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw '*each item must be a hashtable*'
        }
    }

    # ── Roster is not a hashtable ─────────────────────────────────────────────
    Context 'Roster is not a hashtable' {
        It 'Throws when Roster is a string' {
            $Exam = New-ValidExam
            $Exam.Roster = 'not-a-hashtable'
            { Test-ExamDefinition -ExamDefinition $Exam } | Should -Throw "*'Roster' must be a hashtable*"
        }
    }
}

