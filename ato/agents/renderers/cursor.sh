#!/usr/bin/env bash
# Render an agent for Cursor.
#   Usage: cursor.sh <agent-base-dir>
#   Emits the final <name>.mdc file to stdout; filename is authoritative.
#
# Cursor uses MDC (Markdown with metadata) files in `.cursor/rules/` for both
# project-scope and user-scope rule definitions. The frontmatter recognized
# by Cursor is described at https://docs.cursor.com/context/rules — the
# fields we emit are:
#   - description : the hook the harness uses to decide when to apply the rule
#   - alwaysApply : false (we want the model to pick the rule by description,
#                   not have it auto-injected on every request)
#
# Cursor's "agents" concept (delegated subagents) is still evolving and varies
# by version — the safest cross-version representation is to render every
# base agent as an MDC rule. The thin-stub skills will still trigger by
# description match; agents that delegate via Skill or Agent tools may need
# the user to adjust how they're invoked from inside Cursor.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
. "$here/_lib.sh"

base="${1:?usage: cursor.sh <agent-base-dir>}"
meta="$base/metadata.yaml"
body="$base/agent.md"

[ -f "$meta" ] || { echo "cursor.sh: no metadata.yaml in $base" >&2; exit 1; }
[ -f "$body" ] || { echo "cursor.sh: no agent.md in $base" >&2; exit 1; }

description=$(meta_top "$meta" description)

# Note: `model` and `tools` are intentionally not emitted. Cursor's model
# selection lives in the IDE's settings, not in rule files; tool usage is
# governed by the active Cursor mode (Agent/Ask/Edit/Composer), not declared
# per-rule. Subagents inherit whatever the user has configured globally.

cat <<EOF
---
description: $description
alwaysApply: false
---

EOF
cat "$body"
inline_references "$base"
