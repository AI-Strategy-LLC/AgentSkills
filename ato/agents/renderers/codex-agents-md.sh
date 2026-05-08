#!/usr/bin/env bash
# Render a Codex AGENTS.md inventory for a set of installed agents.
#   Usage: codex-agents-md.sh <agent-base-dir> [<agent-base-dir> ...]
#   Emits an AGENTS.md document to stdout. Intended to be installed at
#   ~/.codex/AGENTS.md (global) or <repo>/AGENTS.md (per-repo).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
. "$here/_lib.sh"

if [ $# -lt 1 ]; then
    echo "usage: codex-agents-md.sh <agent-base-dir> [<agent-base-dir> ...]" >&2
    exit 1
fi

cat <<'EOF'
# Installed Agents

This inventory is managed by the AgentSkills installer. Each entry below
corresponds to a Codex subagent under `.codex/agents/` or `~/.codex/agents/`.
Invoke by name in a Codex session.

EOF

for base in "$@"; do
    meta="$base/metadata.yaml"
    [ -f "$meta" ] || continue
    name=$(meta_top_unquoted "$meta" name)
    description=$(meta_top_unquoted "$meta" description)
    printf '## %s\n\n%s\n\n' "$name" "$description"
done
