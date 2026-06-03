# SAGE WebGUI — Implementation Plan

## Overview

Dockerized web application for student self-evaluation of werkcolleges labs.
Students provide VM connection details via browser, select chapters to test,
and receive full graded feedback in a web dashboard. All SAGE evaluation logic
stays server-side — students never see evaluator source code or exam
definitions.

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Frontend | React + TypeScript (Vite) | Rich component model for hierarchical drill-down UI |
| Backend API | Node.js + Fastify | Lightweight; native SSE; easy subprocess management |
| Progress | Server-Sent Events (SSE) | One-way server-to-client; auto-reconnect; proxy-friendly |
| Containers | 3 services + NPM sidecar | Clean separation; independent updates |
| Reverse proxy | Nginx Proxy Manager (NPM) | GUI-based TLS and cert management |
| Concurrency | One pwsh process per student (cap: 10) | Full isolation; approx. 150 MB/process |
| Auth | No auth; IP-based rate limiting | Self-check tool; optional shared access code |
| SSH credentials | Student provides password via GUI | Matches lab setup; HTTPS protects transit |
| Results storage | JSON files on Docker volume (24 h TTL) | Matches SAGE native JSON output |
| Exam definition | Mounted as read-only Docker volume | Update without image rebuild |
| Evaluation entry point | Existing `Invoke-StudentEvaluation` | Already exists; proven code path |
| Diff view | Summary banner + per-test indicators | Quick overview with click-to-expand |
| VM overrides | Per-target connection + enable/disable targets + categories | Flexible without breaking test assumptions |
| SAGE module | Git submodule | Always up-to-date; clean separation |
| Admin view | Optional (env flag) | Teacher dashboard; deployable without it |
| Time window | None — always available | Self-check, not exam |
| Student identity | Email (required) | Result naming and optional admin view |

## Architecture Diagram

```text
+-------------------------------------------------------------------+
|                      Docker Compose                                |
|                                                                    |
|  +---------------------+                                          |
|  | Nginx Proxy Manager |---- :443 / :80 (TLS termination)         |
|  | GUI on :81          |                                          |
|  +---------+-----------+                                          |
|            |                                                       |
|      +-----+-------------------------+                             |
|      |         routes                |                             |
|      v                               v                             |
|  +--------------+     +-------------------------------+            |
|  | frontend     |     | backend (api)                 |            |
|  | (nginx)      |     | (Node.js Fastify)             |            |
|  | static React |     |   /api/exam/info              |            |
|  | build files  |     |   /api/evaluation/start       |            |
|  |              |     |   /api/evaluation/:id/progress |            |
|  |              |     |   /api/evaluation/:id/results  |            |
|  |              |     |   /api/evaluation/:id/diff     |            |
|  |              |     |   /api/health                  |            |
|  +--------------+     |                                |            |
|                       |   spawns per student:          |            |
|                       |   +------------------+         |            |
|                       |   | pwsh process     |--SSH--> VMs         |
|                       |   | SAGE module      |         |            |
|                       |   +------------------+         |            |
|                       +--------------------------------+            |
|                                                                    |
|  Volumes:                                                          |
|    /data/results/  (JSON results, 24 h TTL)                        |
|    /data/exam/     (read-only exam.psd1 mount)                     |
+-------------------------------------------------------------------+
```

## File Structure

```text
webgui/
├── docker-compose.yml
├── .env.example
├── frontend/
│   ├── Dockerfile                  # Multi-stage: node build -> nginx serve
│   ├── nginx.conf                  # Serves static files only
│   ├── package.json
│   ├── tsconfig.json
│   ├── vite.config.ts
│   ├── index.html
│   ├── public/
│   │   ├── ehb-logo.png            # EHB logo (provided)
│   │   └── sage-logo.svg           # Generated: 1 branch, 4 leaves, minimal
│   └── src/
│       ├── main.ts
│       ├── App.tsx                  # Root: disclaimer + router
│       ├── router/
│       │   └── index.ts
│       ├── stores/
│       │   ├── evaluationStore.ts   # Evaluation state, results, diff
│       │   └── connectionStore.ts   # VM connection details
│       ├── components/
│       │   ├── ConnectionForm.tsx   # Hostname, ports, credentials
│       │   ├── CategorySelector.tsx # Checkbox grid for categories
│       │   ├── TargetConfig.tsx     # Per-target override panel
│       │   ├── ProgressView.tsx     # Real-time SSE progress
│       │   ├── ResultsSummary.tsx   # Category cards with scores
│       │   ├── CategoryDetail.tsx   # Expanded test list per category
│       │   ├── TestDetail.tsx       # Individual test: actual vs expected
│       │   ├── DiffBanner.tsx       # Score change summary + indicators
│       │   ├── Disclaimer.tsx       # Legal disclaimer modal
│       │   └── Layout/
│       │       ├── Header.tsx       # EHB logo, navigation
│       │       └── Background.tsx   # Sage leaves SVG backdrop
│       ├── types/
│       │   └── sage.ts              # TS types matching Sage.* PS types
│       └── utils/
│           ├── api.ts               # HTTP client + SSE handler
│           └── diff.ts              # Result comparison logic
├── backend/
│   ├── Dockerfile                   # Base: node:22-slim + pwsh 7.5
│   ├── package.json
│   ├── tsconfig.json
│   ├── src/
│   │   ├── index.ts                 # Fastify server entry
│   │   ├── config.ts                # Environment config
│   │   ├── routes/
│   │   │   ├── exam.ts              # GET /api/exam/info
│   │   │   ├── evaluation.ts        # POST /api/evaluation/start
│   │   │   ├── progress.ts          # GET /api/evaluation/:id/progress (SSE)
│   │   │   ├── results.ts           # GET /api/evaluation/:id/results
│   │   │   ├── diff.ts              # GET /api/evaluation/:id/diff
│   │   │   └── health.ts            # GET /api/health
│   │   ├── services/
│   │   │   ├── evaluation.ts        # Spawns pwsh, manages lifecycle
│   │   │   ├── exam-parser.ts       # Reads exam.psd1 for /api/exam/info
│   │   │   ├── results-store.ts     # JSON file read/write + TTL cleanup
│   │   │   └── session-manager.ts   # Concurrency limiter + session tracking
│   │   ├── middleware/
│   │   │   ├── rate-limit.ts        # Per-IP rate limiting
│   │   │   └── access-code.ts       # Optional shared access code
│   │   └── types/
│   │       └── sage.ts              # TS types for SAGE output
│   └── scripts/
│       └── run-evaluation.ps1       # PS wrapper: JSON stdin -> SAGE -> JSON stdout
├── npm/                             # NPM stores config in Docker volume
└── sage/                            # Git submodule -> SAGE public repo
```

## API Design

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/exam/info` | Categories, targets, defaults from werkcolleges exam.psd1 |
| POST | `/api/evaluation/start` | Starts evaluation; returns `{ id: "uuid" }` |
| GET | `/api/evaluation/:id/progress` | SSE stream of category-level progress events |
| GET | `/api/evaluation/:id/results` | Full `Sage.StudentGradeSummary` as JSON |
| GET | `/api/evaluation/:id/diff` | Diff with previous run (matched by email) |
| GET | `/api/health` | Container health check |

### POST /api/evaluation/start Request Body

```json
{
  "studentEmail": "student@student.ehb.be",
  "targets": {
    "Linux":  { "hostname": "vm.example.com", "port": 20022, "username": "student",       "password": "****", "enabled": true },
    "DC1":    { "hostname": "vm.example.com", "port": 30022, "username": "administrator",  "password": "****", "enabled": true },
    "DC2":    { "hostname": "vm.example.com", "port": 40022, "username": "administrator",  "password": "****", "enabled": true },
    "Client": { "hostname": "vm.example.com", "port": 50022, "username": "student",        "password": "****", "enabled": false }
  },
  "categories": ["General Configuration", "DNS DC1", "DNS DC2", "Active Directory"]
}
```

### SSE Progress Events

```text
event: category-start
data: {"category":"DNS DC1","target":"DC1","step":"collecting"}

event: category-progress
data: {"category":"DNS DC1","target":"DC1","step":"evaluating"}

event: category-complete
data: {"category":"DNS DC1","target":"DC1","score":16.5,"maxScore":20.0,"passed":8,"failed":2}

event: evaluation-complete
data: {"id":"uuid","totalScore":14.2,"maxScore":20.0}

event: error
data: {"category":"DNS DC1","message":"SSH connection failed to DC1:30022"}
```

## PowerShell Wrapper Script (run-evaluation.ps1)

Bridges Fastify and SAGE:

1. Reads JSON config from stdin (targets, categories, student info)
2. Imports the SAGE module
3. Constructs a `$Row` PSCustomObject matching `Invoke-StudentEvaluation`
   expectations (`$IpField`, `$EmailField`, `$NameField` properties)
4. Loads exam.psd1, filters to selected categories
5. Calls `Invoke-StudentEvaluation` with proper parameters
6. Writes progress events to stderr (parsed by Fastify for SSE)
7. Writes final `Sage.StudentGradeSummary` JSON to stdout

## Student Workflow

1. Open the WebGUI URL in any browser
2. Accept disclaimer ("self-check only, not an official grade, as-is")
3. Enter email address
4. Enter VM hostname
5. Review/override per-target connection details (hostname, port, user,
   password); enable/disable targets
6. Select categories to test (checkboxes grouped by lab chapter)
7. Click "Start Evaluation"
8. Watch real-time progress: per-category status updates with spinner
9. View results dashboard:
   - Overall score banner (e.g., "14.2 / 20.0")
   - Diff banner if previous run exists ("Improved from 12.0 to 14.2 (+2.2)")
   - Per-category cards: score, passed/failed count, color-coded
   - Click category to expand individual tests
   - Each test: name, pass/fail icon, points, actual value, expected value
   - Per-test diff indicators (improved / regressed / unchanged / new)
10. Re-run evaluation; new results compared with previous

## Admin View (Optional)

Enabled via `ADMIN_ENABLED=true` environment variable:

- `/admin` route protected by separate admin access code (`ADMIN_CODE`)
- Evaluation history grouped by student email
- Sortable table: email, timestamp, total score, category scores
- Click row to see full results for that evaluation
- Export all results as CSV

## Security Measures

1. **Input validation** — strict DNS-safe hostname chars; block `localhost`,
   `127.*`, `169.254.*` (SSRF prevention); ports 1-65535; usernames
   alphanumeric; passwords max 128 chars
2. **No command injection** — all user values as structured JSON to pwsh,
   never shell-interpolated
3. **HTTPS** — NPM terminates TLS (Let's Encrypt or provided cert)
4. **Rate limiting** — 1 concurrent evaluation per IP; 5 starts/hour/IP
5. **Process isolation** — separate pwsh per student; 10-minute timeout
6. **No disk secrets** — passwords in-memory only; SAGE GDPR logging prevents
   grade/password logging
7. **Results access** — UUID-keyed; no enumeration endpoint; 24 h TTL cleanup
8. **Access code** — optional shared code per class period (env var)
9. **Temp file cleanup** — evaluator files removed from student VMs after
   evaluation (SAGE module fix)

## Implementation Phases

### Phase 0: Repository Split and SAGE Module Prep

*Depends on: nothing. Can run in parallel with Phase 1.*

#### 0.1 Repository Restructure

1. Rename the current GitHub repository from `sage` to `sage-private`.
2. Create a new public repository named `sage` on GitHub.
3. The `sage-private` repo remains the source of truth for all development.
   The public `sage` repo receives only werkcolleges-safe content via
   automated sync (step 0.2).

#### 0.2 GitHub Action: Automated Sync to Public Repo

Create `.github/workflows/sync-public.yml` in `sage-private` using a
pre-built GitHub Marketplace Action to mirror safe content to the public
`sage` repo on every push to `main`.

**Recommended Action**:
[cpina/github-action-push-to-another-repository](https://github.com/cpina/github-action-push-to-another-repository)
— copies a source directory to a target repo. Alternatively,
[BetaHuhn/repo-file-sync-action](https://github.com/BetaHuhn/repo-file-sync-action).

**Workflow outline** (`.github/workflows/sync-public.yml`):

```yaml
name: Sync to public SAGE repo
on:
  push:
    branches: [main]

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Remove private content before sync
      - name: Remove private content
        run: |
          rm -rf samples/exams/
          rm -rf legacy/
          rm -f CLAUDE.md
          rm -f .github/workflows/sync-public.yml
          rm -f .github/sync.yml

      - uses: cpina/github-action-push-to-another-repository@main
        env:
          API_TOKEN_GITHUB: ${{ secrets.SAGE_PUBLIC_PUSH_TOKEN }}
        with:
          source-directory: '.'
          destination-github-username: '<github-org-or-user>'
          destination-repository-name: 'sage'
          target-branch: 'main'
```

**Required secrets**:

A GitHub Personal Access Token (PAT) or fine-grained token with push
access to the public `sage` repo, stored as `SAGE_PUBLIC_PUSH_TOKEN`
in `sage-private` repository secrets.

**What gets synced to public `sage`**:

- `Public/`, `Private/`, `Collectors/` — module code
- `Evaluations/` — werkcolleges-only evaluators (after step 0.4)
- `Tests/` — unit tests
- `sage.psd1`, `sage.psm1` — module manifest and loader
- `werkcolleges/` — werkcolleges exam definition
- `webgui/` — WebGUI application code
- `tui/` — TUI application code
- `tools/` — development tools
- `.github/workflows/ci.yml`, `.github/workflows/release.yml` — CI/CD
- `README.md`, `CHANGELOG.md`, `ARCHITECTURE.md` — documentation
- `PSScriptAnalyzerSettings.psd1` — linting config

**What stays private (excluded from sync)**:

- `samples/exams/` — all exam definitions
- `legacy/` — legacy code
- `CLAUDE.md` — AI collaboration instructions (contains test credentials)
- `.github/workflows/sync-public.yml` — the sync workflow itself
- `.github/sync.yml` — sync configuration (if applicable)

#### 0.3 EHB Logo

The EHB logo has been provided (PNG format). Place at
`webgui/frontend/public/ehb-logo.png`.

#### 0.4 Strip Evaluators for Public Repo

Audit each `Evaluations/*.Tests.ps1` file:

1. Identify Context blocks relevant to werkcolleges labs only.
2. Remove Context blocks that test topics not covered in werkcolleges
   (these reveal exam topics).
3. The stripped versions become the public `Evaluations/` content.
4. The full versions remain in `sage-private` only.

If all evaluator contexts are relevant to werkcolleges, no stripping
is needed. The audit determines this per file.

#### 0.5 Add Optional `-EvaluationsPath` Parameter

Modify `Invoke-RemoteSetup` (Private/) to accept an optional
`-EvaluationsPath` parameter. Default: `$PSScriptRoot/../Evaluations`
(backward-compatible). Flow the parameter through
`Invoke-StudentEvaluation` to `Invoke-RemoteSetup`. This allows exam
grading to use private evaluators from a different path.

#### 0.6 Create Werkcolleges Exam Definition

Create `werkcolleges/exam.psd1` containing only werkcolleges-relevant
categories and expected values. This file is safe for the public repo.

#### 0.7 Fix Temp File Cleanup

Modify `Close-RemoteSession` or `Invoke-StudentEvaluation`'s finally
block to delete `/tmp/sage-evaluations/` and `/tmp/sage-collectors/`
from the remote VM before closing the PSSession. This is a security fix
regardless of deployment model.

#### 0.8 Run Tests and Add New Tests

Run existing tests to verify no regressions. Add unit tests for:

- New `-EvaluationsPath` parameter
- Temp file cleanup behavior

### Phase 1: Backend Foundation

*Depends on: Phase 0.5 and 0.7.*

- 1.1. Initialize `webgui/backend/` with Fastify + TypeScript scaffold
- 1.2. Implement `run-evaluation.ps1` wrapper script:
  parse JSON stdin, construct `$Row` PSCustomObject, load and filter
  exam definition by selected categories, call
  `Invoke-StudentEvaluation`, write progress to stderr, results JSON
  to stdout
- 1.3. `services/evaluation.ts`: spawn pwsh subprocess, parse stderr for
  progress, parse stdout for results, enforce concurrency cap and
  10-minute timeout
- 1.4. `services/session-manager.ts`: active evaluations per IP,
  concurrency and rate limits
- 1.5. `services/results-store.ts`: JSON to `/data/results/`, lookup by
  session ID, lookup previous by email (for diff), 24 h TTL cleanup
- 1.6. `services/exam-parser.ts`: read exam.psd1 from mounted volume,
  extract categories/targets/defaults for `/api/exam/info`
- 1.7. All API routes (exam, evaluation, progress, results, diff, health)
- 1.8. Middleware: rate limiting, optional access code, input validation
  (SSRF prevention)

### Phase 2: Frontend

*Depends on: Phase 1.7 (API routes working).*

- 2.1. Initialize `webgui/frontend/` with Vite + React + TypeScript
- 2.2. Define TypeScript types matching `Sage.*` PowerShell types
- 2.3. API client utility + SSE handler
- 2.4. Build components: disclaimer modal, connection form (hostname,
  email, per-target overrides), category selector (checkboxes by lab
  chapter), progress view (SSE-driven per-category status), results
  summary (score banner, category cards), category detail (expandable
  test list), test detail (pass/fail, actual vs expected, points), diff
  banner + per-test diff indicators
- 2.5. Result comparison logic (`diff.ts`)
- 2.6. Generate `sage-logo.svg` (one branch, four leaves, minimal, sober)
- 2.7. Style with Tailwind CSS
- 2.8. Add EHB logo to header

### Phase 3: Containerization

*Depends on: Phase 1 and Phase 2 feature-complete.*

- 3.1. `backend/Dockerfile`: base `node:22-slim`, install pwsh 7.5 +
  Pester module, copy SAGE module (git submodule), copy backend code,
  define mount points `/data/results` and `/data/exam`
- 3.2. `frontend/Dockerfile`: multi-stage `node:22` build then
  `nginx:alpine` serve, copy built React app to nginx html directory
- 3.3. `docker-compose.yml`:
  - `npm` service: Nginx Proxy Manager (:80, :443, :81 admin GUI)
  - `frontend` service: nginx serving static files
  - `api` service: Fastify + pwsh
  - Volumes: results, exam definition, NPM config/data/letsencrypt
  - Networks: internal (api, frontend, npm communicate)
- 3.4. `.env.example` with all configuration variables
- 3.5. Set up git submodule for SAGE in `webgui/sage/`
- 3.6. Write deployment documentation (`webgui/README.md`)

### Phase 4: Admin View (Optional)

*Depends on: Phase 2 and Phase 3.*

- 4.1. Add `/admin` routes to backend (protected by `ADMIN_CODE`)
- 4.2. Admin frontend pages: student evaluation history table, detail
  view per evaluation, CSV export

### Phase 5: Testing and Hardening

*Depends on: Phase 3.*

- 5.1. End-to-end test: full evaluation via web UI against test VMs
- 5.2. Concurrent load test: 10+ simultaneous evaluations
- 5.3. Security tests: SSRF prevention, input validation, injection
  attempts
- 5.4. Error handling: unreachable VMs, timeout scenarios, pwsh crashes
- 5.5. Health check endpoint verification
- 5.6. Verify temp file cleanup on student VMs after evaluation

## DNS and TLS Setup (Deferred)

These are configured after the Docker Compose stack is running.

### DNS Record

The school IT team must create a DNS A record pointing to the Docker host:

- **Record type**: A
- **Name**: `sage` (or preferred subdomain)
- **Domain**: school domain (e.g., `ehb.be`)
- **Value**: public IP address of the Docker host server
- **Result**: `sage.ehb.be` resolves to the server

The WebGUI URL (e.g., `https://sage.ehb.be`) is then configured in Nginx
Proxy Manager via the admin GUI on port 81.

### TLS Certificate

#### Option A: Let's Encrypt (recommended)

1. Open NPM admin GUI at `http://<server-ip>:81`
2. Create default admin account on first login
3. Add Proxy Host: domain `sage.ehb.be`, forward to `frontend:80` (HTTP)
4. Add custom location `/api/*`, forward to `api:3000` (HTTP)
5. Enable SSL tab: request Let's Encrypt certificate, enable Force SSL
6. NPM auto-renews the certificate

#### Option B: School-provided certificate

1. Place certificate files on the Docker host:
   - `./certs/cert.pem` (certificate)
   - `./certs/key.pem` (private key)
   - `./certs/chain.pem` (CA chain, optional)
2. In NPM admin GUI: add Proxy Host, SSL tab, choose "Custom" and upload
   the certificate files
3. Renewal is manual; replace files and reload NPM when certificates expire

### NPM Admin GUI Initial Setup

After `docker compose up -d`:

1. Navigate to `http://<server-ip>:81`
2. Default login: `admin@example.com` / `changeme`
3. Change email and password immediately
4. Add proxy host entries as described above

## Environment Variables (.env)

```text
# Concurrency
CONCURRENCY_CAP=10
STUDENT_TIMEOUT=600

# Rate limiting
RATE_LIMIT_CONCURRENT=1
RATE_LIMIT_PER_HOUR=5

# Optional access code (empty = no gate)
ACCESS_CODE=

# Admin view (optional)
ADMIN_ENABLED=false
ADMIN_CODE=

# Paths (inside container)
EXAM_PATH=/data/exam/exam.psd1
RESULTS_DIR=/data/results
RESULTS_TTL_HOURS=24

# SAGE module path (inside container)
SAGE_MODULE_PATH=/app/sage
```
