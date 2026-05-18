#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Reference: end-to-end Pester Container Data flow (child-process safe).
.DESCRIPTION
    IMPORTANT: Nested Invoke-Pester calls run in a CHILD pwsh process via
    Invoke-PesterRunner.ps1. In-process nested Invoke-Pester corrupts the
    VS Code extension host runspace, crashing VS Code.
.TAGS Reference
#>

BeforeAll {
    # Runs Pester in a detached child process — never touches the outer session.
    # Must be defined inside BeforeAll so Pester v5's scope isolation doesn't hide it.
    function Invoke-ChildPester {
        param(
            [Parameter(Mandatory)]                                                         [string] $EvalPath,
            [Parameter(Mandatory)]                                                      [hashtable] $ExamVariables,
            [Parameter(Mandatory)]                                                      [hashtable] $CollectedData,
            [string[]] $Tag = @('Evaluation')
        )
        $TmpEV = [System.IO.Path]::GetTempFileName()
        $TmpCD = [System.IO.Path]::GetTempFileName()
        $TmpR = [System.IO.Path]::GetTempFileName()
        $Runner = Join-Path $PSScriptRoot 'Invoke-PesterRunner.ps1'
        try {
            $ExamVariables | ConvertTo-Json -Depth 5 | Set-Content $TmpEV -Encoding UTF8
            $CollectedData | ConvertTo-Json -Depth 5 | Set-Content $TmpCD -Encoding UTF8
            $TagStr = $Tag -join ','
            $PwshArgs = @('-NoProfile', '-NonInteractive', '-File', $Runner,
                '-EvalPath', $EvalPath, '-ExamVarsPath', $TmpEV,
                '-CollectedDataPath', $TmpCD, '-ResultPath', $TmpR, '-Tag', $TagStr)

            # Use Start-Process with a timeout to prevent indefinite hangs
            # that freeze the PSIC and crash the VS Code extension host.
            $StdOutTmp = [System.IO.Path]::GetTempFileName()
            $StdErrTmp = [System.IO.Path]::GetTempFileName()
            $ProcParams = @{
                FilePath               = 'pwsh'
                ArgumentList           = $PwshArgs
                NoNewWindow            = $true
                PassThru               = $true
                RedirectStandardOutput = $StdOutTmp
                RedirectStandardError  = $StdErrTmp
            }
            try {
                $Proc = Start-Process @ProcParams
                $TimeoutMs = 30000
                if (-not $Proc.WaitForExit($TimeoutMs)) {
                    $Proc.Kill()
                    $Proc.WaitForExit(2000)
                    return [PSCustomObject]@{
                        PassedCount = 0
                        FailedCount = 1
                        TotalCount  = 1
                        Tests       = @()
                        Error       = "Child process timed out after $($TimeoutMs / 1000)s"
                    }
                }
            }
            finally {
                Remove-Item $StdOutTmp, $StdErrTmp -Force -ErrorAction SilentlyContinue
            }

            if (-not (Test-Path $TmpR) -or (Get-Item $TmpR).Length -eq 0) {
                return [PSCustomObject]@{
                    PassedCount = 0
                    FailedCount = 1
                    TotalCount  = 1
                    Tests       = @()
                    Error       = 'No child output'
                }
            }
            $Raw = Get-Content $TmpR -Raw | ConvertFrom-Json
            [PSCustomObject]@{
                PassedCount = [int]$Raw.PassedCount
                FailedCount = [int]$Raw.FailedCount
                TotalCount  = [int]$Raw.TotalCount
                Tests       = @($Raw.Tests | ForEach-Object {
                        [PSCustomObject]@{
                            ExpandedName = $_.ExpandedName
                            Result       = $_.Result
                        }
                    })
                Error       = $Raw.Error
            }
        }
        finally {
            Remove-Item $TmpEV, $TmpCD, $TmpR -Force -ErrorAction SilentlyContinue
        }
    }


    $script:EvalFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.Tests.ps1'

    # Minimal evaluation script using Container Data pattern
    $EvalContent = @(
        'param($ExamVariables, $CollectedData)'
        ''
        'Describe "DNS Evaluation" -Tag "Evaluation" {'
        '    It "A records list is not empty" -Tag "Evaluation" {'
        '        $CollectedData.ARecords | Should -Not -BeNullOrEmpty'
        '    }'
        '    It "Server FQDN matches expected" -Tag "Evaluation" {'
        '        $CollectedData.ServerFQDN | Should -Be $ExamVariables.ExpectedFQDN'
        '    }'
        '}'
    ) -join [System.Environment]::NewLine
    Set-Content -Path $script:EvalFile -Value $EvalContent -Encoding UTF8

    $ExamVars = @{ ExpectedFQDN = 'dc01.corp.local' }

    $FullData = @{
        ServerFQDN = 'dc01.corp.local'
        ARecords   = @('192.168.1.10')
    }
    $EmptyData = @{
        ServerFQDN = 'dc01.corp.local'
        ARecords   = @()
    }

    $script:RFull = Invoke-ChildPester -EvalPath $script:EvalFile -ExamVariables $ExamVars -CollectedData $FullData
    $script:REmpty = Invoke-ChildPester -EvalPath $script:EvalFile -ExamVariables $ExamVars -CollectedData $EmptyData
}

AfterAll {
    Remove-Item $script:EvalFile -Force -ErrorAction SilentlyContinue
}

Describe 'Pester Container Data flow (Reference)' -Tag 'Reference' {

    Context 'Run with full data' {
        It 'completes without error' {
            $script:RFull.Error | Should -BeNullOrEmpty
        }
        It 'runs 2 tests' {
            $script:RFull.TotalCount | Should -Be 2
        }
        It 'passes all tests' {
            $script:RFull.FailedCount | Should -Be 0
        }
        It 'exposes individual test results' {
            $script:RFull.Tests | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Run with empty ARecords' {
        It 'completes without error' {
            $script:REmpty.Error | Should -BeNullOrEmpty
        }
        It 'runs 2 tests' {
            $script:REmpty.TotalCount | Should -Be 2
        }
        It 'fails the ARecords test' {
            $script:REmpty.FailedCount | Should -BeGreaterThan 0
        }
    }

    Context 'Evaluation test names' {
        It 'includes A records test name' {
            $Names = $script:RFull.Tests.ExpandedName
            $Names | Should -Contain 'A records list is not empty'
        }
        It 'includes FQDN test name' {
            $Names = $script:RFull.Tests.ExpandedName
            $Names | Should -Contain 'Server FQDN matches expected'
        }
    }
}
