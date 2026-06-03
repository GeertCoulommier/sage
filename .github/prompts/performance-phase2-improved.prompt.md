---
description: "Performance Phase 2 optimization (P2, P1, P7 parallel pipelines + JSON serialization). Verify Step 0 prerequisites, then implement P2 → P1 → P7 sequentially with parallel architecture patterns. TDD discipline, micro-commits per step, full test/lint gates."
name: "Performance Phase 2: Parallel Pipelines & JSON"
agent: "agent"
---

# Performance Phase 2: P2 + P1 + P7 Optimization Pipeline

> **Status:** Step 0 prerequisite complete; ready for P2/P1/P7 implementation  
> **Branch:** `refactor/testing_performance`  
> **Context:** Complex multi-file, multi-stage refactor with parallel architecture patterns  
> **Discipline:** TDD → Implement → Test Green → Lint Green → Micro-commit  

---

## Mandatory Reading — Do This First

Read these files **in order** before any code:

1. [CLAUDE.md](../CLAUDE.md) — full PowerShell style, naming, function conventions
2. [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md) — data types, call hierarchy, function graph
3. [docs/internal/PERFORMANCE-PLAN.md](../../docs/internal/PERFORMANCE-PLAN.md) — proposal rationale (P1–P12)
4. [docs/internal/PERFORMANCE-RESULTS.md](../../docs/internal/PERFORMANCE-RESULTS.md) — benchmark results; why P1/P2 blocked; why P5/P7/P8 viable
5. **This prompt** — execution roadmap

---

## Git Identity Configuration

Before the first commit, configure your Git identity **in this workspace only**:

```powershell
git config user.name  "Geert Coulommier"
git config user.email "geert.coulommier@impulze.be"
```

Verify:

```powershell
git config user.name   # should show "Geert Coulommier"
git config user.email  # should show "geert.coulommier@impulze.be"
```

**Do NOT commit under "GitHub Copilot" or any variant.** If a commit is made with wrong identity, you can amend it:

```powershell
git commit --amend --no-edit
```

---

## Branch Setup

Ensure you're on a fresh branch from `origin/main`:

```powershell
git fetch origin main
git checkout refactor/testing_performance
git log --oneline origin/main..HEAD | wc -l  # should be small; if >50, rebase
```

---

## Terminal Discipline

- **Never** run commands that produce unbounded output. Pipe through `Select-Object -First 50` or redirect to a file.
- For test runs, use `tools/Run-Tests.ps1 -Detailed` and capture full output before each commit.
- For linting, capture all violations; fix them all before committing.
- When checking long-running processes, tail log files rather than waiting on terminal.

---

## Workflow Discipline (Non-Negotiable)

### Testing Gate (TDD Pattern)

1. **Write test first** → run it → **see it fail** → implement → run → **green**
2. Always run: `tools/Run-Tests.ps1 -Detailed` before any commit
3. Zero failing tests required; all existing tests must still pass
4. If a test is slow, use `-Filter <TestName>` to iterate faster

### Linting Gate

1. Run: `tools/Run-PowerShellLint.ps1`
2. Fix **all** violations before committing
3. After any `.md` change, check VS Code's error panel for markdownlint violations
4. Zero lint errors required

### Micro-Commits

- One logical change per commit (e.g., "add -KeepTempFiles to Close-RemoteSession")
- Commit message format: `type(scope): description` (Conventional Commits)
- After tests & lint pass: `$env:SAGE_QUICK_HOOK = '1'` then commit
- Update `CHANGELOG.md` with every commit (timestamp + version bump if warranted)

### Code Quality Standards

- **No backticks** anywhere (use splatting for 3+ params)
- **PascalCase** for all names except loop vars (`$i`, `$_`)
- **Param alignment** to column 100 across all declarations
- **CBH required**: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.OUTPUTS`, at least one `.EXAMPLE` immediately before `function`
- **Return objects only** — no formatted output via `Write-Host` (except banners)
- **Fail fast**: `$ErrorActionPreference = 'Stop'`; use `$PSCmdlet.ThrowTerminatingError()` for fatal errors

---

## Step 0 Verification — P3 Prerequisite: `-KeepTempFiles` via Exam Config

**Objective:** The `-KeepTempFiles` switch (added previously to `Close-RemoteSession`) must be:

- Accessible from exam `.psd1` files as a configuration option (default: `$false`)
- Threaded through `Import-ExamDefinition` → `Invoke-Evaluation` → `Invoke-StudentEvaluation` → `Close-RemoteSession`
- Usable in both roster evaluations AND student self-checks (TUI)

### Files to Modify

| File | Change | Priority |
|------|--------|----------|
| `Sage/data/exams/ServerOS-proefexamen.psd1` | Add `KeepTempFiles = $false` to exam root | 1 |
| `Sage/Public/Import-ExamDefinition.ps1` | Validate `KeepTempFiles` key (optional, default `$false`) | 1 |
| `Sage/Public/Invoke-Evaluation.ps1` | Pass `$Exam.KeepTempFiles` to `Invoke-StudentEvaluation` | 2 |
| `Sage/Public/Invoke-StudentEvaluation.ps1` | Accept & pass through to `Close-RemoteSession` | 2 |
| `Sage/tui/Private/Show-SelfCheckSettings.ps1` | Add TUI checkbox: "Keep temporary files on target" | 3 |
| `tests/Unit/Import-ExamDefinition.Tests.ps1` | Test exam with & without `KeepTempFiles` key | 1 |
| `tests/Unit/Invoke-StudentEvaluation.Tests.ps1` | Mock `-KeepTempFiles` parameter pass-through | 2 |

### Acceptance Criteria — Step 0

- [ ] Exam `.psd1` can include optional `KeepTempFiles = $true` at root level
- [ ] Missing key defaults to `$false` (backward compatible)
- [ ] `Import-ExamDefinition` validates & stores in returned hashtable
- [ ] `Invoke-StudentEvaluation` receives parameter & passes to `Close-RemoteSession`
- [ ] `Invoke-Evaluation` threads `$Exam.KeepTempFiles` to all student runs (both parallel & sequential paths)
- [ ] TUI settings screen shows checkbox; state persists in `tui-config-personal.psd1`
- [ ] All unit tests pass (both new & existing)
- [ ] Live test on Linux target (`:20022`) shows files persist when enabled, cleaned when disabled
- [ ] Zero lint errors
- [ ] Micro-commit message: `feat(config): add KeepTempFiles exam option for P3 lab mode`

---

## Step 1 — P2: Parallel SSH Session Opening

**Objective:** Open 3 SSH sessions concurrently instead of sequentially (saves ~4s per student).

**Reference variant:** `Sage/Private/Benchmarks/Invoke-StudentEvaluation-P2.ps1`

### Files to Modify

| File | Change |
|------|--------|
| `Sage/Public/Invoke-StudentEvaluation.ps1` | Replace sequential `foreach ($TName in $Exam.Targets.Keys)` session-open loop with `ForEach-Object -Parallel` |
| `tests/Unit/Invoke-StudentEvaluation.Tests.ps1` | Add new `Context 'Parallel session opening (P2)'` with 2 tests |

### Key Implementation Points

- Resolve module path BEFORE parallel block: `$ModulePath = (Get-Module Sage).Path`
- Use `[System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]` for thread-safe result collection
- Each parallel iteration: `Import-Module $using:ModulePath -Force`, call `New-RemoteSession`, catch errors, add `[PSCustomObject]@{ Name = $TName; Session = $Sess; Error = $err }` to bag
- After parallel block, loop over bag: on success, add to `$TargetSessions`; on error, `Write-Warning` and skip
- **Remove** the `& $TimeoutCheck` call inside the session loop (parallelism makes per-session checking meaningless)
- The subsequent setup loop (`foreach ($TName in $TargetSessions.Keys)`) remains sequential — do NOT change

### Acceptance Criteria — Step 1

- [ ] Parallel session-open completes all 3 sessions concurrently
- [ ] Single failed session does NOT abort others (warning logged, category skipped)
- [ ] `Write-Log` calls are thread-safe (use existing `Write-Log` implementation)
- [ ] `$TargetSessions` hashtable built correctly after parallel block
- [ ] All existing tests still pass
- [ ] New tests verify: (1) all sessions opened in parallel, (2) single failure doesn't abort
- [ ] Zero lint errors
- [ ] Micro-commit message: `perf(parallel): open SSH sessions in parallel (P2)`

### Benchmarking (Optional)

Expected: **~4s saved** per student (N-1 × session-open-time = 2 × ~2s per session).

---

## Step 2 — P1: Parallel Category Evaluation Per Target Group

**Objective:** Evaluate categories on DC1, Client, and Linux in parallel by target (saves ~25s per student by collapsing Client + Linux onto DC1 critical path).

**Reference variant:** `Sage/Private/Benchmarks/Invoke-StudentEvaluation-P1.ps1`

### Files to Modify

| File | Change |
|------|--------|
| `Sage/Public/Invoke-StudentEvaluation.ps1` | Replace sequential `foreach ($Cat in $Exam.Categories)` with target-group parallel `ForEach-Object -Parallel` |
| `tests/Unit/Invoke-StudentEvaluation.Tests.ps1` | Add new `Context 'Parallel category evaluation (P1)'` with 2 tests |

### Key Implementation Points

1. **Build target groups** before the parallel block:

   ```powershell
   $TargetGroups = @{}
   foreach ($Cat in $Exam.Categories) {
       $TName = $Cat.Target
       if (-not $TargetGroups[$TName]) {
           $TargetGroups[$TName] = [System.Collections.Generic.List[hashtable]]::new()
       }
       $TargetGroups[$TName].Add($Cat)
   }
   ```

2. **Inside each parallel branch:**
   - `Import-Module $using:ModulePath -Force -ErrorAction Stop` at the top
   - Per-branch `$CollCache = @{}` (P5 local cache per target)
   - Pass `$using:StudentStart.Elapsed.TotalSeconds` and `$using:StudentTimeout` for timeout checks
   - **Copy the full `if ($SaveCollectorData) { ... }` block** from current production code into each branch (using `$using:` for outer vars)
   - Use `$using:EvaluationsPath` when building `$PesterParams`
   - Per-branch result collection: add all `TestResult` objects to thread-safe bag

3. **Result accumulation:**

   ```powershell
   $AllTestResults = @($ResultBag.ToArray())
   ```

   Replace the old `$AllTestResults = [System.Collections.Generic.List[object]]::new()` pattern

4. **ThrottleLimit:** set to number of targets: `$TargetGroups.Keys.Count` (typically 3)

5. **Session teardown** in `finally`: unchanged (sessions list already built in Step 1)

### Acceptance Criteria — Step 1

- [ ] Categories evaluated in parallel by target (DC1, Client, Linux run concurrently)
- [ ] Within each target, categories run sequentially (safe on same PSSession)
- [ ] Result accumulation thread-safe (no lost `TestResult` objects)
- [ ] `SaveCollectorData` logic preserved in all parallel branches
- [ ] All existing tests still pass
- [ ] New tests verify: (1) categories on different targets run in parallel, (2) P5 cache works per-branch
- [ ] Zero lint errors
- [ ] Micro-commit message: `perf(parallel): evaluate categories per target group in parallel (P1)`

### Risk Analysis

**Risk: PSSession thread-safety**  
Mitigation: Each parallel branch holds its own session reference; no sharing across branches.

**Risk: Timeout checking across parallel branches**  
Mitigation: Each branch has independent timeout check using elapsed time from `StudentStart`; overall timeout still applies at student level.

---

## Step 3 — P7: Full JSON Collector Pipeline

**Objective:** Replace CLIXML serialization with compressed JSON for collector results (saves ~1–3s per student by reducing payload size and deserialization overhead).

### Substeps

#### 3a — Update All 11 Collectors

**Files:** All in `Sage/Collectors/Invoke-*Collector.ps1`:

- `Invoke-AdCollector.ps1`
- `Invoke-ApacheCollector.ps1`
- `Invoke-BashHistoryCollector.ps1`
- `Invoke-DhcpCollector.ps1`
- `Invoke-DnsCollector.ps1`
- `Invoke-DockerCollector.ps1`
- `Invoke-FileServerCollector.ps1`
- `Invoke-GeneralConfigCollector.ps1`
- `Invoke-GpoCollector.ps1`
- `Invoke-IisCollector.ps1`
- `Invoke-NginxCollector.ps1`

**Change:** Replace final `return $Result` with:

```powershell
# Return as compressed JSON — Invoke-RemoteCollector deserializes via ConvertFrom-Json -AsHashtable
return ($Result | ConvertTo-Json -Depth 15 -Compress)
```

**Acceptance:**

- [ ] All 11 collectors return JSON strings (not hashtables)
- [ ] No other logic changed in any collector
- [ ] Collectors still executable directly on remote (can test: `pwsh -ScriptBlock { & $Path }`)

#### 3b — Update `Invoke-RemoteCollector.ps1`

**File:** `Sage/Private/Invoke-RemoteCollector.ps1`

**Change:** Replace the `$RawResult = Invoke-Command ...` block with:

```powershell
# Collectors return compressed JSON (P7); deserialize to hashtable here.
# ConvertFrom-Json -AsHashtable produces [hashtable] for objects and preserves
# arrays, booleans, and null — type-compatible with the previous CLIXML contract.
$JsonResult = Invoke-Command -Session $RemoteSession.Session -ScriptBlock {
    & $using:RemotePath -Variables $using:Variables
}
$RawResult = $JsonResult | ConvertFrom-Json -AsHashtable
```

**Acceptance:**

- [ ] Deserialization produces hashtable (not PSCustomObject)
- [ ] All downstream uses of `$RawResult.Available`, `.Data`, `.Errors`, `.Reason` work identically
- [ ] No other changes to function logic

#### 3c — Update Unit Tests

**File:** `tests/Unit/Invoke-RemoteCollector.Tests.ps1`

**Changes:**

1. Find all `Mock Invoke-Command` calls that return a hashtable collector result
2. Update each mock to return JSON string instead:

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

3. Add two new tests:
   - `'Deserializes JSON collector output to a hashtable'` — assert `$Result.Data` is `[hashtable]` type
   - `'Preserves Available=false and Reason from JSON'` — mock JSON with `Available = $false`; assert both fields come through

**Evaluator test note:** Tests that mock collector data directly (pre-built hashtables passed to `Invoke-RemotePester`) require NO changes — they bypass `Invoke-RemoteCollector`.

### Acceptance Criteria — Step 3 (Full)

- [ ] All 11 collectors return compressed JSON
- [ ] `Invoke-RemoteCollector` deserializes JSON to hashtable via `-AsHashtable`
- [ ] Deserialized hashtables are type-compatible with previous CLIXML output
- [ ] All unit tests pass (updated mocks + new JSON tests)
- [ ] All evaluator unit tests still pass
- [ ] Zero lint errors
- [ ] Micro-commit message: `perf(json): switch all collectors to JSON serialization; deserialize in Invoke-RemoteCollector (P7)`

---

## Final Verification

After **all steps committed**:

### 1. Test Suite Green

```powershell
tools/Run-Tests.ps1 -Detailed
```

**Requirement:** All tests pass, no skipped, zero failures.

### 2. Lint Suite Green

```powershell
tools/Run-PowerShellLint.ps1
```

**Requirement:** Zero warnings/errors.

### 3. Live Test (Linux Target)

Connect to Linux target and run a single-student evaluation:

```powershell
# Set credentials if not cached
$Cred = Get-Credential  # student / Student1

$Eval = Invoke-Evaluation `
    -ExamPath './Sage/data/exams/ServerOS-proefexamen.psd1' `
    -RosterPath './test-roster.csv' `
    -OutputDir './test-output' `
    -KeyFilePath $null `
    -Credential $Cred
```

**Requirement:** Completes without error; `$Eval.TestResults.Count > 0`.

### 4. Performance Benchmark (Optional)

Expected combined savings: **~25–30s** per student (P1 is the highest-value proposal).

```powershell
# If you have SageVault configured or SAGE_BENCHMARK_PASSWORD env var set:
pwsh -File tools/Measure-PipelinePerformance.ps1 -Runs 3 -Scenario Phase2-Combined 2>&1 |
    tee /tmp/bench-phase2.log | tail -20
```

---

## Context Budget Tracking

- **Complexity level:** High (parallel architecture, 40+ modified lines, 3 steps)
- **Context threshold:** After ~20 tool calls or 3× large terminal outputs (>10KB each), write `HANDOFF.md` and suggest fresh conversation
- **Estimate:** This task will likely require 25–35 tool calls total across 3 steps

If context approaches 60%, **stop and summarize** in `HANDOFF.md`:

- What was completed (step number, files modified)
- What remains (next steps)
- Current git branch & last commit hash
- Any known issues or blockers

---

## File Change Matrix (Quick Reference)

### Step 0 (Verification)

- `Sage/data/exams/ServerOS-proefexamen.psd1` — add config key
- `Sage/Public/Import-ExamDefinition.ps1` — validate key
- `Sage/Public/Invoke-Evaluation.ps1` — thread parameter
- `Sage/Public/Invoke-StudentEvaluation.ps1` — accept & pass parameter
- `Sage/tui/Private/Show-SelfCheckSettings.ps1` — TUI checkbox
- `tests/Unit/*.Tests.ps1` — new/updated test cases

### Step 1 (P2)

- `Sage/Public/Invoke-StudentEvaluation.ps1` — parallel session open
- `tests/Unit/Invoke-StudentEvaluation.Tests.ps1` — new P2 context

### Step 2 (P1)

- `Sage/Public/Invoke-StudentEvaluation.ps1` — parallel category eval
- `tests/Unit/Invoke-StudentEvaluation.Tests.ps1` — new P1 context

### Step 3 (P7)

- `Sage/Collectors/Invoke-*Collector.ps1` (×11) — JSON return
- `Sage/Private/Invoke-RemoteCollector.ps1` — JSON deserialization
- `tests/Unit/Invoke-RemoteCollector.Tests.ps1` — updated mocks + new tests

---

## Commit Checklist

Before pushing each commit:

- [ ] Run `tools/Run-Tests.ps1 -Detailed` — all pass
- [ ] Run `tools/Run-PowerShellLint.ps1` — zero violations
- [ ] For `.md` changes: VS Code error panel shows zero markdownlint errors
- [ ] `CHANGELOG.md` updated with timestamp & version bump
- [ ] Git identity correct: `git config user.name` shows "Geert Coulommier"
- [ ] Commit message format: `type(scope): description` (Conventional Commits)
- [ ] Commit contains ONE logical change only
- [ ] Before commit: `$env:SAGE_QUICK_HOOK = '1'` (skip heavy pre-commit; CI enforces on push)

---

## Key References

| Reference | Purpose |
|-----------|---------|
| [CLAUDE.md](../CLAUDE.md) | PowerShell style, naming conventions, function templates |
| [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) | Data flow, call graph, type hierarchy |
| [PERFORMANCE-PLAN.md](../../docs/internal/PERFORMANCE-PLAN.md) | Optimization rationale & trade-offs |
| [PERFORMANCE-RESULTS.md](../../docs/internal/PERFORMANCE-RESULTS.md) | Benchmark data; why P1/P2 blocked; P5/P7/P8 viable |
| `Sage/Private/Benchmarks/Invoke-StudentEvaluation-P*.ps1` | Reference implementations for each phase |

---

## Troubleshooting

**Q: Tests fail after modifying a collector.**  
A: Evaluator unit tests mock collector results as JSON strings. Verify your `Mock Invoke-Command` returns `<JSON> \| ConvertTo-Json -Depth 15 -Compress` not a hashtable.

**Q: Lint errors in modified files.**  
A: Run `tools/Run-PowerShellLint.ps1` and fix all violations (param names, line length, etc.). Common: param alignment broken during edits.

**Q: `Write-Log` calls in parallel branches produce no output.**  
A: The `Write-Log` implementation is module-scoped. Inside `ForEach-Object -Parallel`, each runspace has a fresh module scope. Ensure the main module file sets `$script:LogPath` correctly; it should be inherited by `Invoke-StudentEvaluation` running inside the module.

**Q: Parallel branch times out.**  
A: Increase `$StudentTimeout` or check target responsiveness. Timeout check inside each branch uses `StudentStart.Elapsed.TotalSeconds`; ensure it matches `StudentTimeout` value passed in.

---

## Questions?

- Check `CLAUDE.md` for coding standards
- Check `ARCHITECTURE.md` for call hierarchy & data types
- Check `PERFORMANCE-PLAN.md` for proposal rationale
- If stuck on a specific step, review the reference variant file in `Sage/Private/Benchmarks/`
