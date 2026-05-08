---
name: ato-remediation-guidance
description: "Generate REMEDIATION_GUIDANCE.md for an existing ATO artifact package — a developer-facing punch list of concrete code, config, infrastructure, test, and documentation changes that close the gaps surfaced by ato-artifact-collector. Each action item carries a NIST 800-53 control ID, the file location to change, the change to make, and acceptance criteria suitable for hand-off to a remediation agent. Use when the user asks for 'remediation', 'how do we fix the gaps', 'what does the developer need to do', 'feed the gaps to a coder', or a similar developer-action request after an ATO package has been produced. The orchestrator (ato-artifact-collector) invokes this only when the user explicitly asks; it is not part of the default 8-step workflow."
---

# ATO Remediation Guidance

This skill consumes an existing `docs/ato-package/` (produced by
`ato-artifact-collector`) and emits a single new file:
`docs/ato-package/REMEDIATION_GUIDANCE.md`. That file is structured for
an autonomous remediation agent to action, item by item, without
needing to re-read the full package.

It is **not** part of the default ATO workflow. It runs only when the
user explicitly asks for remediation guidance, either by triggering this
skill directly or by asking the orchestrator after a collection run.

## When to run

- The user asks "what does the developer need to fix?" / "give me the
  remediation list" / "what changes need to be made to close these
  gaps?" / "feed this to a coding agent."
- The orchestrator finishes an ATO package and the user explicitly
  requests a remediation hand-off.

## When NOT to run

- The package doesn't exist yet (`docs/ato-package/` is missing or
  empty). Ask the user to run `ato-artifact-collector` first.
- The user wants to *write* policy documents or operational runbooks —
  those are not developer remediation; redirect them.
- The user wants security findings explained (root cause, threat model,
  exploitability) — that is a deep-review task, not a remediation list.

## Hard rules

1. **Read-only on the package.** This skill reads the existing
   `docs/ato-package/` and the working repo, then writes exactly one
   new file: `REMEDIATION_GUIDANCE.md`. It does not modify any existing
   evidence file, narrative, INDEX.md, CHECKLIST.md, or
   CODE_REFERENCES.md.
2. **Developer-actionable only.** The output filters to gaps a
   developer can close inside the repo — code, config, infrastructure
   declarations, tests, repo-managed docs (CONTRIBUTING.md, SECURITY.md,
   CODEOWNERS, threat models, ADRs). Operational records (training
   logs, HR data, incident tickets), inherited CSP controls, and
   org-wide policy documents are listed in a single tail section as
   "out of scope" — not as actions.
3. **Concrete, not aspirational.** Every action specifies a file path
   (or a clear "create at X" path), the change to make, and an
   acceptance test. "Improve logging" is not an action; "Add structured
   audit logging in `app/Filters/AuthFilter.php` with the event
   schema in §3 below; existing tests must still pass and a new test
   in `tests/Feature/AuthAuditLoggingTest.php` must assert that a
   failed-login attempt emits an `auth.failed` event" is.
4. **Every action carries a control reference.** The NIST 800-53
   control identifier (family code, base control, or enhancement) goes
   in the action's frontmatter. Multiple controls are allowed when one
   change satisfies multiple requirements; cite the most specific
   identifier first.
5. **No fabrication.** If the gap is not actionable from inside the
   repo, mark it "Out of scope — operational" and move on. Do not
   invent file paths or imagine modules that don't exist.

## Inputs

The skill expects to find, at the repo root:

```
docs/ato-package/
├── INDEX.md
├── CHECKLIST.md
├── CODE_REFERENCES.md
├── ssp-sections/
│   ├── 01-system-description/
│   │   ├── system-description-evidence.md     ← or system-description-gap-analysis.md
│   │   └── evidence/
│   ├── 02-system-inventory/
│   ├── ... (through 14-privacy-impact-assessment/)
└── controls/
    ├── AC-access-control/
    │   ├── ac-implementation.md
    │   └── evidence/
    │       ├── AC-2/
    │       └── ...
    ├── AT-awareness-training/
    ├── ... (through SR-supply-chain-risk-management/, all 20 families)
```

If `docs/ato-package/` is missing or contains fewer than 5 SSP-section
directories AND fewer than 10 control-family directories, halt with an
error message instructing the user to run `ato-artifact-collector`
first.

## Workflow

### Step 1 — Build the gap inventory

Read every artifact in the package and assemble an in-memory list of
gaps:

1. Parse `CHECKLIST.md` and pull every row whose status is RED or
   YELLOW. Each row gives: section number, sub-item ID, sub-item
   title, control ID(s), status, current evidence, notes.
2. Read every `*-evidence.md` and `*-gap-analysis.md`. For each
   `> **GAP**:` blockquote, extract the gap description, the "Needed
   for" line, and the "Suggested source" if present.
3. Cross-reference with `INDEX.md`'s "Missing Artifacts" tables to
   capture the gap-type tag (REPO-FINDABLE, OPERATIONAL, POLICY,
   INFRASTRUCTURE, INHERITED) for each entry.

### Step 2 — Classify each gap

Bucket every gap into exactly one of:

| Bucket | Includes | This skill emits an action? |
|---|---|---|
| **CODE** | Auth/session/audit/crypto/validation logic in source files | Yes |
| **CONFIG** | Framework configs, env templates, Dockerfile, K8s manifests, web server configs | Yes |
| **INFRA** | Terraform / CloudFormation / OpenShift / GitHub Actions / branch-protection-as-code | Yes |
| **TEST** | Missing security-relevant tests; existing tests that don't assert the security property | Yes |
| **DOC-IN-REPO** | SECURITY.md, CONTRIBUTING.md, CODEOWNERS, threat models, ADRs, README sections | Yes |
| **OPERATIONAL** | Training logs, incident tickets, ticket history, maintenance schedules, signed agreements | No — list as out of scope |
| **POLICY** | Org-level written policy/procedure documents owned by Security/Compliance | No — list as out of scope |
| **INHERITED** | Physical security, environmental controls, shared CSP responsibilities | No — list as out of scope |

REPO-FINDABLE gaps split between CODE / CONFIG / INFRA / TEST /
DOC-IN-REPO based on the actual fix shape. Most CHECKLIST RED rows
will fall into one of these. INFRASTRUCTURE gaps map to INFRA when the
repo carries IaC, otherwise to OPERATIONAL.

### Step 3 — Synthesise concrete actions

For every gap in an action-emitting bucket, produce one or more action
items. Each item has the following shape (Markdown):

```markdown
### RG-NNN — [Short imperative title]

> **Control:** AC-2(4)
> **Type:** CODE
> **Section:** controls/AC-access-control (control AC-2(4)); also relevant to ssp-sections/06-policies-procedures
> **Effort:** S | M | L
> **Blocks:** [optional — RG-NNN that depends on this]
> **Evidence after fix:** [filename(s) the assessor should look at once done]

**Why this matters.** One short paragraph explaining the control and
the gap. Cite the relevant `[CR-NNN]` from `CODE_REFERENCES.md` if the
narrative referenced any.

**What to change.**

- File: `path/to/exact/file.ext`
  - [specific change, with enough detail that an agent can locate the
    insertion / replacement point. Use diff-style snippets only when
    the precise text matters; otherwise plain prose.]
- File: `path/to/another/file.ext` *(create new)*
  - [contents to add]

**How to verify.**

- [ ] [acceptance check 1 — runnable command, log line to look for, or
      file-content assertion]
- [ ] [acceptance check 2]
- [ ] [if a test was added: the exact test command to run]

**Out-of-scope here.** [optional — note related concerns this action
deliberately does not address, so the remediation agent doesn't
scope-creep]
```

`RG-NNN` is monotonic across the document, starting at `RG-001`. It is
distinct from `CR-NNN` (which lives in `CODE_REFERENCES.md`).

The **Effort** field is a coarse estimate:
- `S` — under one engineer-day, isolated change
- `M` — one to three engineer-days, may touch multiple files
- `L` — multi-day, requires design discussion, or crosses team boundaries

The **Blocks** field is optional; use it when one action is a
prerequisite for another so the remediation agent does them in order.

### Step 4 — Group, order, and emit

Group the action items by control family (AC, AT, AU, …, SR), with
SSP-document actions appearing under their primary supporting family
(e.g. an action to add a missing IRP attachment goes under `IR`, an
action to fix the SDLC document goes under `SA`). Within each family,
order: blockers first, then by control-ID, then by RG-NNN. Each family
becomes a `## CF — Family Name` heading; each action becomes a `### `
heading underneath it.

### Step 5 — Write the document

Emit `docs/ato-package/REMEDIATION_GUIDANCE.md` with the structure
below. Do not modify any other file.

## Output structure

```markdown
# ATO Remediation Guidance

> **Repository:** [repo name]
> **Generated:** [date]
> **Driven by:** `docs/ato-package/CHECKLIST.md` (snapshot date), `docs/ato-package/INDEX.md`
> **Total actions:** N (S: a, M: b, L: c)
> **Status:** Hand-off document for a remediation agent — every item is
> developer-actionable inside this repo.

## How to read this document

Each action below is independent unless its `Blocks:` line names another
action. Work top-to-bottom; actions are ordered so blockers come first.
Mark an action complete by checking off every box under "How to verify"
and then re-running `ato-artifact-collector` to confirm the corresponding
CHECKLIST row turns from RED/YELLOW to GREEN.

The control identifier on each action (e.g. `AC-2(4)`) is the NIST
800-53 Rev 5 control or enhancement that the change is evidence for.
Cite that identifier in commit messages so the next package run can
re-link the citation automatically.

## Summary

| RG | Control | Type | Family | Effort | Title |
|---|---|---|---|---|---|
| RG-001 | AC-2(4) | CODE | AC | S | Emit account-management audit events from UserController |
| RG-002 | AU-3 | CONFIG | AU | S | Switch logging format to JSON with required fields |
| RG-003 | SC-7 | INFRA | SC | M | Add OpenShift NetworkPolicy for app namespace |
| ... | ... | ... | ... | ... | ... |

---

## AC — Access Control

### RG-001 — Emit account-management audit events from UserController

> **Control:** AC-2(4)
> **Type:** CODE
> **Section:** controls/AC-access-control (control AC-2(4)); also relevant to ssp-sections/06-policies-procedures
> **Effort:** S
> **Evidence after fix:** `app/Controllers/UserController.php`, `tests/Feature/AccountAuditTest.php`

[... full action body per Step 3 template ...]

### RG-002 — ...

---

## AU — Audit and Accountability

### RG-003 — ...

---

## Out of scope for developer remediation

The gaps below appeared in `CHECKLIST.md` but cannot be closed by
changes inside this repo. They are listed here so nothing falls
through, but a remediation agent should not act on them. Each item is
tagged with the team most likely to own it.

| Section | Sub-item | Control | Owner | Note |
|---|---|---|---|---|
| controls/PS-personnel-security | PS-3 Background check records | PS-3 | HR / Personnel Security | Records live in HR system, not this repo |
| controls/PE-physical-environmental | PE-* | PE-* | CSP (FedRAMP package) | Inherited from cloud provider |
| controls/AT-awareness-training | AT-2 Training completion records | AT-2 | L\&D / Security Training team | Tracked in LMS, not this repo |
| ... | ... | ... | ... | ... |
```

## Style rules

- **Imperative, present tense** in every action title ("Add X", "Switch
  Y to Z", "Replace cleartext password storage in W"). Never
  past-tense, never gerund.
- **One change per action.** If a fix touches multiple files, list them
  all under the same action only when they form a single logical
  change (e.g. "add the new column AND backfill it"). Otherwise split.
- **No "review and consider"-style items.** Every action specifies what
  to do, not what to think about.
- **Match the file path to the actual repo.** Read the repo's directory
  structure before writing path strings. Do not invent paths.
- **Cite a control on every action.** No exceptions; if no control
  applies, the gap doesn't belong in this document.
- **Mermaid diagrams stay in the family narratives, not here.**
  REMEDIATION_GUIDANCE.md is a punch list, not a design doc.

## When the orchestrator invokes this skill

`ato-artifact-collector` will not run this skill as part of its
default 8-step workflow. If the user, after the package is produced,
says something like "now turn this into a list of changes for the
developer" / "what should I tell the coding agent to fix?", the
orchestrator should invoke this skill via the Skill tool with no
arguments — the skill reads `docs/ato-package/` directly.

If the user phrases the request *before* the package exists ("we want
the gaps and a remediation list"), the orchestrator runs its full
8-step collection first, then invokes this skill once at the end.
