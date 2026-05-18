#Requires -Version 7.5
<#
.SYNOPSIS
    Sets the SAGE pipeline log file path for the current module scope.
.DESCRIPTION
    SAGE uses a $script:LogPath variable (module-scoped in Write-Log.ps1) to
    determine where structured JSONL log entries are written.  In the main
    process, Invoke-Evaluation sets this variable directly via $script:LogPath.

    The problem with ForEach-Object -Parallel
    ─────────────────────────────────────────
    When PowerShell executes ForEach-Object -Parallel, each student runs in an
    independent runspace.  Each runspace calls Import-Module, which creates a
    completely separate in-memory module scope.  The $script:LogPath that
    Invoke-Evaluation set in the *host* process is invisible inside that new
    module scope — it is $null, so Write-Log silently skips file output.

    Why not use $global: scope?
    ───────────────────────────
    Setting $global:SageLogPath avoids the isolation problem, but $global:
    variables are PowerShell process-level — they leak across all modules,
    pollute the caller's environment, and are inherently fragile in concurrent
    execution because any code anywhere can overwrite them.  They are the
    module-design equivalent of a global variable in C.

    The solution: Set-SageLogPath
    ──────────────────────────────
    Set-SageLogPath is a thin Public function whose ONLY purpose is to write
    into $script:LogPath in the module scope where it is called.  Because it
    is a Public function exported by the module, calling it just after
    Import-Module inside a parallel runspace targets the freshly-created module
    scope for THAT runspace — which is exactly where Write-Log will look.

    Usage inside Invoke-Evaluation's parallel block:

        Import-Module $ModulePath -Force    # creates a fresh module scope
        Set-SageLogPath -Path $LogPath      # fills $script:LogPath in that scope
        # all subsequent Write-Log calls now write to the shared log file

    Thread safety
    ─────────────
    Multiple parallel runspaces share one log file path but Write-Log uses a
    named mutex ('Local\sage-Log') to serialise file appends, so there is no
    risk of interleaved or corrupt JSONL lines.

    Scope model summary
    ───────────────────
    ┌────────────────────────────────────────────────────────────────────┐
    │ Host process (Invoke-Evaluation)                                    │
    │   $script:LogPath = $TempLogPath   ← set directly                  │
    │                                                                     │
    │   ForEach-Object -Parallel {                                        │
    │     Import-Module $ModPath -Force  ← new scope, $script:LogPath=∅  │
    │     Set-SageLogPath -Path $LogPath ← fills scope, no globals       │
    │     Write-Log ...                  ← sees $script:LogPath ✓         │
    │   }                                                                 │
    └────────────────────────────────────────────────────────────────────┘
.PARAMETER Path
    Absolute path to the .jsonl log file for the current pipeline.
    Pass $null or an empty string to clear the log path (stops file output).
.OUTPUTS
    [void]
.EXAMPLE
    # Called once per parallel runspace inside Invoke-Evaluation:
    Import-Module './Sage.psd1' -Force
    Set-SageLogPath -Path '/tmp/20260416-120000-MyExam.jsonl'
    # All Write-Log calls that follow now append to that file.
.EXAMPLE
    # Clear the log path at the end of a pipeline:
    Set-SageLogPath -Path ''
#>
function Set-SageLogPath {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()] [string] $Path
    )

    $ErrorActionPreference = 'Stop'

    # Write into the module-level $script:LogPath that Write-Log reads.
    # Assigning through a Public function ensures we target the correct scope
    # inside whichever runspace (or host process) calls this function.
    $script:LogPath = if ($Path) { $Path } else { $null }
}
