# PowerShell Module — Development Rules

## Architecture & Constraints

- **Structure:** `Sage.psd1` (manifest) + `Sage.psm1` (loader). Export only via `Export-ModuleMember`.
- **Layout:** `Public/` (exports), `Private/` (internal), `Tests/` (Pester 5).
- **Legacy scope:** NEVER change anything in `legacy/` (legacy code area) and always ignore this folder completely when asked to refactor all code.
- **Output:** Functions must return objects only. NEVER emit formatted output.
- **Logging:** Use `Write-Verbose`/`Write-Debug`/`Write-Information`. Keep `Write-Host` strictly for UX banners.
- **Errors:** Fail fast (`$ErrorActionPreference = 'Stop'`). Use `$PSCmdlet.ThrowTerminatingError()` for fatal errors.
- **Portability:** `#Requires -Version 7.5`. Avoid hard-coded paths; use `$PSScriptRoot`. No secrets in plain text.
- **Templates:** See the `.templates/` folder for boilerplate code (`Sage.psm1`, Pester tests, and ScriptAnalyzer config).
- **Public API stability:** Do not change exported function names or mandatory parameters.

## Coding Style

- Write strict, idiomatic PowerShell: Use `[CmdletBinding()]`: no aliases, strongly typed, advanced functions only.
- **Comment-Based Help (CBH):** Place CBH immediately before the `function` keyword with no more than one blank line between them. Use standard `.KEYWORD` syntax (dot adjacent, no space). All functions require `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.OUTPUT`, and at least one `.EXAMPLE`.
- Use splatting when using more than 3 parameters in a function or cmdlet call.
- Hashtable formatting: use one key-value pair per line in literals for readability (including nested hashtables).
- Param block formatting: use one inline declaration per parameter in this shape: `[Parameter(...)][Validator(...)] <aligned spaces> [type] $Name`, where `[type]` is always directly adjacent to `$Name` with exactly one space between them. Align `$` across all entries in the block (target column 100, as in `New-RemoteSessionObject`). The alignment padding goes **before** `[type]`, not between `[type]` and `$Name`.
- Param alignment fallback: if a declaration is too long to keep `$Name` at column 100, split the declaration across multiple lines (for example, put validators on separate attribute lines), keeping `[type] $Name` on the last line. All parameter names in the block must still share the same column.
- Never EVER use backticks (`). Use splatting or natural line breaks instead.
- Use `PascalCase` for all function, variable and type names, except for one-letter variables in loops (`$i`, `$j`, etc.) and common pipeline variables (`$_`).
- Prefer expandable strings (`"Hello $Name"`) over string concatenation or the `-f` format operator.
- Prefer `switch` over long `if/elseif/else` chains.
- For large-dataset loops, prefer `foreach ($Item in $Collection)` over `ForEach-Object` in pipelines, except doing multi-threaded operations with the `-Parallel` parameter.

## Function Naming

- Names describe purpose, not implementation.
- **Avoid:** `*-Eval*` terminology (legacy from "ServerOS - EVAL")
- **Remote session functions:** Use `New-RemoteSession`, `Close-RemoteSession`
- **Credentials:** Use `Set-Credential`, `Import-Credential`
- **Diagnostics:** Use `Invoke-Diagnostic`
- **Data retrieval:** Use `Get-*Summary` or `Invoke-*` depending on complexity:
  - Simple aggregation: `Get-GradeSummary`
  - Complex calculation: `Invoke-Grading`
- **Logging:** Use `Write-Log`, `Write-Diagnostic`

## Type Naming (PSTypeName)

All custom objects use `Sage.<Purpose>` prefix:

```powershell
Sage.RemoteSession        # Wraps PSSession with metadata (TargetName, HostName, Port, etc.)
Sage.TestResult           # Individual test outcome: pass/fail, grades, actual vs. expected
Sage.CollectorResult      # Data from remote collector: available status, structured data, errors
Sage.CategoryGradeSummary # Aggregated grades per exam category: raw/max/normalized scores
Sage.StudentGradeSummary  # Final student grade: total score, overrides, timestamp
```

## Result Type Hierarchy (Data Flow)

```powershell
Collector          → CollectorResult (raw data from remote system)
         ↓
Pester Tests  → TestResult (per-test outcome: pass/fail, actual/expected)
         ↓
Grading Engine → CategoryGradeSummary (per-category: raw/max/normalized)
         ↓
Export Engine  → StudentGradeSummary (final: total score, metadata)
```

Use this hierarchy consistently when implementing Get/Export functions.

## Git & Workflow

- **Repository:** All development happens in `sage-private`. The public `sage` repo is a read-only mirror auto-synced via `sync-public.yml` on every push to `main`. NEVER commit or push to `sage` directly.
- Use Github Flow; use prefix names for branches; keep `main` deployable.
- **Quick hook mode:** After verifying tests and/or lint pass, set `$env:SAGE_QUICK_HOOK = '1'` before committing. This skips the heavy pre-commit checks (lint, markdown lint, unit tests) that CI enforces on push anyway. Security checks (path guard, secret scan, manifest) always run.
- **Always use micro-commits:** one commit per functional change. Never bundle multiple unrelated changes into a single commit. Each commit must be independently understandable, revertable, and contain exactly one logical unit of work.
- Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, etc.).
- Update CHANGELOG.md with every commit, including a timestamp. Update the version number with major/minor/patch tags as appropriate.

## Documentation Quality

- After every change to any `.md` file, check the errorstool in vscode for markdownlint errors and resolve before finishing. Zero lint errors is required.

## AI Collaboration Heuristics

- **Major Refactors:** First produce a numbered plan with affected files, risks, and tests. Wait for approval.
- **TDD:** ALWAYS: Add/update Pester tests if needed -> implement -> ALWAYS rerun tests until green.
- **Running Pester tests:** ALWAYS use `tools/Run-Tests.ps1` — it runs Pester in an **out-of-process child `pwsh`** to prevent VS Code extension host crashes. Use `-Detailed` to see full Pester output. Use `-Filter` to run a subset. NEVER invoke `Invoke-Pester` directly in the PSIC (PowerShell Integrated Console) — this is the primary cause of VS Code crashes. The VS Code task "Run Tests (safe)" is also available from the command palette.
- **Context Resets:** For long sessions were the context window is at 50% or higher, write a `HANDOFF.md` summary so we can start fresh.
- **One task per conversation:** Complete one logical task per conversation (e.g. "fix tests", "run E2E", "implement feature X"). If multiple sequential tasks are requested, suggest splitting after each milestone.
- **Terminal output discipline:** Never run commands that produce unbounded output. Pipe through `Select-Object -First`, `head`, or redirect to a file. For E2E runs, check log files instead of capturing verbose output. Use `Get-Process` or log tailing for long-running processes.
