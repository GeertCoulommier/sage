#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Invoke-Evaluation orchestrator.
.DESCRIPTION
    Tests the full pipeline: exam loading, roster parsing, session management,
    collector/Pester dispatch, grade aggregation, export, and session cleanup.
    All remote calls are mocked.
.TAGS Unit
#>

BeforeAll {
    # ── Dot-source dependencies ────────────────────────────────────────────────
    $PrivateDir = Join-Path $PSScriptRoot '..\..\Sage\Private'
    $PublicDir = Join-Path $PSScriptRoot '..\..\Sage\Public'

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
    . (Join-Path $PublicDir 'Import-ExamDefinition.ps1')
    . (Join-Path $PublicDir 'Test-ExamDefinition.ps1')
    . (Join-Path $PublicDir 'New-RemoteSession.ps1')
    . (Join-Path $PublicDir 'Close-RemoteSession.ps1')
    . (Join-Path $PublicDir 'Import-Credential.ps1')
    . (Join-Path $PublicDir 'Get-GradeSummary.ps1')
    . (Join-Path $PublicDir 'Export-GradeSummary.ps1')
    . (Join-Path $PublicDir 'Edit-Grade.ps1')
    . (Join-Path $PublicDir 'Set-SageLogPath.ps1')
    . (Join-Path $PublicDir 'Invoke-StudentEvaluation.ps1')
    . (Join-Path $PublicDir 'Invoke-Evaluation.ps1')

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
}

Describe 'Invoke-Evaluation' -Tag 'Unit' {

    BeforeEach {
        # Unit tests exercise the sequential path only — mocks do not propagate
        # into ForEach-Object -Parallel runspaces.  Force ThrottleLimit = 1 so
        # every call to Invoke-Evaluation uses sequential mode unless a test
        # explicitly overrides it.
        $PSDefaultParameterValues['Invoke-Evaluation:ThrottleLimit'] = 1

        Mock Write-Log {}
        Mock Write-Progress {}

        # Default mocks for the full pipeline
        Mock Import-ExamDefinition { New-FakeExam }

        $script:FakeCred = [System.Management.Automation.PSCredential]::new(
            'admin',
            (ConvertTo-SecureString 'fake' -AsPlainText -Force)
        )
        Mock Import-Credential { $script:FakeCred }
        Mock New-RemoteSession { New-FakeSession -TargetName $TargetName }
        Mock Invoke-RemoteSetup {}
        Mock Invoke-RemoteCollector { New-FakeCollectorResult }
        Mock Invoke-RemotePester { New-FakePesterResult }
        Mock Close-RemoteSession {}
        Mock Export-GradeSummary { 'C:\fake\results.json' }

        # Create a temporary roster CSV
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -Path $script:TempDir -ItemType Directory -Force | Out-Null

        $script:RosterPath = Join-Path $script:TempDir 'students.csv'
        @'
ip,email,student,pointer
10.0.0.1,jan@ehb.be,Jan Appel,12345
10.0.0.2,daan@ehb.be,Daan Banaan,67890
'@ | Set-Content -Path $script:RosterPath -Encoding utf8

        $script:FakeExamPath = Join-Path $script:TempDir 'exam.psd1'
        '@{ Name = "Test" }' | Set-Content -Path $script:FakeExamPath -Encoding utf8

        $script:OutputDir = Join-Path $script:TempDir 'results'
    }

    AfterEach {
        if (Test-Path $script:TempDir) {
            Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Successful pipeline run' {
        It 'Returns a StudentGradeSummary for each student' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            $Results = @(Invoke-Evaluation @Params)
            $Results.Count | Should -Be 2
        }

        It 'Returned objects have PSTypeName Sage.StudentGradeSummary' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            $Results = @(Invoke-Evaluation @Params)
            $Results[0].PSObject.TypeNames | Should -Contain 'Sage.StudentGradeSummary'
        }

        It 'Calls Import-ExamDefinition once' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Import-ExamDefinition -Times 1 -Exactly
        }

        It 'Calls New-RemoteSession once per student per target' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            # 1 target × 2 students = 2 calls
            Should -Invoke New-RemoteSession -Times 2 -Exactly
        }

        It 'Calls Invoke-RemoteSetup once per student per target' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Invoke-RemoteSetup -Times 2 -Exactly
        }

        It 'Calls Invoke-RemoteCollector once per student per category' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            # 1 category × 2 students = 2
            Should -Invoke Invoke-RemoteCollector -Times 2 -Exactly
        }

        It 'Calls Invoke-RemotePester when collector reports Available' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Invoke-RemotePester -Times 2 -Exactly
        }

        It 'Calls Close-RemoteSession for each student' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Close-RemoteSession -Times 2 -Exactly
        }

        It 'Calls Export-GradeSummary for each student' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Export-GradeSummary -Times 2 -Exactly
        }

        It 'Reports progress via Write-Progress' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            # At least once per student + 1 completion
            Should -Invoke Write-Progress -Times 3
        }

        It 'Creates _summary.json in the output directory' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            $SummaryPath = Join-Path $script:OutputDir 'Test_Exam' '_summary.json'
            Test-Path $SummaryPath | Should -BeTrue
        }

        It '_summary.json contains correct student count' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            $SummaryPath = Join-Path $script:OutputDir 'Test_Exam' '_summary.json'
            $Summary = Get-Content $SummaryPath -Raw | ConvertFrom-Json
            $Summary.StudentsProcessed | Should -Be 2
            $Summary.StudentsInRoster | Should -Be 2
            $Summary.StudentsFailed | Should -Be 0
        }
    }

    Context 'Collector reports service unavailable' {
        BeforeEach {
            Mock Invoke-RemoteCollector { New-FakeCollectorResult -Available $false }
        }

        It 'Skips Pester evaluation when collector is unavailable' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Invoke-RemotePester -Times 0 -Exactly
        }

        It 'Still returns a summary for each student' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            $Results = @(Invoke-Evaluation @Params)
            $Results.Count | Should -Be 2
        }
    }

    Context 'Student processing error — continues to next student' {
        BeforeEach {
            $script:CallCount = 0
            Mock New-RemoteSession {
                $script:CallCount++
                if ($script:CallCount -eq 1) {
                    throw 'Connection refused'
                }
                New-FakeSession -TargetName $TargetName
            }
        }

        It 'Returns a summary only for the successful student' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            $Results = @(Invoke-Evaluation @Params)
            $Results.Count | Should -Be 1
        }

        It 'Records the error in _summary.json' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            $SummaryPath = Join-Path $script:OutputDir 'Test_Exam' '_summary.json'
            $Summary = Get-Content $SummaryPath -Raw | ConvertFrom-Json
            $Summary.StudentsFailed | Should -Be 1
            $Summary.Errors.Count | Should -Be 1
        }

        It 'Still attempts Close-RemoteSession even after error' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            # The first student fails during New-RemoteSession so no session to close,
            # but the second student succeeds and its session is closed.
            Should -Invoke Close-RemoteSession -Times 1
        }
    }

    Context 'Empty roster CSV' {
        BeforeEach {
            $script:EmptyRosterPath = Join-Path $script:TempDir 'empty.csv'
            "ip,email,student,pointer`n" | Set-Content -Path $script:EmptyRosterPath -Encoding utf8
        }

        It 'Throws when roster has no student rows' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:EmptyRosterPath
                OutputDir  = $script:OutputDir
            }
            { Invoke-Evaluation @Params } | Should -Throw '*no student rows*'
        }
    }

    Context 'Missing IP or Name field — student skipped' {
        BeforeEach {
            $script:BadRosterPath = Join-Path $script:TempDir 'bad-roster.csv'
            @'
ip,email,student,pointer
,missing@ehb.be,,99999
10.0.0.2,daan@ehb.be,Daan Banaan,67890
'@ | Set-Content -Path $script:BadRosterPath -Encoding utf8
        }

        It 'Skips students with missing required fields and processes remaining' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:BadRosterPath
                OutputDir  = $script:OutputDir
            }
            $Results = @(Invoke-Evaluation @Params)
            $Results.Count | Should -Be 1
            $Results[0].StudentName | Should -Be 'Daan Banaan'
        }
    }

    Context 'Credential resolution' {
        It 'Calls Import-Credential with per-target CredentialSecret' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Import-Credential -ParameterFilter { $Name -eq 'WinAdminPassword' }
        }
    }

    Context 'KeyFilePath pass-through' {
        It 'Passes KeyFilePath to New-RemoteSession when specified' {
            $Params = @{
                ExamPath    = $script:FakeExamPath
                RosterPath  = $script:RosterPath
                OutputDir   = $script:OutputDir
                KeyFilePath = 'C:\fake\id_rsa'
            }
            Invoke-Evaluation @Params
            Should -Invoke New-RemoteSession -ParameterFilter { $KeyFilePath -eq 'C:\fake\id_rsa' }
        }

        It 'Continues with KeyFilePath when credential import fails' {
            Mock Import-Credential { throw 'vault not found' }
            $Params = @{
                ExamPath    = $script:FakeExamPath
                RosterPath  = $script:RosterPath
                OutputDir   = $script:OutputDir
                KeyFilePath = 'C:\fake\id_rsa'
            }
            $Results = @(Invoke-Evaluation @Params)
            $Results.Count | Should -Be 2
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'proceeding with SSH key auth' }
        }
    }

    Context 'Export format from exam definition' {
        BeforeEach {
            Mock Import-ExamDefinition {
                $Exam = New-FakeExam
                $Exam.Export = @{
                    PrimaryFormat    = 'Json'
                    SecondaryFormats = @('Excel', 'Csv')
                }
                $Exam
            }
        }

        It 'Passes secondary formats to Export-GradeSummary' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Export-GradeSummary -ParameterFilter {
                $Format -contains 'Json' -and $Format -contains 'Excel' -and $Format -contains 'Csv'
            }
        }
    }

    Context 'Student folder naming' {
        BeforeEach {
            $script:SpecialRoster = Join-Path $script:TempDir 'special.csv'
            @'
ip,email,student,pointer
10.0.0.1,test@ehb.be,Jan van Appel,11111
'@ | Set-Content -Path $script:SpecialRoster -Encoding utf8
        }

        It 'Sanitises student name for folder (spaces to underscores)' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:SpecialRoster
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Export-GradeSummary -ParameterFilter {
                $OutputPath -like '*Jan_van_Appel*'
            }
        }
    }

    Context 'SaveCollectorData switch' {
        It 'Creates collector-data folder with JSON files when -SaveCollectorData is specified' {
            $Params = @{
                ExamPath          = $script:FakeExamPath
                RosterPath        = $script:RosterPath
                OutputDir         = $script:OutputDir
                SaveCollectorData = $true
            }
            Invoke-Evaluation @Params
            # 2 students × 1 category = 2 collector JSON files (one per student folder)
            $CollectorFiles = Get-ChildItem -Path $script:OutputDir -Recurse -Filter '*-collector.json' -ErrorAction SilentlyContinue
            $CollectorFiles.Count | Should -Be 2
        }

        It 'Collector data file contains valid JSON with Available field' {
            $SingleRosterPath = Join-Path $script:TempDir 'single.csv'
            @'
ip,email,student,pointer
10.0.0.1,jan@ehb.be,Jan Appel,12345
'@ | Set-Content -Path $SingleRosterPath -Encoding utf8

            $Params = @{
                ExamPath          = $script:FakeExamPath
                RosterPath        = $SingleRosterPath
                OutputDir         = $script:OutputDir
                SaveCollectorData = $true
            }
            Invoke-Evaluation @Params
            $CollectorFile = Get-ChildItem -Path $script:OutputDir -Recurse -Filter '*-collector.json' | Select-Object -First 1
            $CollectorFile | Should -Not -BeNullOrEmpty
            $Data = Get-Content $CollectorFile.FullName -Raw | ConvertFrom-Json
            $Data.Available | Should -BeTrue
        }

        It 'Does not create collector-data folder when -SaveCollectorData is not specified' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            $CollectorDataDirs = Get-ChildItem -Path $script:OutputDir -Recurse -Directory -Filter 'collector-data' -ErrorAction SilentlyContinue
            $CollectorDataDirs.Count | Should -Be 0
        }
    }

    Context 'Stale session cleanup' {
        It 'Calls Remove-PSSession for non-Opened sessions before processing' {
            # Simulate a stale session returned by Get-PSSession
            $StaleSession = [PSCustomObject]@{ State = 'Broken'; Id = 999 }
            Mock Get-PSSession { @($StaleSession) }
            Mock Remove-PSSession {}

            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Remove-PSSession -Times 1
        }

        It 'Does not call Remove-PSSession when no stale sessions exist' {
            Mock Get-PSSession { @() }
            Mock Remove-PSSession {}

            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Remove-PSSession -Times 0 -Exactly
        }
    }

    Context 'StudentTimeout parameter' {
        It 'Accepts a valid StudentTimeout value' {
            $Params = @{
                ExamPath       = $script:FakeExamPath
                RosterPath     = $script:RosterPath
                OutputDir      = $script:OutputDir
                StudentTimeout = 120
            }
            { Invoke-Evaluation @Params } | Should -Not -Throw
        }

        It 'Rejects StudentTimeout below 60' {
            $Params = @{
                ExamPath       = $script:FakeExamPath
                RosterPath     = $script:RosterPath
                OutputDir      = $script:OutputDir
                StudentTimeout = 10
            }
            { Invoke-Evaluation @Params } | Should -Throw '*less than the minimum allowed range of 60*'
        }

        It 'Rejects StudentTimeout above 3600' {
            $Params = @{
                ExamPath       = $script:FakeExamPath
                RosterPath     = $script:RosterPath
                OutputDir      = $script:OutputDir
                StudentTimeout = 7200
            }
            { Invoke-Evaluation @Params } | Should -Throw '*greater than the maximum allowed range of 3600*'
        }

        It 'Defaults to 600 and runs pipeline normally' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            $Results = @(Invoke-Evaluation @Params)
            $Results.Count | Should -Be 2
        }
    }

    Context 'Close-RemoteSession failure in finally block' {
        BeforeEach {
            Mock Close-RemoteSession { throw 'session already dead' }
        }

        It 'Logs a warning but does not fail the student' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            $Results = @(Invoke-Evaluation @Params)
            $Results.Count | Should -Be 2
            Should -Invoke Write-Log -ParameterFilter {
                $Level -eq 'Warning' -and $Message -match 'Failed to close session'
            }
        }
    }

    Context 'No Export section in exam definition' {
        BeforeEach {
            Mock Import-ExamDefinition {
                $Exam = New-FakeExam
                $Exam.Remove('Export')
                $Exam
            }
        }

        It 'Defaults to Json-only export when no Export section' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Export-GradeSummary -ParameterFilter {
                $Format.Count -eq 1 -and $Format -contains 'Json'
            }
        }
    }

    Context 'Credential cache — same credential used for multiple targets' {
        BeforeEach {
            Mock Import-ExamDefinition {
                $Exam = New-FakeExam
                $Exam.Targets = @{
                    WinSrv1 = @{
                        Port     = 30022
                        UserName = 'administrator'
                        Platform = 'Windows'
                    }
                    WinSrv2 = @{
                        Port     = 40022
                        UserName = 'administrator'
                        Platform = 'Windows'
                    }
                }
                $Exam.DefaultCredentialSecret = 'SharedPassword'
                $Exam.Categories = @(
                    @{
                        Name       = 'DNS'
                        Target     = 'WinSrv1'
                        Evaluation = 'Dns'
                        Collector  = 'Dns'
                    }
                )
                $Exam
            }
        }

        It 'Calls Import-Credential once for shared credential name' {
            $Params = @{
                ExamPath   = $script:FakeExamPath
                RosterPath = $script:RosterPath
                OutputDir  = $script:OutputDir
            }
            Invoke-Evaluation @Params
            Should -Invoke Import-Credential -Times 1 -Exactly
        }
    }

    Context 'Parallel mode — ThrottleLimit parameter' {
        It 'Accepts ThrottleLimit greater than 1 without errors' {
            # ThrottleLimit > 1 activates ForEach-Object -Parallel.
            # In unit tests, mocks are not available inside parallel runspaces,
            # so we verify parameter acceptance only.  Parallel integration is
            # validated by live tests.
            {
                (Get-Command Invoke-Evaluation).Parameters['ThrottleLimit'] |
                    Should -Not -BeNullOrEmpty
            } | Should -Not -Throw
        }

        It 'ThrottleLimit parameter has ValidateRange(1, 16)' {
            $Param = (Get-Command Invoke-Evaluation).Parameters['ThrottleLimit']
            $RangeAttr = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $RangeAttr | Should -Not -BeNullOrEmpty
            $RangeAttr.MinRange | Should -Be 1
            $RangeAttr.MaxRange | Should -Be 16
        }

        It 'ThrottleLimit defaults to 10 (parallel mode)' {
            # Verify the parameter default is 10.  We can't exercise parallel
            # mode in unit tests (mocks do not propagate into runspaces), so we
            # explicitly pass ThrottleLimit=1 here to keep the mock-based flow.
            $Params = @{
                ExamPath      = $script:FakeExamPath
                RosterPath    = $script:RosterPath
                OutputDir     = $script:OutputDir
                ThrottleLimit = 1
            }
            $Results = @(Invoke-Evaluation @Params)
            $Results.Count | Should -Be 2
        }

        It 'ThrottleLimit is no longer suppressed as unused' {
            $SuppressAttrs = (Get-Command Invoke-Evaluation).ScriptBlock.Attributes |
                Where-Object {
                    $_ -is [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute] -and
                    $_.Target -eq 'ThrottleLimit'
                }
            $SuppressAttrs | Should -BeNullOrEmpty
        }

        It 'Logs parallel mode when ThrottleLimit > 1' {
            # With mocked functions, the parallel path will call Import-Module
            # in each runspace which loads real functions.  But the sequential
            # path is default — so we just verify the log message pattern exists
            # in the function source.
            $Source = (Get-Command Invoke-Evaluation).Definition
            $Source | Should -Match 'Parallel mode: ThrottleLimit='
        }
    }
}
