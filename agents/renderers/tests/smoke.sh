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

# Pi renders for the subagent extension (pi/install-subagent-extension.sh).
# Its loader reads `tools` as a comma-separated STRING and splits on "," —
# unlike every other CLI here, a YAML list would be silently mis-parsed.
out=$("$renderers/pi.sh" "$base")
grep -q '^name: branch-review$' <<<"$out" || fail "pi: missing name"
grep -q '^description: "' <<<"$out" || fail "pi: missing description"
# `model:` is intentionally NOT emitted — Pi passes it straight to
# `pi --model`, which needs a concrete provider ID, not a Claude alias.
! grep -q '^model:' <<<"$out" || fail "pi: must not emit model (Claude aliases are not resolvable Pi model IDs)"
grep -q '^tools: bash, read, write, grep, find$' <<<"$out" \
    || fail "pi: tools must be a comma-separated string of Pi tool names"
! grep -q '^tools: \[' <<<"$out" || fail "pi: tools must NOT be a YAML list — Pi splits the raw string on commas"
! grep -q '^tools:$' <<<"$out" || fail "pi: tools must be inline, not a block sequence"
grep -q '^## Step 1 — Gather' <<<"$out" || fail "pi: body missing"

# Tool-name mapping edge cases, checked on the two agents that exercise them:
#   deep-review declares Agent  -> must become `subagent` (the tool the
#     extension registers), otherwise its documented fan-out is silently dead.
#   ato-artifact-collector declares Skill -> must be DROPPED, not passed
#     through: Pi has no skill tool, and an unknown name in the allowlist
#     makes the spawned subagent subprocess fail outright.
out=$("$renderers/pi.sh" "$renderers/../base/global-scope/deep-review")
grep -q '^tools: .*subagent' <<<"$out" || fail "pi: deep-review's Agent must map to 'subagent'"
! grep -qi '^tools: .*glob' <<<"$out" || fail "pi: Glob must map to 'find', not pass through"
# References must be inlined: Pi's loadAgentsFromDir() is a single
# non-recursive readdirSync over *.md, so a references/ dir is never read.
grep -q '^## Bundled references (inlined)$' <<<"$out" || fail "pi: deep-review references not inlined"

ato_base="$renderers/../../../ato/agents/base/global-scope/ato-artifact-collector"
if [ -d "$ato_base" ]; then
    out=$("$renderers/pi.sh" "$ato_base" 2>/dev/null)
    ! grep -qi '^tools: .*skill' <<<"$out" || fail "pi: Skill must be dropped (no Pi equivalent)"
fi

# Pi's loader has NO try/catch around parseFrontmatter, so a single agent with
# invalid YAML throws and kills discovery for EVERY agent. Validate with Pi's
# own parser when Pi is installed; skip cleanly when it isn't (CI, other devs).
if command -v pi >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
    pi_real=$(readlink -f "$(command -v pi)" 2>/dev/null \
        || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$(command -v pi)")
    pi_fm="$(dirname "$(dirname "$pi_real")")/dist/utils/frontmatter.js"
    if [ -f "$pi_fm" ]; then
        pi_tmp=$(mktemp -d)
        trap 'rm -rf "$pi_tmp"' EXIT
        for d in "$renderers"/../base/global-scope/*/ "$renderers"/../../../ato/agents/base/global-scope/*/; do
            [ -f "$d/metadata.yaml" ] || continue
            n=$(basename "$d")
            "$renderers/pi.sh" "$d" > "$pi_tmp/$n.md" 2>/dev/null || fail "pi: renderer failed on $n"
        done
        PI_FM="file://$pi_fm" PI_TMP="$pi_tmp" node --input-type=module -e '
            const { parseFrontmatter } = await import(process.env.PI_FM);
            const fs = await import("node:fs");
            const dir = process.env.PI_TMP;
            let bad = 0;
            for (const f of fs.readdirSync(dir).filter(n => n.endsWith(".md"))) {
                try {
                    const { frontmatter } = parseFrontmatter(fs.readFileSync(`${dir}/${f}`, "utf-8"));
                    if (!frontmatter.name || !frontmatter.description) {
                        console.error(`  ${f}: loader would SKIP it (missing name/description)`); bad++;
                    }
                } catch (e) { console.error(`  ${f}: YAML throw — ${e.message}`); bad++; }
            }
            process.exit(bad ? 1 : 0);
        ' || fail "pi: rendered agents are not loadable by Pi's own frontmatter parser (see above)"
        rm -rf "$pi_tmp"
        trap - EXIT
        echo "  pi: validated rendered agents against Pi's own parser"
    fi
fi

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
