#!/usr/bin/env bash
# PreToolUse hook (CP-008) — block Edit/Write/Bash-git-write on protected branches.
# Returns exit code 2 with stderr message to deny the tool call.
# Returns exit code 0 to allow.
#
# Env vars (optional):
#   CP_PROTECTED_BRANCHES   Space-separated list of protected branch names.
#                           Default: "main master develop trunk prod production"

set -euo pipefail

PAYLOAD=$(cat)
TOOL=$(echo "$PAYLOAD" | jq -r '.tool_name // ""')

case "$TOOL" in
  Edit|Write|NotebookEdit) ;;
  Bash)
    CMD=$(echo "$PAYLOAD" | jq -r '.tool_input.command // ""')
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
PROTECTED="${CP_PROTECTED_BRANCHES:-main master develop trunk prod production}"

for p in $PROTECTED; do
  if [[ "$BRANCH" == "$p" ]]; then
    cat >&2 <<EOF
DENIED by counter-patterns branch guard (CP-008).

You are on protected branch '$BRANCH' and attempted: $TOOL.
Policy: never commit or push new work directly to a protected branch. Stop and ask the user to branch first.

To proceed: confirm with the user, then create a feature branch:
  git stash && git checkout -b feature/<name> && git stash pop

Configure protected branch names via the CP_PROTECTED_BRANCHES env var if needed.
EOF
    exit 2
  fi
done

exit 0
