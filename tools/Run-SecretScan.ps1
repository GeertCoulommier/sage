#Requires -Version 7.5
<#
.SYNOPSIS
    Scans staged Git file contents for common secret patterns.
.DESCRIPTION
    Retrieves the diff of staged files and searches for credential-like patterns
    such as hard-coded passwords, API keys, tokens, and private key headers.
    Only checks lines being *added* (lines starting with '+' in the diff output).

    Exit codes:
        0  — no secret-like patterns found
        1  — one or more potential secrets detected
.PARAMETER Base
    Git ref to diff against (e.g. 'HEAD~1'). When provided, runs
    'git diff <Base> --unified=0' instead of 'git diff --cached'.
    Useful in CI where there is no staging area.
.EXAMPLE
    pwsh -NoProfile -File tools/Run-SecretScan.ps1
.EXAMPLE
    pwsh -NoProfile -File tools/Run-SecretScan.ps1 -Base HEAD~1
#>
[CmdletBinding()]
param(
    [Parameter()] [string] $Base
)

$ErrorActionPreference = 'Stop'

# ── Secret patterns ───────────────────────────────────────────────────────────
# Each entry: @{ Name = 'label'; Pattern = 'regex' }
$SecretRules = @(
    @{ Name = 'Hard-coded password'    ; Pattern = '(?i)(password|passwd|pwd)\s*[=:]\s*[''"]?.{4,}' }
    @{ Name = 'Hard-coded secret'      ; Pattern = '(?i)(?<!\w)(secret|api[_-]?key|access[_-]?token)\s*[=:]\s*[''"]?(?!\$).{6,}' }
    @{ Name = 'PEM private key header' ; Pattern = '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' }
    @{ Name = 'Connection string creds'; Pattern = '(?i)(jdbc|mssql|mysql|postgres)://[^:]+:[^@]+@' }
    @{ Name = 'PowerShell SecureString plaintext' ; Pattern = '(?i)ConvertTo-SecureString\s+[''"][^$]' }
)

# ── Paths excluded from secret scanning ──────────────────────────────────────
# Intentional key material committed to sage-private (stripped from public mirror
# by sync-public.yml — see .github/workflows/sync-public.yml).
$ExcludedPaths = @(
    'tui/keys/'
    # Student lab exam definitions intentionally contain the student VM password
    # ('Student1') as Variables.Password so the collector can run sudo -S
    # commands (e.g. firewall-cmd) on VMs that require a password for sudo.
    # This is not a production secret — it is the well-known lab credential
    # documented in CLAUDE.md and used exclusively for student evaluation VMs.
    'Sage/data/werkcolleges/'
)

# ── Collect diff additions ─────────────────────────────────────────────────────
if ($Base) {
    $Diff = git diff $Base --unified=0 2>$null
}
else {
    $Diff = git diff --cached --unified=0 2>$null
}
if (-not $Diff) {
    Write-Output 'SecretScan: no changes to inspect.'
    exit 0
}

# Parse diff into per-file chunks and skip excluded paths.
# Lines added look like: ^+[^+] (single plus, not the +++ file header).
$AddedLines = [System.Collections.Generic.List[string]]::new()
$CurrentFile = ''
foreach ($Line in ($Diff -split "`n")) {
    if ($Line -match '^\+\+\+ b/(.+)$') {
        $CurrentFile = $Matches[1]
    }
    elseif ($Line -match '^\+[^+]') {
        $Skip = $ExcludedPaths | Where-Object { $CurrentFile -like "${_}*" }
        if (-not $Skip) {
            $AddedLines.Add($Line.TrimStart('+'))
        }
    }
}

if ($AddedLines.Count -eq 0) {
    Write-Output 'SecretScan: no added lines in staged diff.'
    exit 0
}

# ── Scan each added line against every rule ───────────────────────────────────
$Violations = [System.Collections.Generic.List[string]]::new()

foreach ($Rule in $SecretRules) {
    $MatchedLines = $AddedLines | Where-Object { $_ -match $Rule.Pattern }
    foreach ($Line in $MatchedLines) {
        $Violations.Add("  [$($Rule.Name)] $Line")
    }
}

if ($Violations.Count -eq 0) {
    Write-Output 'SecretScan: no secrets detected in staged changes.'
    exit 0
}

Write-Host ''
Write-Host '❌ SecretScan: potential secrets found in staged changes!' -ForegroundColor Red
Write-Host '   Review and remove before committing:' -ForegroundColor Yellow
$Violations | ForEach-Object { Write-Host $_ -ForegroundColor Red }
Write-Host ''
Write-Host '   If this is a false positive, un-stage the file and use a variable or' -ForegroundColor Yellow
Write-Host '   environment-based credential instead of a hard-coded value.' -ForegroundColor Yellow
Write-Host ''
exit 1
