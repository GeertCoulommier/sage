# Contributing to SAGE

Thank you for your interest in contributing to SAGE — the Stack Assessment and Grading Engine.

## Getting Started

### Prerequisites

| Tool | Minimum version |
|------|-----------------|
| PowerShell | 7.5 |
| Pester | 5.6.0 |
| PSScriptAnalyzer | 1.21.0 |

### Setup

```powershell
# 1. Fork and clone the repository
git clone https://github.com/<your-fork>/sage.git
cd sage

# 2. Install required modules
Install-Module Pester            -MinimumVersion 5.6.0 -Scope CurrentUser -Force
Install-Module PSScriptAnalyzer  -MinimumVersion 1.21.0 -Scope CurrentUser -Force
Install-Module ImportExcel       -MinimumVersion 7.8.0  -Scope CurrentUser -Force

# 3. Install the pre-commit hook
cp .github/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Workflow

SAGE uses [GitHub Flow](https://docs.github.com/en/get-started/quickstart/github-flow):

1. Create a branch from `main` using the naming convention below
2. Make your changes with micro-commits (one logical change per commit)
3. Ensure tests and lint pass locally before pushing
4. Open a pull request against `main`

### Branch Naming

| Prefix | Use for |
|--------|---------|
| `feat/` | New features |
| `fix/` | Bug fixes |
| `refactor/` | Code restructuring without behaviour change |
| `docs/` | Documentation-only changes |
| `test/` | Test additions or fixes |

**Example:** `feat/add-nginx-collector`

## Coding Standards

All contributions must follow the rules in [CLAUDE.md](CLAUDE.md):

- Strict, idiomatic PowerShell with `[CmdletBinding()]`
- No backticks — use splatting or natural line breaks
- `PascalCase` for all names except loop variables (`$i`, `$_`)
- Comment-Based Help on every function (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.OUTPUTS`, `.EXAMPLE`)
- Strongly typed parameters

## Running Tests

Always use the safe runner — **never** call `Invoke-Pester` directly in the
PowerShell integrated console, as it can crash the VS Code extension host.

```powershell
# All unit tests
./tools/Run-Tests.ps1

# Full Pester output
./tools/Run-Tests.ps1 -Detailed

# Specific test file
./tools/Run-Tests.ps1 -Filter 'Write-Log'
```

## Running the Linter

```powershell
./tools/Run-PowerShellLint.ps1
```

Zero PSScriptAnalyzer warnings are required before a PR can be merged.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat: add Nginx collector for virtual host detection
fix: resolve scope name case-sensitivity in FileServer evaluator
refactor: extract shared SSH helper into private function
docs: add DHCP scope option reference to ARCHITECTURE.md
test: add unit tests for Get-ConnectionFallback
```

## Adding a New Collector / Evaluator

1. Copy `.templates/collector.ps1.template` to `Sage/Collectors/Invoke-<Name>Collector.ps1`
2. Create `Sage/Evaluators/<Name>.Tests.ps1` following the existing evaluator pattern
3. Add unit tests to `tests/Unit/Invoke-<Name>Collector.Tests.ps1`
4. Register the collector in a werkcollege or exam `.psd1` definition

## Pull Request Checklist

- [ ] Branch created from latest `main`
- [ ] All unit tests pass (`./tools/Run-Tests.ps1`)
- [ ] Linter passes with zero warnings (`./tools/Run-PowerShellLint.ps1`)
- [ ] All `.md` files pass markdownlint with zero errors
- [ ] `CHANGELOG.md` updated with a timestamped entry
- [ ] Commits are micro-commits (one logical change each)
- [ ] No secrets, credentials, or exam content included

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).
By participating you agree to abide by its terms.
