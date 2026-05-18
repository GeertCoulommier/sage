#Requires -Version 7.5
<#
.SYNOPSIS
    Orchestrates a SAGE evaluation run from the TUI.
.DESCRIPTION
    Constructs the required parameters and calls Invoke-StudentEvaluation to
    run the full SAGE pipeline against the selected targets and categories.

    When multiple targets are selected, evaluations run in parallel — one
    thread per target — so all VMs are collected and graded simultaneously.
    Results are merged into a single summary after all threads finish.

    The function:
    1. Builds a Row PSCustomObject with IP and identity fields.
    2. Filters the exam categories by user selection (per-target sub-exams
       when running in parallel).
    3. Builds per-target credential objects.
    4. Calls Invoke-StudentEvaluation (in parallel if multiple targets).
    5. Saves results and collector data to the output directory.

    Returns the evaluation result (Summary + Error) as returned by
    Invoke-StudentEvaluation.
.PARAMETER Exam
    Validated exam definition hashtable from Import-ExamDefinition.
.PARAMETER ConnectionInfo
    Hashtable from Get-ConnectionFallback mapping target names to connection
    details (HostName, Port).
.PARAMETER SelectedCategories
    Array of category names to evaluate.  Only these are included.
.PARAMETER OutputDir
    Root output directory.  A timestamped sub-folder is created inside.
.PARAMETER DomainName
    The student's domain name, used to replace '<domainname>' placeholders.
.OUTPUTS
    [PSCustomObject] — { Summary, Error, OutputPath }.
.EXAMPLE
    $Result = Invoke-LocalEvaluation -Exam $Exam -ConnectionInfo $Conn -SelectedCategories @('DNS DC1') -OutputDir './output'
#>
function Invoke-LocalEvaluation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '',
        Justification = 'ThreadJob scriptblocks receive outer variables via -ArgumentList, not $using: scope.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
        Justification = 'JobCreds/JobCred hold PSCredential objects passed as thread-job arguments, not plain text.')]
    param(
        [Parameter(Mandatory)]                                                          [hashtable] $Exam,
        [Parameter(Mandatory)]                                                          [hashtable] $ConnectionInfo,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                 [string[]] $SelectedCategories,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]                                   [string] $OutputDir,
        [Parameter()]                                                                      [string] $DomainName
    )

    $ErrorActionPreference = 'Stop'

    # ── Create timestamped output directory ────────────────────────────────────
    $Timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $RunDir    = Join-Path $OutputDir $Timestamp
    $null      = New-Item -Path $RunDir -ItemType Directory -Force

    # ── Build filtered exam ────────────────────────────────────────────────────
    $FilteredExam = Copy-ExamWithCategories -Exam $Exam -SelectedCategories $SelectedCategories

    # ── Replace domain name placeholders ───────────────────────────────────────
    if ($DomainName) {
        $FilteredExam = Set-DomainNameInExam -Exam $FilteredExam -DomainName $DomainName
    }

    # ── Build target credentials ───────────────────────────────────────────────
    $TargetCredentials = @{}
    $DummySecure       = [System.Security.SecureString]::new()
    foreach ($TargetName in $ConnectionInfo.Keys) {
        $ConnInfo = $ConnectionInfo[$TargetName]
        if (-not $ConnInfo.HostName) { continue }

        $ExamTarget = $FilteredExam.Targets[$TargetName]
        if (-not $ExamTarget) { continue }

        $TargetCredentials[$TargetName] = [PSCredential]::new($ExamTarget.UserName, $DummySecure)

        # Patch target with resolved connection info
        $ExamTarget.HostName = $ConnInfo.HostName
        $ExamTarget.Port     = $ConnInfo.Port
    }

    # ── Build Row object ───────────────────────────────────────────────────────
    $Row = [PSCustomObject]@{
        ip      = 'self-check'
        email   = 'self-check@sage.local'
        student = 'Self-Check'
    }

    # ── Auto-detect SAGE key file ──────────────────────────────────────────────
    $SageKeyPath     = Join-Path $PSScriptRoot '..' 'keys' 'id_sage'
    $UseKeyFile      = (Test-Path $SageKeyPath)
    $ResolvedKeyPath = if ($UseKeyFile) { (Resolve-Path $SageKeyPath).Path } else { $null }

    # ── Determine active targets ───────────────────────────────────────────────
    $ActiveTargets = @($FilteredExam.Targets.Keys | Where-Object {
        $ConnectionInfo.ContainsKey($_) -and $ConnectionInfo[$_].HostName
    })

    # ── Choose sequential vs. parallel execution ───────────────────────────────

    # Compute expected duration per target based on category count
    # Formula: 8 s base for copy + 10 s per category (collect + eval combined)
    $TargetCatCounts = @{}
    foreach ($Cat in $FilteredExam.Categories) {
        if (-not $TargetCatCounts.ContainsKey($Cat.Target)) { $TargetCatCounts[$Cat.Target] = 0 }
        $TargetCatCounts[$Cat.Target]++
    }

    # Max target name length for aligned progress bar labels
    $MaxLabelLen = ($ActiveTargets | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum

    if ($ActiveTargets.Count -le 1) {
        # ── Sequential (single target) — one progress bar ─────────────────────
        $SageModulePsdPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' 'Sage.psd1'))
        $EvalJob = Start-ThreadJob -ScriptBlock {
            param($TExam, $JobCreds, $TDir, $EvalRow, $SageModule, $KeyPath)
            Import-Module $SageModule -Force
            Set-SageLogPath -Path (Join-Path $TDir 'sage.log')
            $Params = @{
                Row               = $EvalRow
                Exam              = $TExam
                IpField           = 'ip'
                EmailField        = 'email'
                NameField         = 'student'
                TargetCredentials = $JobCreds
                SaveCollectorData = $true
                ExamOutputDir     = $TDir
            }
            if ($KeyPath) { $Params['KeyFilePath'] = $KeyPath }
            Invoke-StudentEvaluation @Params
        } -ArgumentList $FilteredExam, $TargetCredentials, $RunDir, $Row, $SageModulePsdPath, $ResolvedKeyPath

        $TargetName       = if ($ActiveTargets.Count -eq 1) { $ActiveTargets[0] } else { 'Evaluation' }
        $CatCount         = if ($TargetCatCounts.ContainsKey($TargetName)) { $TargetCatCounts[$TargetName] } else { 1 }
        $ExpectedSecs     = 8 + ($CatCount * 10)
        $CopyThreshold    = 8
        $CollectThreshold = $CopyThreshold + ($CatCount * 6)
        $TargetLabel      = $TargetName.PadRight($MaxLabelLen)
        $StartTime        = [DateTime]::Now

        while ($EvalJob.State -notin 'Completed', 'Failed', 'Stopped') {
            $Elapsed = ([DateTime]::Now - $StartTime).TotalSeconds
            $Phase   = switch ($true) {
                ($Elapsed -lt $CopyThreshold)    { 'Copying tests...'; break }
                ($Elapsed -lt $CollectThreshold) { 'Collecting data...'; break }
                ($Elapsed -lt $ExpectedSecs)     { 'Evaluating...'; break }
                default                          { 'Processing results...' }
            }
            $Pct = [Math]::Min(95, [int]($Elapsed / $ExpectedSecs * 100))
            Write-Progress -Id 1 -Activity $TargetLabel -Status $Phase -PercentComplete $Pct
            [System.Threading.Thread]::Sleep(400)
        }
        Write-Progress -Id 1 -Activity $TargetLabel -Status 'Complete' -PercentComplete 100
        [System.Threading.Thread]::Sleep(300)
        Write-Progress -Id 1 -Activity $TargetLabel -Status 'Complete' -PercentComplete 100 -Completed

        Write-Host '  Processing results...' -ForegroundColor DarkGray
        $Result = $EvalJob | Receive-Job -Wait -ErrorAction SilentlyContinue
        Remove-Job -Job $EvalJob -Force -ErrorAction SilentlyContinue
        if (-not $Result) {
            $Result = [PSCustomObject]@{ Summary = $null; Error = 'Evaluation returned no result.' }
        }
    }
    else {
        # ── Parallel (one thread job per target, progress bars in main thread) ──
        $SageModulePsdPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' 'Sage.psd1'))

        # Build per-target filtered exams and output directories
        $PerTargetExams    = @{}
        $PerTargetCreds    = @{}
        $PerTargetRunDirs  = @{}
        $TargetCategoryMap = @{}

        foreach ($Cat in $FilteredExam.Categories) {
            if (-not $TargetCategoryMap.ContainsKey($Cat.Target)) {
                $TargetCategoryMap[$Cat.Target] = [System.Collections.Generic.List[string]]::new()
            }
            $TargetCategoryMap[$Cat.Target].Add($Cat.Name)
        }

        foreach ($TargetName in $ActiveTargets) {
            $Cats = @($TargetCategoryMap[$TargetName])
            $PerTargetExams[$TargetName]   = Copy-ExamWithCategories -Exam $FilteredExam -SelectedCategories $Cats
            $PerTargetCreds[$TargetName]   = if ($TargetCredentials.ContainsKey($TargetName)) { @{ $TargetName = $TargetCredentials[$TargetName] } } else { @{} }
            $TDir = Join-Path $RunDir $TargetName
            $null = New-Item -Path $TDir -ItemType Directory -Force
            $PerTargetRunDirs[$TargetName] = $TDir
        }

        # ── Start one thread job per target ────────────────────────────────────
        $Jobs          = @{}
        $JobStartTimes = @{}
        $JobIds        = @{}
        $IdCounter     = 1

        foreach ($TargetName in $ActiveTargets) {
            $JobIds[$TargetName]        = $IdCounter++
            $JobStartTimes[$TargetName] = [DateTime]::Now

            $TExam  = $PerTargetExams[$TargetName]
            $JobCred = $PerTargetCreds[$TargetName]
            $TDir   = $PerTargetRunDirs[$TargetName]

            $Jobs[$TargetName] = Start-ThreadJob -ScriptBlock {
                param($TName, $TExam, $JobCred, $TDir, $SageModule, $EvalRow, $KeyPath)
                Import-Module $SageModule -Force
                Set-SageLogPath -Path (Join-Path $TDir 'sage.log')
                $EvalParms = @{
                    Row               = $EvalRow
                    Exam              = $TExam
                    IpField           = 'ip'
                    EmailField        = 'email'
                    NameField         = 'student'
                    TargetCredentials = $JobCred
                    SaveCollectorData = $true
                    ExamOutputDir     = $TDir
                }
                if ($KeyPath) { $EvalParms['KeyFilePath'] = $KeyPath }
                $R = Invoke-StudentEvaluation @EvalParms
                [PSCustomObject]@{ TargetName = $TName; Result = $R }
            } -ArgumentList $TargetName, $TExam, $JobCred, $TDir, $SageModulePsdPath, $Row, $ResolvedKeyPath
        }

        # ── Poll jobs and render Write-Progress bars ───────────────────────────
        $ActiveJobSet    = [System.Collections.Generic.HashSet[string]]::new([string[]]$ActiveTargets)
        $CompletedJobSet = [System.Collections.Generic.HashSet[string]]::new()
        while ($ActiveJobSet.Count -gt 0) {
            foreach ($T in @($ActiveJobSet)) {
                $Job      = $Jobs[$T]
                $Elapsed  = ([DateTime]::Now - $JobStartTimes[$T]).TotalSeconds
                $CatCount = if ($TargetCatCounts.ContainsKey($T)) { $TargetCatCounts[$T] } else { 1 }
                $ExpectedS       = 8 + ($CatCount * 10)
                $CopyThresholdT  = 8
                $CollectThresholdT = $CopyThresholdT + ($CatCount * 6)
                $Phase    = switch ($true) {
                    ($Elapsed -lt $CopyThresholdT)    { 'Copying tests...'; break }
                    ($Elapsed -lt $CollectThresholdT) { 'Collecting data...'; break }
                    ($Elapsed -lt $ExpectedS)         { 'Evaluating...'; break }
                    default                           { 'Processing results...' }
                }
                $PaddedLabel = $T.PadRight($MaxLabelLen)
                if ($Job.State -in 'Completed', 'Failed', 'Stopped') {
                    Write-Progress -Id $JobIds[$T] -Activity $PaddedLabel -Status 'Complete' -PercentComplete 100
                    $ActiveJobSet.Remove($T) | Out-Null
                    $CompletedJobSet.Add($T) | Out-Null
                }
                else {
                    $Pct = [Math]::Min(95, [int]($Elapsed / $ExpectedS * 100))
                    Write-Progress -Id $JobIds[$T] -Activity $PaddedLabel -Status $Phase -PercentComplete $Pct
                }
            }
            if ($ActiveJobSet.Count -gt 0) {
                [System.Threading.Thread]::Sleep(400)
            }
        }
        # All targets done — remove all progress bars
        [System.Threading.Thread]::Sleep(400)
        foreach ($T in $CompletedJobSet) {
            $PaddedLabel = $T.PadRight($MaxLabelLen)
            Write-Progress -Id $JobIds[$T] -Activity $PaddedLabel -Status 'Complete' -PercentComplete 100 -Completed
        }

        Write-Host '  Processing results...' -ForegroundColor DarkGray

        # ── Collect results and clean up ───────────────────────────────────────
        $PerTargetResults = foreach ($T in $ActiveTargets) {
            $Output = $Jobs[$T] | Receive-Job -Wait -ErrorAction SilentlyContinue
            Remove-Job -Job $Jobs[$T] -Force -ErrorAction SilentlyContinue
            if ($Output) { $Output }
        }

        # ── Merge per-target results into a single summary ────────────────────
        $MergedCategoryScores = [System.Collections.Generic.List[object]]::new()
        $MergedTestResults    = [System.Collections.Generic.List[object]]::new()
        $MergedErrors         = [System.Collections.Generic.List[string]]::new()
        $FirstSummary         = $null

        foreach ($PR in $PerTargetResults) {
            if (-not $PR) { continue }
            $R = $PR.Result
            if ($R.Error) { $MergedErrors.Add("$($PR.TargetName): $($R.Error)") }
            if ($R.Summary) {
                if (-not $FirstSummary) { $FirstSummary = $R.Summary }
                if ($R.Summary.CategoryScores) {
                    foreach ($Cat in $R.Summary.CategoryScores) { $MergedCategoryScores.Add($Cat) }
                }
                if ($R.Summary.TestResults) {
                    foreach ($Test in $R.Summary.TestResults) { $MergedTestResults.Add($Test) }
                }
            }
        }

        $TotalRaw  = ($MergedCategoryScores | ForEach-Object { $_.RawScore } | Measure-Object -Sum).Sum
        $TotalMax  = ($MergedCategoryScores | ForEach-Object { $_.MaxScore } | Measure-Object -Sum).Sum
        $TotalNorm = if ($TotalMax -gt 0) { [math]::Round(($TotalRaw / $TotalMax) * 20, 2) } else { 0.0 }

        $MergedSummary = [PSCustomObject]@{
            PSTypeName     = 'Sage.StudentGradeSummary'
            StudentName    = 'Self-Check'
            GradedAt       = (Get-Date -Format 'MM/dd/yyyy HH:mm:ss')
            TotalScore     = [PSCustomObject]@{
                Raw        = if ($TotalRaw) { [math]::Round($TotalRaw, 4) } else { 0 }
                Normalized = $TotalNorm
                Max        = if ($TotalMax) { [math]::Round($TotalMax, 4) } else { 0 }
            }
            CategoryScores = $MergedCategoryScores.ToArray()
            TestResults    = $MergedTestResults.ToArray()
        }

        # Persist the merged summary so Import-ResultSummary can load it
        $MergedStudentDir = Join-Path $RunDir 'Self-Check'
        $null             = New-Item -Path $MergedStudentDir -ItemType Directory -Force -ErrorAction SilentlyContinue
        $MergedSummary | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $MergedStudentDir 'results.json') -Encoding utf8

        $MergedError = if ($MergedErrors.Count -gt 0) { $MergedErrors -join '; ' } else { $null }
        $Result = [PSCustomObject]@{ Summary = $MergedSummary; Error = $MergedError }
    }

    # ── Inject placeholder rows for selected categories missing from results ────
    if ($Result.Summary -and $Result.Summary.CategoryScores) {
        $PresentCategories = @($Result.Summary.CategoryScores | ForEach-Object { $_.Category })

        $MissingCategories = $SelectedCategories | Where-Object { $_ -notin $PresentCategories }

        if ($MissingCategories) {
            $ExtraRows = [System.Collections.Generic.List[object]]::new()
            foreach ($Missing in $MissingCategories) {
                $MatchingCat = $FilteredExam.Categories | Where-Object { $_.Name -eq $Missing }
                $TargetName  = if ($MatchingCat) { $MatchingCat.Target } else { '—' }

                $ExtraRows.Add([PSCustomObject]@{
                    PSTypeName      = 'Sage.CategoryGradeSummary'
                    Category        = $Missing
                    TargetName      = $TargetName
                    RawScore        = 0.0
                    MaxScore        = 0.0
                    NormalizedScore = 0.0
                    TestCount       = 0
                    PassedCount     = 0
                    FailedCount     = 0
                    Status          = 'Error'
                })
            }

            $Result.Summary.CategoryScores = @($Result.Summary.CategoryScores) + $ExtraRows.ToArray()
        }
    }

    return [PSCustomObject]@{
        Summary    = $Result.Summary
        Error      = $Result.Error
        OutputPath = $RunDir
    }
}
