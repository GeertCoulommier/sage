#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Invoke-StudentEvaluation — the per-student evaluation wrapper.
.DESCRIPTION
    Tests the full per-student pipeline: identity resolution, session setup,
    collector dispatch, Pester evaluation, grade aggregation, export, and
    session teardown.  All remote calls are mocked.
.TAGS Unit
#>

BeforeAll {
    # ── Dot-source dependencies ────────────────────────────────────────────────
    $PrivateDir = Join-Path $PSScriptRoot '..\..\Sage\Private'
    $PublicDir  = Join-Path $PSScriptRoot '..\..\Sage\Public'

    . (Join-Path $PrivateDir 'Write-Log.ps1')
    . (Join-Path $PrivateDir 'New-GradeResult.ps1')
    . (Join-Path $PrivateDir 'New-CollectorResult.ps1')
    . (Join-Path $PrivateDir 'New-RemoteSessionObject.ps1')
    . (Join-Path $PrivateDir 'ConvertTo-NormalizedGrade.ps1')
    . (Join-Path $PrivateDir 'ConvertTo-GradeSummary.ps1')
    . (Join-Path $PrivateDir 'Invoke-RemoteSetup.ps1')
    . (Join-Path $PrivateDir 'Invoke-RemoteCollector.ps1')
    . (Join-Path $PrivateDir 'Invoke-RemotePester.ps1')
    . (Join-Path $PrivateDir 'Copy-File.ps1')
    . (Join-Path $PrivateDir 'Format-CollectorData.ps1')
    . (Join-Path $PublicDir 'New-RemoteSession.ps1')
    . (Join-Path $PublicDir 'Close-RemoteSession.ps1')
    . (Join-Path $PublicDir 'Get-GradeSummary.ps1')
    . (Join-Path $PublicDir 'Export-GradeSummary.ps1')
    . (Join-Path $PublicDir 'Edit-Grade.ps1')
    . (Join-Path $PublicDir 'Set-SageLogPath.ps1')
    . (Join-Path $PublicDir 'Invoke-StudentEvaluation.ps1')

    # ── Shared fake builders ───────────────────────────────────────────────────
    function New-FakeExam {
        @{
            Name                    = 'Test Exam'
            Version                 = '1.0.0'
            Description             = 'Unit test exam'
            Author                  = 'Test'
            ExamStart               = '2025-01-01T09:00:00'
            ExamEnd                 = '2025-01-01T13:00:00'
            _ExamPath               = 'C:\fake\exam.psd1'
            _ExamDir                = 'C:\fake'
            Targets                 = @{
                WinSrv1 = @{
                    Port             = 30022
                    UserName         = 'administrator'
                    Platform         = 'Windows'
                    CredentialSecret = 'WinAdminPassword'
                }
            }
            DefaultCredentialSecret = 'DefaultPassword'
            Roster                  = @{
                IPField    = 'ip'
                EmailField = 'email'
                NameField  = 'student'
                Delimiter  = ','
            }
            Export                  = @{
                PrimaryFormat    = 'Json'
                SecondaryFormats = @()
            }
            Dependencies            = @{
                Modules = @('Pester')
            }
            Categories              = @(
                @{
                    Name       = 'DNS'
                    Target     = 'WinSrv1'
                    Evaluation = 'Dns'
                    Collector  = 'Dns'
                    Variables  = @{
                        ForwardZones = @(
                            @{
                                ZoneName  = 'test.local'
                                ZoneType  = 'Primary'
                                PassGrade = 2
                            }
                        )
                    }
                }
            )
        }
    }

    function New-FakeRow {
        param(
            [string]$Ip      = '10.0.0.1',
            [string]$Email   = 'jan@ehb.be',
            [string]$Student = 'Jan Appel'
        )
        [PSCustomObject]@{
            ip      = $Ip
            email   = $Email
            student = $Student
            pointer = '12345'
        }
    }

    function New-FakeSession {
        param([string]$TargetName = 'WinSrv1')
        [PSCustomObject]@{
            PSTypeName  = 'Sage.RemoteSession'
            TargetName  = $TargetName
            HostName    = '10.0.0.1'
            Port        = 30022
            UserName    = 'administrator'
            Platform    = 'Windows'
            Session     = $null
            ConnectedAt = [datetime]::Now
            SessionId   = 1
        }
    }

    function New-FakeCollectorResult {
        param([bool]$Available = $true)
        [PSCustomObject]@{
            PSTypeName    = 'Sage.CollectorResult'
            CollectorName = 'Dns'
            Available     = $Available
            Reason        = if (-not $Available) { 'DNS not installed' } else { $null }
            Data          = @{ Zones = @() }
            Errors        = @()
            Duration      = [timespan]::FromSeconds(1)
        }
    }

    function New-FakePesterResult {
        [PSCustomObject]@{
            PassedCount  = 1
            FailedCount  = 0
            SkippedCount = 0
            TotalCount   = 1
            Duration     = [timespan]::FromSeconds(2)
            Tests        = @(
                [PSCustomObject]@{
                    Name        = 'Zone test.local exists'
                    Result      = 'Passed'
                    ErrorRecord = $null
                    Data        = @{ PassGrade = 2 }
                    Block       = [PSCustomObject]@{
                        Name   = 'Forward Zones'
                        Parent = $null
                    }
                }
            )
        }
    }

    # ── Shared call helper — used by It blocks via BeforeAll scope ─────────────
    function Invoke-Stu {
        param(
            [hashtable]$Overrides = @{}
        )
        $Base = @{
            Row           = New-FakeRow
            Exam          = New-FakeExam
            IpField       = 'ip'
            EmailField    = 'email'
            NameField     = 'student'
            ExamOutputDir = $script:TempDir
        }
        foreach ($Key in $Overrides.Keys) { $Base[$Key] = $Overrides[$Key] }
        Invoke-StudentEvaluation @Base
    }
}

Describe 'Invoke-StudentEvaluation' -Tag 'Unit' {

    BeforeEach {
        Mock Write-Log {}
        Mock New-RemoteSession { New-FakeSession -TargetName $TargetName }
        Mock Invoke-RemoteSetup {}
        Mock Invoke-RemoteCollector { New-FakeCollectorResult }
        Mock Invoke-RemotePester { New-FakePesterResult }
        Mock Close-RemoteSession {}
        Mock Export-GradeSummary { 'C:\fake\results.json' }
        Mock Format-CollectorData { 'formatted output' }
        Mock Format-CollectorDataMarkdown { '# markdown output' }

        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-stu-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -Path $script:TempDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $script:TempDir) {
            Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ── Missing identity fields ────────────────────────────────────────────────
    Context 'Missing student identity fields' {

        It 'Returns an error result when IP field is empty' {
            $BadRow = New-FakeRow -Ip ''
            $Result = Invoke-Stu -Overrides @{ Row = $BadRow }
            $Result.Summary | Should -BeNullOrEmpty
            $Result.Error   | Should -Match "ip|NameField|skipped" -Because 'Error must mention the missing field'
        }

        It 'Returns an error result when student Name field is empty' {
            $BadRow = New-FakeRow -Student ''
            $Result = Invoke-Stu -Overrides @{ Row = $BadRow }
            $Result.Summary | Should -BeNullOrEmpty
            $Result.Error   | Should -Not -BeNullOrEmpty
        }

        It 'Does not call New-RemoteSession when fields are missing' {
            $BadRow = New-FakeRow -Ip ''
            Invoke-Stu -Overrides @{ Row = $BadRow }
            Should -Invoke New-RemoteSession -Times 0 -Exactly
        }

        It 'Logs a Warning when fields are missing' {
            $BadRow = New-FakeRow -Ip ''
            Invoke-Stu -Overrides @{ Row = $BadRow }
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warning' }
        }
    }

    # ── Successful pipeline ────────────────────────────────────────────────────
    Context 'Successful full pipeline' {

        It 'Returns a result with no Error' {
            $Result = Invoke-Stu
            $Result.Error | Should -BeNullOrEmpty
        }

        It 'Returns a Sage.StudentGradeSummary in Summary' {
            $Result = Invoke-Stu
            $Result.Summary | Should -Not -BeNullOrEmpty
            $Result.Summary.PSObject.TypeNames | Should -Contain 'Sage.StudentGradeSummary'
        }

        It 'Calls New-RemoteSession once per target' {
            Invoke-Stu
            Should -Invoke New-RemoteSession -Times 1 -Exactly
        }

        It 'Calls Invoke-RemoteSetup once per target session' {
            Invoke-Stu
            Should -Invoke Invoke-RemoteSetup -Times 1 -Exactly
        }

        It 'Calls Invoke-RemoteCollector once per category' {
            Invoke-Stu
            Should -Invoke Invoke-RemoteCollector -Times 1 -Exactly
        }

        It 'Calls Invoke-RemotePester once per available category' {
            Invoke-Stu
            Should -Invoke Invoke-RemotePester -Times 1 -Exactly
        }

        It 'Calls Export-GradeSummary once' {
            Invoke-Stu
            Should -Invoke Export-GradeSummary -Times 1 -Exactly
        }

        It 'Calls Close-RemoteSession once per target' {
            Invoke-Stu
            Should -Invoke Close-RemoteSession -Times 1 -Exactly
        }

        It 'Passes Json format to Export-GradeSummary by default' {
            Invoke-Stu
            Should -Invoke Export-GradeSummary -ParameterFilter { $Format -contains 'Json' }
        }

        It 'StudentName is populated on the returned summary' {
            $Result = Invoke-Stu
            $Result.Summary.StudentName | Should -Be 'Jan Appel'
        }

        It 'StudentEmail is populated on the returned summary' {
            $Result = Invoke-Stu
            $Result.Summary.StudentEmail | Should -Be 'jan@ehb.be'
        }
    }

    # ── Collector unavailable ──────────────────────────────────────────────────
    Context 'Collector reports service unavailable' {

        BeforeEach {
            Mock Invoke-RemoteCollector { New-FakeCollectorResult -Available $false }
        }

        It 'Skips Invoke-RemotePester when collector is unavailable' {
            Invoke-Stu
            Should -Invoke Invoke-RemotePester -Times 0 -Exactly
        }

        It 'Still returns a summary (zero-grade) with no Error' {
            $Result = Invoke-Stu
            $Result.Error   | Should -BeNullOrEmpty
            $Result.Summary | Should -Not -BeNullOrEmpty
        }
    }

    # ── Session connection failure ─────────────────────────────────────────────
    Context 'New-RemoteSession throws' {

        BeforeEach {
            Mock New-RemoteSession { throw 'Connection refused' }
        }

        It 'Returns an error result when session creation fails' {
            $Result = Invoke-Stu
            $Result.Summary | Should -BeNullOrEmpty
            $Result.Error   | Should -Match 'Connection refused'
        }

        It 'Logs an Error when session creation fails' {
            Invoke-Stu
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Error' }
        }
    }

    # ── Finally block: Close-RemoteSession failure ─────────────────────────────
    Context 'Close-RemoteSession throws in finally' {

        BeforeEach {
            Mock Close-RemoteSession { throw 'session already dead' }
        }

        It 'Still returns the summary when close fails' {
            $Result = Invoke-Stu
            $Result.Summary | Should -Not -BeNullOrEmpty
            $Result.Error   | Should -BeNullOrEmpty
        }

        It 'Logs a Warning when close fails' {
            Invoke-Stu
            Should -Invoke Write-Log -ParameterFilter {
                $Level -eq 'Warning' -and $Message -match 'Failed to close session'
            }
        }
    }

    # ── KeyFilePath pass-through ───────────────────────────────────────────────
    Context 'KeyFilePath parameter' {

        It 'Passes KeyFilePath to New-RemoteSession when specified' {
            Invoke-Stu -Overrides @{ KeyFilePath = 'C:\fake\id_rsa' }
            Should -Invoke New-RemoteSession -ParameterFilter { $KeyFilePath -eq 'C:\fake\id_rsa' }
        }

        It 'Does not include KeyFilePath in session params when not specified' {
            Invoke-Stu
            Should -Invoke New-RemoteSession -Times 1 -Exactly
        }
    }

    # ── TargetCredentials pass-through ─────────────────────────────────────────
    Context 'TargetCredentials parameter' {

        It 'Passes the credential to New-RemoteSession when provided' {
            $FakeCredStr = 'unit-test-placeholder'
            $FakeCred = [System.Management.Automation.PSCredential]::new(
                'admin',
                (ConvertTo-SecureString $FakeCredStr -AsPlainText -Force)
            )
            Invoke-Stu -Overrides @{ TargetCredentials = @{ WinSrv1 = $FakeCred } }
            Should -Invoke New-RemoteSession -ParameterFilter { $Credential -ne $null }
        }
    }

    # ── Export secondary formats ───────────────────────────────────────────────
    Context 'Exam definition with secondary export formats' {

        It 'Passes secondary formats alongside Json to Export-GradeSummary' {
            $Exam = New-FakeExam
            $Exam.Export = @{
                PrimaryFormat    = 'Json'
                SecondaryFormats = @('Excel', 'Csv')
            }
            Invoke-Stu -Overrides @{ Exam = $Exam }
            Should -Invoke Export-GradeSummary -ParameterFilter {
                $Format -contains 'Json' -and $Format -contains 'Excel' -and $Format -contains 'Csv'
            }
        }
    }

    Context 'Exam definition with no Export section' {

        It 'Defaults to Json-only export when Export key is absent' {
            $Exam = New-FakeExam
            $Exam.Remove('Export')
            Invoke-Stu -Overrides @{ Exam = $Exam }
            Should -Invoke Export-GradeSummary -ParameterFilter { $Format -contains 'Json' }
        }
    }

    # ── Output directory naming ────────────────────────────────────────────────
    Context 'Student output directory naming' {

        It 'Creates a directory path using the sanitised student name' {
            $Row = New-FakeRow -Student 'Jan van Appel'
            Invoke-Stu -Overrides @{ Row = $Row }
            Should -Invoke Export-GradeSummary -ParameterFilter {
                $OutputPath -like '*Jan_van_Appel*'
            }
        }

        It 'Strips special characters from the student name in the path' {
            $Row = New-FakeRow -Student 'Jan <Appel>'
            Invoke-Stu -Overrides @{ Row = $Row }
            Should -Invoke Export-GradeSummary -ParameterFilter {
                $OutputPath -notmatch '<|>'
            }
        }
    }

    # ── SaveCollectorData switch ───────────────────────────────────────────────
    Context 'SaveCollectorData switch' {

        It 'Creates collector-data folder with JSON and txt files when enabled' {
            Invoke-Stu -Overrides @{ SaveCollectorData = $true }
            $CollectorFiles = Get-ChildItem -Path $script:TempDir -Recurse -Filter '*-collector.json' -ErrorAction SilentlyContinue
            $CollectorFiles.Count | Should -Be 1
        }

        It 'Collector JSON file contains a valid Available field' {
            Invoke-Stu -Overrides @{ SaveCollectorData = $true }
            $CollectorFile = Get-ChildItem -Path $script:TempDir -Recurse -Filter '*-collector.json' | Select-Object -First 1
            $CollectorFile | Should -Not -BeNullOrEmpty
            $Data = Get-Content $CollectorFile.FullName -Raw | ConvertFrom-Json
            $Data.Available | Should -BeTrue
        }

        It 'Creates a human-readable .txt file alongside the JSON' {
            Invoke-Stu -Overrides @{ SaveCollectorData = $true }
            $TxtFiles = Get-ChildItem -Path $script:TempDir -Recurse -Filter '*-collector.txt' -ErrorAction SilentlyContinue
            $TxtFiles.Count | Should -Be 1
        }

        It 'Creates a Markdown .md file alongside the JSON' {
            Invoke-Stu -Overrides @{ SaveCollectorData = $true }
            $MdFiles = Get-ChildItem -Path $script:TempDir -Recurse -Filter '*-collector.md' -ErrorAction SilentlyContinue
            $MdFiles.Count | Should -Be 1
        }

        It 'Calls Format-CollectorDataMarkdown when SaveCollectorData is set' {
            Invoke-Stu -Overrides @{ SaveCollectorData = $true }
            Should -Invoke Format-CollectorDataMarkdown -Times 1 -Exactly
        }

        It 'Calls Format-CollectorData when SaveCollectorData is set' {
            Invoke-Stu -Overrides @{ SaveCollectorData = $true }
            Should -Invoke Format-CollectorData -Times 1 -Exactly
        }

        It 'Does not create collector-data folder when switch is absent' {
            Invoke-Stu
            $CollDataDirs = Get-ChildItem -Path $script:TempDir -Recurse -Directory -Filter 'collector-data' -ErrorAction SilentlyContinue
            $CollDataDirs.Count | Should -Be 0
        }

        It 'Does not call Format-CollectorData when SaveCollectorData is absent' {
            Invoke-Stu
            Should -Invoke Format-CollectorData -Times 0 -Exactly
        }
    }

    # ── StudentTimeout parameter validation ────────────────────────────────────
    Context 'StudentTimeout parameter validation' {

        It 'Accepts a valid StudentTimeout of 120' {
            { Invoke-Stu -Overrides @{ StudentTimeout = 120 } } | Should -Not -Throw
        }

        It 'Rejects StudentTimeout below 60' {
            $Params = @{
                Row           = New-FakeRow
                Exam          = New-FakeExam
                IpField       = 'ip'
                EmailField    = 'email'
                NameField     = 'student'
                ExamOutputDir = $script:TempDir
                StudentTimeout = 10
            }
            { Invoke-StudentEvaluation @Params } | Should -Throw '*less than the minimum allowed range of 60*'
        }

        It 'Rejects StudentTimeout above 3600' {
            $Params = @{
                Row           = New-FakeRow
                Exam          = New-FakeExam
                IpField       = 'ip'
                EmailField    = 'email'
                NameField     = 'student'
                ExamOutputDir = $script:TempDir
                StudentTimeout = 7200
            }
            { Invoke-StudentEvaluation @Params } | Should -Throw '*greater than the maximum allowed range of 3600*'
        }
    }

    # ── Category with no session ───────────────────────────────────────────────
    Context 'Category references a target with no session' {

        It 'Logs a warning and skips the category when target session is missing' {
            $Exam = New-FakeExam
            $Exam.Categories = @(
                @{
                    Name       = 'DNS'
                    Target     = 'NonExistentTarget'
                    Evaluation = 'Dns'
                    Collector  = 'Dns'
                    Variables  = @{}
                }
            )
            $Result = Invoke-Stu -Overrides @{ Exam = $Exam }
            $Result.Error | Should -BeNullOrEmpty
            Should -Invoke Write-Log -ParameterFilter {
                $Level -eq 'Warning' -and $Message -match 'no session'
            }
        }
    }

    # ── Multiple categories ────────────────────────────────────────────────────
    Context 'Exam with multiple categories' {

        It 'Calls Invoke-RemoteCollector once per category' {
            $Exam = New-FakeExam
            $Exam.Categories = @(
                @{
                    Name       = 'DNS'
                    Target     = 'WinSrv1'
                    Evaluation = 'Dns'
                    Collector  = 'Dns'
                    Variables  = @{}
                }
                @{
                    Name       = 'AD'
                    Target     = 'WinSrv1'
                    Evaluation = 'Ad'
                    Collector  = 'Ad'
                    Variables  = @{}
                }
            )
            Invoke-Stu -Overrides @{ Exam = $Exam }
            Should -Invoke Invoke-RemoteCollector -Times 2 -Exactly
        }

        It 'Calls Invoke-RemotePester once per available category' {
            $Exam = New-FakeExam
            $Exam.Categories = @(
                @{
                    Name       = 'DNS'
                    Target     = 'WinSrv1'
                    Evaluation = 'Dns'
                    Collector  = 'Dns'
                    Variables  = @{}
                }
                @{
                    Name       = 'AD'
                    Target     = 'WinSrv1'
                    Evaluation = 'Ad'
                    Collector  = 'Ad'
                    Variables  = @{}
                }
            )
            Invoke-Stu -Overrides @{ Exam = $Exam }
            Should -Invoke Invoke-RemotePester -Times 2 -Exactly
        }
    }

    # ── EvaluationsPath parameter ──────────────────────────────────────────────
    Context 'EvaluationsPath parameter' {

        It 'Passes EvaluationsPath to Invoke-RemoteSetup when specified' {
            Invoke-Stu -Overrides @{ EvaluationsPath = '/custom/evals' }
            Should -Invoke Invoke-RemoteSetup -ParameterFilter { $EvaluationsPath -eq '/custom/evals' }
        }

        It 'Passes EvaluationsPath to Invoke-RemotePester when specified' {
            Invoke-Stu -Overrides @{ EvaluationsPath = '/custom/evals' }
            Should -Invoke Invoke-RemotePester -ParameterFilter { $EvaluationsPath -eq '/custom/evals' }
        }

        It 'Does not pass EvaluationsPath when not specified' {
            Invoke-Stu
            Should -Invoke Invoke-RemoteSetup -ParameterFilter { -not $EvaluationsPath }
        }

        It 'Does not pass EvaluationsPath to Invoke-RemotePester when not specified' {
            Invoke-Stu
            Should -Invoke Invoke-RemotePester -ParameterFilter { -not $EvaluationsPath }
        }
    }
}
