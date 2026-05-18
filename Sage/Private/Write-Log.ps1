#Requires -Version 7.5
<#
.SYNOPSIS
    Writes a structured diagnostic log entry (console stream + JSONL file).
.DESCRIPTION
    GDPR-compliant logging: this function MUST NOT log grades, pass/fail
    results, scores, or any data that reveals academic performance.
    Log only technical diagnostic information (timings, connectivity,
    collector errors, file operations, module installs).

    Console output uses the appropriate PowerShell stream:
      Info    → Write-Information
      Warning → Write-Warning
      Error   → Write-Error
      Debug   → Write-Debug
      Verbose → Write-Verbose

    File output appends a single JSON line to a .jsonl file located at:
      <ModuleRoot>/logs/<timestamp>-<ExamName>.jsonl
    The log file path is sourced from the $script:LogPath module
    variable set by Invoke-Evaluation at pipeline start.

    Thread safety: file writes use a named mutex to support parallel
    student processing (Phase 7 ThrottleLimit > 1).
.PARAMETER Level
    Severity level for the log entry.
.PARAMETER Message
    Human-readable diagnostic message. Must NOT contain grade values.
.PARAMETER Category
    Processing stage that produced this log entry.
.PARAMETER Student
    Student email address (for correlation). Optional; technical use only.
.PARAMETER Target
    Target VM name from exam.psd1 (for correlation).
.PARAMETER Data
    Additional structured key/value pairs. Must NOT contain grade values.
.OUTPUTS
    [void]
.EXAMPLE
    Write-Log -Level Info -Category Session -Message 'PSSession opened for LinuxVM.'
    # Emits to Write-Information and appends a JSONL entry when a log path is active.
#>
function Write-Log {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '',
        Justification = 'Write-Log is not a built-in cmdlet in PowerShell 7.5; false positive from legacy reference tables')]
    param(
        [Parameter(Mandatory)][ValidateSet('Info', 'Warning', 'Error', 'Debug', 'Verbose')] [string] $Level,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                    [string] $Message,
        [Parameter()]
        [ValidateSet('Session', 'Setup', 'Collector', 'Pester', 'Export', 'Diagnostic', 'Pipeline', 'Grading')]
        [string] $Category,
        [Parameter()]                                                                       [string] $Student,
        [Parameter()]                                                                       [string] $Target,
        [Parameter()]                                                                    [hashtable] $Data
    )

    $ErrorActionPreference = 'Stop'

    # ── Console stream output ─────────────────────────────────────────────────────
    $Prefix = if ($Category) { "[$Category] " } else { '' }
    $Console = "${Prefix}${Message}"

    switch ($Level) {
        'Info' { Write-Information $Console -InformationAction Continue }
        'Warning' { Write-Warning $Console }
        'Error' { Write-Error $Console -ErrorAction Continue }
        'Debug' { Write-Debug $Console }
        'Verbose' { Write-Verbose $Console }
    }

    # ── Structured JSONL file output ──────────────────────────────────────────────
    # Resolve the active log file path.
    # In the host process: Invoke-Evaluation sets $script:LogPath directly.
    # In parallel runspaces: Invoke-Evaluation calls Set-SageLogPath immediately
    # after Import-Module, which writes the path into $script:LogPath in the
    # freshly-created module scope for that runspace.  Either way, $script:LogPath
    # is the single authoritative source — no $global: variables needed.
    $LogPathToUse = $script:LogPath

    if (-not $LogPathToUse) { return }

    $Entry = [ordered]@{
        Timestamp = [datetime]::Now.ToString('o')   # ISO 8601 with Brussels local time
        Level     = $Level
        Category  = $Category
        Message   = $Message
    }
    if ($Student) { $Entry.Student = $Student }
    if ($Target) { $Entry.Target = $Target }
    if ($Data) { $Entry.Data = $Data }

    $JsonLine = $Entry | ConvertTo-Json -Compress -Depth 5

    # Thread-safe append via named mutex (supports -Parallel in Phase 7).
    # IMPORTANT: $acquired tracks whether WaitOne() succeeded.
    # ReleaseMutex() MUST NOT be called when WaitOne() timed out (returned $false)
    # — doing so throws ApplicationException and crashes the PowerShell host.
    # Use Local\ prefix (not Global\) to avoid UAC/admin requirement on Windows.
    $Mutex = $null
    $Acquired = $false
    try {
        $Mutex = [System.Threading.Mutex]::new($false, 'Local\sage-Log')
        $Acquired = $Mutex.WaitOne(5000)   # 5-second timeout
        if ($Acquired) {
            # Retry up to 3 times to handle transient cloud-sync file locks.
            $AppendDone = $false
            for ($Retry = 0; $Retry -lt 3 -and -not $AppendDone; $Retry++) {
                try {
                    [System.IO.File]::AppendAllText(
                        $LogPathToUse,
                        "${JsonLine}`n",
                        [System.Text.Encoding]::UTF8
                    )
                    $AppendDone = $true
                }
                catch [System.IO.IOException] {
                    if ($Retry -lt 2) {
                        [System.Threading.Thread]::Sleep(100)
                    }
                }
            }
        }
        # Silently skip file write on mutex timeout — console output already emitted above
    }
    catch {
        # Non-IO errors are non-fatal; console output already emitted
        Write-Verbose "Write-Log: file append failed: $($_.Exception.Message)"
    }
    finally {
        # Only release if we acquired — calling ReleaseMutex on an unacquired mutex
        # throws ApplicationException which crashes the PowerShell extension host.
        if ($Acquired) {
            try { $Mutex.ReleaseMutex() } catch { Write-Verbose "Write-Log: mutex release failed: $($_.Exception.Message)" }
        }
        if ($Mutex) {
            try { $Mutex.Dispose() } catch { Write-Verbose "Write-Log: mutex dispose failed: $($_.Exception.Message)" }
        }
    }
}
