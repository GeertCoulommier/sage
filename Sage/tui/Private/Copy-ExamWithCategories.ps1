#Requires -Version 7.5
<#
.SYNOPSIS
    Creates a copy of an exam definition filtered to selected categories.
.DESCRIPTION
    Deep-copies the exam definition hashtable and removes all categories not
    present in the SelectedCategories list.  Also removes targets that have
    no remaining categories.
.PARAMETER Exam
    The original exam definition hashtable.
.PARAMETER SelectedCategories
    Array of category names to keep.
.OUTPUTS
    [hashtable] — Filtered copy of the exam definition.
.EXAMPLE
    $Filtered = Copy-ExamWithCategories -Exam $Exam -SelectedCategories @('DNS DC1','DHCP DC1')
#>
function Copy-ExamWithCategories {
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Copy-ExamWithCategories operates on a collection — the plural noun is intentional.')]
    param(
        [Parameter(Mandatory)]                                                          [hashtable] $Exam,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                 [string[]] $SelectedCategories
    )

    $ErrorActionPreference = 'Stop'

    # ── Shallow-clone top-level keys ───────────────────────────────────────────
    $Filtered = @{}
    foreach ($Key in $Exam.Keys) {
        $Filtered[$Key] = $Exam[$Key]
    }

    # ── Filter categories ──────────────────────────────────────────────────────
    $Filtered['Categories'] = @(
        $Exam.Categories | Where-Object { $SelectedCategories -contains $_.Name }
    )

    # ── Clone only targets referenced by remaining categories ──────────────────
    $UsedTargetNames = @(
        $Filtered['Categories'] | ForEach-Object { $_.Target } | Sort-Object -Unique
    )
    $ClonedTargets = @{}
    foreach ($Key in $UsedTargetNames) {
        if (-not $Exam.Targets.ContainsKey($Key)) { continue }
        $Original = $Exam.Targets[$Key]
        $ClonedTargets[$Key] = @{}
        foreach ($Prop in $Original.Keys) {
            $ClonedTargets[$Key][$Prop] = $Original[$Prop]
        }
    }
    $Filtered['Targets'] = $ClonedTargets

    return $Filtered
}
