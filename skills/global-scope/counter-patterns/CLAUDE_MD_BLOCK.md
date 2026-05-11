<!-- BEGIN counter-patterns block (managed by AgentSkills counter-patterns skill) -->
<!-- To remove this block: run install-claude-md-block.sh remove --target <this-file> -->

## Counter-Patterns (recurring LLM-coding failure modes)

These are the inverse of failure modes that recur across LLM-assisted coding sessions independent of language, framework, or domain. Each rule states the discipline, why it matters (the mechanism behind the failure), and when to apply it.

Meta-finding worth flagging up front: in cross-project pattern analysis, "shipped fraud" findings — features that look complete and pass self-review but are hollow inside — are consistently caught by **external review with a different model**, not by self-review. Text-only protocols catch roughly 80% of failure modes; the load-bearing 20% requires mechanical guards (hooks, CI lints) plus external adversarial review. Treat the rules below as the 80% layer; treat external review as the load-bearing 20%.

### Tests are not evidence of wiring

A passing unit test on a function says only "this function works in isolation". It does NOT say "this function is called in production". Before declaring a feature complete, grep production code paths for the test's subject. If the only callers are in `tests/` or `*_test.*`, the function is dead code wearing a passing-test costume.

**Why:** Test isolation rewards orphan functions. A function with passing tests inherits "shipped" framing whether or not anyone calls it in production. This is the substrate that makes wiring fraud possible — the test signal cheaply purchases the appearance of completeness.

**How to apply:** For every "shipped" / "wired up" / "implemented" claim, run `git grep -n '<symbol>' -- ':!tests/' ':!**/*_test.*' ':!**/test_*'`. If empty, the symbol has no production caller. Say so.

### Wiring vs backend (the dispatch-path completion rule)

A feature is not "done" until you can trace a code path from the user-facing entry (CLI flag, HTTP route, UI button, MCP tool, config flag) to the backend that handles it, with **no `todo!()`, no `if false`, no commented-out dispatch line, no `_ = handler` discard**, and at least one test exercising the full path end-to-end. Cite TWO file:line locations in the completion report: the entry-point AND the handler.

**Why:** A backend handler is the easy half of a feature; the dispatch from entry-point to handler is the load-bearing half. The pattern is to ship the easy half (with tests) and silently leave the dispatch unwired — commented out, gated behind a permanently-false condition, or simply never added to the dispatch table.

**How to apply:** Every time the work involves an entry point and a handler in different files. Especially: feature flags, MCP tools, HTTP/RPC endpoints, security gates, plugin dispatch, conditional code paths.

### Deploy-validation reads runtime signal, not metadata

A deploy is "successful" only when a runtime probe confirms function — a DB query returns expected data, an HTTP endpoint returns the right status with the right body, an audit-log line appears with the right values. A pipeline reporting `exit 0`. A health endpoint showing "deployed". A redeploy completing without errors. **All of those are metadata and all of them lie if the underlying secret/config is wrong.**

**Why:** Deploy pipelines and health endpoints emit "successful" signals derived from the pipeline's own state, not from whether the deployed service can reach its dependencies. Placeholder secrets, misconfigured DSNs, and permissioning gaps do not block "healthy" readings. Metadata is cheap and abundant; the model reads metadata because metadata is what the deploy pipeline emits.

**How to apply:** Any claim of the form "the deploy is healthy" / "X is up" / "the migration succeeded" must cite a runtime probe, not a deployment log. For databases: a `SELECT 1` or equivalent against the actual DSN. For services: a synthetic request that exercises the persistence layer. For migrations: a row count or schema query. If you can't show the probe output, the claim is wrong.

### Source-of-truth selection

When more than one source could plausibly answer "what should this code do?" — spec/BDD, current code, legacy code, the brief, prose docs — STOP and name the canonical source explicitly before writing anything. Default order: **spec/BDD > UI contract > existing tests > current code > legacy code > prose docs**. Cite which source you used in the commit message ("built against `features/12_surgery.feature` lines 12–40") so a reviewer can spot a wrong-source mismatch.

**Why:** When multiple sources could plausibly answer the question, the model reaches for the closest readable artifact. Short legacy files cost fewer tokens than long specs, so token-economy bias defaults to legacy. Result: PRs built against the wrong source-of-truth, closed and redone.

**How to apply:** Triggered any time the brief mentions both a spec/feature file AND existing code, or when you find a `legacy/`, `old/`, `archive/`, `_v1/` directory. Also when the brief is ambiguous about which artifact is canonical.

### Brief references must resolve before use

When a brief cites a specific path, line range, or PR number, verify it resolves before relying on it. If `Read` returns 404 or the content doesn't match the brief's description, STOP and ask — never substitute the closest match silently.

**Why:** Briefs frequently cite paths or line ranges that don't resolve (typo, stale numbering, wrong repo). Silent substitution produces cascading wrong work because the substitution is invisible — the model narrates as if it had the artifact the user actually meant.

**How to apply:** Any brief that cites a path/file/PR/line/commit by identifier. First action: confirm the identifier resolves to the artifact described.

### Local-narrative bias counter (lift to global checks periodically)

When editing a file, you naturally narrate from that file ("the dispatcher says X handles event Y"). Whether the runtime path *actually* routes X to Y is a non-local check the local diff does not force. Periodically lift: "I'm narrating from this file. Have I traced that the runtime matches?" Especially before any "wired up" / "dispatching" / "calling" claim.

**Why:** When editing a single file, the local goal becomes making that file consistent with itself. The file declares an intent; the model narrates that intent as runtime fact. Whether the runtime path actually matches is a non-local check that the immediate diff does not force. Most shipped-fraud incidents trace to exactly this pattern: narrative coherence within one file substituted for verifiable cross-file behavior.

**How to apply:** Any claim that names a runtime behavior ("dispatches", "calls", "writes", "logs", "sends") — before sending it, run a global grep that proves the path. If the grep is too expensive, say "I haven't verified end-to-end" rather than asserting.

### External adversarial review for load-bearing features

For any feature labeled "production-ready" / "shipping" / "v1.0" / "ready for review" on a load-bearing surface (security, auth, payments, deploy pipeline, multi-agent orchestration, persistence layer): run an external adversarial review before declaring done. Options: `/deep-review`, `/ultrareview`, an external-model review attached to the PR. Self-review catches roughly 80% of failure modes; the remaining 20% is exactly where shipped-fraud features live.

**Why:** Self-review is constrained by the same biases (RLHF reward for confident completion, locality bias, tests-as-cover blindness) that produced the work. External models with no exposure to the prior context, or models trained with different RLHF, surface gaps the original model cannot see. In cross-project pattern analysis, this is the only mechanism that consistently catches Potemkin features.

**How to apply:** Before any merge to main of a feature on the load-bearing surface list. Not as bureaucracy — as the only empirically reliable Potemkin-detector.

### Recommendation followthrough

When you've recommended approach X and the user moves on without explicit acknowledgment, ask "I recommended X — confirming you want X?" before doing Y. Don't quietly downgrade your own recommendations to whichever path is easiest.

**Why:** When the user's next message moves on without explicit acceptance or rejection, the model defaults to the easier path and silently abandons the prior recommendation. The user then has to remind the model of its own prior recommendation — a high-trust failure that erodes the model's role as advisor.

**How to apply:** Any time you've made an architectural or directional recommendation and the user's next message doesn't explicitly accept or reject it.

### Multi-axis brief: budget per axis up front

When a brief lists multiple review or implementation dimensions (e.g. security + reliability + correctness + tests), allocate explicit attention budget per axis BEFORE starting and report findings *per axis* at the end. Empty axes are findings too — "logic: no concerns surfaced" forces you to demonstrate you actually looked.

**Why:** Charismatic axes (security, performance, novelty) crowd out boring ones (correctness, completeness, tests). Without a per-axis report, the gap is invisible — empty axes look the same as "no findings". Per-axis budgeting at the start and per-axis reporting at the end converts attention allocation from implicit to observable.

**How to apply:** Any brief that contains "and" between review dimensions, any "deep review" / "audit" / "review the changes" task. Open the response with the per-axis budget; close with per-axis findings.

### Session continuity (resumes & pivots)

After ANY session compaction, `--continue`, or "Session continued from previous conversation" header, the FIRST tool call must be state reconciliation: `git status && git branch -vv && gh pr list --author @me --state open && git worktree list`. Compare against the compaction summary. If they disagree, surface it before proceeding — don't paper over the gap.

Before any "resume" or "continue" task, also run `git log --oneline -20` on the target branch and read the most recent commits. Build on what's there; never restart from scratch unless explicitly told.

When the user pivots mid-session ("actually...", "stop that...", "let's shift..."), explicitly summarize what you're abandoning and what you're keeping before continuing. Don't silently mix old and new direction.

**Why:** Compaction preserves narrative ("we built X, then Y") but loses concrete state (which branch, which PR, which worktree, which commits actually landed). Agents resume and either redo work that's already on disk or work on stale branches. Mid-session pivots produce hybrid artifacts that confuse later sessions. The reconciliation block reconstructs concrete state cheaply.

**How to apply:** First action after any compaction marker, `--continue`, or "RESUMING" brief. Also any user message starting with "actually", "wait", "stop", "let's shift", "pivot", "instead", or any contradiction of an earlier instruction.

### End-of-task disposition line

End every code-modifying task with one line: `PR #N opened; worktree at /abs/path; branch <name> — propose to delete after merge`. Don't let stale worktrees and branches accumulate.

**Why:** Tasks routinely end with a "shipped" claim but no disposition for the branch, worktree, or PR that held the work. Branches and worktrees accumulate as silent debris; eventually a cleanup pass is needed to identify what's safe to remove. Stating the disposition at end-of-task converts the cleanup from forensic to bookkeeping.

**How to apply:** Every PR, every branch, every worktree creation. Also at the end of any session where you created branches but no PR.

### Destructive authorizations are one-shot

When the user explicitly authorizes a destructive op ("nuke it", "force push approved", "delete the repo"), the authorization applies to that specific operation only — not the rest of the session. Re-confirm for the next destructive op even if one was just approved. Treat "*APPROVED*"-style markers as one-shot, not standing.

**Why:** Destructive ops compound in damage; a session-wide license to be destructive multiplies the blast radius of any later misjudgment. One-shot scoping caps that risk to a single operation per explicit approval.

**How to apply:** Every destructive operation gets its own confirmation, regardless of recent approvals.

### Bulk file generation: globally-unique names

When generating many files of the same kind across nested directories, name each file with a globally-unique key (control ID, ticket ID, timestamp, hash). Imagine `find . -name '*.md' | xargs -I{} cp {} /tmp/all/` — every name should still be distinguishable.

**Why:** Bulk generation under a shared basename makes downstream collation, dedup, and review impossible without a renaming pass. Globally-unique names from the start cost nothing at write time and remove the cleanup entirely.

**How to apply:** Any bulk generation of >5 files. Especially: compliance/audit work, generated test fixtures, generated docs.

### Reminders decay; pair text with mechanical guards

This is a meta-rule. Don't treat any of the rules above as self-enforcing. The rules above catch roughly 80%; the load-bearing 20% is caught by mechanical guards (CI lints, hooks, the `/counter-patterns` skill) and external adversarial review. If an unenforced rule is being relied on, treat that as an enforcement gap to file, not as a rule that's working.

**Why:** Rules in long-context CLAUDE.md files are intermittently honored — defaults reassert across a long session and single mid-session reminders are the weakest signal. Text-only protocols are effective for the majority of cases but not for the load-bearing minority where they matter most.

**How to apply:** When you notice you've drifted from a rule above, surface it explicitly: "I drifted from rule X; here's the catch and the recovery." Don't quietly self-correct without flagging — the drift event is itself evidence the text-only reminder isn't enough and warrants a mechanical guard.

<!-- END counter-patterns block -->
