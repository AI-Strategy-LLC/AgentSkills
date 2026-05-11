---
name: counter-patterns
description: "End-of-task and resume-time checks for the recurring failure modes documented in CLAUDE.md (source-of-truth selection, wiring-vs-backend completion, multi-axis brief discipline, session-resume state drift, branch/worktree hygiene, recommendation followthrough). Mechanical where possible; agent-facing checklist where not. Triggers on 'counter-patterns', 'before I declare done', 'am I drifting', 'resume check', 'pre-compaction checkpoint', 'post-compaction reconcile'. Distinct from /honesty-audit (lint-tier mechanical scan for stubs/bypasses) and /deep-review (broad multi-axis review): this skill enforces the *process discipline* counter-patterns. Has three modes: --check (run end-of-task checks), --resume (post-compaction reconciliation), --checkpoint (write AGENT_STATE.md before risky long-running ops)."
---

# Counter-Patterns

Enforces the process-discipline counter-patterns documented in `~/.claude/CLAUDE.md` so they don't depend on the agent remembering across compactions or under deadline pressure.

This is not a code-quality scan (use `/honesty-audit` for that) and not a content review (use `/deep-review` for that). It catches the **process** failures: drifting source-of-truth, half-wired features, missing per-axis coverage, lost state after compaction, branch/worktree drift, recommendations the agent quietly downgraded.

## Three modes

### `--check` (default, run before declaring a task done)

Sequence of checks. Each prints `PASS | WARN | FAIL` and a one-liner. Skill exits non-zero on any FAIL so it can gate completion claims.

| Check | What it does | How |
|---|---|---|
| **branch** | Are we on a feature branch, not main/master/develop? | `git branch --show-current` ≠ protected list |
| **worktree-pwd-match** | Does `pwd` match the expected worktree from the brief? | `git rev-parse --show-toplevel`; compare to brief's stated path if recorded |
| **dispatch-trace** | For each "wired up" claim in the staged commit message, does an entry-point file actually call the handler? | Parse commit msg for `wired up X` / `now dispatches Y`; grep entry-point files (configurable: `src/main.*`, `src/cli/*`, `src/api/*`, `routes/*`) for handler symbol |
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
- Approaching context limit (Claude Code surfaces this) → `/counter-patterns --checkpoint`

## What this skill explicitly does NOT do

- Modify code or tests (those are agent decisions)
- Replace `/honesty-audit` (different scope: that catches stubs/bypasses; this catches process drift)
- Replace human review (this is a floor, not a ceiling)
- Auto-fix anything (it surfaces drift; the agent decides what to do)

## Relationship to other skills

| Skill | When |
|---|---|
| `/honesty-audit` | Every commit, mechanical pattern scan for code-level dishonesty |
| `/counter-patterns` | Before completion claims, after compaction, at checkpoints — process discipline |
| `/deep-review` | Pre-release, full multi-axis judgment review |
| `/branch-review` | When inventorying unmerged branches across the repo |

`/counter-patterns` is the cheapest of the four and runs most often.
