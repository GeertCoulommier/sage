#Requires -Version 7.5
<#
.SYNOPSIS
    Runs a Pester evaluation script on a remote VM via an active PSSession and
    returns deserialized Pester test results.
.DESCRIPTION
    Copies the named evaluation file to the remote VM (if not already present),
    then runs Invoke-Pester via Invoke-Command with -PassThru so results come
    back as CLIXML-deserialized objects.

    The evaluation file is run with Pester Container Data:
      New-PesterContainer -Path <evalPath> -Data @{
          ExamVariables = $Variables
          CollectedData = $CollectedData
      }

    Only tests tagged 'Evaluation' are executed.

    The returned object contains a subset of Pester's TestResult that survives
    CLIXML deserialization:
      Tests     - list with Name, Result, ErrorRecord, Duration, Tag
      PassedCount, FailedCount, SkippedCount, TotalCount, Duration

    All steps are logged via Write-Log.
.PARAMETER EvaluationName
    Short name matching the Evaluation key in exam.psd1 (e.g. 'Dns', 'Docker').
    The file Evaluators/<EvaluationName>.Tests.ps1 must exist.
.PARAMETER RemoteSession
    Active Sage.RemoteSession returned by New-RemoteSession.
.PARAMETER Variables
    Exam variables for the current category (from exam.psd1 category Variables).
.PARAMETER CollectedData
    Data hashtable from the collector result (CollectorResult.Data).
.PARAMETER EvaluationsPath
    Optional path to the directory containing evaluation scripts.  Defaults to
    ../Evaluators relative to the module Private/ directory.  Allows exam
    grading to use private evaluators from a different location.
.OUTPUTS
    [PSCustomObject] — deserialized Pester run result with Tests, counts, Duration.
.EXAMPLE
    $pesterResult = Invoke-RemotePester -EvaluationName 'Dns' -RemoteSession $remoteSession -Variables @{ ExpectedIp = '10.2.3.1' }
    # Returns a deserialized Pester result with PassedCount, FailedCount, TotalCount, and Tests.
#>
function Invoke-RemotePester {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables',
        Justification = 'Used via $using: scope in Invoke-Command scriptblock')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CollectedData',
        Justification = 'Used via $using: scope in Invoke-Command scriptblock')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $EvaluationName,
        [Parameter(Mandatory)][PSTypeName('Sage.RemoteSession')]                   [PSCustomObject] $RemoteSession,
        [Parameter()]                                                                   [hashtable] $Variables = @{},
        [Parameter()]                                                                   [hashtable] $CollectedData = @{},
        [Parameter()][ValidateNotNullOrEmpty()]                                            [string] $EvaluationsPath
    )

    $ErrorActionPreference = 'Stop'

    $IsRemoteWindows = $RemoteSession.Platform -eq 'Windows'
    $TargetName = $RemoteSession.TargetName
    $EvalFileName = "${EvaluationName}.Tests.ps1"
    if (-not $EvaluationsPath) {
        $EvaluationsPath = Join-Path $PSScriptRoot '..' 'Evaluators'
    }
    $LocalPath = Join-Path $EvaluationsPath $EvalFileName

    if (-not (Test-Path $LocalPath)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new(
                    "Evaluation script '$EvalFileName' not found at: $LocalPath"),
                'InvokeRemotePester.ScriptNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $LocalPath
            )
        )
    }

    # Join-Path on Windows converts '/tmp/...' to '\tmp\...' which breaks Linux paths.
    # Windows paths are resolved remotely to avoid local C: drive issues on Linux.
    $RemotePath = if ($IsRemoteWindows) {
        Invoke-Command -Session $RemoteSession.Session -ScriptBlock {
            Join-Path $env:TEMP 'sage-evaluations' $using:EvalFileName
        }
    }
    else {
        "/tmp/sage-evaluations/$EvalFileName"
    }

    Copy-File -Session $RemoteSession.Session -LocalPath $LocalPath -RemotePath $RemotePath

    $LogParams = @{
        Level    = 'Info'
        Category = 'Pester'
        Message  = "Starting Pester evaluation '$EvaluationName' on '$TargetName'."
        Target   = $TargetName
    }
    Write-Log @LogParams

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Run Pester remotely and immediately extract all test data into plain
    # hashtables on the remote side.  Pester's Test objects do not survive
    # CLIXML deserialization intact (they serialise as their string
    # representation).  Everything needed for ConvertTo-GradeSummary is
    # pulled out before the result crosses the remoting boundary.
    $PesterResult = Invoke-Command -Session $RemoteSession.Session -ScriptBlock {
        $Container = New-PesterContainer -Path $using:RemotePath -Data @{
            ExamVariables = $using:Variables
            CollectedData = $using:CollectedData
        }
        $Config = New-PesterConfiguration
        $Config.Run.Container = $Container
        $Config.Run.PassThru  = $true
        $Config.Filter.Tag    = @('Evaluation')
        $Config.Output.Verbosity = 'None'

        $Run = Invoke-Pester -Configuration $Config

        # Extract each test into a plain hashtable safe for CLIXML serialisation.
        $TestList = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($T in $Run.Tests) {
            if ($T.Result.ToString() -in 'Skipped', 'NotRun') { continue }

            # Walk the Block hierarchy for the innermost named context.
            $CtxName = $null
            $Blk = $T.Block
            while ($Blk) {
                if (-not [string]::IsNullOrEmpty($Blk.Name)) {
                    $CtxName = $Blk.Name
                    break
                }
                $Blk = $Blk.Parent
            }

            # Extract error message cleanly.
            $ErrMsg = $null
            if ($T.ErrorRecord) {
                $ErrMsg = $T.ErrorRecord.Exception.Message
            }

            # Data from -ForEach is a hashtable on the server; copy it explicitly
            # so nested keys survive serialisation as a plain hashtable.
            $DataHt = @{}
            if ($T.Data -is [hashtable]) {
                foreach ($K in $T.Data.Keys) {
                    $DataHt[$K] = $T.Data[$K]
                }
            }

            $TestList.Add(@{
                ExpandedName = $T.ExpandedName
                Name         = $T.Name
                Result       = $T.Result.ToString()   # serialise enum as string
                Context      = $CtxName
                Data         = $DataHt
                ErrorMessage = $ErrMsg
            })
        }

        # Collect container-level and block-level errors (e.g. BeforeDiscovery failures).
        # These are swallowed by Pester when Output.Verbosity = 'None' and must be
        # extracted explicitly so the local host can log and surface them.
        $ContainerErrors = @(
            $Run.Containers | ForEach-Object {
                if ($_.ErrorRecord) { $_.ErrorRecord.Exception.Message }
            } | Where-Object { $_ }
        )
        $BlockErrors = @(
            $Run.Containers.Blocks | ForEach-Object {
                if ($_.ErrorRecord) { "[$($_.Name)]: $($_.ErrorRecord.Exception.Message)" }
            } | Where-Object { $_ }
        )

        @{
            PassedCount     = $Run.PassedCount
            FailedCount     = $Run.FailedCount
            SkippedCount    = $Run.SkippedCount
            TotalCount      = $Run.TotalCount
            Duration        = $Run.Duration.ToString()
            Tests           = $TestList.ToArray()
            ContainerErrors = $ContainerErrors
            BlockErrors     = $BlockErrors
        }
    }

    $Stopwatch.Stop()

    # Surface any container or block errors (e.g. BeforeDiscovery failures) via Write-Log
    # so they are visible even when Pester's output verbosity is 'None'.
    foreach ($Err in $PesterResult.ContainerErrors) {
        $LogParams = @{
            Level    = 'Error'
            Category = 'Pester'
            Message  = "Container error in '$EvaluationName' on '$TargetName': $Err"
            Target   = $TargetName
        }
        Write-Log @LogParams
    }
    foreach ($Err in $PesterResult.BlockErrors) {
        $LogParams = @{
            Level    = 'Error'
            Category = 'Pester'
            Message  = "Block error in '$EvaluationName' on '$TargetName': $Err"
            Target   = $TargetName
        }
        Write-Log @LogParams
    }

    $LogParams = @{
        Level    = 'Info'
        Category = 'Pester'
        Message  = "Pester evaluation '$EvaluationName' finished on '$TargetName' in $($Stopwatch.Elapsed.TotalSeconds.ToString('F2'))s. Passed=$($PesterResult.PassedCount) Failed=$($PesterResult.FailedCount) Total=$($PesterResult.TotalCount)."
        Target   = $TargetName
        Data     = @{
            Duration  = $Stopwatch.Elapsed.TotalSeconds
            TestCount = $PesterResult.TotalCount
        }
    }
    Write-Log @LogParams

    $PesterResult
}
