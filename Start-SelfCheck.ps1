#Requires -Version 7.5
<#
.SYNOPSIS
    SAGE Self-Check — root launcher.
.DESCRIPTION
    Convenience entry point for students. Delegates to the TUI launcher inside
    the module directory:

        Sage/tui/Start-SelfCheck.ps1

    This file exists at the repo root so students can start the self-check
    without navigating into the module subdirectory.
.EXAMPLE
    pwsh ./Start-SelfCheck.ps1
#>

$ErrorActionPreference = 'Stop'

$TuiLauncher = Join-Path $PSScriptRoot 'Sage' 'tui' 'Start-SelfCheck.ps1'
if (-not (Test-Path $TuiLauncher)) {
    Write-Host 'Error: SAGE module not found. Ensure you cloned the full repository.' -ForegroundColor Red
    exit 1
}

& $TuiLauncher
