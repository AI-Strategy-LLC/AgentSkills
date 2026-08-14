---
name: deep-review
description: "Conduct a complete multi-axis review of a software project (feature-integrity, stubs/dead-code, user-journey, test quality, security + full threat model including LLM prompt-injection and agent-to-agent attack paths, reliability, ship hygiene, doc↔code cross-check). Use when the user asks for a 'full audit', 'code review', 'external audit', 'pre-release review', 'threat model', 'is this shippable', 'deep review', or an adversarial review of another agent's work. Delegates to the deep-review agent so the axis-by-axis evidence does not bloat the main conversation's context."
---

# Deep Review

This skill is a thin stub that triggers on "deep review" / "full audit" / "threat model" / "is this shippable" requests and delegates to the `deep-review` agent. The agent does the real work across eight axes (A. Feature integrity, B. Stubs & dead code, C. User-journey walk, D. Test quality, E. Security + threat model, F. Reliability, G. Ship hygiene, H. Doc↔code cross-check) and writes the full report to `docs/reviews/DEEP_REVIEW_{YYYY-MM-DD}.md`.

## What to do

1. Delegate to the **`deep-review`** agent using this harness's subagent mechanism — Claude Code: the `Agent` tool with `subagent_type: "deep-review"`; Pi: the `subagent` tool with `{ agent: "deep-review" }`; otherwise the harness equivalent. If the harness has no subagent mechanism at all, follow the agent's own instructions inline instead of erroring. Pass through any scoping the user provided (specific commit SHA, specific axis emphasis, adversarial-review framing). No other prompt is required — the agent's system prompt has the full 8-axis workflow, the submission gate, and the report template.
2. When the agent returns, relay its four-item output to the user verbatim:
   - Shippable? (yes / no / conditional)
   - Top 3–5 findings with severity tier and axis tag
   - Axes with coverage gaps (if any)
   - Path to the full report on disk
3. Do **not** summarise or soften the findings. If the agent flagged coverage gaps, surface them — don't bury them.
4. Wait for explicit instruction before acting on any finding (fixing stubs, filing issues, rewriting docs). Deep review reports; it does not remediate.

## Why this is an agent, not inline skill work

A deep review produces massive intermediate context: per-axis evidence dumps, parallel Explore-agent reports, a full STRIDE + LLM-threat matrix, and file:line citations across the whole repo. Sequestering it in an agent keeps the main conversation lean and lets the agent enforce its own submission gate (refusing to report without evidence for ≥7 of 8 axes) without the user's working conversation being held hostage to the gate.

## Adversarial-review mode

If the user is asking for a review of another agent's work (multi-model adversarial workflow), say so in the delegation prompt — the agent knows to read the code before the author's framing and to flag disagreement between the author's narrative and the code.
