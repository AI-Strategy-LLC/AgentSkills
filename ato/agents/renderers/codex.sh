#!/usr/bin/env bash
# Render an agent for OpenAI Codex CLI as a TOML subagent.
#   Usage: codex.sh <agent-base-dir>
#   Emits the final <name>.toml file to stdout.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
. "$here/_lib.sh"

base="${1:?usage: codex.sh <agent-base-dir>}"
meta="$base/metadata.yaml"
body="$base/agent.md"

[ -f "$meta" ] || { echo "codex.sh: no metadata.yaml in $base" >&2; exit 1; }
[ -f "$body" ] || { echo "codex.sh: no agent.md in $base" >&2; exit 1; }

name=$(meta_top_unquoted "$meta" name)
description=$(meta_top_unquoted "$meta" description)
sandbox_mode=$(meta_extras "$meta" codex sandbox_mode)
: "${sandbox_mode:=read-only}"

# Note: `model` is intentionally not emitted. Codex expects OpenAI model IDs
# (e.g. `gpt-5.4-mini`); our canonical metadata uses Claude aliases
# (opus/sonnet/haiku) that aren't valid Codex IDs. Codex docs confirm `model`
# is optional in subagent TOML — when omitted, the subagent inherits the
# parent session's model. The user picks the model in their Codex config.

# TOML literal multiline strings (''' … ''') do not process escapes, which
# is what we want for prompt bodies that contain regex like \(todo!\) or
# backslash-heavy shell snippets. The guard ensures the body itself never
# contains ''' (which would terminate the literal string prematurely).
if grep -qF "'''" "$body"; then
    echo "codex.sh: '$body' contains triple single-quote ('''), which TOML literal string cannot hold" >&2
    exit 1
fi

# Description goes into a TOML basic string: escape backslashes and raw
# double-quotes so the TOML parser accepts them.
esc_desc=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf 'name = "%s"\n' "$name"
printf 'description = "%s"\n' "$esc_desc"
printf 'sandbox_mode = "%s"\n' "$sandbox_mode"
printf "developer_instructions = '''\n"
cat "$body"
printf "\n'''\n"
