# Other mechanisms for surviving long sessions and multiple compactions

The skill + hook combo above catches the patterns at task-completion and session-start moments. But Alastair's biggest exposure is *long projects* (DevTeamSwarm, AMIS-Node) where context gets compacted multiple times and the agent loses concrete state. Below are additional mechanisms, ranked by leverage. Pick the ones that fit; they compose.

## 1. `AGENT_STATE.md` at repo root (HIGH LEVERAGE)

A single markdown file at repo root the agent maintains as durable cross-compaction memory.

**Why it works:** Compaction strips conversation context, but files on disk persist. The post-compaction agent reads `AGENT_STATE.md` first and reconstructs orientation in one Read call.

**What goes in it:** Brief, canonical sources, branch/PR/worktree, done-with-cite-the-line, stubbed/deferred, open TODOs, recommendations awaiting confirmation, next planned action. Format defined in `SKILL.md` (`--checkpoint` mode).

**How to enforce:**
- The `/counter-patterns --checkpoint` skill mode writes/updates it.
- A `Stop` hook can warn if the file hasn't been updated this session and there are uncommitted changes.
- Add to `.gitignore`? **No** — commit it. State drift is a code-review-able event when the file is in git history.

**Risks:** Becomes stale if not updated; agents may treat the file's contents as truth even when reality has diverged. Mitigation: `--resume` mode always cross-checks file vs live git/gh state and surfaces drift.

## 2. PR description as state-of-truth (MEDIUM LEVERAGE, ZERO MARGINAL COST)

Treat the GitHub PR body as the durable, multi-agent-readable state record. Every "done" claim, every stub, every deferred TODO goes in the PR body and is updated as the branch evolves.

**Why it works:** PR descriptions survive compaction, are visible to humans, and `gh pr view` is one tool call. They're also the artifact the user is going to read at merge time anyway, so updating them isn't extra work — it's the work that should already be happening.

**Discipline:** Every commit that finishes a milestone should be followed by a `gh pr edit` updating the description. Make this part of the `--check` mode.

## 3. Pre-compaction checkpoint trigger (MEDIUM LEVERAGE)

If/when Claude Code surfaces "context approaching limit" as a hookable event, fire `/counter-patterns --checkpoint` automatically. The agent then has its state durably written before compaction strips it.

**Open question:** does Claude Code expose a `PreCompaction` hook? If not, this is a **system-prompt or harness recommendation**, not something Alastair can implement himself. Today, the workaround is for the agent to checkpoint at every milestone (every PR push, every "phase complete" claim) regardless of whether compaction is imminent.

## 4. `/resume` slash command (HIGH LEVERAGE, LOW EFFORT)

A user-side command that produces a one-page resume primer. The user types `/resume` at the start of any continuation session; it runs the `--resume` mode of the counter-patterns skill, prints the result, and the agent absorbs it as its first action.

**Why it works:** Removes the need for the agent to detect "is this a resume?" — the user signals it explicitly. Removes the need for any harness changes.

**Cost:** A 30-line skill file. (Actually subsumed by `/counter-patterns --resume` — no new skill needed; just a habit.)

## 5. Persistent task list as state (MEDIUM LEVERAGE)

Use Claude Code's `TaskCreate`/`TaskList` consistently for every multi-step task. Tasks persist across compactions in some Claude Code configurations and are queryable via `TaskList`.

**Why it works:** Free state persistence with a built-in tool. Mark tasks `in_progress` when starting, `completed` when done with a cite-the-line, `blocked` with a reason when stuck. A post-compaction `TaskList` reconstructs the remaining work.

**Caveat:** Behaviors of `TaskList` across compactions vary by harness version. Worth testing in current Claude Code build before relying on it.

## 6. Cite-the-commit-SHA on resume (LOW EFFORT, HIGH SIGNAL)

When resuming, the agent should cite specific commit SHAs for prior claims, not narrative ("last time we built the dispatch path") but verifiable ("as of `abc123def`, the dispatch path lives in `crates/seatbelt/src/admission.rs:42`").

**Why it works:** Compaction loses context but commits are durable and SHAs are verifiable in one `git show` call.

**Discipline rule (add to CLAUDE.md):** "When resuming, every claim about prior state must cite a commit SHA you can `git show`."

## 7. Mandatory "I am [post-compaction|fresh|continuing]" preamble (LOW EFFORT, HIGH SIGNAL)

After any compaction, the agent's first message should open with one line: `I am [post-compaction|fresh-session|continuing]; AGENT_STATE.md last updated <ts>; reconciliation: [PASS|DRIFT]`. This invites the user to immediately challenge incomplete state.

**Why it works:** Makes the compaction event visible to the user, who can then decide whether to spend a turn re-orienting the agent or to barrel forward.

## 8. Multi-agent state baton (HIGH EFFORT, HIGH LEVERAGE for DevTeamSwarm)

In DevTeamSwarm-style multi-agent workflows, sub-agents handing off work often lose state at the boundary. Mechanism: a structured handoff document (`HANDOFF-<from>-to-<to>.md`) the sub-agent writes before terminating and the next sub-agent reads first. Subset of `AGENT_STATE.md`, scoped to the handoff.

**Why it works:** Sub-agent compaction is independent of parent compaction; today there's no shared state between them other than what the parent re-injects in the brief. A file-based baton is reliable.

## 9. Session-end recap forced by `Stop` hook (LOW EFFORT, MEDIUM LEVERAGE)

`Stop` hook script that prints a checklist: did you update `AGENT_STATE.md`? did you update the PR description? are there stale worktrees? are there uncommitted changes on a feature branch? Output goes to the conversation as a system note before the agent's final message.

**Why it works:** Catches "agent stops without housekeeping" patterns. Cheap to implement, deterministic.

## 10. CI-side reality check (HIGH LEVERAGE if you trust CI)

Add a CI job that fails the PR if the `AGENT_STATE.md` file is older than the most recent commit on the branch. Forces the agent to keep state current, not just write it once.

**Cost:** A 10-line GitHub Actions step per repo. Optional.

---

## Recommended adoption order

1. **`AGENT_STATE.md` discipline** — start using it on the next long project. Zero infrastructure required, immediate compaction-survival benefit.
2. **`/counter-patterns` skill (with `--check`, `--resume`, `--checkpoint` modes)** — codifies the AGENT_STATE.md and reconciliation patterns mechanically.
3. **The three hook scripts** — branch-guard is the highest-value (stops the recurring "you committed to main" disaster). Session-start primer and resume-detect are quality-of-life.
4. **PR-description-as-truth discipline** — costs nothing, integrates naturally into existing workflow.
5. **Stop hook with housekeeping checklist** — catches end-of-session forgetfulness.
6. **Pre-compaction trigger** — defer until Claude Code exposes the hook.
7. **CI-side reality check** — nice-to-have, optional.
