#Requires -Version 7.5
<#
.SYNOPSIS
    Closes one or more Sage.RemoteSession objects and removes their underlying PSSessions.
.DESCRIPTION
    Accepts one or more Sage.RemoteSession objects from the pipeline or -Session parameter
    and closes the underlying PSSession via Remove-PSSession.  Supports -WhatIf and
    -Confirm for safety.

    Before closing, removes temporary SAGE files from the remote VM:
      - /tmp/sage-evaluations/ (Linux) or $env:TEMP\sage-evaluations\ (Windows)
      - /tmp/sage-collectors/ (Linux) or $env:TEMP\sage-collectors\ (Windows)

    Any attempt to close an already-closed or disconnected session is silently
    ignored (idempotent).
.PARAMETER Session
    One or more Sage.RemoteSession objects to close.
.OUTPUTS
    [void]
.EXAMPLE
    $sessions | Close-RemoteSession
.EXAMPLE
    Close-RemoteSession -Session $winSession, $linuxSession -WhatIf
#>
function Close-RemoteSession {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][PSTypeName('Sage.RemoteSession')][PSCustomObject[]] $Session
    )

    begin {
        $ErrorActionPreference = 'Stop'
    }

    process {
        foreach ($S in $Session) {
            $Label = "'$($S.TargetName)' ($($S.HostName):$($S.Port))"
            if ($PSCmdlet.ShouldProcess($Label, 'Close-RemoteSession')) {
                # ── Clean up temporary SAGE files on remote VM ─────────────────
                if ($S.Session -and $S.Session.State -ne 'Closed') {
                    $IsRemoteWindows = $S.Platform -eq 'Windows'
                    try {
                        Invoke-Command -Session $S.Session -ScriptBlock {
                            $Dirs = if ($using:IsRemoteWindows) {
                                @(
                                    (Join-Path $env:TEMP 'sage-evaluations')
                                    (Join-Path $env:TEMP 'sage-collectors')
                                )
                            }
                            else {
                                @('/tmp/sage-evaluations', '/tmp/sage-collectors')
                            }
                            foreach ($Dir in $Dirs) {
                                if (Test-Path $Dir) {
                                    Remove-Item -Path $Dir -Recurse -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                        $LogParams = @{
                            Level    = 'Verbose'
                            Category = 'Session'
                            Message  = "Cleaned up temp files on $Label."
                            Target   = $S.TargetName
                        }
                        Write-Log @LogParams
                    }
                    catch {
                        $LogParams = @{
                            Level    = 'Warning'
                            Category = 'Session'
                            Message  = "Failed to clean up temp files on ${Label}: $($_.Exception.Message)"
                            Target   = $S.TargetName
                        }
                        Write-Log @LogParams
                    }
                }

                # ── Close the PSSession ────────────────────────────────────────
                try {
                    if ($S.Session -and $S.Session.State -ne 'Closed') {
                        Remove-PSSession -Session $S.Session -ErrorAction SilentlyContinue
                    }
                    $LogParams = @{
                        Level    = 'Info'
                        Category = 'Session'
                        Message  = "Session closed for $Label."
                        Target   = $S.TargetName
                    }
                    Write-Log @LogParams
                }
                catch {
                    $LogParams = @{
                        Level    = 'Warning'
                        Category = 'Session'
                        Message  = "Error while closing session ${Label}: $($_.Exception.Message)"
                        Target   = $S.TargetName
                    }
                    Write-Log @LogParams
                }
            }
        }
    }
}
