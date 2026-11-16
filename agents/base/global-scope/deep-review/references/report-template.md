# Deep-Review Report Template

Use this exact structure when writing the full report to `{project}/docs/reviews/DEEP_REVIEW_{YYYY-MM-DD}.md`. The rigidity is intentional — consistent structure lets the same reviewer revisit a project in a year and see what changed, and lets someone reading multiple reviews compare across projects.

---

```markdown
# Deep Review — {Project Name}

**Reviewer:** {name or "Claude Code (deep-review skill)"}
**Date:** {YYYY-MM-DD}
**Commit under review:** {short SHA + one-line commit message}
**Method:** Eight-axis deep review per `deep-review` skill. User-journey walk performed. Five-suspicious-files counter-query applied to every "clean" subagent verdict.

---

## TL;DR — Is this shippable?

**{Yes / No / Conditional}.** {One to three sentences. Lead with the verdict; name the top blocker.}

---

## Axes covered

- [x] A — Feature integrity ({N findings})
- [x] B — Stubs & dead code ({N findings})
- [x] C — User-journey walk ({attempted / skipped with reason})
- [x] D — Test quality & honesty ({N findings})
- [x] E — Security boundary ({N findings})
- [x] F — Reliability & logic ({N findings})
- [x] G — Ship hygiene ({N findings})
- [x] H — Doc ↔ code cross-check ({N findings})

If any axis is unchecked, it must appear in the "Coverage gaps" section below with an explicit reason.

---

## Severity ranking used

- **CRITICAL** — Ship-blocker. Exploitable on day one, advertised capability that does not exist, or data-integrity risk with no rollback.
- **HIGH** — Ship-blocker in practice. Fixable quickly; must not slip.
- **MEDIUM** — Fix before ship; tolerable in signed-beta if documented.
- **LOW** — Nice to have; not a ship gate.

All file:line citations were verified directly against source on {YYYY-MM-DD}.

---

## Threat model

Produced per `references/threat-model-template.md`. Full template output should appear here or be linked from here. Minimum inline content:

### Actors in scope
{one-line per actor from §2 of the threat model, including the "compromised agent inside the boundary" and "peer agent" actors which are the highest-leverage adversaries for LLM multi-agent products}

### Assets and sensitivity
{compressed table of §3}

### Trust boundaries
{compressed table of §4}

### Attack surfaces
{list of §5 surfaces AS-01 through AS-n}

### Threat catalog
{STRIDE-per-surface + LLM-specific (T1–T9) — see `references/threat-model-template.md` §6}

### Actor × surface matrix
{compressed matrix from §7}

### Residual risk
{what remains after mitigation — §9}

Every threat in the catalog that is assessed as "missing" or "partial" mitigation must appear as a numbered finding below.

---

## Adversary scenario walkthroughs

For each scenario in `references/threat-model-template.md` §4 of axis-details that is applicable to this product (at minimum: compromised peer agent, compromised plugin, malicious MCP server, malicious config file in user repo, network attacker, same-UID lateral process), produce a narrative walkthrough. One paragraph per scenario with file:line citations for every defense or absence thereof.

### S1 — Compromised peer agent
{narrative walkthrough}

### S2 — Compromised plugin
{narrative walkthrough}

### S3 — Malicious MCP server
{narrative walkthrough}

### S4 — Malicious `.swarm/*.toml` in cloned repo
{narrative walkthrough}

### S5 — Network attacker on daemon listener
{narrative walkthrough}

### S6 — Same-UID lateral process
{narrative walkthrough}

### S7 — Upstream supply-chain compromise
{narrative walkthrough}

---

## CRITICAL findings

### C1. {Finding title}

**Axis:** {A / B / C / …}
**File:** `{path/to/file.rs:line-range}`
**Also:** `{any additional citations}`

{One paragraph describing what is wrong, with a short quoted snippet as evidence.}

```{language}
{quoted code, 3-15 lines}
```

**Why this is critical:** {one sentence on the impact}

**Remediation:**
1. {concrete action with file:line}
2. {concrete action}
3. {concrete action}

---

### C2. {…}

{Repeat pattern for each CRITICAL finding.}

---

## HIGH findings

### H1. {…}

{Same pattern as CRITICAL, slightly terser is acceptable.}

---

## MEDIUM findings

### M1. {…}

{One paragraph plus file:line.}

---

## LOW findings

- **L1.** {one line}, `{file:line}`. {one sentence on impact and fix.}
- **L2.** {…}

---

## Positive findings (things done well)

Keep this brief — the point is to credit patterns that should be preserved or copied elsewhere.

- **{Pattern name}** ({`file:line`}) — {one sentence on what is good about it}
- …

---

## User-journey walk result

**Attempted on:** {date, host OS}

**Steps performed:**

1. `git clone <repo> /tmp/…` → {result}
2. `./scripts/bootstrap.sh` (or documented setup) → {result}
3. `cargo build --workspace` (or equivalent) → {result with timing}
4. `cargo test --workspace` (or equivalent) → {result}
5. Quickstart per README → {result}

**Findings from the walk** are already listed under the appropriate severity tier above. Restate the ship-blocking walk failures here in one line each.

If the walk could not be completed, state the missing prereq and register the gap in "Coverage gaps" below.

---

## Doc ↔ code cross-check table

One row per capability advertised in README / CLI help / UI labels / top-level docs.

| Capability | Advertised at | Delivered at | Status |
|---|---|---|---|
| {capability name} | `README.md:{line}` | `{file:line}` | ✅ WORKS / ⚠ PARTIAL / ❌ ADVERTISED-BUT-FAKE |
| … | … | … | … |

Every ❌ row should also appear as a CRITICAL or HIGH finding above. Every ⚠ row should appear as a MEDIUM or LOW finding.

---

## Contradictions resolved during review

If axis explorers disagreed, document what was contested and how you resolved it. This is evidence of discipline; it also helps the next reviewer.

- **Contested:** {axis B said stubs clean; axis D found 254 hollow test steps}
- **Resolved by:** {re-running axis B with widened pattern set; confirmed 254 count by direct grep}
- **Outcome:** {finding D1 updated; axis B re-reported}

If there were no contradictions, write "None — all axis explorers were consistent."

---

## Coverage gaps

Anything the review could not cover. Each gap must have a reason.

- **{axis or area}** — {specific reason, e.g. "Could not attempt Docker first-run walk: Docker Desktop not available in review environment"}
- …

If there are no gaps, write "None."

---

## Remediation checklist (condensed, in priority order)

Flat list of every remediation action from CRITICAL + HIGH + MEDIUM, in priority order. Easy to paste into a tracking issue.

- [ ] **C1** — {one-line remediation}
- [ ] **C2** — {…}
- [ ] **H1** — {…}
- [ ] **M1** — {…}
- …

---

## Comparison to external audits (appendix, optional)

If other external audits exist in the repo (e.g. `CODEX_REVIEW.md`, `GEMINI_REVIEW.md`), compare *after* producing your findings — not before.

- **Findings you caught that they missed:** {list}
- **Findings they caught that you missed:** {list, with why}
- **Disagreements:** {cases where you disagree with their severity or diagnosis, with reasoning}

This appendix is a feedback loop for the reviewer, not the main deliverable.

---

## Ship gate recommendation

Not a menu. A ship gate is a set of conditions, all required.

Do not ship until:

1. All CRITICAL findings closed in code (not in plan documents), each with a regression test.
2. All HIGH findings closed or explicitly risk-accepted in writing.
3. {Domain-specific gates — e.g. release workflow enabled; one real sandbox backend wired end-to-end; no @planned BDD in the shipping scenario set.}
4. External pentest or second-auditor pass on the hardened build.
5. …

Realistic calendar from {today's date}: **{N}–{M} weeks of focused work.** Do not compress the security-hardening and user-journey repair lanes under pressure.
```

---

## Writing-style notes

- Lead with the verdict. The TL;DR is the most-read section.
- Cite file:line every time. A paraphrase without a citation is a draft note, not a finding.
- Severity tier is not a popularity vote; use it honestly. "Everything critical" signals you did not triage.
- A "positive findings" section matters more than people think — it tells the team what to preserve under pressure.
- If the project is solid, say so clearly. Don't invent findings to justify the review.
