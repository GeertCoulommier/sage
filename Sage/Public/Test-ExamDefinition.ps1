#Requires -Version 7.5
<#
.SYNOPSIS
    Validates the schema and content of an exam definition file (exam.psd1).
.DESCRIPTION
    Performs deep structural and semantic validation of a loaded exam definition
    hashtable or a path to an exam.psd1 file.

    Validation rules:
      - Top-level required keys: Name, Targets, Categories
      - Targets: each entry must have Port (1-65535), UserName, Platform
        ('Windows' or 'Linux').  Credential resolution is optional — either
        CredentialSecret per target, DefaultCredentialSecret at exam level, or
        SSH key-based auth (no credential required).  Missing credentials
        produce a validation warning, not a hard error.
      - Categories: each entry must have Name, Target (referencing a defined
        Target key), Evaluation and Collector.  If a Variables key is present,
        each value must be an array of hashtables; any hashtable that contains
        a PassGrade key must have PassGrade > 0.
      - Roster (if present): must contain at least IPField, EmailField and
        NameField.
      - ExamStart / ExamEnd (if present): must be parseable as [datetime].
      - ExamEnd must be after ExamStart when both are present.

    The function returns $true on success.  On validation failure it either
    throws a terminating error (default) or writes non-terminating errors and
    returns $false when -PassThru is specified.
.PARAMETER ExamDefinition
    A hashtable previously loaded via Import-PowerShellDataFile or
    Import-ExamDefinition.  Mutually exclusive with -Path.
.PARAMETER Path
    Path to an exam.psd1 file.  The file is loaded internally with
    Import-PowerShellDataFile.  Mutually exclusive with -ExamDefinition.
.PARAMETER PassThru
    When specified, the function returns $false on failure instead of throwing.
    Each validation problem is emitted as a non-terminating error.
.OUTPUTS
    [bool]
.EXAMPLE
    Test-ExamDefinition -Path ./data/exams/_example/exam.psd1
    # Returns $true or throws on invalid schema.
.EXAMPLE
    $def = Import-PowerShellDataFile ./data/exams/myexam/exam.psd1
    Test-ExamDefinition -ExamDefinition $def -PassThru
#>
function Test-ExamDefinition {
    [CmdletBinding(DefaultParameterSetName = 'ByHashtable')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByHashtable', ValueFromPipeline)]      [hashtable] $ExamDefinition,
        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
                                                                                            [string] $Path,
        [Parameter()]                                                                       [switch] $PassThru
    )

    process {

    $ErrorActionPreference = 'Stop'

    # ── Load from disk when path supplied ─────────────────────────────────────────
    $FileContent = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        try {
            $FileContent = @(Get-Content -Path $Path -Raw)
            $ExamDefinition = Import-PowerShellDataFile -Path $Path
        }
        catch {
            $Msg = "Cannot load exam file '$Path': $($_.Exception.Message)"
            if ($PassThru) { Write-Error $Msg -ErrorAction Continue; return $false }
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.InvalidDataException]::new($Msg),
                    'ExamLoad.Failed',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $Path
                )
            )
        }
    }

    # ── Accumulate all errors with line numbers ────────────────────────────────────
    [System.Collections.Generic.List[object]] $Issues = @()

    <#
    .SYNOPSIS
        Appends a validation issue to the Issues list.
    .DESCRIPTION
        Helper nested function for Test-ExamDefinition.  Adds a structured
        issue hashtable with Message and LineNumber to the $Issues list captured
        from the enclosing scope.
    .PARAMETER Message
        Human-readable description of the validation error.
    .PARAMETER LineNumber
        Line number in the exam.psd1 file where the issue was found.  Zero
        when no line information is available.
    .OUTPUTS
        [void]
    .EXAMPLE
        Add-Issue "Missing required key 'Name'." -LineNumber 3
    #>
    function Add-Issue {
        [CmdletBinding()]
        [OutputType([void])]
        param(
            [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                               [string] $Message,
            [Parameter()]                                                                     [int] $LineNumber = 0
        )
        $ErrorActionPreference = 'Stop'
        $Issue = @{
            Message    = $Message
            LineNumber = $LineNumber
        }
        $Issues.Add($Issue)
    }

    # ── Helper: find line number for a key in the psd1 file ───────────────────────
    <#
    .SYNOPSIS
        Returns the 1-based line number of the first line matching a pattern.
    .DESCRIPTION
        Helper nested function for Test-ExamDefinition.  Searches the raw
        $FileContent string (captured from the enclosing scope) for SearchPattern
        and returns the line number.  Returns 0 when $FileContent is not available
        or no matching line is found.
    .PARAMETER SearchPattern
        Regular expression used to locate the key within the psd1 file.
    .OUTPUTS
        [int]
    .EXAMPLE
        $Ln = Find-LineNumber 'Name\s*='
    #>
    function Find-LineNumber {
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                               [string] $SearchPattern
        )
        $ErrorActionPreference = 'Stop'
        if (-not $FileContent) { return 0 }
        $Lines = $FileContent[0] -split "`n"
        for ($I = 0; $I -lt $Lines.Count; $I++) {
            if ($Lines[$I] -match $SearchPattern) {
                return $I + 1
            }
        }
        return 0
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 1. Top-level required keys
    # ─────────────────────────────────────────────────────────────────────────────
    foreach ($key in 'Name', 'Targets', 'Categories') {
        if (-not $ExamDefinition.ContainsKey($key)) {
            Add-Issue "Missing required top-level key: '$key'."
        }
    }

    # Abort early if critical structure missing (further checks would NullRef)
    if ($Issues.Count -gt 0) {
        return Resolve-Issue -Issues $Issues -Definition $ExamDefinition -PassThru:$PassThru -CmdletBinding $PSCmdlet
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 2. Name must be a non-empty string
    # ─────────────────────────────────────────────────────────────────────────────
    if ($ExamDefinition.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($ExamDefinition.Name)) {
        $ln = Find-LineNumber 'Name\s*='
        Add-Issue "Key 'Name' must be a non-empty string." -LineNumber $ln
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 3. Targets
    # ─────────────────────────────────────────────────────────────────────────────
    $Targets = $ExamDefinition.Targets
    if ($Targets -isnot [hashtable] -or $Targets.Count -eq 0) {
        $ln = Find-LineNumber 'Targets\s*='
        Add-Issue "'Targets' must be a non-empty hashtable." -LineNumber $ln
    }
    else {
        $DefaultCred = $ExamDefinition.DefaultCredentialSecret
        foreach ($TargetName in $Targets.Keys) {
            $T = $Targets[$TargetName]
            $TargetLineNum = Find-LineNumber "$TargetName\s*="
            if ($T -isnot [hashtable]) {
                Add-Issue "Target '$TargetName': must be a hashtable." -LineNumber $TargetLineNum
                continue
            }
            # Port
            if (-not $T.ContainsKey('Port')) {
                Add-Issue "Target '$TargetName': missing 'Port'." -LineNumber $TargetLineNum
            }
            elseif ($T.Port -isnot [int] -or $T.Port -lt 1 -or $T.Port -gt 65535) {
                Add-Issue "Target '$TargetName': 'Port' must be an integer between 1 and 65535 (got '$($T.Port)')." -LineNumber $TargetLineNum
            }
            # UserName
            if (-not $T.ContainsKey('UserName') -or [string]::IsNullOrWhiteSpace($T.UserName)) {
                Add-Issue "Target '$TargetName': missing or empty 'UserName'." -LineNumber $TargetLineNum
            }
            # Platform
            if (-not $T.ContainsKey('Platform')) {
                Add-Issue "Target '$TargetName': missing 'Platform'." -LineNumber $TargetLineNum
            }
            elseif ($T.Platform -notin 'Windows', 'Linux') {
                Add-Issue "Target '$TargetName': 'Platform' must be 'Windows' or 'Linux' (got '$($T.Platform)')." -LineNumber $TargetLineNum
            }
            # Credential resolution (optional — key-based auth needs no credential)
            $HasCred = $T.ContainsKey('CredentialSecret') -and -not [string]::IsNullOrWhiteSpace($T.CredentialSecret)
            $HasDefault = -not [string]::IsNullOrWhiteSpace($DefaultCred)
            if (-not $HasCred -and -not $HasDefault) {
                Write-Verbose "Test-ExamDefinition: Target '$TargetName' has no CredentialSecret and no DefaultCredentialSecret. SSH key auth (-KeyFilePath) must be used."
            }
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 4. Categories
    # ─────────────────────────────────────────────────────────────────────────────
    $Categories = $ExamDefinition.Categories
    if ($Categories -isnot [array] -or $Categories.Count -eq 0) {
        $ln = Find-LineNumber 'Categories\s*='
        Add-Issue "'Categories' must be a non-empty array." -LineNumber $ln
    }
    else {
        $DefinedTargets = if ($Targets -is [hashtable]) { $Targets.Keys } else { @() }
        for ($I = 0; $I -lt $Categories.Count; $I++) {
            $Cat = $Categories[$I]
            $Label = if ($Cat.Name) { "'$($Cat.Name)'" } else { "index $I" }
            $CatLineNum = if ($Cat.Name) { Find-LineNumber "Name\s*=\s*['\`"]?$([regex]::Escape($Cat.Name))" } else { 0 }
            if ($Cat -isnot [hashtable]) {
                Add-Issue "Category ${Label}: must be a hashtable." -LineNumber $CatLineNum
                continue
            }
            # Required string keys
            foreach ($Key in 'Name', 'Target', 'Evaluation', 'Collector') {
                if (-not $Cat.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Cat[$Key])) {
                    Add-Issue "Category ${Label}: missing or empty '$Key'." -LineNumber $CatLineNum
                }
            }
            # Target must reference a defined target
            if ($Cat.ContainsKey('Target') -and $Cat.Target -notin $DefinedTargets) {
                Add-Issue "Category ${Label}: 'Target' value '$($Cat.Target)' does not match any key in 'Targets'." -LineNumber $CatLineNum
            }
            # Variables (optional) — each value must be an array of hashtables with PassGrade > 0
            if ($Cat.ContainsKey('Variables') -and $Cat.Variables -is [hashtable]) {
                foreach ($VarKey in $Cat.Variables.Keys) {
                    $VarVal = $Cat.Variables[$VarKey]
                    if ($VarVal -isnot [array]) { continue }   # non-array Variables keys are fine
                    foreach ($Item in $VarVal) {
                        if ($Item -isnot [hashtable]) {
                            Add-Issue "Category ${Label}, Variables.${VarKey}: each item must be a hashtable." -LineNumber $CatLineNum
                        }
                        elseif ($Item.ContainsKey('PassGrade') -and $Item.PassGrade -le 0) {
                            Add-Issue "Category ${Label}, Variables.${VarKey}: PassGrade must be > 0 (got '$($Item.PassGrade)')." -LineNumber $CatLineNum
                        }
                    }
                }
            }
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 5. Roster (optional section)
    # ─────────────────────────────────────────────────────────────────────────────
    if ($ExamDefinition.ContainsKey('Roster')) {
        $Roster = $ExamDefinition.Roster
        $RosterLineNum = Find-LineNumber 'Roster\s*='
        if ($Roster -isnot [hashtable]) {
            Add-Issue "'Roster' must be a hashtable." -LineNumber $RosterLineNum
        }
        else {
            foreach ($Key in 'IPField', 'EmailField', 'NameField') {
                if (-not $Roster.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Roster[$Key])) {
                    Add-Issue "Roster: missing or empty '$Key'." -LineNumber $RosterLineNum
                }
            }
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 6. ExamStart / ExamEnd (optional, must parse as [datetime])
    # ─────────────────────────────────────────────────────────────────────────────
    $ParsedStart = $null
    $ParsedEnd = $null

    if ($ExamDefinition.ContainsKey('ExamStart')) {
        $StartLineNum = Find-LineNumber 'ExamStart\s*='
        try {
            $ParsedStart = [datetime]::Parse($ExamDefinition.ExamStart)
        }
        catch {
            Add-Issue "'ExamStart' value '$($ExamDefinition.ExamStart)' is not a valid datetime string." -LineNumber $StartLineNum
        }
    }
    if ($ExamDefinition.ContainsKey('ExamEnd')) {
        $EndLineNum = Find-LineNumber 'ExamEnd\s*='
        try {
            $ParsedEnd = [datetime]::Parse($ExamDefinition.ExamEnd)
        }
        catch {
            Add-Issue "'ExamEnd' value '$($ExamDefinition.ExamEnd)' is not a valid datetime string." -LineNumber $EndLineNum
        }
    }
    if ($null -ne $ParsedStart -and $null -ne $ParsedEnd -and $ParsedEnd -le $ParsedStart) {
        $EndLineNum = Find-LineNumber 'ExamEnd\s*='
        Add-Issue "'ExamEnd' must be after 'ExamStart'." -LineNumber $EndLineNum
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 7. Resolve accumulated issues
    # ─────────────────────────────────────────────────────────────────────────────
    return Resolve-Issue -Issues $Issues -Definition $ExamDefinition -PassThru:$PassThru -CmdletBinding $PSCmdlet

    } # end process
}

# ─────────────────────────────────────────────────────────────────────────────────
# Helper: emit errors and return result based on -PassThru flag
# ─────────────────────────────────────────────────────────────────────────────────
<#
.SYNOPSIS
    Resolves accumulated validation issues for Test-ExamDefinition.
.DESCRIPTION
    Called internally at the end of Test-ExamDefinition validation.  When issues
    exist, either writes non-terminating errors via $CmdletBinding.WriteError() and
    returns $false (-PassThru), or throws a terminating error with a summary.
    Returns $true immediately when no issues are found.
.PARAMETER Issues
    List of validation issue hashtables, each with Message and LineNumber keys.
.PARAMETER Definition
    The exam definition hashtable being validated — passed as the error target object.
.PARAMETER PassThru
    When set, non-terminating errors are written and $false is returned instead
    of throwing a terminating error.
.PARAMETER CmdletBinding
    The $PSCmdlet instance from the caller, used to emit errors that respect the
    caller's -ErrorAction preference.
.OUTPUTS
    [bool]
.EXAMPLE
    Resolve-Issue -Issues $Issues -Definition $ExamDefinition -PassThru:$PassThru -CmdletBinding $PSCmdlet
#>
function Resolve-Issue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]                                   [System.Collections.Generic.List[object]] $Issues,
        [Parameter(Mandatory)]                                                           [hashtable] $Definition,
        [Parameter()]                                                                        [switch] $PassThru,
        [Parameter()]                                    [System.Management.Automation.PSCmdlet] $CmdletBinding
    )
    $ErrorActionPreference = 'Stop'

    if ($Issues.Count -eq 0) { return $true }

    # Sort by line number (issues with LineNumber=0 go last)
    $SortedIssues = $Issues | Sort-Object { if ($_.LineNumber -eq 0) { [int]::MaxValue } else { $_.LineNumber } }

    # Format messages with line numbers
    $FormattedIssues = $SortedIssues | ForEach-Object {
        if ($_.LineNumber -gt 0) {
            "Line $($_.LineNumber): $($_.Message)"
        }
        else {
            $_.Message
        }
    }

    $IssueListing = $FormattedIssues | ForEach-Object { "  - $_" } | Join-String -Separator "`n"
    $Summary = "Exam definition validation failed with $($Issues.Count) issue(s):`n$IssueListing"

    if ($PassThru) {
        # MUST use $CmdletBinding.WriteError() — NOT the bare Write-Error function.
        # Write-Error ignores the caller's -ErrorAction SilentlyContinue.
        # $PSCmdlet.WriteError() respects it and prevents crashes in the VS Code
        # extension host when a test calls with -ErrorAction SilentlyContinue.
        foreach ($Issue in $FormattedIssues) {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($Issue),
                'ExamDefinition.ValidationError',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $null
            )
            $CmdletBinding.WriteError($ErrorRecord)
        }
        return $false
    }

    $CmdletBinding.ThrowTerminatingError(
        [System.Management.Automation.ErrorRecord]::new(
            [System.ArgumentException]::new($Summary),
            'ExamDefinition.Invalid',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $Definition
        )
    )
}
