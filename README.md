# SAGE

## Stack Assessment and Grading Engine

PowerShell 7.5 module for automated evaluation and grading of VM configurations via SSH.
Modular, data-driven architecture using **Pester 5.6+** for evaluation.

SAGE supports two workflows:

- **Student Self-Check (TUI)** — Interactive terminal UI for students to evaluate their own VMs
- **Instructor Automation** — Batch grading via CSV roster for automated exam assessment

---

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Student Self-Check (TUI)](#student-self-check-tui)
- [Instructor Automation](#instructor-automation)
- [Architecture](#architecture)
- [Module Structure](#module-structure)
- [Exam Definition](#exam-definition)
- [Contributing](#contributing)

---

## Quick Start

Choose your workflow:

### For Students: Run the Self-Check TUI

```powershell
pwsh ./Start-SelfCheck.ps1
```

The TUI will guide you through:

- Selecting your targets (DC1, Linux, etc.)
- Choosing evaluation categories
- Viewing results with drill-down test details
- Comparing runs over time

### For Instructors: Batch Grade Submissions

```powershell
Import-Module ./Sage/Sage.psd1

$params = @{
    ExamPath   = './Sage/data/exams/myexam/exam.psd1'
    RosterPath = './rosters/students.csv'
}
Invoke-Evaluation @params
```

---

## Installation

### Prerequisites

| Dependency                             | Minimum version |
|----------------------------------------|-----------------|
| Git                                    | 2.40            |
| PowerShell                             | 7.5             |
| Pester                                 | 5.6.0           |
| ImportExcel                            | 7.8.0           |

Remote VMs require **OpenSSH** configured on the port specified in `exam.psd1`.

### 1. Install Git

Choose your platform:

**Windows (using Chocolatey or winget):**

```powershell
# Chocolatey
choco install git -y

# Or: Windows Package Manager
winget install Git.Git -e
```

**macOS (using Homebrew):**

```bash
brew install git
```

**Linux (Ubuntu/Debian):**

```bash
sudo apt-get update && sudo apt-get install -y git
```

**Linux (RHEL/CentOS/Fedora):**

```bash
sudo yum install -y git
```

### 2. Clone the Repository

```powershell
git clone https://github.com/GeertCoulommier/sage.git
cd sage
```

### 3. Install PowerShell Modules

```powershell
# Core modules (required for both student and instructor workflows)
Install-Module Pester                 -MinimumVersion 5.6.0 -Scope CurrentUser -Force
Install-Module ImportExcel            -MinimumVersion 7.8.0 -Scope CurrentUser -Force
Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser -Force

# Optional: For rich TUI rendering (students only)
Install-Module PwshSpectreConsole -Scope CurrentUser -Force
```

For the full TUI experience:

Use a modern terminal instead of the old console host.

Install a NerdFont, a font with additional visual characters: <https://www.nerdfonts.com/>

Enable full unicode by adding the following as the FIRST LINE in your $PROFILE file:

```powershell
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
```

### 4. Import the Module

```powershell
Import-Module ./Sage/Sage.psd1
```

---

## Student Self-Check (TUI)

Launch the interactive self-check:

```powershell
pwsh ./Start-SelfCheck.ps1
```

### Setup (First Time)

#### SSH Key Installation (Optional)

```powershell
pwsh ./tools/Install-SshKeys.ps1
```

This installs the pre-provisioned SSH key onto your VMs for passwordless authentication.

#### Connectivity Test

- The TUI tests connectivity to each target (LAN IP first, then public hostname)
- If LAN is unreachable, you'll be prompted for a public hostname

#### Configure Credentials (if SSH key setup fails)

- The TUI will prompt for your password when needed

### TUI Screens

| Screen | Description |
|--------|-------------|
| **Main Menu** | Start an evaluation, view previous runs, open settings, or quit |
| **Target Selector** | Choose which VMs to test (e.g., DC1, Linux) |
| **Category Selector** | Pick which exam categories to evaluate |
| **Results Summary** | Pass/fail overview per category with score |
| **Test Detail** | Drill into individual test results with actual vs expected values |
| **Previous Runs** | Compare the current run against earlier results |
| **Settings** | Change domain name, output directory, or theme |

### Troubleshooting

| Issue | Solution |
|-------|----------|
| **SSH connection refused** | Verify VMs are running. Try public hostname fallback when prompted. |
| **Permission denied (SSH)** | Run `pwsh ./tools/Install-SshKeys.ps1` to install the public key. |
| **PwshSpectreConsole not found** | Optional — TUI runs in plain text. For rich UI: `Install-Module PwshSpectreConsole -Scope CurrentUser` |
| **No SSH client available** | Install OpenSSH: Windows Store, Homebrew (macOS), or package manager (Linux). |

---

## Instructor Automation

### 1. Store Credentials (One-Time Setup)

```powershell
# Register a local vault
Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser
Register-SecretVault -Name SageVault -ModuleName Microsoft.PowerShell.SecretStore

# Store exam credentials
Set-Credential -Name 'WinAdminPassword'
Set-Credential -Name 'LinuxStudentPassword'
```

### 2. Create Your Exam Definition

```powershell
# Copy the example exam
Copy-Item ./Sage/data/exams/_example/exam.psd1 `
          ./Sage/data/exams/myexam-2025/exam.psd1

# Edit to fill in:
#   - Targets (SSH connection profiles)
#   - Roster (CSV field mapping)
#   - Categories (what to test)
#   - Variables (test parameters)

# Validate your exam definition
Test-ExamDefinition -Path ./Sage/data/exams/myexam-2025/exam.psd1
```

### 3. Run Evaluation

```powershell
Import-Module ./Sage/Sage.psd1

$params = @{
    ExamPath          = './Sage/data/exams/myexam-2025/exam.psd1'
    RosterPath        = './rosters/students.csv'
    OutputDir         = './results'
    KeyFilePath       = "$env:HOME/.ssh/id_rsa"
    SaveCollectorData = $true         # Debug: keep raw collector output
    ThrottleLimit     = 4             # Run 4 students in parallel
}
Invoke-Evaluation @params
```

### 4. Review Results

```powershell
# Results include:
#   - results/<ExamName>/<StudentName>/results.json
#   - results/<ExamName>/<StudentName>/results.xlsx

# Manually override grades for edge cases
Edit-Grade -ResultsPath ./results/myexam-2025/StudentName/results.json
```

---

## Architecture

**Pipeline:**  
`Load exam definition → per student in roster → SSH to targets → run collectors → run Pester tests → grade → export JSON/Excel`

**Key design points:**

- **Data-driven:** Test parameters live in exam.psd1, not hardcoded
- **Modular:** Separate collector and evaluator for each service (DNS, DHCP, GPO, etc.)
- **Parallel:** Supports batch grading of multiple students simultaneously
- **Extensible:** Add new evaluation categories without modifying core pipeline
- **GDPR-compliant:** Logging only records technical diagnostics, never scores or pass/fail details

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full technical details.

---

## Module Structure

```text
sage/
├── Sage/                       # Module directory (PowerShell Gallery-ready)
│   ├── Sage.psd1               # Module manifest
│   ├── Sage.psm1               # Dot-source loader
│   ├── Public/                 # Exported functions (15)
│   ├── Private/                # Internal functions (12)
│   ├── Evaluators/             # Pester evaluation test files (11)
│   ├── Collectors/             # Scripts that run on remote VMs (11)
│   ├── tui/                    # Terminal UI entry point and helpers
│   │   ├── Start-SelfCheck.ps1 # TUI launcher script
│   │   ├── tui-config.psd1     # Vanilla TUI configuration
│   │   ├── Private/            # TUI helper functions (25)
│   │   └── keys/               # SSH keys for TUI (.gitkeep)
│   └── data/                   # Module data (shipped with module)
│       ├── exams/              # Exam definitions (example schema only)
│       ├── themes/             # UI theme definitions
│       ├── werkcolleges/       # Werkcollege exam files
│       ├── output/             # Generated results (gitignored, .gitkeep)
│       ├── logs/               # Evaluation logs (gitignored, .gitkeep)
│       └── config/             # User preferences (gitignored, .gitkeep)
├── tests/                      # Module self-tests (Unit + Reference)
├── tools/                      # Development-only scripts
├── docs/                       # Architecture and planning documents
├── .github/                    # CI workflows, hooks, issue templates
└── .gitignore                  # Protects exam content, results, logs
```

---

## Exam Definition

Exams live in `Sage/data/exams/<name>/exam.psd1` (gitignored except the schema example).
Copy `Sage/data/exams/_example/exam.psd1` and fill in:

- **Targets** — SSH connection profiles (port, username, platform, credential)
- **Roster** — maps CSV column names to known roles (IP, email, name, …)
- **Categories** — links each grading category to a Target, Evaluation test file, Collector, and Variables
- **Variables** — arrays of hashtables that drive `-ForEach` in Pester; empty array = test skipped

```powershell
# Validate before running:
Test-ExamDefinition -Path ./Sage/data/exams/myexam/exam.psd1
```

---

## Grading Model

- Grades stored as **absolute raw values** (sum of `PassGrade` for passing tests)
- Each category normalized to **/20** via `ConvertTo-NormalizedGrade`
- Total also normalized to /20 across all categories
- Manual overrides via `Edit-Grade` (writes back to JSON with reason)

---

## Logging (GDPR)

`Write-Log` never records:

- Individual test pass/fail status
- Grade values of any kind
- Scores, percentages, or totals
- Override reasons

It **only** records technical diagnostics: session timings, collector durations, file copy events, and module install results.

Log files: `logs/<timestamp>-<ExamName>.jsonl` (gitignored)

---

## Development & Contributing

### Running Tests

```powershell
# Module unit + reference tests only (fast, no remote VMs required)
./tools/Run-Tests.ps1

# Full Pester output on terminal
./tools/Run-Tests.ps1 -Detailed

# Run a subset by filter
./tools/Run-Tests.ps1 -Filter 'Write-Log'
```

> **Note:** Always use `tools/Run-Tests.ps1` — it runs Pester out-of-process
> to prevent VS Code extension host crashes. Never invoke `Invoke-Pester`
> directly in the integrated console.

### Coding Standards

See [CLAUDE.md](CLAUDE.md) for PowerShell coding standards and AI collaboration rules.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full technical architecture.

### Branches & Commits

- **Branch strategy:** Feature branches; `main` always deployable
- **Commits:** Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`)
- **Micro-commits:** One logical change per commit (revertible and independently testable)

### CI/CD

GitHub Actions runs on every push to `main` and on pull requests:

- **PSScriptAnalyzer** — lint all PowerShell files
- **Markdown Lint** — validate README and docs
- **Unit Tests** — Pester test suite (fast)
- **Security Scan** — path guard, secrets detection

### Contributing

Contributions are welcome! Please:

1. Read the [Code of Conduct](CODE_OF_CONDUCT.md)
2. Review [CONTRIBUTING.md](CONTRIBUTING.md) for the PR checklist and setup
3. Follow [CLAUDE.md](CLAUDE.md) for coding standards
4. Ensure all tests pass: `./tools/Run-Tests.ps1`
5. Ensure linters pass: `./tools/Run-PowerShellLint.ps1` and `./tools/Run-MarkdownLint.ps1`

---

## License

Licensed under the MIT License. See LICENSE file for details.
