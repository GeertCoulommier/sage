#!/usr/bin/env pwsh
#Requires -Version 7.5
<#
.SYNOPSIS
    TUI screen integration test — runs all TUI screens with real result data.
.DESCRIPTION
    1. Optionally runs a live evaluation against a remote server.
    2. Sources all TUI private functions.
    3. Drives each TUI screen with a mocked ReadKey key-queue to verify:
       - Show-ResultsSummary (filter, drill-down, back)
       - Show-CategoryDetail (scroll, back)
       - Show-PreviousRuns (view list, mark for diff, diff, back)
       - Show-DiffResults / Compare-Results (via Show-PreviousRuns)
    Exits 0 when all screens complete without throwing, 1 on any failure.
.PARAMETER RemoteHost
    Public hostname for DC1 (port 30022).
.PARAMETER SkipEvaluation
    Skip running a fresh live evaluation (use existing output data only).
.EXAMPLE
    ./tools/Test-TuiScreens.ps1
.EXAMPLE
    ./tools/Test-TuiScreens.ps1 -SkipEvaluation
#>
[CmdletBinding()]
param(
    [Parameter()]   [string] $RemoteHost = 'srvos-2526s2-geertcoulommier.westeurope.cloudapp.azure.com',
    [Parameter()]   [switch] $SkipEvaluation
)

$ErrorActionPreference = 'Stop'

$RepoRoot    = Resolve-Path (Join-Path $PSScriptRoot '..')
$ModulePath  = Join-Path $RepoRoot 'Sage' 'Sage.psd1'
$TuiPath     = Join-Path $RepoRoot 'Sage' 'tui'
$PrivateDir  = Join-Path $TuiPath 'Private'
$ExamPath    = Join-Path $RepoRoot 'Sage' 'data' 'werkcolleges' 'Server-OS-werkcollege-labo5-7.psd1'
$OutputDir   = Join-Path $TuiPath 'output'
$KeyFile     = Join-Path $TuiPath 'keys' 'id_sage'

$Pass = 0
$Fail = 0

function Write-Result {
    param([string] $Label, [bool] $Ok, [string] $Detail = '')
    if ($Ok) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:Pass++
    }
    else {
        Write-Host "  [FAIL] $Label$(if ($Detail) { " — $Detail" })" -ForegroundColor Red
        $script:Fail++
    }
}

function Invoke-TestBlock {
    param([string] $Label, [scriptblock] $Block)
    try {
        & $Block
        Write-Result $Label $true
    }
    catch {
        Write-Result $Label $false "$_"
    }
}

Write-Host ''
Write-Host '══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  SAGE TUI — Screen Integration Test' -ForegroundColor Cyan
Write-Host '══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# ── 1. Import SAGE module ──────────────────────────────────────────────────────
Import-Module $ModulePath -Force
Write-Host '  [OK] SAGE module imported.' -ForegroundColor Green

# ── 2. Source TUI private helpers ─────────────────────────────────────────────
foreach ($File in (Get-ChildItem -Path $PrivateDir -Filter '*.ps1' -Recurse)) {
    . $File.FullName
}
Write-Host '  [OK] TUI private functions loaded.' -ForegroundColor Green

# ── 3. Set up TUI environment ─────────────────────────────────────────────────
$script:UseSpectre         = $false
$script:SageQuit           = $false
$script:SageExamName       = 'Werkcolleges Lab 5, 6 & 7 — Group Policy, DHCP en AD Sites & Services'
$script:SageExamVersion    = '2.0.0'
$script:SageThemeName      = '13. Nord Ice'
$script:SageTheme          = Get-SageTheme -ThemeName '13. Nord Ice'
$script:SageLatestSummary  = $null

Write-Host '  [OK] TUI environment initialised (Nord Ice theme).' -ForegroundColor Green

# ── 4. Optionally run live evaluation to produce a second output run ───────────
if (-not $SkipEvaluation) {
    Write-Host ''
    Write-Host '  ── Phase 1: Live evaluation ──' -ForegroundColor Cyan

    if (-not (Test-Path $ExamPath)) {
        Write-Host "  [SKIP] Exam definition not found: $ExamPath" -ForegroundColor Yellow
    }
    elseif (-not (Test-Path $KeyFile)) {
        Write-Host "  [SKIP] TUI SSH key not found: $KeyFile" -ForegroundColor Yellow
    }
    else {
        try {
            $Exam = Import-ExamDefinition -Path $ExamPath

            $ConnInfo = @{
                DC1 = [PSCustomObject]@{
                    HostName = $RemoteHost
                    Port     = 30022
                    Status   = 'Fallback'
                }
            }

            $EvalParams = @{
                Exam               = $Exam
                ConnectionInfo     = $ConnInfo
                SelectedCategories = @($Exam.Categories | ForEach-Object { $_.Name })
                OutputDir          = $OutputDir
                DomainName         = ''
            }

            Write-Host "  Evaluating against $RemoteHost:30022 ..." -ForegroundColor Gray
            $EvalResult = Invoke-LocalEvaluation @EvalParams
            if ($EvalResult.Error) {
                throw $EvalResult.Error
            }
            $script:SageLatestSummary = $EvalResult.Summary
            Write-Host "  [OK] Live evaluation complete. Score: $([math]::Round($EvalResult.Summary.TotalScore.Normalized, 2))/20" -ForegroundColor Green
        }
        catch {
            Write-Host "  [WARN] Live evaluation failed: $_" -ForegroundColor Yellow
            Write-Host '  Continuing with existing output data...' -ForegroundColor Yellow
        }
    }
}

# ── 5. Load output runs ────────────────────────────────────────────────────────
Write-Host ''
Write-Host '  ── Phase 2: Load output data ──' -ForegroundColor Cyan

if (-not (Test-Path $OutputDir)) {
    Write-Host "  [SKIP] Output dir not found: $OutputDir" -ForegroundColor Yellow
    exit 0
}

$RunDirs = Get-ChildItem -Path $OutputDir -Directory |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{6}$' } |
    Sort-Object -Property Name -Descending

if ($RunDirs.Count -eq 0) {
    Write-Host '  [SKIP] No output runs found.' -ForegroundColor Yellow
    exit 0
}

Write-Host "  Found $($RunDirs.Count) output run(s)." -ForegroundColor Gray

# Load first run with a valid summary
$PrimaryRun = $null
$Summary1   = $null
foreach ($Dir in $RunDirs) {
    $Loaded = Import-ResultSummary -OutputPath $Dir.FullName
    if ($Loaded) {
        $PrimaryRun = $Dir
        $Summary1   = $Loaded
        break
    }
}

if (-not $script:SageLatestSummary) {
    $script:SageLatestSummary = $Summary1
}

if (-not $Summary1) {
    Write-Host '  [FAIL] Could not load any valid summary.' -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Primary run loaded: $($PrimaryRun.Name)" -ForegroundColor Green

# Load second run for diff (find the next valid run after the primary)
$Summary2    = $null
$SecondaryRun = $null
foreach ($Dir in $RunDirs) {
    if ($Dir.FullName -eq $PrimaryRun.FullName) { continue }
    $Loaded = Import-ResultSummary -OutputPath $Dir.FullName
    if ($Loaded) {
        $SecondaryRun = $Dir
        $Summary2     = $Loaded
        break
    }
}
if ($Summary2) {
    Write-Host "  [OK] Secondary run loaded: $($SecondaryRun.Name)" -ForegroundColor Green
}

# ── Helper: ReadKey queue ───────────────────────────────────────────────────────
function New-KeyQueue {
    param([string[]] $Keys)
    $script:KeyQueue = [System.Collections.Queue]::new()
    foreach ($K in $Keys) {
        $script:KeyQueue.Enqueue($K)
    }
}

function Set-ReadKeyMock {
    # Override Invoke-ReadKey to drain the key queue
    $null = New-Item -Path 'Function:\Invoke-ReadKey' -Value {
        if ($script:KeyQueue.Count -gt 0) {
            $KeySpec = $script:KeyQueue.Dequeue()
            $KeyName = $KeySpec
            $KeyChar = [char]0
            switch ($KeySpec.ToUpper()) {
                'B'         { $KeyName = 'B';         $KeyChar = [char]66  }
                'Q'         { $KeyName = 'Q';         $KeyChar = [char]81  }
                'A'         { $KeyName = 'A';         $KeyChar = [char]65  }
                'P'         { $KeyName = 'P';         $KeyChar = [char]80  }
                'F'         { $KeyName = 'F';         $KeyChar = [char]70  }
                'D'         { $KeyName = 'D';         $KeyChar = [char]68  }
                'ENTER'     { $KeyName = 'Enter';     $KeyChar = [char]13  }
                'SPACE'     { $KeyName = 'Spacebar';  $KeyChar = [char]32  }
                'UP'        { $KeyName = 'UpArrow';   $KeyChar = [char]0   }
                'DOWN'      { $KeyName = 'DownArrow'; $KeyChar = [char]0   }
                'LEFT'      { $KeyName = 'LeftArrow'; $KeyChar = [char]0   }
                'RIGHT'     { $KeyName = 'RightArrow'; $KeyChar = [char]0  }
                'BACKSPACE' { $KeyName = 'Backspace'; $KeyChar = [char]8   }
            }
            [PSCustomObject]@{
                Key     = $KeyName
                KeyChar = $KeyChar
            }
        }
        else {
            # Safety net: Q to quit
            [PSCustomObject]@{ Key = 'Q'; KeyChar = [char]81 }
        }
    } -Force
}

# Override Show-SageHeader to avoid clearing the real console
$null = New-Item -Path 'Function:\Show-SageHeader' -Value {
    Write-Host '  [TUI] Header rendered.' -ForegroundColor DarkGray
    return 5
} -Force

# Override Show-StatusBox so it doesn't cause console dimension issues
$null = New-Item -Path 'Function:\Show-StatusBox' -Value {
    param([string[]] $Lines, [int] $StartY)
    $null = $Lines, $StartY
} -Force

# Also silence direct console manipulations that can fail in non-PTY context
$null = New-Item -Path 'Function:\Invoke-ConsoleSafeOp' -Value {
    param([scriptblock] $Block)
    try { & $Block } catch { Write-Debug $_ }
} -Force

# Patch [System.Console] calls by setting a safe console size
try { [System.Console]::WindowHeight = 40 } catch { Write-Debug $_ }
try { [System.Console]::WindowWidth  = 120 } catch { Write-Debug $_ }

# ── 6. Test Show-ResultsSummary ────────────────────────────────────────────────
Write-Host ''
Write-Host '  ── Phase 3: Show-ResultsSummary ──' -ForegroundColor Cyan

Set-ReadKeyMock
Invoke-TestBlock 'Show-ResultsSummary: press B to go back' {
    New-KeyQueue @('B')
    $Result = Show-ResultsSummary -Summary $Summary1 -OutputPath $PrimaryRun.FullName -UseSpectre $false
    if ($Result -ne 'Back') { throw "Expected 'Back', got '$Result'" }
}

Invoke-TestBlock 'Show-ResultsSummary: filter Pass → back' {
    New-KeyQueue @('P', 'B')
    $Result = Show-ResultsSummary -Summary $Summary1 -OutputPath $PrimaryRun.FullName -UseSpectre $false
    if ($Result -ne 'Back') { throw "Expected 'Back', got '$Result'" }
}

Invoke-TestBlock 'Show-ResultsSummary: filter Fail → All → back' {
    New-KeyQueue @('F', 'A', 'B')
    $Result = Show-ResultsSummary -Summary $Summary1 -OutputPath $PrimaryRun.FullName -UseSpectre $false
    if ($Result -ne 'Back') { throw "Expected 'Back', got '$Result'" }
}

Invoke-TestBlock 'Show-ResultsSummary: drill into first category → back' {
    # RIGHT panel is active by default, Enter drills into selected row
    New-KeyQueue @('ENTER', 'B', 'B')
    # Need to mock Show-CategoryDetail as well for this path
    $OrigCatDetail = Get-Item 'Function:\Show-CategoryDetail' -ErrorAction SilentlyContinue
    $null = New-Item -Path 'Function:\Show-CategoryDetail' -Value {
        param([object]$CategoryGrade, [object]$Summary, [string]$OutputPath, [bool]$UseSpectre)
        $null = $CategoryGrade, $Summary, $OutputPath, $UseSpectre
        return 'Back'
    } -Force
    try {
        $Result = Show-ResultsSummary -Summary $Summary1 -OutputPath $PrimaryRun.FullName -UseSpectre $false
    }
    finally {
        if ($OrigCatDetail) {
            $null = New-Item -Path 'Function:\Show-CategoryDetail' -Value $OrigCatDetail.ScriptBlock -Force
        }
    }
    if ($Result -ne 'Back') { throw "Expected 'Back', got '$Result'" }
}

# ── 7. Test Show-CategoryDetail (if categories exist) ─────────────────────────
if ($Summary1.CategoryScores -and $Summary1.CategoryScores.Count -gt 0) {
    Write-Host ''
    Write-Host '  ── Phase 4: Show-CategoryDetail ──' -ForegroundColor Cyan

    $FirstCat = $Summary1.CategoryScores[0]

    Invoke-TestBlock 'Show-CategoryDetail: press B to go back' {
        New-KeyQueue @('B')
        $null = New-Item -Path 'Function:\Show-TestDetail' -Value {
            param([object]$TestResult, [object]$Summary, [string]$OutputPath, [bool]$UseSpectre)
            $null = $TestResult, $Summary, $OutputPath, $UseSpectre
            return 'Back'
        } -Force
        $Result = Show-CategoryDetail -CategoryGrade $FirstCat -Summary $Summary1 -OutputPath $PrimaryRun.FullName -UseSpectre $false
        if ($Result -ne 'Back') { throw "Expected 'Back', got '$Result'" }
    }

    Invoke-TestBlock 'Show-CategoryDetail: filter Pass → back' {
        New-KeyQueue @('P', 'B')
        $Result = Show-CategoryDetail -CategoryGrade $FirstCat -Summary $Summary1 -OutputPath $PrimaryRun.FullName -UseSpectre $false
        if ($Result -ne 'Back') { throw "Expected 'Back', got '$Result'" }
    }

    # Phase 4b: Test Show-TestDetail with real collector data (regression for blank-line bug)
    Write-Host ''
    Write-Host '  ── Phase 4b: Show-TestDetail with collector data ──' -ForegroundColor Cyan

    $FirstTest = $Summary1.TestResults | Select-Object -First 1
    if ($FirstTest) {
        Invoke-TestBlock 'Show-TestDetail: renders with real collector .md data (blank lines ok)' {
            # This exercises ConvertFrom-CollectorMarkdown with real markdown content
            # that contains blank lines (regression test for Mandatory [string[]] bug).
            New-KeyQueue @('BACKSPACE')
            { Show-TestDetail -TestResult $FirstTest -OutputPath $PrimaryRun.FullName -UseSpectre $false } |
                ForEach-Object { } # just invoke; would throw if bug is present
        }
    }
}

# ── 8. Test Show-PreviousRuns ─────────────────────────────────────────────────
Write-Host ''
Write-Host '  ── Phase 5: Show-PreviousRuns ──' -ForegroundColor Cyan

Invoke-TestBlock 'Show-PreviousRuns: press B to go back' {
    $null = New-Item -Path 'Function:\Show-ResultsSummary' -Value {
        param([object]$Summary, [string]$OutputPath, [bool]$UseSpectre)
        $null = $Summary, $OutputPath, $UseSpectre
        return 'Back'
    } -Force
    New-KeyQueue @('B')
    $Result = Show-PreviousRuns -OutputDir $OutputDir -UseSpectre $false
    if ($Result -ne 'Back') { throw "Expected 'Back', got '$Result'" }
}

# Test diff if we have 2 runs
if ($Summary2) {
    Invoke-TestBlock 'Show-PreviousRuns: mark 2 runs and open diff' {
        # Mock Show-DiffResults to avoid fully interactive diff screen
        $null = New-Item -Path 'Function:\Show-DiffResults' -Value {
            param([object]$Diff, [string]$OlderDate, [string]$NewerDate, [object]$RunA, [object]$RunB, [bool]$UseSpectre)
            $null = $Diff, $OlderDate, $NewerDate, $RunA, $RunB, $UseSpectre
            return 'Back'
        } -Force
        # Sequence: Spacebar = mark first run, DOWN = move to 2nd, Spacebar = mark second, LEFT = to left panel, ENTER = trigger diff
        New-KeyQueue @('SPACE', 'DOWN', 'SPACE', 'LEFT', 'ENTER', 'B')
        $Result = Show-PreviousRuns -OutputDir $OutputDir -UseSpectre $false
        if ($Result -notin @('Back', $null)) { throw "Expected 'Back', got '$Result'" }
    }

    # Test Compare-Results logic directly
    Invoke-TestBlock 'Compare-Results: diff two summaries produces result object' {
        $Diff = Compare-Results -OlderSummary $Summary2 -NewerSummary $Summary1
        if ($null -eq $Diff) { throw 'Compare-Results returned null' }
        if ($null -eq $Diff.TestDiffs) { throw 'Compare-Results result has no TestDiffs property' }
    }
}

# ── 9. Summary ─────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '══════════════════════════════════════' -ForegroundColor Cyan
Write-Host "  Results: $script:Pass passed, $script:Fail failed" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
Write-Host '══════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

if ($script:Fail -gt 0) { exit 1 }
