#Requires -Version 7.5
<#
.SYNOPSIS
    SAGE Self-Check launcher.
.DESCRIPTION
    Imports the SAGE module from the parent directory and launches the
    interactive TUI for student self-evaluation.
.EXAMPLE
    ./Start-SelfCheck.ps1
#>

$ErrorActionPreference = 'Stop'

# ── Import SAGE module ─────────────────────────────────────────────────────────
$ModulePath = Join-Path $PSScriptRoot '..' 'Sage.psd1'
if (-not (Test-Path $ModulePath)) {
    Write-Host 'Error: SAGE module not found. Run this from the tui/ directory.' -ForegroundColor Red
    exit 1
}
Import-Module $ModulePath -Force

# ── Launch TUI ─────────────────────────────────────────────────────────────────
Invoke-SelfCheck -TuiPath $PSScriptRoot
