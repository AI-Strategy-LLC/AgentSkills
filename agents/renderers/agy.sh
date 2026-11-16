#!/usr/bin/env bash
# Render an agent for Antigravity CLI (`agy`).
#   Usage: agy.sh <agent-base-dir>
#   Emits the final <name>.md file to stdout.
#
# Antigravity inherited the (now retired) Gemini CLI's agent loader, tool
# registry, and template validator. The helpers in _lib.sh
# (`tools_for_agy`, `agy_escape_placeholders`) encode those rules.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
. "$here/_lib.sh"

base="${1:?usage: agy.sh <agent-base-dir>}"
meta="$base/metadata.yaml"
body="$base/agent.md"

[ -f "$meta" ] || { echo "agy.sh: no metadata.yaml in $base" >&2; exit 1; }
[ -f "$body" ] || { echo "agy.sh: no agent.md in $base" >&2; exit 1; }

name=$(meta_top_unquoted "$meta" name)
description=$(meta_top "$meta" description)
tools=$(meta_top "$meta" tools)

# Note: `model` is intentionally not emitted. Antigravity's model field
# expects Gemini-family IDs (e.g. `gemini-3-flash-preview`)
# or the literal `inherit`; our canonical metadata uses Claude aliases
# (opus/sonnet/haiku) that aren't valid IDs in either CLI. Omitting the field
# defaults to `inherit`, which is the right behavior — the user picks the
# model in their Antigravity config.

# Antigravity's agent loader validates each `tools:`
# entry against its built-in tool registry, so the canonical Claude names are
# mapped to the registered names and emitted as a YAML block sequence (see
# tools_for_agy in _lib.sh).
{
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    printf 'tools:\n'
    tools_for_agy "$tools"
    printf -- '---\n\n'
}

# The body + inlined references are routed through agy_escape_placeholders
# so that literal `${WORD}` patterns in markdown documentation don't trip the
# template validator that Antigravity enforces. See _lib.sh for
# why and how. The frontmatter block above is emitted unfiltered — its values
# are author-provided metadata (name/description) that we never want rewritten.
{
    cat "$body"
    inline_references "$base"
} | agy_escape_placeholders
