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

# Antigravity (`agy`) inherits Gemini's agent engine (shared core per the
# official google-antigravity/antigravity-cli README), so the renderer reuses
# tools_for_gemini + gemini_escape_placeholders verbatim. Output must be
# byte-identical to gemini's so any regression there is caught here too.
out=$("$renderers/agy.sh" "$base")
grep -q '^name: branch-review$' <<<"$out" || fail "agy: missing name"
! grep -q '^model:' <<<"$out" || fail "agy: must not emit model (Claude aliases are invalid in Antigravity)"
grep -q '^tools:$' <<<"$out" || fail "agy: tools should be a block sequence (header on its own line)"
! grep -q '^tools: \[' <<<"$out" || fail "agy: tools must be mapped names, not the canonical [Bash, ...] list"
grep -q '^  - run_shell_command$' <<<"$out" || fail "agy: expected 'Bash' mapped to 'run_shell_command'"
grep -q '^## Step 1 — Gather' <<<"$out" || fail "agy: body missing"
diff <("$renderers/gemini.sh" "$base") <("$renderers/agy.sh" "$base") >/dev/null \
    || fail "agy: output must be byte-identical to gemini's (shared core agent engine)"

out=$("$renderers/codex.sh" "$base")
grep -q '^name = "branch-review"$' <<<"$out" || fail "codex: missing name"
# `model` is intentionally NOT emitted — Codex expects OpenAI model IDs, not
# our canonical Claude aliases; omitting it inherits the parent session model.
! grep -q '^model = ' <<<"$out" || fail "codex: must not emit model (Claude aliases are invalid Codex IDs)"
grep -q '^sandbox_mode = "read-only"$' <<<"$out" || fail "codex: missing sandbox_mode"
grep -qF "developer_instructions = '''" <<<"$out" || fail "codex: missing developer_instructions opener"
grep -q '^## Step 1 — Gather' <<<"$out" || fail "codex: body missing"
tail -n 1 <<<"$out" | grep -qF "'''" || fail "codex: missing developer_instructions closer"

# Gemini template-placeholder escape: deep-review's body and references
# legitimately contain literal `${VAR}` and `${X}` in markdown (documenting
# the shell-style interpolation failure mode the agent is supposed to look
# for). Gemini's agent loader treats any `${WORD}` in the rendered body as
# a required input and refuses to load the agent — there is no escape syntax.
# gemini_escape_placeholders inserts U+200B between `$` and `{` so the
# regex /\$\{(\w+)\}/g fails to match. Confirm:
#   1) The rendered body still contains a `${...}` pattern (so the docs
#      survive — the ZWSP only breaks the regex, not the visible text).
#   2) The regex Gemini actually applies matches zero placeholders.
out=$("$renderers/gemini.sh" "$renderers/../base/global-scope/deep-review")
# The placeholder text must still be present — only the `${` adjacency is
# broken by a ZWSP. We assert the var name + close brace survive (a strict
# "${VAR}" grep would falsely fail because of the inserted ZWSP).
grep -q 'VAR}' <<<"$out" || fail "gemini: deep-review body lost its \${VAR} documentation"
grep -q '{X}' <<<"$out" || fail "gemini: deep-review languages.md lost its \${X} example"
matches=$(printf '%s' "$out" | awk '
    BEGIN { count = 0 }
    {
        n = length($0); i = 1
        while (i <= n) {
            c = substr($0, i, 1)
            if (c == "$" && i + 1 <= n && substr($0, i + 1, 1) == "{") {
                j = i + 2; word_only = 1
                while (j <= n) {
                    ch = substr($0, j, 1)
                    if (ch == "}") break
                    if (ch !~ /[A-Za-z0-9_]/) { word_only = 0; break }
                    j++
                }
                if (word_only && j <= n && j > i + 2) {
                    count++
                    i = j + 1
                    continue
                }
            }
            i++
        }
    }
    END { print count }
')
[ "$matches" = 0 ] || fail "gemini: \${WORD} pattern still matchable in deep-review output (count=$matches) — Gemini will refuse to load"

# codex-agents-md: takes multiple bases, emits AGENTS.md
out=$("$renderers/codex-agents-md.sh" \
    "$renderers/../base/global-scope/branch-review" \
    "$renderers/../base/global-scope/bdd-audit")
grep -q '^# Installed Agents' <<<"$out" || fail "codex-agents-md: missing title"
grep -q '^## branch-review' <<<"$out" || fail "codex-agents-md: missing branch-review heading"
grep -q '^## bdd-audit' <<<"$out" || fail "codex-agents-md: missing bdd-audit heading"

echo "all renderer smoke tests pass"
