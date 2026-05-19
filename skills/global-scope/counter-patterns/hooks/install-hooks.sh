#!/usr/bin/env bash
# install-hooks.sh — copy counter-patterns hook scripts into a hooks directory
# and print a settings.json snippet with paths resolved.
#
# Usage:
#   install-hooks.sh [install|uninstall|status] [--target <dir>] [--snippet-only]
#
# Modes:
#   install        Copy hook scripts to <target>, chmod +x them, then print the
#                  resolved settings-snippet.json. Default mode.
#   uninstall      Delete counter-patterns hooks from <target>. Does NOT touch
#                  settings.json — the user removes those entries manually.
#   status         Report which hooks are installed under <target>.
#
# Options:
#   --target <dir>   Destination hooks directory. Default: ~/.claude/hooks
#   --snippet-only   Skip copy/chmod; just print the resolved snippet.
#
# Note: the hook system targeted here is Claude Code's. Other CLIs (OpenCode,
# Kilo, Codex, Gemini, Pi) have different (or no) hook surfaces and these
# scripts will not run there.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TARGET="${HOME}/.claude/hooks"
HOOKS=(pre-completion.sh pre-tool-branch-guard.sh session-start-primer.sh user-prompt-resume-detect.sh)

MODE="install"
TARGET="$DEFAULT_TARGET"
SNIPPET_ONLY=0

if [[ $# -ge 1 && "$1" != --* ]]; then
  MODE="$1"; shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)        TARGET="$2"; shift 2 ;;
    --snippet-only)  SNIPPET_ONLY=1; shift ;;
    -h|--help)       sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  install|uninstall|status) ;;
  *) echo "unknown mode: $MODE (use install|uninstall|status)" >&2; exit 2 ;;
esac

print_snippet() {
  local snippet="${SCRIPT_DIR}/settings-snippet.json"
  if [[ ! -f "$snippet" ]]; then
    echo "settings-snippet.json missing at $snippet" >&2
    return 1
  fi
  # Substitute ${HOOKS_DIR} with the resolved absolute target.
  /usr/bin/sed "s|\${HOOKS_DIR}|${TARGET}|g" "$snippet"
}

case "$MODE" in
  status)
    echo "target: $TARGET"
    for h in "${HOOKS[@]}"; do
      if [[ -x "$TARGET/$h" ]]; then
        echo "  [installed] $h"
      else
        echo "  [missing]   $h"
      fi
    done
    ;;

  uninstall)
    if [[ ! -d "$TARGET" ]]; then
      echo "target not present: $TARGET"
      exit 0
    fi
    for h in "${HOOKS[@]}"; do
      if [[ -f "$TARGET/$h" ]]; then
        rm "$TARGET/$h"
        echo "removed: $TARGET/$h"
      fi
    done
    echo ""
    echo "Hook scripts removed. Remember to also remove the counter-patterns entries"
    echo "from your Claude Code settings.json (~/.claude/settings.json by default)."
    ;;

  install)
    if [[ "$SNIPPET_ONLY" -eq 0 ]]; then
      mkdir -p "$TARGET"
      for h in "${HOOKS[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$h" ]]; then
          echo "source missing: $SCRIPT_DIR/$h" >&2
          exit 1
        fi
        cp "$SCRIPT_DIR/$h" "$TARGET/$h"
        chmod +x "$TARGET/$h"
        echo "installed: $TARGET/$h"
      done
      echo ""
    fi

    echo "settings.json snippet (merge the 'hooks' block into your Claude Code settings.json):"
    echo "----------"
    print_snippet
    echo "----------"
    echo ""
    echo "If you already have hooks configured, merge per-event rather than overwriting."
    echo "On macOS, settings.json is at ~/.claude/settings.json (Claude Code)."
    ;;
esac
