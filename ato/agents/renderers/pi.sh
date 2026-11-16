#!/usr/bin/env bash
# Render an agent for Pi (pi.dev).
#   Usage: pi.sh <agent-base-dir>
#   Emits the final <name>.md file to stdout.
#
# Pi core ships no subagent concept — the agents rendered here are consumed by
# the subagent extension vendored at pi/extension/ (adapted from Pi's own
# bundled examples/extensions/subagent/). That extension discovers agents from
# ~/.pi/agent/agents/*.md (user) and <repo>/.pi/agents/*.md (project) and runs
# each one as an isolated `pi` subprocess.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
. "$here/_lib.sh"

base="${1:?usage: pi.sh <agent-base-dir>}"
meta="$base/metadata.yaml"
body="$base/agent.md"

[ -f "$meta" ] || { echo "pi.sh: no metadata.yaml in $base" >&2; exit 1; }
[ -f "$body" ] || { echo "pi.sh: no agent.md in $base" >&2; exit 1; }

name=$(meta_top_unquoted "$meta" name)
description=$(meta_top "$meta" description)
tools=$(meta_top "$meta" tools)

# Both `name` and `description` are load-bearing, not decorative: the
# extension's loadAgentsFromDir() skips any file missing either one
# (`if (!frontmatter.name || !frontmatter.description) continue;`), so a
# malformed agent would silently not exist rather than fail loudly.
[ -n "$name" ] || { echo "pi.sh: metadata.yaml in $base has no name" >&2; exit 1; }
[ -n "$description" ] || { echo "pi.sh: metadata.yaml in $base has no description" >&2; exit 1; }

# Note: `model` is intentionally not emitted, for the same reason as agy.sh.
# Pi passes the frontmatter value straight to `pi --model <value>`, which wants
# a concrete provider model ID (e.g. `claude-haiku-4-5`), not the Claude-family
# aliases (opus/sonnet/haiku) our canonical metadata uses. Pi's default provider
# is Google, so a bare alias would not resolve. Omitting the field makes each
# subagent inherit whatever model the user configured for Pi — the right default.

{
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    # Pi wants a comma-separated string here, NOT a YAML list. See tools_for_pi.
    # Emitted only when non-empty: the loader treats an absent/blank `tools` as
    # "no allowlist", which means the subagent inherits Pi's default tool set.
    # An empty `tools:` line would otherwise render as a no-tools agent.
    tools_line=$(tools_for_pi "$tools")
    [ -n "$tools_line" ] && printf 'tools: %s\n' "$tools_line"
    printf -- '---\n\n'
}

# Flat form + inlined references, same as opencode/kilo/agy — but for a
# different underlying reason. Those CLIs recursively scan agents/ and would
# register each reference .md as a broken agent. Pi's discovery is the mirror
# image: loadAgentsFromDir() does a single non-recursive readdirSync() over
# *.md, so a bundled references/ subdirectory is simply never read and the
# agent would reference files that, from its perspective, do not exist.
cat "$body"
inline_references "$base"
