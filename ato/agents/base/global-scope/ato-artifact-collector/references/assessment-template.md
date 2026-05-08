# Assessment-pass template — Step 6.5 reference

The assessment pass runs after the per-family narrative is written. For every Determine If ID in the inventory, it produces a **Findings paragraph** and a **Result** value (`Satisfied` / `NotSatisfied` / blank). This reference defines the paragraph structure, the decision rules for the Result column, and worked examples drawn from the AMIS assessment spreadsheet.

The orchestrator's job in Step 6.5 is **NOT** to re-do the implementation analysis — that already happened in Steps 4–6. The job is to compare the **Determine If Statement** (what the system does, just emitted into the per-family narrative) against the **requirement text** (from `.staging/sub-control-inventory.json`) and write the assessor's judgment.

## Inputs

For each Determine If ID, the assessment pass reads:

1. The `text` field from the sub-control inventory — the requirement language NIST 800-53 specifies for this Determine If ID.
2. The `**Determine If Statement.**` paragraph in the per-family narrative — the implementation narrative the orchestrator just generated.
3. The per-Determine-If-ID manifest emitted in Step 4.6 (`<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_relevant-evidence.md`) — which parent-level evidence files address this Determine If ID.
4. (Optional) Adjacent Determine If IDs in the same control — sometimes the requirement language references a sibling sub-letter ("as required in (a)").

## Findings paragraph structure

Three sentences (sometimes four). The shape is consistent so a GRC consumer can parse it deterministically:

1. **Positive evidence claim.** Open with what the evidence supports. "The evidence directly supports that [X]." Use language echoing the Determine If Statement so cross-reference is obvious.
2. **Gap or sufficiency call.** Either:
   - **Sufficiency**: "The evidence covers the entire requirement, including [Y]." → leads to `Satisfied`.
   - **Gap**: "However, the determine if statement also requires [Z], which the provided evidence does not [explicitly map | document | specify | demonstrate]." → leads to `NotSatisfied`.
3. **Conclusion.** Single sentence. One of:
   - "The requirement is satisfied."
   - "The requirement is not fully satisfied."
   - "The requirement cannot be assessed without [missing input]."
4. **(Optional) Pointer to synthesized draft.** When Step 6.6 has generated a draft to address the gap: "A draft artifact has been generated at `controls/<CF>-<slug>/evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/synthesized/<artifact>.md` for review."

**Tone.** Federal-assessment register. No hedging, no "appears to", no "seems". Direct evidentiary language. Do not editorialize about the system's overall quality — just whether the evidence covers the specific requirement.

**No new citations.** Step 6.5 does not produce new `[CR-NNN]` IDs. The Findings paragraph references citations that already exist in the Determine If Statement; the assessment pass is downstream of citation generation.

## Result decision rules

| Conclusion of the Findings paragraph | Result column value |
|---|---|
| "The requirement is satisfied." | `Satisfied` |
| "The requirement is not fully satisfied." | `NotSatisfied` |
| "The requirement cannot be assessed without [...]" | blank (the row stays in the CSV but the assessment is incomplete; the Findings paragraph names what's needed) |
| Determine If Statement is empty (no implementation narrative) | blank — emit Findings paragraph saying "No implementation narrative available; the requirement cannot be assessed against this run's evidence." Result stays blank. Note: PR-A scaffolds the placeholder Determine If Statement; PR-B replaces empty placeholders with the un-implementable Findings text. |

The orchestrator MUST NOT mark a row `Satisfied` if the Findings paragraph contains any of these phrases or close variants:
- "does not"
- "no document"
- "no artifact"
- "is not specified"
- "cannot be assessed"
- "lacks"
- "missing"
- "not [explicitly] mapped"

If the Findings paragraph contains any of these, the Result is `NotSatisfied` (or blank for the un-assessable case). This is a hard rule — the orchestrator is not allowed to write "Satisfied" with a Findings paragraph that names a gap.

## Worked examples (from the AMIS spreadsheet)

### AC-02(a) — Define account types — `Satisfied`

**Requirement (`text` from inventory):**
> Define and document the types of accounts allowed and specifically prohibited for use within the system.

**Determine If Statement:**
> AMIS defines and documents two allowed account types within the system: individual user accounts mapped from NIH NED IDs to AMIS identities with the roles `ADMINISTRATOR`, `DATA_ENTERER`, `VIEWER`, `INVESTIGATOR`, and an application or service principal account for the Function App.

**Findings:**
> The evidence directly supports that AMIS defines allowed individual user accounts mapped from NIH NED IDs and an application or service principal account for the Function App, and the implementation statement names the four application roles. The evidence covers the entire requirement, including the type definitions for both account categories. The requirement is satisfied.

**Result:** `Satisfied`

### AC-02(d) — Specify account attributes — `NotSatisfied`

**Requirement:**
> Specify (i) authorized users of the system; (ii) group and role membership; (iii) access authorizations (i.e., privileges) for each account; (iv) for each account, whether the user is Internal or External and whether each account type is Privileged, Non-Privileged, or No Logical Access.

**Determine If Statement:**
> AMIS authorizes only NIH Login SAML-authenticated users whose NED IDs have been manually pre-provisioned by an AMIS administrator in the application's internal user table; users without a matching active record are redirected to `/unauthorized`. The system defines four application role memberships (`ADMINISTRATOR`, `DATA_ENTERER`, `VIEWER`, `INVESTIGATOR`) [CR-042] and enforces access authorizations on each request through the middleware sequence `withErrorHandler → withCsrf → withAuth → checkRole/checkAreaPermission → handler`, where `checkAreaPermission(areaId, action)` applies fine-grained read, write, and delete permissions by user and area, bypassed only for the `ADMINISTRATOR` role [CR-043][CR-044].

**Findings:**
> The evidence and implementation statement support several portions of the requirement by identifying authorized users as NIH-Login-authenticated users who are manually pre-provisioned in the AMIS user table, naming four application roles, and describing role-based and area-based access enforcement. The artifacts also describe specific access authorizations such as read, write, and delete permissions by user and area, with an administrator bypass. However, the determine if statement also requires specification of the user role matrix attributes for each account type — specifically whether users are Internal or External and whether each account type is Privileged, Non-Privileged, or No Logical Access — and the provided evidence does not explicitly map the identified user roles or account types to those required attributes. The requirement is not fully satisfied. A draft artifact has been generated at `controls/AC-access-control/evidence/AC-02/AC-02(d)/synthesized/AC_AC-02_AC-02(d)_role-matrix-draft.md` for review.

**Result:** `NotSatisfied`

### AC-02(g) — Monitor account use — `Satisfied`

**Requirement:**
> Monitor the use of accounts.

**Determine If Statement:**
> The system monitors the use of information system accounts by generating audit records for account lifecycle events, including account creation, role changes, and account disablement, when those actions are performed through the audited Prisma proxy [CR-051]. Audit records carry the actor's NED ID, the affected account, the action, and a timestamp, and are written to the `transaction_log_node` table.

**Findings:**
> The evidence directly supports that the system monitors the use of information system accounts by generating audit records for account lifecycle events, including account creation, role changes, and account disablement, with the actor's NED ID, the affected account, the action, and a timestamp recorded for each event. The evidence covers the entire requirement. The requirement is satisfied.

**Result:** `Satisfied`

### AC-02(c) — Require prerequisites — blank (un-implementable)

**Requirement:**
> Require [Assignment: organization-defined prerequisites and criteria] for group and role membership.

**Determine If Statement:** _(empty — no implementation narrative for this sub-letter)_

**Findings:**
> No implementation narrative available; the requirement cannot be assessed against this run's evidence. The organization-defined prerequisites and criteria for group and role membership are an operational/policy artifact and are not derivable from the repository's code or configuration. Recommend collecting from the system owner or HR.

**Result:** _blank_

### AC-02(01) — Automated System Account Management — `NotSatisfied`

**Requirement:**
> Support the management of system accounts using [Assignment: organization-defined automated mechanisms].

**Determine If Statement:**
> AMIS supports account management by validating user authentication through the SAML callback handler and checking the AMIS user table with `findUserByNedId` each time a NED-authenticated user attempts to access the system [CR-058]. Account creation, role assignment, and disablement are performed manually by an AMIS administrator through the internal user table; no automated provisioning, recertification, or de-provisioning workflow has been detected.

**Findings:**
> The evidence explicitly states that no automated account management workflow is detected in the repository and that account creation appears to be a manual pre-step performed by an AMIS administrator. The determine if statement requires support for management of system accounts using organization-defined automated mechanisms. Manual administrator-driven provisioning does not satisfy the automation requirement. The requirement is not fully satisfied.

**Result:** `NotSatisfied`

## Where the Findings paragraph lands

Two destinations, both populated by Step 6.5:

1. **In the per-family narrative**, under the H3 sub-section for the Determine If ID. Replace the PR-A placeholder text:
   - `Result: _Pending assessment pass — see PR-B_` → `Result: Satisfied | NotSatisfied | _(blank)_`
   - `Findings. _Pending assessment pass — see PR-B._` → the actual Findings paragraph.
2. **In the per-family CSV** (Step 6.7 picks this up). Same content, RFC-4180 quoted.

If the per-family narrative was generated with `--no-assessment` (PR-A behaviour for users who don't want assessment scaffolding), Step 6.5 is a no-op for that family.

## Assessment hygiene checks

Before handing off to Step 6.6 (synthesis):

1. **Result column is consistent with Findings text.** Run the no-`Satisfied`-with-gap-language check (above). Halt with a clear error if violated.
2. **Every Determine If ID in the inventory has either a Findings paragraph or an explicit "un-implementable" Findings paragraph.** No silent omissions.
3. **No new `[CR-NNN]` IDs introduced.** The assessment pass is read-only on citations; new IDs would corrupt the Step 7 merge.
4. **No editorialising about the system overall.** Findings paragraphs stay scoped to the specific Determine If ID's requirement language.

After Step 6.5 completes, proceed to Step 6.6 (synthesis). Step 6.6 consumes the `Result: NotSatisfied` rows and the gap-language in their Findings paragraphs to decide which drafts to produce.
