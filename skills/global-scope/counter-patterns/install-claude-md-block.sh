#!/usr/bin/env bash
# install-claude-md-block.sh
#
# Manage the counter-patterns block in a CLAUDE.md (or any markdown) file.
# Reversible: every mode is idempotent and operates only on the marker-delimited
# block, leaving the rest of the target file untouched.
#
# Usage:
#   install-claude-md-block.sh <mode> [--target <path>] [--block <path>] [--no-backup]
#
# Modes:
#   prepend   Insert (or replace) the block near the top of the target.
#             For files starting with YAML frontmatter (--- ... ---) the block
#             is inserted immediately after the frontmatter; otherwise it goes
#             at the very top. Idempotent — existing block is removed first.
#   append    Insert (or replace) the block at the bottom of the target.
#             Idempotent — existing block is removed first.
#   remove    Delete the block from the target. No-op if absent.
#   status    Report whether the block is present and at what line range.
#
# Options:
#   --target <path>   Target file to modify. Default: ~/.claude/CLAUDE.md
#                     The target is created if missing (prepend/append).
#   --block <path>    Block source file. Default: ./CLAUDE_MD_BLOCK.md
#                     (resolved relative to this script's directory).
#   --no-backup       Skip the .bak copy normally written next to the target.
#
# Safety:
#   - Always writes a <target>.bak before modifying (unless --no-backup).
#   - Markers are HTML comments so they survive markdown rendering.
#   - The block file MUST contain both BEGIN and END markers literally.

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────

BEGIN_MARKER="<!-- BEGIN counter-patterns block (managed by AgentSkills counter-patterns skill) -->"
END_MARKER="<!-- END counter-patterns block -->"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TARGET="${HOME}/.claude/CLAUDE.md"
DEFAULT_BLOCK="${SCRIPT_DIR}/CLAUDE_MD_BLOCK.md"

# ── Args ──────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

MODE="$1"; shift
TARGET="$DEFAULT_TARGET"
BLOCK="$DEFAULT_BLOCK"
BACKUP=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)    TARGET="$2"; shift 2 ;;
    --block)     BLOCK="$2"; shift 2 ;;
    --no-backup) BACKUP=0; shift ;;
    -h|--help)   sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  prepend|append|remove|status) ;;
  *) echo "unknown mode: $MODE (use prepend|append|remove|status)" >&2; exit 2 ;;
esac

# ── Validation ────────────────────────────────────────────────────────────

if [[ "$MODE" != "status" && "$MODE" != "remove" ]]; then
  if [[ ! -f "$BLOCK" ]]; then
    echo "block source not found: $BLOCK" >&2
    exit 1
  fi
  if ! grep -qF "$BEGIN_MARKER" "$BLOCK" || ! grep -qF "$END_MARKER" "$BLOCK"; then
    echo "block source missing BEGIN/END markers: $BLOCK" >&2
    exit 1
  fi
fi

# ── Block-presence helpers ────────────────────────────────────────────────

block_present() {
  [[ -f "$TARGET" ]] && grep -qF "$BEGIN_MARKER" "$TARGET" && grep -qF "$END_MARKER" "$TARGET"
}

block_range() {
  # Print "BEGIN_LINE END_LINE" if present, else empty.
  [[ -f "$TARGET" ]] || return 0
  local b e
  b=$(grep -nF "$BEGIN_MARKER" "$TARGET" | head -1 | cut -d: -f1 || true)
  e=$(grep -nF "$END_MARKER"   "$TARGET" | head -1 | cut -d: -f1 || true)
  [[ -n "$b" && -n "$e" ]] && echo "$b $e"
}

# ── Mode: status ──────────────────────────────────────────────────────────

if [[ "$MODE" == "status" ]]; then
  if [[ ! -f "$TARGET" ]]; then
    echo "target not present: $TARGET"
    exit 0
  fi
  range=$(block_range)
  if [[ -z "$range" ]]; then
    echo "block: absent in $TARGET"
  else
    read -r b e <<<"$range"
    echo "block: present at lines $b-$e in $TARGET"
  fi
  exit 0
fi

# ── Backup ────────────────────────────────────────────────────────────────

backup_if_needed() {
  if [[ "$BACKUP" -eq 1 && -f "$TARGET" ]]; then
    cp "$TARGET" "${TARGET}.bak"
    echo "backup written: ${TARGET}.bak" >&2
  fi
}

# ── Mode: remove ──────────────────────────────────────────────────────────

remove_block() {
  if [[ ! -f "$TARGET" ]] || ! block_present; then
    return 0
  fi
  local tmp
  tmp=$(mktemp -t cp-claude-md.XXXXXX)
  # Drop the marker-delimited block plus EXACTLY ONE blank line immediately
  # before BEGIN and EXACTLY ONE blank line immediately after END — these are
  # the blanks that prepend/append added when inserting, so removing them
  # restores the original file when the block was the only thing changed.
  # Any user-added blanks beyond that single line on either side survive.
  /usr/bin/awk -v B="$BEGIN_MARKER" -v E="$END_MARKER" '
    BEGIN { state = 0; held_blank = 0 }
    state == 0 {
      if (index($0, B) > 0) { state = 1; held_blank = 0; next }
      if ($0 == "") { if (held_blank) print prev; prev = $0; held_blank = 1; next }
      if (held_blank) { print prev; held_blank = 0 }
      print
      next
    }
    state == 1 {
      if (index($0, E) > 0) { state = 2 }
      next
    }
    state == 2 {
      if ($0 == "") { state = 3; next }   # eat exactly one trailing blank
      state = 3
      print
      next
    }
    state == 3 { print }
    END {
      # If BEGIN never matched and we are still holding a blank, emit it.
      if (state == 0 && held_blank) print prev
    }
  ' "$TARGET" > "$tmp"
  mv "$tmp" "$TARGET"
}

if [[ "$MODE" == "remove" ]]; then
  if [[ ! -f "$TARGET" ]]; then
    echo "target not present: $TARGET" >&2
    exit 0
  fi
  if ! block_present; then
    echo "block: absent — nothing to remove"
    exit 0
  fi
  backup_if_needed
  remove_block
  echo "block: removed from $TARGET"
  exit 0
fi

# ── Mode: prepend / append ────────────────────────────────────────────────

mkdir -p "$(dirname "$TARGET")"
[[ -f "$TARGET" ]] || : > "$TARGET"
backup_if_needed
remove_block  # idempotent insert: drop existing first

tmp=$(mktemp -t cp-claude-md.XXXXXX)

if [[ "$MODE" == "append" ]]; then
  # Trim trailing blank lines from target, then add one blank line + block + newline.
  /usr/bin/awk '
    { lines[NR]=$0 }
    END {
      last = 0
      for (i = NR; i >= 1; i--) if (lines[i] != "") { last = i; break }
      for (i = 1; i <= last; i++) print lines[i]
    }
  ' "$TARGET" > "$tmp"
  printf '\n' >> "$tmp"
  cat "$BLOCK" >> "$tmp"
else
  # prepend: insert after YAML frontmatter (if present) or at top.
  if [[ -s "$TARGET" ]] && /usr/bin/awk 'NR==1 { if ($0 == "---") exit 0; else exit 1 }' "$TARGET"; then
    # Frontmatter present — find closing ---
    fm_end=$(/usr/bin/awk 'NR>1 && $0 == "---" { print NR; exit }' "$TARGET")
    if [[ -n "$fm_end" ]]; then
      head -n "$fm_end" "$TARGET" > "$tmp"
      printf '\n' >> "$tmp"
      cat "$BLOCK" >> "$tmp"
      printf '\n' >> "$tmp"
      tail -n +"$((fm_end + 1))" "$TARGET" >> "$tmp"
    else
      # Malformed frontmatter (opening --- but no close) — fall back to top.
      cat "$BLOCK" > "$tmp"
      printf '\n' >> "$tmp"
      cat "$TARGET" >> "$tmp"
    fi
  else
    # No frontmatter — insert at top.
    cat "$BLOCK" > "$tmp"
    if [[ -s "$TARGET" ]]; then
      printf '\n' >> "$tmp"
      cat "$TARGET" >> "$tmp"
    fi
  fi
fi

mv "$tmp" "$TARGET"
echo "block: ${MODE}ed into $TARGET"
