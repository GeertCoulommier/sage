# SAGE Pipeline — Performance Investigation Plan

> **Branch:** `refactor/testing_performance`
> **Date:** 2026-05-30
> **Scope:** Single-student evaluation pipeline; multi-student parallelism exists but
> per-student time dominates.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Baseline Timing Profile](#2-baseline-timing-profile)
3. [Proposals](#3-proposals)
   - [P1 — Parallel category evaluation per student](#p1--parallel-category-evaluation-per-student)
   - [P2 — Parallel SSH session opening](#p2--parallel-ssh-session-opening)
   - [P3 — Skip redundant file copies in setup](#p3--skip-redundant-file-copies-in-setup)
   - [P4 — Cross-student collector caching](#p4--cross-student-collector-caching)
   - [P5 — Deduplicate same-collector calls within one student](#p5--deduplicate-same-collector-calls-within-one-student)
   - [P6 — SFTP vs Copy-Item -ToSession](#p6--sftp-vs-copy-item--tosession)
   - [P7 — JSON serialization instead of CLIXML for large payloads](#p7--json-serialization-instead-of-clixml-for-large-payloads)
   - [P8 — Lazy remote module check](#p8--lazy-remote-module-check)
   - [P9 — SSH ControlMaster connection multiplexing](#p9--ssh-controlmaster-connection-multiplexing)
   - [P10 — In-process Pester against collected data](#p10--in-process-pester-against-collected-data)
   - [P11 — Consolidate collector script startup overhead](#p11--consolidate-collector-script-startup-overhead)
   - [P12 — File copy uses individual Invoke-Command mkdir per file](#p12--file-copy-uses-individual-invoke-command-mkdir-per-file)
4. [Recommended Implementation Order](#4-recommended-implementation-order)

---

## 1. Executive Summary

The per-student evaluation pipeline for `ServerOS-proefexamen.psd1` involves:

- 3 SSH sessions (Linux, DC1, Client)
- 11 category evaluations across 3 targets
- 3 duplicate collector executions (Ad×2, FileServer×2, Docker×2)
- 22 file copies per student (11 collectors + 11 evaluators per target × 3 targets = 66 total)
- Sequential Pester execution on each remote VM per category

Measured bottlenecks in order of impact:

| Rank | Area | Typical Cost | Reducible? |
|------|------|-------------|------------|
| 1 | Sequential category loop (Invoke-RemoteCollector + Invoke-RemotePester) | 30–50 s | Yes — P1, P5 |
| 2 | Redundant collector runs (same collector, same session, different category) | 6–15 s | Yes — P5 |
| 3 | Sequential SSH session opening | 3–10 s | Yes — P2 |
| 4 | File copies during setup (66 Copy-Item per student) | 3–8 s | Yes — P3, P6 |
| 5 | Pester module check on every setup call | 1–3 s | Yes — P8 |
| 6 | mkdir Invoke-Command round-trip per file copy | 0.5–2 s | Yes — P12 |
| 7 | CLIXML overhead for large AD/DNS payloads | 1–3 s | Partially — P7 |

---

## 2. Baseline Timing Profile

For `ServerOS-proefexamen.psd1` (11 categories, 3 targets) with one benchmark student:

```text
Phase                               Estimated cost
─────────────────────────────────── ──────────────
1. SSH session open (×3, sequential)    3–9 s
2. Remote setup (×3, sequential):
   a. Pester module check (×3)          1–4 s
   b. Copy 11 collectors (×3)           2–5 s
   c. Copy 11 evaluators (×3)           2–5 s
3. Category loop (11 categories):
   a. Invoke-RemoteCollector (×11)     11–40 s
   b. Invoke-RemotePester (×11)        10–35 s
   c. ConvertTo-GradeSummary (×11)      1–3 s
4. Get-GradeSummary + Export            1–3 s
5. Close sessions (×3)                  0.5 s
─────────────────────────────────── ──────────────
TOTAL (estimated)                      31–94 s
```

Duplicate collector runs within the category loop (step 3a):

| Duplicate | Target | Collector | Categories |
|-----------|--------|-----------|------------|
| Ad ×2 | DC1 | Ad | C4 (Active Directory DC1) + C5b (AD Groups DC1) |
| FileServer ×2 | DC1 | FileServer | C5a (File Server DC1) + C6-bg (File Server Background DC1) |
| Docker ×2 | Linux | Docker | C10 (Docker Images Linux) + C11 (Docker Compose Linux) |

These 3 redundant collector executions each cost the full collector duration (2–8 s each),
contributing roughly 6–24 s of avoidable remote execution time.

---

## 3. Proposals

---

### P1 — Parallel category evaluation per student

**Targets:** `Invoke-StudentEvaluation.ps1` — the sequential `foreach ($Cat in $Exam.Categories)` loop

**Current behavior:**
`Invoke-StudentEvaluation` iterates categories one at a time:

```powershell
foreach ($Cat in $Exam.Categories) {
    $CollResult = Invoke-RemoteCollector ...   # 2-8 s
    $PesterRes  = Invoke-RemotePester    ...   # 1-8 s
}
```

All 11 categories run sequentially even though DC1, Client, and Linux are independent
machines that can be evaluated simultaneously.

**Proposed change:**
Group categories by `Target`, then process each target group in parallel using
`ForEach-Object -Parallel`. Within a target group, categories still run sequentially
(they share the same PSSession, which is not thread-safe). The parallel axis is across
targets, not across categories within the same target.

```text
Before:  DC1-C1 → DC1-C3 → DC1-C4 → DC1-C5a → ... → Client-C2 → ... → Linux-C9 → ...
After:   DC1:   [C1 → C3 → C4 → C5a → C5b → C6 → C6bg → C7]
         Client:[C2 → C8]                              ← in parallel
         Linux: [C9 → C10 → C11]                       ← in parallel
```

Since DC1 has 8 categories and Client/Linux have 2–3 each, the total time collapses
to the slowest target (DC1), not the sum of all targets.

**Expected impact:** **HIGH** — saves all Client + Linux evaluation time from the
critical path. For this exam: Client (2 categories ~10–20 s) and Linux (3 categories
~15–30 s) run in parallel with DC1's 8 categories. Estimated saving: 15–40 s.

**Pros:**

- Largest single speedup available
- Non-destructive: uses existing sessions, no protocol changes
- Clean isolation: each target already has its own session

**Cons / Risks:**

- `PSSession` objects are not thread-safe; must ensure each parallel branch
  holds its own session reference and never shares it
- Result collection requires thread-safe accumulation
  (`[System.Collections.Concurrent.ConcurrentBag[object]]`)
- Timeout checking becomes more complex across parallel branches
- Logging requires mutex-aware calls (already implemented in `Write-Log`)

**Implementation effort:** Medium

**Dependencies:** None; purely internal to `Invoke-StudentEvaluation`.

---

### P2 — Parallel SSH session opening

**Targets:** `Invoke-StudentEvaluation.ps1` — the sequential `foreach ($TName in $Exam.Targets.Keys)` session-open loop (lines ~168–195)

**Current behavior:**

```powershell
foreach ($TName in $Exam.Targets.Keys) {
    $Sess = New-RemoteSession ...   # 1-3 s per target
    $TargetSessions[$TName] = $Sess
}
```

Sessions to DC1, Client, and Linux open one at a time. Each `New-RemoteSession` call
blocks until the SSH handshake completes (up to 20 s timeout with 3 retry attempts).

**Proposed change:**
Open all sessions concurrently using `ForEach-Object -Parallel`, collect results into
a thread-safe hashtable:

```powershell
$SessionResults = $Exam.Targets.Keys | ForEach-Object -Parallel {
    $TName = $_
    $Tgt = ($using:Exam).Targets[$TName]
    [PSCustomObject]@{ Name = $TName; Session = New-RemoteSession ... }
}
$TargetSessions = @{}
foreach ($R in $SessionResults) { $TargetSessions[$R.Name] = $R.Session }
```

**Expected impact:** **MEDIUM** — saves ~(N-1) × session-open-time where N = number of
targets. For 3 targets at ~2 s each: saves ~4 s. If one target is slow/retrying, the
parallel approach fully hides that latency behind the fastest targets.

**Pros:**

- Very easy to implement (no architectural change)
- Zero risk to session correctness (each session is independent)
- Combines naturally with P1

**Cons / Risks:**

- SSH server may rate-limit simultaneous connection attempts from the same client IP
- Minor complexity increase in error handling (one failed session must not abort others)

**Implementation effort:** Small

**Dependencies:** None.

---

### P3 — Skip redundant file copies in setup

**Targets:** `Invoke-RemoteSetup.ps1` — the `Copy-File` loops for collectors and evaluators

**Current behavior:**
Every call to `Invoke-RemoteSetup` copies all 11 collector scripts and all 11 evaluator
scripts to the remote VM unconditionally, even if they already exist from a prior run
of the same exam.

For 3 targets × (11 + 11 files) = 66 `Copy-Item -ToSession` calls per student.
When 30 students share the same exam VM environment, all 66 copies happen 30 times.

**Proposed change:**
Before copying, check if the file already exists on the remote VM. Use a lightweight
hash comparison (local file vs remote) or a simpler size+mtime check.
Alternatively, add a `-SkipIfExists` flag that checks remote file existence (not hash)
and skips the copy when the remote file is already present.

The simplest safe approach: compute `Get-FileHash` locally, then `Get-FileHash` remotely
in a single batched `Invoke-Command`, compare, and skip files that match.

```powershell
# Batch hash check for all collectors in one Invoke-Command
$RemoteHashes = Invoke-Command -Session $Session -ScriptBlock {
    Get-ChildItem $using:RemoteCollectors -Filter '*.ps1' -ErrorAction SilentlyContinue |
        ForEach-Object { @{ Name = $_.Name; Hash = (Get-FileHash $_.FullName).Hash } }
}
# Build lookup; only copy files where hash differs or remote file is missing
```

**Expected impact:** **MEDIUM** — for repeated exams on the same VM (all 30 students
share the same infrastructure), eliminates ~98% of all file copies after student 1.
Per-student saving: 22 copies × ~150 ms = ~3.3 s. For 30 students: saves ~100 s total.

**Pros:**

- Easy to implement with backward compatibility (`-Force` still available as fallback)
- Reduces remote disk I/O
- Safe: hash comparison guarantees correctness

**Cons / Risks:**

- Adds 1 round-trip Invoke-Command for hash checking (costs ~200–400 ms)
- Net saving is only positive if more than 2 files are unchanged (break-even)
- If exam scripts change between students (unlikely), cache must be invalidated

**Implementation effort:** Small

**Dependencies:** None.

---

### P4 — Cross-student collector caching

**Targets:** `Invoke-RemoteCollector.ps1` and `Invoke-StudentEvaluation.ps1`

**Current behavior:**
In a 30-student exam where all students share the same infrastructure, the AD collector
runs 30 times on DC1 collecting identical data (the VM state doesn't change between
students). Same for DNS, FileServer, GPO, DHCP, etc.

**Proposed change:**
Store collector results in a module-scope or pipeline-scope dictionary keyed by
`TargetHostname+Port+CollectorName+ExamRunId`. On subsequent students, return the
cached result instead of executing a remote collection.

**Expected impact:** **HIGH** for shared-infra exams — eliminates 29/30 collector
executions after the first student. For 30 students × 11 categories × ~3 s average
collector time: saves ~990 s ≈ 16.5 minutes.

**Pros:**

- Enormous saving for shared-infrastructure exam scenarios
- No protocol or architectural changes needed

**Cons / Risks:**

- **Correctness risk:** If the student is expected to have modified the VM (self-setup
  scenario), caching stale collector data produces wrong grades
- In exams where each student configures their own VM (typical use), this would be
  **incorrect** — the collector data must reflect that student's configuration
- Safe **only** when: (a) all students share read-only reference infrastructure, OR
  (b) using the benchmark/TUI self-check mode against a single student's own VM
- Must be opt-in via a `-CacheCollectorData` flag with a clear warning
- Cache invalidation logic adds complexity

**Implementation effort:** Medium

**Dependencies:** Must be clearly opt-in; the default must remain no-cache.

---

### P5 — Deduplicate same-collector calls within one student

**Targets:** `Invoke-StudentEvaluation.ps1` — the category loop

**Current behavior:**
The proefexamen defines 11 categories, but 3 collector/target combinations run twice:

| Collector | Target | Categories | Wasted runs |
|-----------|--------|------------|-------------|
| Ad | DC1 | C4 (AD DC1) + C5b (AD Groups DC1) | 1 |
| FileServer | DC1 | C5a (File Server DC1) + C6-bg (File Server Background DC1) | 1 |
| Docker | Linux | C10 (Docker Images) + C11 (Docker Compose) | 1 |

Each duplicate collector run makes a full SSH round-trip and re-executes the entire
collection script, even though the data is identical to the first run within the same
student evaluation.

**Proposed change:**
Cache collector results within a single student run using a dictionary keyed by
`"$TargetName-$CollectorName"`. Before calling `Invoke-RemoteCollector`, check if
the result is already cached:

```powershell
$CollCacheKey = "$CatTarget-$($Cat.Collector)"
if ($CollectorCache.ContainsKey($CollCacheKey)) {
    $CollResult = $CollectorCache[$CollCacheKey]
} else {
    $CollResult = Invoke-RemoteCollector ...
    $CollectorCache[$CollCacheKey] = $CollResult
}
```

**Expected impact:** **HIGH per exam** — for this specific exam, eliminates 3 collector
executions per student. At ~3–8 s per collector: saves ~9–24 s per student.
For 30 students: saves ~270–720 s ≈ 4.5–12 minutes.

**Pros:**

- Within a single student run, VM state is constant — caching is always correct
- Simple implementation; no correctness risk (same student, same VM, same run)
- Generalizes automatically to any exam with duplicate collector/target combinations

**Cons / Risks:**

- Negligible: within one student run, the VM cannot change between categories
- Minor: collector errors in the first run propagate to subsequent categories
  (acceptable — error already captured; avoids hiding errors through retry)

**Implementation effort:** Small

**Dependencies:** None.

---

### P6 — SFTP vs Copy-Item -ToSession

**Targets:** `Copy-File.ps1` and `Invoke-RemoteSetup.ps1`

**Current behavior:**
`Copy-File` uses `Copy-Item -ToSession` which tunnels file data through the PSSession
as CLIXML-encoded byte arrays. This has per-file overhead (CLIXML framing, multiple
Invoke-Command round-trips for mkdir) and does not pipeline multiple transfers.

**Proposed change:**
For bulk transfers (setup phase), use native SSH/SFTP via the `sftp` CLI or
`Pscx\Invoke-Sftp`. SFTP multiplexes over a single SSH channel and avoids CLIXML
overhead for binary/text file transfer.

```powershell
# Example using openssh sftp batch mode:
$BatchFile = [System.IO.Path]::GetTempFileName()
$Files | ForEach-Object { "put $($_.FullName) $RemoteDir/$($_.Name)" } | Set-Content $BatchFile
sftp -P $Port -b $BatchFile "$UserName@$HostName"
```

**Expected impact:** **LOW–MEDIUM** — SFTP is typically 2–5× faster than `Copy-Item
-ToSession` for bulk small files. Estimated saving per student setup: 1–3 s.
Largest benefit when scripts change frequently (invalidating P3 cache).

**Pros:**

- Native protocol, better throughput for multiple small files
- Supports batch mode (all files in one connection)

**Cons / Risks:**

- Requires `sftp` CLI available on the Copilot/evaluation host (OpenSSH client)
- Must handle credential/key passing consistently with existing auth approach
- Windows SFTP path handling (backslash vs forward slash) adds complexity
- Cannot reuse the existing PSSession; needs separate auth flow

**Implementation effort:** Large

**Dependencies:** OpenSSH client on the evaluation host.

---

### P7 — JSON serialization instead of CLIXML for large payloads

**Targets:** `Invoke-RemoteCollector.ps1` and collector scripts in `Collectors/`

**Current behavior:**
All `Invoke-Command` calls return objects through PowerShell's CLIXML remoting
serialization. For large payloads (AD collector: 50–200 KB; DNS collector: 20–100 KB),
CLIXML is verbose and slow to deserialize.

`Invoke-RemotePester` already mitigates this by pre-converting Pester results to plain
hashtables before crossing the SSH boundary (see lines 120–180 of `Invoke-RemotePester.ps1`).

**Proposed change:**
For the largest collectors (Ad, Dns, FileServer), serialize the collector result to JSON
on the remote side before returning, then deserialize locally:

```powershell
# In collector script (remote):
$Result | ConvertTo-Json -Depth 10 -Compress
# In Invoke-RemoteCollector (local):
$RawResult = Invoke-Command ... | ConvertFrom-Json -AsHashtable
```

JSON deserialization is typically 3–10× faster than CLIXML for large structured objects.

**Expected impact:** **LOW–MEDIUM** — the SSH transport itself dominates; serialization
is a smaller fraction. Estimated saving: 0.5–2 s per large collector. Most benefit for
AD and FileServer collectors with many objects.

**Pros:**

- JSON is faster to serialize/deserialize than CLIXML for large objects
- JSON strings can also be compressed (`Compress-Archive` or gzip) for slow links
- Simpler debugging (human-readable JSON)

**Cons / Risks:**

- Changes the collector contract (all collectors must return JSON string instead of
  hashtable) — requires updating all 11 collector scripts and `Invoke-RemoteCollector`
- JSON depth limits may truncate deeply nested objects; must set `-Depth 10` or higher
- Type fidelity loss: DateTime becomes string, requires explicit parsing downstream

**Implementation effort:** Medium

**Dependencies:** All 11 collector scripts must be updated simultaneously.

---

### P8 — Lazy remote module check

**Targets:** `Invoke-RemoteSetup.ps1` — the `foreach ($ModuleName in $ModuleList)` loop

**Current behavior:**
Every call to `Invoke-RemoteSetup` runs an `Invoke-Command` to check if Pester ≥ 5.0.0
is installed on the remote VM. For 30 students on the same 3 VMs, this check runs
90 times (30 × 3 targets), even though the VM state does not change.

**Proposed change:**
Track which (hostname+port+moduleName) combinations have already been verified in a
module-scope dictionary. Skip the check on subsequent `Invoke-RemoteSetup` calls for
the same target:

```powershell
$CacheKey = "$($RemoteSession.HostName):$($RemoteSession.Port)-$ModuleName"
if ($script:ModuleCheckCache.ContainsKey($CacheKey)) {
    Write-Log ... "Skipping module check (cached)"
    continue
}
# ... original check logic ...
$script:ModuleCheckCache[$CacheKey] = $true
```

**Expected impact:** **LOW–MEDIUM** — saves 1 `Invoke-Command` round-trip per target
per student after the first. At ~0.5–1 s per round-trip × 3 targets × 29 students =
~45–87 s saved for a 30-student exam.

**Pros:**

- Trivial to implement (add a `$script:` dictionary)
- Zero correctness risk (module installs persist across sessions on the same VM)
- Safe for parallel mode (mutex needed or use `[System.Collections.Concurrent.ConcurrentDictionary]`)

**Cons / Risks:**

- Cache persists for the process lifetime; if a module is uninstalled mid-exam, the
  check would incorrectly skip (extremely unlikely in practice)
- Parallel mode requires thread-safe dictionary

**Implementation effort:** Small

**Dependencies:** None.

---

### P9 — SSH ControlMaster connection multiplexing

**Targets:** `New-RemoteSession.ps1` — SSH transport configuration

**Current behavior:**
Each `New-RemoteSession` call creates an independent TCP + SSH handshake. For 30
students on the same 3 VMs, this is 90 full SSH handshakes, each taking 1–3 s
(TLS/SSH key exchange, authentication).

**Proposed change:**
Configure OpenSSH `ControlMaster` and `ControlPath` in the SSH client config so that
connections to the same host/port reuse an existing master socket:

```text
# ~/.ssh/config
Host *
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```

Subsequent connections to the same host/port reuse the master and complete in ~50 ms
instead of ~1–2 s.

**Expected impact:** **MEDIUM** — saves ~1–2 s per SSH session open after the first per
host/port. For 30 students × 3 targets × ~1.5 s saved = ~135 s saved.

**Pros:**

- Zero code changes required; configured via SSH client config
- Transparent to PowerShell's SSH transport

**Cons / Risks:**

- `ControlMaster` is an OpenSSH-specific feature; not available on Windows OpenSSH
  versions older than 8.1 (Linux hosts: fully supported)
- PowerShell SSH remoting creates connections with specific SSH config options that
  may conflict with ControlMaster settings
- The master socket must persist between student evaluations; cleanup required
- Windows evaluation host may not support this feature

**Implementation effort:** Small (documentation + optional config script)

**Dependencies:** OpenSSH ≥ 8.1 on the evaluation host.

---

### P10 — In-process Pester against collected data

**Targets:** `Invoke-RemotePester.ps1` and evaluator scripts in `Evaluators/`

**Current behavior:**
Pester tests run **on the remote VM** via `Invoke-Command`. This requires:

1. Copying the evaluator script to the remote VM
2. Executing `Invoke-Pester` on the remote
3. Serializing Pester results back over SSH
4. Deserializing on the local side

**Proposed change:**
Run Pester **locally** (on the evaluation host), passing the already-collected
`CollectorResult.Data` as the test container data. The evaluator script would run in a
local pwsh process, not on the remote VM.

This is already partially possible: most evaluator tests inspect `$CollectedData` (a
hashtable passed via `New-PesterContainer`). Tests that use `curl`, `Resolve-DnsName`,
or other live network probes would still need remote execution.

**Hybrid approach:** Tag tests as `Local` (can run on eval host against collected data)
or `Remote` (must run on target VM). Only `Remote`-tagged tests use `Invoke-RemotePester`.

**Expected impact:** **MEDIUM–HIGH** for tests that only inspect collected data. Eliminates
SSH overhead + Pester startup time on remote (~1–3 s per category). For categories with
no live network tests (AD, DNS record checks, FileServer, DHCP, GPO): full saving.

**Pros:**

- Removes SSH round-trip for most categories
- Pester startup is faster locally than on remote Windows VMs
- Enables offline re-grading from saved collector data

**Cons / Risks:**

- **High implementation effort**: all 11 evaluator scripts must be audited and tagged
- Some tests inherently require remote execution (curl, live DNS lookups)
- Dual execution paths add maintenance burden
- Breaking change to evaluator script contract

**Implementation effort:** Large

**Dependencies:** Audit of all 11 evaluator scripts; evaluator refactoring.

---

### P11 — Consolidate collector script startup overhead

**Targets:** Collector scripts in `Collectors/`

**Current behavior:**
Each collector is a standalone `.ps1` file executed via `& $RemotePath -Variables $vars`.
PowerShell incurs process/script startup overhead per invocation. For 11 collectors × N
students on Windows, this includes PSModulePath resolution, profile loading (if any),
and JIT compilation of each script's AST.

**Proposed change:**
Consolidate all 11 collectors into a single dispatcher script that accepts a `-Names`
parameter and returns all requested collector results in one execution:

```powershell
# Single Invoke-Command:
$AllCollectorData = Invoke-Command -Session $Session -ScriptBlock {
    $Result = @{}
    foreach ($Name in $using:CollectorNames) {
        . "$using:CollectorDir/Invoke-${Name}Collector.ps1"
        $Result[$Name] = Invoke-"${Name}Collector" -Variables ($using:Vars)[$Name]
    }
    $Result
}
```

**Expected impact:** **LOW** — script startup on remote PowerShell is typically
100–300 ms per script. Consolidating saves at most ~1–3 s per target.

**Pros:**

- Reduces SSH round-trips (1 instead of N per target)
- Reduces remote process overhead

**Cons / Risks:**

- One script failure aborts all collectors for that target
- Collector isolation is lost (global variable pollution possible)
- Complex implementation; high maintenance burden

**Implementation effort:** Large

**Dependencies:** P5 must be implemented first (avoids duplicate collector runs).

---

### P12 — File copy uses individual Invoke-Command mkdir per file

**Targets:** `Copy-File.ps1`

**Current behavior:**
`Copy-File` runs `Invoke-Command` to create the parent directory **before every single
file copy**. For 22 files per session setup, this adds 22 `Invoke-Command` round-trips
just for directory checks, even though the directory already exists after the first call.

```powershell
# Current Copy-File.ps1:
Invoke-Command -Session $Session -ScriptBlock {
    if (-not (Test-Path $using:RemoteDir)) {
        New-Item -ItemType Directory -Path $using:RemoteDir -Force | Out-Null
    }
}
Copy-Item -Path $LocalPath -Destination $RemotePath -ToSession $Session -Force
```

**Proposed change 1:** Create directories once in `Invoke-RemoteSetup` before the copy
loop (already known), and call a variant of `Copy-File` that skips the mkdir check.

**Proposed change 2:** Remove the `Invoke-Command` mkdir from `Copy-File` and rely on
`Copy-Item -ToSession`'s native directory creation (it auto-creates parent dirs when
`-Recurse` is used on a directory, but not for individual files).

Simplest fix: add an optional `-EnsureDirectory` switch to `Copy-File`, default `$false`
when called from `Invoke-RemoteSetup` (which already creates the directories itself),
and `$true` only when called from `Invoke-RemoteCollector` (which copies a single script
to a potentially new directory).

**Expected impact:** **LOW–MEDIUM** — saves ~22 × 150 ms = ~3.3 s per target × 3 = ~10 s
per student. For 30 students: ~300 s = 5 minutes.

**Pros:**

- Trivially safe: directory already exists; skipping a no-op mkdir check is correct
- No change to behavior; purely an optimization

**Cons / Risks:**

- If `Invoke-RemoteSetup` is bypassed (unusual), the directory may not exist;
  `Invoke-RemoteCollector` must still ensure it exists before copying

**Implementation effort:** Small

**Dependencies:** `Invoke-RemoteSetup` must create directories before copy loops.

---

## 4. Recommended Implementation Order

Prioritized by impact/effort ratio, with dependencies respected:

| Priority | ID | Title | Impact | Effort | Correctness Risk |
|----------|----|-------|--------|--------|-----------------|
| 1 | P5 | Deduplicate same-collector within student | High | Small | None |
| 2 | P2 | Parallel SSH session opening | Medium | Small | None |
| 3 | P12 | Skip per-file mkdir round-trips | Medium | Small | None |
| 4 | P8 | Lazy remote module check | Medium | Small | None |
| 5 | P3 | Skip unchanged file copies in setup | Medium | Small | None |
| 6 | P1 | Parallel category evaluation per student | High | Medium | Low (session isolation) |
| 7 | P7 | JSON instead of CLIXML for large payloads | Low–Medium | Medium | Low (type fidelity) |
| 8 | P4 | Cross-student collector caching | High (shared infra) | Medium | **High if misused** — opt-in only |
| 9 | P9 | SSH ControlMaster multiplexing | Medium | Small | Low |
| 10 | P6 | SFTP vs Copy-Item -ToSession | Low–Medium | Large | Low |
| 11 | P10 | In-process Pester | Medium–High | Large | Medium |
| 12 | P11 | Consolidate collector dispatcher | Low | Large | Medium |

**Phase 1 (quick wins, implement first):** P5 + P2 + P12 + P8 + P3

**Phase 2 (architectural improvements):** P1 + P7

**Phase 3 (opt-in / high-effort):** P4 + P9 + P6

**Phase 4 (research / future):** P10 + P11
