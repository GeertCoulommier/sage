#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6.0' }
<#
.SYNOPSIS
    Unit tests for Import-ExamDefinition (Public).
.DESCRIPTION
    Tests: successful load, synthetic key injection (_ExamPath, _ExamDir),
    validation propagation, non-existent path error, malformed psd1 error.
.TAGS Unit
#>

BeforeAll {
    # Load dependencies that Import-ExamDefinition needs
    $PublicDir = Join-Path $PSScriptRoot '..\..\Sage\Public'
    $PrivateDir = Join-Path $PSScriptRoot '..\..\Sage\Private'
    . (Join-Path $PrivateDir 'Write-Log.ps1')
    . (Join-Path $PublicDir 'Test-ExamDefinition.ps1')
    . (Join-Path $PublicDir 'Import-ExamDefinition.ps1')

    $script:ExampleExamPath = Join-Path $PSScriptRoot '..\..\' 'Sage' 'data' 'exams' '_example' 'exam.psd1'
    $script:BadExamPath = Join-Path $PSScriptRoot '..\..\' 'Sage' 'data' 'exams' 'bad' 'exam.psd1'

    # Temp directory for on-the-fly test psd1 files
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sage-test-' + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item -Path $script:TempDir -Recurse -Force
    }
}

Describe 'Import-ExamDefinition' -Tag 'Unit' {

    Context 'Successful load of example exam' {
        BeforeAll {
            $script:Def = Import-ExamDefinition -Path $script:ExampleExamPath
        }

        It 'Returns a hashtable' {
            $script:Def | Should -BeOfType [hashtable]
        }

        It 'Injects _ExamPath synthetic key' {
            $script:Def.ContainsKey('_ExamPath') | Should -Be $true
        }

        It '_ExamPath is an absolute, resolved path' {
            [System.IO.Path]::IsPathRooted($script:Def['_ExamPath']) | Should -Be $true
        }

        It 'Injects _ExamDir synthetic key' {
            $script:Def.ContainsKey('_ExamDir') | Should -Be $true
        }

        It '_ExamDir is the parent folder of the exam file' {
            $Expected = Split-Path -Path $script:Def['_ExamPath'] -Parent
            $script:Def['_ExamDir'] | Should -Be $Expected
        }

        It 'Preserves exam Name' {
            $script:Def.Name | Should -Not -BeNullOrEmpty
        }

        It 'Preserves Targets hashtable' {
            $script:Def.Targets | Should -BeOfType [hashtable]
            $script:Def.Targets.Count | Should -BeGreaterThan 0
        }

        It 'Preserves Categories array' {
            @($script:Def.Categories).Count | Should -BeGreaterThan 0
        }
    }

    Context 'Invalid exam file — bad schema' {
        BeforeAll {
            # Write a minimal psd1 with a missing required key
            $script:MissingKeyPath = Join-Path $script:TempDir 'missing-key.psd1'
            Set-Content -Path $script:MissingKeyPath -Value "@{ Name = 'Bad Exam' }"
        }

        It 'Throws a terminating error for missing required keys' {
            { Import-ExamDefinition -Path $script:MissingKeyPath } | Should -Throw
        }
    }

    Context 'Non-existent path' {
        It 'Throws due to ValidateScript when path does not exist' {
            { Import-ExamDefinition -Path './nonexistent/exam.psd1' } | Should -Throw
        }
    }

    Context 'Malformed psd1 file' {
        BeforeAll {
            $script:SyntaxErrPath = Join-Path $script:TempDir 'syntax-error.psd1'
            Set-Content -Path $script:SyntaxErrPath -Value "@{ Name = 'Unclosed"
        }

        It 'Throws when psd1 has syntax errors' {
            { Import-ExamDefinition -Path $script:SyntaxErrPath } | Should -Throw
        }
    }

    Context 'Bad exam from exams/bad directory' {
        It 'Throws when loading the known-bad exam file' {
            { Import-ExamDefinition -Path $script:BadExamPath } | Should -Throw
        }
    }
}
