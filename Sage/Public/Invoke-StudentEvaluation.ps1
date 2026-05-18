#Requires -Version 7.5
<#
.SYNOPSIS
    Runs the full SAGE evaluation pipeline for a single student.
.DESCRIPTION
    Encapsulates the per-student work that Invoke-Evaluation performs for every
    row in the roster CSV:

      1. Resolves student identity fields from the CSV row.
      2. Connects to every target defined in the exam (New-RemoteSession).
      3. Sets up each session — installs Pester, copies scripts
         (Invoke-RemoteSetup).
      4. For each evaluation category:
           a. Runs the collector on the remote VM (Invoke-RemoteCollector).
           b. If the service is available, runs Pester (Invoke-RemotePester)
              and converts results to Sage.TestResult objects
              (ConvertTo-GradeSummary).
           c. If unavailable, creates a zero-grade result (New-GradeResult).
      5. Aggregates all results into a Sage.StudentGradeSummary
         (Get-GradeSummary).
      6. Exports results to disk (Export-GradeSummary).
      7. Closes all sessions (Close-RemoteSession).

    WHY THIS IS A PUBLIC FUNCTION
    ──────────────────────────────
    In PowerShell, ForEach-Object -Parallel executes each scriptblock in an
    independent runspace.  When a runspace calls Import-Module it creates a
    brand-new, isolated module scope.  Code in the scriptblock runs in user
    space — it can only call PUBLIC (exported) module functions.  Private
    helper functions (Write-Log, Invoke-RemoteSetup, Invoke-RemoteCollector,
    Invoke-RemotePester, ConvertTo-GradeSummary, New-GradeResult) are
    inaccessible directly from a scriptblock, but they ARE accessible from
    within a module function.

    By placing all per-student logic here (a Public function), the parallel
    scriptblock in Invoke-Evaluation only needs to:

        Import-Module $ModulePath -Force    # new module scope
        Set-SageLogPath -Path $LogPath      # wire up the log file
        Invoke-StudentEvaluation @params    # executes inside module scope ✓

    All private helper calls inside this function work because they execute
    within the module, not from an external scriptblock.

    This function is NOT intended for direct use in everyday grading workflows
    — use Invoke-Evaluation instead.  It is public by necessity, not by design
    intent.
.PARAMETER Row
    A PSCustomObject representing one row from the roster CSV, with properties
    for IP address, student name, email, etc.
.PARAMETER Exam
    Validated exam definition hashtable as returned by Import-ExamDefinition.
    Each target inside Exam.Targets may optionally include a HostName property
    to override the Row's IP field for that target.  When HostName is set on a
    target, that address is used for the SSH connection instead of $StudentIp.
    This enables multi-IP scenarios (e.g. the SAGE TUI, where each target VM
    has a distinct IP).
.PARAMETER IpField
    Name of the CSV column that holds the student's IP address or hostname.
.PARAMETER EmailField
    Name of the CSV column that holds the student's email address.
.PARAMETER NameField
    Name of the CSV column that holds the student's display name.
.PARAMETER TargetCredentials
    Hashtable of PSCredential objects keyed on target name (e.g. 'DC1').
    Passed through from Invoke-Evaluation's credential resolution phase.
.PARAMETER KeyFilePath
    Path to the SSH private key file.  When provided, SSH key auth is used in
    addition to (or instead of) credential-based auth.
.PARAMETER SaveCollectorData
    When set, raw collector output is saved as JSON and .txt files in a
    'collector-data' sub-folder of the student output directory.
.PARAMETER ExamOutputDir
    Root output directory for the exam (e.g. './output/ExamName/').  A
    student-named sub-folder is created inside this directory.
.PARAMETER StudentTimeout
    Maximum seconds allowed for all work on one student.  Default 600 (10 min).
.PARAMETER EvaluationsPath
    Optional path to the directory containing evaluation scripts.  Flowed
    through to Invoke-RemoteSetup and Invoke-RemotePester.  Defaults to the
    module's built-in Evaluators/ directory.
.OUTPUTS
    [PSCustomObject] with two properties:
      Summary  — Sage.StudentGradeSummary on success; $null on failure.
      Error    — null on success; error message string on failure.
.EXAMPLE
    # Called by Invoke-Evaluation for parallel processing:
    $StuParams = @{
        Row               = $Row
        Exam              = $Exam
        IpField           = 'ip'
        EmailField        = 'email'
        NameField         = 'student'
        TargetCredentials = $TargetCreds
        ExamOutputDir     = './output/MyExam'
    }
    $Result = Invoke-StudentEvaluation @StuParams
    if ($Result.Error) { Write-Warning $Result.Error }
    else { $Result.Summary }
#>
function Invoke-StudentEvaluation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'StudentTimeout',
        Justification = 'Used in $TimeoutCheck scriptblock')]
    param(
        [Parameter(Mandatory)]                                                             [object] $Row,
        [Parameter(Mandatory)]                                                          [hashtable] $Exam,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $IpField,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $EmailField,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $NameField,
        [Parameter()]                                                                   [hashtable] $TargetCredentials = @{},
        [Parameter()]                                                                      [string] $KeyFilePath,
        [Parameter()]                                                                      [switch] $SaveCollectorData,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $ExamOutputDir,
        [Parameter()]         [ValidateRange(60, 3600)]                                       [int] $StudentTimeout = 600,
        [Parameter()]         [ValidateNotNullOrEmpty()]                                    [string] $EvaluationsPath
    )

    $ErrorActionPreference = 'Stop'

    # ── Extract student identity fields ────────────────────────────────────────
    $StudentIp = $Row.$IpField
    $StudentEmail = $Row.$EmailField
    $StudentName = $Row.$NameField

    if (-not $StudentIp -or -not $StudentName) {
        $LogParams = @{
            Level    = 'Warning'
            Category = 'Pipeline'
            Message  = "Row missing '$IpField' or '$NameField' — skipped."
        }
        Write-Log @LogParams
        return [PSCustomObject]@{
            Summary = $null
            Error   = "Row missing '$IpField' or '$NameField' — skipped."
        }
    }

    $StudentData = @{}
    foreach ($Prop in $Row.PSObject.Properties) {
        $StudentData[$Prop.Name] = $Prop.Value
    }

    $SafeName = $StudentName -replace '[^\w\s\-.]', '' -replace '\s+', '_'
    $StudentOutputDir = Join-Path $ExamOutputDir $SafeName

    $LogParams = @{
        Level    = 'Info'
        Category = 'Pipeline'
        Message  = "Processing student: '$StudentName' (IP: $StudentIp)."
    }
    Write-Log @LogParams

    $StudentStart = [System.Diagnostics.Stopwatch]::StartNew()
    $AllTestResults = [System.Collections.Generic.List[object]]::new()
    $Sessions = [System.Collections.Generic.List[object]]::new()

    try {
        $TimeoutCheck = {
            if ($StudentStart.Elapsed.TotalSeconds -ge $StudentTimeout) {
                throw "Student '$StudentName' exceeded timeout of ${StudentTimeout}s."
            }
        }

        # ── Connect to all targets ─────────────────────────────────────────────
        $TargetSessions = @{}
        foreach ($TName in $Exam.Targets.Keys) {
            & $TimeoutCheck
            $Tgt = $Exam.Targets[$TName]
            $SessParams = @{
                HostName   = if ($Tgt.HostName) { $Tgt.HostName } else { $StudentIp }
                Port       = $Tgt.Port
                UserName   = $Tgt.UserName
                TargetName = $TName
                Platform   = $Tgt.Platform
            }
            if ($TargetCredentials.ContainsKey($TName)) {
                $SessParams['Credential'] = $TargetCredentials[$TName]
            }
            if ($KeyFilePath) {
                $SessParams['KeyFilePath'] = $KeyFilePath
            }

            $Sess = New-RemoteSession @SessParams
            $TargetSessions[$TName] = $Sess
            $Sessions.Add($Sess)
        }

        # ── Setup each session ─────────────────────────────────────────────────
        foreach ($TName in $TargetSessions.Keys) {
            $SetupParams = @{
                RemoteSession = $TargetSessions[$TName]
                Dependencies  = if ($Exam.Dependencies) { $Exam.Dependencies } else { @{ Modules = @() } }
            }
            if ($EvaluationsPath) {
                $SetupParams['EvaluationsPath'] = $EvaluationsPath
            }
            Invoke-RemoteSetup @SetupParams
        }

        # ── Process each category ──────────────────────────────────────────────
        foreach ($Cat in $Exam.Categories) {
            $CatName = $Cat.Name
            $CatTarget = $Cat.Target
            $CatSession = $TargetSessions[$CatTarget]

            if (-not $CatSession) {
                $LogParams = @{
                    Level    = 'Warning'
                    Category = 'Pipeline'
                    Message  = "Category '$CatName' references target '$CatTarget' with no session — skipped."
                }
                Write-Log @LogParams
                continue
            }

            & $TimeoutCheck
            $CollParams = @{
                Name          = $Cat.Collector
                RemoteSession = $CatSession
                Variables     = if ($Cat.Variables) { $Cat.Variables } else { @{} }
            }
            $CollResult = Invoke-RemoteCollector @CollParams

            if ($SaveCollectorData) {
                $CollDataDir = Join-Path $StudentOutputDir 'collector-data'
                if (-not (Test-Path $CollDataDir)) {
                    New-Item -Path $CollDataDir -ItemType Directory -Force | Out-Null
                }
                $SafeCat = $CatName -replace '[^\w\-.]', '' -replace '\s+', '_'
                $CollFile = Join-Path $CollDataDir "${CatTarget}-${SafeCat}-collector.json"
                $CollResult | ConvertTo-Json -Depth 10 | Set-Content -Path $CollFile -Encoding utf8

                $FmtParams = @{
                    CollectorResult = $CollResult
                    CollectorName   = $Cat.Collector
                    CategoryName    = $CatName
                    TargetName      = $CatTarget
                }
                $ReadFile = Join-Path $CollDataDir "${CatTarget}-${SafeCat}-collector.txt"
                Format-CollectorData @FmtParams | Set-Content -Path $ReadFile -Encoding utf8

                $MdFile = Join-Path $CollDataDir "${CatTarget}-${SafeCat}-collector.md"
                Format-CollectorDataMarkdown @FmtParams | Set-Content -Path $MdFile -Encoding utf8

                $LogParams = @{
                    Level    = 'Verbose'
                    Category = 'Collector'
                    Message  = "Raw collector data saved to: $CollFile"
                }
                Write-Log @LogParams
            }

            if ($CollResult.Available) {
                & $TimeoutCheck
                $PesterParams = @{
                    EvaluationName = $Cat.Evaluation
                    RemoteSession  = $CatSession
                    Variables      = if ($Cat.Variables) { $Cat.Variables } else { @{} }
                    CollectedData  = $CollResult.Data
                }
                if ($EvaluationsPath) {
                    $PesterParams['EvaluationsPath'] = $EvaluationsPath
                }
                $PesterRes = Invoke-RemotePester @PesterParams

                $ConvParams = @{
                    PesterResult  = $PesterRes
                    StudentEmail  = $StudentEmail
                    StudentName   = $StudentName
                    StudentData   = $StudentData
                    TargetName    = $CatTarget
                    Category      = $CatName
                    CollectedData = $CollResult.Data
                }
                foreach ($R in @(ConvertTo-GradeSummary @ConvParams)) {
                    $AllTestResults.Add($R)
                }
            }
            else {
                $Reason = if ($CollResult.Reason) { $CollResult.Reason }
                else { 'Service not available on remote VM' }

                $GrParams = @{
                    StudentEmail = $StudentEmail
                    StudentName  = $StudentName
                    StudentData  = $StudentData
                    TargetName   = $CatTarget
                    Category     = $CatName
                    TestName     = "$CatName — Service Unavailable"
                    Passed       = $false
                    PassGrade    = 0
                    ActualValue  = $Reason
                    ErrorMessage = $Reason
                }
                $AllTestResults.Add((New-GradeResult @GrParams))
            }
        }

        # ── Aggregate and export ───────────────────────────────────────────────
        $SumParams = @{
            TestResult   = $AllTestResults.ToArray()
            StudentEmail = $StudentEmail
            StudentName  = $StudentName
            StudentData  = $StudentData
            ExamName     = $Exam.Name
        }
        $Summary = Get-GradeSummary @SumParams

        $ExpFormats = @('Json')
        if ($Exam.Export -and $Exam.Export.SecondaryFormats) {
            $ExpFormats += @($Exam.Export.SecondaryFormats)
        }
        $ExpParams = @{
            GradeSummary = $Summary
            OutputPath   = $StudentOutputDir
            Format       = $ExpFormats
        }
        $null = Export-GradeSummary @ExpParams

        $StudentStart.Stop()
        $LogParams = @{
            Level    = 'Info'
            Category = 'Pipeline'
            Message  = "Student '$StudentName' completed in $($StudentStart.Elapsed.TotalSeconds.ToString('F1'))s."
        }
        Write-Log @LogParams

        return [PSCustomObject]@{
            Summary = $Summary
            Error   = $null
        }
    }
    catch {
        $LogParams = @{
            Level    = 'Error'
            Category = 'Pipeline'
            Message  = "Student '$StudentName' failed: $($_.Exception.Message)"
        }
        Write-Log @LogParams

        return [PSCustomObject]@{
            Summary = $null
            Error   = "Student '$StudentName': $($_.Exception.Message)"
        }
    }
    finally {
        foreach ($S in $Sessions) {
            try {
                Close-RemoteSession -Session $S
            }
            catch {
                $LogParams = @{
                    Level    = 'Warning'
                    Category = 'Session'
                    Message  = "Failed to close session for '$($S.TargetName)': $($_.Exception.Message)"
                }
                Write-Log @LogParams
            }
        }
    }
}
