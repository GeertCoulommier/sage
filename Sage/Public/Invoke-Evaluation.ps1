#Requires -Version 7.5
<#
.SYNOPSIS
    Main orchestrator — runs the full SAGE evaluation pipeline for every
    student in a CSV roster.
.DESCRIPTION
    Loads the exam definition, reads the CSV roster, and for each student:
      1. Connects to every target defined in exam.psd1 via SSH.
      2. Runs Invoke-RemoteSetup on each session (install Pester, copy scripts).
      3. For each evaluation category:
         a. Runs the collector to gather data from the remote VM.
         b. If the service is available, runs the Pester evaluation.
         c. Converts Pester results to Sage.TestResult objects.
         d. If unavailable, creates zero-grade TestResults.
      4. Aggregates all TestResults into a Sage.StudentGradeSummary.
      5. Exports results to JSON (and optionally Excel/CSV).
      6. Closes all remote sessions.

    Progress is reported via Write-Progress.  A _summary.json file
    (containing count, timing, and errors — but no grades) is written
    to the results root directory when the pipeline completes.

    When ThrottleLimit is greater than 1, students are processed in parallel
    using ForEach-Object -Parallel.  Each parallel runspace imports the SAGE
    module independently and calls Set-SageLogPath to wire up the shared log
    file, then delegates all per-student work to Invoke-StudentEvaluation.
    Sequential processing uses the same delegate for consistency.
    Write-Log uses a named mutex for thread-safe JSONL file writes.
    Progress reporting is suppressed in parallel mode (per-student
    Write-Progress would race across runspaces).
.PARAMETER ExamPath
    Path to the exam.psd1 definition file.
.PARAMETER RosterPath
    Path to the CSV file listing students (roster).
.PARAMETER OutputDir
    Root directory for results.  Defaults to 'results' under the module root.
    A subfolder named after the exam is created automatically.
.PARAMETER ThrottleLimit
    Number of students to process in parallel.  Default 1 (sequential).
    Values greater than 1 enable ForEach-Object -Parallel execution.
.PARAMETER ExcelTemplatePath
    Optional path to an Excel template (.xlsx) used by Export-GradeSummary.
    Not yet wired — reserved for future use.
.PARAMETER KeyFilePath
    Path to an SSH private key file for authentication.  Passed to every
    New-RemoteSession call.
.PARAMETER SaveCollectorData
    When specified, each raw CollectorResult is exported to a JSON file
    inside a 'collector-data' sub-folder under the student output directory.
    Filenames follow the pattern '<TargetName>-<CategoryName>-collector.json'.
    Useful for post-run inspection and debugging of collected data.
.PARAMETER StudentTimeout
    Maximum number of seconds allowed per student before the pipeline aborts
    that student and moves on to the next.  Default is 600 (10 minutes).
    Prevents hung SSH connections from blocking the entire pipeline.
.OUTPUTS
    [PSCustomObject[]] — array of Sage.StudentGradeSummary for every student.
.EXAMPLE
    $params = @{
        ExamPath   = './data/exams/OSII-25-08/exam.psd1'
        RosterPath = './rosters/students.csv'
    }
    Invoke-Evaluation @params
.EXAMPLE
    Invoke-Evaluation -ExamPath './data/exams/_example/exam.psd1' -RosterPath './students.csv' -KeyFilePath '~/.ssh/id_rsa'
.EXAMPLE
    $params = @{
        ExamPath          = './data/exams/live-test/exam.psd1'
        RosterPath        = './data/exams/live-test/roster.csv'
        OutputDir         = './data/output'
        KeyFilePath       = "$env:USERPROFILE\.ssh\id_rsa"
        SaveCollectorData = $true
    }
    Invoke-Evaluation @params
#>
function Invoke-Evaluation {
    [CmdletBinding()]
    [OutputType('Sage.StudentGradeSummary')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExcelTemplatePath',
        Justification = 'Reserved for future Excel export wiring')]
    param(
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })]            [string] $ExamPath,
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })]            [string] $RosterPath,
        [Parameter()]                                                                      [string] $OutputDir,
        [Parameter()]         [ValidateRange(1, 16)]                                          [int] $ThrottleLimit = 10,
        [Parameter()]                                                                      [string] $ExcelTemplatePath,
        [Parameter()]                                                                      [string] $KeyFilePath,
        [Parameter()]                                                                      [switch] $SaveCollectorData,
        [Parameter()]         [ValidateRange(60, 3600)]                                       [int] $StudentTimeout = 600
    )

    $ErrorActionPreference = 'Stop'

    # ── Load exam definition ───────────────────────────────────────────────────
    $Exam = Import-ExamDefinition -Path $ExamPath

    # ── Determine output root ──────────────────────────────────────────────────
    if (-not $OutputDir) {
        $OutputDir = Join-Path $PSScriptRoot '..' 'data' 'output'
    }
    $ExamOutputDir = Join-Path $OutputDir ($Exam.Name -replace '[^\w\s\-.]', '' -replace '\s+', '_')
    if (-not (Test-Path $ExamOutputDir)) {
        New-Item -Path $ExamOutputDir -ItemType Directory -Force | Out-Null
    }

    # ── Configure pipeline log file ───────────────────────────────────────────
    # $script:LogPath targets the module scope — Write-Log reads this variable
    # to append JSONL lines.  It is cleared after the pipeline finishes.
    #
    # Log is written to $env:TEMP first to avoid cloud-sync conflicts (e.g.
    # Proton Drive intercepting an in-progress file mid-write).  The completed
    # log is moved to <module-root>/data/logs/ at the very end of the pipeline.
    $ModuleRoot = Join-Path $PSScriptRoot '..'
    $LogDir = Join-Path $ModuleRoot 'data' 'logs'
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    $LogStamp = [datetime]::Now.ToString('yyyyMMdd-HHmmss')
    $SafeExamName = $Exam.Name -replace '\s+', '-' -replace '[^\w\-.]', ''
    $LogFileName = "${LogStamp}-${SafeExamName}.jsonl"
    $TempLogPath = Join-Path ([System.IO.Path]::GetTempPath()) $LogFileName
    $FinalLogPath = Join-Path $LogDir $LogFileName
    $script:LogPath = $TempLogPath

    # ── Read roster CSV ────────────────────────────────────────────────────────
    $Roster = $Exam.Roster
    $CsvParams = @{
        Path      = $RosterPath
        Delimiter = if ($Roster -and $Roster.Delimiter) { $Roster.Delimiter } else { ',' }
        Encoding  = 'UTF8'
    }
    $Students = @(Import-Csv @CsvParams)

    if ($Students.Count -eq 0) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    "Roster CSV '$RosterPath' contains no student rows."),
                'InvokeEvaluation.EmptyRoster',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $RosterPath
            )
        )
    }

    # ── Resolve field names ────────────────────────────────────────────────────
    $IpField = if ($Roster -and $Roster.IPField) { $Roster.IPField } else { 'ip' }
    $EmailField = if ($Roster -and $Roster.EmailField) { $Roster.EmailField } else { 'email' }
    $NameField = if ($Roster -and $Roster.NameField) { $Roster.NameField } else { 'student' }

    $LogParams = @{
        Level    = 'Info'
        Category = 'Pipeline'
        Message  = "Pipeline started: exam='$($Exam.Name)', students=$($Students.Count), categories=$($Exam.Categories.Count)."
    }
    Write-Log @LogParams

    # ── Resolve credentials per target (once) ──────────────────────────────────
    # When KeyFilePath is provided, vault credentials are optional — SSH key auth
    # handles authentication without a credential object.
    # Cache by credential name so the same vault entry is not prompted twice.
    $CredentialCache = @{}
    $TargetCredentials = @{}
    foreach ($TargetName in $Exam.Targets.Keys) {
        $Target = $Exam.Targets[$TargetName]
        $CredName = if ($Target.CredentialSecret) { $Target.CredentialSecret }
        elseif ($Exam.DefaultCredentialSecret) { $Exam.DefaultCredentialSecret }
        else { $null }
        if ($CredName) {
            if ($CredentialCache.ContainsKey($CredName)) {
                $TargetCredentials[$TargetName] = $CredentialCache[$CredName]
            }
            else {
                try {
                    $Cred = Import-Credential -Name $CredName -AllowPrompt
                    $CredentialCache[$CredName] = $Cred
                    $TargetCredentials[$TargetName] = $Cred
                }
                catch {
                    if ($KeyFilePath) {
                        $LogParams = @{
                            Level    = 'Warning'
                            Category = 'Setup'
                            Message  = "Could not load credential '$CredName' for target '$TargetName' — proceeding with SSH key auth only. ($($_.Exception.Message))"
                        }
                        Write-Log @LogParams
                    }
                    else {
                        throw
                    }
                }
            }
        }
    }

    # ── Clean up stale PSSessions ─────────────────────────────────────────────
    # After a crash or forced termination, orphaned SSH sessions may linger in
    # Broken/Disconnected state.  Remove them before starting new work.
    $StaleSessions = @(Get-PSSession | Where-Object { $_.State -ne 'Opened' })
    if ($StaleSessions.Count -gt 0) {
        $LogParams = @{
            Level    = 'Warning'
            Category = 'Session'
            Message  = "Removing $($StaleSessions.Count) stale PSSession(s) before pipeline start."
        }
        Write-Log @LogParams
        $StaleSessions | Remove-PSSession -ErrorAction SilentlyContinue
    }

    # ── Process each student ───────────────────────────────────────────────────
    $PipelineStart = [datetime]::Now
    $AllSummaries = [System.Collections.Generic.List[object]]::new()
    $PipelineErrors = [System.Collections.Generic.List[string]]::new()

    if ($ThrottleLimit -gt 1) {
        # ── Parallel student processing ────────────────────────────────────────
        # Each student runs in a separate runspace with its own module copy.
        # Write-Log's named mutex ensures thread-safe JSONL file writes.
        # Write-Progress is skipped — per-student bars would race.
        $ModulePath = (Join-Path $PSScriptRoot '..' 'Sage.psd1') |
            Resolve-Path -ErrorAction Stop |
            Select-Object -ExpandProperty Path
        $SaveCollectorDataFlag = [bool]$SaveCollectorData

        $LogParams = @{
            Level    = 'Info'
            Category = 'Pipeline'
            Message  = "Parallel mode: ThrottleLimit=$ThrottleLimit for $($Students.Count) students."
        }
        Write-Log @LogParams

        $ParallelResults = $Students | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            $Row         = $_
            $Exam        = $using:Exam
            $IpField     = $using:IpField
            $EmailField  = $using:EmailField
            $NameField   = $using:NameField
            $TargetCreds = $using:TargetCredentials
            $KeyFile     = $using:KeyFilePath
            $SaveColl    = $using:SaveCollectorDataFlag
            $ExamOutDir  = $using:ExamOutputDir
            $Timeout     = $using:StudentTimeout
            $LogPath     = $using:TempLogPath
            $ModPath     = $using:ModulePath

            # Each runspace gets its own fresh module scope after Import-Module.
            # Set-SageLogPath (Public) writes $script:LogPath into that new scope
            # so Write-Log can append to the shared log file.  All other private
            # functions (Write-Log, Invoke-RemoteSetup, etc.) are called from
            # inside Invoke-StudentEvaluation (a module function) where they are
            # accessible — not directly from this scriptblock where they are not.
            # See Public/Set-SageLogPath.ps1 and Public/Invoke-StudentEvaluation.ps1.
            Import-Module $ModPath -Force
            Set-SageLogPath -Path $LogPath

            $StuParams = @{
                Row               = $Row
                Exam              = $Exam
                IpField           = $IpField
                EmailField        = $EmailField
                NameField         = $NameField
                TargetCredentials = $TargetCreds
                ExamOutputDir     = $ExamOutDir
                StudentTimeout    = $Timeout
            }
            if ($KeyFile)  { $StuParams['KeyFilePath']       = $KeyFile }
            if ($SaveColl) { $StuParams['SaveCollectorData'] = $true }

            Invoke-StudentEvaluation @StuParams
        }

        # Collect results from parallel output
        foreach ($ParResult in $ParallelResults) {
            if ($ParResult.Summary) {
                $AllSummaries.Add($ParResult.Summary)
            }
            if ($ParResult.Error) {
                $PipelineErrors.Add($ParResult.Error)
            }
        }
    }
    else {

    # ── Sequential processing (ThrottleLimit = 1) ─────────────────────────
    # Private helpers are accessible here because this code runs inside a
    # module function (Invoke-Evaluation).  Invoke-StudentEvaluation is called
    # for each student so that session, collector, and grading logic lives in
    # one place shared with the parallel path.
    $StudentIndex = 0

    foreach ($Row in $Students) {
        $StudentIndex++

        # ── Progress tracking ──────────────────────────────────────────────────
        $StudentName = $Row.$NameField
        $ProgressParams = @{
            Activity        = "SAGE Evaluation: $($Exam.Name)"
            Status          = "Student $StudentIndex of $($Students.Count): $StudentName"
            PercentComplete = [int](($StudentIndex / $Students.Count) * 100)
        }
        Write-Progress @ProgressParams

        $LogParams = @{
            Level    = 'Info'
            Category = 'Pipeline'
            Message  = "Processing student $StudentIndex/$($Students.Count): '$StudentName' (IP: $($Row.$IpField))."
        }
        Write-Log @LogParams

        $StuParams = @{
            Row               = $Row
            Exam              = $Exam
            IpField           = $IpField
            EmailField        = $EmailField
            NameField         = $NameField
            TargetCredentials = $TargetCredentials
            ExamOutputDir     = $ExamOutputDir
            StudentTimeout    = $StudentTimeout
        }
        if ($KeyFilePath)       { $StuParams['KeyFilePath']       = $KeyFilePath }
        if ($SaveCollectorData) { $StuParams['SaveCollectorData'] = $true }

        $StuResult = Invoke-StudentEvaluation @StuParams

        if ($StuResult.Summary) {
            $AllSummaries.Add($StuResult.Summary)
        }
        if ($StuResult.Error) {
            $PipelineErrors.Add($StuResult.Error)
        }
    }

    } # end else (sequential processing)

    Write-Progress -Activity "SAGE Evaluation: $($Exam.Name)" -Completed

    # ── Write pipeline summary ─────────────────────────────────────────────────
    $PipelineDuration = ([datetime]::Now - $PipelineStart)
    $SummaryDoc = [ordered]@{
        _type                = 'Sage.PipelineSummary'
        ExamName             = $Exam.Name
        CompletedAt          = [datetime]::Now.ToString('o')
        DurationSeconds      = [Math]::Round($PipelineDuration.TotalSeconds, 1)
        StudentsProcessed    = $AllSummaries.Count
        StudentsInRoster     = $Students.Count
        StudentsFailed       = $PipelineErrors.Count
        CategoriesPerStudent = $Exam.Categories.Count
        Errors               = $PipelineErrors.ToArray()
    }

    $SummaryPath = Join-Path $ExamOutputDir '_summary.json'
    $SummaryDoc | ConvertTo-Json -Depth 5 | Set-Content -Path $SummaryPath -Encoding utf8

    $LogParams = @{
        Level    = 'Info'
        Category = 'Pipeline'
        Message  = "Pipeline finished: $($AllSummaries.Count)/$($Students.Count) students processed in $($PipelineDuration.TotalSeconds.ToString('F1'))s. Summary: $SummaryPath"
        Data     = @{
            Duration  = $PipelineDuration.TotalSeconds
            Processed = $AllSummaries.Count
            Errors    = $PipelineErrors.Count
        }
    }
    Write-Log @LogParams

    # ── Release log file handle + move to final location ──────────────────────
    # Clear the module-scope log path before the Move-Item so Write-Log stops
    # appending to the temp file during the move.
    $script:LogPath = $null
    if (Test-Path -LiteralPath $TempLogPath) {
        try {
            Move-Item -Path $TempLogPath -Destination $FinalLogPath -Force
        }
        catch {
            Write-Warning "[Pipeline] Could not move log '$TempLogPath' to '$FinalLogPath': $($_.Exception.Message)"
        }
    }

    $AllSummaries.ToArray()
}
