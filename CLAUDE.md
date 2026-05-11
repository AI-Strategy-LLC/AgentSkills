# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of **multi-CLI AI skills and agents** for Claude Code, OpenCode, Kilo Code, OpenAI Codex, and Gemini CLI. Skills (stateless step-by-step guides surfaced by description) live under `skills/`; agents (isolated-context subprocesses) live under `agents/`. Each agent is authored once in a CLI-agnostic base form and rendered to each CLI's native format at install time.

Both trees are split into **`global-scope/`** (user-level, installed once per CLI into each CLI's global directory — available in every repo) and **`repo-scope/`** (per-repo, installed by `skill-sync` into each CLI's per-repo directory only when the toolchain matches).

Repo layout:

```
skills/
  global-scope/      # workflow utilities that work on any repo
  repo-scope/        # toolchain-specific; pulled in by skill-sync
agents/
  base/              # canonical, CLI-agnostic agent source (body + metadata.yaml)
    global-scope/
    repo-scope/
  renderers/         # per-CLI transformers: claude.sh, opencode.sh, kilo.sh, gemini.sh, codex.sh
                     # + codex-agents-md.sh for the Codex AGENTS.md inventory
install.sh           # per-CLI installer with --for <cli>[,<cli>...]
CLAUDE.md            # this file
```

**Scope-selection rule.** A skill or agent belongs in `global-scope/` if it works usefully on any repo regardless of language (`deep-review`, `branch-review`, `bdd-audit`, `coverage-audit`, `repo-health`, `merge-sprint`, `skill-sync`, `skill-interview`, the ATO orchestrator + sources + remediation guidance + POA&M generator + vulnerability scanner, `auth-*`). It belongs in `repo-scope/` if it is meaningful only when a specific toolchain or target is present (language preflights, testing guides, `preflight` dispatcher, `deploy-app` + siblings, `ios-app-template-conventions`).

A paired stub and agent live in matching scopes — if the stub is global, the agent is too.

## CLI support

| CLI | Global agents dir | Global skills dir | Per-repo dir | Agent file | Identity |
|---|---|---|---|---|---|
| Claude Code | `~/.claude/agents/` | `~/.claude/skills/` | `<repo>/.claude/` | `<name>.md` (MD + YAML) | frontmatter `name:` |
| OpenCode | `~/.config/opencode/agents/` | `~/.agents/skills/` (shared) | `<repo>/.opencode/` | `<name>.md` (MD + YAML, no name) | filename |
| Kilo Code | `~/.config/kilo/agents/` | `~/.agents/skills/` (shared) | `<repo>/.kilo/` | `<name>.md` (MD + YAML, no name) | filename |
| OpenAI Codex | `~/.codex/agents/` | `~/.agents/skills/` (shared) | `<repo>/.codex/` | `<name>.toml` + `AGENTS.md` | TOML `name =` |
| Gemini CLI | `~/.gemini/agents/` | `~/.agents/skills/` (shared) | `<repo>/.gemini/` | `<name>.md` (MD + YAML) | frontmatter `name:` |
| Pi (pi.dev) | — *(no subagents)* | `~/.agents/skills/` (shared) | `<repo>/.pi/` and `<repo>/.agents/skills/` | `SKILL.md` only | frontmatter `name:` |
| Cursor | `~/.cursor/agents/` | `~/.agents/skills/` (shared) | `<repo>/.cursor/` | `<name>.mdc` (MDC + YAML) | filename |
| Crush | — *(no subagents)* | `~/.config/agents/skills/` (XDG-shared) | `<repo>/.crush/` and `<repo>/.agents/skills/` | `SKILL.md` only | frontmatter `name:` |

The installer (`install.sh --for <cli>[,<cli>...]`) and `skill-sync` both accept a multi-CLI selection. The user chooses which CLIs to install for; each selected CLI gets its own correctly-shaped copy of every agent (where applicable — Pi has only skills).

**Cursor caveat.** Cursor's "agents" concept is still evolving (Custom Agents, Background Agents, etc. — the API has shifted between minor versions). The renderer (`agents/renderers/cursor.sh`) emits MDC files with `description:` + `alwaysApply: false` frontmatter, which is the most stable cross-version representation. Bodies that say "invoke the Agent tool with `subagent_type:`" or "use the Skill tool" assume Claude Code semantics — those calls have no direct Cursor equivalent yet, and a thin-stub skill running in Cursor will degrade to "the model reads the steps and does them inline." Track Cursor's docs and update the renderer as the format stabilizes.

**Native Windows support.** `install.ps1` (and `ato/install.ps1`) are PowerShell wrappers that detect Git Bash, offer to install Git for Windows via `winget` (or Chocolatey, or a manual download fallback), and forward args to the bash installers. Git Bash provides bash + curl + tar + the rest of the POSIX toolset the installer needs, and handles the Windows-path translation transparently. CLI directories follow the same `~/.<cli>/` convention — `~` resolves to `%USERPROFILE%` (e.g. `C:\Users\<name>\.claude\`).

**Skill placement (strategy A — single canonical location per scan-group, lean on cross-scan):** Three dedup buckets exist:

- `~/.claude/skills/` — Claude Code only (it doesn't scan the cross-CLI paths).
- `~/.agents/skills/` — OpenCode, Kilo, Gemini, Codex, Pi, Cursor (HOME-dot-prefixed cross-CLI compat path).
- `~/.config/agents/skills/` — Crush (XDG-rooted cross-CLI path per Crush's `GlobalSkillsDirs()`; Crush does not scan `~/.agents/skills/`).

`install.sh` writes each unique skills directory exactly once per install. Result: **at most three physical copies of any skill on disk regardless of how many CLIs are selected**, and no within-CLI duplicates — important for Codex specifically, which scans both `~/.codex/skills/` and `~/.agents/skills/` and would surface every skill twice if we wrote to both.

**Pi has no subagents.** Pi (pi.dev) is a "minimal terminal coding harness" whose only customization mechanism is skills (loaded from `~/.pi/agent/skills/` and `~/.agents/skills/`). It has no Agent tool, no `subagent_type`, no equivalent to `~/.claude/agents/`. The installer skips agent rendering entirely for Pi (`cli_has_agents pi` returns false; `install_cli pi` short-circuits after the skills-dedup step). **Caveat:** thin-stub skills like `branch-review`, `deep-review`, `bdd-audit`, and `ato-artifact-collector` will surface in Pi (they're skills) but their bodies say "invoke the Agent tool with `subagent_type: <agent-name>`" — which Pi cannot do. Pi users who trigger one of those stubs will get a clear runtime error from Pi's harness; consider this a known limitation, not a bug. Skills that do their work inline (`coverage-audit`, `repo-health`, `auth-config`, `auth-interview`, the language preflights, etc.) work normally in Pi.

**Crush has no subagents either.** Crush (`charmbracelet/crush`) is skills-only from this installer's perspective: its `Agent` type is a JSON struct defined inline in `crush.json` under the `agents` key, with no equivalent of `~/.claude/agents/<name>.md` file-based subagents. Skills come from `$CRUSH_SKILLS_DIR`, `~/.config/crush/skills/`, `~/.config/agents/skills/`, and the project-local `.crush/skills`, `.agents/skills`, `.claude/skills`, `.cursor/skills`. The installer writes once to `~/.config/agents/skills/` (the cross-CLI XDG path) and `cli_has_agents crush` returns false. Same thin-stub caveat as Pi applies — skills whose bodies call the Agent tool will fail at runtime in Crush.

**Flat-only agent shape for OpenCode / Kilo / Gemini.** Those three CLIs recursively scan their `agents/` directory and register every `.md` file as an agent — including bundled `references/*.md`, which then surface as broken namespaced agents. To avoid that, the renderers for those CLIs **inline bundled references into the agent body** (via `_lib.sh::inline_references`) and the installer always writes them as flat `<name>.md` files. Claude and Codex preserve directory form because they don't have the same scanning trap.

## Skill anatomy

Every `skills/<name>/` directory contains a `SKILL.md`:

```markdown
---
name: <skill-name>
description: "One-line hook the harness uses to decide when to surface this skill."
---

# Human-readable title

Body: step-by-step instructions, tables, shell snippets.
```

- `name` is **required** and must match the directory name. Claude Code will fall back to the directory name if absent, but OpenCode, Kilo, Codex, and Gemini all require it explicitly per the agent-skills spec — keep it present so a single SKILL.md works across every CLI.
- `description` is **required** and is the field the harness matches against. Write it as a trigger sentence — lead with what the skill does, then when to use it. Keep it on a single line (Codex's loader has been observed to mishandle folded `>` and literal `|` YAML scalars in some versions); single-quoted scalars are the safe default. Description max length per the spec is 1024 chars.
- The directory name is the canonical skill identifier.
- Skills may carry supporting material in sibling folders (e.g. `references/`). Reference those from `SKILL.md` using relative paths.

## Agent anatomy

Agents live in a **base + renderer** pattern. The canonical source is CLI-agnostic; the renderers produce CLI-native files at install time.

Every `agents/base/<scope>/<name>/` directory contains:

```
agents/base/<scope>/<name>/
  agent.md              # prompt body — no frontmatter
  metadata.yaml         # canonical metadata (name, description, tools, model, extras.*)
  references/           # optional — copied verbatim for Claude/Codex; inlined into the rendered agent body for OpenCode/Kilo/Gemini
  evals/                # optional — copied verbatim for Claude/Codex; not installed for OpenCode/Kilo/Gemini
  config.yaml           # optional — copied verbatim for Claude/Codex; not installed for OpenCode/Kilo/Gemini
```

`metadata.yaml` shape:

```yaml
name: <agent-name>
description: "When the parent model should invoke this agent. Specific trigger language."
tools: [Bash, Read, Edit, Grep, Glob, Skill]
model: sonnet                                  # opus / sonnet / haiku / inherit
extras:                                        # optional per-CLI hints
  opencode:
    mode: subagent
  kilo:
    mode: subagent
  codex:
    sandbox_mode: read-only                    # or workspace-write for agents that write files
```

`model:` is authored using the canonical Claude aliases (`opus` / `sonnet` / `haiku` / `inherit`). Only the Claude renderer emits the value verbatim — Claude understands those aliases natively. The OpenCode, Kilo, Gemini, and Codex renderers **drop the field** because each of those CLIs expects its own provider/model-id format and would reject a bare alias. Subagents inherit the invoker's model when `model:` is absent, which is the right default — the user picks the model in their CLI's global config rather than having every agent hard-code one.

At install time, each renderer at `agents/renderers/<cli>.sh` reads the agent's base directory and emits the CLI's native format:

- `claude.sh` / `gemini.sh` → Markdown with `name:` frontmatter
- `opencode.sh` / `kilo.sh` → Markdown without `name:` (filename is authoritative); adds `mode:`
- `codex.sh` → TOML with `developer_instructions = '''<body>'''`
- `codex-agents-md.sh` → `AGENTS.md` inventory listing every installed agent

**Agent shape per CLI:**

- **Claude / Codex** — agents that bundle `references/`, `evals/`, or `config.yaml` install as directory-form (`<cli-root>/agents/<name>/<name>.<ext>`) so the bundled files sit alongside the rendered agent. Simple agents land flat.
- **OpenCode / Kilo / Gemini** — always flat (`<cli-root>/agents/<name>.<ext>`), regardless of base shape. Those CLIs recursively scan their `agents/` directory and would register every reference `.md` as a broken namespaced agent. Bundled `references/*.md` are inlined into the rendered agent body via `_lib.sh::inline_references` so the agent stays self-contained; `evals/` and `config.yaml` are not installed for these CLIs (they are dev-loop artifacts, not runtime inputs).

**Shape rule:** the rendered frontmatter is CLI-specific, but the body (`agent.md`) is identical across CLIs. When editing an agent, edit `agent.md` — do not touch the rendered output in any CLI install tree. When adding a field that matters for only one CLI, put it under `extras.<cli>.` in `metadata.yaml` and teach that CLI's renderer to honor it.

## Skill ↔ agent pairing

A thin-stub skill often pairs with an agent. The stub triggers on user intent (preserving slash-command discoverability like `/branch-review`); the agent does the actual multi-step work in its own context. Current pairs:

| Stub skill | Agent | Scope |
|---|---|---|
| `skills/global-scope/deep-review/` | `agents/base/global-scope/deep-review/` | global |
| `skills/global-scope/branch-review/` | `agents/base/global-scope/branch-review/` | global |
| `skills/global-scope/bdd-audit/` | `agents/base/global-scope/bdd-audit/` | global |
| `skills/global-scope/coverage-audit/` | `agents/base/global-scope/coverage-investigator/` (optional; skill is usable without agent) | global |
| `ato/skills/global-scope/ato-artifact-collector/` | `ato/agents/base/global-scope/ato-artifact-collector/` | global (ATO subset) |
| `ato/skills/global-scope/ato-vulnerability-scanner/` | `ato/agents/base/global-scope/ato-vulnerability-scanner/` | global (ATO subset) |

`install.sh` installs every global-scope pair under `skills/global-scope/` and `agents/base/global-scope/` into each selected CLI's global directory, rendered per CLI. The ATO collection lives under its own `ato/` subtree and ships with a dedicated installer (`ato/install.sh`) — see "ATO subset is independently shareable" below. `skill-sync` handles repo-scope pairs (none today; reserved). All three installers share the `agents/base/` + `agents/renderers/` pattern.

## Skills and agents must be generic

Every directory under `skills/` or `agents/` is a **generic** artifact — safe to drop into any repo. No hardcoded crate names, project-specific paths, tenant names, or CLI tools that only exist in one product. If a command, path, or concept only makes sense for a specific downstream project, either genericize it (placeholders, framework-neutral examples) or keep it out of this repo. `ios-app-template-conventions/` is the one intentional exception — its description announces it as opinionated, so users opt in knowingly.

## Skill categories

**Global-scope** (`skills/global-scope/`, `agents/global-scope/`):

- **Audit / review** — stub+agent pairs `bdd-audit/`, `branch-review/`, `deep-review/`, and skill `coverage-audit/` (optionally paired with `coverage-investigator` agent); `repo-health/`
- **Batched-PR workflow** — `merge-sprint/`
- **Per-repo provisioning** — `skill-sync/`, `skill-interview/`
- **Credentials** — `auth-config/` (resolver — reads `~/.agent-skills/auth/auth.yaml`, runs user's vault CLI, validates session) and `auth-interview/` (AskUserQuestion-driven bootstrap of the config file, 0600 on write). **Both currently live under `ato/skills/global-scope/`** since ATO is their only consumer; promote back to `skills/global-scope/` if a non-ATO consumer appears (see "Editing rules for the ATO subset" below).

**Repo-scope** (`skills/repo-scope/`):

- **Preflight dispatcher** — `preflight/` (detects toolchains and delegates via the Skill tool to the matching sibling)
- **Language preflight siblings** — `cargo-preflight/` (Rust), `xcode-preflight/` (Swift + Objective-C), `python-preflight/`, `node-preflight/` (TypeScript + JavaScript), `jvm-preflight/` (Java + Kotlin), `go-preflight/`, `ruby-preflight/`, `dotnet-preflight/` (C#), `cmake-preflight/` (C + C++), `php-preflight/`, `data-script-preflight/` (SQL + R + SAS + Perl)
- **Testing guides** — `rust-testing/`, `swift-testing/`, `python-testing/`, `node-testing/`, `jvm-testing/`
- **Project conventions templates** — `ios-app-template-conventions/` (opt-in; one team's Swinject + Swift Testing + FileSystemSynchronizedRootGroup + Backups stack)
- **Ops / deployment** — `deploy-app/` (dispatcher), `native-app-deploy/`, `web-app-deploy/`, `container-app-deploy/`

`agents/base/repo-scope/` is currently empty and reserved for repo-scoped agents.

`preflight` is the dispatcher — it invokes the matching `*-preflight` sibling via the Skill tool, with an inline fallback for unrecognized toolchains. When adding a new language-specific preflight, (1) wire it into `skills/repo-scope/preflight/SKILL.md`'s marker table, (2) add a matching row to `skills/global-scope/skill-sync/SKILL.md`'s detection table, and (3) keep the sibling's description prefixed `"Pre-PR checklist for <language>:"` so the harness disambiguates cleanly.

## ATO subset is independently shareable

The ATO (Authority to Operate) collection lives under a dedicated **`ato/`** subtree at the repo root:

```
ato/
  skills/global-scope/         # 9 ATO skills + 2 shared auth skills
  agents/base/global-scope/    # 3 ATO agents
  agents/renderers/            # bundled per-CLI renderers (copies of agents/renderers/)
  install.sh                   # ATO-only installer
  README.md                    # the user guide
```

Why a separate folder? The ATO collection is the largest cohesive workflow in this repo and has its own audience (federal-system ISSOs and ATO authors) that may want it without the rest of the AgentSkills corpus. The `ato/` folder is **self-contained** — it carries every skill and agent the ATO flow needs (including the two auth skills `auth-config` and `auth-interview` that every source sibling preauths through, since ATO is their only consumer today) plus a copy of the per-CLI renderers. So it works whether you've cloned the parent repo or copied just the `ato/` folder somewhere else (an internal share, a separate repo, an archive). `bash ato/install.sh --for claude` writes a separate manifest (`~/.agent-skills/ato-installer-manifest.json`) so the two installers don't trip over each other.

**Two installers, one source of truth:**

- `bash install.sh --for <cli>` — installs **everything** (the generic AgentSkills corpus + the ATO collection). It walks `skills/global-scope/`, `agents/base/global-scope/`, AND `ato/skills/global-scope/`, `ato/agents/base/global-scope/`, deduping by name.
- `bash ato/install.sh --for <cli>` — installs **only the ATO subset**. Runs from `ato/` and never reaches outside it, so the `ato/` folder remains independently shareable (drop it on a shared drive and ship it).

**Editing rules for the ATO subset:**

- **Everything under `ato/` except the renderer mirror is canonical there.** ATO-specific content (`ato-*`) and the auth skills (`auth-config`, `auth-interview` — they exclusively serve ATO today) all live under `ato/skills/global-scope/` and `ato/agents/base/global-scope/` with no canonical home elsewhere. Edit them in place; the main installer pulls them in via `merge_ato_into_src`.
- **Renderers (`agents/renderers/*.sh`) are the only thing mirrored.** Canonical at `agents/renderers/`; copy lives at `ato/agents/renderers/`. Edit the canonical copy and run `bin/sync-ato.sh` before committing — the renderer needs to live in two places because the main installer renders ATO content during merge AND the standalone ATO bundle has to render its own agents without the parent repo present.

**Sync mechanics:**

- `bin/sync-ato.sh` — write changes (default), `--check` (CI/precommit, no writes, exit 1 on drift), `--list` (report state). Pairs are listed in the script's `PAIRS` array; add a row when you introduce a new shared file.
- `.githooks/pre-commit` runs `bin/sync-ato.sh --check` and blocks the commit on drift. Activate per-clone: `bash bin/install-hooks.sh` (sets `core.hooksPath = .githooks`).
- `.github/workflows/sync-check.yml` runs the same check on every PR, so contributors who skipped the local hook still get caught at PR time.

**If `auth-config` / `auth-interview` ever pick up a non-ATO consumer**, promote them back to canonical: `git mv ato/skills/global-scope/auth-config skills/global-scope/auth-config` (and same for auth-interview), add a `skills/global-scope/auth-config:ato/skills/global-scope/auth-config` row to `bin/sync-ato.sh`'s `PAIRS` array, and run `bin/sync-ato.sh` to recreate the mirror.

## ATO orchestrator + sibling pattern

The ATO orchestrator lives as an **agent** at `ato/agents/base/global-scope/ato-artifact-collector/`, fronted by a thin stub skill at `ato/skills/global-scope/ato-artifact-collector/`. The orchestrator coordinates six siblings, all under `ato/skills/global-scope/` (one is paired with an agent — see "Sibling shapes" below):

- **Source siblings** (4 read-only collectors): `ato-source-aws`, `ato-source-azure`, `ato-source-sharepoint`, `ato-source-smb`. Each runs when the user enables the corresponding external scope (AWS, Azure, SharePoint/M365, SMB shares).
- **Vulnerability scanner** (`ato-vulnerability-scanner`): a 5th source, but shaped as **agent + thin stub** (the only sibling shaped that way). Runs in Step 1.5 (between Orient and Discover) by default; the user can disable per-run with `--no-vuln-scan` or per-host via `vulnerability_scan.enabled: false` in config.
- **Remediation guidance** (`ato-remediation-guidance`): produces `REMEDIATION_GUIDANCE.md` post-collection. Runs only when the user explicitly asks, OR when the user invoked the orchestrator with `--remediation` / `--poam` (the stub flips an `auto_remediation` flag in the scope object).
- **POA&M generator** (`ato-poam-generator`): produces `poam-generated.md/.csv` post-remediation. Runs only when the user explicitly asks, OR when the user invoked the orchestrator with `--poam` (which implies `--remediation`). Consumes the remediation output, vulnerability findings, and CHECKLIST gaps.

The orchestrator's stub skill (`ato/skills/global-scope/ato-artifact-collector/SKILL.md`) accepts CLI-style flags (`--repo / --aws / --azure / --sharepoint / --smb / --no-vuln-scan / --no-assessment / --no-synthesize / --accept-synthesized / --remediation / --poam`) that bypass the interactive scope-confirmation interview. Any source flag triggers skip-interview mode; unflagged sources are disabled. The flags compose: `--poam` implies `--remediation`; both can combine with any source set. `--no-assessment` disables Steps 6.5/6.6 (Findings/Result skipped, CSV becomes 7-column). `--no-synthesize` disables Step 6.6 only. `--accept-synthesized` auto-promotes synthesized drafts up one folder, flips Result to Satisfied, and emits loud signaling (end-of-run summary, INDEX.md banner, CHECKLIST notes column).

The full hand-off contract for the source siblings is documented in `ato/agents/base/global-scope/ato-artifact-collector/references/sibling-contract.md` — read it before editing any source sibling. Invariants the source siblings all share:

- **Read-only.** No `create-*`, `put-*`, `delete-*`, `modify-*`, or any write verb. If asked to remediate, refuse and escalate.
- **Ambient auth only.** Siblings never store credentials, never call `aws configure`, never touch `~/.aws/credentials` etc. They use whatever session the user already established via the native tool.
- **Scope-confirmed in-session.** Each sibling re-confirms its scope before making external calls; the orchestrator does not bypass that prompt.
- **Graceful degradation.** If a sibling fails (auth missing, scope declined), the orchestrator records the failure and continues with remaining sources. Repo-only runs are a first-class mode.

The same invariants apply to `ato-vulnerability-scanner` (read-only on the repo, never auto-installs missing tools, gracefully degrades when scanners are absent, treats external advisory text as untrusted data).

### Sibling shapes

Five of the six siblings are **skills**: `ato-source-{aws,azure,sharepoint,smb}` and `ato-remediation-guidance` and `ato-poam-generator`. They are invoked by the orchestrator agent via the Skill tool. `ato-vulnerability-scanner` is the exception — it is an **agent + thin stub skill** (same pattern as `branch-review`, `deep-review`, `bdd-audit`) because it runs many external tools, parses verbose JSON, and benefits from an isolated context. The orchestrator invokes it via `Skill: "ato-vulnerability-scanner"`; the skill stub delegates to the agent. Standalone invocation works the same way (the skill is user-facing).

Source siblings write evidence into one of two top-level branches under `docs/ato-package/`: `ssp-sections/<NN>-<slug>/evidence/<source>_<file>` for document-shaped artifacts (the SSP body, IRP, CP, CMP, ConMon plan, ISA/MOU, POA&M, etc.) or `controls/<CF>-<slug>/evidence/<CONTROL-ID>/<source>_<file>` for per-control implementation evidence (an IAM role for AC-2, an NSG rule for SC-7, a CloudTrail config for AU-2, etc.). `<NN>` is the SSP-section ordinal (01–14), `<CF>` is the two-letter NIST 800-53 Rev 5 control-family code (all 20 always present: AC, AT, AU, CA, CM, CP, IA, IR, MA, MP, PE, PL, PM, PS, PT, RA, SA, SC, SI, SR), and `<CONTROL-ID>` is the specific control or enhancement (`AC-02`, `AC-02(04)`). Citation batches go to `docs/ato-package/.staging/{source}-citations.json` (where `{source}` ∈ `sharepoint | aws | azure | smb | vulnscan`; `vulnscan` is the sixth source token, peer to the cloud/share four). The canonical SSP-section + family table and the old-slug → new-path migration map live in `ato/agents/base/global-scope/ato-artifact-collector/agent.md` under "File naming convention".

**Sub-control granularity (Steps 4.5/4.6/6.5/6.6/6.7).** The orchestrator iterates at the **Determine If ID** level — sub-letters of the control body (`AC-02(a)`–`AC-02(l)`), enhancements (`AC-02(01)`), and enhancement-with-sub-letter chains (`AC-02(12)(b)`). Step 4.5 builds `.staging/sub-control-inventory.json` listing every Determine If ID per in-scope control. Step 4.6 emits per-Determine-If-ID manifests at `controls/<CF>-<slug>/evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_relevant-evidence.md`; the family + control + Determine If ID embedded in the filename keeps every manifest uniquely identifiable when an assessor flattens the package or copies files into a GRC tool, and manifests reference parent-level evidence files by relative path (no file duplication within a family). Step 6.5 (assessment pass) generates a Findings paragraph + Result (Satisfied / NotSatisfied / blank) for every Determine If ID, comparing the implementation narrative against the requirement text. Step 6.6 (synthesis) generates draft artifacts at `synthesized/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md` for "implementation present, artifact missing" gaps (e.g., `AC_AC-02_AC-02(d)_role-matrix-draft.md`); when `--accept-synthesized` is set, drafts auto-promote up one folder with loud signaling. Step 6.7 emits a 9-column GRC CSV per family (`controls/<CF>-<slug>/<cf>-assessment.csv`) plus a master CSV (`controls/_master-assessment.csv`) with header `Family ID,Family,Control ID,Control,Determine If ID,Determine If Statement,Method,Result,Findings`. See `references/sub-control-enumeration.md`, `references/assessment-template.md`, `references/synthesis-patterns.md`, and `references/csv-schema.md` for the full schemas. Siblings remain control-level (do not write into per-Determine-If-ID sub-folders).

`ato-remediation-guidance` and `ato-poam-generator` are read-only on the existing package. `ato-remediation-guidance` writes exactly one new file (`docs/ato-package/REMEDIATION_GUIDANCE.md`). `ato-poam-generator` writes three (`ssp-sections/04-poam/poam-generated.md`, `ssp-sections/04-poam/poam-generated.csv`, and `controls/CA-assessment-authorization/evidence/CA-5/poam-generated.md`). Neither is part of the default 8-step workflow; both share none of the source-sibling auth or scope-confirmation flow — their only inputs are the package on disk and the working repo.

## Editing conventions

- **File casing:** Skills use `SKILL.md` (uppercase). Agents use `agent.md` (under `agents/base/<scope>/<name>/`). Keep this consistent — mixed casing works on macOS but would break on a case-sensitive filesystem.
- **`metadata.yaml` must stay valid YAML.** A renderer will fail if frontmatter parses oddly. Keep `description:` as a single-line quoted string.
- **Never commit per-CLI-rendered output.** Agent changes land in `agent.md` + `metadata.yaml` under `agents/base/`. The CLI-specific output is generated by the installer; do not hand-edit it.
- **Shell snippets in skill / agent bodies are contracts**, not examples — users will copy-paste them. When you change a command, verify it still runs on the toolchain it targets.
- **When editing a paired stub skill or its agent, check both.** The skill's description and the agent's description must stay coherent — the skill is what triggers, the agent is what runs.
- **When adding a new CLI:** add `agents/renderers/<cli>.sh`, teach `install.sh` about its target root and file extension, add a row to the CLI-support table above, and add a case to `skill-sync`'s per-CLI install loop.
- The repo has no root-level `README.md`; the skill corpus is its own documentation. Don't create one unless asked.

## Working with the `repo/` sandbox

If a task mentions `x3f-*` crates, `cargo`, or anything Rust-shaped, you are almost certainly in `repo/` — `cd` there and follow its own `CLAUDE.md`. Changes to the sandbox are not changes to the skills and should not land in the same commit.
