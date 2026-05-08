# AgentSkills

A curated collection of **multi-CLI AI skills and agents** — drop-in capabilities for [Claude Code](https://docs.claude.com/claude-code), [OpenCode](https://opencode.ai), [Kilo Code](https://kilo.ai), [OpenAI Codex CLI](https://developers.openai.com/codex), and [Gemini CLI](https://geminicli.com). Each agent is authored once in a CLI-agnostic base form and rendered to each CLI's native format at install time; you pick which CLI(s) to install for.

The tree is split into **global-scope** (user-level, installed once per CLI into each CLI's global directory — available in every repo) and **repo-scope** (per-repo, installed by [`skill-sync`](skills/global-scope/skill-sync/SKILL.md) into each CLI's per-repo directory only when the toolchain matches). Instead of installing everything globally and hoping the harness picks the right one, repo-scope artifacts land only in the repos that actually need them.

## What's in here

```
skills/
  global-scope/      # workflow utilities that work on any repo (canonical for shared skills)
  repo-scope/        # toolchain-specific; pulled in by skill-sync
agents/
  base/              # canonical agent source (CLI-agnostic: agent.md + metadata.yaml)
    global-scope/    # general-purpose agents
    repo-scope/      # 0 agents today; reserved
  renderers/         # canonical per-CLI renderers: claude.sh, opencode.sh, kilo.sh, gemini.sh, codex.sh
install.sh           # all-in-one installer: --for <cli>[,<cli>...]
ato/                 # ATO (NIST 800-53) collection — independently shareable subset
  skills/            # ATO skills (canonical) + auth-* mirrors (kept in sync)
  agents/            # ATO agents + bundled renderer mirrors (kept in sync)
  install.sh         # ATO-only installer (writes its own manifest)
  README.md          # ATO user guide
bin/
  sync-ato.sh        # propagate canonical → ato/ mirrors; --check for CI/precommit
  install-hooks.sh   # opt-in: sets core.hooksPath = .githooks
.githooks/
  pre-commit         # runs sync-ato.sh --check
.github/workflows/
  sync-check.yml     # runs sync-ato.sh --check on every PR
CLAUDE.md            # conventions for contributors editing this repo
```

The ATO collection lives under its own `ato/` subtree and ships with its own dedicated installer. The folder is **self-contained** — copy it anywhere (separate repo, internal share) and `bash ato/install.sh` works the same way. See [ato/README.md](ato/README.md) for the full ATO user guide.

**Source-of-truth model.** Everything ATO-specific (including `auth-config` and `auth-interview`, since ATO is their only current consumer) lives canonically under `ato/`. The only thing mirrored is the per-CLI renderers — canonical at `agents/renderers/`, copies at `ato/agents/renderers/` so the standalone ATO bundle can render agents without the parent repo. Edit the canonical renderer, run `bin/sync-ato.sh`, commit. The pre-commit hook and CI both run `bin/sync-ato.sh --check`, so drift fails fast.

## CLI support

| CLI | Global dir | Per-repo dir | Agent file |
|---|---|---|---|
| Claude Code | `~/.claude/` | `<repo>/.claude/` | `<name>.md` |
| OpenCode | `~/.config/opencode/` | `<repo>/.opencode/` | `<name>.md` |
| Kilo Code | `~/.config/kilo/` | `<repo>/.kilo/` | `<name>.md` |
| OpenAI Codex | `~/.codex/` | `<repo>/.codex/` | `<name>.toml` + `AGENTS.md` |
| Gemini CLI | `~/.gemini/` | `<repo>/.gemini/` | `<name>.md` |
| Pi (pi.dev) | `~/.pi/agent/` | `<repo>/.pi/` | _(skills only)_ |
| Cursor | `~/.cursor/` | `<repo>/.cursor/` | `<name>.mdc` |

**Native Windows support.** `install.ps1` and `ato/install.ps1` are the Windows entry points: they detect Git Bash, offer to install Git for Windows (via `winget` → Chocolatey → manual fallback) if missing, then forward to the bash installers. CLI directories follow the same convention with `~` resolving to `%USERPROFILE%`.

Claude Code additionally gets skills (`~/.claude/skills/` + `<repo>/.claude/skills/`); the other CLIs handle skill-like content differently and are agent-only today.

**Skills** are stateless step-by-step guides the Claude Code harness surfaces by description. They're how you teach Claude Code "when the user says X, do Y."

**Agents** are isolated-context subprocesses invoked via the `Agent` tool. They handle multi-step investigations without polluting the parent conversation.

**Scope-selection rule.** A skill / agent lives in `global-scope/` if it works on any repo regardless of language (`deep-review`, `branch-review`, `bdd-audit`, `coverage-audit`, `repo-health`, `merge-sprint`, `skill-sync`, `skill-interview`). It lives in `repo-scope/` if it is meaningful only when a specific toolchain or target is present. The auth skills (`auth-config`, `auth-interview`) live under `ato/` today since ATO is their only consumer; they'd be promoted to `skills/global-scope/` if a non-ATO consumer appears.

Some skills are **thin stubs paired with an agent** — the skill triggers on user intent (preserving slash-command discoverability like `/branch-review`); the agent does the work in its own context. Paired stubs and their agents always live in matching scopes:

| Stub skill | Agent | Scope |
|---|---|---|
| `deep-review` | `deep-review` | global |
| `branch-review` | `branch-review` | global |
| `bdd-audit` | `bdd-audit` | global |
| `coverage-audit` | `coverage-investigator` (optional) | global |
| `ato-artifact-collector` | `ato-artifact-collector` | global |

`install.sh` installs every global-scope pair into each selected CLI's global directory, rendered per CLI. `skill-sync` handles repo-scope pairs (none today). Both share the `agents/base/` + `agents/renderers/` pattern.

## Catalog

All 37 skills and 5 agents, grouped by purpose. **Scope** indicates whether the artifact is installed globally per CLI (global) or per-repo via `skill-sync` (repo). **How to use** lists the detection marker (for repo-scope skills) or the natural-language trigger the harness listens for.

### Preflight — PR / merge quality gates _(all repo-scope)_

| Skill | What it does | Dependencies | How to use |
|---|---|---|---|
| `preflight` | Dispatcher — detects the project's language(s) and delegates to the matching language preflight | None (delegates via Skill tool) | Trigger: "run preflight", "pre-PR checks", end of work session |
| `cargo-preflight` | Rust: `cargo fmt`, `cargo clippy -D warnings`, `cargo check`, `cargo test` | Rust toolchain (`cargo`) | Detects `Cargo.toml` |
| `xcode-preflight` | Swift / Objective-C: `xcodebuild build-for-testing`, focused tests, zero-warning check | Xcode / `xcodebuild` | Detects `*.xcodeproj`, `*.xcworkspace`, `Package.swift` |
| `python-preflight` | Format, lint, type-check, test — adapts to venv / Poetry / uv / tox | Python + whichever of `ruff`/`black`/`mypy`/`pytest` the repo uses | Detects `pyproject.toml`, `requirements.txt`, `setup.py` |
| `node-preflight` | Type-check, lint, build, test — detects npm / pnpm / yarn from lockfiles | Node.js + repo's declared tools (tsc, eslint, vitest/jest, …) | Detects `package.json` |
| `jvm-preflight` | Compile, lint, test, full build for Java + Kotlin; auto-detects Maven vs Gradle | JDK + Maven or Gradle | Detects `pom.xml`, `build.gradle[.kts]` |
| `go-preflight` | `gofmt`, `go vet`, `golangci-lint`, `go test ./...` | Go toolchain; `golangci-lint` optional | Detects `go.mod` |
| `ruby-preflight` | `bundle install`, RuboCop, Sorbet/RBS if configured, RSpec or Minitest | Ruby + Bundler + repo's gems | Detects `Gemfile` |
| `dotnet-preflight` | C# / .NET: `dotnet format`, restore, build with warnings-as-errors, test | `dotnet` SDK | Detects `*.csproj`, `*.sln` |
| `cmake-preflight` | C / C++: format, static analysis, build, test; adapts to CMake / Make / Meson | Compiler toolchain + chosen build system | Detects `CMakeLists.txt`, `Makefile`, `meson.build` |
| `php-preflight` | Syntax check, Composer validation, CS-Fixer / CodeSniffer, PHPStan/Psalm, PHPUnit/Pest | PHP + Composer + repo's chosen linters/testers | Detects `composer.json` |
| `data-script-preflight` | Best-effort checks for SQL / R / SAS / Perl — runs whatever authoritative checker exists per file type | `sqlfluff`, `lintr`, SAS, Perl as applicable | Detects `*.sql`, `DESCRIPTION`, `*.sas`, `Makefile.PL` |

### Testing guides _(all repo-scope)_

| Skill | What it does | Dependencies | How to use |
|---|---|---|---|
| `rust-testing` | Patterns for async tests with tokio, `tempfile` fixtures, `mockall` traits, focused `cargo test` runs | `cargo`; typically `tokio`, `tempfile`, `mockall` dev-deps | Trigger: "write a Rust test", "mock this trait" |
| `swift-testing` | Swift Testing framework: `@Test`, `@Suite`, `#expect`, `#require`, focused runs (never XCTest) | Xcode 16+ / Swift Testing | Trigger: "write a Swift test" |
| `python-testing` | pytest: fixtures, `parametrize`, mock / monkeypatch, async via `pytest-asyncio` / `anyio`, unittest interop | `pytest` (+ plugins as needed) | Trigger: "write a pytest test" |
| `node-testing` | Vitest / Jest / Mocha patterns: describe/it, fixtures, mocks/spies, async, supertest, Playwright | Node.js + chosen test runner | Trigger: "write a Node/TS test" |
| `jvm-testing` | JUnit 5 (Java + Kotlin), Kotest, Mockito / MockK, parameterized tests, focused Gradle / Maven runs | JDK + JUnit 5 + mocking lib | Trigger: "write a JVM test" |

### Audit & review _(all global-scope)_

| Skill | What it does | Dependencies | How to use |
|---|---|---|---|
| `repo-health` | Start-of-session panel: branch state, open PRs, build status, test failures, coverage trend, leftover worktrees | git, `gh` (optional), language tools | Trigger: "repo health", start of session |
| `coverage-audit` | Measures coverage, filters structurally untestable code, ranks high-impact gaps across 11 languages. Optionally pairs with `coverage-investigator` agent | Language coverage tool (cargo-llvm-cov, pytest-cov, vitest, jacoco, …) | Trigger: "coverage audit", "what's our real coverage?" |
| `deep-review` | Thin stub → agent. Eight-axis review: feature integrity, stubs/dead code, user journey, tests, security + threat model, reliability, ship hygiene, doc↔code | None — reads the code | Trigger: "full audit", "deep review", "is this shippable?" |
| `bdd-audit` | Thin stub → agent. Classifies each BDD feature area wired / unwired / truly-missing / deferred | git; feature files (`.feature`) | Trigger: "audit BDD coverage", "Gherkin specs wired?" |
| `branch-review` | Thin stub → agent. Classifies every unmerged branch, writes `CHANGES.md`, recommends merge/prune/PR | git (+ `gh` for PR state) | Trigger: "review branches", "produce CHANGES.md" |
| `merge-sprint` | Merges a batch of related PRs in dependency order, resolves conflicts, verifies build after each | git, `gh`, language build tool | Trigger: "merge these PRs", "run a merge sprint" |

### Deployment _(all repo-scope)_

| Skill | What it does | Dependencies | How to use |
|---|---|---|---|
| `deploy-app` | Dispatcher — detects deployment target(s) and delegates to the right sibling | None (delegates) | Trigger: "deploy", "ship", "release" |
| `native-app-deploy` | Native GUI: `~/Applications` (Tauri / Electron / Xcode), iOS Simulator / device, TestFlight, Android adb, Play Console | Xcode / Tauri / Electron / `adb` / `xcrun altool` as relevant | Invoked by `deploy-app` when project is native |
| `web-app-deploy` | Web / server: Fly.io, Render, Railway, Vercel, Netlify, Heroku, DO App Platform, bare-metal SSH | Platform CLI (`flyctl`, `vercel`, …) + ambient auth | Invoked by `deploy-app` when project is web |
| `container-app-deploy` | Build OCI / Docker image and push to Docker Hub / GHCR / ECR / GCR / ACR / Quay; multi-arch via buildx | Docker or Podman / Buildah; registry credentials | Invoked by `deploy-app` when project has `Dockerfile` |

### ATO / NIST 800-53 compliance _(all global-scope; lives under `ato/`, installed by `bash ato/install.sh`)_

The ATO collection is a self-contained subset under [`ato/`](ato/). Install with `bash ato/install.sh --for <cli>` (separate from the main installer). Full user guide at [ato/README.md](ato/README.md).

| Skill | What it does | Dependencies | How to use |
|---|---|---|---|
| `ato-artifact-collector` | Thin stub → agent. Orchestrates NIST 800-53 evidence collection across repo + optional external sources | git; sibling skills as scoped | Trigger: "ATO", "NIST 800-53", "collect security artifacts" |
| `ato-source-aws` | Sibling. Read-only AWS evidence via `mcp__AWS_API_MCP_Server__call_aws` (US regions only) | AWS MCP server + ambient AWS session | Invoked by orchestrator when AWS scope confirmed |
| `ato-source-azure` | Sibling. Read-only Azure evidence via `az` CLI (US regions only) | `az` CLI + ambient Azure session | Invoked by orchestrator when Azure scope confirmed |
| `ato-source-sharepoint` | Sibling. Read-only SharePoint Online team-site evidence via `m365` CLI; includes content-based pre-scan | `pnp/cli-microsoft365` (`m365`) + ambient M365 session; optional `pdftotext`/`pandoc`/`unzip` | Invoked by orchestrator when SharePoint scope confirmed |
| `ato-source-onedrive` | Sibling. Read-only OneDrive for Business evidence (per-user personal sites) via `m365` CLI; same pre-scan layer | `m365` + delegated access to each user's OneDrive | Invoked by orchestrator when OneDrive scope confirmed |
| `ato-source-smb` | Sibling. Read-only SMB / Windows file-share evidence; cross-platform; pre-mount probe + content pre-scan | `mount_smbfs` (macOS) / `mount.cifs` or gvfs (Linux) / UNC (Windows) + ambient auth | Invoked by orchestrator when SMB scope confirmed |
| `ato-vulnerability-scanner` | Stub → agent. Pre-collection vulnerability baseline (Step 1.5) | Language scanners as available (cargo-audit, pip-audit, etc.) | Auto-runs before Step 2 unless `--no-vuln-scan` |
| `ato-remediation-guidance` | Generates `REMEDIATION_GUIDANCE.md` punch list from package gaps | Existing ATO package | Auto-runs with `--remediation` (or invoke standalone) |
| `ato-poam-generator` | Generates POA&M Markdown + federal-submission CSV | Existing ATO package + remediation output | Auto-runs with `--poam` (implies `--remediation`) |
| `auth-config` | Resolves credentials for AWS / Azure / SharePoint / OneDrive / SMB via `~/.agent-skills/auth/auth.yaml`. Supports 1Password, Bitwarden, LastPass, Keeper, HashiCorp Vault, macOS Keychain, Windows Cred Manager, Linux libsecret, OAuth, env vars, user scripts. Read-only — never writes credentials | User's vault CLI (op / bw / vault / security / …) + `~/.agent-skills/auth/auth.yaml` | Lives canonically under `ato/`. Invoked by every ATO source sibling's preauth step. |
| `auth-interview` | AskUserQuestion-driven bootstrap of `~/.agent-skills/auth/auth.yaml`. Detects installed vault CLIs, writes the file `chmod 0600`, dry-validates each entry | `AskUserQuestion`; vault CLIs at runtime | Lives canonically under `ato/`. Run once before the first ATO collection if you want vault-backed credentials. |

### Provisioning _(all global-scope)_

| Skill | What it does | Dependencies | How to use |
|---|---|---|---|
| `skill-sync` | Detects toolchains, fetches the matching subset of `repo-scope/` skills + agents from the source repo, writes `.sync-manifest.json` for idempotent re-runs | `gh` or git over SSH + `~/.claude/skill-sync.config.yaml` | Trigger: "skill-sync", "install skills for this repo" |
| `skill-interview` | Greenfield: interviews the user about languages / frameworks / deploy targets, then delegates to `skill-sync` | `AskUserQuestion` + `skill-sync` | Trigger: "new repo", "set up skills for a fresh project" |

### Credentials

`auth-config` and `auth-interview` are listed above in the ATO section — they live under `ato/` since the ATO source siblings are their only consumer today. They're general-purpose by design (supporting AWS, Azure, M365, SMB, plus LLM-provider keys for any future multi-model agent), so if a non-ATO consumer appears, they get promoted back to `skills/global-scope/`. Until then, they ship with the ATO bundle.

### Opinionated templates _(repo-scope, opt-in)_

| Skill | What it does | Dependencies | How to use |
|---|---|---|---|
| `ios-app-template-conventions` | One team's iOS / macOS stack: Swinject DI, Swift Testing (never XCTest), `FileSystemSynchronizedRootGroup`, `Backups/` folder for deletes | Xcode 16+, Swinject, Swift Testing | **Opt-in only** — install per-project for repos that follow the template. Not a universal Swift guide. |

### Agents (invoked via the `Agent` tool)

| Agent | What it does | Scope | Tools | How to use |
|---|---|---|---|---|
| `deep-review` | Eight-axis review orchestrator — feature integrity, stubs/dead code, user journey, test honesty, security + full threat model (incl. LLM + agent-to-agent attack paths), reliability, ship hygiene, doc↔code. Spawns parallel Explore sub-agents, enforces submission gate | global | Bash, Read, Write, Grep, Glob, Agent | Invoked by the `deep-review` stub skill |
| `bdd-audit` | Classifies each feature area as wired / partially / stubbed / missing; diagnoses implemented-but-untested vs truly-missing vs deferred. **Read-only.** | global | Bash, Read, Grep, Glob | Invoked by the `bdd-audit` stub skill |
| `branch-review` | Audits every unmerged branch, classifies each, flags merge risks, writes `CHANGES.md`, returns a recommendation table. Only write is `CHANGES.md`. | global | Bash, Read, Write, Grep, Glob | Invoked by the `branch-review` stub skill |
| `coverage-investigator` | Deep dive on a single low-coverage file/module: classifies each uncovered entry point (pure / injectable / hard-wired / dead / integration-only), estimates effort, recommends next action. **Read-only.** | global | Bash, Read, Grep, Glob | Invoked by `coverage-audit` when the user asks "why is this file low?" |
| `ato-artifact-collector` | 8-step NIST 800-53 evidence-collection orchestrator. Produces `docs/ato-package/` with 20+ evidence families, narrative docs with `[CR-NNN]` citations, `INDEX.md` + `CHECKLIST.md` + `CODE_REFERENCES.md` | global (under `ato/`) | Bash, Read, Write, Edit, Grep, Glob, Skill | Invoked by the `ato-artifact-collector` stub skill after scope is confirmed |
| `ato-vulnerability-scanner` | Pre-collection vulnerability baseline — runs language-specific advisory scanners (cargo-audit, pip-audit, govulncheck, etc.) plus secret scanning and SAST | global (under `ato/`) | Bash, Read, Write, Grep, Glob, Skill | Auto-invoked at Step 1.5 of the orchestrator; standalone via `/ato-vulnerability-scanner` |
| `ato-doc-summarizer` | Source-agnostic document summarizer — reads pre-extracted excerpts and returns 2–3 sentence neutral summaries plus per-control-family confidence scores | global (under `ato/`) | Bash, Read, Write, Grep, Glob | Invoked by `ato-source-{smb,sharepoint,onedrive}` during pre-scan |

## Quick start

### 0. Install the global-scope skills + agents for your CLI(s)

**Two installers, one source of truth:**

- `bash install.sh` — the all-in-one installer. Walks both the generic tree (`skills/`, `agents/`) AND the `ato/` subtree, so a single command installs the full corpus plus the ATO collection.
- `bash ato/install.sh` — installs **only** the ATO subset. The `ato/` folder is independently shareable: copy it onto a shared drive and `bash ato/install.sh` works without the rest of this repo. The subset bundles its own copies of the auth skills and the per-CLI renderers; `bin/sync-ato.sh` keeps them in sync with their canonical sources (verified by a pre-commit hook and CI).

**macOS / Linux — one-liner for the full corpus (single CLI, no clone required):**

```bash
curl -fsSL https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/install.sh | bash -s -- --for claude
```

**macOS / Linux — one-liner for just the ATO collection:**

```bash
curl -fsSL https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/ato/install.sh | bash -s -- --for claude
```

**Windows (PowerShell) — full corpus:**

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
$u='https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/install.ps1'
$f="$env:TEMP\agentskills-install.ps1"
iwr -useb $u -OutFile $f; & $f -For claude
```

**Windows (PowerShell) — ATO only:**

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
$u='https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/ato/install.ps1'
$f="$env:TEMP\ato-install.ps1"
iwr -useb $u -OutFile $f; & $f -For claude
```

The PowerShell scripts use Git Bash (from Git for Windows) under the hood. If Git for Windows isn't installed, they offer to install it via `winget` (or Chocolatey, or a manual download link as last-resort fallback). Pass `-Yes` to skip the prompt; pass `-SkipGitInstall` to fail loudly instead of installing.

**Install for several CLIs at once:**

```bash
curl -fsSL https://raw.githubusercontent.com/AlastairThomson/AgentSkills/main/install.sh | bash -s -- --for claude,opencode,kilo
```

What happens: the installer fetches the repo tarball at `main` (or whatever `--ref` you pass). For each CLI in `--for`, every agent under `agents/base/global-scope/` is piped through the matching renderer (`agents/renderers/<cli>.sh`) to produce the CLI's native format, then written to that CLI's global directory (`~/.claude/`, `~/.config/opencode/`, `~/.config/kilo/`, `~/.codex/`, `~/.gemini/`). Claude additionally gets `skills/global-scope/*` under `~/.claude/skills/`. Codex additionally gets an `AGENTS.md` inventory. A single manifest at `~/.agent-skills/installer-manifest.json` tracks everything so subsequent runs are idempotent. Artifacts you authored by hand are never touched — only ones listed in the manifest.

**No `--for`?** If stdin is a TTY the installer will prompt multi-select. In a non-TTY pipe, `--for` is required (no silent default).

**Pin a specific version** (recommended for teams):

```bash
curl -fsSL https://raw.githubusercontent.com/AlastairThomson/AgentSkills/main/install.sh | bash -s -- --for claude --ref v1.0.0
```

**Inspect before installing:**

```bash
curl -fsSL https://raw.githubusercontent.com/AlastairThomson/AgentSkills/main/install.sh | bash -s -- --for claude --list
```

**Uninstall:**

```bash
# Remove everything installed:
curl -fsSL https://raw.githubusercontent.com/AlastairThomson/AgentSkills/main/install.sh | bash -s -- --uninstall

# Or just one CLI:
curl -fsSL https://raw.githubusercontent.com/AlastairThomson/AgentSkills/main/install.sh | bash -s -- --uninstall --for claude
```

**All flags:**

| Flag | Effect |
|---|---|
| `--for <list>` | Comma-separated CLIs: `claude`, `opencode`, `kilo`, `codex`, `gemini`. Multi-select TTY prompt if omitted; required in non-TTY mode. Also `AGENT_SKILLS_FOR`. |
| `--ref <branch\|tag\|sha>` | Pin to a specific revision. Default: `main`. Also `AGENT_SKILLS_REF`. |
| `--repo <owner/name>` | Pull from a fork instead. Default: `AlastairThomson/AgentSkills`. Also `AGENT_SKILLS_REPO`. |
| `--dest <dir>` | Override install root — each CLI installs under `<dir>/<cli>/`. Useful for sandboxed testing. Also `AGENT_SKILLS_DEST`. |
| `--from <dir>` | Install from a local checkout instead of fetching (development / smoke testing). |
| `--list` | Print what would be installed; write nothing. |
| `--uninstall` | Remove manifest-listed artifacts. Combine with `--for` to target one CLI. |
| `--keep-cache <dir>` | After install, move the extracted repo to `<dir>` for offline re-use. |
| `-y`, `--yes` | Skip the interactive confirmation (required under `curl \| bash` without a TTY — pass `-y` in that case). |

After install, `skill-sync`, `skill-interview`, `repo-health`, `branch-review`, `bdd-audit`, `coverage-audit`, `merge-sprint`, `deep-review`, `auth-config`, `auth-interview`, and the full ATO family (`ato-artifact-collector`, the five `ato-source-*` skills, `ato-vulnerability-scanner`, `ato-remediation-guidance`, `ato-poam-generator`) are all available in every repo without further install (for Claude Code — other CLIs get the agents only, not the skills). Use `bash ato/install.sh --for <cli>` if you only want the ATO subset (e.g., on a per-team shared drive that doesn't need the rest of the corpus).

**Kilo cross-scan note.** Kilo by default scans `.claude/`, `.opencode/`, and `.agents/` directories in addition to its own. If you install for Kilo *only* (`--for kilo`), the installer prints instructions to isolate Kilo from those other directories. If you install for Kilo alongside other CLIs, cross-scan is left enabled (assumption: you want visibility).

**Prefer a full clone?** Fine — `git clone`, then `./install.sh --for <cli>` from the checkout. Same result, same manifest.

**Optional next step — credentials.** If any repo you work in will use the ATO source skills (AWS, Azure, SharePoint, SMB) or a multi-model agent framework that needs LLM API keys, run `auth-interview` once to bootstrap `~/.agent-skills/auth/auth.yaml`. The interview asks where each credential lives (1Password, Bitwarden, Keychain, Vault, env var, or a custom script) and writes the config with `chmod 0600`.

### 1. One-time config at `~/.claude/skill-sync.config.yaml`

```yaml
version: 2
source:
  repo: AlastairThomson/AgentSkills   # or your fork
  ref: main                            # prefer a pinned tag in production
target_clis: []                        # empty = inherit from ~/.agent-skills/installer-manifest.json
                                       # else list: claude, opencode, kilo, codex, gemini
allowlist: []                          # empty = any skill in source is eligible
deny: []
auth:
  method: gh                           # gh | ssh — uses ambient auth
```

### 2. From inside the target repo, ask your AI CLI to run `skill-sync`

It will:

1. Resolve which CLIs to configure (from `target_clis:`, the installer manifest, or a TTY prompt).
2. Detect the repo's toolchains (Cargo.toml, package.json, Package.swift, …) and workflow signals (Dockerfile, …).
3. Fetch the matching subset of **repo-scope** artifacts from this repo (global-scope artifacts are already in each CLI's global directory from step 0).
4. For each selected CLI, render agents through `agents/renderers/<cli>.sh` and install into `<repo>/.<cli>/`.
5. Write a `.sync-manifest.json` so subsequent runs are idempotent.
6. Ask once whether the per-CLI directories should be committed to git or gitignored, and edit `.gitignore` accordingly.

**Greenfield project with no code yet?** Use `skill-interview` instead — it asks about intended languages/frameworks, then delegates to `skill-sync`.

**Subsequent runs:**

| Invocation | Behaviour |
|---|---|
| `skill-sync` | Apply: detect, diff, install, prune, write manifest |
| `skill-sync --dry-run` | Detect and print the diff; touch nothing |
| `skill-sync --status` | Report drift vs. the manifest; exit non-zero if drift exists |
| `skill-sync --prune` | Remove manifest-listed skills no longer selected |
| `skill-sync --force-update` | Treat all manifest entries as "to update" |

## Skill anatomy

```markdown
---
description: "One-line hook the harness uses to decide when to surface this skill."
---

# Human-readable title

Body: step-by-step instructions, tables, shell snippets.
```

- `description` is the only field the harness matches against — write it as a trigger sentence.
- The directory name is the canonical skill identifier.
- Supporting material (tables, checklists) lives in sibling folders and is referenced by relative path.

## Agent anatomy

Agents are authored in a CLI-agnostic base form and rendered per CLI at install time. Each agent lives in `agents/base/<scope>/<name>/`:

```
agents/base/<scope>/<name>/
  agent.md          # prompt body — no frontmatter
  metadata.yaml     # canonical metadata (see below)
  references/       # optional — copied verbatim into every CLI install
  evals/            # optional
  config.yaml       # optional
```

`metadata.yaml`:

```yaml
name: <agent-name>
description: "When the parent model should invoke this agent."
tools: [Bash, Read, Edit, Grep, Glob, Skill]
model: sonnet
extras:                        # optional per-CLI hints
  opencode:
    mode: subagent
  kilo:
    mode: subagent
  codex:
    sandbox_mode: read-only
```

When `install.sh` or `skill-sync` installs an agent for a given CLI, it runs `agents/renderers/<cli>.sh` on the base directory and writes the rendered file to the CLI's native location with the right frontmatter (or TOML, for Codex). Never hand-edit the rendered output — edit `agent.md` + `metadata.yaml` in the base tree, then re-run the installer.

## Contributing

Everything under `skills/` and `agents/` must be **generic** — safe to drop into any repo. No hardcoded crate names, tenant names, or single-product CLI tools. The one intentional exception is `ios-app-template-conventions`, whose description announces it as opinionated.

When adding a new skill or agent, pick the scope:

- `global-scope/` — works usefully against any repo, regardless of language. Typical candidates: audit/review, VCS workflows, user-level provisioning tooling.
- `repo-scope/` — only makes sense in the presence of a specific toolchain, target, or workflow file. Language preflights, testing guides, deployment siblings, compliance orchestrators.

A paired stub skill and its agent must live in matching scopes.

When you add a new language-specific preflight:

1. Wire it into `skills/repo-scope/preflight/SKILL.md`'s marker table.
2. Add a matching row to `skills/global-scope/skill-sync/SKILL.md`'s detection table.
3. Prefix the description with `"Pre-PR checklist for <language>:"` so the harness disambiguates cleanly.

When you add a new CLI:

1. Add `agents/renderers/<cli>.sh` (see existing renderers as templates; source `_lib.sh` for YAML helpers).
2. Add a golden assertion block to `agents/renderers/tests/smoke.sh`.
3. Teach `install.sh` about the CLI's target root (`cli_root()`), file extension (`cli_agent_ext()`), and the `SUPPORTED_CLIS` list.
4. Add a row to the CLI-support table in this README and in `CLAUDE.md`.
5. Add a per-CLI branch to `skill-sync`'s install loop.

Full contributor conventions — file casing, frontmatter rules, the skill↔agent pairing contract, the ATO orchestrator/sibling invariants — live in [CLAUDE.md](CLAUDE.md).

## Version History

| Release | Date | Notes |
|:--|:--|:--|
| Release v0.1.0 | April 27, 2026 | Alpha release for testing |

## License

AgentSkills is released under a BSD Three Clause license.

Copyright &copy;2026 AI Strategy LLC and CVP Corporation, All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission. 

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
