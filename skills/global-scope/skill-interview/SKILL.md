---
name: skill-interview
description: "Greenfield project setup: interview the user via AskUserQuestion about the intended AI CLIs (Claude Code, OpenCode, Kilo Code, Codex, Gemini, Antigravity), languages, test frameworks, deployment targets, and compliance/workflow requirements for a new repo, then delegate to `skill-sync` to install the matching subset into each CLI's per-repo directory. Use when starting a fresh repo that has no code yet — for existing repos, use `skill-sync` directly (its detection is more accurate than any interview)."
---

# Skill Interview

`skill-interview` provisions a greenfield repo's `.claude/skills/` by asking the user what the project *will* be, rather than what it currently is. Once the answers are in hand, it produces a selection set and hands off to `skill-sync` for the actual install.

**Not for existing repos.** If the repo has any language markers (`Cargo.toml`, `package.json`, `pyproject.toml`, etc.), run `skill-sync` directly. Its detection is more accurate than any Q&A.

## When to run

- First commit to a new repo, before code exists.
- When converting a planning-only directory (specs, diagrams) into a working codebase.
- When seeding an org template repo.

## Workflow

### Step 0 — Gate-check

Run a quick detection pass identical to `skill-sync` Step 2. If **any** toolchain marker is found, stop and recommend `skill-sync` instead. Offer to proceed anyway only if the user insists (e.g. a monorepo where the interview covers a new subproject).

### Step 1 — Ask the interview questions

Use the `AskUserQuestion` tool. Group related questions into a single call (multiple question entries, multiple options each) so the user sees a compact form rather than a slow serial interrogation.

**Required questions** (always ask):

1. **Target AI CLIs.** Multi-select from: Claude Code, OpenCode, Kilo Code, Codex (OpenAI), Gemini CLI, Antigravity CLI (`agy`). If the user has previously run `install.sh` and `~/.agent-skills/installer-manifest.json` exists, pre-fill the answer with the `clis` array from that file and let the user edit down. Stored in `<repo>/.skill-sync.yaml` as `target_clis:` — `skill-sync` will configure each CLI's per-repo directory (`.claude/`, `.opencode/`, `.kilo/`, `.codex/`, `.gemini/`, `.antigravity/`).
2. **Primary language(s).** Multi-select from: Rust, Swift, Python, TypeScript, JavaScript, Kotlin, Java, C#, C, C++, Go, Ruby, PHP, R, SAS, Perl, SQL, Objective-C, Other (free-text).
3. **Testing intensity.** Single-select: (a) No tests initially, (b) Smoke tests only, (c) Full unit + integration, (d) TDD / BDD (Gherkin).
4. **Deployment target.** Multi-select: iOS, macOS, Android, Windows desktop, Linux desktop, Docker container, Node web app, Python web app, Static site, Library package (no deploy), CLI binary, Other.
5. **Compliance scope.** Multi-select: None, NIST 800-53 / ATO package, SOC 2, HIPAA, FedRAMP, Other. Any selection other than "None" implies ATO-adjacent tooling.
6. **Team workflow.** Multi-select: Pull requests (GitHub flow), Trunk-based, Multi-branch release train, Solo / personal project.

**Conditional follow-ups** (ask only when the primary answer suggests it's needed):

- If **Swift** or **Objective-C** selected → ask about file-management style: (a) FileSystemSynchronizedRootGroup (modern Xcode), (b) Classic group references, (c) Not sure yet. If (a), offer `ios-app-template-conventions` as an opt-in install.
- If **Python** or **Node** web app selected → ask web framework (Flask / FastAPI / Django / Express / Fastify / Next.js / Other).
- If **C** or **C++** selected → ask build system (CMake / Make / Meson / Autotools / Bazel / Other).
- If **JVM** selected → ask build tool (Gradle / Maven).
- If **ATO / compliance** in scope → ask which external evidence sources apply: AWS, Azure, SharePoint/M365, SMB fileshares, none (repo-only).

Keep total question count under 10. If the user is unsure, accept "skip" / "not sure yet" — `skill-sync` can be re-run later when the answer firms up.

### Step 2 — Translate answers to a selection set

Map the answers to the same skill list `skill-sync` would produce from markers. Use this table as the mapping spec:

| Answer | Skills added |
|---|---|
| Rust | `cargo-preflight`, `rust-testing` |
| Swift / Objective-C | `xcode-preflight`, `swift-testing` (+ `ios-app-template-conventions` if user opted in) |
| Python | `python-preflight`, `python-testing` |
| TypeScript or JavaScript | `node-preflight`, `node-testing` |
| Kotlin or Java | `jvm-preflight`, `jvm-testing` |
| Go | `go-preflight` |
| Ruby | `ruby-preflight` |
| C# | `dotnet-preflight` |
| C or C++ | `cmake-preflight` |
| PHP | `php-preflight` |
| R, SAS, Perl, or SQL (primary) | `data-script-preflight` |
| Testing intensity ≥ (c) | keep `*-testing` siblings; (a)/(b) → drop `*-testing` |
| Any deployment target selected | `deploy-app` dispatcher + matching sub-skill (`native-app-deploy` / `web-app-deploy` / `container-app-deploy`) |
| ATO/compliance in scope | `ato-artifact-collector` + relevant `ato-source-*` skills |

**Always add** (VCS-shape defaults): `preflight`.

**Not installed by interview.** The global-scope skills and agents — `deep-review`, `branch-review`, `bdd-audit`, `coverage-audit` + `coverage-investigator`, `repo-health`, `merge-sprint`, `skill-sync`, `skill-interview` — live in the user's `~/.claude/` and are always available. They are not added to the per-repo selection set. BDD workflows, pull-request reviews, coverage audits, and repo health checks all work from the user-level install against the new repo with no per-repo install.

### Step 3 — Confirm the selection

Show the computed selection set back to the user as a bulleted list with one-line reasons. Use `AskUserQuestion` with a single yes/no/edit option. Accept edits via a free-text "add or remove X" response.

### Step 4 — Hand off to `skill-sync`

Write a per-repo override at `<repo>/.skill-sync.yaml` encoding the interview result as an `allowlist` of the confirmed skills + the `target_clis` list, then invoke `skill-sync` via the Skill tool:

```yaml
# <repo>/.skill-sync.yaml
version: 2
source: {}                    # inherit from ~/.claude/skill-sync.config.yaml
target_clis: [claude, opencode]   # from Q1; empty = inherit from installer manifest
allowlist:
  - preflight
  - cargo-preflight
  - rust-testing
  # ... etc
```

Record in the manifest that this install was interview-driven (in the top-level `source` block: `"provisioning": "skill-interview"`) so `skill-sync --status` can later distinguish interview-seeded installs from marker-detected ones.

### Step 5 — Suggest next steps

After the install completes, tell the user:

- Which skill to run next to scaffold the project (usually `deploy-app` for a new app, or no specific skill for a library).
- That they can re-run `skill-sync` once real code lands — it may detect languages the interview missed and add more siblings.
- That the org can extend the interview's question tree by editing this skill in the source repo.

## Fallback for unrecognised stacks

If the user answers "Other" for the language, or chooses a stack with no matching sibling (SAS-only, SQL-only, etc.), record it as an unmatched language in the per-repo override:

```yaml
unmatched_languages: [SAS, Cobol]
```

Still install the always-on default (`preflight`), and tell the user what to do: "no preflight sibling exists for SAS/Cobol yet — the `preflight` dispatcher falls back to inline best-effort syntax checks. File an issue at the source repo if you'd like a dedicated sibling."

## Non-goals

- `skill-interview` does **not** fetch skills itself. That is `skill-sync`'s job.
- `skill-interview` does **not** scaffold project files (no `cargo init`, no `npm init`). Project scaffolding belongs in language-specific scaffolding skills, not here.
- `skill-interview` does **not** store the raw answers long-term. Only the confirmed selection set (in the per-repo override) persists.
