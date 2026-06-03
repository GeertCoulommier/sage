#Requires -Version 7.5
<#
.SYNOPSIS
    P2 optimized Invoke-StudentEvaluation: opens all SSH sessions in parallel.
.DESCRIPTION
    Drop-in replacement logic for the session-open phase of Invoke-StudentEvaluation.
    Instead of opening sessions to DC1, Client, and Linux one at a time (sequentially),
    all target sessions are opened concurrently using ForEach-Object -Parallel.

    Since each New-RemoteSession call is fully independent (different host/port/user),
    parallelizing them hides the per-session latency behind the slowest single session
    rather than adding all session latencies together.

    Example timing (3 targets, sequential vs parallel):
      Sequential: 2s (DC1) + 2s (Client) + 1.5s (Linux) = 5.5s
      Parallel:   max(2s, 2s, 1.5s) = 2s   → saves ~3.5s

    THREAD SAFETY
    ─────────────
    New-RemoteSession creates an independent PSSession per call.  There is no shared
    mutable state.  The only shared resource is the SSH server, which handles
    concurrent connections from the same client IP — this is standard and expected.

    The parallel results are collected via [System.Collections.Concurrent.ConcurrentBag]
    and then transferred to a plain hashtable after the parallel block completes.

    ERROR HANDLING
    ──────────────
    A failed session for one target does not abort sessions for other targets.
    Failed sessions are recorded with $null so that the category loop can skip
    categories that target the failed VM (same behavior as the sequential version).
.OUTPUTS
    [PSCustomObject] with Summary and Error properties.
.EXAMPLE
    $Result = Invoke-StudentEvaluation-P2 @StuParams
#>
function Invoke-StudentEvaluation-P2 {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
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

    $StudentIp = $Row.$IpField
    $StudentEmail = $Row.$EmailField
    $StudentName = $Row.$NameField

    if (-not $StudentIp -or -not $StudentName -or -not $StudentEmail) {
        return [PSCustomObject]@{
            Summary = $null
            Error   = "Row missing '$IpField', '$NameField', or '$EmailField' — skipped."
        }
    }

    $StudentData = @{}
    foreach ($Prop in $Row.PSObject.Properties) {
        $StudentData[$Prop.Name] = $Prop.Value
    }

    $SafeName = $StudentName -replace '[^\w\s\-.]', '' -replace '\s+', '_'
    $StudentOutputDir = Join-Path $ExamOutputDir $SafeName

    $StudentStart = [System.Diagnostics.Stopwatch]::StartNew()
    $AllTestResults = [System.Collections.Generic.List[object]]::new()
    $Sessions = [System.Collections.Generic.List[object]]::new()

    try {
        $TimeoutCheck = {
            if ($StudentStart.Elapsed.TotalSeconds -ge $StudentTimeout) {
                throw "Student '$StudentName' exceeded timeout of ${StudentTimeout}s."
            }
        }

        # ── P2: Open all sessions in parallel ─────────────────────────────────
        $SessionBag = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
        $LocalStudentIp = $StudentIp
        $LocalKeyFilePath = $KeyFilePath
        $LocalTargetCredentials = $TargetCredentials
        # Resolve the module path once — parallel runspaces need to import it explicitly
        $LocalModulePath = (Get-Module Sage).Path

        $Exam.Targets.Keys | ForEach-Object -Parallel {
            $TName = $_
            $LocalExam = $using:Exam
            $Tgt = $LocalExam.Targets[$TName]
            $Bag = $using:SessionBag
            $StudentIpLocal = $using:LocalStudentIp
            $KeyFile = $using:LocalKeyFilePath
            $TargetCreds = $using:LocalTargetCredentials

            # Each parallel runspace must import the module to access New-RemoteSession
            Import-Module $using:LocalModulePath -Force -ErrorAction Stop

            $SessParams = @{
                HostName   = if ($Tgt.HostName) { $Tgt.HostName } else { $StudentIpLocal }
                Port       = $Tgt.Port
                UserName   = $Tgt.UserName
                TargetName = $TName
                Platform   = $Tgt.Platform
            }
            if ($TargetCreds.ContainsKey($TName)) {
                $SessParams['Credential'] = $TargetCreds[$TName]
            }
            if ($KeyFile) {
                $SessParams['KeyFilePath'] = $KeyFile
            }

            $SessResult = $null
            $SessError = $null
            try {
                $SessResult = New-RemoteSession @SessParams
            }
            catch {
                $SessError = $_.Exception.Message
            }

            $Bag.Add([PSCustomObject]@{
                Name    = $TName
                Session = $SessResult
                Error   = $SessError
            })
        }

        # Collect parallel session results into a hashtable
        $TargetSessions = @{}
        foreach ($SessEntry in $SessionBag) {
            if ($SessEntry.Session) {
                $TargetSessions[$SessEntry.Name] = $SessEntry.Session
                $Sessions.Add($SessEntry.Session)
            }
            else {
                Write-Warning "[P2] Session failed for target '$($SessEntry.Name)': $($SessEntry.Error)"
                $TargetSessions[$SessEntry.Name] = $null
            }
        }

        # ── Setup each session (sequential — depends on completed sessions) ────
        foreach ($TName in $TargetSessions.Keys) {
            if (-not $TargetSessions[$TName]) { continue }
            $SetupParams = @{
                RemoteSession = $TargetSessions[$TName]
                Dependencies  = if ($Exam.Dependencies) { $Exam.Dependencies } else { @{ Modules = @() } }
            }
            if ($EvaluationsPath) {
                $SetupParams['EvaluationsPath'] = $EvaluationsPath
            }
            Invoke-RemoteSetup @SetupParams
        }

        # ── Process each category (sequential) ────────────────────────────────
        foreach ($Cat in $Exam.Categories) {
            $CatName = $Cat.Name
            $CatTarget = $Cat.Target
            $CatSession = $TargetSessions[$CatTarget]

            if (-not $CatSession) {
                continue
            }

            & $TimeoutCheck

            $CollParams = @{
                Name          = $Cat.Collector
                RemoteSession = $CatSession
                Variables     = if ($Cat.Variables) { $Cat.Variables } else { @{} }
            }
            $CollResult = Invoke-RemoteCollector @CollParams

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
                $Reason = if ($CollResult.Reason) { $CollResult.Reason } else { 'Service not available' }
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
        Write-Verbose "[P2] Student '$StudentName' completed in $($StudentStart.Elapsed.TotalSeconds.ToString('F1'))s (parallel SSH open)."

        return [PSCustomObject]@{
            Summary = $Summary
            Error   = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Summary = $null
            Error   = "Student '$StudentName': $($_.Exception.Message)"
        }
    }
    finally {
        foreach ($S in $Sessions) {
            try { Close-RemoteSession -Session $S } 
            catch { Write-Warning "Failed to close session for '$($S.TargetName)': $($_.Exception.Message)" }
        }
    }
}
