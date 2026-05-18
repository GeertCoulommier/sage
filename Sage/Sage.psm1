#Requires -Version 7.5
<#
.SYNOPSIS
    SAGE module loader.
.DESCRIPTION
    Dot-sources all Public and Private functions in definition order.
    Public functions are explicitly exported; Private functions remain module-internal.
#>

$ErrorActionPreference = 'Stop'

# ── Dot-source Private functions first (Public may depend on them) ──────────────
$PrivatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $PrivatePath) {
    Get-ChildItem -Path $PrivatePath -Filter '*.ps1' -Recurse |
        ForEach-Object { . $_.FullName }
}

# ── Dot-source Public functions ───────────────────────────────────────────────────
$PublicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path $PublicPath) {
    Get-ChildItem -Path $PublicPath -Filter '*.ps1' -Recurse |
        ForEach-Object { . $_.FullName }
}

# ── Export Public functions ───────────────────────────────────────────────────────
# Export-ModuleMember is the single source of truth for what the module exposes.
# The list must stay in sync with FunctionsToExport in SAGE.psd1.
Export-ModuleMember -Function @(
    # Phase 1
    'Test-ExamDefinition'
    # Phase 2
    'New-RemoteSession'
    'Close-RemoteSession'
    'Import-ExamDefinition'
    # Phase 3
    'Get-GradeSummary'
    'Export-GradeSummary'
    'Edit-Grade'
    'Set-Credential'
    'Import-Credential'
    # Phase 4
    'Invoke-Evaluation'
    'Invoke-Diagnostic'
    'Invoke-SelfCheck'
    # Phase 7 parallel log-path initialiser:
    # Set-SageLogPath is called once per parallel runspace immediately after
    # Import-Module so that the freshly-created module scope gets a valid
    # $script:LogPath before any Write-Log calls are made.  Private functions
    # remain private; this single thin function is the only cross-scope bridge
    # needed for parallel execution.  See Public/Set-SageLogPath.ps1 for the
    # full design rationale.
    'Set-SageLogPath'
    # Invoke-StudentEvaluation encapsulates all per-student pipeline work so
    # that the ForEach-Object -Parallel scriptblock in Invoke-Evaluation only
    # needs to call this one public function.  Private helpers (Write-Log,
    # Invoke-RemoteSetup, etc.) are called from inside this module function
    # where they are accessible, not from the scriptblock where they are not.
    # See Public/Invoke-StudentEvaluation.ps1 for the full design rationale.
    'Invoke-StudentEvaluation'
    # VM management — SSH key distribution across computer sets
    'Install-SshKey'
)
