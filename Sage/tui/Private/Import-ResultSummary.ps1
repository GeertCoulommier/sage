#Requires -Version 7.5
<#
.SYNOPSIS
    Imports a saved evaluation result summary from disk.
.DESCRIPTION
    Reads the results.json file from a timestamped output directory and returns
    the deserialized Sage.StudentGradeSummary object.
.PARAMETER OutputPath
    Path to the timestamped output directory containing results.json or a
    student subdirectory with grade-summary.json.
.OUTPUTS
    [PSCustomObject] — The deserialized grade summary, or $null if not found.
.EXAMPLE
    $Summary = Import-ResultSummary -OutputPath './output/2026-04-18_143022'
#>
function Import-ResultSummary {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $OutputPath
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $OutputPath)) {
        return $null
    }

    # ── Look for results.json in student subdirectory or at top level ─────────
    $JsonFiles = Get-ChildItem -Path $OutputPath -Filter 'results.json' -Recurse -File
    if ($JsonFiles.Count -gt 0) {
        $JsonPath = ($JsonFiles | Sort-Object -Property LastWriteTime -Descending)[0].FullName
        $Content  = Get-Content -Path $JsonPath -Raw -Encoding utf8
        return ($Content | ConvertFrom-Json)
    }

    # ── Legacy: look for grade-summary.json ────────────────────────────────────
    $JsonFiles = Get-ChildItem -Path $OutputPath -Filter 'grade-summary.json' -Recurse -File
    if ($JsonFiles.Count -gt 0) {
        $JsonPath = $JsonFiles[0].FullName
        $Content  = Get-Content -Path $JsonPath -Raw -Encoding utf8
        return ($Content | ConvertFrom-Json)
    }

    return $null
}
