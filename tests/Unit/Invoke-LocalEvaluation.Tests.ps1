#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Invoke-LocalEvaluation.
.DESCRIPTION
    Verifies the TUI evaluation orchestrator: exam filtering, domain replacement,
    credential construction, and delegation to Invoke-StudentEvaluation.
.TAGS Unit
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Copy-ExamWithCategories.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Set-DomainNameInExam.ps1')
    . (Join-Path $PSScriptRoot '..\..\Sage\tui\Private\Invoke-LocalEvaluation.ps1')

    # Note: Invoke-StudentEvaluation runs inside a Start-ThreadJob scriptblock and
    # imports the full sage module, so Pester Mock cannot intercept it.  Tests mock
    # Start-ThreadJob directly and return a pre-built completed job instead.
    function Invoke-StudentEvaluation {
        param($Row, $Exam, $IpField, $EmailField, $NameField,
              [hashtable] $TargetCredentials, [switch] $SaveCollectorData, $ExamOutputDir)
        return [PSCustomObject]@{
            Summary = [PSCustomObject]@{ TotalNormalizedScore = 10; MaxNormalizedScore = 20 }
            Error   = $null
        }
    }

    # Returns a real already-completed PowerShell job whose output is $Result.
    # Receive-Job on the returned job yields the deserialized $Result object.
    function New-FakeCompletedJob {
        [CmdletBinding()]
        param([Parameter(Mandatory)][AllowNull()][object]$Result)
        $j = Start-Job -ScriptBlock { $using:Result }
        $null = Wait-Job $j -Timeout 30
        $j
    }

    function New-FakeExam {
        @{
            Name       = 'Test'
            Version    = '1.0.0'
            Targets    = @{
                DC1 = @{
                    Port     = 22
                    UserName = 'administrator'
                    Platform = 'Windows'
                }
            }
            Categories = @(
                @{
                    Name       = 'DNS DC1'
                    Target     = 'DC1'
                    Collector  = 'Dns'
                    Evaluation = 'Dns'
                    Variables  = @{ ForwardZones = @(@{ ZoneName = '<domainname>.be' }) }
                }
            )
            Export     = @{ PrimaryFormat = 'Json'; SecondaryFormats = @() }
        }
    }
}

Describe 'Invoke-LocalEvaluation' -Tag 'Unit' {

    BeforeEach {
        $env:SAGE_CRED = 'TestCred'
        $TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "sage-test-$(New-Guid)"
        New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
        $Exam = New-FakeExam
        $ConnInfo = @{
            DC1 = [PSCustomObject]@{
                HostName = '192.168.1.3'
                Port     = 22
                Status   = 'Primary'
            }
        }

        # Suppress progress bars and intercept Start-ThreadJob so tests don't
        # attempt real SSH connections inside thread jobs.
        Mock Write-Progress { }
        Mock Start-ThreadJob {
            New-FakeCompletedJob -Result ([PSCustomObject]@{
                Summary = [PSCustomObject]@{ TotalNormalizedScore = 10; MaxNormalizedScore = 20 }
                Error   = $null
            })
        }
    }

    AfterEach {
        $env:SAGE_CRED = $null
        if (Test-Path $TestDir) {
            Remove-Item -Path $TestDir -Recurse -Force
        }
    }

    Context 'Output directory creation' {

        It 'Creates a timestamped subdirectory' {
            $Result = Invoke-LocalEvaluation -Exam $Exam -ConnectionInfo $ConnInfo -SelectedCategories @('DNS DC1') -OutputDir $TestDir

            $Result.OutputPath | Should -Not -BeNullOrEmpty
            Test-Path $Result.OutputPath | Should -BeTrue
            (Split-Path $Result.OutputPath -Leaf) | Should -Match '^\d{4}-\d{2}-\d{2}_\d{6}$'
        }
    }

    Context 'Domain name replacement' {

        It 'Replaces placeholders when DomainName is provided' {
            $script:CapturedExam = $null
            Mock Start-ThreadJob {
                # $ArgumentList[0] is the FilteredExam after domain name substitution
                $script:CapturedExam = $ArgumentList[0]
                New-FakeCompletedJob -Result ([PSCustomObject]@{
                    Summary = [PSCustomObject]@{ TotalNormalizedScore = 10; MaxNormalizedScore = 20 }
                    Error   = $null
                })
            }

            Invoke-LocalEvaluation -Exam $Exam -ConnectionInfo $ConnInfo -SelectedCategories @('DNS DC1') -OutputDir $TestDir -DomainName 'geert'

            $script:CapturedExam.Categories[0].Variables.ForwardZones[0].ZoneName | Should -Be 'geert.be'
        }
    }

    Context 'Delegation to evaluation' {

        It 'Delegates to Start-ThreadJob and returns result' {
            Mock Start-ThreadJob {
                New-FakeCompletedJob -Result ([PSCustomObject]@{
                    Summary = [PSCustomObject]@{ TotalNormalizedScore = 14.5; MaxNormalizedScore = 20 }
                    Error   = $null
                })
            }

            $Result = Invoke-LocalEvaluation -Exam $Exam -ConnectionInfo $ConnInfo -SelectedCategories @('DNS DC1') -OutputDir $TestDir

            Should -Invoke Start-ThreadJob -Times 1
            $Result.Summary.TotalNormalizedScore | Should -Be 14.5
            $Result.Error | Should -BeNullOrEmpty
        }

        It 'Passes errors through' {
            Mock Start-ThreadJob {
                New-FakeCompletedJob -Result ([PSCustomObject]@{
                    Summary = $null
                    Error   = 'Connection failed'
                })
            }

            $Result = Invoke-LocalEvaluation -Exam $Exam -ConnectionInfo $ConnInfo -SelectedCategories @('DNS DC1') -OutputDir $TestDir

            $Result.Error | Should -Be 'Connection failed'
        }
    }

    Context 'Category filtering' {

        It 'Only includes selected categories' {
            $Exam.Categories += @{
                Name       = 'DHCP DC1'
                Target     = 'DC1'
                Collector  = 'Dhcp'
                Evaluation = 'Dhcp'
                Variables  = @{}
            }

            $script:CapturedExam = $null
            Mock Start-ThreadJob {
                # $ArgumentList[0] is the FilteredExam after category selection
                $script:CapturedExam = $ArgumentList[0]
                New-FakeCompletedJob -Result ([PSCustomObject]@{
                    Summary = [PSCustomObject]@{ TotalNormalizedScore = 10; MaxNormalizedScore = 20 }
                    Error   = $null
                })
            }

            Invoke-LocalEvaluation -Exam $Exam -ConnectionInfo $ConnInfo -SelectedCategories @('DNS DC1') -OutputDir $TestDir

            $script:CapturedExam.Categories.Count | Should -Be 1
            $script:CapturedExam.Categories[0].Name | Should -Be 'DNS DC1'
        }
    }

    Context 'Parameter validation' {

        It 'Requires Exam' {
            { Invoke-LocalEvaluation -ConnectionInfo $ConnInfo -SelectedCategories @('DNS DC1') -OutputDir $TestDir } | Should -Throw
        }

        It 'Requires ConnectionInfo' {
            { Invoke-LocalEvaluation -Exam $Exam -SelectedCategories @('DNS DC1') -OutputDir $TestDir } | Should -Throw
        }

        It 'Requires SelectedCategories' {
            { Invoke-LocalEvaluation -Exam $Exam -ConnectionInfo $ConnInfo -OutputDir $TestDir } | Should -Throw
        }

        It 'Requires OutputDir' {
            { Invoke-LocalEvaluation -Exam $Exam -ConnectionInfo $ConnInfo -SelectedCategories @('DNS DC1') } | Should -Throw
        }
    }
}
