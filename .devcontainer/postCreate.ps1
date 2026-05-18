#!/usr/bin/env pwsh
# .devcontainer/postCreate.ps1
# One-time setup for the SAGE devcontainer. Installs PowerShell modules,
# configures the SecretStore vault in no-password mode, and installs the
# git pre-commit hook.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Seed password for non-interactive SecretStore initialisation in devcontainer.')]
param()

$ErrorActionPreference = 'Stop'

# ── PowerShell Modules ────────────────────────────────────────────────────────
Write-Host 'Installing PowerShell modules...' -ForegroundColor Cyan

$Modules = @(
    @{ Name = 'Pester'; RequiredVersion = '5.6.0' }
    @{ Name = 'ImportExcel'; MinimumVersion = '7.8.0' }
    @{ Name = 'Microsoft.PowerShell.SecretManagement'; MinimumVersion = '1.1.2' }
    @{ Name = 'Microsoft.PowerShell.SecretStore' }
    @{ Name = 'PSScriptAnalyzer' }
)

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

foreach ($Spec in $Modules) {
    $InstallParams = @{
        Name  = $Spec.Name
        Scope = 'CurrentUser'
        Force = $true
    }
    if ($Spec.RequiredVersion) { $InstallParams.RequiredVersion = $Spec.RequiredVersion }
    if ($Spec.MinimumVersion) { $InstallParams.MinimumVersion = $Spec.MinimumVersion }

    Write-Host "  $($Spec.Name)" -ForegroundColor Gray
    Install-Module @InstallParams
}

# ── SecretStore Vault (no-password mode) ──────────────────────────────────────
Write-Host 'Configuring SecretStore vault...' -ForegroundColor Cyan

# Provide a seed password for first-time initialisation, then switch authentication
# to None so the vault never prompts again (the container itself is the boundary).
$SeedPassword = ConvertTo-SecureString -String 'devcontainer-init' -AsPlainText -Force
$StoreConfigParams = @{
    Authentication = 'None'
    Interaction    = 'None'
    Password       = $SeedPassword
    Confirm        = $false
}
Set-SecretStoreConfiguration @StoreConfigParams

$VaultParams = @{
    Name         = 'SecretStore'
    ModuleName   = 'Microsoft.PowerShell.SecretStore'
    DefaultVault = $true
    AllowClobber = $true
}
Register-SecretVault @VaultParams

# ── Git Pre-Commit Hook ──────────────────────────────────────────────────────
Write-Host 'Installing pre-commit hook...' -ForegroundColor Cyan

$RepoRoot = Split-Path $PSScriptRoot
$HookSource = Join-Path $RepoRoot '.github' 'hooks' 'pre-commit'
$HookTarget = Join-Path $RepoRoot '.git' 'hooks' 'pre-commit'

if (Test-Path $HookSource) {
    $HookDir = Split-Path $HookTarget
    if (-not (Test-Path $HookDir)) {
        New-Item -ItemType Directory -Path $HookDir -Force | Out-Null
    }
    Copy-Item -Path $HookSource -Destination $HookTarget -Force
    if ($IsLinux -or $IsMacOS) {
        & chmod +x $HookTarget
    }
    Write-Host '  Hook installed.' -ForegroundColor Gray
}
else {
    Write-Host '  Hook source not found, skipping.' -ForegroundColor Yellow
}

Write-Host 'Devcontainer ready.' -ForegroundColor Green
