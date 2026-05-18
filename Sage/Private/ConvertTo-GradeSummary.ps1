#Requires -Version 7.5
<#
.SYNOPSIS
    Converts deserialized Pester results into Sage.TestResult objects with grades
    and review data attached.
.DESCRIPTION
    Processes the Tests collection from the Pester run result returned by
    Invoke-RemotePester.  For each test:
      • Reads the PassGrade from the test's Data hashtable (from -ForEach).
      • Derives Passed from the Pester Result ('Passed').
      • Parses the ErrorRecord message to extract ActualValue and ExpectedValue.
      • Looks up a ReviewContextName from the Pester Context name.
      • Invokes the matching ReviewContextMap scriptblock (if supplied) with
        $CollectedData to produce ReviewData for manual review in Edit-Grade.
      • Creates a Sage.TestResult via New-GradeResult.

    PassGrade is extracted from the Pester test's Data hashtable that was
            supplied through -ForEach in the evaluation file.  The convention is:
                It 'Description' -ForEach @(
                        @{
                                PassGrade = 2
                                ...
                        }
                ) { ... }

    Tests whose Result is 'Skipped' are omitted.
.PARAMETER PesterResult
    The deserialized Pester run object returned by Invoke-RemotePester.
.PARAMETER StudentEmail
    Student email address — stored on every TestResult for traceability.
.PARAMETER StudentName
    Student display name.
.PARAMETER StudentData
    Full CSV row as hashtable — preserved on each TestResult.
.PARAMETER TargetName
    Logical target name (from exam.psd1) for this run.
.PARAMETER Category
    Category name from exam.psd1.
.PARAMETER CollectedData
    Data hashtable from Invoke-RemoteCollector result.  Used by ReviewContextMap.
.PARAMETER ReviewContextMap
    Hashtable mapping Pester Context names to scriptblocks that extract review data.
    Optional — falls back gracefully when an entry is absent.
.OUTPUTS
    [PSCustomObject[]] typed as 'Sage.TestResult'
.EXAMPLE
    $convertParams = @{
        PesterResult = $pesterResult
        StudentEmail = 'jan@ehb.be'
        StudentName  = 'Jan Appel'
        StudentData  = @{ pointer = '42' }
        TargetName   = 'WinSrv1'
        Category     = 'DNS'
    }
    $testResults = ConvertTo-GradeSummary @convertParams
    # Returns an array of Sage.TestResult objects, one per non-skipped Pester test.
#>
function ConvertTo-GradeSummary {
    [CmdletBinding()]
    [OutputType('Sage.TestResult')]
    param(
        [Parameter(Mandatory)]                                                             [object] $PesterResult,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $StudentEmail,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $StudentName,
        [Parameter(Mandatory)]                                                          [hashtable] $StudentData,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $TargetName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $Category,
        [Parameter()]                                                                   [hashtable] $CollectedData = @{},
        [Parameter()]                                                                   [hashtable] $ReviewContextMap = @{}
    )

    $ErrorActionPreference = 'Stop'

    $Results = [System.Collections.Generic.List[object]]::new()

    foreach ($Test in $PesterResult.Tests) {
        # Skip tests that were never executed.
        # $Test is now a plain hashtable extracted on the remote side.
        $ResultStr = if ($Test -is [hashtable]) { $Test.Result } else { $Test.Result.ToString() }
        if ($ResultStr -in 'Skipped', 'NotRun') { continue }

        $Passed = $ResultStr -eq 'Passed'
        $PassGrade = 0.0

        # PassGrade lives in the Data hashtable attached via -ForEach.
        $DataHt = if ($Test -is [hashtable]) { $Test.Data } else { $null }
        if ($DataHt -is [hashtable] -and $DataHt.ContainsKey('PassGrade')) {
            $PassGrade = [double]$DataHt.PassGrade
        }

        # ── Extract actual / expected from Pester error message ────────────────
        $ActualValue = $null
        $ExpectedValue = $null
        $ErrorMessage = $null

        # ErrorMessage is pre-extracted as a string on the remote side.
        if (-not $Passed -and $Test.ErrorMessage) {
            $ErrorMessage = $Test.ErrorMessage
            if ($ErrorMessage -match "Expected '(.+)', but got '(.+)'.") {
                $ExpectedValue = $Matches[1]
                $ActualValue   = $Matches[2]
            }
            elseif ($ErrorMessage -match 'Expected\s+(.+?)\s+to\s+') {
                $ExpectedValue = $Matches[1]
            }
        }

        # ── Context name & ReviewContextMap lookup ─────────────────────────────
        # Context is pre-extracted on the remote side by Invoke-RemotePester.
        $ContextName = $Test.Context

        $ReviewData = $null
        $ReviewContextName = $ContextName

        if ($ContextName -and $ReviewContextMap.ContainsKey($ContextName) -and -not $Passed) {
            try {
                $ReviewData = & $ReviewContextMap[$ContextName] $CollectedData
            }
            catch {
                $LogParams = @{
                    Level    = 'Warning'
                    Category = 'Grading'
                    Message  = "ReviewContextMap scriptblock failed for context '$ContextName': $($_.Exception.Message)"
                }
                Write-Log @LogParams
            }
        }

        $GradeParams = @{
            StudentEmail      = $StudentEmail
            StudentName       = $StudentName
            StudentData       = $StudentData
            TargetName        = $TargetName
            Category          = $Category
            # Pester 5 CLIXML deserialization: ExpandedName contains the
            # -ForEach-expanded test description; Name is the raw template.
            # Fall back through both to ensure a non-empty string.
            TestName          = if (-not [string]::IsNullOrEmpty($Test.ExpandedName)) {
                $Test.ExpandedName
            }
            elseif (-not [string]::IsNullOrEmpty($Test.Name)) {
                $Test.Name
            }
            else {
                "$Category — Test $($Results.Count + 1)"
            }
            Context           = $ContextName
            Passed            = $Passed
            PassGrade         = $PassGrade
            ActualValue       = $ActualValue
            ExpectedValue     = $ExpectedValue
            ErrorMessage      = $ErrorMessage
            ReviewData        = $ReviewData
            ReviewContextName = $ReviewContextName
        }
        $Results.Add((New-GradeResult @GradeParams))
    }

    $Results.ToArray()
}
