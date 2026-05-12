---
name: skill-sync
description: "Provision a repo's per-CLI agent and skill directories (.claude/, .opencode/, .kilo/, .codex/, .gemini/, .pi/, .crush/) with only the artifacts relevant to its languages and workflow. Detects toolchains (Cargo.toml, package.json, pyproject.toml, Package.swift, *.csproj, go.mod, Gemfile, CMakeLists.txt, composer.json, DESCRIPTION, *.sas, Makefile.PL, .sql), fetches the matching subset from an org-configured GitHub source repo, renders every agent through the per-CLI renderer for every CLI the user installed for, and writes a .sync-manifest.json for idempotent re-runs. Pi (pi.dev) and Crush (charmbracelet/crush) are skills-only — repo-scope skills install into <repo>/.agents/skills/ and <repo>/.crush/skills/ which the harness auto-discovers; agent rendering is skipped. Modes: apply, --dry-run, --status, --prune. Accepts --for <cli>[,<cli>...] to override the CLI set. Ambient gh auth. Use when setting up a new repo, after adding/removing a language, or after adding a new CLI to your global install."
---

# Skill Sync

`skill-sync` installs only the repo-scope artifacts (skills + agents) a given repo actually needs, fetched from an organization's source GitHub repo, and writes them into the correct directory for each AI CLI the user has installed AgentSkills for. It replaces "install everything globally and hope the harness picks the right one" with "install the relevant subset per repo so the harness has a clean pick — for each CLI in play."

## Source repo layout

The source GitHub repo splits skills and agents into **global-scope** and **repo-scope** subtrees. Agents live under a single `agents/base/` canonical tree and are rendered to per-CLI formats at install time by the scripts in `agents/renderers/`:

```
skills/
  global-scope/      # user-level — installed into ~/.claude/skills/ via install.sh, not skill-sync
    deep-review/SKILL.md
    branch-review/SKILL.md
    bdd-audit/SKILL.md
    coverage-audit/SKILL.md
    repo-health/SKILL.md
    merge-sprint/SKILL.md
    skill-sync/SKILL.md
    skill-interview/SKILL.md
  repo-scope/        # per-repo — installed by skill-sync when the toolchain matches
    preflight/SKILL.md
    cargo-preflight/SKILL.md
    rust-testing/SKILL.md
    deploy-app/SKILL.md
    native-app-deploy/SKILL.md, web-app-deploy/SKILL.md, container-app-deploy/SKILL.md
    …
agents/
  base/              # canonical, CLI-agnostic source
    global-scope/
      deep-review/{agent.md, metadata.yaml, references/, evals/}
      branch-review/{agent.md, metadata.yaml}
      bdd-audit/{agent.md, metadata.yaml}
      coverage-investigator/{agent.md, metadata.yaml}
      ato-artifact-collector/{agent.md, metadata.yaml, references/, evals/, config.yaml}
    repo-scope/      # empty today; reserved for future repo-scoped agents
  renderers/         # one script per CLI (claude.sh, opencode.sh, kilo.sh, gemini.sh, codex.sh)
    + codex-agents-md.sh for the Codex AGENTS.md inventory
```

**Agent rendering.** `skill-sync` never copies `agents/base/<scope>/<name>/agent.md` verbatim. Instead, for each CLI in play, it pipes the base agent through `agents/renderers/<cli>.sh` to produce the CLI's native format (Markdown+YAML for Claude/OpenCode/Kilo/Gemini; TOML for Codex).

**`skill-sync` only ever fetches from `skills/repo-scope/` and `agents/base/repo-scope/`.** The `global-scope/` subtrees are the responsibility of a separate one-time install (`install.sh`) — they are always available regardless of which repo the user is working in, so installing them per-repo would just duplicate them. Globally, `install.sh` writes skills to **at most two physical locations** regardless of how many CLIs are selected: `~/.claude/skills/` (Claude only) and `~/.agents/skills/` (shared by OpenCode + Kilo + Gemini + Codex, all of which auto-discover that path). Codex specifically also scans `~/.codex/skills/`, so writing there in addition would surface every skill twice — `install.sh` deliberately avoids that. Within `~/.<cli>/agents/`, each selected CLI gets its own rendered agents.

A thin-stub skill in `skills/repo-scope/<name>/SKILL.md` may delegate to an agent in `agents/base/repo-scope/<name>/`. When a skill advertises an agent delegate, **both** are installed together; they are versioned as a pair and recorded as a pair in the manifest.

## Install target layout — per CLI

In the target repo, installs go under a per-CLI directory. The installer manifest at `~/.agent-skills/installer-manifest.json` lists which CLIs the user has installed globally; `skill-sync` targets that same set unless overridden with `--for`.

| CLI | Per-repo target | Agent file extension |
|---|---|---|
| Claude Code | `<repo>/.claude/` | `.md` |
| OpenCode | `<repo>/.opencode/` | `.md` |
| Kilo Code | `<repo>/.kilo/` | `.md` |
| Codex | `<repo>/.codex/` | `.toml` |
| Gemini CLI | `<repo>/.gemini/` | `.md` |
| Pi (pi.dev) | `<repo>/.pi/` and `<repo>/.agents/skills/` (skills only — no agents) | — |
| Crush | `<repo>/.crush/skills/` and `<repo>/.agents/skills/` (skills only — agents live in crush.json) | — |

For each selected CLI the install shape is:

```
<repo>/.<cli>/
  skills/<name>/SKILL.md                        # Claude only — other CLIs don't consume SKILL.md today
  agents/<name>.<ext>                           # flat form for agents without bundled references
  agents/<name>/<name>.<ext>                    # directory form for agents that bundle references/evals/config.yaml
  agents/<name>/{references/, evals/, config.yaml}   # bundled alongside the rendered agent file
```

Codex additionally gets `<repo>/.codex/AGENTS.md` — an inventory of installed agents rendered via `agents/renderers/codex-agents-md.sh`.

**Why skills are Claude-only per-repo for now.** Per-repo skill placement is still Claude-only here even though OpenCode, Kilo, Gemini, and Codex all support `SKILL.md` natively at the global tier — `install.sh` (global) handles them via the cross-scan compatibility paths (`~/.agents/skills/` for OpenCode/Kilo/Gemini, dedicated dirs for Claude/Codex). Per-repo skill scanning paths differ by CLI (e.g., `<repo>/.opencode/skills/` vs `<repo>/.kilo/skills/` vs `<repo>/.gemini/skills/`) and there is no equivalent shared `.agents/skills/` convention at the per-repo tier in every CLI. Until that lands consistently, repo-scope skills go to `.claude/skills/` only and other CLIs read repo-scope content via Claude's directory if they cross-scan it; otherwise per-CLI repo-scope skill placement should be added when there is a real need.

## When to run

- Setting up a brand-new clone of an existing repo.
- After adding or removing a language/toolchain from the repo.
- After the org publishes a new skill-source ref and you want to update.
- After adding a new CLI to your global install (re-run with the new CLI in `--for` or refresh the installer manifest).
- To audit drift: `skill-sync --status` reports what is installed vs. what would be installed.

For a **greenfield** project with no code yet, use the sibling skill `skill-interview` — it gathers the language/framework/architecture answers by Q&A and then calls this skill.

## Configuration

Config lives at `~/.claude/skill-sync.config.yaml` (user-global). A per-repo override at `<repo>/.skill-sync.yaml` wins for its fields. If neither exists, `skill-sync` refuses to run — there is no built-in default source, because the source is org-specific.

```yaml
version: 2
source:
  repo: your-org/ClaudeSkills           # GitHub owner/repo
  ref: main                             # branch, tag, or commit SHA (prefer a pinned tag)
target_clis: []                         # optional. Empty = read from ~/.agent-skills/installer-manifest.json
                                        # else comma-list of: claude, opencode, kilo, codex, gemini, pi, cursor, crush
allowlist: []                           # empty = every skill/agent in source is available
                                        # non-empty = only these directory names may be installed
deny: []                                # always exclude these (takes precedence over allowlist)
auth:
  method: gh                            # gh | ssh
                                        # gh  → use `gh` CLI (ambient auth, no tokens stored)
                                        # ssh → use `git` over SSH (keys must already be configured)
```

## Workflow

### Step 1 — Load config, resolve CLI set, verify auth

1. Read `~/.claude/skill-sync.config.yaml`. Merge `<repo>/.skill-sync.yaml` if present (per-field override, no deep merge).
2. Resolve the CLI set:
   - If the user passed `--for <list>` on invocation, use that.
   - Else if config has `target_clis:` non-empty, use that.
   - Else read `~/.agent-skills/installer-manifest.json` and use the `clis` array from the most recent `install.sh` run.
   - Else ask the user via `AskUserQuestion` (multi-select): "Which CLIs should I configure this repo for? claude / opencode / kilo / codex / gemini / pi / cursor / crush".
3. If `auth.method: gh`, check `gh auth status` succeeds; if `ssh`, check `ssh -T git@github.com 2>&1 | grep -q 'successfully authenticated'`. If auth is missing, **stop** with an actionable message — do not prompt to store tokens.

### Step 2 — Detect the repo's toolchains and workflow signals

Walk the repo root and immediate subtrees for marker files. Record every toolchain detected.

**Toolchain markers:**

| Marker | Toolchain → Skills to install |
|---|---|
| `Cargo.toml` | Rust → `cargo-preflight`, `rust-testing` |
| `*.xcodeproj`, `*.xcworkspace`, `Package.swift`, `Podfile`, `*.m` + `*.h` | Swift / Objective-C → `xcode-preflight`, `swift-testing` |
| `tsconfig.json`, or `package.json` + TypeScript dep | TypeScript → `node-preflight`, `node-testing` |
| `package.json` without TypeScript | JavaScript → `node-preflight`, `node-testing` |
| `pyproject.toml`, `setup.py`, `requirements.txt`, `Pipfile` | Python → `python-preflight`, `python-testing` |
| `pom.xml`, `build.gradle`, `build.gradle.kts` | Java / Kotlin → `jvm-preflight`, `jvm-testing` |
| `go.mod` | Go → `go-preflight` |
| `Gemfile`, `*.gemspec`, `Rakefile` | Ruby → `ruby-preflight` |
| `*.csproj`, `*.sln`, `Directory.Build.props` | C# / .NET → `dotnet-preflight` |
| `CMakeLists.txt`, `Makefile`, `configure.ac`, `meson.build` | C / C++ → `cmake-preflight` |
| `composer.json` | PHP → `php-preflight` |
| `DESCRIPTION` + `.R` files, `*.sas`, `Makefile.PL` / `cpanfile`, standalone `.sql` / `.sqlfluff` | R / SAS / Perl / SQL → `data-script-preflight` |

**Workflow signals (always install when detected):**

Only artifacts under the source repo's repo-scope trees are candidates. Global-scope artifacts live in each CLI's global directory already.

| Signal | Skills / agents to install |
|---|---|
| Any recognized VCS/CI marker (git repo) | skills: `preflight` |
| Tauri (`tauri.conf.json` or `src-tauri/`) **or** `*.xcodeproj` **or** `.xcworkspace` **on macOS** | skills: `deploy-app` (dispatcher), `native-app-deploy` |
| `Dockerfile` **or** `docker-compose.yml` | skills: `deploy-app`, `container-app-deploy` |
| `package.json` with `"express"` / `"fastify"` / `"next"` dep, **or** `pyproject.toml` with `"flask"` / `"fastapi"` / `"django"` | skills: `deploy-app`, `web-app-deploy` |

**Skill↔agent pairing rule.** When a repo-scope stub skill advertises an agent delegate, **both** are installed together and recorded as a pair in the manifest. Never install the stub without the agent — the stub's only purpose is to trigger the agent. There are no repo-scope pairs today; all current agent pairs live under `agents/base/global-scope/` and are handled by `install.sh`, not `skill-sync`.

Apply `allowlist` and `deny` filters last.

### Step 3 — Compute the diff

Read `<repo>/.claude/.sync-manifest.json` if it exists (the legacy single-CLI location; used as the authoritative source regardless of which CLIs are now in play — the manifest records what was previously installed per CLI).

Compute three sets **per CLI**:

- **To add** — selected by detection, not present in the manifest's entry for this CLI.
- **To update** — present in the manifest, manifest records a different source ref than current config.
- **To prune** — present in the manifest's entry for this CLI, NOT selected by detection.

Any directory present on disk under `<repo>/.<cli>/` but **not** listed in the manifest is user-authored or left over from another tool; never touch it.

### Step 4 — Apply (or dry-run)

In `--dry-run` mode, print the three sets for each CLI and stop.

Otherwise, fetch a shallow clone of the source repo to a cache:

```bash
CACHE=~/.cache/claude-skill-sync/<source-repo-slug>@<ref>
if [ ! -d "$CACHE" ]; then
    gh repo clone <source-repo> "$CACHE" -- --depth 1 --branch <ref> --quiet
fi
```

Then, **for each selected CLI, for each skill/agent in add ∪ update**:

```bash
# Determine per-CLI target root
case "$cli" in
    claude)   root="<repo>/.claude" ;;
    opencode) root="<repo>/.opencode" ;;
    kilo)     root="<repo>/.kilo" ;;
    codex)    root="<repo>/.codex" ;;
    gemini)   root="<repo>/.gemini" ;;
    cursor)   root="<repo>/.cursor" ;;
    pi)       root="<repo>/.pi"  ;;     # Pi has no subagents — skills only (handled below)
    crush)    root="<repo>/.crush" ;;   # Crush has no subagents — skills only (handled below)
esac

# Pi and Crush both have no subagents. Install repo-scope skills into a shared
# per-repo location each harness auto-discovers, then continue to the next CLI
# without rendering any agents.
if [ "$cli" = "pi" ]; then
    pi_skills_dir="<repo>/.agents/skills"
    mkdir -p "$pi_skills_dir"
    rsync -a --delete "$CACHE/skills/repo-scope/<name>/" "$pi_skills_dir/<name>/"
    continue
fi
if [ "$cli" = "crush" ]; then
    crush_skills_dir="<repo>/.crush/skills"
    mkdir -p "$crush_skills_dir"
    rsync -a --delete "$CACHE/skills/repo-scope/<name>/" "$crush_skills_dir/<name>/"
    continue
fi

mkdir -p "$root/agents"

# Skills: Claude only (for now)
if [ "$cli" = "claude" ]; then
    mkdir -p "$root/skills"
    rsync -a --delete "$CACHE/skills/repo-scope/<name>/" "$root/skills/<name>/"
fi

# Agents: render through the per-CLI script
renderer="$CACHE/agents/renderers/$cli.sh"
base="$CACHE/agents/base/repo-scope/<name>"
ext=$(case "$cli" in codex) echo toml ;; *) echo md ;; esac)

if [ -d "$base/references" ] || [ -d "$base/evals" ] || [ -f "$base/config.yaml" ]; then
    # Directory form: render inside the bundled directory
    mkdir -p "$root/agents/<name>"
    "$renderer" "$base" > "$root/agents/<name>/<name>.$ext"
    [ -d "$base/references" ] && cp -R "$base/references" "$root/agents/<name>/"
    [ -d "$base/evals" ]      && cp -R "$base/evals"      "$root/agents/<name>/"
    [ -f "$base/config.yaml" ] && cp "$base/config.yaml" "$root/agents/<name>/"
else
    # Flat form
    "$renderer" "$base" > "$root/agents/<name>.$ext"
fi
```

Codex additionally gets an `AGENTS.md` inventory covering every agent that was installed for it:

```bash
if [ "$cli" = "codex" ]; then
    "$CACHE/agents/renderers/codex-agents-md.sh" <every-installed-base-path> > "$root/AGENTS.md"
fi
```

For each entry in prune (per CLI):

```bash
# Skill (Claude only)
rm -rf "$root/skills/<name>"

# Agent (flat)
rm -f "$root/agents/<name>.$ext"

# Agent (directory)
rm -rf "$root/agents/<name>"
```

Only prune paths that are in the manifest entry for this CLI.

### Step 5 — Write the manifest

`<repo>/.claude/.sync-manifest.json` (kept at `.claude/` for historical reasons; covers all CLIs):

```json
{
  "version": 2,
  "source": {
    "repo": "your-org/ClaudeSkills",
    "ref": "v1.4.0",
    "resolved_sha": "abc123def456..."
  },
  "generated_at": "2026-04-24T14:00:00Z",
  "commit_policy": "committed",
  "clis": ["claude", "opencode"],
  "installed": {
    "claude": {
      "skills": {
        "cargo-preflight": {"reason": "Cargo.toml detected"},
        "rust-testing":    {"reason": "Cargo.toml detected"}
      },
      "agents": {}
    },
    "opencode": {
      "agents": {}
    }
  }
}
```

### Step 6 — Commit policy for per-CLI directories

Teams split on whether synced skills/agents should be committed (a team lead runs `skill-sync` once and the result rides with the repo) or gitignored (each developer runs `skill-sync` locally). Ask once per repo, record the answer in the manifest, and update `.gitignore` to match.

**Skip the prompt when already decided:**

- Manifest has `commit_policy: "committed" | "ignored"` → honor it.
- `.gitignore` already contains a line matching any of the per-CLI directories → treat as `"ignored"`, record in manifest.
- `--dry-run` → skip this step entirely.

Otherwise, ask via `AskUserQuestion` with two options:

- **Committed** — Team lead runs `skill-sync` once, commits `.claude/`, `.opencode/`, `.kilo/`, `.codex/`, `.gemini/` (as applicable) + manifest.
- **Ignored** — Each developer runs `skill-sync` themselves; those directories + the manifest stay gitignored.

**Apply `committed`:**

- Remove any matching ignore lines (and any preceding `# Added by skill-sync` comment), one at a time, without reordering.
- Record `commit_policy: "committed"` in the manifest.
- Remind the user to `git add` the per-CLI directories and the manifest.

**Apply `ignored`:**

- Append this block to `.gitignore` **only if** none of its paths already appear as standalone lines:

  ```
  # Added by skill-sync — per-developer AI CLI skills/agents
  .claude/skills/
  .claude/agents/
  .claude/.sync-manifest.json
  .opencode/
  .kilo/
  .codex/
  .gemini/
  ```

- Record `commit_policy: "ignored"` in the manifest.

**Invariants:** Never edit unrelated sections of `.gitignore`. Never touch `.claude/settings.json` or similar tool-managed files.

## Modes

| Invocation | Behaviour |
|---|---|
| `skill-sync` | Full apply: detect, compute diff per CLI, render, install, prune, write manifest. |
| `skill-sync --for <cli>[,<cli>...]` | Override the CLI set for this run only. Does not change the installer manifest. |
| `skill-sync --dry-run` | Detect and print the diff for each CLI; do not touch the filesystem. |
| `skill-sync --status` | Read the manifest, compare to current detection; print any drift. Exit non-zero if drift. |
| `skill-sync --prune` | Only prune. Do not add or update. |
| `skill-sync --force-update` | Treat all manifest entries as "to update" regardless of ref. |

## Safety rules

1. **Never delete a skill or agent that isn't in the manifest.** Those are user-authored or from another tool.
2. **Never write auth tokens to the manifest** — `gh` and `ssh` handle auth; `skill-sync` only records source repo/ref/SHA.
3. **Refuse to run without valid auth.** Don't prompt for token creation; tell them what's missing and stop.
4. **Abort on allowlist violations.** If detection selects a skill/agent not in the allowlist (and allowlist is non-empty), warn, skip, continue.
5. **Never install a stub skill without its paired agent** (or vice versa).
6. **Respect the CLI scope.** Never write into a CLI directory the user didn't select.
7. **Every change is reversible via `--prune`** and via manifest inspection. Back up the manifest before running with `--force-update`.
8. **Ask for the commit policy at most once.**

## Example — polyglot repo with two CLIs

`~/.agent-skills/installer-manifest.json` shows the user installed for Claude + OpenCode. Detection finds `Cargo.toml` + `package.json` (no TS) + `Dockerfile`. Selected install set:

```
skills (Claude only — repo-scope):
  preflight, cargo-preflight, rust-testing, node-preflight, node-testing,
  deploy-app, container-app-deploy

agents (both CLIs — rendered per CLI):
  (none currently — no repo-scope agents in the base tree today)
```

Layout after apply:

```
<repo>/
├── .claude/
│   ├── skills/{preflight, cargo-preflight, rust-testing, ...}/SKILL.md
│   └── .sync-manifest.json
└── .opencode/
    └── agents/          # empty today; will populate when repo-scope agents land
```

Global-scope artifacts (`deep-review`, `branch-review`, `bdd-audit`, `coverage-audit` + `coverage-investigator`, `repo-health`, `merge-sprint`, `skill-sync`, `skill-interview`, `ato-*`, `auth-*`) are **not** in this list — they live in each CLI's global directory already, installed by `install.sh`.
