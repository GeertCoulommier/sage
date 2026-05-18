#Requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter()] [switch] $IncludeLegacy,
    [Parameter()] [string] $SettingsPath = (Join-Path -Path $PSScriptRoot '..' 'PSScriptAnalyzerSettings.psd1')
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ResolvedSettingsPath = (Resolve-Path $SettingsPath).Path

$Results = Invoke-ScriptAnalyzer -Path $RepoRoot -Recurse -Severity Warning, Error -Settings $ResolvedSettingsPath

if (-not $IncludeLegacy) {
    $Results = @($Results | Where-Object { $_.ScriptPath -notmatch '[/\\]legacy[/\\]' })
}

# ConvertTo-SecureString with plaintext is expected in test files (fake credentials for mocking).
$Results = @($Results | Where-Object {
        -not ($_.RuleName -eq 'PSAvoidUsingConvertToSecureStringWithPlainText' -and $_.ScriptPath -match '[/\\]Tests[/\\]')
    })

# Pester-specific false positives in test files:
#   PSUseDeclaredVarsMoreThanAssignments — BeforeEach variables ARE used in It blocks; PSA can't
#       track Pester's scope injection across blocks.
#   PSReviewUnusedParameter             — Mock function parameters must match real signatures even
#       when the stub body ignores them.
#   PSAvoidUsingPlainTextForPassword    — Mock function parameter names like $TargetCredentials
#       trigger this even when typed as [hashtable].
#   PSUseSingularNouns                  — Test helper stubs like New-FakeExamTargets are fine.
$TestFileRulesExclusions = @(
    'PSUseDeclaredVarsMoreThanAssignments'
    'PSReviewUnusedParameter'
    'PSAvoidUsingPlainTextForPassword'
    'PSUseSingularNouns'
    'PSAvoidOverwritingBuiltInCmdlets'
)
$Results = @($Results | Where-Object {
        -not ($TestFileRulesExclusions -contains $_.RuleName -and $_.ScriptPath -match '[/\\]Tests[/\\]')
    })

if (-not $Results -or $Results.Count -eq 0) {
    Write-Output 'ScriptAnalyzer: clean run (0 warnings/errors).'
    exit 0
}

$Sorted = $Results | Sort-Object Severity, RuleName, ScriptPath, Line, Column

Write-Output "ScriptAnalyzer: $($Sorted.Count) finding(s)."
foreach ($Finding in $Sorted) {
    Write-Output "$($Finding.Severity)|$($Finding.RuleName)|$($Finding.ScriptPath):$($Finding.Line):$($Finding.Column)|$($Finding.Message)"
}

exit 1
