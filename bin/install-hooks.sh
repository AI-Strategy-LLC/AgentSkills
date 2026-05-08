#!/usr/bin/env bash
# bin/install-hooks.sh — wire up the repo's git hooks for this clone.
#
# Sets core.hooksPath = .githooks so the .githooks/* scripts run as git
# hooks. Idempotent — re-running just reconfirms the setting.
#
# Why a per-clone opt-in (rather than .git/hooks/* directly)? Hooks under
# .git/hooks/ can't be committed and shared. .githooks/ is committed,
# version-controlled, and the same for everyone — but each clone has to
# point git at it once. CI runs the same checks regardless.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ ! -d .githooks ]; then
    echo "install-hooks.sh: .githooks/ not found; nothing to install." >&2
    exit 1
fi

current=$(git config --get core.hooksPath || echo "")
if [ "$current" = ".githooks" ]; then
    echo "install-hooks.sh: core.hooksPath already set to .githooks. Nothing to do."
    exit 0
fi

git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true

echo "install-hooks.sh: configured core.hooksPath=.githooks"
echo
echo "Active hooks:"
for h in .githooks/*; do
    [ -x "$h" ] && echo "  - $(basename "$h")"
done
echo
echo "Disable: git config --unset core.hooksPath"
