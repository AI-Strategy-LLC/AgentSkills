#!/usr/bin/env bash
# Render an agent for Kilo Code.
#   Usage: kilo.sh <agent-base-dir>
#   Emits the final agent file to stdout; filename is authoritative for Kilo,
#   so the installer must save as <name>.md.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
. "$here/_lib.sh"

base="${1:?usage: kilo.sh <agent-base-dir>}"
meta="$base/metadata.yaml"
body="$base/agent.md"

[ -f "$meta" ] || { echo "kilo.sh: no metadata.yaml in $base" >&2; exit 1; }
[ -f "$body" ] || { echo "kilo.sh: no agent.md in $base" >&2; exit 1; }

description=$(meta_top "$meta" description)
tools_list=$(meta_top "$meta" tools)
mode=$(meta_extras "$meta" kilo mode)
: "${mode:=subagent}"

# Note: `model` is intentionally not emitted. Kilo expects fully-qualified
# `provider/model-id` strings (e.g. `anthropic/claude-sonnet-4-20250514`); our
# canonical metadata uses bare aliases (opus/sonnet/haiku/inherit) that aren't
# valid Kilo IDs. Subagents inherit the invoker's model when `model:` is
# omitted — the user picks the model in their global Kilo config.

{
    printf -- '---\n'
    printf 'description: %s\n' "$description"
    printf 'mode: %s\n' "$mode"
    # Kilo uses the same record-form tools schema as OpenCode.
    printf 'tools:\n'
    tools_as_record "$tools_list"
    printf -- '---\n\n'
}
cat "$body"
inline_references "$base"
