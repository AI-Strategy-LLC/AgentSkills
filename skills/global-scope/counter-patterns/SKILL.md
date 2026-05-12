---
name: counter-patterns
description: "End-of-task and resume-time checks for the recurring process-discipline failure modes: source-of-truth selection, wiring-vs-backend completion, deploy-validation reads signal not metadata, multi-axis brief discipline, session-resume state drift, branch/worktree hygiene, recommendation followthrough. Mechanical where possible; agent-facing checklist where not. Triggers on 'counter-patterns', 'before I declare done', 'am I drifting', 'resume check', 'pre-compaction checkpoint', 'post-compaction reconcile'. Distinct from /honesty-audit (lint-tier mechanical scan for stubs/bypasses) and /deep-review (broad multi-axis review): this skill enforces the *process discipline* counter-patterns. Three modes: --check (run end-of-task checks), --resume (post-compaction reconciliation), --checkpoint (write AGENT_STATE.md before risky long-running ops)."
---

# Counter-Patterns

Enforces the process-discipline counter-patterns so they don't depend on the agent remembering across compactions or under deadline pressure.

This is **not** a code-quality scan (use `/honesty-audit` for that) and **not** a content review (use `/deep-review` for that). It catches the **process** failures: drifting source-of-truth, half-wired features, deploy-validation that reads metadata instead of signal, missing per-axis coverage, lost state after compaction, branch/worktree drift, recommendations the agent quietly downgraded.

The canonical rule library is in `counter-patterns.yaml` (CP-001..CP-019). Each rule has an id, severity, trigger, injected text, and a short generic description of the failure mode it prevents.

## What's in this skill folder

| File | Purpose |
|---|---|
| `SKILL.md` | This file. The skill body. |
| `counter-patterns.yaml` | Canonical CP-001..CP-019 rule library. |
| `CLAUDE_MD_BLOCK.md` | Marker-delimited block that can be prepended or appended to a CLAUDE.md as a reversible install. |
| `install-claude-md-block.sh` | Helper: `prepend | append | remove | status` modes for the CLAUDE.md block. Idempotent. |
| `hooks/` | Claude-Code-specific hook scripts that enforce the rules at the moment of action. See `hooks/README.md`. |
| `references/MECHANISMS.md` | Compaction-survival design notes (AGENT_STATE.md, PR-as-state-of-truth, multi-agent handoff baton, etc.). |

The hooks are Claude-Code-only (other CLIs do not currently expose the same hook surface). The skill body and the CLAUDE.md block are CLI-portable.

## Three modes

### `--check` (default, run before declaring a task done)

Sequence of checks. Each prints `PASS | WARN | FAIL` and a one-liner. Skill exits non-zero on any FAIL so it can gate completion claims.

| Check | What it does | How |
|---|---|---|
| **branch** | Are we on a feature branch, not a protected one? | `git branch --show-current` ≠ `main|master|develop|trunk|prod|production` (override via `CP_PROTECTED_BRANCHES`) |
| **worktree-pwd-match** | Does `pwd` match the expected worktree from the brief? | `git rev-parse --show-toplevel`; compare to brief's stated path if recorded |
| **dispatch-trace** | For each "wired up" claim in the staged commit message, does an entry-point file actually call the handler? | Parse commit msg for `wired up X` / `now dispatches Y`; grep entry-point locations (e.g. `src/main.*`, `src/cli/*`, `src/api/*`, `routes/*`) for handler symbol |
| **per-axis-report** | If the brief listed multiple axes, did the agent's recent messages address each? | Read brief from `.claude/current-brief.md` if present; check most recent assistant message contains each axis word |
| **ci-parity** | Did we run the EXACT command CI runs? | Parse `.github/workflows/*.yml`; extract lint/test invocations; grep recent shell history for them |
| **disposition-line** | Did the most recent assistant turn end with `PR #N opened; worktree at ...; branch ... — propose to delete` or equivalent? | Pattern match |
| **stale-worktrees** | Any worktrees older than 7 days with no recent commits? | `git worktree list` + commit dates |
| **bulk-naming** | Did this task generate >5 files with the same basename? | `find <staged dirs> -type f \| xargs basename \| sort \| uniq -c \| awk '$1>5'` |

Output: `docs/counter-patterns/REPORT.md` with grouped findings and a single-line CI verdict.

### `--resume` (run as the FIRST tool call after compaction or `--continue`)

Reconstructs verifiable state and surfaces drift between the compaction summary and reality.

1. Read `AGENT_STATE.md` from repo root if present (see `--checkpoint` below). Print last-known state.
2. Run the reconciliation block:
   ```
   git status
   git branch -vv
   gh pr list --author @me --state open
   git worktree list
   git log --oneline -20
   ```
3. Diff vs `AGENT_STATE.md`. Print `STATE-DRIFT: <field>` for each disagreement.
4. Print a one-paragraph "I am resuming. Last known: X. Current reality: Y. The gaps I see are: Z. Confirming I should proceed by ..." that the agent can adapt and send to the user.
5. Exit with non-zero if drift detected so the agent doesn't silently barrel forward.

### `--checkpoint` (run before any risky multi-step op or near context limits)

Writes `AGENT_STATE.md` at the repo root. Sections:

```
# Agent state — <UTC timestamp>

## Brief
<original task in 2-3 lines>

## Canonical sources
- spec: <path>
- truth-of-record: <BDD/code/legacy>
- read at: <commit SHA>

## Branch & PR
- branch: <name>
- worktree: <abs path>
- PR: #<n> (status)
- last commit: <sha> <subject>

## Done (with cite-the-line)
- <claim> — <file:line>

## Stubbed / deferred
- <claim> — <file:line> — why

## Open (TODOs)
- <item>

## Recommendations made (awaiting confirmation)
- <X recommended at <ts>; user response: <none|accepted|rejected>>

## Next planned action
<one sentence>
```

This file is the agent's memory across compactions. Read it on `--resume`, write it on `--checkpoint`, append to it on every milestone.

## Triggers (when an agent should self-invoke)

- About to send "X is complete" / "wired up" / "ready for review" → `/counter-patterns --check`
- "Session continued from previous conversation" header detected → `/counter-patterns --resume`
- About to run a long-running multi-step op (refactor, migration, multi-PR sequence) → `/counter-patterns --checkpoint`
- Approaching context limit (the harness surfaces this) → `/counter-patterns --checkpoint`

## Optional install: CLAUDE.md block + hooks

The skill body works on its own — invoking `/counter-patterns` will run the checks. Two optional installs add mechanical enforcement so the rules fire even when the agent forgets to invoke the skill:

### CLAUDE.md block (CLI-portable, reversible)

```sh
# Install at the top of your CLAUDE.md
bash install-claude-md-block.sh prepend

# Or at the bottom
bash install-claude-md-block.sh append

# Custom target
bash install-claude-md-block.sh prepend --target /path/to/PROJECT_CLAUDE.md

# Status / uninstall
bash install-claude-md-block.sh status
bash install-claude-md-block.sh remove
```

The block is wrapped in `<!-- BEGIN counter-patterns block -->` ... `<!-- END counter-patterns block -->` markers so the helper finds and removes it cleanly. Re-running `prepend` or `append` is idempotent (existing block is dropped first). A `.bak` is written alongside the target before each modification.

### Hooks (Claude Code only)

```sh
bash hooks/install-hooks.sh install            # copies scripts to ~/.claude/hooks/, prints settings.json snippet
bash hooks/install-hooks.sh status             # report installed scripts
bash hooks/install-hooks.sh uninstall          # removes the scripts (settings.json edited by hand)
```

The hooks add four mechanical enforcement points:

- **PreToolUse branch guard** — blocks Edit/Write/git-commit on protected branches (CP-008).
- **SessionStart primer** — surfaces highest-leverage rules at session start.
- **UserPromptSubmit resume detect** — injects state-reconciliation reminder on resume/pivot cues.
- **Stop pre-completion** — blocks stops on completion language that lacks supporting evidence (cite-the-line, production-caller grep, deploy probe, disposition line). Two-stage: regex pre-filter (free), optional AI judge (cheap, opt-in via `CP_USE_AI=1`).

See `hooks/README.md` for full env-var documentation and the snippet-merge procedure for `settings.json`.

## What this skill explicitly does NOT do

- Modify code or tests (those are agent decisions)
- Replace `/honesty-audit` (different scope: that catches stubs/bypasses; this catches process drift)
- Replace `/deep-review` (this is a process-discipline floor, not a multi-axis review)
- Replace human / external adversarial review (this is the ~80% layer; external review is the load-bearing ~20%)
- Auto-fix anything (it surfaces drift; the agent decides what to do)

## Relationship to other skills

| Skill | When |
|---|---|
| `/honesty-audit` | Every commit, mechanical pattern scan for code-level dishonesty |
| `/counter-patterns` | Before completion claims, after compaction, at checkpoints — process discipline |
| `/deep-review` | Pre-release, full multi-axis judgment review |
| `/branch-review` | When inventorying unmerged branches across the repo |

`/counter-patterns` is the cheapest of the four and runs most often.
