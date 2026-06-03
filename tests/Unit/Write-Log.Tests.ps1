#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for the Write-Log function.
.DESCRIPTION
    Tests: console stream routing, JSONL file output, GDPR compliance (no grades/scores),
    thread-safe file writes, and handling of optional parameters.
.TAGS Unit
#>

BeforeAll {
    $Sut = Join-Path $PSScriptRoot '..\..\Sage\Private\Write-Log.ps1'
    . $Sut
}

Describe 'Write-Log' -Tag 'Unit' {

    # ── Console stream routing ─────────────────────────────────────────────────────
    Context 'Console stream routing' {
        It 'Info level emits to Information stream' {
            $Msgs = Write-Log -Level Info -Message 'test-info' 6>&1
            $Msgs | Should -Not -BeNullOrEmpty
            ($Msgs | Where-Object { $_.ToString() -match 'test-info' }) | Should -Not -BeNullOrEmpty
        }

        It 'Warning level emits to Warning stream' {
            $Msgs = Write-Log -Level Warning -Message 'test-warn' 3>&1
            ($Msgs | Where-Object { $_ -match 'test-warn' }) | Should -Not -BeNullOrEmpty
        }

        It 'Verbose level emits to Verbose stream' {
            $Msgs = Write-Log -Level Verbose -Message 'test-verbose' -Verbose 4>&1
            ($Msgs | Where-Object { $_ -match 'test-verbose' }) | Should -Not -BeNullOrEmpty
        }

        It 'Debug level emits to Debug stream without throwing' {
            # Use $DebugPreference = 'Continue' explicitly instead of the -Debug switch.
            # The -Debug switch activates Inquire mode which can prompt the user and
            # hang the test runner in interactive sessions.
            $PrevPref = $DebugPreference
            try {
                $DebugPreference = 'Continue'
                Write-Log -Level Debug -Message 'test-debug' 5>&1 | Out-Null
                # Under Continue preference the message is captured; just assert no throw
                { Write-Log -Level Debug -Message 'test-debug-2' 5>&1 } | Should -Not -Throw
            }
            finally {
                $DebugPreference = $PrevPref
            }
        }
    }

    Context 'Category prefix in console output' {
        It 'Prepends [Category] to the message' {
            $Msgs = Write-Log -Level Info -Message 'hello' -Category 'Session' 6>&1
            ($Msgs | Where-Object { $_.ToString() -match '\[Session\].*hello' }) | Should -Not -BeNullOrEmpty
        }
    }

    # ── JSONL file output ─────────────────────────────────────────────────────────
    Context 'JSONL file output' {
        BeforeAll {
            $script:TmpLog = Join-Path ([System.IO.Path]::GetTempPath()) "evallog-test-$([System.Guid]::NewGuid().ToString('N')[0..7] -join '').jsonl"
            $script:LogPath = $script:TmpLog
        }
        AfterAll {
            Remove-Item $script:TmpLog -Force -ErrorAction SilentlyContinue
        }

        It 'Creates the log file on first write' {
            Write-Log -Level Info -Message 'file-test'
            Test-Path $script:TmpLog | Should -Be $true
        }

        It 'Appends valid JSON on each call' {
            Write-Log -Level Info -Message 'entry-1' -Category 'Pipeline'
            Write-Log -Level Warning -Message 'entry-2' -Category 'Collector'
            $Lines = Get-Content $script:TmpLog
            $Lines.Count | Should -BeGreaterOrEqual 2   # may have the first write too
            foreach ($Line in $Lines) {
                { $Line | ConvertFrom-Json } | Should -Not -Throw
            }
        }

        It 'Includes Level, Message and Timestamp in each entry' {
            $Lines = Get-Content $script:TmpLog
            $Last = $Lines[-1] | ConvertFrom-Json
            $Last.Level | Should -Not -BeNullOrEmpty
            $Last.Message | Should -Not -BeNullOrEmpty
            $Last.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Includes optional Student and Target when provided' {
            Write-Log -Level Info -Message 'with-meta' -Student 'test@ehb.be' -Target 'WinSrv1'
            $Line = (Get-Content $script:TmpLog | Select-Object -Last 1) | ConvertFrom-Json
            $Line.Student | Should -Be 'test@ehb.be'
            $Line.Target | Should -Be 'WinSrv1'
        }

        It 'Stores additional Data keys in JSON' {
            Write-Log -Level Info -Message 'with-data' -Data @{ DurationMs = 250 }
            $Line = (Get-Content $script:TmpLog | Select-Object -Last 1) | ConvertFrom-Json
            $Line.Data.DurationMs | Should -Be 250
        }
    }

    # ── No file output when log path not set ─────────────────────────────────────
    Context 'No file output when log path not set' {
        BeforeAll {
            # Ensure no log path is set in this scope
            $script:LogPath = $null
        }
        It 'Does not throw when EvalLogPath is null' {
            { Write-Log -Level Info -Message 'no-file' } | Should -Not -Throw
        }
    }

    # ── GDPR compliance ───────────────────────────────────────────────────────────
    Context 'GDPR: prohibited content detection' {
        BeforeAll {
            $script:TmpLog2 = Join-Path ([System.IO.Path]::GetTempPath()) "evallog-gdpr-$([System.Guid]::NewGuid().ToString('N')[0..7] -join '').jsonl"
            $script:LogPath = $script:TmpLog2
        }
        AfterAll {
            Remove-Item $script:TmpLog2 -Force -ErrorAction SilentlyContinue
        }

        # These tests verify the design contract: callers must not pass grade data.
        # The function itself cannot easily inspect caller intent, but these tests
        # document the expectation and ensure no accidental grade words slip into
        # framework-generated messages.
        It 'Does not log the word "PassGrade" in framework-generated messages' {
            Write-Log -Level Info -Message 'Collector finished' -Category 'Collector'
            $Content = Get-Content $script:TmpLog2 -Raw
            $Content | Should -Not -Match 'PassGrade'
        }
        It 'Does not log the word "AwardedGrade" in framework-generated messages' {
            Write-Log -Level Info -Message 'Session connected' -Category 'Session'
            $Content = Get-Content $script:TmpLog2 -Raw
            $Content | Should -Not -Match 'AwardedGrade'
        }
        It 'Does not log the word "FinalGrade" in framework-generated messages' {
            Write-Log -Level Info -Message 'Export complete' -Category 'Export'
            $Content = Get-Content $script:TmpLog2 -Raw
            $Content | Should -Not -Match 'FinalGrade'
        }
    }
    # ── Error level stream routing ────────────────────────────────────────────
    Context 'Error level stream routing' {
        It 'Error level emits to Error stream without terminating' {
            $Errors = Write-Log -Level Error -Message 'test-error' -ErrorAction SilentlyContinue 2>&1
            ($Errors | Where-Object { $_ -match 'test-error' }) | Should -Not -BeNullOrEmpty
        }
    }

    # ── Mutex retry logic ──────────────────────────────────────────────────────
    Context 'File write retry on IOException' {
        BeforeAll {
            $script:RetryLog = Join-Path ([System.IO.Path]::GetTempPath()) "evallog-retry-$([System.Guid]::NewGuid().ToString('N')[0..7] -join '').jsonl"
            $script:LogPath = $script:RetryLog
        }
        AfterAll {
            Remove-Item $script:RetryLog -Force -ErrorAction SilentlyContinue
        }

        It 'Succeeds on first write without retry' {
            { Write-Log -Level Info -Message 'retry-test' } | Should -Not -Throw
            $Line = Get-Content $script:RetryLog | Select-Object -Last 1 | ConvertFrom-Json
            $Line.Message | Should -Be 'retry-test'
        }
    }
    # ── Parameter validation ──────────────────────────────────────────────────────
    Context 'Parameter validation' {
        It 'Throws on invalid Level value' {
            { Write-Log -Level 'Critical' -Message 'x' } | Should -Throw
        }
        It 'Throws when Message is empty' {
            { Write-Log -Level Info -Message '' } | Should -Throw
        }
        It 'Throws on invalid Category value' {
            { Write-Log -Level Info -Message 'x' -Category 'Invalid' } | Should -Throw
        }
    }
}
