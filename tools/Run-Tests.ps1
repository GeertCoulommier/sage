#Requires -Version 7.5
<#
.SYNOPSIS
    Out-of-process Pester runner with crash diagnostics.
.DESCRIPTION
    Runs Pester in a CHILD pwsh process — never in the PowerShell Integrated
    Console (PSIC). This prevents test failures, memory leaks, or runaway
    output from crashing the VS Code extension host.

    The child process writes Pester results to a temporary NUnit XML file.
    The parent (this script) reads the XML, prints a compact summary table
    to the terminal, and writes full details to a log file.

    Crash breadcrumbs: before launching the child, the runner writes a
    breadcrumb file with PID, timestamp, and memory baseline. On crash, the
    breadcrumb survives for post-mortem analysis.

    Use -Detailed to also print full Pester output to the terminal (the
    child stdout/stderr is captured to a file either way).

.PARAMETER TestDir
    Path to the tests/ folder.  Defaults to <repo-root>/tests.
.PARAMETER Filter
    Optional glob filter for test file names.  Default: *.Tests.ps1
.PARAMETER Detailed
    Show the child process Pester output on the terminal in addition to
    the summary. Without this switch, only the summary table is shown.
.PARAMETER Tag
    Optional Pester tag filter.  Only tests with matching tags run.
.PARAMETER TimeoutSeconds
    Maximum time (seconds) the child Pester process may run before being
    killed. Default: 300 (5 minutes). Windows GitHub Actions runners require
    more time than Linux dev containers.
.OUTPUT
    Exit code: 0 = all passed, >0 = number of failures + errors.
.EXAMPLE
    # Default: summary-only terminal, full log to file
    pwsh -File tools/Run-Tests.ps1

    # Troubleshoot failures: also show full Pester output on terminal
    pwsh -File tools/Run-Tests.ps1 -Detailed

    # Run only tests matching a filter
    pwsh -File tools/Run-Tests.ps1 -Filter 'New-Remote*.Tests.ps1'

    # Run only Unit-tagged tests with 60s timeout
    pwsh -File tools/Run-Tests.ps1 -Tag Unit -TimeoutSeconds 60
#>
[CmdletBinding()]
param(
    [string]   $TestDir = (Join-Path $PSScriptRoot '..' 'tests'),
    [string]   $Filter = '*.Tests.ps1',
    [switch]   $Detailed,
    [string[]] $Tag,
    [ValidateRange(30, 600)]
    [int]      $TimeoutSeconds = 300
)

$ErrorActionPreference = 'Continue'

# ── Setup log directory ────────────────────────────────────────────────────────
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}
$LogFile = Join-Path $LogDir "test-run-$Stamp.log"
$Breadcrumb = Join-Path $LogDir "test-run-$Stamp.breadcrumb"

# ── Clean up old log/breadcrumb files (keep last 10 of each) ──────────────────
foreach ($Pattern in @('test-run-*.log', 'test-run-*.breadcrumb')) {
    $OldFiles = Get-ChildItem -Path $LogDir -Filter $Pattern |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 10
    foreach ($Old in $OldFiles) {
        Remove-Item $Old.FullName -ErrorAction SilentlyContinue
    }
}

# ── Discover test files ────────────────────────────────────────────────────────
$TestFiles = Get-ChildItem -Path $TestDir -Recurse -Filter $Filter |
    Where-Object { $_.FullName -notlike '*Reference*' } |
    Sort-Object FullName

if ($TestFiles.Count -eq 0) {
    Write-Host "No test files matching '$Filter' found in $TestDir" -ForegroundColor Yellow
    exit 0
}

# ── Memory baseline ───────────────────────────────────────────────────────────
$MemBefore = [Math]::Round(
    [System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64 / 1MB, 1
)

# ── Header ─────────────────────────────────────────────────────────────────────
$HeaderLines = @(
    '═══════════════ SAGE TEST RUN ═══════════════'
    "Test dir : $TestDir"
    "Filter   : $Filter"
    "Tag      : $(if ($Tag) { $Tag -join ', ' } else { '(all)' })"
    "Files    : $($TestFiles.Count)"
    "Timeout  : ${TimeoutSeconds}s"
    "Log file : $LogFile"
    'Mode     : OUT-OF-PROCESS (child pwsh)'
    "Mem (MB) : $MemBefore"
    '══════════════════════════════════════════════'
)
foreach ($Line in $HeaderLines) { Write-Host $Line }
$HeaderLines | Out-File -FilePath $LogFile -Encoding utf8

# ── Prepare temp files for the child process ──────────────────────────────────
$ChildScript = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
$NUnitXml = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.xml'
$ChildStdOut = [System.IO.Path]::GetTempFileName()
$ChildStdErr = [System.IO.Path]::GetTempFileName()

# Build the list of test paths as a PowerShell array literal for the child
$TestPathList = ($TestFiles.FullName |
        ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ",`n    "

# Build tag filter line
$TagLine = if ($Tag) {
    "`$Cfg.Filter.Tag = @($(($Tag | ForEach-Object { "'$_'" }) -join ', '))"
}
else {
    '# No tag filter'
}

# ── Generate child script ─────────────────────────────────────────────────────
$ChildCode = @"
#Requires -Version 7.5
`$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion '5.6.0'

`$Cfg = New-PesterConfiguration
`$Cfg.Run.Path                = @(
    $TestPathList
)
`$Cfg.Run.PassThru            = `$true
`$Cfg.TestResult.Enabled      = `$true
`$Cfg.TestResult.OutputPath   = '$($NUnitXml -replace '\\', '/')'
`$Cfg.TestResult.OutputFormat = 'NUnitXml'
`$Cfg.Output.CIFormat         = 'None'
`$Cfg.Should.ErrorAction      = 'Continue'
`$Cfg.Output.Verbosity        = 'Detailed'
$TagLine

`$Result = Invoke-Pester -Configuration `$Cfg
exit (`$Result.FailedCount + `$Result.FailedBlocksCount + `$Result.FailedContainersCount)
"@

Set-Content -Path $ChildScript -Value $ChildCode -Encoding utf8
"Child script: $ChildScript" | Out-File -FilePath $LogFile -Append -Encoding utf8
'' | Out-File -FilePath $LogFile -Append -Encoding utf8

# ── Write crash breadcrumb ────────────────────────────────────────────────────
$BreadcrumbData = @{
    Timestamp   = Get-Date -Format 'o'
    ParentPID   = $PID
    MemBeforeMB = $MemBefore
    TestFiles   = @($TestFiles.Name)
    Filter      = $Filter
    Tag         = $Tag
    Timeout     = $TimeoutSeconds
    Status      = 'RUNNING'
}
$BreadcrumbData | ConvertTo-Json -Depth 3 |
    Set-Content $Breadcrumb -Encoding utf8

# ── Launch child process ──────────────────────────────────────────────────────
Write-Host ''
Write-Host 'Launching child pwsh process...' -ForegroundColor Cyan

$ProcParams = @{
    FilePath               = 'pwsh'
    ArgumentList           = @(
        '-NoProfile', '-NonInteractive', '-File', $ChildScript
    )
    NoNewWindow            = $true
    PassThru               = $true
    RedirectStandardOutput = $ChildStdOut
    RedirectStandardError  = $ChildStdErr
}

$Sw = [System.Diagnostics.Stopwatch]::StartNew()
$Proc = Start-Process @ProcParams

$Completed = $Proc.WaitForExit($TimeoutSeconds * 1000)
$Sw.Stop()
$ElapsedTotal = [Math]::Round($Sw.Elapsed.TotalSeconds, 1)

# ── Handle timeout ────────────────────────────────────────────────────────────
if (-not $Completed) {
    $Proc.Kill()
    $Proc.WaitForExit(3000)
    $TimeoutMsg = "TIMEOUT: Child process killed after ${TimeoutSeconds}s"
    Write-Host $TimeoutMsg -ForegroundColor Red
    $TimeoutMsg | Out-File -FilePath $LogFile -Append -Encoding utf8

    # Update breadcrumb
    $BreadcrumbData.Status = 'TIMEOUT'
    $BreadcrumbData | ConvertTo-Json -Depth 3 |
        Set-Content $Breadcrumb -Encoding utf8

    # Dump child stderr to log
    if (Test-Path $ChildStdErr) {
        '── CHILD STDERR (timeout) ──' |
            Out-File -FilePath $LogFile -Append -Encoding utf8
        Get-Content $ChildStdErr |
            Out-File -FilePath $LogFile -Append -Encoding utf8
    }
    exit 1
}

$ChildExitCode = $Proc.ExitCode

# ── Capture child output to log ───────────────────────────────────────────────
'── CHILD STDOUT ──' | Out-File -FilePath $LogFile -Append -Encoding utf8
if (Test-Path $ChildStdOut) {
    Get-Content $ChildStdOut |
        Out-File -FilePath $LogFile -Append -Encoding utf8

    # If -Detailed, also show on terminal
    if ($Detailed) {
        Write-Host ''
        Write-Host '── PESTER OUTPUT ──' -ForegroundColor Cyan
        Get-Content $ChildStdOut | ForEach-Object { Write-Host $_ }
    }
}

if ((Test-Path $ChildStdErr) -and (Get-Item $ChildStdErr).Length -gt 0) {
    '' | Out-File -FilePath $LogFile -Append -Encoding utf8
    '── CHILD STDERR ──' | Out-File -FilePath $LogFile -Append -Encoding utf8
    Get-Content $ChildStdErr |
        Out-File -FilePath $LogFile -Append -Encoding utf8
}

# ── Memory after ──────────────────────────────────────────────────────────────
$MemAfter = [Math]::Round(
    [System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64 / 1MB, 1
)
$MemDelta = [Math]::Round($MemAfter - $MemBefore, 1)

# ── Parse NUnit XML for summary ───────────────────────────────────────────────
$TotalPassed = 0
$TotalFailed = 0
$TotalSkipped = 0
$TotalErrors = 0
$FileSummary = [System.Collections.Generic.List[PSCustomObject]]::new()
$FailedTests = [System.Collections.Generic.List[string]]::new()

if (Test-Path $NUnitXml) {
    try {
        [xml]$Xml = Get-Content $NUnitXml -Raw

        # Top-level summary from root
        $Root = $Xml.'test-results'
        if ($Root) {
            $TotalPassed = [int]($Root.total ?? 0) -
            [int]($Root.failures ?? 0) -
            [int]($Root.errors ?? 0) -
            [int]($Root.'not-run' ?? 0)
            $TotalFailed = [int]($Root.failures ?? 0)
            $TotalErrors = [int]($Root.errors ?? 0)
            $TotalSkipped = [int]($Root.'not-run' ?? 0)
        }

        # Per-file: find test-suite elements with .Tests.ps1 names
        $FileSuites = $Xml.SelectNodes(
            "//test-suite[contains(@name, '.Tests.ps1')]"
        )
        foreach ($Suite in $FileSuites) {
            $Name = Split-Path $Suite.name -Leaf
            $Passed = 0
            $Failed = 0
            $Skipped = 0

            $Cases = $Suite.SelectNodes('.//test-case')
            foreach ($Case in $Cases) {
                switch ($Case.result) {
                    'Success' { $Passed++ }
                    'Failure' {
                        $Failed++
                        $FailedTests.Add($Case.name)
                    }
                    'Ignored' { $Skipped++ }
                    'Inconclusive' { $Skipped++ }
                    default { $Skipped++ }
                }
            }

            $Status = if ($Failed -gt 0) { 'FAIL' } else { 'PASS' }
            $FileSummary.Add([PSCustomObject]@{
                    File    = $Name
                    Status  = $Status
                    Passed  = $Passed
                    Failed  = $Failed
                    Skipped = $Skipped
                })
        }

        # Fallback: build summary from all test-cases
        if ($FileSummary.Count -eq 0) {
            $AllCases = $Xml.SelectNodes('//test-case')
            $P = 0; $F = 0; $S = 0
            foreach ($Case in $AllCases) {
                switch ($Case.result) {
                    'Success' { $P++ }
                    'Failure' {
                        $F++
                        $FailedTests.Add($Case.name)
                    }
                    default { $S++ }
                }
            }
            $TotalPassed = $P
            $TotalFailed = $F
            $TotalSkipped = $S
            $FileSummary.Add([PSCustomObject]@{
                    File    = '(all tests)'
                    Status  = if ($F -gt 0) { 'FAIL' } else { 'PASS' }
                    Passed  = $P
                    Failed  = $F
                    Skipped = $S
                })
        }
    }
    catch {
        "NUnit XML parse error: $_" |
            Out-File -FilePath $LogFile -Append -Encoding utf8
        Write-Host (
            'Warning: Could not parse NUnit XML — using exit code only.'
        ) -ForegroundColor Yellow
    }
}
else {
    Write-Host 'Warning: No NUnit XML output file found.' -ForegroundColor Yellow
    'No NUnit XML output file found.' |
        Out-File -FilePath $LogFile -Append -Encoding utf8
}

# ── Print summary table to terminal ────────────────────────────────────────────
Write-Host ''
Write-Host '══════════════════ SUMMARY ══════════════════════' -ForegroundColor Cyan

if ($FileSummary.Count -gt 0) {
    $TableOutput = $FileSummary |
        Format-Table File, Status, Passed, Failed, Skipped -AutoSize |
        Out-String
    Write-Host $TableOutput
    $TableOutput | Out-File -FilePath $LogFile -Append -Encoding utf8
}

$OverallFail = $TotalFailed + $TotalErrors
$SummaryLine = (
    "Total: Passed=$TotalPassed  Failed=$TotalFailed  " +
    "Skipped=$TotalSkipped  Errors=$TotalErrors  " +
    "(${ElapsedTotal}s)  ChildExit=$ChildExitCode"
)
$MemLine = (
    "Memory: before=${MemBefore}MB  after=${MemAfter}MB  " +
    "delta=${MemDelta}MB"
)
$SummaryLine | Out-File -FilePath $LogFile -Append -Encoding utf8
$MemLine | Out-File -FilePath $LogFile -Append -Encoding utf8

if ($OverallFail -eq 0 -and $ChildExitCode -eq 0) {
    Write-Host $SummaryLine -ForegroundColor Green
}
else {
    Write-Host $SummaryLine -ForegroundColor Red

    if ($FailedTests.Count -gt 0) {
        Write-Host ''
        Write-Host 'FAILED TESTS:' -ForegroundColor Red
        foreach ($FailedTest in $FailedTests) {
            Write-Host "  X $FailedTest" -ForegroundColor Red
        }
    }
}
Write-Host $MemLine
Write-Host "Log: $LogFile"

# ── Update breadcrumb to completed ────────────────────────────────────────────
$BreadcrumbData.Status = 'COMPLETED'
$BreadcrumbData.ExitCode = $ChildExitCode
$BreadcrumbData.ElapsedSec = $ElapsedTotal
$BreadcrumbData.MemAfterMB = $MemAfter
$BreadcrumbData.MemDeltaMB = $MemDelta
$BreadcrumbData | ConvertTo-Json -Depth 3 |
    Set-Content $Breadcrumb -Encoding utf8

# ── Clean up temp files ───────────────────────────────────────────────────────
Remove-Item $ChildScript, $NUnitXml, $ChildStdOut, $ChildStdErr -Force -ErrorAction SilentlyContinue

# Use child exit code if NUnit parsing failed
if ($OverallFail -eq 0 -and $ChildExitCode -ne 0) {
    $OverallFail = $ChildExitCode
}

exit $OverallFail
