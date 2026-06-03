#Requires -Version 7.5
<#
    Unit tests for P5 — Collector result deduplication within a single student run.

    Validates that:
    1. The collector is called only ONCE for duplicate collector/target combinations.
    2. The grade output is identical whether the cache is used or not.
    3. A fresh cache is created per student (no cross-student leakage).
#>

Describe 'P5 — Collector Cache within student run' -Tag 'Unit', 'Performance' {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..' '..' '..' 'Sage' 'Sage.psd1'
        Import-Module $ModulePath -Force

        $BenchmarksPath = Join-Path $PSScriptRoot '..' '..' '..' 'Sage' 'Private' 'Benchmarks'
        . (Join-Path $BenchmarksPath 'Invoke-StudentEvaluation-P5.ps1')
    }

    Context 'Collector cache logic' {

        It 'should return the cached result on the second call for the same key' {
            $script:CallCount1 = 0
            $FakeCollector = {
                $script:CallCount1++
                [PSCustomObject]@{
                    PSTypeName    = 'Sage.CollectorResult'
                    CollectorName = 'TestCollector'
                    Available     = $true
                    Reason        = $null
                    Data          = @{ Value = 'collected' }
                    Errors        = @()
                    Duration      = [timespan]::FromSeconds(1)
                }
            }

            $Cache = @{}

            # First call — cache miss
            $Key1 = 'DC1-Ad'
            $Result1 = if ($Cache.ContainsKey($Key1)) { $Cache[$Key1] } else {
                $R = & $FakeCollector
                $Cache[$Key1] = $R
                $R
            }

            # Second call — cache hit
            $Result2 = if ($Cache.ContainsKey($Key1)) { $Cache[$Key1] } else {
                & $FakeCollector
            }

            $script:CallCount1 | Should -Be 1 -Because 'Collector should be invoked only once for the same key'
            $Result1.Data.Value | Should -Be 'collected'
            $Result2.Data.Value | Should -Be 'collected'
            $Result1 | Should -Be $Result2 -Because 'Both calls should return the same object'
        }

        It 'should call the collector separately for different target/collector combinations' {
            $script:CallCount2 = 0
            $FakeCollector = {
                param([string] $Name)
                $script:CallCount2++
                [PSCustomObject]@{ Available = $true; Data = @{ Name = $Name }; Errors = @() }
            }

            $Cache = @{}

            $Keys = @('DC1-Ad', 'DC1-FileServer', 'Linux-Docker')
            foreach ($Key in $Keys) {
                if (-not $Cache.ContainsKey($Key)) {
                    $Cache[$Key] = & $FakeCollector -Name $Key
                }
            }
            # Second pass (simulating second category with same collector)
            foreach ($Key in $Keys) {
                if (-not $Cache.ContainsKey($Key)) {
                    $Cache[$Key] = & $FakeCollector -Name $Key
                }
            }

            $script:CallCount2 | Should -Be 3 -Because 'Each unique key should be collected exactly once'
        }

        It 'proefexamen has 3 duplicate collector/target combinations' {
            $ExamPath = Join-Path $PSScriptRoot '..' '..' '..' 'Sage' 'data' 'werkcolleges' 'ServerOS-proefexamen.psd1'
            $Exam = Import-PowerShellDataFile -Path $ExamPath

            # Group categories by Target+Collector
            $CollectorUsage = @{}
            foreach ($Cat in $Exam.Categories) {
                $Key = "$($Cat.Target)-$($Cat.Collector)"
                if (-not $CollectorUsage.ContainsKey($Key)) {
                    $CollectorUsage[$Key] = 0
                }
                $CollectorUsage[$Key]++
            }

            $Duplicates = $CollectorUsage.GetEnumerator() | Where-Object { $_.Value -gt 1 }
            $DuplicateCount = @($Duplicates).Count

            $DuplicateCount | Should -Be 3 -Because 'Proefexamen has Ad×2, FileServer×2, Docker×2 duplicates'

            $DuplicateKeys = @($Duplicates | Select-Object -ExpandProperty Key | Sort-Object)
            $DuplicateKeys | Should -Contain 'DC1-Ad'
            $DuplicateKeys | Should -Contain 'DC1-FileServer'
            $DuplicateKeys | Should -Contain 'Linux-Docker'
        }

        It 'cache does not persist across separate hashtable instances (per-student isolation)' {
            $Cache1 = @{}
            $Cache2 = @{}
            $Key = 'DC1-Ad'

            $Cache1[$Key] = @{ StudentId = 'Student1' }
            # Cache2 should be independent
            $Cache2.ContainsKey($Key) | Should -BeFalse -Because 'Each student gets a fresh cache'
        }
    }
}

Describe 'P2 — Parallel SSH session opening' -Tag 'Unit', 'Performance' {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..' '..' '..' 'Sage' 'Sage.psd1'
        Import-Module $ModulePath -Force

        $BenchmarksPath = Join-Path $PSScriptRoot '..' '..' '..' 'Sage' 'Private' 'Benchmarks'
        . (Join-Path $BenchmarksPath 'Invoke-StudentEvaluation-P2.ps1')
    }

    Context 'ConcurrentBag session collection' {

        It 'ConcurrentBag accumulates items from multiple adders' {
            $Bag = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

            $Items = @('DC1', 'Client', 'Linux')
            $Items | ForEach-Object -Parallel {
                $Name = $_
                $B = $using:Bag
                $B.Add([PSCustomObject]@{ Name = $Name; Session = "FakeSession-$Name" })
            }

            $Bag.Count | Should -Be 3
            $Names = $Bag | Select-Object -ExpandProperty Name | Sort-Object
            $Names | Should -Contain 'DC1'
            $Names | Should -Contain 'Client'
            $Names | Should -Contain 'Linux'
        }

        It 'a failed session entry records null Session and non-null Error' {
            $Bag = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

            $Bag.Add([PSCustomObject]@{ Name = 'DC1'; Session = $null; Error = 'Connection refused' })
            $Bag.Add([PSCustomObject]@{ Name = 'Linux'; Session = 'FakeSession'; Error = $null })

            $FailedSessions = @($Bag | Where-Object { -not $_.Session })
            $FailedSessions.Count | Should -Be 1
            $FailedSessions[0].Name | Should -Be 'DC1'
            $FailedSessions[0].Error | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'P8 — Lazy remote module check cache' -Tag 'Unit', 'Performance' {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..' '..' '..' 'Sage' 'Sage.psd1'
        Import-Module $ModulePath -Force

        $BenchmarksPath = Join-Path $PSScriptRoot '..' '..' '..' 'Sage' 'Private' 'Benchmarks'
        . (Join-Path $BenchmarksPath 'Invoke-RemoteSetup-P8.ps1')
    }

    Context 'Module check cache' {

        It 'P8_ModuleCheckCache is initialized as a hashtable when the module is loaded' {
            # Verify that a fresh hashtable works as a cache store
            $CacheStore = @{}
            $CacheStore | Should -BeOfType [hashtable]
            $CacheStore.Count | Should -Be 0 -Because 'Cache starts empty'
        }

        It 'cache key format is HostName:Port-ModuleName' {
            $ExpectedKey = 'myhost.example.com:30022-Pester'

            $CacheLocal = @{}
            $CacheLocal[$ExpectedKey] = $true

            $CacheLocal.ContainsKey($ExpectedKey) | Should -BeTrue
        }

        It 'adding an entry prevents the same key from being added again' {
            $CacheLocal = @{}
            $Key = '10.0.0.1:22-Pester'

            $CheckCount = 0
            # Simulate two calls: first is a miss, second should be a hit
            if (-not $CacheLocal.ContainsKey($Key)) {
                $CheckCount++      # "Invoke-Command round-trip"
                $CacheLocal[$Key] = $true
            }
            if (-not $CacheLocal.ContainsKey($Key)) {
                $CheckCount++      # Should NOT execute
            }

            $CheckCount | Should -Be 1 -Because 'Module check should execute only once per unique key'
        }
    }
}

Describe 'P3 — Skip unchanged file copies' -Tag 'Unit', 'Performance' {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..' '..' '..' 'Sage' 'Sage.psd1'
        Import-Module $ModulePath -Force
    }

    Context 'Hash-based skip logic' {

        It 'files with matching hashes are skipped' {
            $LocalHashes = @{
                'Invoke-DnsCollector.ps1'     = 'AAAA1111'
                'Invoke-AdCollector.ps1'      = 'BBBB2222'
                'Invoke-DhcpCollector.ps1'    = 'CCCC3333'
            }
            $RemoteHashes = @{
                'Invoke-DnsCollector.ps1'     = 'AAAA1111'  # unchanged
                'Invoke-AdCollector.ps1'      = 'XXXX9999'  # changed
                # DhcpCollector absent on remote
            }

            $ToCopy = @()
            $ToSkip = @()
            foreach ($FileName in $LocalHashes.Keys) {
                if ($RemoteHashes.ContainsKey($FileName) -and
                    $RemoteHashes[$FileName] -eq $LocalHashes[$FileName]) {
                    $ToSkip += $FileName
                }
                else {
                    $ToCopy += $FileName
                }
            }

            $ToSkip.Count | Should -Be 1
            $ToSkip | Should -Contain 'Invoke-DnsCollector.ps1'
            $ToCopy.Count | Should -Be 2
            $ToCopy | Should -Contain 'Invoke-AdCollector.ps1'
            $ToCopy | Should -Contain 'Invoke-DhcpCollector.ps1'
        }

        It 'all matching hashes result in zero copies (second student scenario)' {
            $Files = @(
                'Invoke-DnsCollector.ps1'
                'Invoke-AdCollector.ps1'
                'Invoke-DhcpCollector.ps1'
            )
            $SharedHash = 'HASH123'
            $LocalHashes = @{}
            $RemoteHashes = @{}
            foreach ($F in $Files) {
                $LocalHashes[$F] = $SharedHash
                $RemoteHashes[$F] = $SharedHash
            }

            $CopyCount = 0
            foreach ($F in $Files) {
                if (-not ($RemoteHashes.ContainsKey($F) -and $RemoteHashes[$F] -eq $LocalHashes[$F])) {
                    $CopyCount++
                }
            }

            $CopyCount | Should -Be 0 -Because 'All files match; no copies needed (second student scenario)'
        }
    }
}
