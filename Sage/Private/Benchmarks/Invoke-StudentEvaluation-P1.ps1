#Requires -Version 7.5
<#
.SYNOPSIS
    P1 optimized Invoke-StudentEvaluation: evaluates categories for different
    targets in parallel, collapsing multi-target evaluation time.
.DESCRIPTION
    Drop-in replacement for Invoke-StudentEvaluation that groups the exam
    categories by target and processes each target group concurrently using
    ForEach-Object -Parallel.

    Current (sequential) timeline for proefexamen:
      DC1  [C1→C3→C4→C5a→C5b→C6→C6bg→C7]   ~40–60s  (8 categories)
      Client [C2→C8]                           ~15–20s  (2 categories)
      Linux  [C9→C10→C11]                      ~20–30s  (3 categories)
      TOTAL                                    ~75–110s

    With P1 (parallel targets):
      DC1  [C1→C3→C4→C5a→C5b→C6→C6bg→C7]  } run in
      Client [C2→C8]                          } parallel
      Linux  [C9→C10→C11]                     }
      TOTAL = slowest target (DC1)             ~40–60s

    Expected saving: ~35–50s (35–45% reduction in per-student time).

    THREAD SAFETY
    ─────────────
    Each target group's parallel branch has exclusive access to its own
    PSSession — PSSession objects are NOT shared across parallel branches.
    Within each target branch, categories run sequentially (no sharing).
    Results accumulate in a ConcurrentBag then merged after the parallel block.

    COMBINED WITH P5 (COLLECTOR CACHING)
    ──────────────────────────────────────
    P1 and P5 are compatible.  Since each target branch is isolated, the
    collector cache is per-branch (not global).  Categories on DC1 still
    benefit from P5 (Ad×2, FileServer×2), while Client and Linux branches
    also deduplicate Docker×2.  P1+P5 combined is the recommended configuration.
.OUTPUTS
    [PSCustomObject] with Summary and Error properties.
.EXAMPLE
    $Result = Invoke-StudentEvaluation-P1 @StuParams
#>
function Invoke-StudentEvaluation-P1 {
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
    $Sessions = [System.Collections.Generic.List[object]]::new()

    try {
        # ── Open sessions sequentially (can be combined with P2 for full speedup) ──
        $TargetSessions = @{}
        foreach ($TName in $Exam.Targets.Keys) {
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

        # ── P1: Group categories by target ─────────────────────────────────────
        # Build a list of (TargetName, [Category[]]) pairs to drive the parallel loop
        $TargetGroups = @{}
        foreach ($Cat in $Exam.Categories) {
            $TName = $Cat.Target
            if (-not $TargetGroups.ContainsKey($TName)) {
                $TargetGroups[$TName] = [System.Collections.Generic.List[hashtable]]::new()
            }
            $TargetGroups[$TName].Add($Cat)
        }

        # Resolve module path once for parallel runspaces
        $P1ModulePath = (Get-Module Sage).Path

        # ── P1: Process target groups in parallel ──────────────────────────────
        $ResultBag = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

        $TargetGroups.Keys | ForEach-Object -Parallel {
            $TName = $_
            $Groups = ($using:TargetGroups)[$TName]
            $Sess = ($using:TargetSessions)[$TName]
            $Bag = $using:ResultBag
            $StuEmail = $using:StudentEmail
            $StuName = $using:StudentName
            $StuData = $using:StudentData
            $SaveColl = $using:SaveCollectorData
            $EvalPath = $using:EvaluationsPath

            # Each parallel runspace must import the module to access private functions
            Import-Module $using:P1ModulePath -Force -ErrorAction Stop

            if (-not $Sess) { return }

            # Per-target collector cache (P5 within target branch)
            $CollCache = @{}

            foreach ($Cat in $Groups) {
                $CatName = $Cat.Name
                $CatCollector = $Cat.Collector

                # P5 collector cache within this target branch
                $CollCacheKey = "$TName-$CatCollector"
                if ($CollCache.ContainsKey($CollCacheKey)) {
                    $CollResult = $CollCache[$CollCacheKey]
                }
                else {
                    $CollParams = @{
                        Name          = $CatCollector
                        RemoteSession = $Sess
                        Variables     = if ($Cat.Variables) { $Cat.Variables } else { @{} }
                    }
                    $CollResult = Invoke-RemoteCollector @CollParams
                    $CollCache[$CollCacheKey] = $CollResult
                }

                if ($CollResult.Available) {
                    $PesterParams = @{
                        EvaluationName = $Cat.Evaluation
                        RemoteSession  = $Sess
                        Variables      = if ($Cat.Variables) { $Cat.Variables } else { @{} }
                        CollectedData  = $CollResult.Data
                    }
                    if ($EvalPath) { $PesterParams['EvaluationsPath'] = $EvalPath }
                    $PesterRes = Invoke-RemotePester @PesterParams

                    $ConvParams = @{
                        PesterResult  = $PesterRes
                        StudentEmail  = $StuEmail
                        StudentName   = $StuName
                        StudentData   = $StuData
                        TargetName    = $TName
                        Category      = $CatName
                        CollectedData = $CollResult.Data
                    }
                    foreach ($R in @(ConvertTo-GradeSummary @ConvParams)) {
                        $Bag.Add($R)
                    }
                }
                else {
                    $Reason = if ($CollResult.Reason) { $CollResult.Reason } else { 'Service not available' }
                    $GrParams = @{
                        StudentEmail = $StuEmail
                        StudentName  = $StuName
                        StudentData  = $StuData
                        TargetName   = $TName
                        Category     = $CatName
                        TestName     = "$CatName — Service Unavailable"
                        Passed       = $false
                        PassGrade    = 0
                        ActualValue  = $Reason
                        ErrorMessage = $Reason
                    }
                    $Bag.Add((New-GradeResult @GrParams))
                }
            }
        }

        # Collect results from concurrent bag
        $AllTestResults = @($ResultBag.ToArray())

        # ── Aggregate and export ───────────────────────────────────────────────
        $SumParams = @{
            TestResult   = $AllTestResults
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
        Write-Verbose "[P1] Student '$StudentName' completed in $($StudentStart.Elapsed.TotalSeconds.ToString('F1'))s (parallel target evaluation)."

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
            catch { Write-Warning "Failed to close session for student '$StudentName': $($_.Exception.Message)" }
        }
    }
}
