#!/usr/bin/env bash
# PreToolUse hook — block Edit/Write/Bash-git-commit on protected branches.
# Returns exit code 2 with stderr message to deny the tool call.
# Returns exit code 0 to allow.

set -euo pipefail

# Stdin: JSON envelope. Fields: .tool_name, .tool_input
PAYLOAD=$(cat)
TOOL=$(echo "$PAYLOAD" | jq -r '.tool_name // ""')

# We only care about Edit, Write, NotebookEdit, and Bash with git commit/push
case "$TOOL" in
  Edit|Write|NotebookEdit) ;;
  Bash)
    CMD=$(echo "$PAYLOAD" | jq -r '.tool_input.command // ""')
    # Allow read-only git ops; block writes
    if ! echo "$CMD" | grep -qE '\bgit (commit|push|merge|reset --hard|rebase|cherry-pick)\b'; then
      exit 0
    fi
    ;;
  *) exit 0 ;;
esac

CWD=$(pwd)
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
case "$BRANCH" in
  main|master|develop|trunk|prod|production)
    cat >&2 <<EOF
DENIED by counter-patterns branch guard.

You are on protected branch '$BRANCH' and attempted: $TOOL.
CLAUDE.md says: NEVER commit or push new work directly to main. Stop and ask to branch first.

To proceed: ask the user, then create a feature branch:
  git stash && git checkout -b feature/<name> && git stash pop
EOF
    exit 2
    ;;
esac
exit 0
