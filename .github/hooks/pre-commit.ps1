#Requires -Version 7.5
<#
.SYNOPSIS
    PowerShell pre-commit hook — guards quality and security before every commit.
.DESCRIPTION
    Runs the following checks in order, blocking the commit on the first failure:

        1. Sensitive path guard   — blocks exam/results/logs content by path
        2. Content secret scan    — blocks hard-coded passwords, tokens, keys
        3. Module manifest check  — validates sage.psd1 with Test-ModuleManifest
        4. PSScriptAnalyzer lint  — enforces coding standards on all PS files
        5. Markdown lint          — enforces prose quality on all .md files
        6. Unit tests             — runs Pester tests tagged 'Unit'

    Set SAGE_QUICK_HOOK=1 to run only steps 1-3 (security-critical checks).
    Steps 4-6 are skipped because CI enforces them on every push. Use this
    when you have already verified lint and tests pass in the current session.

    Install by calling this script from .git/hooks/pre-commit (via bash shim).

    Exit code 0 = commit allowed.
    Exit code 1 = commit blocked.
#>

$ErrorActionPreference = 'Stop'

$ToolsRoot = Join-Path $PSScriptRoot '..' '..' 'tools'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$QuickMode = $env:SAGE_QUICK_HOOK -eq '1'

# ── Step 0: Repository guard — block commits in the public sage repo ──────────
$OriginUrl = git remote get-url origin 2>$null
if ($OriginUrl -and $OriginUrl -notmatch 'sage-private') {
    Write-Host ''
    Write-Host '❌ REPO GUARD: You are committing in the PUBLIC sage repo!' -ForegroundColor Red
    Write-Host "   Origin: $OriginUrl" -ForegroundColor Red
    Write-Host '   All development must happen in sage-private.' -ForegroundColor Yellow
    Write-Host '   Clone sage-private instead: https://github.com/GeertCoulommier/sage-private.git' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

# ── Helper ────────────────────────────────────────────────────────────────────
<#
.SYNOPSIS
    Runs a single pre-commit check step in an isolated child process.
.DESCRIPTION
    Launches the specified PowerShell script in a child pwsh process,
    waiting up to TimeoutSeconds for it to complete. Captures stdout and
    stderr; on failure, writes captured output to the terminal. Returns
    the exit code of the child process, or 99 on timeout.
.PARAMETER Label
    Human-readable step label shown during commit output (e.g. '[2/6] Secret scan').
.PARAMETER Script
    Absolute path to the PowerShell script to run as a child process.
.PARAMETER Arguments
    Optional array of arguments to pass to the script.
.PARAMETER TimeoutSeconds
    Maximum seconds to wait for the child process. Default: 120.
.OUTPUT
    [int] Exit code of the child pwsh process (0 = success, 99 = timeout).
.EXAMPLE
    $Code = Invoke-Step -Label '[2/6] Secret scan' -Script $SecretScanScript
#>
function Invoke-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]    $Label,
        [Parameter(Mandatory)] [string]    $Script,
        [Parameter()]          [string[]]  $Arguments = @(),
        [Parameter()]          [int]       $TimeoutSeconds = 120
    )
    Write-Host "  → $Label..." -NoNewline
    $StdOut = [System.IO.Path]::GetTempFileName()
    $StdErr = [System.IO.Path]::GetTempFileName()
    try {
        $PwshArgs = @('-NoProfile', '-NonInteractive', '-File', $Script) + $Arguments
        $Params = @{
            FilePath               = 'pwsh'
            ArgumentList           = $PwshArgs
            NoNewWindow            = $true
            PassThru               = $true
            RedirectStandardOutput = $StdOut
            RedirectStandardError  = $StdErr
        }
        $Proc = Start-Process @Params
        $Completed = $Proc.WaitForExit($TimeoutSeconds * 1000)
        if (-not $Completed) {
            $Proc.Kill()
            Write-Host ' TIMEOUT' -ForegroundColor Red
            return 99
        }
        $Code = $Proc.ExitCode
        if ($Code -ne 0) {
            $Out = Get-Content -Path $StdOut -Raw -ErrorAction SilentlyContinue
            $Err = Get-Content -Path $StdErr -Raw -ErrorAction SilentlyContinue
            if ($Out) { Write-Host $Out }
            if ($Err) { Write-Host $Err -ForegroundColor Red }
        }
        return $Code
    }
    finally {
        Remove-Item -Path $StdOut, $StdErr -Force -ErrorAction SilentlyContinue
    }
}

# ── Step 1: Sensitive path guard ──────────────────────────────────────────────
Write-Host ''
Write-Host '── Pre-commit checks ────────────────────────────────────────────────' -ForegroundColor Cyan

$BlockedPatterns = @(
    '^Sage/data/exams/[^_]',   # any exam folder that is not _example
    '^Sage/data/output/',
    '^Sage/data/logs/',
    '^Sage/data/config/'
)

# Exam folders that are safe to commit (demo/template exams, not real student data)
$AllowedExamPaths = @(
    '^Sage/data/exams/_example/',
    '^Sage/data/exams/bad/',
    '^Sage/data/exams/live-test/',
    '^Sage/data/exams/full-live-test/',
    '^Sage/data/exams/serveros-2020/',
    '^Sage/data/exams/werkcolleges-2526/'
)

$Staged = git diff --cached --name-only 2>$null

$PathViolations = @()
foreach ($Pattern in $BlockedPatterns) {
    $PatternMatches = @($Staged | Where-Object { $_ -match $Pattern })
    foreach ($File in $PatternMatches) {
        $IsAllowed = $AllowedExamPaths | Where-Object { $File -match $_ }
        $IsGitKeep = $File -match '\.gitkeep$'
        if (-not $IsAllowed -and -not $IsGitKeep) {
            $PathViolations += $File
        }
    }
}

if ($PathViolations.Count -gt 0) {
    Write-Host ''
    Write-Host '❌ [1/6] Sensitive path guard: BLOCKED' -ForegroundColor Red
    Write-Host '   Attempt to commit sensitive exam/results content:' -ForegroundColor Red
    $PathViolations | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
    Write-Host ''
    Write-Host '   Un-stage with: git reset HEAD <file>' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}
Write-Host '  ✓ [1/6] Sensitive path guard: clean' -ForegroundColor Green

# ── Step 2: Content secret scan ───────────────────────────────────────────────
$SecretScanScript = Join-Path $ToolsRoot 'Run-SecretScan.ps1'
if (Test-Path $SecretScanScript) {
    $ExitCode = Invoke-Step -Label '[2/6] Content secret scan' -Script $SecretScanScript
    if ($ExitCode -ne 0) {
        Write-Host ' BLOCKED' -ForegroundColor Red
        Write-Host ''
        Write-Host '❌ PRE-COMMIT BLOCKED: Potential secrets detected in staged changes.' -ForegroundColor Red
        Write-Host '   Replace hard-coded values with environment variables or secure credential stores.' -ForegroundColor Yellow
        Write-Host ''
        exit 1
    }
    Write-Host ' ✓' -ForegroundColor Green
}
else {
    Write-Host '  ⚠ [2/6] Content secret scan: script not found, skipping.' -ForegroundColor Yellow
}

# ── Step 3: Module manifest validation ───────────────────────────────────────
Write-Host '  → [3/6] Module manifest validation...' -NoNewline
$ManifestPath = Join-Path $RepoRoot 'Sage' 'Sage.psd1'
try {
    $null = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
    Write-Host ' ✓' -ForegroundColor Green
}
catch {
    Write-Host ' BLOCKED' -ForegroundColor Red
    Write-Host ''
    Write-Host '❌ PRE-COMMIT BLOCKED: Sage.psd1 failed Test-ModuleManifest.' -ForegroundColor Red
    Write-Host "   $_" -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ── Steps 4-6 are skipped in quick mode (CI enforces them on push) ────────────
if ($QuickMode) {
    Write-Host '  ⏩ [4-6] Skipped (SAGE_QUICK_HOOK=1). CI enforces lint + tests on push.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '✅ Quick pre-commit checks passed. Proceeding with commit.' -ForegroundColor Green
    Write-Host ''
    exit 0
}

# ── Step 4: PSScriptAnalyzer lint ─────────────────────────────────────────────
$LintScript = Join-Path $ToolsRoot 'Run-PowerShellLint.ps1'
if (Test-Path $LintScript) {
    $ExitCode = Invoke-Step -Label '[4/6] PSScriptAnalyzer lint' -Script $LintScript
    if ($ExitCode -ne 0) {
        Write-Host ' BLOCKED' -ForegroundColor Red
        Write-Host ''
        Write-Host '❌ PRE-COMMIT BLOCKED: ScriptAnalyzer lint failed.' -ForegroundColor Red
        Write-Host '   Fix findings or adjust PSScriptAnalyzerSettings.psd1 intentionally.' -ForegroundColor Yellow
        Write-Host ''
        exit 1
    }
    Write-Host ' ✓' -ForegroundColor Green
}
else {
    Write-Host '  ⚠ [4/6] PSScriptAnalyzer lint: script not found, skipping.' -ForegroundColor Yellow
}

# ── Step 5: Markdown lint ─────────────────────────────────────────────────────
$MdLintScript = Join-Path $ToolsRoot 'Run-MarkdownLint.ps1'
if (Test-Path $MdLintScript) {
    $ExitCode = Invoke-Step -Label '[5/6] Markdown lint' -Script $MdLintScript
    if ($ExitCode -ne 0) {
        Write-Host ' BLOCKED' -ForegroundColor Red
        Write-Host ''
        Write-Host '❌ PRE-COMMIT BLOCKED: Markdown lint failed.' -ForegroundColor Red
        Write-Host '   Fix findings or adjust .markdownlint.jsonc intentionally.' -ForegroundColor Yellow
        Write-Host ''
        exit 1
    }
    Write-Host ' ✓' -ForegroundColor Green
}
else {
    Write-Host '  ⚠ [5/6] Markdown lint: script not found, skipping.' -ForegroundColor Yellow
}

# ── Step 6: Unit tests ────────────────────────────────────────────────────────
$TestRunner = Join-Path $ToolsRoot 'Run-Tests.ps1'
if (Test-Path $TestRunner) {
    $ExitCode = Invoke-Step -Label '[6/6] Unit tests' -Script $TestRunner -Arguments @('-Tag', 'Unit') -TimeoutSeconds 180
    if ($ExitCode -ne 0) {
        Write-Host ' BLOCKED' -ForegroundColor Red
        Write-Host ''
        Write-Host '❌ PRE-COMMIT BLOCKED: Unit test(s) failed.' -ForegroundColor Red
        Write-Host '   Run: pwsh -File tools/Run-Tests.ps1 -Tag Unit -Detailed' -ForegroundColor Yellow
        Write-Host '   Log: tools/logs/' -ForegroundColor Yellow
        Write-Host ''
        exit 1
    }
    Write-Host ' ✓' -ForegroundColor Green
}
else {
    Write-Host '  ⚠ [6/6] Unit tests: Run-Tests.ps1 not found, skipping.' -ForegroundColor Yellow
}

# ── All checks passed ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host '✅ All pre-commit checks passed. Proceeding with commit.' -ForegroundColor Green
Write-Host ''
exit 0
