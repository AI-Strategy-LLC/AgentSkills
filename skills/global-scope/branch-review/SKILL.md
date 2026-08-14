---
name: branch-review
description: "Review unmerged branches, classify each, produce CHANGES.md, and recommend merge/prune/PR actions. Use when the user asks to audit the branch state or produce a CHANGES.md. Delegates the investigation to the branch-review agent so per-branch evidence does not bloat the main conversation's context."
---

# Branch Review

This skill is a thin stub that triggers on "review branches" / "produce CHANGES.md" requests and delegates to the `branch-review` agent. The agent does the real work and writes `CHANGES.md` at the repo root.

## What to do

1. Delegate to the **`branch-review`** agent using this harness's subagent mechanism — Claude Code: the `Agent` tool with `subagent_type: "branch-review"`; Pi: the `subagent` tool with `{ agent: "branch-review" }`; otherwise the harness equivalent. If the harness has no subagent mechanism at all, follow the agent's own instructions inline instead of erroring. No prompt required beyond stating the working directory context — the agent's system prompt has the full workflow.
2. When the agent returns, relay its recommendation table to the user. The full per-branch detail lives in `CHANGES.md` on disk.
3. Wait for explicit instruction before merging, pruning, or creating PRs. If the user wants to act on multiple PRs at once, hand off to `merge-sprint`.

## Why this is an agent, not inline skill work

`branch-review` reads `git log`, `git diff`, and `gh pr list` output for every unmerged branch in the repo. That output is verbose and one-time; sequestering it in an agent's context keeps the main conversation lean.
