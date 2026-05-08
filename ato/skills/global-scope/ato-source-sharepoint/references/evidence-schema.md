# SharePoint Evidence Schema

## File naming

Downloads land in `{evidence_root}/{NN-CF-section-slug}/evidence/` with this
naming scheme:

```
sharepoint_{original-filename}
```

The `sharepoint_` prefix is mandatory — it prevents collisions with
repo-sourced evidence and lets the assessor tell at a glance which source
the file came from. The original filename (including extension) is
preserved verbatim. Spaces and special characters in the original name are
kept as-is; the filesystem handles them.

If the same original filename would collide across two families, the file is
simply copied twice — once into each family's `evidence/` folder. No
disambiguation is needed because different families never share a directory.

If two different SharePoint files happen to have the same filename (e.g.,
`SSP.docx` in two different sites), prefix with the site slug:

```
sharepoint_ato-site__SSP.docx
sharepoint_policies-site__SSP.docx
```

## Citation batch JSON

Written to `{staging_dir}/sharepoint-citations.json`. One file per sibling run.

```json
{
  "source": "sharepoint",
  "generated_at": "2026-04-14T10:32:00Z",
  "scope_summary": "tenant=contoso, 1 site, 2 folders",
  "citations": [
    {
      "id_placeholder": "SP-001",
      "cited_by": "ssp-sections/06-policies-procedures/security-policies-evidence.md",
      "location": "SSP-v2.docx",
      "link": "https://contoso.sharepoint.com/sites/ato/Shared%20Documents/Current%20ATO/SSP-v2.docx",
      "purpose": "Prior approved SSP — baseline for this revision",
      "control_family": "ssp-sections/06-policies-procedures",
      "evidence_file": "ssp-sections/06-policies-procedures/evidence/sharepoint_SSP-v2.docx"
    },
    {
      "id_placeholder": "SP-002",
      "cited_by": "ssp-sections/03-risk-assessment-report/risk-assessment-gap-analysis.md",
      "location": "POA&M-Q1-2026.xlsx",
      "link": "https://contoso.sharepoint.com/sites/ato/Shared%20Documents/POA%26M/POA%26M-Q1-2026.xlsx",
      "purpose": "Current POA&M tracking open findings",
      "control_family": "ssp-sections/03-risk-assessment-report",
      "evidence_file": "ssp-sections/03-risk-assessment-report/evidence/sharepoint_POA&M-Q1-2026.xlsx"
    }
  ],
  "partial_failures": [
    {
      "location": "/Shared Documents/Archive/old-SSP.docx",
      "reason": "too_large",
      "detail": "File size 72MB exceeds 50MB limit"
    }
  ]
}
```

## Field reference

| Field | Required | Description |
|---|---|---|
| `source` | yes | Always `"sharepoint"` |
| `generated_at` | yes | ISO 8601 UTC timestamp |
| `scope_summary` | yes | One-line human summary of the scope |
| `citations` | yes | Array of citation rows; may be empty |
| `citations[].id_placeholder` | yes | `SP-NNN`, monotonic within batch |
| `citations[].cited_by` | yes | Narrative doc path, relative to `docs/ato-package/` |
| `citations[].location` | yes | Original SharePoint filename |
| `citations[].link` | yes | Full SharePoint URL to the file |
| `citations[].purpose` | yes | One-line reason this file matters |
| `citations[].control_family` | yes | One of the 20 slugs |
| `citations[].evidence_file` | yes | Local copy path, relative to `docs/ato-package/` |
| `partial_failures` | no | Array of skipped/failed items |

## Error file format

Written as `{staging_dir}/sharepoint-error.json` when the run cannot proceed:

```json
{
  "error": "auth_missing",
  "instruction": "Run: m365 login --authType deviceCode"
}
```

Error codes: `auth_missing`, `scope_declined`, `scope_invalid`,
`tool_not_installed`.
