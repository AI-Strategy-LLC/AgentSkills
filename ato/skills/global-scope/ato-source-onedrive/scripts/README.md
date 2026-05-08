# OneDrive Helper Scripts

Helper scripts the `ato-source-onedrive` skill invokes. Each does rote work
outside any LLM context — downloading, text extraction — so the orchestrator's
main conversation never sees the noisy intermediate output.

| Script | Phase in the skill | Purpose |
|---|---|---|
| `onedrive-walk-extract.sh` | Step 4.5a (PRE-SCAN) | Download every candidate from per-user OneDrives to a local cache, extract first-pages text excerpts, emit manifest for `ato-doc-summarizer` |

## `onedrive-walk-extract.sh`

Downloads each candidate file via `m365 spo file get --asFile` (OneDrive for
Business is a personal SharePoint site, so the same `m365 spo *` commands
apply) into a SHA-1-keyed cache, extracts a short text excerpt per file, and
emits a source-agnostic manifest the
[`ato-doc-summarizer`](../../../../agents/base/global-scope/ato-doc-summarizer/)
agent consumes. The cache persists for the duration of the skill's run —
Step 5 (COPY) moves files from the cache to `evidence/` rather than re-
downloading.

The script is near-identical to its SharePoint sibling; the differences are:

- `--source` defaults to `onedrive` instead of `sharepoint`.
- Cache / excerpt / manifest filenames default to `onedrive-*`.
- Each candidate must carry a `user_upn` field (the SharePoint walker
  doesn't use this — it has no concept of per-user owners).
- Per-file manifest entries embed `source_meta.user_upn` so the calling
  skill's COPY step can prefix evidence files with the user's UPN local-
  part on cross-user filename collisions.

### Required tools

- `m365` — pnp/cli-microsoft365.
- `jq` — JSON construction.
- `sha1sum` (Linux) **or** `shasum` (macOS) — stable per-file cache hashing.

### Optional extractors (graceful-degrade)

Same set as the SMB and SharePoint walkers (`pdftotext`, `pandoc`, `unzip`).
See `../../ato-source-sharepoint/scripts/README.md` for install hints — they
apply identically here.

### Input — candidates JSON

```json
[
  {
    "site_url": "https://contoso-my.sharepoint.com/personal/alice_contoso_onmicrosoft_com",
    "server_relative_url": "/personal/alice_contoso_onmicrosoft_com/Documents/ATO/SSP-v2.docx",
    "filename": "SSP-v2.docx",
    "size_bytes": 2415104,
    "mtime": "2025-11-14T09:11:00Z",
    "user_upn": "alice@contoso.onmicrosoft.com"
  }
]
```

The skill's Step 4 (DISCOVER) builds this list by deriving each user's
OneDrive site URL from the configured tenant + UPN, then running
`m365 spo file list` per (user, folder) pair.

### Usage

```bash
onedrive-walk-extract.sh \
  --candidates-json docs/ato-package/.staging/onedrive-discovery.json \
  --staging-dir     docs/ato-package/.staging
```

### Outputs

- `<staging>/<cache-subdir>/<sha1>.<ext>` — per-file downloaded original.
  SHA-1 is taken over `<site_url>::<server_relative_url>` so re-runs map to
  the same cache file (cache hits skip the m365 download).
- `<staging>/<excerpt-subdir>/<sha1>.txt` — per-file excerpt.
- `<staging>/<manifest-name>` — JSON manifest matching the contract at
  [`agents/base/global-scope/ato-doc-summarizer/references/manifest-contract.md`](../../../../agents/base/global-scope/ato-doc-summarizer/references/manifest-contract.md).
  Each `files[]` entry carries `cache_file` at top level and per-user
  metadata under `source_meta.user_upn`.

### Exit codes

| Code | Meaning | Manifest written? |
|---|---|---|
| `0` | OK — every candidate downloaded and extracted | yes |
| `1` | Fatal failure (auth missing, m365 not on PATH, IO error) | maybe |
| `2` | No candidates in input | yes (empty `files[]`) |
| `3` | Partial — some files skipped (`extractor_missing`, `download_failed`, `too_large`) | yes |
| `64` | Usage error | no |

### What this script does NOT do

- **No LLM calls.**
- **No write to OneDrive.** Read-only on the tenant.
- **No copy to `evidence/`.** The skill's Step 5 (COPY) does that for
  high/medium-confidence files.
- **No permission elevation.** If a user's OneDrive isn't shared with the
  logged-in identity, the per-file `m365 spo file get` returns failure;
  the script records `download_failed` and continues. The skill's higher-
  level loop is responsible for converting that into a per-user
  `access_forbidden` entry in the citation batch's `partial_failures`.
