#Requires -Version 7.5
<#
.SYNOPSIS
    P5 optimized Invoke-StudentEvaluation: deduplicates same-collector calls within
    a single student evaluation run.
.DESCRIPTION
    Drop-in replacement logic for Invoke-StudentEvaluation that caches collector
    results within a single student run.  When two categories target the same VM
    with the same collector (e.g. 'Ad' collector on DC1 used by both 'Active Directory
    DC1' and 'AD Groups DC1'), the second call returns the cached result instead of
    executing a full SSH round-trip.

    This is always correct within a single student run because the remote VM state
    cannot change between categories during one evaluation.

    The cache is a plain hashtable keyed by "$TargetName-$CollectorName".  It is
    created fresh for every student and does not persist between students.

    USAGE IN BENCHMARKS
    ───────────────────
    This file is sourced by Measure-PipelinePerformance.ps1 when running the P5
    benchmark scenario.  It defines Invoke-StudentEvaluation-P5 which wraps the
    real Invoke-StudentEvaluation with collector caching injected.

    For production use, the caching logic should be merged directly into
    Invoke-StudentEvaluation.ps1 in the main pipeline.
.OUTPUTS
    [PSCustomObject] with Summary and Error properties (same as Invoke-StudentEvaluation).
.EXAMPLE
    $Result = Invoke-StudentEvaluation-P5 @StuParams
#>

# This function reproduces Invoke-StudentEvaluation with P5 caching added.
# Parameters are identical; see Invoke-StudentEvaluation for full documentation.
function Invoke-StudentEvaluation-P5 {
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

    # ── P5: per-student collector result cache (keyed by "TargetName-CollectorName") ──
    $CollectorCache = @{}
    $CollectorCacheHits = 0

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

        # ── Process each category — with P5 collector caching ─────────────────
        foreach ($Cat in $Exam.Categories) {
            $CatName = $Cat.Name
            $CatTarget = $Cat.Target
            $CatSession = $TargetSessions[$CatTarget]

            if (-not $CatSession) {
                continue
            }

            & $TimeoutCheck

            # P5: check cache before executing collector
            $CollCacheKey = "$CatTarget-$($Cat.Collector)"
            if ($CollectorCache.ContainsKey($CollCacheKey)) {
                $CollResult = $CollectorCache[$CollCacheKey]
                $CollectorCacheHits++
                Write-Verbose "[P5] Collector cache hit: '$CollCacheKey' (hit #$CollectorCacheHits)"
            }
            else {
                $CollParams = @{
                    Name          = $Cat.Collector
                    RemoteSession = $CatSession
                    Variables     = if ($Cat.Variables) { $Cat.Variables } else { @{} }
                }
                $CollResult = Invoke-RemoteCollector @CollParams
                $CollectorCache[$CollCacheKey] = $CollResult
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
        Write-Verbose "[P5] Student '$StudentName' completed in $($StudentStart.Elapsed.TotalSeconds.ToString('F1'))s. Collector cache hits: $CollectorCacheHits"

        return [PSCustomObject]@{
            Summary           = $Summary
            Error             = $null
            CollectorCacheHits = $CollectorCacheHits
        }
    }
    catch {
        return [PSCustomObject]@{
            Summary           = $null
            Error             = "Student '$StudentName': $($_.Exception.Message)"
            CollectorCacheHits = $CollectorCacheHits
        }
    }
    finally {
        foreach ($S in $Sessions) {
            try { Close-RemoteSession -Session $S } 
            catch { Write-Warning "Failed to close session for '$($S.TargetName)': $($_.Exception.Message)" }
        }
    }
}
