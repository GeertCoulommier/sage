#Requires -Version 7.5
<#
.SYNOPSIS
    Loads an exam definition file (exam.psd1), validates it, and returns the
    validated hashtable ready for use by the pipeline.
.DESCRIPTION
    Reads the specified exam.psd1 file with Import-PowerShellDataFile, passes it
    through Test-ExamDefinition (terminating on any schema error), and returns the
    resulting hashtable.

    Relative paths inside the exam hashtable are NOT resolved here — callers are
    responsible for resolving any paths relative to the exam file location.

    The exam directory path is injected into the returned hashtable as the synthetic
    key '_ExamPath' (absolute path to the exam.psd1 file) and '_ExamDir' (the
    containing directory) for downstream use.
.PARAMETER Path
    Path to an exam.psd1 file.
.OUTPUTS
    [hashtable] — validated exam definition with _ExamPath and _ExamDir injected.
.EXAMPLE
    $exam = Import-ExamDefinition -Path ./data/exams/OSII-25-08/exam.psd1
#>
function Import-ExamDefinition {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })]            [string] $Path
    )

    $ErrorActionPreference = 'Stop'

    $ResolvedPath = (Resolve-Path -Path $Path).Path

    $LogParams = @{
        Level    = 'Info'
        Category = 'Pipeline'
        Message  = "Loading exam definition from: $ResolvedPath"
    }
    Write-Log @LogParams

    # Load the file
    $Definition = $null
    try {
        $Definition = Import-PowerShellDataFile -Path $ResolvedPath
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.InvalidDataException]::new(
                    "Cannot load exam file '$ResolvedPath': $($_.Exception.Message)"),
                'ImportExamDefinition.LoadFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $Path
            )
        )
    }

    # Deep validation — throws on failure; suppress boolean return to pipeline
    $null = Test-ExamDefinition -ExamDefinition $Definition

    # Inject synthetic path keys for downstream use
    $Definition['_ExamPath'] = $ResolvedPath
    $Definition['_ExamDir'] = Split-Path -Path $ResolvedPath -Parent

    $LogParams = @{ 
        Level    = 'Info'
        Category = 'Pipeline'
        Message  = "Exam '$($Definition.Name)' loaded successfully. Targets: $($Definition.Targets.Keys -join ', '). Categories: $($Definition.Categories.Count)." 
    }
    Write-Log @LogParams

    $Definition
}
