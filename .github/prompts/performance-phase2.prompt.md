# Performance Phase 2: P3-unlock + P2 + P1 + P7

## Branch

Work on `refactor/testing_performance`.
Run `git fetch origin main` first, then verify the branch is current.
Use `tools/Run-Tests.ps1 -Detailed` after each step. All tests must stay green.
Use `$env:SAGE_QUICK_HOOK = '1'` for commits; one micro-commit per step.
Update CHANGELOG.md with every commit.

---

## Step 0 — P3 prerequisite: add `-KeepTempFiles` to `Close-RemoteSession`

**Production files:**

- `Sage/Public/Close-RemoteSession.ps1`
- `Sage/Public/Invoke-StudentEvaluation.ps1`

**Change in `Close-RemoteSession.ps1`:**
Add `[switch] $KeepTempFiles` as a non-mandatory parameter.
Wrap the entire `Invoke-Command { Remove-Item ... }` cleanup block in
`if (-not $KeepTempFiles) { ... }`.
The `Write-Log 'Cleaned up temp files'` verbose entry also moves inside the same guard.

**Change in `Invoke-StudentEvaluation.ps1`:**
Add `[switch] $KeepTempFiles` parameter.
In the `finally` block where `Close-RemoteSession` is called, pass
`-KeepTempFiles:$KeepTempFiles` through.

**Tests:** Add to `tests/Unit/Close-RemoteSession.Tests.ps1`:

- `'Does NOT clean temp files when -KeepTempFiles is set'` — mock `Invoke-Command`,
  assert it is NOT invoked when `-KeepTempFiles` is passed.
- `'Cleans temp files by default (no -KeepTempFiles)'` — assert `Invoke-Command` IS
  called without the switch (existing behaviour, verify it is unchanged).

**Commit:** `feat: add -KeepTempFiles to Close-RemoteSession to preserve remote scripts (unlocks P3 in lab mode)`

---

## Step 1 — P2: Parallel SSH session opening

**Production file:** `Sage/Public/Invoke-StudentEvaluation.ps1`
**Reference variant:** `Sage/Private/Benchmarks/Invoke-StudentEvaluation-P2.ps1`

Replace the sequential `foreach ($TName in $Exam.Targets.Keys)` session-open loop
(the block that calls `New-RemoteSession`) with the parallel pattern from the P2 variant.

Key implementation points (taken directly from the variant):

- Resolve module path BEFORE the parallel block:
  `$ModulePath = (Get-Module Sage).Path`
- Use `[System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]` to collect
  results.
- Each parallel block does `Import-Module $using:ModulePath -Force -ErrorAction Stop`
  then calls `New-RemoteSession` in a try/catch; wraps result in a `[PSCustomObject]`
  with `Name`, `Session`, and `Error` properties added to the bag.
- After the parallel block, loop over the bag to build `$TargetSessions` and add
  successful sessions to `$Sessions`. Log a warning for any failed session (same
  behaviour as the variant's `Write-Warning` call).
- Remove the `& $TimeoutCheck` call that was inside the sequential session loop
  (parallelism makes it meaningless at that point; overall timeout still applies).
- The setup loop that follows (`foreach ($TName in $TargetSessions.Keys)`) remains
  sequential — do not change it.

**Tests:** Add to `tests/Unit/Invoke-StudentEvaluation.Tests.ps1` a new
`Context 'Parallel session opening (P2)'` block:

- `'Opens all target sessions (parallel path)'` — mock `New-RemoteSession` to return
  a fake session; assert it is called once per target.
- `'Does not abort on a single session failure'` — mock `New-RemoteSession` to throw
  for one target; assert the other sessions are still opened and the category for the
  failed target is skipped (not a terminating error).

**Commit:** `perf: open SSH sessions in parallel (P2)`

---

## Step 2 — P1: Parallel category evaluation per target group

**Production file:** `Sage/Public/Invoke-StudentEvaluation.ps1`
**Reference variant:** `Sage/Private/Benchmarks/Invoke-StudentEvaluation-P1.ps1`

This step modifies the same file as Step 1 (apply after Step 1 is committed).

Replace the sequential `foreach ($Cat in $Exam.Categories)` loop with the
parallel-by-target-group pattern from the P1 variant. Follow the variant exactly
with these additions/corrections not in the variant:

1. **Build target groups** before the parallel block using a `[hashtable]` keyed
   by target name, each value a `[System.Collections.Generic.List[hashtable]]`
   of that target's categories.

2. **Inside each parallel branch:**
   - `Import-Module $using:ModulePath -Force -ErrorAction Stop` at the top.
   - Per-branch `$CollCache = @{}` (P5 collector cache — this is local to each
     branch, not shared; categories within the same target branch still benefit
     from deduplication).
   - Pass `$using:StudentStart.Elapsed.TotalSeconds` and `$using:StudentTimeout`
     for timeout checking; throw if exceeded.
   - Preserve the **`$SaveCollectorData`** handling block from the current
     production code: copy the full `if ($SaveCollectorData) { ... }` block into
     each parallel branch, using `$using:` for `$SaveCollectorData`,
     `$using:StudentOutputDir`, `$using:StudentEmail`, etc.
   - Use `$using:EvaluationsPath` when building `$PesterParams`.

3. **Result accumulation:** use
   `[System.Collections.Concurrent.ConcurrentBag[object]]` (`$ResultBag`) declared
   before the parallel block. Inside each branch, call `$Bag.Add($item)` for each
   `TestResult`. After the parallel block:
   `$AllTestResults = @($ResultBag.ToArray())`.
   Replace the existing `$AllTestResults` list with this pattern; remove the
   original `$AllTestResults = [System.Collections.Generic.List[object]]::new()`.

4. **ThrottleLimit:** set `-ThrottleLimit` to the number of targets:
   `$TargetGroups.Keys.Count` (typically 3).

5. **Session teardown** in `finally`: unchanged — `$Sessions` list was populated
   during the (now-parallel) session-open phase; `Close-RemoteSession` loop is
   the same.

**Tests:** Add to `tests/Unit/Invoke-StudentEvaluation.Tests.ps1` a new
`Context 'Parallel category evaluation (P1)'` block:

- `'Evaluates categories on different targets in parallel'` — create a fake exam
  with 2 targets (DC1 with 2 categories, Linux with 1 category); assert
  `Invoke-RemoteCollector` is called 3 times total and all 3 appear in the grade
  summary.
- `'P5 cache still deduplicates within a target branch'` — create a fake exam
  where DC1 has two categories sharing the same collector; assert
  `Invoke-RemoteCollector` is called once for that collector on DC1.

**Commit:** `perf: evaluate categories in parallel per target group (P1)`

---

## Step 3 — P7: Full JSON collector pipeline

**Production files:**

- All 11 collectors: `Sage/Collectors/Invoke-*Collector.ps1`
- `Sage/Private/Invoke-RemoteCollector.ps1`

### 3a — Update all 11 collectors

Each collector script ends with `return $Result` where `$Result` is a hashtable
with keys `Available`, `Reason`, `Data`, `Errors`.

Replace `return $Result` in every collector with:

```powershell
# Return as compressed JSON — Invoke-RemoteCollector deserializes via ConvertFrom-Json -AsHashtable
return ($Result | ConvertTo-Json -Depth 15 -Compress)
```

Do not change any other logic. Apply identically to all 11 collectors:
`Invoke-AdCollector.ps1`, `Invoke-ApacheCollector.ps1`,
`Invoke-BashHistoryCollector.ps1`, `Invoke-DhcpCollector.ps1`,
`Invoke-DnsCollector.ps1`, `Invoke-DockerCollector.ps1`,
`Invoke-FileServerCollector.ps1`, `Invoke-GeneralConfigCollector.ps1`,
`Invoke-GpoCollector.ps1`, `Invoke-IisCollector.ps1`,
`Invoke-NginxCollector.ps1`.

### 3b — Update `Invoke-RemoteCollector.ps1`

Replace the `$RawResult = Invoke-Command ...` block with a two-step pattern:

```powershell
# Collectors return compressed JSON (P7); deserialize to hashtable here.
# ConvertFrom-Json -AsHashtable produces [hashtable] for objects and preserves
# arrays, booleans, and null — type-compatible with the previous CLIXML contract.
$JsonResult = Invoke-Command -Session $RemoteSession.Session -ScriptBlock {
    & $using:RemotePath -Variables $using:Variables
}
$RawResult = $JsonResult | ConvertFrom-Json -AsHashtable
```

No other changes to `Invoke-RemoteCollector.ps1` — all downstream uses of
`$RawResult.Available`, `$RawResult.Data`, `$RawResult.Errors`, `$RawResult.Reason`
work identically after `-AsHashtable` deserialization.

### 3c — Update unit tests

In `tests/Unit/Invoke-RemoteCollector.Tests.ps1`, find the `Mock Invoke-Command`
calls that return a hashtable representing the collector result. Update each mock
to return a JSON string instead:

```powershell
Mock Invoke-Command {
    @{
        Available = $true
        Reason    = $null
        Data      = @{ Key = 'val' }
        Errors    = @()
    } | ConvertTo-Json -Depth 15 -Compress
}
```

In any evaluator unit tests that mock collector data directly (passing a pre-built
`$CollectedData` hashtable to `Invoke-RemotePester`), no changes are needed —
those tests bypass `Invoke-RemoteCollector` entirely.

**Tests to add** in `tests/Unit/Invoke-RemoteCollector.Tests.ps1`:

- `'Deserializes JSON collector output to a hashtable'` — assert `$Result.Data`
  is of type `[hashtable]` (or `[System.Collections.Hashtable]`).
- `'Preserves Available=false and Reason from JSON'` — mock `Invoke-Command` to
  return JSON with `Available = false` and a `Reason` string; assert both fields
  come through correctly.

**Commit:** `perf: switch all collectors to JSON return; deserialize in Invoke-RemoteCollector (P7)`

---

## Final verification

After all steps are committed:

1. Run `tools/Run-Tests.ps1 -Detailed` — all tests must be green.
2. Run `tools/Run-PowerShellLint.ps1` — zero warnings.
3. Run a live benchmark:

```powershell
# Set lab password via SageVault (preferred) or SAGE_BENCHMARK_PASSWORD env var before running.
pwsh -File tools/Measure-PipelinePerformance.ps1 -Runs 3 -Scenario Phase2-Combined 2>&1 |
    tee /tmp/bench-phase2.log | tail -5
```

1. Compare result against the Phase 1 baseline of ~96s. Expected: **<65s** (P1 alone
   should save ~30s by collapsing Client + Linux evaluation time off the critical path).

## Files changed summary

| File | Change |
|---|---|
| `Sage/Public/Close-RemoteSession.ps1` | Add `-KeepTempFiles` switch |
| `Sage/Public/Invoke-StudentEvaluation.ps1` | Parallel session-open (P2) + parallel target-group loop (P1) + `-KeepTempFiles` passthrough |
| `Sage/Private/Invoke-RemoteCollector.ps1` | JSON deserialization (P7) |
| `Sage/Collectors/Invoke-*Collector.ps1` (×11) | `ConvertTo-Json -Depth 15 -Compress` on return (P7) |
| `tests/Unit/Close-RemoteSession.Tests.ps1` | 2 new tests for `-KeepTempFiles` |
| `tests/Unit/Invoke-StudentEvaluation.Tests.ps1` | ~4 new tests for P2 + P1 |
| `tests/Unit/Invoke-RemoteCollector.Tests.ps1` | Update mocks + 2 new tests for JSON contract |
| `CHANGELOG.md` | Entry per commit |
