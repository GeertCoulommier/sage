#Requires -Version 7.5
<#
.SYNOPSIS
    Runs markdownlint-cli2 over all Markdown files in the repository.
.DESCRIPTION
    Invokes markdownlint-cli2 (must be installed: npm install -g markdownlint-cli2)
    against every *.md file, excluding the legacy/ folder.

    Exit codes:
        0  — no findings (or tool not installed — soft-fail with warning)
        1  — one or more markdownlint violations found
.EXAMPLE
    pwsh -NoProfile -File tools/Run-MarkdownLint.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ── Dependency check ──────────────────────────────────────────────────────────
$ToolName = 'markdownlint-cli2'
if (-not (Get-Command $ToolName -ErrorAction SilentlyContinue)) {
    Write-Warning 'markdownlint-cli2 not found on PATH — skipping markdown lint.'
    Write-Warning 'Install with: npm install -g markdownlint-cli2'
    exit 0
}

# ── Resolve paths ─────────────────────────────────────────────────────────────
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# ── Collect .md files (exclude legacy/ and output/ directories) ───────────────
$ExcludePatterns = @(
    [regex]::Escape((Join-Path $RepoRoot 'legacy'))
    [regex]::Escape((Join-Path $RepoRoot 'output'))
    [regex]::Escape((Join-Path $RepoRoot 'Sage' 'data' 'output'))
    [regex]::Escape((Join-Path $RepoRoot 'Sage' 'tui' 'output'))
    [regex]::Escape((Join-Path $RepoRoot 'tui' 'output'))
)
$ExcludeRegex = ($ExcludePatterns | ForEach-Object { "($_)" }) -join '|'

$MdFiles = Get-ChildItem -Path $RepoRoot -Filter '*.md' -Recurse |
    Where-Object { $_.FullName -notmatch $ExcludeRegex } |
    Select-Object -ExpandProperty FullName

if ($MdFiles.Count -eq 0) {
    Write-Output 'MarkdownLint: no .md files found.'
    exit 0
}

Write-Verbose "MarkdownLint: scanning $($MdFiles.Count) file(s)."

# ── Run markdownlint-cli2 ─────────────────────────────────────────────────────
$StdOut = [System.IO.Path]::GetTempFileName()
$StdErr = [System.IO.Path]::GetTempFileName()
try {
    $Params = @{
        FilePath               = $ToolName
        ArgumentList           = $MdFiles
        NoNewWindow            = $true
        PassThru               = $true
        RedirectStandardOutput = $StdOut
        RedirectStandardError  = $StdErr
    }
    $Process = Start-Process @Params
    $Completed = $Process.WaitForExit(120000)
    if (-not $Completed) {
        $Process.Kill()
        Write-Output 'MarkdownLint: timed out after 120 seconds.'
        exit 1
    }
}
finally {
    # Show any lint findings from captured output before cleaning up
    if (Test-Path $StdOut) {
        $Output = Get-Content -Path $StdOut -Raw -ErrorAction SilentlyContinue
        if ($Output) { Write-Output $Output }
    }
    Remove-Item -Path $StdOut, $StdErr -Force -ErrorAction SilentlyContinue
}

if ($Process.ExitCode -eq 0) {
    Write-Output "MarkdownLint: clean run (0 findings across $($MdFiles.Count) file(s))."
    exit 0
}

Write-Output 'MarkdownLint: findings detected. Fix the issues listed above.'
exit 1
