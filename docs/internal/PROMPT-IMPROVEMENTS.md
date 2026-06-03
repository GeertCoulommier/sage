# Improvements to Performance Phase 2 Prompt

## Summary of Enhancements

The original prompt has been improved with better structure, clearer acceptance criteria, and explicit guidance for complex multi-file refactoring work. The new version is saved as:

**[.github/prompts/performance-phase2-improved.prompt.md](.github/prompts/performance-phase2-improved.prompt.md)**

---

## Key Improvements

### 1. **Frontmatter & Metadata**

- Added YAML frontmatter with clear `description`, `name`, and `agent` declaration
- Makes the prompt discoverable in VS Code chat (`/` commands)
- Frontmatter includes context level ("complex multi-file, multi-stage refactor")

### 2. **Mandatory Reading Order**

- Explicit sequence: CLAUDE.md → ARCHITECTURE.md → PERFORMANCE-PLAN.md → PERFORMANCE-RESULTS.md → This prompt
- Prevents implementation starting before full context is understood
- Each reference has a clear purpose statement

### 3. **Git Identity Setup (Early)**

- Moved to top of workflow section with explicit verification commands
- Prevents commits under wrong identity (Copilot vs. Geert Coulommier)
- Includes amendment instruction if identity is wrong

### 4. **Terminal Discipline**

- Dedicated section with specific guidelines:
  - No unbounded output (pipe through `Select-Object -First 50`)
  - Tail logs instead of waiting on processes
  - Capture output before commits for verification
- Prevents context window overflow

### 5. **Workflow Discipline (Explicit)**

- **Testing Gate (TDD):** Write test → fail → implement → pass (with specific tool commands)
- **Linting Gate:** Run lint → fix ALL violations before commit (markdown + PowerShell)
- **Micro-Commits:** One change per commit, with Conventional Commits format
- **Code Quality Standards:** All CLAUDE.md rules in one section (no backticks, PascalCase, alignment, CBH, etc.)

### 6. **Step 0 Greatly Expanded**

- **New:** Step 0 is now "Verification" not just "Prerequisite"
- **Detailed:** Full file change matrix showing what needs modification
- **Thread-through:** Explains the full path: exam .psd1 → Import-ExamDefinition → Invoke-Evaluation → Invoke-StudentEvaluation → Close-RemoteSession
- **TUI support:** Adds Show-SelfCheckSettings modification so students can enable/disable via checkbox
- **Acceptance criteria:** 9 explicit checkboxes covering config, threading, tests, live testing, linting, commit message
- **Live test requirement:** Must verify on Linux target (`:20022`) that files persist when enabled

### 7. **File Change Matrices Per Step**

- Each step has a **markdown table** showing:
  - Which files change
  - What the change is
  - Priority order (helps with parallelization)
- Eliminates ambiguity about scope

### 8. **Clear Acceptance Criteria (Checklists)**

- Each step has 5-15 specific checkboxes
- All criteria are **measurable** and **verifiable**
- Format: `[ ] Specific testable condition`
- Prevents "done-ness" ambiguity

### 9. **Implementation Point Specificity**

- Step 1 (P2): Shows exact code for `ConcurrentBag`, module path resolution, error handling
- Step 2 (P1): Shows pseudo-code for building target groups, explains what stays sequential vs. parallel
- Step 3 (P7): Shows exact JSON transformation syntax for all 11 collectors
- Each step links to reference variant file for comparison

### 10. **Risk Analysis**

- Step 2 includes explicit risk sections:
  - "PSSession thread-safety" with mitigation
  - "Timeout checking across parallel branches" with mitigation
- Helps anticipate potential issues

### 11. **Context Budget Tracking**

- Explicit estimation: "25–35 tool calls total across 3 steps"
- Threshold: 60% context → write HANDOFF.md and suggest fresh conversation
- Prevents unexpected context resets mid-task

### 12. **Benchmarking Guidance**

- Includes optional command to run live performance benchmark
- Shows expected savings per step
- Explains why results matter (25–30s combined = 25–28% improvement)

### 13. **Commit Checklist**

- Pre-commit verification: tests, lint, markdown, CHANGELOG, git identity, message format, quick-hook mode
- Forces discipline before each push

### 14. **Quick Reference Table**

- "File Change Matrix (Quick Reference)" at bottom
- Shows which files are touched in each step
- Helps visualize scope and dependencies

### 15. **Troubleshooting Section**

- Q&A covering common issues:
  - Mock Invoke-Command JSON format
  - Lint errors after edits
  - Write-Log in parallel runspaces
  - Timeout handling
- Saves time on debugging

### 16. **Scope Boundaries Removed**

- Original prompt didn't clarify boundaries; new one implicitly respects them:
  - No modifications to `legacy/` folder
  - No changes to student TUI (Invoke-SelfCheck.ps1)
  - Only public function signatures that already exist get new parameters

---

## How to Use the Improved Prompt

1. **In VS Code chat:** Type `/` and search for "Performance Phase 2" → select the improved version
2. **Direct file reference:** Open the file in editor → click ▶ (play button) to invoke as prompt
3. **Copy into conversation:** Paste the content directly into chat if you prefer

---

## What Changed vs. Original

| Aspect | Original | Improved |
|--------|----------|----------|
| Frontmatter | None | YAML metadata + description |
| Reading order | Implied | Explicit 5-file sequence |
| Git setup | Missing | Early section with verification |
| Terminal discipline | 1 line | Dedicated section + examples |
| Workflow discipline | Scattered | Consolidated under 4 subsections |
| Step 0 scope | 1 small section | Full verification workflow (9 files involved) |
| File matrices | Per-step, text | Per-step, markdown tables + summary |
| Acceptance criteria | Prose | Checklist format (measurable) |
| Risk analysis | None | Explicit risk + mitigation per step |
| Context budgeting | None | Explicit threshold + HANDOFF guidance |
| Troubleshooting | None | 4 common issues + solutions |
| Commit checklist | Missing | 8-point pre-commit gate |
| Reference table | None | Quick matrix at bottom |

---

## Why These Improvements Matter for Complex Work

1. **Prevents context loss:** Explicit budget tracking + HANDOFF template prevents mid-task resets
2. **Forces discipline:** Checklists + gates ensure quality before committing
3. **Reduces ambiguity:** Tables + matrices show exactly what files/lines are affected
4. **Enables parallelization:** Priority columns in file matrices help split work
5. **Catches errors early:** TDD + lint gates catch bugs before they accumulate
6. **Maintains overview:** Risk analysis + troubleshooting keep the big picture visible
7. **Scales to team:** Clear standards (CLAUDE.md + ARCHITECTURE.md) mean others can pick up where you left off

---

## Next Steps

1. Open the new prompt: [.github/prompts/performance-phase2-improved.prompt.md](.github/prompts/performance-phase2-improved.prompt.md)
2. Review the "Mandatory Reading" section — start there
3. Run through Step 0 verification first (most of the Step 0 changes are already done)
4. Follow the TDD discipline: write test → fail → implement → green
5. Commit micro-commits (one per logical change) with `SAGE_QUICK_HOOK=1`
6. If context approaches 60%, pause and write HANDOFF.md for the next session

---

## Questions?

- All CLAUDE.md coding rules are consolidated in the "Code Quality Standards" subsection
- All performance rationale is in PERFORMANCE-PLAN.md and PERFORMANCE-RESULTS.md
- Reference variant implementations are in `Sage/Private/Benchmarks/`
- Terminal discipline is covered to prevent context overflow
- Acceptance criteria are measurable — check them off as you go

Good luck with the Phase 2 implementation! 🚀
