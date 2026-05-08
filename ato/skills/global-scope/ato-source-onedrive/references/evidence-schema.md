# OneDrive Evidence Schema

## File naming

Evidence lands in `{evidence_root}/{family}/evidence/` (or
`{evidence_root}/controls/{CF}/evidence/{CONTROL-ID}/` for per-control
evidence) with this naming scheme:

```
onedrive_{filename}
```

The `onedrive_` prefix is mandatory — it prevents collisions with
SharePoint, AWS, Azure, SMB, and repo-sourced evidence and lets the
assessor tell at a glance which source the file came from. The
original filename (including extension) is preserved verbatim.

### Per-user prefix on cross-user collisions

When two users in scope have a file with the same name (e.g.,
`SSP.docx` from alice + bob), prefix with the UPN-local-part:

```
onedrive_alice__SSP.docx
onedrive_bob__SSP.docx
```

The double-underscore separator distinguishes the user prefix from
filenames that legitimately contain underscores. The user's UPN
local-part is read from the manifest entry's `source_meta.user_upn`
(in the form `alice@contoso.onmicrosoft.com` → `alice`).

If a single user has two files with the same name in different
folders, drop the second-and-later silently with a `partial_failures`
entry — the operator can resolve the collision in OneDrive directly.

## Citation batch JSON

Written to `{staging_dir}/onedrive-citations.json`. One file per sibling
run. Placeholder IDs `OD-001`, `OD-002`, … (the orchestrator renumbers
on merge).

```json
{
  "source": "onedrive",
  "generated_at": "2026-04-14T10:32:00Z",
  "scope_summary": "tenant=contoso, 2 users",
  "citations": [
    {
      "id_placeholder": "OD-001",
      "prescan_id": "onedrive-pre-001",
      "prescan_confidence": "high",
      "source": "onedrive",
      "cited_by": ["controls/AC-access-control/ac-implementation.md"],
      "location": "access-review-Q1.xlsx",
      "link": "https://contoso-my.sharepoint.com/personal/alice_contoso_onmicrosoft_com/Documents/ATO/access-review-Q1.xlsx",
      "purpose": "Quarterly access review export covering AC-2(3) inactive disable",
      "ssp_section": null,
      "control_families": ["AC"],
      "controls": ["AC-2", "AC-2(3)"],
      "evidence_file": "controls/AC-access-control/evidence/AC-2/onedrive_alice__access-review-Q1.xlsx",
      "source_meta": {
        "user_upn": "alice@contoso.onmicrosoft.com"
      }
    }
  ],
  "partial_failures": [
    {
      "user_upn": "bob@contoso.onmicrosoft.com",
      "reason": "access_forbidden",
      "detail": "m365 returned 403 — bob's OneDrive is not shared with the logged-in identity"
    }
  ]
}
```

## Field reference

The citation row inherits the cross-source schema in
`agents/base/global-scope/ato-artifact-collector/references/sibling-contract.md`,
plus these OneDrive-specific additions:

| Field | Required | Description |
|---|---|---|
| `prescan_id` | yes (normal flow) / null (legacy) | The inventory row's `id` from `ato-doc-summarizer`. |
| `prescan_confidence` | yes (normal flow) / null (legacy) | `"high"` / `"medium"`. (Low-confidence files are not in the citation batch — they're in `partial_failures`.) |
| `source` | yes | Always `"onedrive"`. |
| `purpose` | yes | The agent's neutral 2–3 sentence summary in normal flow; filename-pattern-derived purpose in legacy flow. |
| `source_meta.user_upn` | yes | The OneDrive owner's UPN (the field the assessor needs to know which user-facing OneDrive sourced the evidence). |

## Error file format

Written as `{staging_dir}/onedrive-error.json` when the run cannot
proceed:

```json
{
  "error": "auth_missing",
  "instruction": "Run: m365 login --authType deviceCode"
}
```

Error codes: `auth_missing`, `scope_declined`, `scope_invalid`,
`tool_not_installed`, `summarizer_error`.
