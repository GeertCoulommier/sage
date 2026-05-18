# Changelog

All notable changes to **SAGE** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).  
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- **Lab 1 general-config categories** — Renamed exam definition to
  `Server-OS-werkcollege-labo-1-and-5-7-and-apache-nginx.psd1` (v5.0.0) and
  added three new `General Configuration` categories (DC1, DC2, Client) that
  verify hostname, static IP/prefix/gateway, DNS servers from an allowed set,
  ping (ICMPv4 inbound), and RDP enabled. *(2026-05-18)*
- **DC2 and Client targets** — Added DC2 (port 40022) and Client (port 50022)
  targets to TUI configs. *(2026-05-18)*
- **`Invoke-GeneralConfigCollector` — RDP and ICMP collection** — Collects
  `RdpEnabled` via `HKLM:\…\Terminal Server\fDenyTSConnections` registry key
  and `PingEnabled` via enabled ICMPv4 inbound firewall rules. *(2026-05-18)*
- **`GeneralConfig.Tests.ps1` — AllowedDns, Ping, RDP test contexts** —
  Evaluates `AllowedDnsTests`, `PingTests`, and `RdpTests` exam variables.
  *(2026-05-18)*

- **Nginx evaluation categories (Lab 8)** — Added five new exam categories to
  the renamed `Server-OS-werkcollege-labo5-7-and-apache-nginx.psd1` definition
  covering all Nginx lab exercises: *(2026-05-17)*
  - `Nginx — Tutorial`: service enabled/running, firewall http/https, default
    welcome page curl test.
  - `Nginx — PHP-FPM`: php-fpm service, `/etc/php-fpm.d/www.conf` config lines,
    `/var/www/php-nginx.local/html` directory, `info.php` content, `php-nginx.conf`
    server block lines, live curl tests for `php-nginx.local`.
  - `Nginx — Exercise 1`: `website1.local` via `sites-available`/`sites-enabled`
    pattern with symlink verification, `nginx.conf` include directive, index.html
    content, live curl test.
  - `Nginx — Exercise 2`: `website2.local` via `conf.d`, `nginx.conf` include
    directive, conf file lines, content and dual-site live tests.
  - `Nginx — Exercise 3`: `website3.local` on port 443 via `conf.d`, `nginx.conf`
    listen 80 + 443 directives, directory structure, conf file lines, content
    and triple-site live tests.
- **`Invoke-NginxCollector` expansion** — Added `NginxConfInclude`,
  `FirewallServices`, `Directories`, `SymlinkFiles`, `CurlResults`,
  `PhpFpmEnabled`, `PhpFpmRunning`, `PhpFpmConfContent`, `PhpFiles` data fields;
  normalized `NginxConfListen` whitespace. *(2026-05-17)*
- **`Nginx.Tests.ps1` expansion** — Added `Firewall`, `Required Directories`,
  `nginx.conf Include Directives`, `nginx.conf Listen Directives`, `Nginx Config Files`
  (ContainsLine), `Symlink Files`, `Live Web Tests`, `PHP-FPM Service`, `PHP-FPM Config`,
  and `PHP Files` test contexts with matching `ReviewContextMap` entries. *(2026-05-17)*

### Changed

- **Exam definition renamed** from `Server-OS-werkcollege-labo5-7-and-apache.psd1`
  to `Server-OS-werkcollege-labo5-7-and-apache-nginx.psd1`; `Name` and `Description`
  updated to reflect Nginx additions; version bumped to `4.0.0`. *(2026-05-17)*
- **`tui-config.psd1`** — `ExamDefinitionPath` updated to the renamed file;
  five Nginx categories added to `SelectedCategories`. *(2026-05-17)*
- **`Invoke-NginxCollector.Tests.ps1`** — Added sub-key assertions for all new
  Data fields and a `DirectoryTests variable handling` context. *(2026-05-17)*

- **LAMP php.local evaluation (Lab 8)** — Extended the `Apache — LAMP` exam
  category to verify the complete php.local setup from the LAMP tutorial:
  - `Invoke-ApacheCollector`: added `PhpFiles = @()` to the `Data` block and
    a new collection section that scans `/var/www` recursively for `php.info`
    files, storing `Path`, `Dir`, `Name`, and `Content` for each match.
  - `Apache.Tests.ps1`: added `PhpFileTests` guard in `BeforeDiscovery`, a
    `'PHP Info Files'` entry in `ReviewContextMap`, and a new
    `Context 'PHP Info Files'` that asserts each file exists in the expected
    directory and its content matches the expected string.
  - `Server-OS-werkcollege-labo5-7-and-apache.psd1` (`Apache — LAMP` category):
    added `DirectoryTests` for `/var/www/php.local/html`, `VirtualHostConfigTests`
    for `php.local.conf` (`<VirtualHost *:80>` and `ServerName php.local`),
    `PhpFileTests` confirming `php.info` contains `phpinfo()`, and a `CurlTests`
    entry that fetches `http://php.local/php.info` and asserts `PHP Version`
    appears in the response (verifying PHP-FPM execution end-to-end).
  *(2026-05-16)*
  Apache webserver configuration as described in Lab 8. Includes:
  - `Server-OS-werkcollege-labo5-7.psd1` renamed to
    `Server-OS-werkcollege-labo5-7-and-apache.psd1` (version bumped to 3.0.0);
    added `Linux` target (port 20022, user student) and four new categories:
    `Apache — Tutorial`, `Apache — Exercise 1`, `Apache — Exercise 2`,
    `Apache — LAMP`.
  - `Invoke-ApacheCollector`: extended with firewall service collection
    (`firewall-cmd --list-services`), directory existence checks driven by
    `Variables.DirectoryTests`, symlink info collection for
    `/etc/httpd/sites-enabled/*.conf`, live curl tests driven by
    `Variables.CurlTests` (with `--resolve` for DNS-independent testing),
    MariaDB service status, and PHP-FPM service status.
  - `Apache.Tests.ps1`: added `Firewall`, `Required Directories`,
    `httpd.conf Include Directives`, `Virtual Host Config Files`,
    `Symlink Files`, `Live Web Tests`, `MariaDB Service`, and `PHP-FPM Service`
    context blocks. Updated `ReviewContextMap` with entries for all new contexts.
  - `tui-config.psd1`: updated `ExamDefinitionPath`, added `Linux` target with
    port 20022, updated `TargetOrder`, `SelectedTargets`, and `SelectedCategories`
    to include the Apache categories.
  - 4 new unit tests in `Invoke-ApacheCollector.Tests.ps1` covering the new
    data keys, directory existence checks, and curl result population.
  *(2026-05-11)*

### Fixed

- **Apache firewall collection requires sudo on Rocky Linux** — `firewall-cmd
  --list-services` needs elevated D-Bus access on Rocky Linux; without a
  password the collector was running the command without privileges and always
  got an empty result. Changed the no-password branch to use `sudo -n` (non-
  interactive, works when the student user has `NOPASSWD` sudo configured).
  *(2026-05-16)*

- **Firewall tests still failing when sudo requires password** — `sudo -n`
  only works when NOPASSWD is configured; student VMs that require a password
  silently returned empty `FirewallServices`. Added the student VM password to
  the `Variables` block of all four Apache exam categories in
  `Server-OS-werkcollege-labo5-7-and-apache.psd1` so the collector uses
  `sudo -S` (pipe password via stdin), which works regardless of the sudoers
  configuration. Live-tested on
  `srvos-2526s2-lukebouvard-fba7e.westeurope.cloudapp.azure.com:20022` —
  `FirewallServices` now correctly returns `http` and `https`.
  *(2026-05-16)*

- **`ReviewContextMap` keys did not match Pester context names** — The entry
  `'Apache Config Files'` had no matching `Context` block in
  `Apache.Tests.ps1` so its data was never displayed in Edit-Grade. Renamed
  it to `'Virtual Host Config Files'` (the actual context name) and added the
  three missing entries: `'httpd.conf Include Directives'`,
  `'Apache Virtual Hosts'`, and `'Website Content'`. All entries now show the
  relevant collected data when a grader reviews an item.
  *(2026-05-16)*

### Added

- **Expanded `Format-WebServerData` and `Format-WebServerDataMarkdown`** — Both
  text and Markdown formatters for Apache/Nginx collector output now render all
  collected data: firewall services, MariaDB/PHP-FPM service status,
  `httpd.conf` `Listen` and `IncludeOptional` directives (Apache only),
  directory existence results, virtual-host config files (including
  `VirtualHost`, `ServerAlias`, and `DocumentRoot` lines), symlink details,
  curl live-test results, and index file previews.
  *(2026-05-16)*

- **Refactored colour-conversion utilities** — Consolidated
  duplicate color-conversion functions and fixed runtime errors when Spectre
  colour strings were assigned directly to the console API. Includes:
  - Removed duplicate `Resolve-ThemeColor` from `Show-TestDetail.ps1` (canonical
    version is in `Write-SageColor.ps1`).
  - Removed duplicate `ConvertToSafeConsoleColor` from `Show-TargetSelector.ps1`
    and replaced all call sites with the canonical `Resolve-ThemeColor`.
  - Fixed two ForegroundColor assignments in `Show-TestDetail.ps1` that were
    assigning Spectre colour strings (e.g. `'grey89'`) directly to the console
    API; now wrapped with `Resolve-ThemeColor` to convert to System.ConsoleColor.
  - Updated unit tests for both functions to dot-source `Write-SageColor.ps1`
    so `Resolve-ThemeColor` is available during tests.
  - Corrected Linux target's PrimaryHostName in `tui-config.psd1` from the
    incorrect DC1 IP (`192.168.1.3`) to the correct Linux LAN IP (`192.168.1.2`).
  *(2026-05-11)*

- **Self-check exam path migration** — Repaired TUI startup when an older
  `data/config/tui-config-personal.psd1` still referenced the removed
  `werkcollege-labo5-6-group-policy-en-dhcp.psd1` file.
  - `Initialize-TuiUserConfig` now synchronizes `ExamDefinitionPath` from the
    shipped TUI config while preserving remembered user settings.
  - Added regression coverage for stale personal config migration.
  - Updated TUI live test helpers to use `Server-OS-werkcollege-labo5-7.psd1`.
  *(2026-05-07)*

- **AD Sites & Services evaluation (Lab 7)** — Added full evaluation coverage for
  Active Directory Sites & Services as described in Lab 7. Includes:
  - New exam definition `Server-OS-werkcollege-labo5-7.psd1` (renamed from
    `werkcollege-labo5-6-group-policy-en-dhcp.psd1`, version bumped to 2.0.0)
    with a new `Active Directory — Sites & Services` category covering sites,
    subnets, site links (existence + sites), costs, replication intervals, and
    custom schedules (weekend exclusion for Kaai-Jette; night-time exclusion
    for Jette-Bloemenhof).
  - `Invoke-AdCollector`: extended with `Sites`, `Subnets`, and `SiteLinks`
    collection using `Get-ADReplicationSite`, `Get-ADReplicationSubnet`, and
    `Get-ADReplicationSiteLink`. Site link schedule bytes are decoded into a
    flat 168-integer availability matrix (7 days × 24 hours).
  - `Ad.Tests.ps1`: added `Sites`, `Subnets`, `Site Links` context blocks with
    Pester assertions for existence, subnet-to-site assignment, cost, replication
    interval, weekend schedule exclusion, and hour-based schedule exclusion.
  - `tui-config.psd1`: updated `ExamDefinitionPath` to reference the renamed file.
  - 10 new unit tests in `Invoke-AdCollector.Tests.ps1` covering sites, subnets,
    site link collection, and schedule byte decoding.
  *(2026-05-07)*

- **AD Sites & Services: DC site membership tests (Lab 7)** — Extended evaluation
  to verify which site each domain controller belongs to (DC1 → Kaai,
  DC2 → Bloemenhof).
  - `Invoke-AdCollector`: added `DomainControllers` collection via
    `Get-ADDomainController -Filter *`, capturing `Name` and `Site` per DC.
  - `Ad.Tests.ps1`: added `Domain Controllers` context block with
    `DcSiteTests`-driven Pester assertion for DC-to-site assignment. Added
    `DomainControllers` entry to the `ReviewContextMap`.
  - `Server-OS-werkcollege-labo5-7.psd1`: added `DcSiteTests` array to the
    `Active Directory — Sites & Services` category.
  - 3 new unit tests in `Invoke-AdCollector.Tests.ps1` and updated sub-key
    and partial-failure assertions.
  *(2026-05-07)*

### Fixed

- **SSH key setup: key generation used wrong passphrase argument** —
  `Invoke-SshKeySetup` was calling `ssh-keygen -N '""'` which passes the
  literal two-character string `""` as the passphrase instead of an empty
  passphrase. This created a passphrase-protected key that `Test-SshKeyAuth`
  could not use in `BatchMode=yes`, causing the re-test after key installation
  to always fail. Fixed by using `-N ''` (empty string) so the generated
  `id_sage` key has no passphrase.
  *(2026-05-06)*

- **SSH key auth test: agent keys could produce false positives** —
  `Test-SshKeyAuth` did not set `IdentitiesOnly=yes` when a `KeyFilePath` was
  provided, so an SSH agent key could satisfy the auth check even when the
  target's `authorized_keys` did not yet contain the SAGE key. Added
  `-o IdentitiesOnly=yes` alongside `-i $KeyFilePath` to ensure only the
  specified key is tested.
  *(2026-05-06)*

### Changed

- **`Format-CollectorData.ps1`: All `*DataMarkdown` formatters now emit code blocks** —
  All ten `Format-*DataMarkdown` functions have been rewritten to emit aligned
  key-value pairs inside fenced code blocks (` ```text `) instead of Markdown tables.
  Column widths are computed with `foreach` loops to avoid PowerShell pipeline
  array-unrolling. This provides a cleaner, diff-friendly representation in the
  TUI and in exported reports.
  *(2026-05-06)*

- **TUI: `ConvertFrom-CollectorMarkdown` updated for code-block rendering** —
  Code blocks in the diff drill-down pane now display with standard text color
  (White) instead of accent color. Indentation is now relative to header level:
  code blocks are indented by `2 * heading_level` spaces (e.g., 2 spaces under
  `# Heading`, 4 spaces under `## Heading`, etc.). The `$WrapText` function now
  aligns wrapped lines to the column where the value content starts, ensuring
  continuation lines preserve the alignment of key-value pairs.
  *(2026-05-06)*

- **`Format-GpoDataMarkdown`: Nested hashtable rendering** —
  GPO settings that contain hashtable values (e.g., application configurations)
  are now rendered as nested key-value pairs in code blocks instead of showing
  the type name `System.Collections.Hashtable`. Added `Format-HashtableAsCodeBlock`
  helper function to render hashtables recursively with proper indentation. Code
  blocks now display full structured data for better readability.
  *(2026-05-06)*

### Style

- **`Invoke-SshKeySetup.ps1`: Fix variable assignment alignment** —
  Normalized inconsistent spacing in variable assignment statements to follow
  CLAUDE.md alignment rules. All `$VariableName = ...` assignments now use
  consistent single-space alignment.
  *(2026-05-06)*

### Fixed

- **`Format-GpoDataMarkdown`: Fix hashtable Settings rendering** —
  When `Settings` on a GPO scope item is a `[hashtable]` (as produced by the
  live `Invoke-GpoCollector`), the formatter was iterating `PSObject.Properties`,
  which exposes internal hashtable members (`IsReadOnly`, `IsFixedSize`, `Keys`,
  `Values`, `SyncRoot`, `Count`) instead of the actual key-value pairs.  The fix
  detects the `[hashtable]` case and delegates directly to
  `Format-HashtableAsCodeBlock`, so only the meaningful `Name`, `Path`,
  `PathExists`, `DeploymentType`, etc. are rendered — properly aligned and in a
  fenced code block.  `PSCustomObject` settings continue to use `PSObject.Properties`
  as before.
  *(2026-05-06)*

- **`Invoke-DiffDrillDown`: Fix infinite loop on long UNC paths** —
  The `$WrapText` scriptblock used a continuation-indent strategy to align wrapped
  continuation lines to the value column of key-value pairs.  When the continuation
  indent was wider than the remaining content (e.g., a UNC path with no spaces
  inside a code-block-indented section), adding the indent could make `$Remaining`
  the same length as before, causing an infinite loop that froze the TUI with a
  blank unresponsive screen.  A progress-tracking guard (`$PrevContentLen`) now
  breaks out of the loop whenever no forward progress is made on the actual content
  length.
  *(2026-05-06)*

- **TUI: `ConvertFrom-CollectorMarkdown` crashes on markdown content with blank lines** —
  The `$Lines` parameter was declared `[Parameter(Mandatory)] [string[]]` which causes
  PowerShell to throw "Cannot bind argument to parameter 'Lines' because it is an
  empty string" whenever the array contains any empty string element (blank lines in
  markdown are split to `""`). Removed `Mandatory` and added `[AllowNull()]` and
  `[AllowEmptyCollection()]` with a default of `@()`. This fixes the crash in
  `Show-TestDetail` (via `Show-CategoryDetail`) and `Invoke-DiffDrillDown` (via
  `Compare-Results`) when drilling down into test results with collector data.
  *(2026-05-05)*

- **TUI: `Resolve-ThemeColor` missing in `Show-ResultsSummary`, `Show-CategoryDetail`,
  `Show-PreviousRuns`, `Compare-Results`** — All four screens were assigning Spectre
  theme colour values (e.g. `'white on steelblue'`) directly to
  `[System.Console]::ForegroundColor` without going through `Resolve-ThemeColor`,
  causing a `"Cannot convert value 'white on steelblue' to type System.ConsoleColor"`
  crash on the Nord Ice and GitHub Dark themes. Wrapped all direct theme colour
  assignments in these files with `Resolve-ThemeColor`.
  *(2026-05-05)*

- **Tools: markdown lint scanning generated output files** — `Run-MarkdownLint.ps1`
  was picking up auto-generated collector Markdown in `output/` directories, causing
  spurious lint failures. Extended the exclusion filter to also skip
  `output/`, `Sage/data/output/`, `Sage/tui/output/`, and `tui/output/`.
  *(2026-05-05)*

### Added

- **Tools: `Test-TuiScreens.ps1` TUI screen integration test** — New script that
  runs a live evaluation against a remote server, then drives every TUI screen
  (`Show-ResultsSummary`, `Show-CategoryDetail`, `Show-PreviousRuns`, diff comparison)
  with a mocked ReadKey key-queue to verify no exceptions are thrown. Supports
  `-SkipEvaluation` to run against existing output data only.
  *(2026-05-05)*

- **SSH key installation on Windows targets** —
  `Install-SshKeyOnTarget` now encodes the remote PowerShell script as
  Base64/UTF-16LE and runs it via `powershell -EncodedCommand` instead of
  `-Command "..."`. This eliminates cmd.exe double-quote mis-parsing that
  silently broke key installation on Windows Server targets (DC1/DC2).
  *(2026-05-04)*

- **TUI: SSH auth failure no longer flashes and disappears** —
  `Invoke-SelfCheck` now pauses with a troubleshooting message before
  returning to the main menu when all targets fail SSH key authentication,
  instead of immediately redrawing the menu and hiding the error.
  *(2026-05-04)*

### Added

- **Markdown collector output (`Format-CollectorDataMarkdown`)** —
  Added `Format-CollectorDataMarkdown` and eleven per-collector sub-formatters
  in `Sage/Private/Format-CollectorData.ps1`.  Each collector produces a
  structured Markdown report with H1/H2/H3/H4 headings, `| Key | Value |`
  tables for key-value data, fenced code blocks for file content, bullet lists,
  and blockquote warnings for unavailable services.
  *(2026-05-05)*

- **`.md` collector file saved alongside `.txt` during evaluation** —
  `Invoke-StudentEvaluation` now calls `Format-CollectorDataMarkdown` and
  saves a `*-collector.md` file next to the existing `*-collector.txt` in the
  `CollectorData/` subdirectory when `-SaveCollectorData` is used.
  *(2026-05-05)*

- **TUI renders collector Markdown with per-line colours** —
  Added `ConvertFrom-CollectorMarkdown` to `Sage/tui/Private/Compare-Results.ps1`.
  `Show-TestDetail` and `Invoke-DiffDrillDown` now load `*-collector.md` instead
  of `*-collector.txt` and render each line with a colour derived from its
  Markdown element type (headings cyan, tables white, blockquotes yellow, code
  fences dark-gray, bullets white).
  *(2026-05-05)*

- **DHCP collector and evaluator restored from history** —
  Restored `Invoke-DhcpCollector` additions (`RoleInstalled`, `DomainName`,
  `Filters.AllowEnabled/DenyEnabled`, `LeaseDurationDays`) and corresponding
  `Dhcp.Tests.ps1` contexts (`DHCP Role`, `Filters`, scope name/state/lease tests,
  dynamic `DomainName` option assertion, reservation name check).
  Unit tests in `tests/Unit/Invoke-DhcpCollector.Tests.ps1` updated to match.
  *(2026-05-04)*

- **Werkcollege Lab 5 & 6 — Group Policy en DHCP** —
  Created `Sage/data/werkcolleges/werkcollege-labo5-6-group-policy-en-dhcp.psd1`
  combining the existing Lab 5 GPO categories with the restored Lab 6 DHCP
  category (scope Kaai, exclusions, options, reservation, allow/deny filter checks).
  Filename uses kebab-case for cross-platform compatibility.
  *(2026-05-04)*

- **Community files** — Added `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `.github/PULL_REQUEST_TEMPLATE.md`, and three issue templates
  (`bug_report.md`, `feature_request.md`, `new_collector.md`) to support
  future open-source contributions.
  *(2026-05-04)*

### Changed

- **`tui-config.psd1` — updated to new werkcollege filename** —
  `ExamDefinitionPath` now points to `werkcollege-labo5-6-group-policy-en-dhcp.psd1`.
  *(2026-05-04)*

- **`sync-public.yml` — preserve `.gitkeep` files in gitignored runtime dirs** —
  Changed `rm -rf` to `rm -rf <dir>/*` for `data/logs/`, `data/output/`, and
  `data/config/` so the public mirror retains the `.gitkeep` placeholders that
  students need for a working self-check out of the box.
  *(2026-05-04)*

- **README — improved TUI section and structure diagram** —
  Added TUI screen descriptions, troubleshooting tips, updated module structure
  diagram (removed `.templates/`, added `.github/`), updated exam creation
  instructions to reference the committed `_example/` schema instead of
  deleted `.templates/`, added Contributing section.
  *(2026-05-04)*

### Removed

- **Empty `Collectors/` directory at repo root** — Stale artifact from the
  pre-`Sage/` restructure. Removed.
  *(2026-05-04)*

- **`Server OS - labo 5 - Group Policy.psd1`** — Superseded by the new
  kebab-case combined Lab 5 & 6 file. Preserved locally for reference;
  no longer referenced by `tui-config.psd1`.
  *(2026-05-04)*

- **Module restructure — moved into `Sage/` subdirectory** -
  All module source files (manifests, functions, collectors, evaluators, TUI, data)
  moved from the repository root into a `Sage/` subdirectory, aligning with
  PowerShell Gallery packaging conventions. `Evaluations/` renamed to `Evaluators/`,
  `Tests/` to `tests/`. All internal path references, tooling, and CI updated accordingly.

- **TUI config formatting alignment tidy-up** -
  Adjusted alignment-only spacing in `tui/Private/Save-TuiPreferencesInExam.ps1`
  and `tui/tui-config.psd1` for consistent key/value readability, without
  altering runtime behavior.
  *(2026-05-03 15:28 UTC)*

- **Evaluator style alignment clean-up** -
  Normalized alignment-only spacing in `Evaluations/FileServer.Tests.ps1` and
  `Evaluations/Gpo.Tests.ps1` to keep hashtable/scriptblock formatting
  consistent without changing evaluation behavior.
  *(2026-05-03 15:28 UTC)*

- **Dev container now mirrors host timezone metadata** -
  Added read-only mounts for `/etc/localtime` and `/etc/timezone` in
  `.devcontainer/devcontainer.json` so container time and timezone-dependent
  tooling match the host configuration more reliably.
  *(2026-05-03 15:28 UTC)*

- **Werkcollege Lab 5 checks hardened for live host path/link/deployment variance** -
  Fixed `Invoke-FileServerCollector` relative-path derivation so folder/file
  checks handle case and slash differences reliably, and improved
  `Invoke-GpoCollector` policy-path extraction to prefer configured UNC values
  over documentation examples in XML. Updated `FileServer.Tests.ps1` and
  `Gpo.Tests.ps1` to use case-insensitive path/link matching, tolerate
  `Assign` vs `Assigned` software deployment values, and keep domain-root/
  forbidden-link constraints robust. Updated
  `data/werkcolleges/Server OS - labo 5 - Group Policy.psd1` to validate
  `Everyone` full share access on `Shared`, align NTFS identity expectations
  with per-folder groups, relax `Background`/`Lockdown` link requirements to
  required-any + forbidden constraints, keep wallpaper extension validation,
  and add an optional `Enable Active Desktop` policy check.
  *(2026-05-03 15:09 UTC)*

- **Werkcollege Lab 5: expanded collector/evaluator coverage for GPO and FileServer** -
  Extended `Invoke-FileServerCollector` with recursive folder/file inventory and
  per-folder ACL capture; extended `FileServer.Tests.ps1` with folder/file
  assertions, relative-path ACL checks, and flexible identity matching. Extended
  `Invoke-GpoCollector` with UNC path extraction and path existence signals for
  software installs, drive maps, and policy evidence; extended `Gpo.Tests.ps1`
  with multi-link checks (required/forbidden/domain-root constraints), flexible
  software name matching, and optional path/path-exists assertions.
  *(2026-05-03 13:13 UTC)*

- **Werkcollege Lab 5 exam data aligned with shared-folder model and stricter GPO rules** -
  Updated `data/werkcolleges/Server OS - labo 5 - Group Policy.psd1` to validate
  one `Shared` SMB share with required subfolders (`algemene_informatie`,
  `algemene_informatie_IT`, `public`, `public\\software`), added NTFS checks for
  `public-R` and read/execute access on distribution paths, added file-pattern
  checks for wallpaper assets and MSI payloads, changed `Background`/`Lockdown`
  link expectations to department OUs with explicit exclusions and domain-root
  prohibition, and set all GPO test `PassGrade` values to `5`.
  *(2026-05-03 13:16 UTC)*

- **Renamed `samples/` directory to `data/`** — The top-level `samples/`
  folder has been renamed to `data/` for clarity. All references across
  `.gitignore`, CI workflows, pre-commit hooks, `Public/`, `tools/`,
  `Tests/`, `.templates/`, `.vscode/settings.json`, and all documentation
  files have been updated accordingly. `data/logs/`, `data/output/`, and
  `data/config/` are gitignored.
  *(2026-04-30)*

- **Moved werkcolleges exam to `data/werkcolleges/`** — `werkcolleges/exam.psd1`
  has been moved to `data/werkcolleges/Server OS - labo 5 - Group Policy.psd1`
  to centralise all data under `data/`. The `tui-config.psd1` `ExamDefinitionPath`
  already pointed to the new location. Updated `tools/Test-TuiLive.ps1` and
  documentation to reference the new path.
  *(2026-04-30)*

- **TUI config split: vanilla stays in `tui/`, user config persisted to `data/config/`** —
  `tui/tui-config.psd1` is now a read-only vanilla/default config that is never
  written to by the TUI. On the first time a student modifies a setting (targets,
  categories, domain name, theme, output dir), `data/config/tui-config-personal.psd1` is
  created as a copy of the vanilla config and all changes are stored there.
  Subsequent TUI launches use `data/config/tui-config-personal.psd1` automatically.
  Added `Initialize-TuiUserConfig` helper to `Save-TuiPreferencesInExam.ps1`.
  Updated `Show-Settings` to accept an optional `$ConfigPath` parameter.
  *(2026-04-30)*

### Fixed

- **Tests: moved Windows CI TUI skip detection to Pester discovery time** —
  The initial Windows-host compatibility guard for interactive TUI test suites
  was placed in `BeforeAll`, which meant `Describe -Skip` still evaluated too
  early on GitHub Actions and the tests executed anyway. The skip predicate is
  now computed at file scope so non-interactive Windows CI hosts correctly skip
  console-surface-dependent tests during discovery.
  *(2026-04-30 12:22 UTC)*

- **Tests: stabilized interactive TUI unit tests for Windows CI hosts** —
  Added an environment guard in interactive console-driven test suites to skip
  only when the host is non-interactive on Windows (redirected console input/
  output or zero-sized console surface), while keeping these tests active on
  normal interactive runs. Also relaxed brittle Windows networking assertions
  in `Invoke-GeneralConfigCollector.Tests.ps1` to validate schema/IPv4 shape
  instead of host-specific addresses.
  *(2026-04-30)*

- **TUI: theme picker now writes to personal config only** —
  `Show-ThemePicker` was hardcoding the write target to `tui/tui-config.psd1`
  (vanilla) instead of the personal config. Added a `$ConfigPath` parameter
  to `Show-ThemePicker` and updated `Show-Settings` to pass `$ConfigFile`
  when invoking it. Also corrected the vanilla `tui/tui-config.psd1` which had
  `Theme = '17. Night Owl'` written there by the previous buggy logic; restored
  to the canonical default `'13. Nord Ice'`.
  *(2026-04-30)*

- **TUI: restored full TUI functionality after breaking Spectre rewrite** —
  Reverted commits phase1–phase6 that replaced the entire arrow-key TUI with
  mandatory `PwshSpectreConsole` calls. Restored: optional Spectre with
  plain-text fallback in `Invoke-SelfCheck`, ASCII-art banner and
  `Show-StatusBox` in `Show-SageHeader`, split-pane `Show-CategorySelector`
  and `Show-TargetSelector`, arrow-key `Show-MainMenu` and `Show-Settings`,
  and full results/detail/diff screens. `Get-SageTheme` is kept for future
  use but is not yet called.
  *(2026-04-28)*

### Changed

- **TUI: results table slash alignment + collector panel scrolling** —
  Category `Score` and `Passed` columns in `Show-ResultsSummary` now align on
  a centered `/` character; `Show-TestDetail` now supports selecting the
  collector-data panel and scrolling long data with arrows, PgUp/PgDn,
  Home/End, and Tab panel switching.
  *(2026-04-26)*

- **TUI: restored remembered/fallback persistence behavior** — Reinstated
  `Invoke-SelfCheck` and `Get-ConnectionFallback` behavior that saves and
  reuses selected targets/categories, domain value, and fallback preferences
  via `tui/exam.psd1`.
  *(2026-04-26)*

- **TUI: redistribution-safe defaults while preserving blocks** —
  `tui/exam.psd1` now keeps `Fallback*` and `Remembered` blocks but ships with
  empty fallback data (`FallbackHostName = ''`, `FallbackPort = 0`) so no
  environment-specific fallback endpoints are bundled.
  *(2026-04-26)*

- **Tests: ScriptAnalyzer problem cleanup in self-check tests** —
  `Invoke-SelfCheck.Tests.ps1` was adjusted to remove problematic stub
  overrides and unused mock parameters so VS Code Problems no longer reports
  those PSScriptAnalyzer findings.
  *(2026-04-26)*

- **TUI: fixed empty-string detail wrapping crash** — Updated wrap helpers in
  `Show-TestDetail` and diff drill-down to allow empty strings, preventing
  `Cannot bind argument to parameter 'Text' because it is an empty string`
  when opening certain test details. Added targeted unit coverage in
  `Show-TestDetail.Tests.ps1`.
  *(2026-04-26)*

- **TUI: restored self-check header metadata + menu fit** — Rewired
  `Invoke-SelfCheck` to repopulate `$script:SageExamName` /
  `$script:SageExamVersion` and refresh `$script:SageLatestSummary` so the
  top banner again shows the correct exam name/version. `Show-MainMenu` now
  adapts disclaimer rendering for small terminal heights to reduce header
  scrolling/flicker, and fail rows in `Show-ResultsSummary` use dark orange
  (`DarkYellow`) instead of red.
  *(2026-04-26)*

- **TUI: restored parallel local evaluation + progress bars** — Reverted
  `Invoke-LocalEvaluation` to the previously working per-target thread-job
  execution model with live `Write-Progress` updates, restoring parallel
  target processing and progress visibility during self-check runs.
  *(2026-04-26)*

- **TUI: remembered self-check preferences** — The TUI now persists and reuses
  remembered values in `tui/exam.psd1` (`Remembered.DomainName`,
  `Remembered.SelectedTargets`, `Remembered.SelectedCategories`, and
  `Remembered.PreferFallbackTargets`). Run Evaluation preselects these on
  later runs, preferred fallback targets are tried first, and only selected
  evaluation test files are copied for a run. *(2026-04-26)*
- **TUI: navigation and results UI polish** — Escape handling was removed from
  TUI flows in favor of explicit `B`/Backspace + `Q`, previous-runs now shows
  auto-sized aligned columns with targeted VM list, results screens keep
  grouped target headers, partial status uses dark orange, and test-detail
  views always render collector data with wrapped long lines. *(2026-04-26)*
- **TUI: diff drill-down and SSH key setup hardening** — Diff results now use
  newer-on-left/older-on-right labeling with safer color fallback and wrapped
  long detail text; SSH key installation keeps SecureString password handling
  while preserving non-interactive sshpass support. *(2026-04-26)*
- **TUI: results banner │ alignment** — The pipe separator in the last-results
  banner is now always at a fixed column (left side padded to 29 chars) so
  `Score: X / 20  (Y%)   │  Tests passed: N / T` aligns regardless of score
  width. *(2026-04-26)*
- **TUI: CategorySelector left panel** — Added a `Selection` header row above
  the `All` and `None` actions to make it clear the buttons affect the
  category selection. *(2026-04-26)*
- **TUI: PreviousRuns default state** — When ≥ 2 runs exist the screen now
  opens with the 2 most recent runs pre-marked for diff and focus on the
  `Diff 2 marked` action so pressing Enter immediately diffs them.
  *(2026-04-26)*
- **TUI: DiffResults grouped display** — The right panel in the diff screen
  now groups tests under VM headers (`── DC1 ──`) and category sub-headers
  (`── DNS DC1 ──`), matching the layout of CategorySelector. Default filter
  changed from *Diff only* to *All* so all tests are visible on first open.
  *(2026-04-26)*

### Changed

- **TUI: last-results banner format** — Banner now shows `Tests passed: N / T`
  instead of `Total: T  Passed: N` for clearer readability. *(2026-04-25)*
- **TUI: all menus converted to arrow-key navigation** — `Show-MainMenu` and
  `Show-Settings` rewritten to use Up/Down arrows and Enter.  Spectre
  early-return paths removed from `Show-TargetSelector`, `Show-CategorySelector`,
  and `Show-PreviousRuns` so the split-pane layout always renders regardless of
  whether PwshSpectreConsole is installed. *(2026-04-25)*

### Fixed

- **TUI: menu scrolling replication bug** — Arrow-key menus now use ANSI
  cursor-previous-N-lines (`\e[NF`) to overwrite previous renders in-place,
  preventing duplicate items when scrolling. *(2026-04-24)*
- **TUI: Spectre markup crash** — Dynamic strings (timestamps, scores,
  category names, test names) are now escaped (`[` → `[[`, `]` → `]]`)
  before passing to PwshSpectreConsole, fixing `MethodInvocationException:
  Encountered malformed markup tag`. *(2026-04-24)*
- **TUI: Switch to plain text does nothing** — `Show-MainMenu` now trims
  the Spectre selection value and uses a fuzzy fallback match so `ToggleRenderer`
  is correctly returned regardless of trailing whitespace. *(2026-04-24)*
- **TUI: View Previous Runs banner wrong run** — The "Last Score" banner in
  `Show-PreviousRuns` is now always driven by `$LatestSummary` (passed from
  `Invoke-SelfCheck`) instead of the currently selected run. *(2026-04-24)*
- **TUI: diff column too narrow for long test names** — `Show-DiffResults`
  autosizes column 1 to the longest test name in the result set
  (`max(30, maxLen+2)`) instead of a hardcoded 40. *(2026-04-24)*
- **TUI: no back option in target/category menus** — `Show-TargetSelector`
  and `Show-CategorySelector` now handle `Escape` and `B` keys as a back
  signal, returning `@()`. `Invoke-SelfCheck` checks `$script:SageQuit` after
  each selector to exit cleanly. *(2026-04-24)*
- **TUI: Show-ResultsSummary/Show-Settings/Show-PreviousRuns return values**
  — These functions now return `'Back'` or `'QuitTui'` strings so callers can
  react to navigation events. *(2026-04-24)*

### Added

- **TUI: per-target header in diff overview** — `Show-DiffResults` now prints
  a `═══ TargetName ═══` separator before each group of results, making it
  easy to distinguish DC1/DC2/Linux entries at a glance. *(2026-04-24)*
- **TUI: last-score banner in main menu** — `Show-MainMenu` accepts a new
  optional `$LatestSummary` parameter; when provided, a framed banner showing
  score, percentage, and test counts is displayed below the header. *(2026-04-24)*
- **TUI: diff uses Spectre by default with 2-selection limit** — `Show-DiffSelector`
  now uses two sequential `Read-SpectreSelection` calls (pick run A, then pick
  run B from the remainder) in Spectre mode. *(2026-04-24)*
- **TUI: parallel evaluation** — `Invoke-LocalEvaluation` now runs one
  `Invoke-StudentEvaluation` per target in parallel via `ForEach-Object -Parallel`
  when more than one target is selected, then merges the results. Single-target
  evaluations remain sequential. *(2026-04-24)*

### Fixed

- **TUI: domain prompt null input** — `Invoke-DomainNamePrompt`
  now casts `Read-Host` results to string before trimming so cancelled
  confirmations and empty input return cleanly instead of failing on a
  null value. *(2026-04-21 06:12 UTC)*
- **TUI: SSH auth target gating** — `Invoke-SelfCheck` now disables
  categories for targets that still fail SSH key authentication and only
  passes authenticated targets into `Invoke-LocalEvaluation`.
  *(2026-04-21 06:12 UTC)*
- **TUI: Q/B navigation** — Q now quits the TUI entirely; B goes back
  one level. B is available in every sub-menu; main menu only has Q.
  All `Show-*` functions return `'Back'` or `'QuitTui'` signals that
  propagate up the call stack. *(2026-04-20)*
- **TUI: target filtering** — `Copy-ExamWithCategories` now removes
  targets that have no remaining categories after filtering. Fixes
  "self-check" hostname errors when evaluating only a subset of
  targets. *(2026-04-20)*
- **TUI: domain name validation** — Strips known suffixes (`.local`,
  `.be`) from user input before using it as the `<domainname>`
  placeholder replacement. Prevents double-suffix domains like
  `voornaam.local.local`. Warns on multi-part domain prefixes.
  *(2026-04-20)*
- **TUI: VM order** — Targets now follow the order defined in
  `tui/exam.psd1` via the new `TargetOrder` key, instead of
  non-deterministic hashtable key order. *(2026-04-20)*

### Added

- **SSH key setup workflow** — Added `Install-SshKey`,
  `Install-SshKeyForSet`, `Test-SshKeyAuth`, `Install-SshKeyOnTarget`,
  `Invoke-SshKeySetup`, and `tools/Install-SshKeys.ps1` to provision and
  verify SSH key authentication across werkcolleges VM sets before TUI
  evaluations start. *(2026-04-21 06:12 UTC)*
- **TUI: PwshSpectreConsole auto-install** — Attempts to install
  `PwshSpectreConsole` automatically when not found, with graceful
  fallback to plain-text `Read-Host` mode. *(2026-04-20)*
- **Lint exclusion** — `PSAvoidOverwritingBuiltInCmdlets` is now
  excluded for test files (needed for `Install-Module` stubs).
  *(2026-04-20)*

### Added

- **TUI: auto-install PwshSpectreConsole** — `Invoke-SelfCheck` now
  attempts `Install-Module PwshSpectreConsole -Scope CurrentUser -Force`
  automatically when the module is missing, instead of just printing a
  warning. Falls back to plain-text mode with a clearer message if the
  install fails. *(2026-04-21)*
- **TUI: explicit target display order** — Added `TargetOrder` array to
  `tui/exam.psd1` (`Linux, DC1, DC2, Client`). `Invoke-SelfCheck` now
  uses this order when building the target list for the selector,
  replacing the non-deterministic hashtable key enumeration. *(2026-04-21)*
- **TUI: arrow-key target selector** — Replaced the numbered
  `Read-Host` toggle loop in `Show-TargetSelector` with an arrow-key
  driven menu. Up/Down moves the cursor, Space toggles the highlighted
  target, Enter confirms. The menu redraws in-place after every
  toggle. A/N still select/deselect all. Added `Invoke-ReadKey` helper
  for testability. *(2026-04-21)*

### Fixed

- **TUI: deselected targets caused SSH errors** — `Copy-ExamWithCategories`
  now removes exam targets that have no remaining categories after filtering,
  matching the behaviour documented in its `.DESCRIPTION`. Previously all
  targets were always cloned, causing `Invoke-StudentEvaluation` to attempt
  SSH connections to deselected VMs (falling back to the placeholder IP
  `self-check`). *(2026-04-21)*
- **TUI: category scores exceeded max** — `Show-ResultsSummary` was
  displaying `NormalizedScore/MaxScore` in the category table (e.g. `20/18`
  when all DNS tests passed on a category with raw max 18). Changed to
  `RawScore/MaxScore` so the displayed score can never exceed the
  maximum. *(2026-04-21)*

### Added

- **TUI Phases 1–5** — Full terminal user interface implementation for
  student self-evaluation. *(2026-04-19)*
  - **`Invoke-SelfCheck`** — Entry point replacing the placeholder.
    Loads TUI config, dot-sources tui/Private/*.ps1, checks Spectre
    availability, prompts for domain name, runs main menu loop.
  - **`tui/exam.psd1`** — TUI configuration with target LAN IPs,
    exam definition path, and domain-name placeholder setting.
  - **`tui/Start-SelfCheck.ps1`** — Standalone launcher script.
  - **Connectivity** — `Test-SshConnection` (TCP port check) and
    `Get-ConnectionFallback` (LAN-first with public fallback prompt).
  - **Exam manipulation** — `Copy-ExamWithCategories` (filter by
    selection) and `Set-DomainNameInExam` (recursive placeholder
    replacement using `List<object>` to prevent array unwrap).
  - **Orchestration** — `Invoke-LocalEvaluation` builds credentials
    from `SAGE_CRED` env var, filters exam, calls
    `Invoke-StudentEvaluation`.
  - **Menus** — `Show-MainMenu`, `Show-TargetSelector`,
    `Show-CategorySelector` with PwshSpectreConsole and plain-text
    fallback modes.
  - **Results display** — `Show-ResultsSummary` (score banner +
    category table), `Show-CategoryDetail` (per-category test list),
    `Show-TestDetail` (expected vs actual + collector data).
  - **History** — `Show-PreviousRuns` (timestamped runs with deltas),
    `Compare-Results` (diff two summaries), `Get-LatestOutputPath`,
    `Import-ResultSummary`.
  - **Settings** — `Show-Settings` (edit exam path, output dir, clear
    results).
  - **Unit tests** — 96 new tests across 14 test files covering all
    TUI functions (686 total tests, 0 failures).

- **`-EvaluationsPath` parameter** — `Invoke-RemoteSetup`,
  `Invoke-RemotePester`, and `Invoke-StudentEvaluation` now accept an
  optional `-EvaluationsPath` parameter.  Defaults to the module's
  built-in `Evaluations/` directory (backward-compatible).  Allows exam
  grading to use private evaluators from a different location.
  *(2026-04-18)*
- **`werkcolleges/exam.psd1`** — Prebuilt werkcolleges exam definition
  covering all 11 categories across 4 targets (Linux, DC1, DC2, Client).
  Uses `<domainname>` placeholders for student-specific domain names;
  the TUI replaces these at runtime. *(2026-04-18)*

### Fixed

- **Temp file cleanup** — `Close-RemoteSession` now removes
  `/tmp/sage-evaluations/` and `/tmp/sage-collectors/` (Linux) or their
  Windows equivalents from the remote VM before closing the PSSession.
  Prevents evaluation scripts and collector data from persisting on
  student VMs between sessions. *(2026-04-18)*

### Added

- **WEBGUI-PLAN.md** — Full implementation plan for server-side web
  application (React + Fastify + Docker Compose) for student
  self-evaluation of werkcolleges labs. Covers architecture, API design,
  security measures, and 6 implementation phases including repo split
  strategy and GitHub Action sync. *(2025-07-16)*
- **TUI-PLAN.md** — Full implementation plan for terminal user interface
  (PwshSpectreConsole) running locally on student VMs. Covers menu
  structure, drill-down results display, dual connectivity fallback,
  and 7 implementation phases. *(2025-07-16)*

---

## [0.9.1] — 2026-04-16

### Added

- **`Invoke-StudentEvaluation`** — new public function encapsulating all
  per-student pipeline work (session creation, setup, collector dispatch,
  Pester evaluation, grade aggregation, and export). Exposed as a public
  function so `ForEach-Object -Parallel` runspaces can call it after
  `Import-Module`; private helpers remain private but are accessible when
  called from within this module function.
- **`Set-SageLogPath`** — thin public pass-through that writes
  `$script:LogPath` into the correct module scope of a freshly-created
  parallel runspace. Eliminates the need for `$global:` variables and
  keeps log wiring explicit and thread-safe.
- **Unit test suite for `Invoke-StudentEvaluation`** — 40 tests covering
  identity field validation, full pipeline success, collector unavailability,
  session failures, `SaveCollectorData` output, export format pass-through,
  `KeyFilePath` and `TargetCredentials` forwarding, `StudentTimeout`
  parameter validation, multi-category execution, and finally-block
  resilience. Total tests: 570.

### Changed

- **`Invoke-Evaluation`** — sequential and parallel paths both now delegate
  all per-student logic to `Invoke-StudentEvaluation`. The orchestrator
  retains exam loading, credential resolution, progress reporting, and
  summary JSON writing; all student-scoped work lives in the delegate.
- **`Invoke-Evaluation.Tests.ps1`** — added dot-sources for
  `Set-SageLogPath.ps1`, `Invoke-StudentEvaluation.ps1`, and
  `Format-CollectorData.ps1`, which are now required by the updated
  `Invoke-Evaluation` at test time.

### Fixed

- **`Write-Log`** — parallel scope handling now captures `$script:LogPath`
  into a local `$LogPathToUse` variable at call time, making the intent
  explicit and consistent across both host-process and parallel-runspace
  invocations.

### Removed

- **`legacy/labs_new_2/`** — obsolete second copy of the lab markdown drafts
  (superseded by `labs_new_sageoptimized_eng/` and
  `labs_new_sageoptimized_nl/`).

---

## [0.9.0] — 2026-04-15

### Added

- **Parallel student processing** — `Invoke-Evaluation` now processes
  students concurrently when `-ThrottleLimit` is greater than 1, using
  `ForEach-Object -Parallel`. Each runspace imports the SAGE module
  independently. Write-Log's named mutex ensures thread-safe JSONL file
  writes. Sequential mode (ThrottleLimit = 1, default) is unchanged.
- **Unified CI workflow** (`.github/workflows/ci.yml`) — consolidates
  PSScriptAnalyzer lint, markdownlint, Pester unit tests, and exam content
  guard into a single GitHub Actions pipeline with job dependencies.
- **Release workflow** (`.github/workflows/release.yml`) — tag-triggered
  (`v*`) pipeline that validates the manifest, runs tests, packages the
  module into a ZIP, and creates a GitHub Release with the artifact.
- **Required modules manifest** (`.github/required-modules.psd1`) — declares
  Pester 5.6.0, PSScriptAnalyzer 1.22.0, ImportExcel 7.8.0, and
  SecretManagement 1.1.2 for CI/CD and development setup.
- **Unit tests for parallel mode** — 5 new tests verifying ThrottleLimit
  parameter validation, default behavior, absence of suppress attribute, and
  parallel-mode log message presence. Total: 530 tests passing.

### Changed

- **`sage.psd1`** — Bumped `ModuleVersion` to `0.9.0`.

---

## [0.8.0] — 2026-04-15

### Added

- **Unit test coverage improvement** — Increased code coverage from 63.51%
  to 90.49%. Created `Format-CollectorData.Tests.ps1` (41 tests covering
  all 11 sub-formatters). Enhanced 12 existing test files with targeted
  branch coverage: Write-Log, Import-Credential, Edit-Grade,
  Invoke-RemotePester, Invoke-RemoteCollector, Invoke-RemoteSetup,
  Invoke-Diagnostic, ConvertTo-GradeSummary, Invoke-Evaluation,
  Test-ExamDefinition, Export-GradeSummary, Copy-File. Total: 525 tests
  passing (up from 449).

### Fixed

- **Documentation audit** — Resolved 13 inconsistencies between docs and
  code. Fixed stale function counts and file listings in ARCHITECTURE.md,
  corrected legacy folder path in CLAUDE.md (`legacy/` not `.legacy/`),
  replaced direct `Invoke-Pester` instructions in README.md with
  `tools/Run-Tests.ps1`, removed phantom `Data/` directory from README.md
  module structure, annotated planned-but-unimplemented items in
  IMPLEMENTATION-PLAN.md, updated Mermaid diagrams with missing functions.

### Refactored

- **CLAUDE.md compliance audit (full-project)** — Added `[CmdletBinding()]`,
  `[Parameter()]`, `$ErrorActionPreference = 'Stop'`, CBH-before-function
  placement, and expandable strings across all `Public/` and `Private/`
  functions. All tool scripts (`Run-Tests.ps1`, `Run-PowerShellLint.ps1`,
  `pre-commit.ps1`) aligned to the same standard.
- **`Edit-Grade.ps1`** — Replaced `ForEach-Object` pipeline with `foreach`
  in the grade recalculation loop.
- **`Format-CollectorData.ps1`** — Added `$ErrorActionPreference = 'Stop'`,
  strong types, and proper param alignment.
- **`ConvertTo-GradeSummary.ps1`** — Fixed PascalCase path separator.
- **Hashtable alignment** — Normalized key-value alignment in test helpers
  across the test suite.

### Changed

- **`sage.psd1`** — Bumped `ModuleVersion` to `0.8.0`.

---

## [0.7.0] — 2026-04-15

### Fixed

- **`tools/Run-Tests.ps1`** — Rewrote as out-of-process Pester runner.
  Pester now runs in a child `pwsh` process with `Start-Process` +
  configurable timeout (default 120s). Parent reads NUnit XML results and
  prints a compact summary table. Crash breadcrumb files survive if the
  child crashes. Memory baseline/delta logging for diagnostics. Adds
  `-TimeoutSeconds` parameter. This eliminates the root cause of VS Code
  extension host crashes: in-process Pester execution in the PSIC.
- **`.vscode/settings.json`** — New workspace settings for crash prevention:
  reduced terminal scrollback (5000), disabled GPU acceleration, file watcher
  exclusions for logs/output/legacy directories.
- **`.vscode/tasks.json`** — Added "Run Tests (safe)" and "Run Tests
  (detailed)" tasks using the out-of-process runner. "Run Tests (safe)" is
  the default test task.
- **`CLAUDE.md`** — Updated test running instructions: always use
  `tools/Run-Tests.ps1`, never invoke `Invoke-Pester` directly in the PSIC.
- **`Tests/Reference/PesterContainerData.Tests.ps1`** — Replaced blocking
  `& pwsh 2>&1 | Out-Null` child process call with `Start-Process` + 30s
  timeout guard. Prevents indefinite hangs that freeze the PowerShell
  Integrated Console and crash the VS Code extension host. Also replaced
  `2>&1 | Out-Null` with proper stream redirection to avoid heavyweight
  ErrorRecord wrapping, and reduced `ConvertTo-Json -Depth` from 10 to 5
  (sufficient for simple test data hashtables).
- **`.github/hooks/pre-commit.ps1`** — Rewrote `Invoke-Step` helper to use
  `Start-Process -RedirectStandardOutput -RedirectStandardError` with a
  120-second timeout guard. Prevents pipe deadlocks that crash VS Code when
  child processes produce enough output to fill the OS pipe buffer in a git
  hook context. Uses proper argument array instead of backtick-escaped string.
- **`tools/Run-MarkdownLint.ps1`** — Same pipe-deadlock fix: replaced bare
  `Start-Process -Wait` with output redirection and 120-second timeout guard.

### Changed

- **CI:** Renamed workflow files: `lint.yml` → `PowerShellLint.yml`,
  `markdown-lint.yml` → `MarkdownLint.yml`, `tests.yml` → `PesterTests.yml`.
  Updated `name:` fields and all in-project references to match.
- **`exams/` → `samples/exams/`** — Moved all exam definitions, output, and
  logs under a `samples/` top-level folder. `samples/output/` and
  `samples/logs/` are gitignored; sample/public exam folders remain tracked.
  `tools/logs/` added to `.gitignore`.
- **`tools/Run-Tests.ps1`** — Rewrote from crash-safe subprocess-per-file
  runner to a single in-process Pester invocation with summary-only terminal
  output. Full output always written to `tools/logs/`. Adds `-Detailed` switch
  to show full Pester output on the terminal; `-Tag` switch for tag filtering.
  Eliminates the N×`pwsh` child processes that were the root cause of VS Code
  extension-host crashes during the pre-commit test step.
- **`tools/Run-Lint.ps1`** — Renamed to `Run-PowerShellLint.ps1` for clarity;
  updated all references in `.vscode/tasks.json`, `.github/hooks/pre-commit.ps1`,
  and `.github/workflows/PowerShellLint.yml`.
- **`CLAUDE.md`** — Added `SAGE_QUICK_HOOK` documentation under Git & Workflow
  section so the rule is co-located with commit conventions.

### Added — Crash resilience and session management

- **`.github/copilot-instructions.md`** — New repo-level Copilot instructions
  enforcing context-budget tracking, HANDOFF.md summaries, one-task-per-conversation
  workflow, and terminal output discipline to prevent context window exhaustion.
- **`CLAUDE.md`** — Added "One task per conversation" and "Terminal output
  discipline" rules under AI Collaboration Heuristics.
- **`Public/New-RemoteSession.ps1`** — SSH keepalive defaults
  (`ServerAliveInterval=15`, `ServerAliveCountMax=3`) detect dead connections
  within ~45s instead of hanging indefinitely. Caller-supplied `SshOptions`
  override defaults.
- **`Public/Invoke-Evaluation.ps1`** — Per-student timeout guard
  (`StudentTimeout` parameter, default 600s, range 60–3600). Checks elapsed
  time before each major remote operation. Stale PSSessions in
  Broken/Disconnected state are cleaned up before the student loop starts.
- **`.devcontainer/postStart.ps1`** — New post-start cleanup script kills
  orphaned SSH processes and stale PSSessions on every container start.
  Registered as `postStartCommand` in `devcontainer.json`.
- **Tests** — 8 new unit tests: 2 for SSH keepalive, 4 for `StudentTimeout`
  parameter validation, 2 for stale session cleanup.
- **`.github/hooks/pre-commit.ps1`** — Quick hook mode via `SAGE_QUICK_HOOK=1`
  environment variable. When set, skips heavy checks (lint, markdown lint,
  unit tests) that CI enforces on push. Security-critical checks (path guard,
  secret scan, manifest) always run. Prevents VS Code crashes caused by
  pre-commit hook spawning multiple pwsh processes during micro-commit
  workflows.
- **`.github/copilot-instructions.md`** — Added Git Commit Discipline section
  documenting quick hook mode, micro-commit workflow, and push strategy.

### Fixed — Secret scanner false positive on PowerShell variable references

- **`tools/Run-SecretScan.ps1`** — The "Hard-coded secret" regex matched
  PowerShell variable interpolations like `Secret=$Secret` in test stub throw
  messages, blocking commits with false positives. Added `(?!\$)` negative
  lookahead after the value delimiter to exclude variable references.

---

## [0.6.0] — 2026-04-14

### Added — Phase 6: Remaining Subjects (AD, DHCP, FileServer, GPO, BashHistory, Docker, Nginx, Apache, IIS)

- **Collectors/Invoke-AdCollector.ps1** — Active Directory collector: domain info,
  OUs, users, groups, computers. Checks domain membership and AD-DS module.
- **Collectors/Invoke-DhcpCollector.ps1** — DHCP collector: server authorization,
  scopes, exclusion ranges, scope options, reservations. Checks DhcpServer module.
- **Collectors/Invoke-FileServerCollector.ps1** — File Server collector: SMB shares,
  NTFS permissions (Get-Acl), share-level access rules.
- **Collectors/Invoke-GpoCollector.ps1** — GPO collector: XML report parsing for
  software installation, scripts, folder redirection, drive maps, local users/groups,
  administrative policies, links, and permissions.
- **Collectors/Invoke-BashHistoryCollector.ps1** — Bash history and cmd.log collector:
  epoch timestamp parsing, exam time window filtering, CSV log parsing.
- **Collectors/Invoke-DockerCollector.ps1** — Docker collector: images, containers,
  Dockerfile discovery, docker-compose.yml discovery.
- **Collectors/Invoke-NginxCollector.ps1** — Nginx collector: service status,
  sites-enabled/available, config file parsing, index.html content.
- **Collectors/Invoke-ApacheCollector.ps1** — Apache (httpd) collector: service status,
  httpd.conf parsing, IncludeOptional, VirtualHost/ServerName/DocumentRoot extraction.
- **Collectors/Invoke-IisCollector.ps1** — IIS collector with PS 5.1 fallback: tries
  IISAdministration on PS 7 first, falls back to `powershell.exe` for PS 5.1.
  Collects websites, bindings, virtual directories, and app pools.
- **Evaluations/Ad.Tests.ps1** — AD evaluation: domain level, computers, OUs, users,
  group membership assertions.
- **Evaluations/Dhcp.Tests.ps1** — DHCP evaluation: server authorization, scopes,
  exclusions, options, reservations.
- **Evaluations/FileServer.Tests.ps1** — File Server evaluation: share existence,
  NTFS permissions, share-level access.
- **Evaluations/Gpo.Tests.ps1** — GPO evaluation: existence, links, software
  installation, administrative policies, drive mappings, scope settings.
- **Evaluations/BashHistory.Tests.ps1** — Bash history evaluation: keyword matching,
  cmd.log keywords, network origin validation.
- **Evaluations/Docker.Tests.ps1** — Docker evaluation: images, containers,
  Dockerfiles, docker-compose services.
- **Evaluations/Nginx.Tests.ps1** — Nginx evaluation: service properties, virtual
  hosts, website content.
- **Evaluations/Apache.Tests.ps1** — Apache evaluation: service properties, virtual
  hosts, website content.
- **Evaluations/Iis.Tests.ps1** — IIS evaluation: websites, bindings, virtual
  directories, app pools.
- **Tests/Unit/** — Unit tests for all 9 new collectors (98 tests total):
  Invoke-AdCollector (14), Invoke-DhcpCollector (14), Invoke-FileServerCollector (10),
  Invoke-GpoCollector (13), Invoke-BashHistoryCollector (7), Invoke-DockerCollector (8),
  Invoke-NginxCollector (8), Invoke-ApacheCollector (8), Invoke-IisCollector (13).
- **exams/_example/exam.psd1** — Updated with sample categories for all 9 new
  subjects plus the existing GeneralConfig and DNS categories.

### Fixed — PSScriptAnalyzer warnings for automatic variable assignments

- **Collectors/Invoke-BashHistoryCollector.ps1** — Renamed `$Pwd` to `$WorkDir`
  to avoid assignment to the automatic `$PWD` variable.
- **Evaluations/BashHistory.Tests.ps1** — Renamed `$Host` to `$RemoteAddr`
  to avoid assignment to the readonly automatic `$Host` variable.
- **Tests/Unit/Invoke-IisCollector.Tests.ps1** — Added suppression for `$MockPool`
  used across Pester scope boundaries.

### Fixed — GDPR: remove score from grade-summary log message

- **Public/Invoke-Evaluation.ps1** — added `$script:LogPath` initialization so
  `Write-Log` actually writes JSONL diagnostic entries to a file (was previously
  always a no-op because the path was never set).  The log is written to
  `$env:TEMP` during the run and moved to `<module-root>/logs/` at completion to
  prevent cloud-sync tools (e.g. Proton Drive) from intercepting the in-progress
  file and causing conflicts or truncation.  Log filename format:
  `yyyyMMdd-HHmmss-<exam-name>.jsonl`.

### Fixed — Write-Log: retry on IOException for cloud-synced log paths

- **Private/Write-Log.ps1** — file-append now retries up to 3 times (100 ms
  between attempts) on `IOException`, handling transient file locks from
  cloud-sync daemons without silently dropping log entries.

### Fixed — PSScriptAnalyzer false positives in test and collector files

- **Tests/Unit/Invoke-DnsCollector.Tests.ps1**,
  **Tests/Unit/Invoke-GeneralConfigCollector.Tests.ps1** — Added script-level
  `[Diagnostics.CodeAnalysis.SuppressMessageAttribute]` with an empty `param()`
  block to suppress `PSUseDeclaredVarsMoreThanAssignments` for `$Sut`, which is
  assigned in `BeforeAll` and consumed inside `It` blocks — a cross-block usage
  pattern that PSScriptAnalyzer cannot trace.
- **Collectors/Invoke-DnsCollector.ps1**,
  **Collectors/Invoke-GeneralConfigCollector.ps1** — Suppressed
  `PSReviewUnusedParameter` for `$Variables`; the parameter is part of the
  collector contract (reserved for future category-level filtering) and must
  remain in the signature.
- **Evaluations/Dns.Tests.ps1**, **Evaluations/GeneralConfig.Tests.ps1** —
  Suppressed `PSReviewUnusedParameter` for `$ExamVariables` and `$CollectedData`
  (Pester Container Data parameters accessed via closure) and
  `PSUseDeclaredVarsMoreThanAssignments` for `$ReviewContextMap` (consumed
  dynamically by `Edit-Grade`).
- **Private/Invoke-RemoteSetup.ps1** — Suppressed
  `PSUseUsingScopeModifierInNewRunspaces` for `$env:TEMP` and
  `$env:ProgramFiles` inside `Invoke-Command` scriptblocks; these intentionally
  resolve on the **remote** VM — adding `$using:` would incorrectly send local
  host values.

### Fixed — CLIXML deserialization of Pester test results

- **Private/Invoke-RemotePester.ps1** — Pester `Test` objects do not survive
  PowerShell Remoting CLIXML serialization intact (they serialize as their
  `ToString()` representation, e.g. `[+] Hostname should be DC1`).  The
  `Invoke-Command` scriptblock now extracts all required test data into plain
  hashtables **on the remote side** before the result crosses the remoting
  boundary.  Returned structure: `{ PassedCount, FailedCount, SkippedCount,
  TotalCount, Duration, Tests = @(@{ ExpandedName, Name, Result, Context,
  Data, ErrorMessage }) }`.
- **Private/ConvertTo-GradeSummary.ps1** — Updated to consume the new plain
  hashtable test structure: uses `$Test.Result` (string) for pass/fail,
  `$Test.Data` (hashtable) for `PassGrade`, `$Test.Context` (pre-extracted
  string) instead of `Block.Name` hierarchy traversal, and `$Test.ErrorMessage`
  (pre-extracted string) instead of `$Test.ErrorRecord.Exception.Message`.

### Fixed — SSH key-auth pipeline compatibility

- **Public/New-RemoteSession.ps1** — Removed guard that incorrectly blocked
  `Credential` without `KeyFilePath`; SSH transport does not support
  `-Credential` in `New-PSSession` so the parameter is accepted for auditing
  only and not forwarded to the session factory.
- **Public/Test-ExamDefinition.ps1** — Downgraded missing-credential check from
  hard validation error to `Write-Verbose` hint; targets authenticating via SSH
  key do not require a vault secret.
- **Public/Invoke-Evaluation.ps1** — Wrapped credential loading in `try/catch`;
  when `KeyFilePath` is provided and the vault secret is absent the pipeline
  logs a warning and continues rather than throwing.

### Added — Live end-to-end test exam

- **exams/live-test/exam.psd1** — New exam targeting two Azure-hosted Windows
  Server VMs (DC1 port 30022, DC2 port 40022).  Covers four categories:
  General Configuration DC1/DC2 and DNS DC1/DC2.  Uses SSH key auth; includes
  one intentional failing test (forwarder `8.8.8.8` not configured on DC1) to
  validate partial scoring.
- **exams/live-test/roster.csv** — Single-student roster for the live test exam.
- **tools/Run-LiveTest.ps1** — Convenience script that invokes `Invoke-Evaluation`
  with the live exam definition, avoiding shell string-escaping for paths.

### Changed

- **CI:** Bumped `actions/checkout` from `v4` to `v6` in all three workflows (`PowerShellLint.yml`, `MarkdownLint.yml`, `PesterTests.yml`).
- **CI:** Bumped `DavidAnson/markdownlint-cli2-action` from `v19` to `v23` in `MarkdownLint.yml`.

---

## [0.5.0] — 2026-03-31

### Added — Phase 5: GeneralConfig & DNS Subjects

- **Collectors/Invoke-GeneralConfigCollector.ps1** — new; collects hostname, static IP addresses, prefix length, gateway, and DNS server configuration from a remote Windows VM. Returns a CollectorResult-compatible hashtable.
- **Collectors/Invoke-DnsCollector.ps1** — new; collects DNS zones, resource records (A, AAAA, CNAME, MX, NS, PTR, SRV, SOA, TXT), and forwarders. Checks DNS role availability first. Flattens all complex objects to plain strings for safe CLIXML deserialization.
- **Evaluations/GeneralConfig.Tests.ps1** — new; evaluation test library for general server configuration: hostname, static IP, prefix length, gateway, DNS servers. Data-driven via `$ExamVariables` and `$CollectedData`. Includes `$ReviewContextMap` for `Edit-Grade`.
- **Evaluations/Dns.Tests.ps1** — new; evaluation test library for DNS configuration: forward/reverse zones, A/CNAME/MX/NS/PTR records, forwarders. Handles trailing-dot normalisation for FQDN comparisons. Includes `$ReviewContextMap` for `Edit-Grade`.
- **Tests/Unit/Invoke-GeneralConfigCollector.Tests.ps1** — new; unit tests for the GeneralConfig collector: successful collection, IP failure path, result structure validation.
- **Tests/Unit/Invoke-DnsCollector.Tests.ps1** — new; unit tests for the DNS collector: role not installed, query failure, successful collection with zones/records/forwarders, partial failure, result structure.
- **sage.psd1** — bumped `ModuleVersion` to `0.5.0`.

---

## [0.4.0] — 2026-03-30

### Added — Phase 4: Orchestrator

- **Public/Invoke-Evaluation.ps1** — new; main pipeline orchestrator that loads an exam definition, reads a CSV roster, and for each student: connects to all targets via SSH, runs setup/collector/Pester per category, aggregates grades via Get-GradeSummary, exports results, and writes a GDPR-compliant `_summary.json` (counts, timing, errors — no grades). Supports `KeyFilePath` pass-through and per-target credential resolution.
- **Public/Invoke-Diagnostic.ps1** — new; pre-flight connectivity diagnostics for a single target: TCP port reachability, SSH session establishment, remote PowerShell version check, and required module availability. Returns a `Sage.DiagnosticResult` with cascading step skips on failure.
- **Public/Invoke-SelfCheck.ps1** — new; stub for future student self-evaluation feature (throws `NotImplementedException`).
- **Tests/Unit/Invoke-Evaluation.Tests.ps1** — new; 23 unit tests covering full pipeline, collector unavailable path, student error handling, empty roster, missing fields, credential resolution, KeyFilePath pass-through, export formats, and student folder naming.
- **Tests/Unit/Invoke-Diagnostic.Tests.ps1** — new; 10 unit tests covering all-pass scenario, TCP unreachable, SSH failure, missing modules, no dependencies, timestamp, and session cleanup. Uses deterministic TcpListener approach.
- **Tests/Unit/Invoke-SelfCheck.Tests.ps1** — new; 2 unit tests verifying NotImplementedException is thrown.
- **sage.psd1** — bumped `ModuleVersion` to `0.4.0`; added `Invoke-Evaluation`, `Invoke-Diagnostic`, `Invoke-SelfCheck` to `FunctionsToExport`.
- **sage.psm1** — added Phase 4 exports to `Export-ModuleMember`.

### Added — Maximise unit test coverage

- **Tests/Unit/Close-RemoteSession.Tests.ps1** — new; covers session closure, idempotent handling, error paths, WhatIf, and multi-session input.
- **Tests/Unit/ConvertTo-NormalizedGrade.Tests.ps1** — new; covers all grade-normalization branches and edge cases.
- **Tests/Unit/Copy-File.Tests.ps1** — new; covers remote directory creation, Copy-Item call, and parameter validation.
- **Tests/Unit/Import-Credential.Tests.ps1** — new; covers SecretManagement and PSCredential retrieval, fallback, and error handling.
- **Tests/Unit/Invoke-RemoteCollector.Tests.ps1** — new; covers collector dispatch, CollectorResult construction, and remote error paths.
- **Tests/Unit/Invoke-RemotePester.Tests.ps1** — new; covers evaluation execution, file copying, logging, and platform-specific paths.
- **Tests/Unit/Invoke-RemoteSetup.Tests.ps1** — new; covers module install, local-fallback copy, and missing-module termination.
- **Tests/Unit/New-CollectorResult.Tests.ps1** — new; covers factory output, PSTypeName stamping, defaults, and validation.
- **Tests/Unit/New-RemoteSession.Tests.ps1** — new; covers SSH session creation, retry logic, credential handling, and MaxRetries exhaustion.
- **Tests/Unit/New-RemoteSessionObject.Tests.ps1** — new; covers factory output, metadata properties, ConnectedAt, and parameter validation.
- **Tests/Unit/Set-Credential.Tests.ps1** — new; covers SecretManagement vault registration, secret storage, and error handling.

### Removed — Delete duplicate source and test files

- **Public/Get-GradeResults.ps1** — removed; exact duplicate of `Get-GradeSummary.ps1` (leftover from rename).
- **Public/Export-GradeResults.ps1** — removed; exact duplicate of `Export-GradeSummary.ps1` (leftover from rename).
- **Tests/Unit/Get-GradeResults.Tests.ps1** — removed; exact duplicate of `Get-GradeSummary.Tests.ps1`.
- **Tests/Unit/Export-GradeResults.Tests.ps1** — removed; exact duplicate of `Export-GradeSummary.Tests.ps1`.
- **tools/Transform-ParamBlocks.ps1** — removed; one-time utility no longer needed.

### Changed — Consolidate test runners into tools/Run-Tests.ps1

- **tools/Run-Tests-Safe.ps1 → tools/Run-Tests.ps1** — renamed the crash-safe per-file Pester runner; removed the old thin subprocess wrapper that previously had the same name. The `-Log` switch (off by default) now gates all file logging, system-info snapshots, and memory tracking; without it the script only prints to the console.
- **CLAUDE.md** — added explicit rule: always use `tools/Run-Tests.ps1` for running Pester tests locally; never run `Tests/Invoke-Tests.ps1` directly in the VS Code terminal.

### Added — Enhanced pre-commit hook (6-step quality gate)

- **.github/hooks/pre-commit.ps1** — rewrote hook to run six ordered checks: (1) sensitive path guard, (2) content secret scan, (3) module manifest validation, (4) PSScriptAnalyzer lint, (5) markdown lint, (6) unit tests. Each step is labelled and fails fast on first violation.
- **.github/hooks/pre-commit** — simplified bash shim; all logic delegated to `pre-commit.ps1`; added `pwsh` availability check.
- **tools/Run-SecretScan.ps1** — new tool that scans staged Git diff additions for common credential patterns (hard-coded passwords, API keys, tokens, PEM private key headers, connection string credentials, plain-text `ConvertTo-SecureString` calls).
- **tools/Run-MarkdownLint.ps1** — new tool that invokes `markdownlint-cli2` over all `*.md` files (excluding `legacy/`); soft-fails with a warning and install hint when the tool is not on PATH.
- **.markdownlint.jsonc** — new markdownlint configuration; disables MD013 (line length), MD024 (duplicate headings, needed for CHANGELOG), MD033 (inline HTML), and MD041 (first-line heading).

### Fixed — PSScriptAnalyzer lint violations in tool scripts

- **tools/Run-SecretScan.ps1** — renamed local variable `$Matches` to `$MatchedLines` (was shadowing the `$Matches` automatic variable; `PSAvoidAssignmentToAutomaticVariable`).
- **tools/Run-Tests-Safe.ps1** — renamed local helper `Write-Log` to `Write-RunLog` to avoid shadowing the built-in cmdlet (`PSAvoidOverwritingBuiltInCmdlets`).
- **tools/Transform-ParamBlocks.ps1** — renamed internal function `Transform-Line` to `Update-Line` to use an approved PowerShell verb (`PSUseApprovedVerbs`).

### Refactored — Move [type] adjacent to $Name in all param blocks

- **All Public/ and Private/ functions** — updated param block formatting so that `[type]` is always directly adjacent to `$ParameterName` with one space (`[type] $Name`); alignment padding moved to before `[type]` instead of between `[type]` and `$Name`; `$` column unchanged at ~102 per block; matches updated CLAUDE.md convention.
- **CLAUDE.md** — updated param block formatting rule and fallback rule to document the `[type] $Name` adjacent style.

### Refactored — Inline param block style (full-project)

- **All Public/ and Private/ functions** — reformatted multi-line parameter block declarations to single-line-per-parameter inline style (`[Parameter(...)][Validator(...)][type]<spaces>$Name`), with `$` signs right-aligned to column 100; matches the style established in `New-RemoteSessionObject` and `New-GradeResult`; functions affected: `Close-RemoteSession`, `Edit-Grade`, `Export-GradeSummary`, `Get-GradeSummary`, `Import-Credential`, `Import-ExamDefinition`, `New-RemoteSession`, `Set-Credential`, `Test-ExamDefinition`, `ConvertTo-GradeSummary`, `Copy-File`, `Invoke-RemoteCollector`, `Invoke-RemotePester`, `Invoke-RemoteSetup`, `Write-Log`

### Added — Architecture documentation

- **ARCHITECTURE.md** — added comprehensive module architecture reference with structure overview, type hierarchy, function inventory, and Mermaid diagrams for data flow, dependencies, session lifecycle, and end-to-end evaluation pipeline
- **REFACTORING-PLAN.md** — updated high-level design section to Mermaid-based architecture diagram aligned with current module layout and terminology

### Changed — Hashtable formatting in tests

- **Unit tests** — reformatted inline and nested hashtable literals in `ConvertTo-GradeSummary.Tests.ps1`, `Edit-Grade.Tests.ps1`, `Export-GradeSummary.Tests.ps1`, `Import-ExamDefinition.Tests.ps1`, `New-GradeResult.Tests.ps1`, and `Test-ExamDefinition.Tests.ps1` to improve readability and align with the one-key-per-line style rule

### Refactored — CLAUDE.md compliance (full-project audit)

- **Backtick elimination** — replaced all backtick line-continuations with splatting (`$params = @{…}; Cmd @params`) across all `Public/`, `Private/`, and `Tests/` files; curly-brace notation (`${Var}:`) used where backtick escaped a colon in strings
- **Legacy `$EvalSession` rename** — `Private/Invoke-RemoteCollector.ps1`, `Invoke-RemotePester.ps1`, `Invoke-RemoteSetup.ps1`: renamed parameter and all body references to `$RemoteSession`
- **Stale `*-Eval*` comment fixes** — `Private/ConvertTo-GradeSummary.ps1`, `ConvertTo-NormalizedGrade.ps1`, `New-GradeResult.ps1`: updated internal comments referencing old `Edit-EvalGrade` / `Get-EvalResults` names
- **Help block completeness** — added `.PARAMETER` sections to `New-CollectorResult.ps1`, `New-GradeResult.ps1`, `New-RemoteSessionObject.ps1`; added `.EXAMPLE` blocks to all nine private functions that were missing them
- **Large call splatting** — converted 15-param `New-GradeResult` call in `ConvertTo-GradeSummary.ps1`, 7-param `New-RemoteSessionObject` call in `New-RemoteSession.ps1`, and 5-param `Copy-Item` call in `Invoke-RemoteSetup.ps1` to explicit splat hashtables per CLAUDE.md Priority 4 rule

### Fixed — Documentation audit (code-vs-docs sync)

- **README.md** — `EvalVault` → `SageVault`; `Edit-EvalGrade` → `Edit-Grade`; `Write-EvalLog` → `Write-Log`; backtick line-continuation → splatting in example; removed duplicate `Evaluations/` line; fixed broken fence marker
- **IMPLEMENTATION-PLAN.md** — 18 stale references updated: `New-EvalResult` → `New-GradeResult`; `Sage.EvalResult` → `Sage.TestResult`; `New-EvalSessionObject` → `New-RemoteSessionObject`; `Sage.EvalSession` → `Sage.RemoteSession`; `Check.CollectorResult` → `Sage.CollectorResult`; `Edit-EvalGrade` → `Edit-Grade`; `Export-EvalResults` → `Export-GradeSummary`; `Write-EvalLog` → `Write-Log`; `EvalVault` → `SageVault`; backtick examples → splatting; test file names aligned with codebase
- **REFACTORING-PLAN.md** — updated §2 diagram to v3 (removed `Classes/`, replaced 11 `Get-*Data` functions with `Invoke-RemoteCollector`, renamed collectors `Get-*Collector` → `Invoke-*Collector`); updated §4 module tree (Private + Tests sections); `Edit-EvalGrade` → `Edit-Grade`; `Export-EvalResults` → `Export-GradeSummary`; `Write-EvalLog` → `Write-Log`; `EvalVault` → `SageVault`; `Import-EvalCredential` → `Import-Credential`; removed `ValidateSet('SSH', 'WinRM')`; `Invoke-EvalDiagnostic` → `Invoke-Diagnostic`; replaced class definition with PSCustomObject factory pattern; removed `ConvertTo-OrderedDictionary` from Phase 1

### Removed

- **HANDOFF.md** — obsolete context-reset file (one-time use, content already applied)
- **EVAL-TERMINOLOGY-AUDIT.md** — obsolete audit (rename changes already applied to codebase)
- **LEGACY-TERMS-COMPREHENSIVE-AUDIT.md** — obsolete audit (rename changes already applied to codebase)

---

## [0.3.0] — 2026-03-17

### Added — Phase 3: Export + Override

#### Public — Grading & Output

- `Public/Get-GradeSummary.ps1` — aggregates `Sage.TestResult[]` → `Sage.StudentGradeSummary`; per-category `RawScore`/`MaxScore`/`NormalizedScore`; overall `TotalScore`; pipeline input support
- `Public/Export-GradeSummary.ps1` — exports `Sage.StudentGradeSummary` to JSON (always), CSV and Excel (optional, `ImportExcel`); `-WhatIf` support; returns written file paths
- `Public/Edit-Grade.ps1` — interactive manual grade override; reads `ReviewContextMap` from exam definition; produces `ManualOverrideGrade` + `ManualOverrideReason` on `Sage.TestResult`

#### Public — Secrets

- `Public/Set-Credential.ps1` — stores a `PSCredential` in a `Microsoft.PowerShell.SecretManagement` vault
- `Public/Import-Credential.ps1` — retrieves a `PSCredential` from a vault by secret name

#### Tests — Phase 3

- `Tests/Unit/Get-GradeSummary.Tests.ps1` — 30 tests: type names, single/multi-category scores, override counting, pipeline, empty input
- `Tests/Unit/Export-GradeSummary.Tests.ps1` — 25 tests: JSON structure, ISO 8601 GradedAt, WhatIf, CSV columns, Excel sheets, multiple formats
- `Tests/Unit/Edit-Grade.Tests.ps1` — interactive override unit tests

#### Tooling

- `tools/Run-Tests-Safe.ps1` — crash-safe per-file Pester runner; isolates each `.Tests.ps1` in its own `pwsh` subprocess; logs system info, memory deltas, and stdout/stderr to disk so test output survives VS Code crashes

### Fixed

- `Public/Export-GradeSummary.ps1` — `$summaryRows += [PSCustomObject]@{...}` threw `op_Addition` when only one category was present (single `ForEach-Object` output is a bare object, not an array); fixed by wrapping with `@()`; replaced `continue` with `break` in the Excel guard for clearer flow control
- `Tests/Unit/Get-GradeSummary.Tests.ps1` — `[double] $FinalGrade = $null` in `New-TestResult` helper silently coerced `$null` → `0.0`, making the null-check always true and `FinalGrade` always 0; fixed by using `[object]`
- `Tests/Unit/Export-GradeSummary.Tests.ps1` — `ConvertFrom-Json` in PowerShell 7 auto-converts ISO 8601 date strings to `DateTime` objects; `Should -Match` then used the locale-specific `ToString()` representation, not the ISO string; fixed by reading the raw JSON string directly

### Changed

- `sage.psd1` — bumped `ModuleVersion` to `0.3.0`; added Phase 3 exports
- `sage.psm1` — added Phase 3 `Export-ModuleMember` entries

---

## [0.2.0] — 2026-03-05

### Added — Phase 2: SSH Pipeline

#### Private — Session layer

- `Private/New-RemoteSessionObject.ps1` — `[PSTypeName('Sage.RemoteSession')]` factory; wraps `PSSession` with metadata (TargetName, HostName, Port, Platform)
- `Private/Invoke-RemoteSetup.ps1` — installs Pester on remote VM and copies collector scripts
- `Private/Invoke-RemoteCollector.ps1` — generic dispatcher: runs any collector `.ps1` on remote VM, returns `Sage.CollectorResult`
- `Private/Invoke-RemotePester.ps1` — executes Pester evaluation tests on remote VM, returns CLIXML result stream
- `Private/New-CollectorResult.ps1` — `[PSTypeName('Sage.CollectorResult')]` factory
- `Private/ConvertTo-GradeSummary.ps1` — maps `Pester.Result` → `Sage.TestResult[]`; extracts `PassGrade`, `ActualValue`, `ExpectedValue`, `ReviewContextName`
- `Private/New-GradeResult.ps1` — `[PSTypeName('Sage.TestResult')]` factory
- `Private/Copy-File.ps1` — copies individual files to remote VM via `scp`
- `Private/Write-Log.ps1` — GDPR-compliant structured logging; console streams + JSONL file; thread-safe mutex append
- `Private/ConvertTo-NormalizedGrade.ps1` — scales raw score to /20 format

#### Public — Session management & exam loading

- `Public/New-RemoteSession.ps1` — creates SSH `PSSession` to target VM; retry logic, configurable ssh options
- `Public/Close-RemoteSession.ps1` — destroys `PSSession` and cleans remote temp files; `-WhatIf` support
- `Public/Import-ExamDefinition.ps1` — loads and validates `exam.psd1` via `Import-PowerShellDataFile`
- `Public/Test-ExamDefinition.ps1` — standalone schema validation for `exam.psd1`

#### Tests — Phase 2

- `Tests/Unit/ConvertTo-GradeSummary.Tests.ps1`
- `Tests/Unit/Import-ExamDefinition.Tests.ps1`
- `Tests/Unit/New-GradeResult.Tests.ps1`
- `Tests/Unit/Test-ExamDefinition.Tests.ps1`
- `Tests/Unit/Write-Log.Tests.ps1`
- `Tests/Invoke-Tests.ps1` — safe Pester runner that catches unhandled errors
- `tools/Run-Tests.ps1` — fires a subprocess, redirects stdout/stderr to timestamped log files
- `tools/Run-Remote-Smoke.ps1` — live SSH smoke tests: Linux (port 20022) + Windows (port 30022) + non-existent host

## [0.1.0] — 2026-03-02

### Added — Phase 1 Scaffold

#### Module infrastructure

- `SAGE.psd1` — module manifest (`ModuleVersion = '0.1.0'`, `PowerShellVersion = '7.5'`)
- `SAGE.psm1` — dot-source loader for `Public/` and `Private/` with explicit `Export-ModuleMember`

#### Private — Type factories

- `Private/New-EvalResult.ps1` — `[PSTypeName('Check.EvalResult')]` factory (Decision #10)
- `Private/New-EvalSessionObject.ps1` — `[PSTypeName('Check.EvalSession')]` factory
- `Private/New-CollectorResult.ps1` — `[PSTypeName('Check.CollectorResult')]` factory

#### Private — Core utilities

- `Private/ConvertTo-NormalizedGrade.ps1` — scales raw score to /20 via `[Math]::Round`
- `Private/Write-EvalLog.ps1` — GDPR-compliant structured logging; console streams + JSONL file; thread-safe mutex append

#### Public — Validation

- `Public/Test-ExamDefinition.ps1` — deep schema validation for `exam.psd1`; supports `-PassThru` for non-terminating error mode

#### Tests — Phase 1

- `Tests/Unit/New-EvalResult.Tests.ps1`
- `Tests/Unit/Write-EvalLog.Tests.ps1`
- `Tests/Unit/Test-ExamDefinition.Tests.ps1`
- `Tests/Reference/PesterContainerData.Tests.ps1` — validates Pester Container Data scoping end-to-end (Decision #4)

#### Supporting files

- `.gitignore` — protects exam content, results, logs, and secrets
- `.github/hooks/pre-commit` (bash) + `.github/hooks/pre-commit.ps1`
- `.templates/exam.psd1.template` — boilerplate exam definition with all sections
- `.templates/collector.ps1.template` — boilerplate collector script
- `exams/_example/exam.psd1` — public example covering Docker, GeneralConfig and DNS
- `CHANGELOG.md`, `README.md`

[0.8.0]: https://github.com/GeertCoulommier/sage-private/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/GeertCoulommier/sage-private/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/GeertCoulommier/sage-private/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/GeertCoulommier/sage-private/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/GeertCoulommier/sage-private/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/GeertCoulommier/sage-private/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/GeertCoulommier/sage-private/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/GeertCoulommier/sage-private/releases/tag/v0.1.0
