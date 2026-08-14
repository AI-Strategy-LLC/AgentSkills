#!/usr/bin/env bash
# Install Pi's bundled subagent extension into ~/.pi/agent/extensions/.
#
# WHY THIS EXISTS
# ---------------
# Pi core deliberately ships no subagent concept (`docs/usage.md`: "It
# intentionally does not include built-in MCP, sub-agents, permission popups,
# plan mode, to-dos, or background bash"). Without one, every thin-stub skill
# in this repo that delegates to an agent — deep-review, branch-review,
# bdd-audit, coverage-audit, ato-artifact-collector, ato-vulnerability-scanner
# — has nothing to delegate *to*.
#
# Pi does, however, ship a complete, working subagent implementation as a
# bundled example (`examples/extensions/subagent/`): isolated context per
# agent (each runs as its own `pi` subprocess), parallel fan-out, chaining,
# streaming output and cost tracking. It is first-party MIT code. This script
# copies it into place.
#
# WHY COPY AT INSTALL TIME RATHER THAN VENDOR A COPY IN THIS REPO
# ---------------------------------------------------------------
# The extension imports `@earendil-works/pi-coding-agent` and uses its internal
# API surface (ExtensionAPI, parseFrontmatter, getAgentDir, CONFIG_DIR_NAME).
# A copy vendored at one Pi version would silently rot against a later one.
# Copying from the user's own installed Pi guarantees the extension always
# matches the API of the Pi that will load it.
#
# WHY COPY RATHER THAN SYMLINK
# ----------------------------
# Pi's own README suggests symlinking. Don't: the source lives inside the
# package directory, so `brew upgrade`, `npm -g update` or `pi update self`
# replaces or removes it and leaves a dangling link. Re-run this script after
# upgrading Pi instead — it is idempotent.
#
# Usage:
#   bash pi/install-subagent-extension.sh [--dest <dir>] [--force] [--samples]
#
#   --dest <dir>  Install under <dir> instead of $HOME (for testing).
#   --force       Overwrite an existing install without prompting.
#   --samples     Also install Pi's sample agents (scout/planner/reviewer/
#                 worker) and its workflow prompt templates. Off by default:
#                 this repo renders its own agents into the same directory,
#                 and the workflow prompts (/implement, /scout-and-plan,
#                 /implement-and-review) reference the sample agents by name,
#                 so installing the prompts without the samples yields broken
#                 slash commands.
set -euo pipefail

DEST=""
FORCE=0
SAMPLES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dest)    DEST="${2:?--dest needs a directory}"; shift 2 ;;
        --force)   FORCE=1; shift ;;
        --samples) SAMPLES=1; shift ;;
        -h|--help) sed -n '35,47p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

die() { echo "error: $*" >&2; exit 1; }

# ---- locate the user's Pi installation ------------------------------------

command -v pi >/dev/null 2>&1 || die "\`pi\` is not on PATH. Install Pi first: https://pi.dev"

pi_bin=$(command -v pi)
# `readlink -f` is GNU/BSD-modern; fall back to python3 on older macOS.
if real=$(readlink -f "$pi_bin" 2>/dev/null); then :; else
    real=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$pi_bin") \
        || die "could not resolve the real path of $pi_bin"
fi

# .../<pkg-root>/dist/cli.js  ->  <pkg-root>
pkg_root=$(dirname "$(dirname "$real")")
[ -f "$pkg_root/package.json" ] || die "resolved Pi to '$real' but found no package.json at '$pkg_root'"

grep -q '"@earendil-works/pi-coding-agent"' "$pkg_root/package.json" \
    || die "'$pkg_root' does not look like @earendil-works/pi-coding-agent.
Note: the npm package '@mariozechner/pi' is an unrelated vLLM deployment CLI —
the coding agent is '@earendil-works/pi-coding-agent'."

pi_version=$(pi --version 2>/dev/null | head -1 || echo unknown)
src="$pkg_root/examples/extensions/subagent"

[ -d "$src" ] || die "Pi $pi_version does not ship examples/extensions/subagent at '$src'.
This script depends on that bundled example. Either your Pi predates it, or
this distribution channel strips examples/. Install a subagent extension
manually instead — see pi/README.md."

for f in index.ts agents.ts; do
    [ -f "$src/$f" ] || die "expected '$src/$f' but it is missing"
done

# ---- destination ----------------------------------------------------------

home="${DEST:-$HOME}"
ext_dir="$home/.pi/agent/extensions/subagent"

if [ -e "$ext_dir/index.ts" ] && [ "$FORCE" != 1 ]; then
    prev=$(sed -n 's/^\/\/ *pi-version: *//p' "$ext_dir/.provenance" 2>/dev/null | head -1)
    echo "A subagent extension is already installed at:"
    echo "  $ext_dir"
    [ -n "$prev" ] && echo "  (installed from Pi $prev; you now have Pi $pi_version)"
    printf 'Overwrite it? [y/N] '
    read -r reply </dev/tty || reply=n
    case "$reply" in [yY]*) ;; *) echo "Left unchanged."; exit 0 ;; esac
fi

mkdir -p "$ext_dir"
cp "$src/index.ts" "$src/agents.ts" "$ext_dir/"

# Provenance, so a later session can tell where this came from and whether it
# has drifted from the installed Pi.
cat > "$ext_dir/.provenance" <<EOF
// Copied by AgentSkills pi/install-subagent-extension.sh — do not edit in place.
// pi-version: $pi_version
// source: $src
// Re-run that script after upgrading Pi to refresh this copy.
EOF

# The agents directory the extension reads from. Our rendered agents land here
# via install.sh; create it now so the extension has somewhere to look even
# before the first agent is installed.
mkdir -p "$home/.pi/agent/agents"

if [ "$SAMPLES" = 1 ]; then
    mkdir -p "$home/.pi/agent/prompts"
    [ -d "$src/agents" ]  && cp "$src"/agents/*.md  "$home/.pi/agent/agents/"  2>/dev/null || true
    [ -d "$src/prompts" ] && cp "$src"/prompts/*.md "$home/.pi/agent/prompts/" 2>/dev/null || true
fi

echo "Installed Pi subagent extension:"
echo "  extension → $ext_dir  (from Pi $pi_version)"
echo "  agents    → $home/.pi/agent/agents/"
[ "$SAMPLES" = 1 ] && echo "  samples   → sample agents + workflow prompts installed"

cat <<'EOF'

The extension registers a tool named `subagent`. It discovers agents from
~/.pi/agent/agents/*.md — which is where `install.sh --for pi` writes the
agents rendered from this repo.

Note on project-local agents: the extension's `agentScope` defaults to "user",
so agents in a repo's <repo>/.pi/agents/ are NOT loaded unless the caller
passes agentScope: "both". That default is deliberate and we keep it — see
pi/README.md for why.

Verify with:
  pi -p 'Use the subagent tool with agent "branch-review" to summarize this repo'
EOF
