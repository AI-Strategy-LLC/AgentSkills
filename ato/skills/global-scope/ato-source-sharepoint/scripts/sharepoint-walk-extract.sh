#!/usr/bin/env bash
# sharepoint-walk-extract.sh — Download SharePoint candidate files and extract
# text excerpts for the ato-doc-summarizer agent.
#
# Reads a candidates JSON (one entry per file, with site_url,
# server_relative_url, filename, size_bytes, mtime). For each candidate:
#   1. Downloads the file via `m365 spo file get --asFile` into
#      .staging/<cache-subdir>/<sha1>.<ext>  (the cache is reused by the
#      skill's COPY step — no re-download).
#   2. Extracts a short excerpt to .staging/<excerpt-subdir>/<sha1>.txt.
#   3. Emits a manifest entry matching the ato-doc-summarizer contract.
#
# Strictly read-only on SharePoint. Never writes to the tenant. Never
# auto-installs missing extractors — gracefully records skipped files.
#
# NOTE on duplication: the per-file-type excerpt extraction below is the
# same logic that lives in ../../ato-source-smb/scripts/smb-walk-extract.sh
# and ../../ato-source-onedrive/scripts/onedrive-walk-extract.sh. The
# duplication is intentional for now (each sibling installs as a self-
# contained unit). If you change the extraction here, update the matching
# code in those scripts too.
#
# Required tools: m365, jq, sha1sum or shasum.
# Optional extractors (graceful-degrade): pdftotext, pandoc, unzip.
#
# Outputs (under --staging-dir):
#   <cache-subdir>/<sha1>.<ext>    — downloaded original (kept for COPY step)
#   <excerpt-subdir>/<sha1>.txt    — first ~3 pages or ~8 KB of text
#   <manifest-name>                — JSON manifest, see manifest-contract.md
#
# Exit codes:
#   0  ok (manifest written, every candidate downloaded + extracted)
#   1  fatal failure (auth missing, m365 not on PATH, IO error)
#   2  no candidates in input
#   3  partial (some files skipped: extractor_missing, download_failed,
#               or too_large)
#   64 usage error

set -u

usage() {
  cat >&2 <<EOF
Usage: sharepoint-walk-extract.sh \\
  --candidates-json <path> \\
  --staging-dir <path> \\
  [--cache-subdir <name>=sharepoint-cache] \\
  [--excerpt-subdir <name>=sharepoint-excerpts] \\
  [--manifest-name <name>=sharepoint-manifest.json] \\
  [--source <name>=sharepoint] \\
  [--max-bytes <n>=52428800] \\
  [--scan-id <id>=auto]

Reads the candidates JSON (an array; each entry has site_url,
server_relative_url, filename, size_bytes, mtime), downloads each file via
m365, extracts a short excerpt, and emits a manifest the ato-doc-summarizer
agent consumes.

Required tools: m365, jq, sha1sum or shasum.
Optional extractors (graceful-degrade): pdftotext, pandoc, unzip.
EOF
}

# ---------- argument parsing ----------

CANDIDATES_JSON=""
STAGING_DIR=""
CACHE_SUBDIR="sharepoint-cache"
EXCERPT_SUBDIR="sharepoint-excerpts"
MANIFEST_NAME="sharepoint-manifest.json"
SOURCE="sharepoint"
MAX_BYTES=52428800
SCAN_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --candidates-json) CANDIDATES_JSON="${2:-}"; shift 2 ;;
    --staging-dir)     STAGING_DIR="${2:-}"; shift 2 ;;
    --cache-subdir)    CACHE_SUBDIR="${2:-}"; shift 2 ;;
    --excerpt-subdir)  EXCERPT_SUBDIR="${2:-}"; shift 2 ;;
    --manifest-name)   MANIFEST_NAME="${2:-}"; shift 2 ;;
    --source)          SOURCE="${2:-}"; shift 2 ;;
    --max-bytes)       MAX_BYTES="${2:-}"; shift 2 ;;
    --scan-id)         SCAN_ID="${2:-}"; shift 2 ;;
    -h|--help)         usage; exit 0 ;;
    *)                 echo "Unknown option: $1" >&2; usage; exit 64 ;;
  esac
done

[ -n "$CANDIDATES_JSON" ] || { echo "--candidates-json is required" >&2; exit 64; }
[ -n "$STAGING_DIR" ]     || { echo "--staging-dir is required" >&2; exit 64; }
[ -f "$CANDIDATES_JSON" ] || { echo "Candidates JSON not found: $CANDIDATES_JSON" >&2; exit 1; }

# ---------- required tools ----------

command -v m365 >/dev/null 2>&1 || {
  echo "m365 CLI is required (npm install -g @pnp/cli-microsoft365)" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "jq is required (brew install jq / apt-get install jq)" >&2
  exit 1
}

if command -v sha1sum >/dev/null 2>&1; then
  sha1_of() { printf '%s' "$1" | sha1sum | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  sha1_of() { printf '%s' "$1" | shasum -a 1 | awk '{print $1}'; }
else
  echo "Need sha1sum or shasum on PATH" >&2; exit 1
fi

[ -z "$SCAN_ID" ] && SCAN_ID="${SOURCE}-$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------- probe optional extractors ----------

have_pdftotext=0; command -v pdftotext >/dev/null 2>&1 && have_pdftotext=1
have_pandoc=0;    command -v pandoc    >/dev/null 2>&1 && have_pandoc=1
have_unzip=0;     command -v unzip     >/dev/null 2>&1 && have_unzip=1

# ---------- prepare staging ----------

cache_dir="$STAGING_DIR/$CACHE_SUBDIR"
excerpt_dir="$STAGING_DIR/$EXCERPT_SUBDIR"
manifest_path="$STAGING_DIR/$MANIFEST_NAME"
mkdir -p "$cache_dir" "$excerpt_dir" || {
  echo "Failed to create cache/excerpt dirs under $STAGING_DIR" >&2; exit 1; }

files_jsonl="$(mktemp -t sp-walk-files.XXXXXX)"
skipped_jsonl="$(mktemp -t sp-walk-skipped.XXXXXX)"
trap 'rm -f "$files_jsonl" "$skipped_jsonl"' EXIT

# ---------- counters ----------

candidates=0
extracted=0
skipped_too_large=0
skipped_extractor_missing=0
skipped_unsupported_type=0
skipped_download_failed=0
partial=0

# ---------- excerpt extractor (per-file-type) ----------
# DUPLICATED in smb-walk-extract.sh and onedrive-walk-extract.sh — keep in sync.

extract_excerpt() {
  # $1 = downloaded file path, $2 = excerpt output path, $3 = lowercased extension
  # Sets the global `reason` and `missing_tool` on failure.
  local in="$1" out="$2" ext="$3"
  reason=""; missing_tool=""
  case "$ext" in
    pdf)
      if [ "$have_pdftotext" = "1" ]; then
        pdftotext -l 3 -q -- "$in" - 2>/dev/null | head -c 8192 > "$out" || true
      else
        reason="extractor_missing"; missing_tool="pdftotext"
      fi
      ;;
    docx)
      if [ "$have_pandoc" = "1" ]; then
        pandoc --to=plain -- "$in" 2>/dev/null | head -c 8192 > "$out" || true
      elif [ "$have_unzip" = "1" ]; then
        unzip -p -- "$in" word/document.xml 2>/dev/null \
          | sed 's/<[^>]*>//g' | tr -s ' \n\t' ' ' \
          | head -c 8192 > "$out" || true
      else
        reason="extractor_missing"; missing_tool="pandoc-or-unzip"
      fi
      ;;
    pptx|xlsx)
      if [ "$have_unzip" = "1" ]; then
        unzip -p -- "$in" '*.xml' 2>/dev/null \
          | sed 's/<[^>]*>//g' | tr -s ' \n\t' ' ' \
          | head -c 8192 > "$out" || true
      else
        reason="extractor_missing"; missing_tool="unzip"
      fi
      ;;
    md|txt)
      head -c 8192 -- "$in" > "$out" 2>/dev/null || true
      ;;
    doc|xls|ppt)
      reason="extractor_unsupported"; missing_tool="legacy-office-binary"
      ;;
    *)
      reason="extractor_unsupported"; missing_tool="$ext"
      ;;
  esac
}

# ---------- iterate candidates ----------

# Read the candidates JSON as JSONL via jq -c .[]
while IFS= read -r line; do
  candidates=$((candidates + 1))

  site_url=$(jq -r '.site_url // ""'             <<<"$line")
  server_rel=$(jq -r '.server_relative_url // ""' <<<"$line")
  filename=$(jq -r '.filename // ""'             <<<"$line")
  size_bytes=$(jq -r '.size_bytes // 0'          <<<"$line")
  mtime=$(jq -r '.mtime // ""'                   <<<"$line")

  if [ -z "$site_url" ] || [ -z "$server_rel" ] || [ -z "$filename" ]; then
    skipped_unsupported_type=$((skipped_unsupported_type + 1))
    jq -nc --arg path "$server_rel" --arg reason "malformed_entry" \
           --arg type "" --arg missing_tool "" \
      '{path:$path, reason:$reason, type:$type, missing_tool:$missing_tool}' \
      >> "$skipped_jsonl"
    continue
  fi

  ext_lower=$(printf '%s' "${filename##*.}" | tr '[:upper:]' '[:lower:]')

  # size gate (use server-reported size; we don't probe pre-download)
  if [ "$size_bytes" -gt "$MAX_BYTES" ]; then
    skipped_too_large=$((skipped_too_large + 1))
    jq -nc \
      --arg path "$server_rel" \
      --arg reason "too_large" \
      --argjson size "$size_bytes" \
      '{path:$path, reason:$reason, size_bytes:$size}' >> "$skipped_jsonl"
    continue
  fi

  excerpt_id=$(sha1_of "${site_url}::${server_rel}")
  cache_file="$cache_dir/${excerpt_id}.${ext_lower}"
  excerpt_file="$excerpt_dir/${excerpt_id}.txt"
  rel_excerpt="$EXCERPT_SUBDIR/${excerpt_id}.txt"
  rel_cache="$CACHE_SUBDIR/${excerpt_id}.${ext_lower}"

  # Download (m365 spo file get --asFile). Re-use cache if already downloaded.
  if [ ! -s "$cache_file" ]; then
    if ! m365 spo file get \
            --webUrl "$site_url" \
            --url "$server_rel" \
            --asFile \
            --path "$cache_file" \
            >/dev/null 2>&1; then
      skipped_download_failed=$((skipped_download_failed + 1))
      partial=1
      jq -nc \
        --arg path "$server_rel" \
        --arg reason "download_failed" \
        --arg type "$ext_lower" \
        --arg missing_tool "" \
        '{path:$path, reason:$reason, type:$type, missing_tool:$missing_tool}' \
        >> "$skipped_jsonl"
      continue
    fi
  fi

  # Extract
  reason=""; missing_tool=""
  extract_excerpt "$cache_file" "$excerpt_file" "$ext_lower"

  if [ -n "$reason" ]; then
    if [ "$reason" = "extractor_missing" ]; then
      skipped_extractor_missing=$((skipped_extractor_missing + 1))
      partial=1
    else
      skipped_unsupported_type=$((skipped_unsupported_type + 1))
    fi
    jq -nc \
      --arg path "$server_rel" \
      --arg reason "$reason" \
      --arg type "$ext_lower" \
      --arg missing_tool "$missing_tool" \
      '{path:$path, reason:$reason, type:$type, missing_tool:$missing_tool}' \
      >> "$skipped_jsonl"
    continue
  fi

  extracted=$((extracted + 1))
  printf -v file_id "%s-pre-%04d" "$SOURCE" "$extracted"

  # uri = full https URL (site_url + server_rel beyond the host portion)
  # The server_relative_url already includes the site path, so the full URL is
  # the host portion of site_url + server_rel.
  host_portion="${site_url%%/sites/*}"   # strip from /sites/ onwards
  [ "$host_portion" = "$site_url" ] && host_portion="${site_url%/}"  # fallback
  uri="${host_portion}${server_rel}"

  jq -nc \
    --arg id "$file_id" \
    --arg path "$server_rel" \
    --arg uri "$uri" \
    --argjson size "$size_bytes" \
    --arg mtime "$mtime" \
    --arg type "$ext_lower" \
    --arg excerpt "$rel_excerpt" \
    --arg cache "$rel_cache" \
    --arg site "$site_url" \
    --arg filename "$filename" \
    --arg hint "" \
    '{id:$id, path:$path, uri:$uri, size_bytes:$size, mtime:$mtime,
      type:$type, excerpt_file:$excerpt, cache_file:$cache,
      filename_hint:$hint, source_meta: {site_url:$site, filename:$filename}}' \
    >> "$files_jsonl"

done < <(jq -c '.[]' "$CANDIDATES_JSON")

# ---------- write manifest ----------

jq -n \
  --arg schema "1.0" \
  --arg source "$SOURCE" \
  --arg scan_id "$SCAN_ID" \
  --arg root "$EXCERPT_SUBDIR" \
  --argjson candidates "$candidates" \
  --argjson extracted "$extracted" \
  --argjson too_large "$skipped_too_large" \
  --argjson missing "$skipped_extractor_missing" \
  --argjson unsupported "$skipped_unsupported_type" \
  --argjson download_failed "$skipped_download_failed" \
  --slurpfile files "$files_jsonl" \
  --slurpfile skipped "$skipped_jsonl" \
  '{
    schema_version: $schema,
    source: $source,
    scan_id: $scan_id,
    extracted_root: $root,
    totals: {
      candidates: $candidates,
      excerpts_extracted: $extracted,
      skipped_too_large: $too_large,
      skipped_extractor_missing: $missing,
      skipped_unsupported_type: $unsupported,
      skipped_download_failed: $download_failed
    },
    files: $files,
    skipped: $skipped
  }' > "$manifest_path" || { echo "Failed to write manifest" >&2; exit 1; }

# ---------- summarize to stderr ----------

{
  echo "sharepoint-walk-extract: $candidates candidates, $extracted extracted,"
  echo "  too_large=$skipped_too_large, extractor_missing=$skipped_extractor_missing,"
  echo "  unsupported=$skipped_unsupported_type, download_failed=$skipped_download_failed"
  echo "  manifest: $manifest_path"
  if [ "$skipped_extractor_missing" -gt 0 ]; then
    echo "  hint: install pdftotext (poppler), pandoc, or unzip to cover skipped types"
  fi
} >&2

# ---------- exit code ----------

if [ "$candidates" = "0" ]; then
  exit 2
elif [ "$partial" = "1" ]; then
  exit 3
else
  exit 0
fi
