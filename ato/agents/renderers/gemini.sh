#!/usr/bin/env bash
# Render an agent for Gemini CLI.
#   Usage: gemini.sh <agent-base-dir>
#   Emits the final <name>.md file to stdout.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
. "$here/_lib.sh"

base="${1:?usage: gemini.sh <agent-base-dir>}"
meta="$base/metadata.yaml"
body="$base/agent.md"

[ -f "$meta" ] || { echo "gemini.sh: no metadata.yaml in $base" >&2; exit 1; }
[ -f "$body" ] || { echo "gemini.sh: no agent.md in $base" >&2; exit 1; }

name=$(meta_top_unquoted "$meta" name)
description=$(meta_top "$meta" description)
tools=$(meta_top "$meta" tools)

# Note: `model` is intentionally not emitted. Gemini's model field expects
# Gemini-family IDs (e.g. `gemini-3-flash-preview`) or the literal `inherit`;
# our canonical metadata uses Claude aliases (opus/sonnet/haiku) that aren't
# valid Gemini IDs. Omitting the field defaults to `inherit`, which is the
# right behavior — the user picks the model in their Gemini config.

# Gemini's agent loader validates each `tools:` entry against its built-in
# tool registry, so the canonical Claude names are mapped to Gemini's names
# and emitted as a YAML block sequence (see tools_for_gemini in _lib.sh).
{
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    printf 'tools:\n'
    tools_for_gemini "$tools"
    printf -- '---\n\n'
}
cat "$body"
inline_references "$base"
