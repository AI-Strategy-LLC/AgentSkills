#!/usr/bin/env bash
# Smoke tests for every renderer. Runs each one against branch-review (the
# smallest agent) and checks a handful of invariants. Exits non-zero on any
# failure.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
renderers="$here/.."
base="$renderers/../base/global-scope/branch-review"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Every Markdown-frontmatter renderer should emit `description:` + the body's
# first "## Step 1" header.

out=$("$renderers/claude.sh" "$base")
grep -q '^name: branch-review$' <<<"$out" || fail "claude: missing name"
grep -q '^description: "' <<<"$out" || fail "claude: missing description"
grep -q '^tools: \[' <<<"$out" || fail "claude: missing tools"
grep -q '^model: sonnet$' <<<"$out" || fail "claude: missing model"
grep -q '^## Step 1 — Gather' <<<"$out" || fail "claude: body missing"

out=$("$renderers/opencode.sh" "$base")
! grep -q '^name:' <<<"$out" || fail "opencode: should not have name field"
grep -q '^description: "' <<<"$out" || fail "opencode: missing description"
grep -q '^mode: subagent$' <<<"$out" || fail "opencode: missing mode"
grep -q '^tools:$' <<<"$out" || fail "opencode: tools should be a record (header only on its own line)"
! grep -q '^tools: \[' <<<"$out" || fail "opencode: tools must NOT be a list — OpenCode rejects arrays"
grep -q '^  bash: true$' <<<"$out" || fail "opencode: expected 'bash: true' under tools"
grep -q '^## Step 1 — Gather' <<<"$out" || fail "opencode: body missing"

out=$("$renderers/kilo.sh" "$base")
! grep -q '^name:' <<<"$out" || fail "kilo: should not have name field"
grep -q '^mode: subagent$' <<<"$out" || fail "kilo: missing mode"
grep -q '^tools:$' <<<"$out" || fail "kilo: tools should be a record"
! grep -q '^tools: \[' <<<"$out" || fail "kilo: tools must NOT be a list"
grep -q '^  bash: true$' <<<"$out" || fail "kilo: expected 'bash: true' under tools"
grep -q '^## Step 1 — Gather' <<<"$out" || fail "kilo: body missing"

out=$("$renderers/gemini.sh" "$base")
grep -q '^name: branch-review$' <<<"$out" || fail "gemini: missing name"
# `model:` is intentionally NOT emitted — Gemini expects Gemini-family IDs,
# not our canonical Claude aliases; omitting it defaults to `inherit`.
! grep -q '^model:' <<<"$out" || fail "gemini: must not emit model (Claude aliases are invalid Gemini IDs)"
grep -q '^tools:$' <<<"$out" || fail "gemini: tools should be a block sequence (header on its own line)"
! grep -q '^tools: \[' <<<"$out" || fail "gemini: tools must be mapped names, not the canonical [Bash, ...] list"
grep -q '^  - run_shell_command$' <<<"$out" || fail "gemini: expected 'Bash' mapped to 'run_shell_command'"
grep -q '^## Step 1 — Gather' <<<"$out" || fail "gemini: body missing"

out=$("$renderers/codex.sh" "$base")
grep -q '^name = "branch-review"$' <<<"$out" || fail "codex: missing name"
# `model` is intentionally NOT emitted — Codex expects OpenAI model IDs, not
# our canonical Claude aliases; omitting it inherits the parent session model.
! grep -q '^model = ' <<<"$out" || fail "codex: must not emit model (Claude aliases are invalid Codex IDs)"
grep -q '^sandbox_mode = "read-only"$' <<<"$out" || fail "codex: missing sandbox_mode"
grep -qF "developer_instructions = '''" <<<"$out" || fail "codex: missing developer_instructions opener"
grep -q '^## Step 1 — Gather' <<<"$out" || fail "codex: body missing"
tail -n 1 <<<"$out" | grep -qF "'''" || fail "codex: missing developer_instructions closer"

# codex-agents-md: takes multiple bases, emits AGENTS.md
out=$("$renderers/codex-agents-md.sh" \
    "$renderers/../base/global-scope/branch-review" \
    "$renderers/../base/global-scope/bdd-audit")
grep -q '^# Installed Agents' <<<"$out" || fail "codex-agents-md: missing title"
grep -q '^## branch-review' <<<"$out" || fail "codex-agents-md: missing branch-review heading"
grep -q '^## bdd-audit' <<<"$out" || fail "codex-agents-md: missing bdd-audit heading"

echo "all renderer smoke tests pass"
