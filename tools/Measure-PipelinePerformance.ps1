#Requires -Version 7.5
<#
.SYNOPSIS
    Benchmarks the SAGE evaluation pipeline against the live ServerOS infrastructure.
.DESCRIPTION
    Runs the full Invoke-Evaluation pipeline against the ServerOS proefexamen exam
    definition and a one-row benchmark roster, capturing per-stage timing for each
    run.  Produces structured benchmark result objects and writes them to JSON files
    under tools/logs/.

    Each run exercises the complete pipeline:
      - SSH session open per target (3 sessions)
      - Remote setup per target (Pester check + file copies)
      - 11 category evaluations (collector + Pester per category)
      - Grade aggregation and export

    The script patches Invoke-StudentEvaluation at benchmark time to inject timing
    instrumentation without modifying the module itself.  Timings are captured via
    Stopwatch at the overall pipeline level; per-stage breakdowns are extracted from
    the pipeline log file produced by Write-Log.

    Credentials are resolved from the SageVault SecretVault (preferred).  When vault
    entries are absent, SSH_ASKPASS-style password auth is used as fallback (password
    'Student1').

    Run this script from the repo root:
      pwsh -File tools/Measure-PipelinePerformance.ps1

    Or with custom options:
      pwsh -File tools/Measure-PipelinePerformance.ps1 -Runs 5 -Scenario Baseline
.PARAMETER Runs
    Number of benchmark runs to average.  Default 3.  Minimum 1.
.PARAMETER Scenario
    Scenario name to record in output.  Default 'Baseline'.
    Other values: 'P1-ParallelCategories', 'P2-ParallelSSH', 'P3-SkipFileCopies',
    'P5-CollectorCache', 'P8-LazyModuleCheck'.
.PARAMETER ExamPath
    Path to the exam .psd1 to benchmark.  Defaults to
    Sage/data/werkcolleges/ServerOS-proefexamen.psd1.
.PARAMETER RosterPath
    Path to the benchmark roster CSV.  Defaults to
    Sage/data/exams/benchmark-roster.csv.
.PARAMETER OutputDir
    Root output directory for pipeline results.  Defaults to
    Sage/data/output/benchmark/.
.PARAMETER SaveCollectorData
    When specified, raw collector data is saved alongside student results.
    Useful for inspecting collected data; adds minor I/O overhead.
.OUTPUTS
    [PSCustomObject[]] — one BenchmarkResult object per run, plus a summary.
.EXAMPLE
    pwsh -File tools/Measure-PipelinePerformance.ps1
    # Runs 3 baseline benchmark runs and prints a comparison table.
.EXAMPLE
    pwsh -File tools/Measure-PipelinePerformance.ps1 -Runs 1 -Scenario P2-ParallelSSH
    # Single run labelled as the P2 scenario.
#>
[CmdletBinding()]
param(
    [Parameter()][ValidateRange(1, 20)]  [int] $Runs = 3,
    [Parameter()][ValidateNotNullOrEmpty()] [string] $Scenario = 'Baseline',
    [Parameter()]                           [string] $ExamPath,
    [Parameter()]                           [string] $RosterPath,
    [Parameter()]                           [string] $OutputDir,
    [Parameter()]                           [switch] $SaveCollectorData
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Resolve paths ──────────────────────────────────────────────────────────────
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $RepoRoot 'Sage' 'Sage.psd1'

if (-not $ExamPath) {
    $ExamPath = Join-Path $RepoRoot 'Sage' 'data' 'werkcolleges' 'ServerOS-proefexamen.psd1'
}
if (-not $RosterPath) {
    $RosterPath = Join-Path $RepoRoot 'Sage' 'data' 'exams' 'benchmark-roster.csv'
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $RepoRoot 'Sage' 'data' 'output' 'benchmark'
}

$LogDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

foreach ($RequiredPath in @($ExamPath, $RosterPath, $ModulePath)) {
    if (-not (Test-Path $RequiredPath)) {
        throw "Required path not found: $RequiredPath"
    }
}

# ── Ensure SageVault credentials or set up SSH_ASKPASS fallback ───────────────
Write-Information '=== SAGE Pipeline Performance Benchmark ===' -InformationAction Continue
Write-Information "Scenario : $Scenario" -InformationAction Continue
Write-Information "Runs     : $Runs" -InformationAction Continue
Write-Information "Exam     : $ExamPath" -InformationAction Continue
Write-Information "Roster   : $RosterPath" -InformationAction Continue
Write-Information '' -InformationAction Continue

# Import the module fresh for each invocation context
Import-Module $ModulePath -Force

# ── Patch module scope for non-baseline scenarios ─────────────────────────────
# Each scenario variant is dot-sourced into the module's scope via
#   & (Get-Module Sage) { . $VariantFile }
# which gives the variant full access to private module functions.
# The variant function's ScriptBlock is then swapped into the module's
# function table, so Invoke-Evaluation transparently calls the new version.
$BenchmarksDir = Join-Path $RepoRoot 'Sage' 'Private' 'Benchmarks'

$ScenarioDispatch = @{
    'P1-ParallelCategories' = @{
        VariantFile = Join-Path $BenchmarksDir 'Invoke-StudentEvaluation-P1.ps1'
        VariantFunc = 'Invoke-StudentEvaluation-P1'
        TargetFunc  = 'Invoke-StudentEvaluation'
    }
    'P2-ParallelSSH'        = @{
        VariantFile = Join-Path $BenchmarksDir 'Invoke-StudentEvaluation-P2.ps1'
        VariantFunc = 'Invoke-StudentEvaluation-P2'
        TargetFunc  = 'Invoke-StudentEvaluation'
    }
    'P5-CollectorCache'     = @{
        VariantFile = Join-Path $BenchmarksDir 'Invoke-StudentEvaluation-P5.ps1'
        VariantFunc = 'Invoke-StudentEvaluation-P5'
        TargetFunc  = 'Invoke-StudentEvaluation'
    }
    'P3-SkipFileCopies'     = @{
        VariantFile = Join-Path $BenchmarksDir 'Invoke-RemoteSetup-P3.ps1'
        VariantFunc = 'Invoke-RemoteSetup-P3'
        TargetFunc  = 'Invoke-RemoteSetup'
    }
    'P8-LazyModuleCheck'    = @{
        VariantFile = Join-Path $BenchmarksDir 'Invoke-RemoteSetup-P8.ps1'
        VariantFunc = 'Invoke-RemoteSetup-P8'
        TargetFunc  = 'Invoke-RemoteSetup'
    }
}

if ($Scenario -ne 'Baseline' -and $ScenarioDispatch.ContainsKey($Scenario)) {
    $Dispatch = $ScenarioDispatch[$Scenario]
    $VFile = $Dispatch.VariantFile
    $VFunc = $Dispatch.VariantFunc
    $TFunc = $Dispatch.TargetFunc

    if (-not (Test-Path $VFile)) {
        throw "Variant file for scenario '$Scenario' not found: $VFile"
    }

    Write-Information "Patching module function '$TFunc' → '$VFunc'..." -InformationAction Continue

    $SageModule = Get-Module Sage
    # & (module) {} passes positional args, not -ArgumentList
    & $SageModule {
        param($VariantFilePath, $VariantFuncName, $TargetFuncName)
        # Load variant into module scope (gives it access to all private functions)
        . $VariantFilePath
        # Replace the target function with the variant's ScriptBlock
        $VariantBlock = (Get-Item "function:$VariantFuncName").ScriptBlock
        Set-Item -Path "function:$TargetFuncName" -Value $VariantBlock
        Write-Verbose "Module scope: replaced '$TargetFuncName' with '$VariantFuncName' body."
    } $VFile $VFunc $TFunc

    Write-Information '  Patch applied.' -InformationAction Continue
}
elseif ($Scenario -ne 'Baseline') {
    Write-Warning "Unknown scenario '$Scenario' — no patch applied. Running as Baseline."
}

# Check vault availability; if not available, pre-populate credentials via
# SSH_ASKPASS mechanism (password 'Student1' for all benchmark targets)
$VaultAvailable = $false
try {
    $null = Get-SecretVault -Name 'SageVault' -ErrorAction Stop
    $VaultAvailable = $true
    Write-Information 'SageVault found — using stored credentials.' -InformationAction Continue
}
catch {
    Write-Warning 'SageVault not available — will use SSH_ASKPASS password auth (Student1).'
}

# When the vault is not available, populate temporary credentials
if (-not $VaultAvailable) {
    $RawCred = $env:SAGE_BENCHMARK_PASSWORD
    if (-not $RawCred) {
        throw (
            'SageVault is not available and $env:SAGE_BENCHMARK_PASSWORD is not set. ' +
            'Set the environment variable to the benchmark lab password before running.'
        )
    }
    $SecureCred = [System.Security.SecureString]::new()
    foreach ($Char in $RawCred.ToCharArray()) { $SecureCred.AppendChar($Char) }
    $SecureCred.MakeReadOnly()
    $BenchmarkCred = $SecureCred
    Remove-Variable RawCred, SecureCred

    $CredMap = @{
        LinuxStudentUser   = [PSCredential]::new('student', $BenchmarkCred)
        WindowsAdminUser   = [PSCredential]::new('administrator', $BenchmarkCred)
        WindowsStudentUser = [PSCredential]::new('student', $BenchmarkCred)
        DefaultCredential  = [PSCredential]::new('student', $BenchmarkCred)
    }

    # Register a temporary in-memory vault with the required credential names
    try {
        Register-SecretVault -Name 'SageVault' -ModuleName 'Microsoft.PowerShell.SecretStore' `
            -VaultParameters @{ Authentication = 'None'; Interaction = 'None' } `
            -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "SageVault registration skipped: $($_.Exception.Message)"
    }

    foreach ($CredName in $CredMap.Keys) {
        try {
            Set-Credential -Name $CredName -Credential $CredMap[$CredName]
        }
        catch {
            Write-Warning "Could not store credential '$CredName': $($_.Exception.Message)"
        }
    }
}

# ── Helper: parse timing data from SAGE JSONL log ─────────────────────────────
function Read-PipelineLog {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })] [string] $LogPath
    )

    $Entries = Get-Content -Path $LogPath -Encoding utf8 |
        Where-Object { $_ -match '^\{' } |
        ForEach-Object {
            try { $_ | ConvertFrom-Json } catch { $null }
        } |
        Where-Object { $null -ne $_ }

    $CollectorEntries = $Entries |
        Where-Object { $_.Category -eq 'Collector' -and $_.Level -eq 'Info' -and $_.Data.Duration }
    $SetupEntries = $Entries |
        Where-Object { $_.Category -eq 'Setup' -and $_.Level -eq 'Info' }
    $SessionEntries = $Entries |
        Where-Object { $_.Category -eq 'Session' -and $_.Message -match 'connected' }

    $CollectorTimings = $CollectorEntries | ForEach-Object {
        [PSCustomObject]@{
            Target   = $_.Target
            Message  = $_.Message
            Duration = $_.Data.Duration
        }
    }

    [PSCustomObject]@{
        TotalLogEntries    = $Entries.Count
        CollectorTimings   = @($CollectorTimings)
        CollectorTotalSecs = ($CollectorTimings | Measure-Object -Property Duration -Sum).Sum
        SetupEntries       = @($SetupEntries)
        SessionEntries     = @($SessionEntries)
    }
}

# ── Helper: run one benchmark pass ───────────────────────────────────────────
function Invoke-BenchmarkRun {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [string] $RunScenario,
        [Parameter(Mandatory)] [int]    $RunNumber,
        [Parameter(Mandatory)] [string] $RunExamPath,
        [Parameter(Mandatory)] [string] $RunRosterPath,
        [Parameter(Mandatory)] [string] $RunOutputDir,
        [Parameter()]          [switch] $RunSaveCollectorData
    )

    Write-Information "  Run $RunNumber — starting..." -InformationAction Continue

    # Clean output dir for this run to avoid stale data
    $RunOutputDir = Join-Path $RunOutputDir "run-$RunNumber"
    if (Test-Path $RunOutputDir) {
        Remove-Item -Path $RunOutputDir -Recurse -Force
    }

    $TotalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    $EvalParams = @{
        ExamPath       = $RunExamPath
        RosterPath     = $RunRosterPath
        OutputDir      = $RunOutputDir
        ThrottleLimit  = 1
        StudentTimeout = 600
    }
    if ($RunSaveCollectorData) {
        $EvalParams['SaveCollectorData'] = $true
    }

    $Summaries = $null
    $PipelineError = $null
    try {
        $Summaries = Invoke-Evaluation @EvalParams
    }
    catch {
        $PipelineError = $_.Exception.Message
        Write-Warning "  Run $RunNumber — pipeline error: $PipelineError"
    }

    $TotalTimer.Stop()
    $TotalSecs = [Math]::Round($TotalTimer.Elapsed.TotalSeconds, 2)

    # Parse SAGE log for per-stage timings
    $LogFiles = @(Get-Item (Join-Path (Split-Path $RunOutputDir -Parent) '*.jsonl') `
            -ErrorAction SilentlyContinue)
    # Fallback: look in data/logs/
    if ($LogFiles.Count -eq 0) {
        $DataLogDir = Join-Path $RepoRoot 'Sage' 'data' 'logs'
        $LogFiles = @(Get-ChildItem -Path $DataLogDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1)
    }

    $LogData = $null
    if ($LogFiles.Count -gt 0 -and (Test-Path $LogFiles[0].FullName)) {
        try { $LogData = Read-PipelineLog -LogPath $LogFiles[0].FullName }
        catch { Write-Verbose "Log parse skipped: $($_.Exception.Message)" }
    }

    # Grade sanity check
    $TotalScore = $null
    $CategoryCount = 0
    if ($Summaries -and $Summaries.Count -gt 0) {
        $First = $Summaries[0]
        $TotalScore = if ($First.TotalScore) { $First.TotalScore.Normalized } else { $null }
        $CategoryCount = if ($First.CategoryScores) { $First.CategoryScores.Count } else { 0 }
    }

    Write-Information "  Run $RunNumber — completed in ${TotalSecs}s. Score: $TotalScore /20, Categories: $CategoryCount" -InformationAction Continue

    [PSCustomObject]@{
        PSTypeName          = 'Sage.BenchmarkResult'
        Scenario            = $RunScenario
        RunNumber           = $RunNumber
        Timestamp           = [datetime]::Now.ToString('o')
        TotalSeconds        = $TotalSecs
        NormalizedScore     = $TotalScore
        CategoriesEvaluated = $CategoryCount
        CollectorTotalSecs  = if ($LogData) { $LogData.CollectorTotalSecs } else { $null }
        CollectorTimings    = if ($LogData) { $LogData.CollectorTimings } else { @() }
        Error               = $PipelineError
    }
}

# ── Run all benchmark passes ──────────────────────────────────────────────────
$Timestamp = [datetime]::Now.ToString('yyyyMMdd-HHmmss')
$ScenarioOutputDir = Join-Path $OutputDir "$Timestamp-$Scenario"

Write-Information "Starting $Runs benchmark run(s) for scenario '$Scenario'..." -InformationAction Continue
Write-Information '' -InformationAction Continue

$AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()

for ($RunIdx = 1; $RunIdx -le $Runs; $RunIdx++) {
    $RunParams = @{
        RunScenario          = $Scenario
        RunNumber            = $RunIdx
        RunExamPath          = $ExamPath
        RunRosterPath        = $RosterPath
        RunOutputDir         = $ScenarioOutputDir
        RunSaveCollectorData = $SaveCollectorData
    }
    $RunResult = Invoke-BenchmarkRun @RunParams
    $AllResults.Add($RunResult)

    # Brief pause between runs to let SSH connections fully close
    if ($RunIdx -lt $Runs) {
        Start-Sleep -Seconds 3
    }
}

# ── Compute summary statistics ────────────────────────────────────────────────
$ValidResults = @($AllResults | Where-Object { -not $_.Error })
$AvgTotal = if ($ValidResults.Count -gt 0) {
    [Math]::Round(($ValidResults | Measure-Object -Property TotalSeconds -Average).Average, 2)
}
else { $null }
$MinTotal = if ($ValidResults.Count -gt 0) {
    [Math]::Round(($ValidResults | Measure-Object -Property TotalSeconds -Minimum).Minimum, 2)
}
else { $null }
$MaxTotal = if ($ValidResults.Count -gt 0) {
    [Math]::Round(($ValidResults | Measure-Object -Property TotalSeconds -Maximum).Maximum, 2)
}
else { $null }

$AvgCollector = if ($ValidResults.Count -gt 0 -and $null -ne $ValidResults[0].CollectorTotalSecs) {
    [Math]::Round(($ValidResults | Where-Object { $null -ne $_.CollectorTotalSecs } |
                Measure-Object -Property CollectorTotalSecs -Average).Average, 2)
}
else { $null }

$Summary = [PSCustomObject]@{
    PSTypeName          = 'Sage.BenchmarkSummary'
    Scenario            = $Scenario
    RunsRequested       = $Runs
    RunsSucceeded       = $ValidResults.Count
    RunsFailed          = $AllResults.Count - $ValidResults.Count
    AvgTotalSeconds     = $AvgTotal
    MinTotalSeconds     = $MinTotal
    MaxTotalSeconds     = $MaxTotal
    AvgCollectorSeconds = $AvgCollector
    Timestamp           = $Timestamp
    Runs                = $AllResults.ToArray()
}

# ── Save results to JSON ──────────────────────────────────────────────────────
$JsonOutputPath = Join-Path $LogDir "benchmark-${Scenario}-${Timestamp}.json"
$Summary | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonOutputPath -Encoding utf8
Write-Information '' -InformationAction Continue
Write-Information "Results saved to: $JsonOutputPath" -InformationAction Continue

# ── Print summary table ───────────────────────────────────────────────────────
Write-Information '' -InformationAction Continue
Write-Information "=== BENCHMARK SUMMARY: $Scenario ===" -InformationAction Continue
Write-Information ('  Runs succeeded : {0}/{1}' -f $ValidResults.Count, $Runs) -InformationAction Continue
Write-Information ('  Avg total time : {0}s' -f $AvgTotal) -InformationAction Continue
Write-Information ('  Min total time : {0}s' -f $MinTotal) -InformationAction Continue
Write-Information ('  Max total time : {0}s' -f $MaxTotal) -InformationAction Continue
if ($null -ne $AvgCollector) {
    Write-Information ('  Avg collector  : {0}s' -f $AvgCollector) -InformationAction Continue
}
Write-Information '' -InformationAction Continue
Write-Information '  Per-run breakdown:' -InformationAction Continue
foreach ($R in $AllResults) {
    $Status = if ($R.Error) { "FAILED: $($R.Error)" } else { "$($R.TotalSeconds)s (score: $($R.NormalizedScore)/20)" }
    Write-Information ('    Run {0}: {1}' -f $R.RunNumber, $Status) -InformationAction Continue
}

$Summary
