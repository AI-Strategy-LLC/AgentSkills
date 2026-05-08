# Gap-driven artifact synthesis — Step 6.6 reference

When the assessment pass classifies a Determine If ID as `NotSatisfied` because the **implementation exists in code/config but a formal artifact is missing**, Step 6.6 generates a draft artifact for human review. The draft is written under `controls/<CF>-<slug>/evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/synthesized/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md` and listed in a top-level `SYNTHESIZED_ARTIFACTS.md` inventory. The `<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_` prefix matches the Step 4.6 manifest convention: it keeps every orchestrator-generated file uniquely identifiable when an assessor flattens the package or copies files into a GRC tool.

This reference defines the gap-detection heuristic, the templates for common synthesized artifacts, and the auto-promote semantics for the `--accept-synthesized` flag.

## Gap-detection heuristic

Step 6.6 walks every Determine If ID where `Result: NotSatisfied`. For each, it inspects the Findings paragraph (just produced by Step 6.5) and decides whether the gap is **synthesizable**.

A gap is synthesizable when **all** of the following hold:

1. **Positive evidence claim present.** The Findings paragraph contains language like "the evidence directly supports", "the system does", "the implementation describes". This signals the implementation exists.
2. **Missing-artifact gap, not missing-implementation gap.** The Findings paragraph contains language like "does not explicitly map", "no document specifies", "no artifact maps", "lacks a written matrix", "is not stated as a standalone document". This signals the gap is documentation, not behaviour.
3. **Synthesis input is in the package.** The orchestrator can synthesize the missing artifact only from inputs already collected — code, config, IaC, evidence files. If the gap requires operational data (HR records, training logs, signed AUPs, physical security plans), it is NOT synthesizable.

Conversely, a gap is **NOT** synthesizable when:

- The implementation itself is missing ("no automated workflow detected", "no logging of [event]"). Synthesis would fabricate the implementation.
- The required artifact is operational policy or a signed document (acceptable use policy, training certificate, physical access roster).
- The Findings paragraph names "operational", "policy", "inherited", or "out of scope" as the gap category.

When unsure, **do not synthesize**. The Findings paragraph already names the gap; an unsynthesized row leads to a remediation action via `ato-remediation-guidance`. Spurious drafts are worse than no draft — they create review burden and risk being adopted unreviewed.

## Common synthesizable artifacts

These are the recurring "implementation present, artifact missing" patterns the orchestrator should recognise. Each has a template; all live under `synthesized/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md`. The `<artifact-slug>` portion is the human-readable shorthand listed below; the prefix is computed from the Determine If ID's parent-control family + control + Determine If ID.

### 1. User role matrix (AC-02(d), AC-06(01), AC-06(02), AC-06(05))

Required when the system enforces role-based authorization in code but no artifact maps roles onto the federal Privileged / Non-Privileged / No-Logical-Access categories.

**Inputs**: role enum / type / constants in code; the role-check middleware; any per-role permission matrix in config.

**Template** (`<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_role-matrix-draft.md` — e.g. `AC_AC-02_AC-02(d)_role-matrix-draft.md`):

```markdown
---
status: DRAFT
generated_by: ato-artifact-collector
generated_from: code/config inspection
generated_at: <ISO 8601 timestamp>
needs_review: true
control: AC-02
determine_if_id: AC-02(d)
gap_addressed: "User role matrix mapping roles onto Privileged / Non-Privileged / No-Logical-Access"
sources:
  - <CR-NNN of role enum file>
  - <CR-NNN of role-check middleware>
  - <CR-NNN of permission matrix, if any>
---

# DRAFT — User Role Matrix (<system name>)

> ⚠ **DRAFT — generated from code inspection.** This document was synthesized
> by the ATO orchestrator from the role definitions and authorization
> middleware in this repository. It has NOT been reviewed by the system
> owner. Read carefully, edit, and decide whether to adopt before
> referencing it as official ATO evidence.

## Roles

| Role | Internal/External | Privilege class | Logical access | Source |
|---|---|---|---|---|
| <ROLE_1> | <Internal\|External> | <Privileged\|Non-Privileged\|No Logical Access> | <plain-English access scope> | [CR-NNN] |
| <ROLE_2> | ... | ... | ... | [CR-NNN] |

## Privilege class definitions (federal)

- **Privileged**: Account has authorities that allow it to bypass, alter, or
  control access to resources. Examples: administrator, auditor with reset
  authority, root.
- **Non-Privileged**: Account has only the authorities required for the user's
  job function. Cannot bypass access controls or grant authority to others.
- **No Logical Access**: Account exists for record-keeping or contact purposes
  only; cannot authenticate to the system.

## How privilege class was assigned

[1–3 sentences explaining the orchestrator's reasoning per role. For each
Privileged role, name the specific code path that grants the bypass.
Example: "The ADMINISTRATOR role is classified Privileged because the
checkAreaPermission function returns true unconditionally for administrators
without consulting the per-area permission table."]

## Open questions for the system owner

- [ ] Is the assignment of <ROLE_X> as <Privileged|Non-Privileged> consistent
      with org policy? (The orchestrator inferred this from code; org policy
      may override.)
- [ ] Are there service principal / non-human accounts (e.g., the Function
      App's resource role) that should appear in this matrix as
      "No Logical Access" or as "Privileged at the resource layer"?
- [ ] Are there roles defined elsewhere (database, infra) that don't show
      up in the application code? If so, add rows.
```

### 2. Account-type definition table (AC-02(a))

Required when the system has well-defined account types in code but no document enumerates them with their attributes.

**Inputs**: account types in code, identity provider config, service principal definitions.

**Template** (`<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_account-types-draft.md` — e.g. `AC_AC-02_AC-02(a)_account-types-draft.md`):

```markdown
---
status: DRAFT
generated_by: ato-artifact-collector
generated_from: code/config inspection
control: AC-02
determine_if_id: AC-02(a)
gap_addressed: "Documented account-type definitions"
sources: [...]
---

# DRAFT — Account Types (<system name>)

> ⚠ **DRAFT — generated from code inspection.** Not yet reviewed by the
> system owner. Verify before adopting as ATO evidence.

| Type | Description | Provisioning method | Authentication method | Lifecycle owner |
|---|---|---|---|---|
| <Individual user account> | <how the role is described in code> | Manual by AMIS administrator [CR-042] | NIH SAML SSO [CR-058] | AMIS administrator |
| <Service principal> | Function App runtime identity | Provisioned in Azure AD | Managed identity / OIDC | Cloud team |

## Prohibited account types

[List any explicitly-prohibited account types — usually shared accounts,
local fallback accounts, etc. Cite where the prohibition is enforced or
documented in code.]
```

### 3. Privileged-account list (AC-06(02), AU-09(04))

Required when the system has privileged-access logic in code but no inventory of who currently holds privileged access.

**Inputs**: role-grant code, the database schema or fixture data showing initial privileged users, IaC role assignments, the audit-log code that records privilege use.

**Template** (`<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_privileged-accounts-draft.md` — e.g. `AC_AC-06_AC-06(02)_privileged-accounts-draft.md`):

```markdown
---
status: DRAFT
generated_by: ato-artifact-collector
generated_from: code/config inspection
control: AC-06
determine_if_id: AC-06(02)
gap_addressed: "Privileged account inventory"
sources: [...]
---

# DRAFT — Privileged Accounts (<system name>)

> ⚠ **DRAFT — generated from code inspection.** This list is derived from
> code-level role definitions and may not reflect the current authoritative
> set of privileged users in production. The system owner MUST verify against
> the live identity store before adopting.

## Application-layer privileged accounts

| Account | NED ID / login | Granted role | Granted on | Source |
|---|---|---|---|---|
| _(Names redacted; the orchestrator does not export real user data into the package. Replace with current production list.)_ | | | | |

## Resource-layer privileged accounts

| Identity | Scope | Role | Source |
|---|---|---|---|
| <Function App service principal> | <subscription/resource group/resource> | <Storage Blob Data Owner | Key Vault Secrets User | ...> | [CR-NNN of IaC] |

## Open questions for the system owner

- [ ] Verify the application-layer table against the current AMIS user table
      (`SELECT ned_id, role FROM users WHERE role = 'ADMINISTRATOR'`).
- [ ] Confirm no privileged users have been added outside the audit log.
- [ ] Confirm no resource-layer roles have been assigned to identities not
      listed above.
```

### 4. System-owner / system-component inventory (CM-08, PL-02)

Required when the SDD names the system's components (containers, services, IaC resources) but no canonical inventory document exists.

**Inputs**: Dockerfiles, docker-compose, K8s manifests, IaC, package manifests, dependency files.

**Template** (`<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_system-components-draft.md` — e.g. `CM_CM-08_system-components-draft.md` for a single-Determine-If control):

```markdown
---
status: DRAFT
generated_by: ato-artifact-collector
generated_from: IaC + container manifests
control: CM-08
determine_if_id: CM-08
gap_addressed: "System component inventory"
sources: [...]
---

# DRAFT — System Component Inventory (<system name>)

> ⚠ **DRAFT — generated from IaC inspection.** This inventory is structural;
> it does not include patch levels, owner names, or recovery priorities.
> Adopt as a starting point and add operational metadata.

## Compute

| Component | Type | Image / runtime | Source |
|---|---|---|---|

## Data stores

| Component | Type | Location | Encryption at rest | Source |
|---|---|---|---|---|

## External dependencies

| Component | Vendor | Connection | Source |
|---|---|---|---|

## Network boundary

[Mermaid diagram from the SDD's Section 1, copied here. Verify the boundary
matches the production reality before adopting.]
```

### 5. Continuous monitoring sampling plan (CA-07)

Required when the system has CI/CD-driven scanning (vuln, secret, SAST) but no document spelling out the cadence and sample size.

**Inputs**: CI workflow files, scheduled-scan configs, the vulnerability scanner's output from Step 1.5.

**Template** (`<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_conmon-sampling-plan-draft.md` — e.g. `CA_CA-07_conmon-sampling-plan-draft.md`):

```markdown
---
status: DRAFT
generated_by: ato-artifact-collector
generated_from: CI/CD configuration
control: CA-07
determine_if_id: CA-07
gap_addressed: "ConMon sampling plan"
sources: [...]
---

# DRAFT — Continuous Monitoring Sampling Plan (<system name>)

> ⚠ **DRAFT — generated from CI/CD inspection.** Verify cadence and sample
> sizes match operational reality and risk tolerance.

## Scan schedule

| Scan | Tool | Trigger | Cadence | Coverage | Source |
|---|---|---|---|---|---|
| Dependency vulnerabilities | <tool> | <PR / nightly / on push> | <every PR / daily> | <100% / sampled> | [CR-NNN] |
| Secrets in source | gitleaks | <pre-commit / PR / nightly> | ... | full repo | [CR-NNN] |
| SAST | semgrep | <PR / weekly> | ... | full repo | [CR-NNN] |
| Container image | trivy | <build / nightly> | ... | every image | [CR-NNN] |

## Reporting

[Where findings land — the dated vulnerability-scan-{date}.md files in this
package, the CI summary, the security team's tracking system. Cite paths.]
```

## SYNTHESIZED_ARTIFACTS.md inventory

Top-level file at `docs/ato-package/SYNTHESIZED_ARTIFACTS.md`. One row per draft.

```markdown
# Synthesized Artifacts — DRAFTS for Review

> **Generated**: <date>
> **Total drafts**: N
> **Status**: All drafts under review unless `--accept-synthesized` was passed.

This file lists every draft document the orchestrator generated to address a
"implementation present, artifact missing" gap. Each draft is in the
`synthesized/` subfolder of the relevant Determine If ID's evidence
directory. **Drafts are NOT official ATO evidence until reviewed.**

## How to review

1. Open the draft and check every entry against the live system state.
2. Edit or rewrite as needed.
3. Either:
   - **Accept**: copy or move the file from
     `synthesized/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md`
     up one folder to
     `evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md`
     (preserve the filename so the audit trail is preserved) and re-run
     the orchestrator (Step 6.5 will detect the present artifact and flip
     Result to Satisfied).
   - **Reject**: delete the draft. The Determine If ID stays
     NotSatisfied; the gap rolls into the next remediation cycle.

| Control ID | Determine If ID | Artifact | Status | Path |
|---|---|---|---|---|
| AC-02 | AC-02(d) | User role matrix | DRAFT — needs review | `controls/AC-access-control/evidence/AC-02/AC-02(d)/synthesized/AC_AC-02_AC-02(d)_role-matrix-draft.md` |
| AC-02 | AC-02(a) | Account-type definitions | DRAFT — needs review | `controls/AC-access-control/evidence/AC-02/AC-02(a)/synthesized/AC_AC-02_AC-02(a)_account-types-draft.md` |
| CM-08 | CM-08 | System-component inventory | DRAFT — needs review | `controls/CM-configuration-management/evidence/CM-08/synthesized/CM_CM-08_system-components-draft.md` |
```

When `--accept-synthesized` was set, rows that the orchestrator auto-promoted carry status `ACCEPTED (auto, <ISO timestamp>)` instead of `DRAFT — needs review`. The original draft stays under `synthesized/` for audit; the promoted copy is at the parent level.

## `--accept-synthesized` semantics

When the user invokes the orchestrator with `--accept-synthesized`:

1. Step 6.6 generates the draft normally under `synthesized/`.
2. Immediately after writing the draft, Step 6.6 copies it from `synthesized/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md` to `evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md` (one level up; same filename). The promoted copy:
   - Drops the `⚠ DRAFT` banner (replaced with a `> Generated by ato-artifact-collector on <date>; reviewed-and-accepted=auto via --accept-synthesized.` banner).
   - Keeps the YAML frontmatter's `generated_by` and `generated_from` lines for audit traceability.
   - Sets `status: ACCEPTED-AUTO` (was `DRAFT`).
3. Re-run the assessment for that Determine If ID. If the missing artifact is now present (the Findings paragraph would no longer name it as missing), flip `Result: Satisfied` and update the Findings paragraph: "The evidence supports the requirement, including the synthesized role matrix at `<path>` (auto-promoted via `--accept-synthesized`; review before authoritative submission)."
4. Update `SYNTHESIZED_ARTIFACTS.md`'s row for this artifact: status becomes `ACCEPTED (auto, <ISO timestamp>)`.

**Loud signaling.** Auto-promotion is risky — synthesized drafts make assertions about the system from code inspection alone, and they may be wrong (e.g., a role classification that org policy disagrees with). The orchestrator surfaces every auto-promoted artifact loudly:

1. **End-of-run summary block.** Print a prominent block at the end of the orchestrator's output:
   ```
   ⚠ AUTO-PROMOTED: 5 synthesized artifacts adopted as evidence.
     - controls/AC-access-control/evidence/AC-02/AC-02(d)/AC_AC-02_AC-02(d)_role-matrix-draft.md
     - controls/AC-access-control/evidence/AC-02/AC-02(a)/AC_AC-02_AC-02(a)_account-types-draft.md
     - controls/AC-access-control/evidence/AC-06/AC-06(02)/AC_AC-06_AC-06(02)_privileged-accounts-draft.md
     - controls/CM-configuration-management/evidence/CM-08/CM_CM-08_system-components-draft.md
     - controls/CA-assessment-authorization/evidence/CA-07/CA_CA-07_conmon-sampling-plan-draft.md
     Review SYNTHESIZED_ARTIFACTS.md and each promoted file before treating
     this package as authoritative.
   ```
2. **INDEX.md banner.** At the top of `docs/ato-package/INDEX.md`, before the table of contents, insert:
   ```markdown
   > ⚠ **AUTO-PROMOTED ARTIFACTS PRESENT.** This package contains N
   > synthesized artifacts that were auto-promoted from drafts via the
   > `--accept-synthesized` flag. Review `SYNTHESIZED_ARTIFACTS.md` and
   > each promoted file before authoritative submission.
   ```
3. **CHECKLIST.md notes column.** For every Determine If ID whose Result was flipped from NotSatisfied to Satisfied due to auto-promotion, the Notes column carries `Auto-promoted draft — review before submission`.

The loud signaling exists because the auto-promote flag is a fast-iteration tool, not a way to launder unreviewed assertions into ATO evidence.

## Idempotency on re-run with `--accept-synthesized`

If the orchestrator runs twice with `--accept-synthesized`:

1. Step 6.6 detects the previously-promoted file at `evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md` (NOT under `synthesized/`).
2. The file's frontmatter has `status: ACCEPTED-AUTO` and a `generated_at` timestamp from the prior run.
3. Step 6.6 compares the current run's draft (newly generated under `synthesized/`) against the promoted file. If the contents are byte-identical, do nothing — the artifact is already adopted. If different, write the new draft to `synthesized/` BUT do NOT auto-overwrite the promoted file. Update SYNTHESIZED_ARTIFACTS.md's row to status `DRAFT-CHANGED (auto-promoted-stale, <date>)` so the user sees that a re-run produced a different draft and the live evidence may be out of date.
4. Never auto-overwrite an existing `evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md`. The orchestrator never destroys a previously-accepted artifact silently.

## When NOT to synthesize

The orchestrator MUST refuse to synthesize when:

- The Findings paragraph indicates the implementation itself is missing (not just the artifact). Examples: "no automated workflow detected", "no audit logging for [event]". Synthesis would fabricate the implementation.
- The Determine If ID is in a family the orchestrator does not have synthesis templates for AND the orchestrator cannot produce a structurally meaningful draft from the inputs at hand. Better to leave a NotSatisfied row than emit a sparse draft.
- The user passed `--no-synthesize`. Step 6.6 is a no-op; SYNTHESIZED_ARTIFACTS.md is not written; the per-family narrative's Findings paragraph mentions the missing artifact textually but does not point at a draft.

## Where to look first when adding a new template

The five templates above cover most AC-family and CM-family gaps. New synthesizable patterns will likely emerge in:

- **AT** (Awareness and Training) — training plan from CI hooks.
- **AU** (Audit and Accountability) — audit-event catalog from logging code.
- **IR** (Incident Response) — IR roles inventory.
- **PE** (Physical and Environmental) — usually NOT synthesizable (operational).
- **PS** (Personnel Security) — usually NOT synthesizable (HR data).
- **SC** (System and Communications Protection) — boundary diagram, key inventory.

When adding a new template, follow the same shape: YAML frontmatter, banner, source-cited table, open questions, never publish PII without redaction.
