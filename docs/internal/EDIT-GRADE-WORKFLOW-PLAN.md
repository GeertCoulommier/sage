# SAGE — Instructor Grade Review Workflow: Implementation Plan

> **Purpose:** Detailed technical plan for Claude Sonnet to implement the
> instructor-facing grade review TUI and exam-wide grade book export.
> Read CLAUDE.md before implementing anything.
> **Created:** 2026-05-31

---

## 1. Overview

### What and why

SAGE currently has a single linear reviewer (`Edit-Grade.ps1`) that opens one
student's `results.json` and walks failed tests sequentially with `Read-Host`.
There is no way to browse across students, inspect collector data in context,
or view/edit grades in an interactive split-pane interface.

This plan designs and specifies two new capabilities:

1. **Instructor Review TUI** — an interactive terminal UI for reviewing and
   editing grades across a full exam run or for a single student. Two distinct
   review workflows.
2. **Exam Grade Book Export** — aggregate per-exam Excel files (original
   automatic grades and reviewed/edited grades), plus per-student reviewed
   Excel files with changed grades in italic.

### Guiding principles

- All code must conform to every rule in CLAUDE.md (strict PowerShell, no
  aliases, splatting, PascalCase, param alignment, CBH, TDD first).
- Never touch `legacy/` at all.
- Student self-check TUI (`Invoke-SelfCheck` → `Sage/tui/`) must remain
  unchanged — instructor review is a completely separate entry point.
- Do not duplicate grading math. Extract shared helpers once and reuse.
- Follow the result type hierarchy:
  `CollectorResult → TestResult → CategoryGradeSummary → StudentGradeSummary`.

---

## 2. Prerequisite: Data Model Gaps

These must be resolved before building any review UI or grade-book export.

### 2.1 ReviewData is not persisted

`ConvertTo-GradeSummary.ps1` attaches `ReviewData` to each `Sage.TestResult`
object using the `ReviewContextMap` scriptblocks defined in each
`Evaluators/*.Tests.ps1` file (e.g. `Evaluators/Dns.Tests.ps1` — see the
`$ReviewContextMap` hashtable at the top). This structured data is lost because
`Export-GradeSummary.ps1` does not include `ReviewData` in the JSON document.

**Required fix:** Add `ReviewData` to the `TestResults` serialization block
in `Export-GradeSummary.ps1`. Set `Depth` to at least 15 when the document
contains ReviewData objects. Update corresponding unit tests in
`tests/Unit/Export-GradeSummary.Tests.ps1`.

### 2.2 ReviewerNote field missing

`Sage.TestResult` (defined in `New-GradeResult.ps1`) needs a `ReviewerNote`
field: an optional free-form string annotation that can be placed on **any**
test, pass or fail, without requiring a grade change.

**Distinction from ManualOverrideReason:**

| Field | When set | Meaning |
|-------|----------|---------|
| `ManualOverrideReason` | Only when `ManualOverrideGrade != null` | Justifies *why* the grade changed |
| `ReviewerNote` | Any time, grade change or not | Observation/annotation about a test |

Example: a test passes, but the reviewer notes "student's approach is fragile —
no grade change but worth flagging". A failing test may get:
`ManualOverrideGrade = 1.0`, `ManualOverrideReason = "trailing dot — functionally
correct"`, and `ReviewerNote = "common student error — consider updating test
tolerance"`.

**Required fix:** Add `ReviewerNote = $null` to the object literal in
`New-GradeResult.ps1`, add it as an optional `[string]` parameter, include it
in the JSON serialization in `Export-GradeSummary.ps1`, and include it in
`Edit-Grade.ps1` when applying overrides. Update unit tests.

### 2.3 Stable review item identity

`Edit-Grade.ps1` currently keys overrides on `TestName` alone, which is not
unique across categories or targets. All review-related code must use the
compound identity:

```text
StudentEmail + TargetName + Category + Context + TestName
```

Use a helper private function `Get-ReviewItemKey` that formats this as a
canonical string: `"$StudentEmail|$TargetName|$Category|$Context|$TestName"`.
Place it in `Sage/Private/`. Update `Edit-Grade.ps1` to use it in non-interactive
mode (the interactive loop already uses object references, so it is unaffected).

### 2.4 Original results must be immutable after first evaluation

Each student's result folder must contain two result files:

| File | Written when | Modified after? |
|------|-------------|-----------------|
| `results-original.json` | At first evaluation export | **Never** |
| `results.json` | At first evaluation export (identical to original) | Yes, by Edit-Grade and review workflow |

**Required fix in `Export-GradeSummary.ps1`:** When writing `results.json`,
also write `results-original.json` *only if it does not yet exist*. Never
overwrite an existing `results-original.json`. Add a unit test for this
idempotency guarantee.

---

## 3. Shared Grading Infrastructure

### 3.1 Extract shared recomputation helper

`Edit-Grade.ps1` lines 184–218 duplicate category and total recalculation
logic. `Invoke-LocalEvaluation.ps1` (TUI) also inlines this math. Extract it
into:

**`Sage/Private/Invoke-GradeRecalculation.ps1`**

```text
function Invoke-GradeRecalculation
  Input:  [object[]] $TestResults
  Output: PSCustomObject with:
    CategoryScores  — Sage.CategoryGradeSummary[]
    TotalScore      — { Raw, Max, Normalized }
    OverrideCount   — [int]
```

This function is pure (no I/O, no side effects). It calls
`ConvertTo-NormalizedGrade` for normalization and groups by `Category`. After
extraction, update `Edit-Grade.ps1` and `Invoke-LocalEvaluation.ps1` to use
it. Add unit tests covering: single category, multi-category, override counts,
zero-max category (0 tests available).

### 3.2 Review item loaders

Create `Sage/Private/Get-ReviewRun.ps1`:

```text
function Get-ReviewRun
  -RunRoot  [string]   # path to exam output root (multi-student) or student folder
  -Student  [string]   # optional: filter to one student name/email
  Output:   [PSCustomObject[]] each with:
    StudentName    [string]
    StudentEmail   [string]
    ResultsPath    [string]   # absolute path to results.json
    OriginalPath   [string]   # absolute path to results-original.json (may be null)
    CollectorDir   [string]   # absolute path to collector-data/ folder
    Summary        [PSCustomObject]   # loaded Sage.StudentGradeSummary
```

Discovery logic:

1. If `RunRoot` contains `results.json` directly → single-student mode.
2. Otherwise enumerate immediate subdirectories; for each that contains
   `results.json`, load it as a student result.
3. Sort by `StudentName`.

This replaces the recursive-search behavior in
`Sage/tui/Private/Import-ResultSummary.ps1` for instructor use (leave that
function unchanged for student self-check compatibility).

---

## 4. Per-Student Excel Export

### 4.1 results-original.xlsx

Written once by `Export-GradeSummary.ps1` when `'Excel'` is in `-Format` and
`results-original.xlsx` does not yet exist. Uses `AwardedGrade` for all grade
cells. Never modified after initial write. Uses plain (non-italic) formatting
everywhere.

Structure (one sheet "Results"):

- Header row: Category, Target, Context, TestName, PassGrade, AwardedGrade, Passed
- One data row per `TestResult`, sorted by Category → TestName.
- Second sheet "Summary": CategoryScores + TotalScore.

### 4.2 results-reviewed.xlsx

Written whenever grades are saved (by review workflow or `Export-GradeSummary`
after an override). Starts from `AwardedGrade` baseline. Cells where
`FinalGrade != AwardedGrade` are rendered in **italic**. When `ReviewerNote`
is set, include it in a "Note" column.

Structure: same as original, plus columns: FinalGrade, ManualOverrideGrade,
ManualOverrideReason, ReviewerNote.

Use `Set-ExcelRange -Italic` via `ImportExcel` to apply italic formatting to
individual cells (not entire rows).

---

## 5. Aggregate Exam Grade Book

### 5.1 New public function: Export-ExamGradeBook

**`Sage/Public/Export-ExamGradeBook.ps1`**

```text
function Export-ExamGradeBook
  -Summaries        [PSCustomObject[]]   # array of Sage.StudentGradeSummary
  -ExamName         [string]
  -OutputPath       [string]             # folder to write into
  -FileName         [string]             # optional override for filename
  -Mode             [string]             # 'Original' | 'Reviewed' (default 'Reviewed')
  -MergeStrategy    [string]             # 'Replace' | 'New' | 'Merge' (default 'Merge')
  -SupportsShouldProcess
  Output:           [string]             # written file path
```

When `-Mode Original`: uses `AwardedGrade` for all cells, no italic,
no reviewer columns. Filename: `{ExamName}-grades-original.xlsx`.

When `-Mode Reviewed`: uses `FinalGrade`, italic for changed cells,
includes ManualOverrideReason and ReviewerNote columns.
Filename: `{ExamName}-grades-reviewed.xlsx`.

### 5.2 Aggregate Excel structure

#### Sheet 1 — "Grades"

Column layout (left to right):

1. `StudentName`
2. `StudentEmail`
3. For each category (in exam definition order):
   - Merged header cell spanning all test columns for that category
     (colored background using `ImportExcel` `Set-ExcelRange`)
   - One column per test: header = truncated TestName (max 40 chars),
     value = grade for that test
   - A "Category /20" summary column using NormalizedScore
4. Final summary: `Total Raw`, `Total Max`, `Total /20`

#### Sheet 2 — "Summary"

One row per category, columns: Category, TargetName, RawScore, MaxScore,
NormalizedScore, PassedCount, FailedCount.

#### Sheet 3 — "Graphs"

1. Bar chart: X = students, Y = Total /20 score. Color threshold lines at
   10 and 14 if possible.
2. Clustered bar chart: X = categories, Y = NormalizedScore, grouped
   by student (or use a category pass-rate view if too many students).

Use `Add-ExcelChart` from `ImportExcel`. Keep charts on a dedicated
worksheet named "Graphs" via `New-ExcelChartDefinition` or
`Export-Excel -WorksheetName`.

**Merge strategy:**

`Replace`: delete and recreate file.

`New`: create `{ExamName}-grades-reviewed-2.xlsx` (increment suffix until
filename is available).

`Merge` (default):

1. Open existing file, read existing rows (keyed by StudentEmail).
2. For students present in both: update grade/override cells; apply italic
   where needed; do not change cells for tests not in the new summaries.
3. For new students: append rows.
4. Recalculate total columns.
5. Preserve any manually added rows/annotations not from SAGE data.

### 5.3 Path configuration

Add optional `AggregateExcelPath` property to the `Export` section of
`exam.psd1` (document in schema comments). Add optional `-AggregateExcelPath`
parameter to `Invoke-Evaluation.ps1` and `Invoke-StudentEvaluation.ps1`
(pass-through only; `Invoke-StudentEvaluation` writes individual student
files; `Invoke-Evaluation` assembles and calls `Export-ExamGradeBook` at the
end of the run).

When neither the parameter nor the `exam.psd1` property is set, default the
aggregate output path to the exam output root.

**Merge prompt:** When called interactively (no automation flag) and an
existing aggregate file is found, prompt:

```text
Aggregate grade book found: {path}
  [M] Merge — add/update students (default)
  [R] Replace — overwrite entire file
  [N] New file — create {name}-2.xlsx
Choice [M]:
```

When called non-interactively (e.g. from a script or CI), default to Merge
without prompting. Pass `-MergeStrategy` to override.

---

## 6. Instructor Review TUI

### 6.1 Entry point

**`Sage/Public/Invoke-InstructorReview.ps1`** (new public function)

```text
function Invoke-InstructorReview
  -RunRoot      [string]   # exam output root or single-student folder
  -StudentEmail [string]   # optional: open a specific student directly
  -Filter       [string]   # 'All' | 'Failed' | 'Overridden' (default: last used)
  -TuiPath      [string]   # optional override of review tui/ directory
  Output:       [void]
```

Dot-sources review TUI helpers from `Sage/tui/review/Private/*.ps1` at
runtime (same pattern as `Invoke-SelfCheck` dot-sources from `Sage/tui/Private/`).

Store last-used filter in `Sage/data/config/review-config-personal.psd1`
(same pattern as `tui-config-personal.psd1`).

Add to `Sage.psd1` and `Sage.psm1` exports. Add root-level launcher
`Start-InstructorReview.ps1` (same pattern as `Start-SelfCheck.ps1`).

### 6.2 Review TUI file layout

```text
Sage/tui/review/
  Private/
    Get-ReviewRun.ps1               # (symlink/copy) or loaded from Sage/Private/
    Show-ReviewMainMenu.ps1         # entry: choose single student or guided queue
    Show-StudentSelector.ps1        # multi-student list, filter/search
    Show-ReviewSummary.ps1          # student summary — reuse patterns from Show-ResultsSummary.ps1
    Show-ReviewCategoryDetail.ps1   # category drill-down — reuse Show-CategoryDetail.ps1 patterns
    Show-ReviewTestEdit.ps1         # test detail + inline edit form (NEW)
    Show-GuidedReviewQueue.ps1      # workflow B: cross-student review queue (NEW)
    Save-ReviewResult.ps1           # write overrides to results.json, recompute, save
    Initialize-ReviewConfig.ps1     # load/create review-config-personal.psd1
```

### 6.3 Workflow A: Free browse and edit

Navigation flow:

```text
Invoke-InstructorReview
  └─ Show-ReviewMainMenu → "Browse a student"
       └─ Show-StudentSelector (list all students in run)
            └─ Show-ReviewSummary (category table, reuse split-pane pattern)
                 └─ Show-ReviewCategoryDetail (test list, add 'E' = edit shortcut)
                      └─ Show-ReviewTestEdit
                           left panel: test detail (TestName, Status, Points, Expected, Actual, Error)
                           right panel: collector data (reuse ConvertFrom-CollectorMarkdown)
                           bottom panel: edit form (score field, reason field, note field)
                           keys: Tab = move between fields, Enter = save, R = reset to automatic, Esc = cancel
                      back → category detail (cursor stays on last edited test)
                 back → summary (unsaved-change indicator on category row if any edits pending)
            back → student selector
```

**Edit form layout (bottom panel):**

```text
  ────────────────────────────────────────────────────
  [Score  ]  current: 0.0  max: 2.0  auto: 0.0
  [Reason ]  __________________________________________
  [Note   ]  __________________________________________
  Enter: save  R: reset  Esc: cancel  Tab: next field
```

Score field accepts any double in range `[0, PassGrade]`. Empty = no override
(keeps current FinalGrade). Validation inline with red color on out-of-range.

On save: call `Save-ReviewResult` which:

1. Applies `ManualOverrideGrade`, `ManualOverrideReason`, `ReviewerNote` to
   the in-memory TestResult.
2. Calls `Invoke-GradeRecalculation` to recompute CategoryScores and TotalScore.
3. Writes back to `results.json` via `ConvertTo-Json -Depth 15 | Set-Content`.
4. Logs via `Write-Log`.
5. Triggers regeneration of `results-reviewed.xlsx` for that student.

### 6.4 Workflow B: Guided review queue

```text
Invoke-InstructorReview
  └─ Show-ReviewMainMenu → "Guided review queue"
       └─ Show-GuidedReviewQueue
```

**Queue build:** flatten all students × all tests into a flat list.
Filter by last-used filter (default: `Failed`; remembered in
`review-config-personal.psd1`). Sort by: StudentName → Category → TestName.

**Queue navigation:**

```text
  Student 3 of 8 — Daan Banaan
  Test 12 of 47 — DNS > PTR Records > PTR 3 resolves to dc1.sage.local

  left panel:               right panel:
  [test detail]             [collector data / ReviewData]

  bottom panel: edit form (same as workflow A)

  ←/→ : prev/next student   ↑/↓: prev/next test in queue
  F   : toggle filter        S: save and next   R: reset   Esc: skip
  Q   : quit                 /: search queue
```

Unsaved changes indicator: show `*` in the student name header row.
Auto-save on student navigation (`S`); prompt on `Q` if unsaved changes exist.

**Filter options** (toggled with `F`):

- `Failed` — all non-passed tests
- `Overridden` — tests with ManualOverrideGrade set (review existing overrides)
- `All` — every test

Last-used filter is persisted to `review-config-personal.psd1` on change.

**Queue progress display:**

```text
  ████████████░░░░░░░░  12/47 tests  (3/8 students complete)
```

---

## 7. Wiring Into Invoke-Evaluation

After the parallel/sequential processing loop completes in
`Invoke-Evaluation.ps1`, add a step:

```powershell
# ── Export aggregate grade book ────────────────────────────────────────────
$AllSummaries = # collect from results
$GradeBookParams = @{
    Summaries      = $AllSummaries
    ExamName       = $Exam.Name
    OutputPath     = $ExamOutputDir
    Mode           = 'Original'
    MergeStrategy  = 'Merge'
}
Export-ExamGradeBook @GradeBookParams   # writes {ExamName}-grades-original.xlsx

$GradeBookParams['Mode'] = 'Reviewed'
Export-ExamGradeBook @GradeBookParams   # writes {ExamName}-grades-reviewed.xlsx
```

When `-AggregateExcelPath` is supplied to `Invoke-Evaluation`, override the
`OutputPath` in the splat above. When running non-interactively (e.g. CI),
default to `Merge` silently. When running interactively and an existing file
is found, prompt as described in §5.3.

Reviewed aggregate is also regenerated whenever `Save-ReviewResult` saves a
student. Pass the RunRoot to find all student summaries and update in place.

---

## 8. Test Plan (TDD — implement tests before code)

Write tests in `tests/Unit/` before implementing the corresponding function.
Run all tests with `tools/Run-Tests.ps1` (never run `Invoke-Pester` directly).

| Test file | Covers |
|-----------|--------|
| `New-GradeResult.Tests.ps1` (update) | ReviewerNote field presence, null default |
| `Export-GradeSummary.Tests.ps1` (update) | ReviewData serialized; results-original.json idempotency |
| `Invoke-GradeRecalculation.Tests.ps1` (new) | Single/multi-category; override counting; zero-max; normalization |
| `Get-ReviewRun.Tests.ps1` (new) | Single-student path; multi-student enumeration; sort order; missing original |
| `Get-ReviewItemKey.Tests.ps1` (new) | Key uniqueness across students, targets, categories, contexts, tests |
| `Save-ReviewResult.Tests.ps1` (new) | Override applies; recomputation correct; JSON written; original unchanged |
| `Export-ExamGradeBook.Tests.ps1` (new) | Column structure; italic on overrides; merge adds rows; merge updates cells; Replace recreates; New increments filename; ShouldProcess |
| `Edit-Grade.Tests.ps1` (update) | Non-interactive uses stable compound key; ReviewerNote applied |

---

## 9. Scope Boundaries

**Included:**

- `Sage/Private/New-GradeResult.ps1` — add ReviewerNote field
- `Sage/Public/Export-GradeSummary.ps1` — persist ReviewData and ReviewerNote; write results-original.json
- `Sage/Private/Invoke-GradeRecalculation.ps1` — new private helper (extracted from Edit-Grade)
- `Sage/Private/Get-ReviewRun.ps1` — new instructor-only result loader
- `Sage/Private/Get-ReviewItemKey.ps1` — new stable identity helper
- `Sage/Public/Edit-Grade.ps1` — use stable key in non-interactive mode; apply ReviewerNote
- `Sage/Public/Export-ExamGradeBook.ps1` — new public function
- `Sage/Public/Invoke-Evaluation.ps1` — wire aggregate export, path parameter
- `Sage/Public/Invoke-InstructorReview.ps1` — new TUI entry point
- `Sage/tui/review/Private/*.ps1` — new instructor review TUI screens
- `Start-InstructorReview.ps1` — root launcher
- All corresponding unit tests

**Excluded (do not touch):**

- `legacy/` — entirely excluded, as always
- `Sage/tui/Private/` — all existing student self-check TUI files stay unchanged
- `Sage/Public/Invoke-SelfCheck.ps1` — no changes
- `Sage/Collectors/` — no changes
- `Sage/Evaluators/` — no changes (ReviewContextMap already works correctly)

---

## 10. Known Risks and Blockers

| Risk | Mitigation |
|------|------------|
| `ImportExcel` not installed | Guard with `Get-Command 'Export-Excel'`; emit warning and skip Excel output; never throw |
| `ImportExcel` italic-cell API changes between versions | Use `Set-ExcelRange -Italic` on cell address; document minimum module version |
| Merge behavior on large student files can be slow | Merge by loading entire worksheet into memory as a hashtable keyed by row index, then update atomically |
| Parallel writes to aggregate Excel from parallel eval | Aggregate export runs *after* all parallel students complete — never during parallel phase |
| JSON Depth truncates nested ReviewData | Use `-Depth 15` minimum in all `ConvertTo-Json` calls in this flow |
| `results-original.json` already exists from a re-run | Check existence before write; never overwrite (already specified) |
| Review queue loses progress on crash | Queue state is in-memory only; each save call writes to disk immediately so partial progress is preserved |
