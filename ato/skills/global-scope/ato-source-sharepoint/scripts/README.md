# SharePoint Helper Scripts

Helper scripts the `ato-source-sharepoint` skill invokes. Each does rote work
outside any LLM context — downloading, text extraction — so the orchestrator's
main conversation never sees the noisy intermediate output.

| Script | Phase in the skill | Purpose |
|---|---|---|
| `sharepoint-walk-extract.sh` | Step 4.5a (PRE-SCAN) | Download every candidate to a local cache, extract first-pages text excerpts, emit manifest for `ato-doc-summarizer` |

## `sharepoint-walk-extract.sh`

Downloads each candidate file via `m365 spo file get --asFile` into a SHA-1-
keyed cache, extracts a short text excerpt per file, and emits a source-
agnostic manifest the
[`ato-doc-summarizer`](../../../../agents/base/global-scope/ato-doc-summarizer/)
agent consumes. The cache persists for the duration of the skill's run — Step
5 (COPY) moves files from the cache to `evidence/` rather than re-downloading.

### Required tools

- `m365` — pnp/cli-microsoft365. Already required by the SKILL itself for
  discovery + download.
- `jq` — JSON construction
- `sha1sum` (Linux) **or** `shasum` (macOS) — stable per-file cache hashing

### Optional extractors (graceful-degrade)

If any extractor is missing, files of the corresponding type are recorded in
the manifest's `skipped` array with `reason: extractor_missing`. The script
still succeeds — exit code `3` (partial).

| Tool | Covers | Install (macOS) | Install (Debian/Ubuntu) | Install (Windows) |
|---|---|---|---|---|
| `pdftotext` (poppler) | `.pdf` | `brew install poppler` | `apt-get install poppler-utils` | `choco install poppler` |
| `pandoc` | `.docx` (preferred) | `brew install pandoc` | `apt-get install pandoc` | `choco install pandoc` |
| `unzip` | `.docx` (fallback), `.xlsx`, `.pptx` | preinstalled | preinstalled | `choco install unzip` |

Legacy binary Office formats (`.doc`, `.xls`, `.ppt`) have no portable shell
extractor; they're skipped with `reason: extractor_unsupported`.

### Input — candidates JSON

Each entry must have these fields (the SKILL's Step 4 builds this list by
flattening `m365 spo file list` outputs across configured (site, library,
folder) triples):

```json
[
  {
    "site_url": "https://contoso.sharepoint.com/sites/ato",
    "server_relative_url": "/sites/ato/Shared Documents/Current ATO/SSP-v2.docx",
    "filename": "SSP-v2.docx",
    "size_bytes": 2415104,
    "mtime": "2025-11-14T09:11:00Z"
  }
]
```

### Usage

```bash
sharepoint-walk-extract.sh \
  --candidates-json docs/ato-package/.staging/sharepoint-discovery.json \
  --staging-dir     docs/ato-package/.staging
```

Optional flags:

| Flag | Default | Purpose |
|---|---|---|
| `--cache-subdir`   | `sharepoint-cache`    | Subdir under `--staging-dir` for downloaded originals |
| `--excerpt-subdir` | `sharepoint-excerpts` | Subdir for extracted excerpts |
| `--manifest-name`  | `sharepoint-manifest.json` | Output manifest filename |
| `--source`         | `sharepoint`          | Source identifier in the manifest + file IDs |
| `--max-bytes`      | `52428800` (50 MB)    | Server-reported size above this is skipped as `too_large` (no download) |
| `--scan-id`        | auto                  | Override for stable scan identifiers |

### Outputs

- `<staging>/<cache-subdir>/<sha1>.<ext>` — per-file downloaded original.
  SHA-1 is taken over `<site_url>::<server_relative_url>` so re-runs map to
  the same cache file (cache hits skip the m365 download).
- `<staging>/<excerpt-subdir>/<sha1>.txt` — per-file excerpt.
- `<staging>/<manifest-name>` — JSON manifest. Schema documented in
  [`agents/base/global-scope/ato-doc-summarizer/references/manifest-contract.md`](../../../../agents/base/global-scope/ato-doc-summarizer/references/manifest-contract.md).
  Each `files[]` entry carries `cache_file` (relative to `--staging-dir`) at
  top level so the SKILL's Step 5 (COPY) can move the cached file to
  `evidence/`. SharePoint-specific metadata (site URL, filename) lands under
  `source_meta`.

### Exit codes

| Code | Meaning | Manifest written? |
|---|---|---|
| `0` | OK — every candidate downloaded and extracted | yes |
| `1` | Fatal failure (auth missing, m365 not on PATH, IO error) | maybe |
| `2` | No candidates in input | yes (empty `files[]`) |
| `3` | Partial — some files skipped (`extractor_missing`, `download_failed`, `too_large`) | yes |
| `64` | Usage error | no |

### What this script does NOT do

- **No LLM calls.** Excerpt extraction is rote shell work. Summarization is
  the summarizer agent's job.
- **No write to SharePoint.** Read-only on the tenant; only `m365 spo file get`
  (download) is invoked.
- **No copy to `evidence/`.** The skill's Step 5 (COPY) moves cache → evidence/
  for high/medium-confidence files only.
- **No secret scan.** The skill's existing secret-scan still runs at COPY time
  on text files. Excerpts in `.staging/` are scratch; the orchestrator wipes
  `.staging/` at end-of-run.
