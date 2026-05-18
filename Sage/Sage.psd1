#Requires -Version 7.5
@{
    # ── Identity ──────────────────────────────────────────────────────────────────
    RootModule        = 'Sage.psm1'
    ModuleVersion     = '0.11.1'
    GUID              = '8209dfc6-b99a-4257-a06e-2ca072cdc21b'
    Author            = 'Geert Coulommier'
    CompanyName       = 'Erasmushogeschool Brussel'
    Copyright         = '(c) 2026 Geert Coulommier. All rights reserved.'
    Description       = 'Evaluates student server configurations on remote VMs via SSH and grades them using Pester.'
    PowerShellVersion = '7.5'

    # ── Exported symbols ──────────────────────────────────────────────────────────
    # Only functions that have been implemented are listed here.
    # Update FunctionsToExport in each subsequent phase.
    FunctionsToExport = @(
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
        # Phase 7 parallel log-path initialiser — see Public/Set-SageLogPath.ps1
        'Set-SageLogPath'
        # Phase 7 parallel student wrapper — see Public/Invoke-StudentEvaluation.ps1
        'Invoke-StudentEvaluation'
        # VM management
        'Install-SshKey'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # ── Required modules ──────────────────────────────────────────────────────────
    # Pester is a test-time dependency; declaring it here ensures it is available
    # when the module is imported in a CI/CD context.
    RequiredModules   = @(
        @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
    )

    # ── Metadata ──────────────────────────────────────────────────────────────────
    PrivateData       = @{
        PSData = @{
            Tags         = @('Evaluation', 'SSH', 'Pester', 'Grading', 'Education')
            ProjectUri   = 'https://github.com/GeertCoulommier/SAGE'
            ReleaseNotes = 'TUI SSH key setup, target auth gating, and domain prompt input hardening.'
        }
    }
}
