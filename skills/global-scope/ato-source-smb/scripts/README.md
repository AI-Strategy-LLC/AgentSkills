# SMB Pre-Scan Scripts

Helper scripts the `ato-source-smb` skill invokes during its PRE-SCAN step.
These do the rote walk-and-extract work outside any LLM context so document
text never lands in the orchestrator's main conversation.

## `smb-walk-extract.sh`

Walks an SMB-mounted share depth-limited, extracts a short text excerpt from
each candidate document, and writes a source-agnostic manifest the
[`ato-doc-summarizer`](../../../../agents/base/global-scope/ato-doc-summarizer/)
agent consumes.

### Required tools

- `jq` — JSON construction
- `sha1sum` (Linux) **or** `shasum` (macOS) — stable per-path excerpt hashing
- `find`, `head`, `sed`, `tr`, `awk` — POSIX core utilities

### Optional extractors (graceful-degrade)

If any of these is missing, files of the corresponding type are recorded in
the manifest's `skipped` array with `reason: extractor_missing` and a
`missing_tool` hint. The script still succeeds — exit code `3` (partial).

| Tool | Covers | Install (macOS) | Install (Debian/Ubuntu) | Install (Windows) |
|---|---|---|---|---|
| `pdftotext` (poppler) | `.pdf` | `brew install poppler` | `apt-get install poppler-utils` | `choco install poppler` |
| `pandoc` | `.docx` (preferred) | `brew install pandoc` | `apt-get install pandoc` | `choco install pandoc` |
| `unzip` | `.docx` (fallback), `.xlsx`, `.pptx` | preinstalled | preinstalled | `choco install unzip` |

Legacy binary Office formats (`.doc`, `.xls`, `.ppt`) have no portable shell
extractor; they're skipped with `reason: extractor_unsupported`. If your share
contains many of these, convert them to `.docx` / `.xlsx` / `.pptx` upstream
or skip them by removing those extensions from the file-type allow list in
the discovery patterns.

### Usage

```bash
smb-walk-extract.sh \
  --mount-point /Users/alice/mnt/ato-policies \
  --uri-prefix smb://fileserver.corp/ato \
  --staging-dir docs/ato-package/.staging \
  --depth 3
```

Optional flags:

| Flag | Default | Purpose |
|---|---|---|
| `--excerpt-subdir` | `smb-excerpts` | Subdirectory of `--staging-dir` for excerpt files |
| `--manifest-name` | `smb-manifest.json` | Manifest filename under `--staging-dir` |
| `--source` | `smb` | Source identifier embedded in the manifest and file IDs |
| `--max-bytes` | `52428800` (50 MB) | Files larger than this are skipped as `too_large` |
| `--scan-id` | auto (`<source>-<UTC-ISO>`) | Override for stable scan identifiers |

### Outputs

- `<staging-dir>/<excerpt-subdir>/<sha1>.txt` — one excerpt per file. SHA-1 is
  hashed from the absolute path (so re-runs against the same share map to the
  same excerpt files; cheap to re-summarize after rubric tuning).
- `<staging-dir>/<manifest-name>` — JSON manifest. Schema documented in
  [`agents/base/global-scope/ato-doc-summarizer/references/manifest-contract.md`](../../../../agents/base/global-scope/ato-doc-summarizer/references/manifest-contract.md).

### Exit codes

| Code | Meaning | Manifest written? |
|---|---|---|
| `0` | OK — every candidate extracted | yes |
| `1` | Mount/walk/IO failure | maybe |
| `2` | No candidates found | yes (empty `files[]`) |
| `3` | Partial — some files skipped extractor_missing | yes |
| `64` | Usage error | no |

### Multiple shares

The script handles **one share per invocation**. The `ato-source-smb` skill
loops over configured shares and merges the per-share manifests with `jq -s`
before invoking the summarizer agent.

### What this script does NOT do

- **No LLM calls.** Excerpt extraction is rote shell work. Summarization is
  the summarizer agent's job.
- **No mount / unmount.** The skill mounts and unmounts; this script assumes
  `--mount-point` is already a readable directory.
- **No write to the share.** Read-only on the input.
- **No copy to `evidence/`.** The skill's COPY step does that, after reading
  the inventory the summarizer produces.
- **No secret scan.** The skill's existing secret-scan still runs at COPY
  time on text files. Excerpts in `.staging/` are scratch; the orchestrator
  wipes `.staging/` at end-of-run.
