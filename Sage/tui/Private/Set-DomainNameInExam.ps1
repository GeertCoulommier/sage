#Requires -Version 7.5
<#
.SYNOPSIS
    Replaces domain name placeholders in an exam definition.
.DESCRIPTION
    Recursively walks the exam definition and replaces all occurrences of
    '<domainname>' with the specified domain name string in all string values
    within the Variables hashtables of each category.
.PARAMETER Exam
    The exam definition hashtable (will be mutated in-place).
.PARAMETER DomainName
    The student's domain name to substitute for '<domainname>'.
.OUTPUTS
    [hashtable] — The same exam hashtable, with placeholders replaced.
.EXAMPLE
    $Exam = Set-DomainNameInExam -Exam $Exam -DomainName 'geert'
#>
function Set-DomainNameInExam {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]                                                          [hashtable] $Exam,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $DomainName
    )

    $ErrorActionPreference = 'Stop'

    $Placeholder = '<domainname>'

    foreach ($Category in $Exam.Categories) {
        if (-not $Category.Variables) { continue }
        $Category['Variables'] = Resolve-PlaceholderInValue -Value $Category.Variables -Placeholder $Placeholder -Replacement $DomainName
    }

    return $Exam
}

<#
.SYNOPSIS
    Recursively replaces a placeholder string in a value.
.DESCRIPTION
    Walks strings, arrays, and hashtables recursively, replacing all
    occurrences of the placeholder in string values.
.PARAMETER Value
    The value to process (string, array, hashtable, or other).
.PARAMETER Placeholder
    The placeholder string to find.
.PARAMETER Replacement
    The replacement string.
.OUTPUTS
    [object] — The value with placeholders replaced.
.EXAMPLE
    $Result = Resolve-PlaceholderInValue -Value $Ht -Placeholder '<domainname>' -Replacement 'geert'
#>
function Resolve-PlaceholderInValue {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]                                                           [object] $Value,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                  [string] $Placeholder,
        [Parameter(Mandatory)]                                                           [string] $Replacement
    )

    if ($Value -is [string]) {
        return $Value.Replace($Placeholder, $Replacement)
    }

    if ($Value -is [hashtable]) {
        $Result = @{}
        foreach ($Key in $Value.Keys) {
            $Result[$Key] = Resolve-PlaceholderInValue -Value $Value[$Key] -Placeholder $Placeholder -Replacement $Replacement
        }
        return $Result
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [hashtable]) {
        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $Value) {
            $Items.Add((Resolve-PlaceholderInValue -Value $Item -Placeholder $Placeholder -Replacement $Replacement))
        }
        return , $Items.ToArray()
    }

    return $Value
}
