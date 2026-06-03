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

### Phase 1 — Data model prerequisites

Implement only the items listed below. Do NOT touch anything outside this scope.
Stop and ask if you encounter a dependency that is not covered here.

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
