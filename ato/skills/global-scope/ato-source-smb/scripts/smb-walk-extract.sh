#!/usr/bin/env bash
# smb-walk-extract.sh — Walk an SMB-mounted share, extract short text excerpts
# from candidate documents, and emit a source-agnostic manifest for the
# ato-doc-summarizer agent.
#
# Strictly read-only on the mount. Never writes back to the share. Never
# auto-installs missing extractors — gracefully records them as gaps.
#
# Outputs (under --staging-dir):
#   <excerpt-subdir>/<sha1>.txt   — per-file excerpt (first ~3 pages or ~8 KB)
#   <manifest-name>               — JSON manifest, see references/
#                                   manifest-contract.md in ato-doc-summarizer
#
# Exit codes:
#   0  ok (manifest written, every candidate extracted)
#   1  mount/walk/IO failure (manifest may not be written)
#   2  no candidates found (manifest written with empty files[])
#   3  partial (manifest written; some files skipped extractor_missing)
#   64 usage error
#
# This script is part of the ato-source-smb skill. It runs entirely outside
# any LLM context — its job is rote walk-and-extract so that the document
# text never lands in the orchestrator's main conversation.

set -u

usage() {
  cat >&2 <<EOF
Usage: smb-walk-extract.sh \\
  --mount-point <path> \\
  --uri-prefix <smb://host/share> \\
  --staging-dir <path> \\
  [--excerpt-subdir <name>=smb-excerpts] \\
  [--manifest-name <name>=smb-manifest.json] \\
  [--depth <n>=3] \\
  [--source <name>=smb] \\
  [--max-bytes <n>=52428800] \\
  [--scan-id <id>=auto]

Walks the mounted share depth-limited, extracts a short text excerpt from
each candidate document, and writes a manifest the ato-doc-summarizer agent
consumes.

Required tools: jq, sha1sum or shasum.
Optional extractors (graceful-degrade): pdftotext, pandoc, unzip.
EOF
}

# ---------- argument parsing ----------

MOUNT_POINT=""
URI_PREFIX=""
STAGING_DIR=""
EXCERPT_SUBDIR="smb-excerpts"
MANIFEST_NAME="smb-manifest.json"
DEPTH=3
SOURCE="smb"
MAX_BYTES=52428800
SCAN_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mount-point)    MOUNT_POINT="${2:-}"; shift 2 ;;
    --uri-prefix)     URI_PREFIX="${2:-}"; shift 2 ;;
    --staging-dir)    STAGING_DIR="${2:-}"; shift 2 ;;
    --excerpt-subdir) EXCERPT_SUBDIR="${2:-}"; shift 2 ;;
    --manifest-name)  MANIFEST_NAME="${2:-}"; shift 2 ;;
    --depth)          DEPTH="${2:-}"; shift 2 ;;
    --source)         SOURCE="${2:-}"; shift 2 ;;
    --max-bytes)      MAX_BYTES="${2:-}"; shift 2 ;;
    --scan-id)        SCAN_ID="${2:-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "Unknown option: $1" >&2; usage; exit 64 ;;
  esac
done

[ -n "$MOUNT_POINT" ] || { echo "--mount-point is required" >&2; exit 64; }
[ -n "$URI_PREFIX" ]  || { echo "--uri-prefix is required" >&2; exit 64; }
[ -n "$STAGING_DIR" ] || { echo "--staging-dir is required" >&2; exit 64; }
[ -d "$MOUNT_POINT" ] || { echo "Mount point not a directory: $MOUNT_POINT" >&2; exit 1; }

# ---------- required tools ----------

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

excerpt_dir="$STAGING_DIR/$EXCERPT_SUBDIR"
manifest_path="$STAGING_DIR/$MANIFEST_NAME"
mkdir -p "$excerpt_dir" || { echo "Failed to mkdir $excerpt_dir" >&2; exit 1; }

files_jsonl="$(mktemp -t smb-walk-files.XXXXXX)"
skipped_jsonl="$(mktemp -t smb-walk-skipped.XXXXXX)"
trap 'rm -f "$files_jsonl" "$skipped_jsonl"' EXIT

# ---------- counters ----------

candidates=0
extracted=0
skipped_too_large=0
skipped_extractor_missing=0
skipped_unsupported_type=0
partial=0

# ---------- portable stat helpers (Linux GNU vs macOS/BSD) ----------

stat_size() {
  if stat -c%s "$1" >/dev/null 2>&1; then
    stat -c%s "$1"
  else
    stat -f%z "$1"
  fi
}

stat_mtime_iso() {
  local epoch
  if epoch=$(stat -c%Y "$1" 2>/dev/null); then
    date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ
  else
    epoch=$(stat -f%m "$1")
    date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ
  fi
}

# ---------- walk + extract ----------

# find: prune excluded directory names at any depth, then match candidate
# file types. -print0 + read -d '' handles filenames with spaces / unicode.
while IFS= read -r -d '' path; do
  candidates=$((candidates + 1))
  size_bytes=$(stat_size "$path" 2>/dev/null) || size_bytes=0
  rel_path="${path#"$MOUNT_POINT"/}"
  uri="$URI_PREFIX/$rel_path"
  mtime=$(stat_mtime_iso "$path" 2>/dev/null || echo "")
  ext_lower=$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')

  # size gate
  if [ "$size_bytes" -gt "$MAX_BYTES" ]; then
    skipped_too_large=$((skipped_too_large + 1))
    jq -nc \
      --arg path "$path" \
      --arg reason "too_large" \
      --argjson size "$size_bytes" \
      '{path:$path, reason:$reason, size_bytes:$size}' >> "$skipped_jsonl"
    continue
  fi

  excerpt_id=$(sha1_of "$path")
  excerpt_file="$excerpt_dir/$excerpt_id.txt"
  rel_excerpt="$EXCERPT_SUBDIR/$excerpt_id.txt"

  reason=""
  missing_tool=""

  case "$ext_lower" in
    pdf)
      if [ "$have_pdftotext" = "1" ]; then
        pdftotext -l 3 -q -- "$path" - 2>/dev/null | head -c 8192 > "$excerpt_file" || true
      else
        reason="extractor_missing"; missing_tool="pdftotext"
      fi
      ;;
    docx)
      if [ "$have_pandoc" = "1" ]; then
        pandoc --to=plain -- "$path" 2>/dev/null | head -c 8192 > "$excerpt_file" || true
      elif [ "$have_unzip" = "1" ]; then
        unzip -p -- "$path" word/document.xml 2>/dev/null \
          | sed 's/<[^>]*>//g' | tr -s ' \n\t' ' ' \
          | head -c 8192 > "$excerpt_file" || true
      else
        reason="extractor_missing"; missing_tool="pandoc-or-unzip"
      fi
      ;;
    pptx|xlsx)
      if [ "$have_unzip" = "1" ]; then
        unzip -p -- "$path" '*.xml' 2>/dev/null \
          | sed 's/<[^>]*>//g' | tr -s ' \n\t' ' ' \
          | head -c 8192 > "$excerpt_file" || true
      else
        reason="extractor_missing"; missing_tool="unzip"
      fi
      ;;
    md|txt)
      head -c 8192 -- "$path" > "$excerpt_file" 2>/dev/null || true
      ;;
    doc|xls|ppt)
      # Legacy binary OLE — no portable shell extractor.
      reason="extractor_unsupported"; missing_tool="legacy-office-binary"
      ;;
    *)
      reason="extractor_unsupported"; missing_tool="$ext_lower"
      ;;
  esac

  if [ -n "$reason" ]; then
    if [ "$reason" = "extractor_missing" ]; then
      skipped_extractor_missing=$((skipped_extractor_missing + 1))
      partial=1
    else
      skipped_unsupported_type=$((skipped_unsupported_type + 1))
    fi
    jq -nc \
      --arg path "$path" \
      --arg reason "$reason" \
      --arg type "$ext_lower" \
      --arg missing_tool "$missing_tool" \
      '{path:$path, reason:$reason, type:$type, missing_tool:$missing_tool}' \
      >> "$skipped_jsonl"
    continue
  fi

  extracted=$((extracted + 1))
  printf -v file_id "%s-pre-%04d" "$SOURCE" "$extracted"
  jq -nc \
    --arg id "$file_id" \
    --arg path "$path" \
    --arg uri "$uri" \
    --argjson size "$size_bytes" \
    --arg mtime "$mtime" \
    --arg type "$ext_lower" \
    --arg excerpt "$rel_excerpt" \
    --arg hint "" \
    '{id:$id, path:$path, uri:$uri, size_bytes:$size, mtime:$mtime, type:$type, excerpt_file:$excerpt, filename_hint:$hint}' \
    >> "$files_jsonl"

done < <(
  find "$MOUNT_POINT" -maxdepth "$DEPTH" \
    \( -type d \( \
         -iname Archive -o -iname Archives -o -iname Old -o -iname Obsolete \
         -o -iname Deprecated -o -iname Personal -o -iname "My Documents" \
         -o -iname "Recycle Bin" -o -iname ".Trash" -o -iname ".Trashes" \
         -o -name '$RECYCLE.BIN' \
      \) -prune \) -o \
    \( -type f \( \
         -iname '*.pdf' -o -iname '*.docx' -o -iname '*.doc' \
         -o -iname '*.xlsx' -o -iname '*.xls' \
         -o -iname '*.pptx' -o -iname '*.ppt' \
         -o -iname '*.md' -o -iname '*.txt' \
      \) -print0 \) 2>/dev/null
)

# ---------- write manifest ----------

# --slurpfile reads JSON values one-per-line into an array; an empty file
# yields []. Both jsonl files exist (touched at mktemp time).
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
      skipped_unsupported_type: $unsupported
    },
    files: $files,
    skipped: $skipped
  }' > "$manifest_path" || { echo "Failed to write manifest" >&2; exit 1; }

# ---------- summarize to stderr ----------

{
  echo "smb-walk-extract: $candidates candidates, $extracted extracted,"
  echo "  too_large=$skipped_too_large, extractor_missing=$skipped_extractor_missing,"
  echo "  unsupported_type=$skipped_unsupported_type"
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
