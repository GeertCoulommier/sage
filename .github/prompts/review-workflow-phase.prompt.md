---
agent: agent
description: Universal phase prompt for implementing the SAGE Instructor Grade Review Workflow. Replace the PHASE block for each session.
---

## Role

You are an expert PowerShell 7.5 developer, ICT instructor and automated exam
grading system architect, and TUI designer familiar with ANSI/VT terminal rendering
using `[System.Console]` APIs and the SAGE codebase conventions.

## Mandatory reading — do this first, before any code

1. Read `docs/internal/EDIT-GRADE-WORKFLOW-PLAN.md` in full.
2. Read `CLAUDE.md` in full.
3. Read the current files you will modify (listed below) before touching them.

## Git identity — configure before the first commit

```powershell
git config user.name  "Geert Coulommier"
git config user.email "geert.coulommier@impulze.be"
```

## Branch setup

```powershell
git fetch origin main
git checkout -b feat/review-phase<N>-<slug> origin/main
```

Use branch naming: `feat/review-phase<N>-<slug>` (e.g. `feat/review-phase1-data-model`).

## This session: [PHASE N — TITLE]

Implement only the items listed below. Do NOT touch anything outside this scope.
Stop and ask if you encounter a dependency that is not covered here.

**Files to create or modify:**

- [ ] ...

**Acceptance criteria:**

- [ ] ...

## Workflow discipline (non-negotiable)

- **TDD strictly**: write the Pester test first → run `tools/Run-Tests.ps1 -Filter <TestName>`
  → see it fail → implement → run again → green. Never implement before the test exists.
- **Micro-commits**: one logical change per commit. Commit message format:
  `type(scope): short description` (Conventional Commits).
  After verifying tests pass: `$env:SAGE_QUICK_HOOK = '1'` then commit.
- **No backticks** anywhere. Splatting for 3+ params. PascalCase everywhere.
- **CBH required** on every function: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`,
  `.OUTPUTS`, at least one `.EXAMPLE`. Place CBH immediately before `function`.
- **Param alignment**: align `$` to column 100 across all params in a block.
- **Never run `Invoke-Pester` directly** — always use `tools/Run-Tests.ps1`.
- **Terminal output**: never run commands that produce unbounded output.
  Pipe through `| Select-Object -First 50` or redirect to a file.
- **After any `.md` change**: check VS Code errors panel for markdownlint violations.
  Zero lint errors required before committing.
- **Update CHANGELOG.md** with every commit (timestamp + version bump if warranted).

## Scope boundaries (hard stops)

- NEVER touch `legacy/` — not even to read it.
- NEVER modify `Sage/tui/Private/` (student self-check TUI).
- NEVER modify `Sage/Public/Invoke-SelfCheck.ps1`.
- NEVER change exported function names or mandatory parameters.

## Context budget

After ~15 tool calls or 3 large terminal outputs, write a `HANDOFF.md` in the
repo root and ask the user to start a fresh conversation.

---

## Phase reference (copy the relevant block into "This session" above)

### Phase 1 — Data model prerequisites

**Files to create or modify:**

- `Sage/Private/New-GradeResult.ps1` — add ReviewerNote field
- `Sage/Public/Export-GradeSummary.ps1` — persist ReviewData + ReviewerNote; write results-original.json
- `Sage/Private/Get-ReviewItemKey.ps1` — new: stable compound identity helper
- `tests/Unit/New-GradeResult.Tests.ps1` — update
- `tests/Unit/Export-GradeSummary.Tests.ps1` — update
- `tests/Unit/Get-ReviewItemKey.Tests.ps1` — new

**Acceptance criteria:**

- `New-GradeResult` returns an object with `ReviewerNote = $null` by default
- `Export-GradeSummary` JSON output includes `ReviewData` at `-Depth 15`
- `results-original.json` written on first export; second export does NOT overwrite it
- `Get-ReviewItemKey` returns `"email|target|category|context|testname"` format
- All existing tests still pass

---

### Phase 2 — Shared grading infrastructure

**Files to create or modify:**

- `Sage/Private/Invoke-GradeRecalculation.ps1` — new: extract from Edit-Grade lines 184-218
- `Sage/Public/Edit-Grade.ps1` — use `Invoke-GradeRecalculation` + `Get-ReviewItemKey` + ReviewerNote
- `tests/Unit/Invoke-GradeRecalculation.Tests.ps1` — new
- `tests/Unit/Edit-Grade.Tests.ps1` — update

**Acceptance criteria:**

- `Invoke-GradeRecalculation` is pure (no I/O), covers single-category, multi-category,
  zero-max, and override count scenarios
- `Edit-Grade` non-interactive mode keys overrides on compound identity
- `Edit-Grade` applies `ReviewerNote` when supplied in the `-Overrides` hashtable
- All existing Edit-Grade tests still pass

---

### Phase 3 — Review run loader

**Files to create or modify:**

- `Sage/Private/Get-ReviewRun.ps1` — new
- `tests/Unit/Get-ReviewRun.Tests.ps1` — new

**Acceptance criteria:**

- Single-student path: `RunRoot` containing `results.json` directly
- Multi-student path: enumerates immediate subdirectories only (no recursive search)
- Results sorted by `StudentName`
- `OriginalPath` is `$null` when `results-original.json` does not exist
- `Import-ResultSummary.ps1` (student TUI) is NOT modified

---

### Phase 4 — Per-student Excel export

**Files to create or modify:**

- `Sage/Public/Export-GradeSummary.ps1` — add results-original.xlsx and results-reviewed.xlsx
- `tests/Unit/Export-GradeSummary.Tests.ps1` — update for Excel sheets

**Acceptance criteria:**

- `results-original.xlsx` written once (idempotent); uses `AwardedGrade`; no italic
- `results-reviewed.xlsx` written on every save; italic on cells where `FinalGrade != AwardedGrade`
- `ImportExcel` not installed → warning emitted, no throw, JSON/CSV output unaffected

---

### Phase 5 — Aggregate grade book

**Files to create or modify:**

- `Sage/Public/Export-ExamGradeBook.ps1` — new
- `Sage/Public/Invoke-Evaluation.ps1` — wire aggregate export, `-AggregateExcelPath` parameter
- `tests/Unit/Export-ExamGradeBook.Tests.ps1` — new

**Acceptance criteria:**

- `Mode=Original` uses `AwardedGrade`; `Mode=Reviewed` uses `FinalGrade` with italic
- Merge adds new students, updates existing rows, preserves extra/manual rows
- Replace deletes and recreates the file
- New increments filename suffix until available
- Interactive prompt shown when file exists and `-MergeStrategy` is not supplied
- `-WhatIf` (ShouldProcess) supported

---

### Phase 6 — Instructor review TUI (Workflow A: free browse)

**Files to create:**

- `Sage/Public/Invoke-InstructorReview.ps1`
- `Sage/tui/review/Private/Show-ReviewMainMenu.ps1`
- `Sage/tui/review/Private/Show-StudentSelector.ps1`
- `Sage/tui/review/Private/Show-ReviewSummary.ps1`
- `Sage/tui/review/Private/Show-ReviewCategoryDetail.ps1`
- `Sage/tui/review/Private/Show-ReviewTestEdit.ps1`
- `Sage/tui/review/Private/Save-ReviewResult.ps1`
- `Sage/tui/review/Private/Initialize-ReviewConfig.ps1`
- `Start-InstructorReview.ps1`

**Acceptance criteria:**

- Free browse: StudentSelector → ReviewSummary → CategoryDetail → TestEdit navigation works end-to-end
- Edit form exposes score (validated `[0, PassGrade]`), `ManualOverrideReason`, `ReviewerNote` fields
- Save calls `Invoke-GradeRecalculation`; writes `results.json`; regenerates `results-reviewed.xlsx`
- Esc cancels without saving; R resets to `AwardedGrade`
- Unsaved-change indicator visible on category row when edits are pending

---

### Phase 7 — Instructor review TUI (Workflow B: guided queue)

**Files to create:**

- `Sage/tui/review/Private/Show-GuidedReviewQueue.ps1`

**Acceptance criteria:**

- Queue builds from all students, filtered by Failed / Overridden / All
- Last-used filter saved to `review-config-personal.psd1` on change
- `←/→` navigates students; `↑/↓` navigates tests in queue
- Progress bar displays filled/empty blocks with test and student counts
- Unsaved-change indicator (`*`) shown in student header row
- Prompt on `Q` if unsaved changes exist for any student
