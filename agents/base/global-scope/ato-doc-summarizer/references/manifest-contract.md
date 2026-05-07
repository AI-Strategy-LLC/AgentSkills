# Manifest Contract — `ato-doc-summarizer` Inputs

This file is the contract any document-source extractor must satisfy when
producing a manifest for `ato-doc-summarizer`. The first such extractor is
`skills/global-scope/ato-source-smb/scripts/smb-walk-extract.sh`. Future
extractors (SharePoint, OneDrive, S3, Box, etc.) follow the same shape so
the agent stays source-agnostic.

## Top-level shape

```json
{
  "schema_version": "1.0",
  "source": "smb",
  "scan_id": "smb-2026-05-07T14:23:00Z",
  "extracted_root": "smb-excerpts",
  "totals": {
    "candidates": 247,
    "excerpts_extracted": 198,
    "skipped_too_large": 12,
    "skipped_extractor_missing": 37,
    "skipped_unsupported_type": 0
  },
  "files": [ /* see below */ ],
  "skipped": [ /* see below */ ]
}
```

| Field | Required | Description |
|---|---|---|
| `schema_version` | yes | Semantic version. Major-version mismatch (`2.x` and up) causes the agent to refuse the manifest. |
| `source` | yes | Producer identifier. Free-form string but must match the source's citation-batch token (`smb`, `sharepoint`, etc.). The agent passes this through unchanged into the inventory. |
| `scan_id` | yes | Unique identifier for this run. Convention: `<source>-<UTC-ISO>`. The agent passes this through unchanged. |
| `extracted_root` | yes | Subdirectory name under the manifest's directory where excerpts live. Used by the agent to resolve `excerpt_file` paths. |
| `totals` | yes | Aggregate counts. The agent does not validate these but reproduces the relevant ones in its inventory. |
| `files` | yes | Array of per-file entries that have an excerpt available for summarization. Empty array is valid (nothing to summarize). |
| `skipped` | yes | Array of files the extractor walked but could not produce an excerpt for. Empty array is valid. The agent passes this through into its inventory unchanged. |

## `files[]` entries

Every entry in `files[]` has these fields:

| Field | Required | Description |
|---|---|---|
| `id` | yes | Source-scoped placeholder ID. Convention: `<source>-pre-NNNN`. The agent uses this as the inventory row's `id`. |
| `path` | yes | Absolute path to the original document on the source side (mount path for SMB, full server-relative path for SharePoint, etc.). The agent passes this through; the calling skill uses it to copy the file later. |
| `uri` | yes | Source-native URI for the document (`smb://...`, `https://tenant.sharepoint.com/...`). The agent passes this through; ends up in the citation batch. |
| `size_bytes` | yes | File size in bytes. Pass-through. |
| `mtime` | yes | Last-modified timestamp, ISO-8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`). Pass-through. |
| `type` | yes | Lowercased file extension without the leading dot (`pdf`, `docx`, `md`, `txt`, etc.). The agent uses this as a hint when interpreting the excerpt. |
| `excerpt_file` | yes | Path to the excerpt text, **relative to the manifest file's directory**. The agent resolves this to an absolute path before reading. |
| `filename_hint` | optional | Slug like `ssp-sections/08-contingency-plan` if the extractor wants to suggest a family from the filename. The agent treats this as a tie-breaker, not as ground truth. Empty string `""` means "no hint." |

## `skipped[]` entries

Every entry in `skipped[]` has these fields:

| Field | Required | Description |
|---|---|---|
| `path` | yes | Absolute path to the original document. |
| `reason` | yes | One of: `too_large`, `extractor_missing`, `extractor_unsupported`, `walk_error`. Extractors are free to add new reasons; the agent passes them through unchanged. |
| `size_bytes` | for `too_large` | The file's size, so the operator knows by how much it exceeded the limit. |
| `type` | for `extractor_missing` and `extractor_unsupported` | The file extension, so the operator knows which extractor would help. |
| `missing_tool` | for `extractor_missing` | The tool that would have processed this file (`pdftotext`, `pandoc`, `unzip`). The agent surfaces this in the inventory's "Skipped" table so the operator knows what to install. |

## What the agent reads vs. passes through

| Field | Read | Pass through to inventory |
|---|---|---|
| `schema_version` | yes (validation) | no (inventory has its own) |
| `source` | yes | yes |
| `scan_id` | yes | yes |
| `extracted_root` | yes (path resolution) | no (not relevant after summarization) |
| `totals` | no | partial (just `skipped_in_manifest`) |
| `files[].id` | yes | yes |
| `files[].path` | yes | yes |
| `files[].uri` | yes | yes |
| `files[].size_bytes` | no | yes |
| `files[].mtime` | no | no |
| `files[].type` | yes | yes |
| `files[].excerpt_file` | yes (open it) | no (the excerpt is scratch; only the summary persists) |
| `files[].filename_hint` | yes (tie-breaker) | no |
| `skipped[]` | no | yes (verbatim) |

## Schema versioning

- `1.x` — current. Minor versions add optional fields (e.g. a future `language: "en"` hint). The agent ignores unknown fields.
- `2.x` — reserved for breaking changes (e.g. moving excerpts out-of-band). The agent refuses `2.x` manifests with `error: "schema_unsupported"` so a coordinated upgrade is required.

## Authoring a new extractor

When adding a new source-specific extractor (e.g. for SharePoint or
OneDrive), the requirements are:

1. Produce a manifest matching this contract.
2. Write excerpts under `<staging-dir>/<extracted_root>/`.
3. Resolve `excerpt_file` paths relative to the manifest's directory.
4. Use the same source-prefix convention (`<source>-pre-NNNN`) for `id`.
5. Match the file-type allow list (`pdf`, `docx`, `pptx`, `xlsx`, `md`,
   `txt`) — extending this requires also extending the agent's
   summarization logic and the `summary-rubric.md`.
6. Match the `extractor_missing` / `extractor_unsupported` /
   `too_large` reason vocabulary in `skipped[]`.
