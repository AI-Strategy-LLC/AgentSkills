# GRC assessment CSV — schema reference

The orchestrator emits one CSV per control family (`controls/<CF>-<slug>/<cf>-assessment.csv`) and one master CSV at `controls/_master-assessment.csv`. Both share the same 9-column schema, derived from the federal assessment-spreadsheet pattern (e.g., `AMIS Testing-assessment.xlsx`). The CSVs are designed for direct ingestion into GRC tools (RSA Archer, ServiceNow GRC, custom POA&M trackers) without further transformation.

## Column schema (9 columns)

| # | Column | Source | Required | Notes |
|---|---|---|---|---|
| 1 | `Family ID` | `.staging/sub-control-inventory.json` `family_id` | yes | 2-letter NIST family code: `AC`, `AT`, `AU`, `CA`, `CM`, `CP`, `IA`, `IR`, `MA`, `MP`, `PE`, `PL`, `PM`, `PS`, `PT`, `RA`, `SA`, `SC`, `SI`, `SR` |
| 2 | `Family` | `.staging/sub-control-inventory.json` `family` | yes | Full family name, e.g. `Access Control` |
| 3 | `Control ID` | `.staging/sub-control-inventory.json` controls-map key | yes | Base control or enhancement, zero-padded: `AC-02`, `AC-02(01)`, `AC-02(12)` |
| 4 | `Control` | `.staging/sub-control-inventory.json` `title` | yes | Control title from NIST 800-53 |
| 5 | `Determine If ID` | `.staging/sub-control-inventory.json` `determine_if_ids[].id` | yes | The row's primary key. `AC-02(a)`, `AC-02(01)`, `AC-02(12)(b)` |
| 6 | `Determine If Statement` | Per-family narrative — implementation paragraph for that Determine If ID | conditional | Filled when the orchestrator could synthesize a narrative from collected evidence; blank otherwise |
| 7 | `Method` | Constant | yes | Always `Review` for the orchestrator-produced rows. (Manual rows added by an assessor may use `Test`, `Examine`, `Interview` per NIST 800-53A.) |
| 8 | `Result` | Assessment pass (PR-B) | conditional | One of: `Satisfied`, `NotSatisfied`, blank. Blank in PR-A (assessment pass not yet running). Blank when `Method` was not run. |
| 9 | `Findings` | Assessment pass (PR-B) | conditional | Assessor-style narrative explaining why the row is Satisfied / NotSatisfied. Blank in PR-A and when `Method` was not run. |

**Column order is fixed** — GRC importers key off positional order, not header text. Do not reorder.

## Header row

The first row of every CSV (per-family and master) is exactly:

```
Family ID,Family,Control ID,Control,Determine If ID,Determine If Statement,Method,Result,Findings
```

No leading byte-order mark. UTF-8. Newline `\n` (LF). The orchestrator MUST NOT emit `\r\n` line endings — many GRC tools accept both, but a few legacy ones split on `\n` and treat the trailing `\r` as part of the field value.

## RFC 4180 quoting rules

Every field value goes through the same encoding pipeline:

1. If the field is empty → emit `,,` (no quotes).
2. If the field contains `,`, `"`, `\n`, or leading/trailing whitespace → wrap in double quotes.
3. Inside a quoted field, double-quote any embedded `"` by replacing `"` with `""`.
4. Embedded newlines are preserved as literal `\n` *inside the quoted field* (not escaped, not stripped). This means `Determine If Statement` paragraphs and `Findings` narratives can wrap across multiple physical lines in the CSV file.

Pseudo-code:

```python
def encode_field(value: str) -> str:
    if value is None or value == "":
        return ""
    needs_quoting = any(c in value for c in [",", '"', "\n"]) or value != value.strip()
    if not needs_quoting:
        return value
    return '"' + value.replace('"', '""') + '"'
```

Pseudo-code emitter:

```python
def emit_row(values: list[str], out):
    out.write(",".join(encode_field(v) for v in values))
    out.write("\n")
```

## Sample rows

```csv
Family ID,Family,Control ID,Control,Determine If ID,Determine If Statement,Method,Result,Findings
AC,Access Control,AC-02,Account Management,AC-02(a),"AMIS defines and documents two allowed account types within the system: individual user accounts mapped from NIH NED IDs to AMIS identities with the roles ""ADMINISTRATOR"", ""DATA_ENTERER"", ""VIEWER"", and an application or service principal account for the Function App.",Review,Satisfied,"The evidence directly supports that AMIS defines allowed individual user accounts mapped from NIH NED IDs and an application or service principal account for the Function App, and the implementation statement names the four application roles."
AC,Access Control,AC-02,Account Management,AC-02(b),"Account provisioning is performed as a manual pre-step by an AMIS administrator before a NED-authenticated user can access the system.",Review,Satisfied,"The evidence states that an AMIS administrator manually performs account provisioning."
AC,Access Control,AC-02,Account Management,AC-02(c),,,,,
AC,Access Control,AC-02,Account Management,AC-02(d),"AMIS authorizes only NIH Login SAML-authenticated users whose NED IDs have been manually pre-provisioned by an AMIS administrator.",Review,NotSatisfied,"The evidence supports several portions of the requirement but does not explicitly map the identified user roles or account types to Privileged / Non-Privileged / No-Logical-Access categories."
AC,Access Control,AC-03,Access Enforcement,AC-03,"The system enforces approved logical access authorizations by requiring authentication and authorization for all application requests except /api/health and the SAML endpoints.",Review,Satisfied,
```

**Note the AC-02(c) row:** an enumerated Determine If ID with no implementation narrative is preserved as a row with all subsequent columns blank. This mirrors the AMIS spreadsheet's behavior — it lets the assessor see the full enumeration and decide which un-scoped items need attention.

## Per-family CSV vs. master CSV

| File | Path | Content | Sort order |
|---|---|---|---|
| Per-family | `controls/<CF>-<slug>/<cf>-assessment.csv` | Only that family's rows | By Control ID, then by Determine If ID (within control) |
| Master | `controls/_master-assessment.csv` | All 20 families concatenated | By Family ID (alphabetical), then by Control ID, then by Determine If ID |

The master CSV is **not** a literal byte-concatenation of the per-family files — it has a single header row at the top, no inter-family blank lines, and no repeated headers. It is the file most GRC tools want to ingest.

The per-family files are useful when an assessor is reviewing one family at a time, or when feeding family-scoped tools.

## Sort order for `Determine If ID` within a control

Determine If IDs sort by:

1. The Determine If ID's lexical order **after** zero-padding numeric segments to 2 digits and after lowercasing letter segments. So `AC-02(a)` < `AC-02(b)` < `AC-02(c)` < ... < `AC-02(l)`.
2. Sub-letters of the base control come before enhancements: `AC-02(a)` ... `AC-02(l)` precede `AC-02(01)`.
3. Within enhancements, lower enhancement number first: `AC-02(01)` < `AC-02(02)` < `AC-02(11)` < `AC-02(12)` < `AC-02(13)`.
4. Enhancement-with-sub-letter sorts under its enhancement: `AC-02(12)(a)` < `AC-02(12)(b)` immediately after `AC-02(12)`.

The orchestrator should compute this sort with a numeric-aware key that splits on parens and zero-pads digit groups to width 2 — naive lexical sort would put `AC-02(11)` before `AC-02(2)` if the inventory ever uses unpadded numbers.

## CSV ↔ narrative cross-reference

The CSV is generated **from** the per-family narrative (`<cf>-implementation.md`), not authored in parallel. Step 6.7 walks the narrative's H3 sub-sections, extracts:

- The H3 heading's Determine If ID
- The `> **Method**:` blockquote line
- The `> **Result**:` blockquote line (PR-B only)
- The `**Determine If Statement.**` paragraph (immediately after the H3's blockquote header)
- The `**Findings.**` paragraph (PR-B only)

…and writes them into the CSV. If a Determine If ID is in the inventory but absent from the narrative, the row is emitted with blank columns 6–9. If a Determine If ID is in the narrative but absent from the inventory, log a warning and include the row anyway (don't drop on the floor).

## Validation before write

Before writing each CSV, the orchestrator should:

1. Re-parse the file it's about to write with a stdlib CSV reader. If it fails to parse cleanly, an encoding bug has been introduced — halt with a clear error, do not emit a corrupt CSV.
2. Verify row count matches the count of Determine If IDs in the inventory for the relevant family (per-family) or globally (master).
3. Verify the header row is exactly the 9-column string above.
4. Verify every row has exactly 9 fields after RFC 4180 parsing (commas inside quoted fields don't count as field separators).

Round-trip tests:

```bash
python3 -c "
import csv, sys
with open('controls/AC-access-control/ac-assessment.csv') as f:
    r = list(csv.DictReader(f))
print(f'rows: {len(r)}')
print(f'cols: {list(r[0].keys()) if r else None}')
print(f'first row Determine If ID: {r[0][\"Determine If ID\"] if r else None}')
"
```

If this prints a 9-column header set and a sensible row count, the CSV is structurally valid.
