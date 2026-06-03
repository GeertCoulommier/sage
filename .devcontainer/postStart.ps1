#!/usr/bin/env pwsh
# .devcontainer/postStart.ps1
# Runs every time the devcontainer starts (including restarts after crashes).
# Cleans up orphaned SSH and PowerShell processes left by previously aborted
# SAGE pipelines or terminated Copilot sessions.

param()

$ErrorActionPreference = 'Continue'

Write-Host 'Post-start cleanup...' -ForegroundColor Cyan

# ── Remove stale PSSessions ──────────────────────────────────────────────────
$StaleSessions = @(Get-PSSession -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Opened' })
if ($StaleSessions.Count -gt 0) {
    Write-Host "  Removing $($StaleSessions.Count) stale PSSession(s)." -ForegroundColor Yellow
    $StaleSessions | Remove-PSSession -ErrorAction SilentlyContinue
}

# ── Kill orphaned ssh processes not owned by an active PSSession ─────────────
$ActiveSessionPids = @(Get-PSSession -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq 'Opened' -and $_.Transport -eq 'SSH' } |
    ForEach-Object { $_.ChildProcessId } |
    Where-Object { $_ })

$OrphanedSsh = @(Get-Process -Name 'ssh' -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -notin $ActiveSessionPids })

if ($OrphanedSsh.Count -gt 0) {
    Write-Host "  Stopping $($OrphanedSsh.Count) orphaned ssh process(es)." -ForegroundColor Yellow
    $OrphanedSsh | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host '  Cleanup complete.' -ForegroundColor Gray
