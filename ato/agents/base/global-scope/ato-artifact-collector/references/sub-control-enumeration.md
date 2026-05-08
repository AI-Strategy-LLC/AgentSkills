# Sub-control enumeration — Step 4.5 reference

The orchestrator's per-family narrative and per-family CSV iterate at the **Determine If ID** level (sub-control granularity), not at the base-control level. Step 4.5 builds the canonical inventory that drives every downstream step (sub-control evidence routing, narrative iteration, assessment, CSV emission).

This reference defines the inventory's source, schema, and sub-control naming rules.

## What "Determine If ID" means

A NIST 800-53 base control like **AC-2 (Account Management)** decomposes into multiple individually-assessable items. Some come from the lettered sub-parts of the control body (`AC-2(a)` through `AC-2(l)`); others are control enhancements (`AC-2(1)`, `AC-2(2)`, …). A small number of enhancements have their own lettered sub-parts (`AC-2(12)(a)`, `AC-2(12)(b)`).

Every assessable item — whether sub-letter, enhancement, or enhancement-with-sub-letter — is a **Determine If ID**. The federal assessment pattern (and FedRAMP / NIST 800-53A test plans) writes one row per Determine If ID with its own implementation statement, method, result, and findings. The ATO orchestrator mirrors that shape.

Examples:

| Control body shape | Determine If ID set |
|---|---|
| `AC-3` (single requirement) | `AC-3` (1 item; the control itself) |
| `AC-2` (12 sub-letters) | `AC-2(a)`, `AC-2(b)`, …, `AC-2(l)` |
| `AC-2(1)` (enhancement, single requirement) | `AC-2(01)` |
| `AC-2(12)` (enhancement with sub-parts) | `AC-2(12)(a)`, `AC-2(12)(b)` |

**Naming rules** (the orchestrator must emit IDs in exactly this form):

- Family code uppercase (`AC`, `IA`, `SC`).
- Base-control number is two digits, zero-padded (`AC-02`, not `AC-2`). The legacy `AC-2(4)` form is also accepted on input but the orchestrator emits `AC-02(04)`.
- Enhancement number is two digits, zero-padded, in parentheses (`AC-02(01)`, not `AC-02(1)`).
- Sub-letters are single lowercase letters in parentheses (`AC-02(a)`).
- Enhancement-with-sub-letter chains the parens (`AC-02(12)(b)`).

## Inventory source — LLM enumeration with optional override

**Default (no catalog file present):** the orchestrator generates the Determine If ID list per in-scope control directly from its NIST 800-53 Rev 5 knowledge. For each control on the system's baseline, list the sub-letters present in the control body, then list the enhancements drawn into the baseline (LOW / MODERATE / HIGH). For each enhancement that itself has sub-parts, expand those.

**Override (catalog file present):** if either of these files exists, use it as the authoritative enumeration instead — do not fall back to LLM enumeration:

1. `agents/base/global-scope/ato-artifact-collector/references/control-catalog-rev5.csv` (bundled with the agent; ships empty in v1)
2. `docs/control-catalog.csv` at the target repo root (per-system override; takes precedence over the bundled catalog)

Catalog CSV schema (matches the AMIS spreadsheet header row):

```csv
Family ID,Family,Control ID,Control,Determine If ID,Determine If Statement Template
AC,Access Control,AC-02,Account Management,AC-02(a),"Define and document the types of accounts allowed and specifically prohibited..."
AC,Access Control,AC-02,Account Management,AC-02(b),"Assign account managers..."
...
```

The `Determine If Statement Template` column is optional — if present, it carries the requirement language verbatim. The orchestrator uses it during the assessment pass (PR-B) to compare against the implementation narrative.

## Output — `.staging/sub-control-inventory.json`

After enumeration, write a single JSON file at `docs/ato-package/.staging/sub-control-inventory.json` with this schema:

```json
{
  "schema_version": 1,
  "generated_at": "2026-04-30T14:35:00Z",
  "source": "llm_enumeration",
  "baseline": "MODERATE",
  "controls": {
    "AC-02": {
      "family_id": "AC",
      "family": "Access Control",
      "title": "Account Management",
      "determine_if_ids": [
        {"id": "AC-02(a)", "text": "Define and document the types of accounts allowed and specifically prohibited..."},
        {"id": "AC-02(b)", "text": "Assign account managers..."},
        {"id": "AC-02(c)", "text": "Require [Assignment: organization-defined prerequisites and criteria]..."},
        {"id": "AC-02(d)", "text": "Specify..."},
        {"id": "AC-02(e)", "text": "..."},
        {"id": "AC-02(f)", "text": "..."},
        {"id": "AC-02(g)", "text": "..."},
        {"id": "AC-02(h)", "text": "..."},
        {"id": "AC-02(i)", "text": "..."},
        {"id": "AC-02(j)", "text": "..."},
        {"id": "AC-02(k)", "text": "..."},
        {"id": "AC-02(l)", "text": "..."}
      ]
    },
    "AC-02(01)": {
      "family_id": "AC",
      "family": "Access Control",
      "title": "Automated System Account Management",
      "parent_control": "AC-02",
      "determine_if_ids": [
        {"id": "AC-02(01)", "text": "Support the management of system accounts using..."}
      ]
    },
    "AC-02(12)": {
      "family_id": "AC",
      "family": "Access Control",
      "title": "Account Monitoring for Atypical Usage",
      "parent_control": "AC-02",
      "determine_if_ids": [
        {"id": "AC-02(12)(a)", "text": "Monitor system accounts for [Assignment: ...]"},
        {"id": "AC-02(12)(b)", "text": "Report atypical usage of system accounts to..."}
      ]
    },
    "AC-03": {
      "family_id": "AC",
      "family": "Access Control",
      "title": "Access Enforcement",
      "determine_if_ids": [
        {"id": "AC-03", "text": "Enforce approved authorizations for logical access..."}
      ]
    }
  }
}
```

**Schema notes:**

- The top-level `controls` map is keyed by Control ID (which includes any enhancement number). One entry per Control ID, not per Determine If ID — sub-letters live inside the parent control's `determine_if_ids` array.
- Enhancements with their own sub-letters get one entry keyed by the enhancement (e.g., `AC-02(12)`) with the sub-letters in its `determine_if_ids` array. They are NOT collapsed into the base control's entry.
- The `parent_control` field appears only on enhancement entries. Base controls and enhancements without a parent have no `parent_control` field.
- `source` is one of: `llm_enumeration`, `bundled_catalog`, `repo_catalog_override`. Used by Step 6.5 (assessment) to decide whether to trust the `text` field as ground truth or treat it as orchestrator-generated.
- `baseline` is `LOW`, `MODERATE`, `HIGH`, or `TAILORED`. Drives which enhancements appear in the inventory. The orchestrator infers it from the system's documented impact level (FIPS-199 categorization in the SSP) or asks the user if no impact level is recorded.
- `generated_at` is ISO 8601 UTC. Consumed by INDEX.md.

## How the inventory is used downstream

| Step | Consumer | Use |
|---|---|---|
| 4.6 | Sub-control evidence routing | Walks every Determine If ID; emits `evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_relevant-evidence.md` manifests pointing at parent-level evidence files. Filename embeds family + control + Determine If ID so each manifest stays uniquely identifiable when the package is flattened. Simple-control case (Determine If ID equals Control ID) drops the redundant DI segment. |
| 6 | Per-family narrative | Iterates Determine If IDs to produce H3 sub-sections with Determine If Statement blocks |
| 6.5 | Assessment pass (PR-B) | Compares narrative against `text` field; produces Findings + Result |
| 6.6 | Synthesized drafts (PR-B) | Walks NotSatisfied Determine If IDs; checks for "implementation present, artifact missing" pattern |
| 6.7 | CSV emission | One row per Determine If ID, per family CSV |
| 8 | INDEX.md / CHECKLIST.md | Sub-control rollup; per-family Determine-If-ID coverage statistics |

## Folder-naming conventions for sub-control evidence

Once enumerated, evidence routes to sub-control folders using these rules:

| Determine If ID | Folder path under `controls/<CF>-<slug>/evidence/` |
|---|---|
| `AC-02(a)` | `AC-02/AC-02(a)/` |
| `AC-02(d)` | `AC-02/AC-02(d)/` |
| `AC-02(01)` | `AC-02/AC-02(01)/` (peer of sub-letters under the same parent) |
| `AC-02(12)(b)` | `AC-02/AC-02(12)/AC-02(12)(b)/` (nested) |
| `AC-03` (only Determine If ID for the control is the control itself) | `AC-03/` (skip redundant `AC-03/AC-03/` nesting) |

**Skip-redundant-nesting rule:** if a control's `determine_if_ids` array has exactly one entry whose `id` equals the control's own key, write evidence directly under `evidence/<CONTROL-ID>/`. Otherwise always nest. This keeps simple controls flat while making multi-part controls navigable.

## Correctness checks before handing the inventory to Step 4.6

The orchestrator should sanity-check the inventory before downstream steps consume it:

1. **Family coverage.** Every in-scope control must belong to one of the 20 NIST 800-53 Rev 5 families. Reject IDs that don't match `[A-Z]{2}-\d+(\(\d+\))?(\([a-z]\))?(\(\d+\))?(\([a-z]\))?` (relaxed to permit zero-padded forms). Log and drop bad rows; continue.
2. **No duplicate Determine If IDs.** Within and across controls, every Determine If ID must be unique. Duplicates indicate an enumeration bug.
3. **Parent linkage.** Every enhancement entry must have a `parent_control` field that is itself a key in the inventory's `controls` map. Orphaned enhancements (no parent) get logged but kept; they are valid for tailored baselines.
4. **Baseline-completeness.** For MODERATE baseline runs, the inventory should contain at least these controls per family (sanity floor): AC-1, AC-2, AC-3, AC-6, AC-17, AC-22; AT-1, AT-2, AT-3; AU-1 through AU-12; etc. If a family has fewer than its baseline-floor controls, log a warning so the assessor sees the gap.

After validation, write the file. Then proceed to Step 4.6.
