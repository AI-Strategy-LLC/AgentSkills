#!/usr/bin/env bash
# bin/sync-ato.sh — keep the ato/ subset in sync with the canonical sources.
#
# The ato/ folder is independently shareable: copy it onto a shared drive and
# `bash ato/install.sh` works without the rest of this repo. To make that
# possible, ato/ bundles its own copies of the per-CLI renderers, so the
# ATO installer can render agents without the canonical agents/renderers/.
#
# The renderer copies are MIRRORS of the canonical agents/renderers/. This
# script is the single source of "in sync" between them.
#
# Editor contract:
#   - To change a renderer, edit `agents/renderers/<file>` ONLY. Do not edit
#     the ato/ mirror.
#   - To change anything else under ato/ (the ATO skills, ATO agents, the
#     auth-config / auth-interview skills which now live canonically there)
#     edit under `ato/` directly — there is no canonical home elsewhere.
#   - Run `bin/sync-ato.sh` before committing. The pre-commit hook
#     (.githooks/pre-commit) runs `--check` automatically; CI runs `--check`
#     on every PR.
#
# Modes:
#   bin/sync-ato.sh             write changes, report what was synced
#   bin/sync-ato.sh --check     exit 1 if anything is stale; no writes
#   bin/sync-ato.sh --list      print what would be synced; no writes
#   bin/sync-ato.sh -h | --help help

set -euo pipefail

# ---- locate repo root -----------------------------------------------------
if root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ]; then
    cd "$root"
else
    cd "$(cd "$(dirname "$0")/.." && pwd)"
fi

usage() {
    cat <<EOF
Usage: bin/sync-ato.sh [--check | --list | -h]

  (default)   Sync canonical sources into ato/. Idempotent.
  --check     Report drift, exit 1 if anything is stale. No writes.
  --list      Print the (canonical, mirror) pairs and current sync state.
  -h, --help  This message.

The pairs synced are listed in this script's PAIRS array.
EOF
}

mode="sync"
case "${1:-}" in
    --check) mode="check" ;;
    --list)  mode="list"  ;;
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

# ---- pairs ----------------------------------------------------------------
# Each row: "canonical:mirror". If canonical is a directory, the mirror is
# replaced wholesale (rm -rf + cp -R). If it's a file, the mirror is replaced
# with cp.
PAIRS=(
    "agents/renderers/_lib.sh:ato/agents/renderers/_lib.sh"
    "agents/renderers/claude.sh:ato/agents/renderers/claude.sh"
    "agents/renderers/codex.sh:ato/agents/renderers/codex.sh"
    "agents/renderers/codex-agents-md.sh:ato/agents/renderers/codex-agents-md.sh"
    "agents/renderers/cursor.sh:ato/agents/renderers/cursor.sh"
    "agents/renderers/gemini.sh:ato/agents/renderers/gemini.sh"
    "agents/renderers/kilo.sh:ato/agents/renderers/kilo.sh"
    "agents/renderers/opencode.sh:ato/agents/renderers/opencode.sh"
)

# ---- helpers --------------------------------------------------------------
# Returns 0 if mirror exists and matches canonical byte-for-byte.
is_in_sync() {
    local src="$1" dst="$2"
    if [ -d "$src" ]; then
        [ -d "$dst" ] || return 1
        diff -rq "$src" "$dst" >/dev/null 2>&1
    elif [ -f "$src" ]; then
        [ -f "$dst" ] || return 1
        cmp -s "$src" "$dst"
    else
        echo "sync-ato.sh: canonical missing: $src" >&2
        return 2
    fi
}

# Reason a pair is out of sync, for human-readable reporting.
drift_reason() {
    local src="$1" dst="$2"
    if [ -d "$src" ]; then
        [ -d "$dst" ] || { printf 'mirror missing'; return; }
        # Show first 2 differing entries.
        local diffs; diffs=$(diff -rq "$src" "$dst" 2>&1 | head -2 | sed 's/^/    /')
        printf 'content differs:\n%s' "$diffs"
    elif [ -f "$src" ]; then
        [ -f "$dst" ] || { printf 'mirror missing'; return; }
        printf 'content differs'
    else
        printf 'canonical missing'
    fi
}

# ---- modes ----------------------------------------------------------------
sync_pair() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -d "$src" ]; then
        rm -rf "$dst"
        cp -R "$src" "$dst"
    elif [ -f "$src" ]; then
        cp "$src" "$dst"
        # Preserve executable bit if the canonical was executable.
        if [ -x "$src" ]; then chmod +x "$dst"; fi
    else
        echo "sync-ato.sh: canonical missing: $src" >&2
        return 1
    fi
}

case "$mode" in
    list)
        printf '%-55s  %-55s  %s\n' "CANONICAL" "MIRROR" "STATE"
        for pair in "${PAIRS[@]}"; do
            src="${pair%%:*}" dst="${pair#*:}"
            if is_in_sync "$src" "$dst"; then state="in sync"
            else                              state="STALE"
            fi
            printf '%-55s  %-55s  %s\n' "$src" "$dst" "$state"
        done
        ;;

    check)
        stale=0
        for pair in "${PAIRS[@]}"; do
            src="${pair%%:*}" dst="${pair#*:}"
            if ! is_in_sync "$src" "$dst"; then
                if [ "$stale" = 0 ]; then
                    echo "sync-ato.sh: ato/ is out of sync with canonical sources." >&2
                    stale=1
                fi
                printf '  %s -> %s : %s\n' "$src" "$dst" "$(drift_reason "$src" "$dst")" >&2
            fi
        done
        if [ "$stale" = 1 ]; then
            echo >&2
            echo "Run \`bin/sync-ato.sh\` to update the ato/ mirrors, then commit." >&2
            exit 1
        fi
        echo "sync-ato.sh: ato/ is in sync with canonical sources."
        ;;

    sync)
        synced=0
        for pair in "${PAIRS[@]}"; do
            src="${pair%%:*}" dst="${pair#*:}"
            if is_in_sync "$src" "$dst"; then continue; fi
            sync_pair "$src" "$dst"
            printf '  synced: %s -> %s\n' "$src" "$dst"
            synced=$((synced + 1))
        done
        if [ "$synced" = 0 ]; then
            echo "sync-ato.sh: nothing to do — already in sync."
        else
            echo "sync-ato.sh: synced $synced item(s)."
        fi
        ;;
esac
