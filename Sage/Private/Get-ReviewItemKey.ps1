#Requires -Version 7.5
<#
.SYNOPSIS
    Generates a stable compound identity key for a review item.
.DESCRIPTION
    Creates a canonical review item key by combining StudentEmail, TargetName,
    Category, Context, and TestName. This key uniquely identifies a test across
    all students, targets, and categories, making it suitable for keying override
    dictionaries and tracking review changes in non-interactive workflows.

    The key format is: "StudentEmail|TargetName|Category|Context|TestName"
.PARAMETER StudentEmail
    Email address of the student.
.PARAMETER TargetName
    Name of the system/target the test ran against (e.g., 'WinSrv1', 'LinuxWeb').
.PARAMETER Category
    Exam category name (e.g., 'DNS', 'AD', 'Docker').
.PARAMETER Context
    Pester Context/Describe block name (e.g., 'A Records', 'Domain').
.PARAMETER TestName
    Full Pester test description (e.g., 'A record dc1 resolves').
.OUTPUTS
    [string] A pipe-delimited compound key.
.EXAMPLE
    Get-ReviewItemKey -StudentEmail 'jan@ehb.be' -TargetName 'WinSrv1' `
                      -Category 'DNS' -Context 'A Records' -TestName 'A record exists'
    # Returns: "jan@ehb.be|WinSrv1|DNS|A Records|A record exists"
#>
function Get-ReviewItemKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]                                                           [string] $StudentEmail,
        [Parameter(Mandatory)]                                                           [string] $TargetName,
        [Parameter(Mandatory)]                                                           [string] $Category,
        [Parameter(Mandatory)]                                                           [string] $Context,
        [Parameter(Mandatory)]                                                           [string] $TestName
    )

    "$StudentEmail|$TargetName|$Category|$Context|$TestName"
}
