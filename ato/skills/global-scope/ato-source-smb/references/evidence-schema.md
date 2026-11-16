# SMB Evidence Schema

## File naming

Copied files land in `{evidence_root}/{NN-CF-section-slug}/evidence/` with:

```
smb_{original-filename}
```

The `smb_` prefix is mandatory. If two different shares have a same-named
file, prefix with the share slug:

```
smb_ato-policies__SSP.docx
smb_dr-runbooks__SSP.docx
```

## Citation batch JSON

`{staging_dir}/smb-citations.json`:

```json
{
  "source": "smb",
  "generated_at": "2026-04-14T10:50:00Z",
  "scope_summary": "2 shares, depth=3, macOS (mount_smbfs)",
  "os": "Darwin",
  "citations": [
    {
      "id_placeholder": "SMB-001",
      "cited_by": "ssp-sections/08-contingency-plan/contingency-plan-evidence.md",
      "location": "//fileserver.corp/ato/Current/DR-runbook.pdf",
      "link": "smb://fileserver.corp/ato/Current/DR-runbook.pdf",
      "purpose": "Disaster recovery runbook — current approved version",
      "control_family": "ssp-sections/08-contingency-plan",
      "evidence_file": "ssp-sections/08-contingency-plan/evidence/smb_DR-runbook.pdf"
    }
  ],
  "partial_failures": [
    {
      "location": "//fileserver.corp/ato/Archive/old-IR-plan.pdf",
      "reason": "excluded_directory",
      "detail": "Inside 'Archive' — hard-skipped"
    },
    {
      "location": "//fileserver.corp/ato/Backups/2012-SSP-snapshot.zip",
      "reason": "wrong_type",
      "detail": "Extension .zip not in file_types allow list"
    }
  ]
}
```

## Link format

The `link` field is always an `smb://` URI. It is not browser-clickable in
most viewers, but uniquely identifies the source for an assessor and lets a
Windows user paste it into Explorer.

```
smb://{host}/{share}/{path-with-forward-slashes}
```

Spaces in paths are percent-encoded: ` ` → `%20`.

## Error file

`{staging_dir}/smb-error.json`. Codes: `auth_missing`, `scope_declined`,
`scope_invalid`, `mount_failed`, `tool_not_installed`.

## Unmount guarantee

Even if the citation batch is written with `partial_failures`, the unmount
step must run. The error file is only written when the skill cannot proceed
to discovery at all — partial failures during discovery go into the citation
batch's `partial_failures` array.
