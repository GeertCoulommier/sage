#Requires -Version 7.5
<#
.SYNOPSIS
    Child-process Pester runner for the Reference tests.
    Called by PesterContainerData.Tests.ps1 via: pwsh -File Invoke-PesterRunner.ps1
    NOT a test file — Pester only discovers *.Tests.ps1.
#>
param(
    [Parameter(Mandatory)]                                                                 [string] $EvalPath,
    [Parameter(Mandatory)]                                                                 [string] $ExamVarsPath,
    [Parameter(Mandatory)]                                                                 [string] $CollectedDataPath,
    [Parameter(Mandatory)]                                                                 [string] $ResultPath,
                                                                                           [string] $Tag = 'Evaluation'
)

$ErrorActionPreference = 'Stop'

try {
    $Tags          = $Tag -split ','
    $ExamVars      = Get-Content -Path $ExamVarsPath      -Raw | ConvertFrom-Json -AsHashtable
    $CollectedData = Get-Content -Path $CollectedDataPath -Raw | ConvertFrom-Json -AsHashtable

    $Container = New-PesterContainer -Path $EvalPath -Data @{
        ExamVariables = $ExamVars
        CollectedData = $CollectedData
    }
    $Cfg                    = New-PesterConfiguration
    $Cfg.Run.Container      = $Container
    $Cfg.Filter.Tag         = $Tags
    $Cfg.Output.Verbosity   = 'None'
    $Cfg.Run.PassThru       = $true

    $PesterResult = Invoke-Pester -Configuration $Cfg

    @{
        PassedCount = $PesterResult.PassedCount
        FailedCount = $PesterResult.FailedCount
        TotalCount  = $PesterResult.TotalCount
        Tests       = @($PesterResult.Tests | ForEach-Object {
            @{
                ExpandedName = $_.ExpandedName
                Result = $_.Result.ToString()
            }
        })
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $ResultPath -Encoding UTF8
}
catch {
    @{
        Error       = $_.Exception.Message
        PassedCount = 0
        FailedCount = 1
        TotalCount  = 1
        Tests       = @()
    } | ConvertTo-Json | Set-Content -Path $ResultPath -Encoding UTF8
}
