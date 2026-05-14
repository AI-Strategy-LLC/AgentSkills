---
name: adversarial-review
description: "Get a second-opinion review from a different AI model — dispatches a review skill (deep-review, branch-review, bdd-audit, honesty-audit, counter-patterns, coverage-audit) to a different CLI (codex, gemini, opencode, crush, kilo) via the AdversarialReviewMCP server. Use when the user asks for 'external review', 'adversarial review', 'second opinion', 'different model review', 'check this with another model', or before merging anything on a load-bearing surface (security, auth, deploy pipeline, persistence, multi-agent orchestration) where self-review's 80% catch rate isn't enough. Requires the AdversarialReviewMCP server to be installed and registered with this CLI (one-time setup; see step 1 below)."
---

# Adversarial Review

CLAUDE.md treats external adversarial review with a different model as the
load-bearing 20% of honesty defense — the only mechanism that consistently
catches "shipped fraud" features that look complete on self-review but are
hollow inside.

This skill is the trigger that routes such requests through the
**AdversarialReviewMCP** server, which spawns a different AI CLI to run the
requested review. The server lives in its own repository:
<https://github.com/AI-Strategy-LLC/AdversarialReviewMCP>.

## What to do

1. **Confirm the MCP server is registered.** Call the `list_reviewers` MCP
   tool. If it errors, the server isn't installed — direct the user to:
   ```bash
   git clone https://github.com/AI-Strategy-LLC/AdversarialReviewMCP
   cd AdversarialReviewMCP
   bash install.sh --for claude     # (or --for codex, gemini, cursor, …)
   ```

2. **Confirm at least one reviewer is installed and authenticated.** From
   `list_reviewers`, surface any reviewer with `installed: false` or
   `authenticated: false` — the user must install/log in to a reviewer CLI
   different from the one running this session. (If Claude is the host, the
   reviewer should NOT be Claude; pick codex / gemini / crush / opencode /
   kilo.)

3. **Pick the skill.** Translate the user's intent:
   - "is this shippable / full audit / threat model / deep review" → `deep-review`
   - "what's in our branches / CHANGES.md / merge or prune" → `branch-review`
   - "spec coverage / BDD drift / gherkin alignment" → `bdd-audit`
   - "are we cheating / stubs / tautological tests / cite-the-line" → `honesty-audit`
   - "process discipline / wiring claims / source of truth / am I drifting" → `counter-patterns`
   - "test coverage gaps / how covered is X" → `coverage-audit`

4. **Pick the reviewer.** Use whatever the user named, OR `auto` if
   unspecified. Auto-fallback order: codex → gemini → crush → opencode → kilo.

5. **Call the MCP tool.** Either `adversarial_review` with `skill=` /
   `reviewer=` / `repo_path=` (absolute), or one of the per-skill convenience
   tools (`deep_review`, `honesty_audit`, etc.).

6. **Relay the result honestly.**
   - Report `provider`, `model`, `report_path`, and the `summary`.
   - Do NOT soften findings. Adversarial review's value is catching what
     self-review missed; if the reviewer found something, surface it.
   - If `report_path` is set, suggest the user `Read` it for full detail.
   - If `findings_count` is set, lead with the count.

7. **Wait for explicit instruction before remediating.** Adversarial review
   reports; it does not remediate. The user decides what to act on.

## When to invoke proactively

The CLAUDE.md doctrine names a load-bearing surface list: security, auth,
payments, deploy pipeline, multi-agent orchestration, persistence layer.
Before merging or shipping work that touches any of those:

- Ask the user whether they want adversarial review.
- If yes, route through this skill.

A self-review (`/deep-review` running in the same Claude session) is fine
for everything else, but for the load-bearing list it's the wrong instrument
— same model, same biases.

## What this skill is NOT

- Not a wrapper around `/deep-review` running in this session. That's
  self-review. This skill ALWAYS goes to a different CLI.
- Not a remediator. It collects findings; it doesn't fix anything.
- Not a substitute for `/honesty-audit` or `/counter-patterns` running
  locally as CI gates. Adversarial review is a load-bearing checkpoint, not
  a cheap-and-fast scan.

## If no other CLI is installed

Direct the user to install at least one:

```bash
# Codex (OpenAI)
brew install openai/codex/codex   # or: npm i -g @openai/codex

# Gemini (Google)
npm install -g @google/gemini-cli

# Crush (Charm — multi-provider)
brew install charmbracelet/tap/crush

# OpenCode
curl -fsSL https://opencode.ai/install | bash
```

Then `bash <AgentSkills>/install.sh --for <cli>` to give that CLI the
review skills (the skills live in this repo; the MCP server lives in
AdversarialReviewMCP).
