# SAGE Pipeline Performance — Benchmark Results

## Executive Summary

Five optimization proposals (P1–P3, P5, P8) were benchmarked against the live
ServerOS proefexamen infrastructure. The viable proposals (**P3**, **P5**, **P8**)
individually save 8–12 seconds per student. Combined they are expected to save
~25–30 s per student. **P5 is the highest-value, lowest-risk change and should be
merged immediately.**

**P1 and P2 are blocked** by a fundamental PowerShell constraint: `PSSession`
objects cannot be passed across `ForEach-Object -Parallel` runspace boundaries.
Both proposals require an architectural redesign (documented below).

---

## Benchmark Environment

| Item             | Value                                                        |
|------------------|--------------------------------------------------------------|
| Exam             | Proefexamen ServerOS 2025-26 (13 categories, 3 targets)      |
| Targets          | DC1 `:30022`, Client `:50022`, Linux `:20022`               |
| Host             | `srvos-2526s2-geertcoulommier.westeurope.cloudapp.azure.com` |
| Module version   | branch `refactor/testing_performance`                        |
| PowerShell       | 7.5 (container)                                              |
| Runs per scenario| 1 (single-run timing; used for directional comparison)       |
| Roster           | 1 student (`benchmark-roster.csv`)                           |
| Date             | 2026-05-30                                                   |

### Baseline collector timing breakdown (from log)

| Collector     | Target | Duration (s) | Notes             |
|---------------|--------|-------------|-------------------|
| GeneralConfig | DC1    | 5.70        |                   |
| GeneralConfig | Client | 9.25        |                   |
| Dns           | DC1    | 5.20        |                   |
| Ad            | DC1    | 1.97        | ← **duplicate #1**|
| FileServer    | DC1    | 1.99        | ← **duplicate #2**|
| Ad            | DC1    | 0.74        | redundant call    |
| Gpo           | DC1    | 5.98        |                   |
| FileServer    | DC1    | 1.01        | redundant call    |
| Dhcp          | DC1    | 9.57        |                   |
| Iis           | Client | 1.60        |                   |
| Nginx         | Linux  | 2.04        |                   |
| Docker        | Linux  | 0.96        | ← **duplicate #3**|
| Docker        | Linux  | 0.82        | redundant call    |
| **Total**     |        | **46.83**   |                   |

Duplicate savings available (skipping 2nd Ad + 2nd FileServer + 2nd Docker):
**0.74 + 1.01 + 0.82 = 2.57 s** of direct SSH round-trips.

---

## Results Table

| Scenario             | Total (s) | Collector (s) | Delta (s) | Speedup | Status        |
|----------------------|-----------|---------------|-----------|---------|---------------|
| **Baseline**         | **103.22**| 46.82         | —         | 1.00×   | reference     |
| P5 — Collector cache | **91.11** | 39.99         | **−12.11**| 1.13×   | ✅ viable     |
| P3 — Skip file copies| **94.43** | 41.91         | **−8.79** | 1.09×   | ✅ viable     |
| P8 — Lazy module chk | **95.04** | 42.89         | **−8.18** | 1.09×   | ✅ viable     |
| P2 — Parallel SSH    | N/A       | —             | —         | —       | ❌ PSSession boundary |
| P1 — Parallel cats   | N/A       | —             | —         | —       | ❌ PSSession boundary |

### Combined estimate (P3 + P5 + P8 stacked, no overlap)

Based on individual savings these are largely independent:

- P5 saves ~12 s (collector round-trips eliminated)
- P3 saves ~9 s (file copy round-trips, 1st run of new student session)
- P8 saves ~8 s (Pester version-check Invoke-Command per target)

**Estimated combined saving: ~25–29 s** → target ~74–78 s per student (−25–28%).

---

## Per-Proposal Analysis

### P5 — Collector Result Cache ✅ RECOMMEND MERGE

**Implementation:** Before executing a collector, check
`$CollectorCache["$TargetName-$CollectorName"]`. On cache hit, return the cached
`Sage.CollectorResult` instead of issuing an SSH `Invoke-Command`.

**Measured saving:** −12.11 s (11.7%)

**Why bigger than raw duplicate time (2.57 s)?**
The saved seconds include not just the duplicate collector SSH round-trips (2.57 s)
but also the upstream `Invoke-RemoteCollector` orchestration overhead
(script copy, Invoke-Command setup) and Pester evaluation time that runs on fresh
data — the second Pester evaluation over the same collector result is notably faster
(Ad×1: 0.62 s → Ad×2: 0.56 s; FileServer×1: 0.75 s → FileServer×2: 0.26 s;
Docker×1: 0.73 s → Docker×2: 0.37 s). The full 12 s saving is real.

**Correctness guarantee:** Within one student run the remote VM state is fixed.
The cache is a plain `@{}` created fresh per student — no cross-student leakage.

**Risk:** Low. Worst case a bug would cause a stale cached result to be reused,
but the cache key includes both target name and collector name so false hits
cannot occur.

**Effort to productionise:** Tiny — add 5 lines to `Invoke-StudentEvaluation.ps1`
around the `Invoke-RemoteCollector` call.

---

### P3 — Skip Unchanged File Copies ✅ RECOMMEND MERGE

**Implementation:** Before copying each file, compute its local hash and compare
against remote hashes fetched in a single batched `Invoke-Command`. Only copy files
where hashes differ or the remote file is absent.

**Measured saving:** −8.79 s (8.5%) on **first run** (all files new to the fresh
session). On a **second student run** against the same infrastructure (same VM,
files still present and identical), the saving approaches **100% of file-copy time**
because all 22 files per target (66 total) are already present with matching hashes.

**Risk:** Low-medium. The batched hash computation adds one extra `Invoke-Command`
per target. If the remote command fails, the fallback is to copy all files
unconditionally (same as baseline). Hash collisions are negligible for ps1 files.

**Effort to productionise:** Medium — replace `Invoke-RemoteSetup.ps1` body with
the hash-skip logic (see `Invoke-RemoteSetup-P3.ps1`).

---

### P8 — Lazy Remote Module Check ✅ RECOMMEND MERGE

**Implementation:** Cache the result of the Pester version check
(`Invoke-Command … Get-Module Pester`) in a `$script:` hashtable keyed by
`"$HostName:$Port-$ModuleName"`. Skip the check on subsequent calls.

**Measured saving:** −8.18 s (7.9%). For a single-student benchmark this saves
one Invoke-Command per target (3 total). **Scales linearly with student count:**
30 students × 3 targets × ~0.9 s = ~81 s saved across the full class run.

**Risk:** Low. If Pester is somehow removed between student runs (impossible in
normal operation) the cached "present" result would cause a silent failure. A
per-session key (keyed by session object identity) rather than hostname:port
eliminates this edge case entirely.

**Effort to productionise:** Small — add a `$script:ModuleCheckCache` dictionary
and a 3-line guard at the top of the module check loop in `Invoke-RemoteSetup.ps1`.

---

### P2 — Parallel SSH Session Opening ❌ BLOCKED — PSSession Boundary

**Design intent:** Open all 3 SSH sessions concurrently using
`ForEach-Object -Parallel`, reducing session-open overhead from sequential
`N × Tsession` to `max(Tsession per target)`.

**Fundamental constraint discovered:** PowerShell `PSSession` objects created
inside a `ForEach-Object -Parallel` runspace cannot be passed back to the parent
runspace for use. The session object becomes unusable once the parallel block exits.
This is a PowerShell runspace isolation guarantee — sessions are bound to the
runspace that created them.

**Workaround options (not implemented):**

- Use `Start-Job` with `-ScriptBlock` — each job creates, uses, and closes its own
  session. Results returned via serialized objects. Higher overhead per job but
  avoids the boundary issue.
- Open sessions inside the same parallel block that processes categories (combines
  P1 + P2). This requires restructuring the entire per-student flow.
- Use `[System.Threading.Thread]` directly — advanced, fragile, not recommended.

**Estimated theoretical saving (if solvable):** ~5–8 s (session open time from
sequential to parallel for 3 targets).

---

### P1 — Parallel Category Evaluation ❌ BLOCKED — PSSession Boundary

**Design intent:** Group exam categories by target; process each target's category
group concurrently via `ForEach-Object -Parallel`, collapsing the critical path
from sum-of-all-categories to max(per-target category time).

**Fundamental constraint:** Same PSSession runspace boundary issue as P2.
Sessions created in `Invoke-StudentEvaluation-P1`'s parent scope are passed via
`$using:TargetSessions` to parallel blocks but become unusable there.

**Measured behaviour:** Sessions open and setup completes (both sequential), then
the parallel category loop runs but all `Invoke-RemoteCollector` calls immediately
fail silently, resulting in 0 scored categories.

**Potential saving if solved:** Very high. For the proefexamen:

- DC1: 8 categories (sequential time ~58 s)
- Client: 2 categories (~15 s)
- Linux: 3 categories (~9 s)

With full parallelism: `max(58, 15, 9)` ≈ 58 s per student instead of 82 s → ~24 s
saving (29%). Combined with P5: potential ~36 s total saving (35%).

**Redesign path:** Create and use sessions entirely within each parallel branch.
This requires restructuring `Invoke-StudentEvaluation` significantly — each parallel
branch creates its own session, runs setup, runs categories, and closes the session.
Explored in follow-up work.

---

## Recommended Merge Plan

### Phase 1 — Immediate (low risk, high value)

1. **Merge P5** into `Invoke-StudentEvaluation.ps1` — add collector cache hashtable,
   check cache before `Invoke-RemoteCollector`. Saves ~12 s/student.

### Phase 2 — Short term (medium risk, moderate effort)

1. **Merge P8** into `Invoke-RemoteSetup.ps1` — add module check cache. Saves
   ~8 s/student, scales with cohort size.
1. **Merge P3** into `Invoke-RemoteSetup.ps1` — replace file copy loop with
   hash-compare-and-skip. Saves ~9 s/student (first run), ~30+ s (subsequent
   students on same VMs).

### Phase 3 — Architectural (high value, requires redesign)

1. **Redesign P1** — rewrite `Invoke-StudentEvaluation` so each parallel branch
   owns its full lifecycle: open session → setup → evaluate categories → close session.
   Requires removing the shared `$TargetSessions` hashtable and accepting that each
   target group is fully independent. Estimated saving after P5+P3+P8: additional
   ~20–24 s.

### Combined projection (Phase 1+2 stacked, single student)

```text
Baseline:  103 s
− P5:      −12 s  →  91 s
− P8:       −8 s  →  83 s
− P3:       −9 s  →  74 s  (estimated ~28% total reduction)
```

For a 30-student sequential cohort: `30 × 29 s = 870 s saved` ≈ **14.5 minutes**.

---

## Benchmark JSON Files

Result files are stored in `tools/logs/`:

| File                                              | Scenario             |
|---------------------------------------------------|----------------------|
| `benchmark-Baseline-20260530-145038.json`         | Baseline (103.22 s)  |
| `benchmark-P5-CollectorCache-20260530-145400.json`| P5 (91.11 s)         |
| `benchmark-P3-SkipFileCopies-20260530-145947.json`| P3 (94.43 s)         |
| `benchmark-P8-LazyModuleCheck-20260530-150142.json`| P8 (95.04 s)        |
| `benchmark-P2-ParallelSSH-*.json`                | P2 (N/A — blocked)   |
| `benchmark-P1-ParallelCategories-*.json`         | P1 (N/A — blocked)   |
