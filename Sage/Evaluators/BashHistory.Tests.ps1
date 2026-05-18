# Evaluations/BashHistory.Tests.ps1
# Bash history and cmd.log evaluation — tests driven entirely by exam data.
# Contains ONLY assertion logic — no expected values hardcoded.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExamVariables',
    Justification = 'Injected by the evaluation framework; consumed by Pester test blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CollectedData',
    Justification = 'Injected by the evaluation framework; consumed by Pester test blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ReviewContextMap',
    Justification = 'Consumed by ConvertTo-GradeSummary via Get-Variable after dot-sourcing this file.')]
param(
    [Parameter(Mandatory)][hashtable] $ExamVariables,
    [Parameter(Mandatory)][hashtable] $CollectedData
)

# ── Review Context Map (for Edit-Grade) ──────────────────────────────────────
$ReviewContextMap = @{
    'Bash History' = {
        param($Data)
        $Data.BashHistory | ForEach-Object {
            [PSCustomObject]@{
                Timestamp = $_.Timestamp
                Command   = $_.Command
            }
        }
    }
    'Cmd Log' = {
        param($Data)
        $Data.CmdLog | ForEach-Object {
            [PSCustomObject]@{
                Timestamp  = $_.Timestamp
                Command    = $_.Command
                User       = $_.User
                RemoteHost = $_.RemoteHost
            }
        }
    }
}

Describe 'Bash History and Cmd Log' -Tag 'Evaluation' {

    BeforeDiscovery {
        $V = $ExamVariables
        if (-not $V.BashKeywordTests) { $V.BashKeywordTests = @() }
        if (-not $V.CmdLogKeywordTests) { $V.CmdLogKeywordTests = @() }
        if (-not $V.AllowedNetworkTests) { $V.AllowedNetworkTests = @() }
    }

    Context 'Bash History Keywords' {
        It 'Bash history should contain command matching <Keyword>' -ForEach $V.BashKeywordTests {
            $AllCommands = $CollectedData.BashHistory | ForEach-Object { $_.Command }
            $MatchingCommand = $AllCommands | Where-Object { $_ -match [regex]::Escape($Keyword) }
            $MatchingCommand | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Cmd Log Keywords' {
        It 'Cmd log should contain command matching <Keyword>' -ForEach $V.CmdLogKeywordTests {
            $AllCommands = $CollectedData.CmdLog | ForEach-Object { $_.Command }
            $MatchingCommand = $AllCommands | Where-Object { $_ -match [regex]::Escape($Keyword) }
            $MatchingCommand | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Network Origin Validation' {
        It 'All cmd.log connections should be from allowed networks' -ForEach $V.AllowedNetworkTests {
            $AllHosts = $CollectedData.CmdLog |
                Where-Object { $_.RemoteHost -ne 'localhost' -and $null -ne $_.RemoteHost } |
                ForEach-Object { $_.RemoteHost } |
                Select-Object -Unique

            foreach ($RemoteAddr in $AllHosts) {
                $IsAllowed = $false
                foreach ($Range in $AllowedRanges) {
                    if ($RemoteAddr -match [regex]::Escape($Range) -or $RemoteAddr -eq $Range) {
                        $IsAllowed = $true
                        break
                    }
                }
                $IsAllowed | Should -BeTrue -Because "Host $RemoteAddr should be in allowed ranges"
            }
        }
    }
}
