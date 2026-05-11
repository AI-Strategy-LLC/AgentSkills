#!/usr/bin/env bash
# install.sh — install AgentSkills' global-scope artifacts for one or more
# AI coding CLIs (Claude Code, OpenCode, Kilo Code, OpenAI Codex, Gemini CLI).
#
# Usage (one-liner — no clone required):
#   curl -fsSL https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/install.sh | bash -s -- --for claude
#
#   # Install for several CLIs at once:
#   curl -fsSL https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/install.sh | bash -s -- --for claude,opencode,kilo
#
#   # Pin a specific tag/branch/SHA:
#   curl -fsSL https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/install.sh | bash -s -- --for claude --ref v1.0.0
#
#   # Inspect before installing:
#   curl -fsSL https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/install.sh | bash -s -- --for claude --list
#
#   # Remove what this script previously installed (everything, or per-CLI):
#   curl -fsSL https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/install.sh | bash -s -- --uninstall
#   curl -fsSL https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/install.sh | bash -s -- --uninstall --for claude
#
# What it does:
#   1. Fetches the repo at the chosen ref (tarball via curl, or `git clone` fallback).
#   2. For each selected CLI, renders every agent under agents/base/global-scope/
#      through agents/renderers/<cli>.sh and writes the result into that CLI's
#      agents directory. Claude additionally gets skills/global-scope/*.
#      Codex additionally gets an AGENTS.md inventory.
#   3. Writes a single manifest tracking exactly what was installed per CLI.
#   4. Re-runs are idempotent: new/updated artifacts replace, removed-from-source
#      artifacts are pruned, user-authored artifacts are never touched.
#
# Opt-in extras (default off — preserves the "don't touch user files outside
# the CLI agent/skill dirs" invariant unless the user explicitly opts in):
#   --counter-patterns-block prepend|append   Insert a marker-delimited
#                                             counter-patterns block into the
#                                             user's CLAUDE.md. Reversible.
#   --counter-patterns-block-target <path>    Override CLAUDE.md target.
#                                             Default: ~/.claude/CLAUDE.md
#   --counter-patterns-hooks                  Install Claude Code hook scripts
#                                             that enforce the counter-patterns
#                                             rules at the moment of action.
#                                             Requires `claude` in --for.
#
# What it does NOT do:
#   - Install repo-scope artifacts (those land per-repo via the skill-sync skill).
#   - Modify shell configs or any user file outside the CLI agent/skill dirs
#     UNLESS the user opts in via one of the counter-patterns extras flags
#     above. Two narrower exceptions remain on by default: if --for is exactly
#     "kilo", the installer writes a defensive setting into Kilo's own config
#     to disable cross-scanning. See "Kilo defensive" below.
#   - Edit ~/.claude/settings.json. The counter-patterns hooks installer prints
#     a JSON snippet for the user to merge by hand — JSON-merge across
#     hand-authored settings is risky to automate.
#   - Store credentials. For that, run the auth-interview skill after install.

set -euo pipefail

# Re-exec under bash if invoked via `sh install.sh`.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo "install.sh: needs bash" >&2
    exit 1
fi

# ---- defaults -------------------------------------------------------------
REPO="${AGENT_SKILLS_REPO:-AI-Strategy-LLC/AgentSkills}"
REF="${AGENT_SKILLS_REF:-release}"
DEST="${AGENT_SKILLS_DEST:-}"                         # unset = each CLI uses its native root
FOR_LIST="${AGENT_SKILLS_FOR:-}"                      # CSV: claude,opencode,kilo,codex,gemini
FROM_LOCAL="${AGENT_SKILLS_FROM:-}"                   # local path to source tree (skips fetch)
ACTION="install"
ASSUME_YES=0
KEEP_CACHE=""

# Counter-patterns extras (opt-in). Set via flags or the interactive prompt.
CP_BLOCK_MODE=""                                       # "" | "prepend" | "append"
CP_BLOCK_TARGET=""                                     # default resolved to ~/.claude/CLAUDE.md
CP_HOOKS_INSTALL=0                                     # 0 | 1
CP_HOOKS_TARGET=""                                     # default resolved to ~/.claude/hooks
CP_EXPLICIT=0                                          # user passed at least one --counter-patterns-* flag

MANIFEST_NAME="installer-manifest.json"

SUPPORTED_CLIS="claude opencode kilo codex gemini pi cursor crush"

# ---- usage ----------------------------------------------------------------
usage() {
    cat <<EOF
AgentSkills installer

Usage:
  install.sh --for <cli>[,<cli>...] [options]

Required:
  --for <list>        Comma-separated list of CLIs. Any of:
                        claude     → ~/.claude/
                        opencode   → ~/.config/opencode/
                        kilo       → ~/.config/kilo/
                        codex      → ~/.codex/
                        gemini     → ~/.gemini/
                        pi         → ~/.pi/agent/   (skills only — Pi has no subagents)
                        cursor     → ~/.cursor/     (rules-as-MDC; see CLAUDE.md)
                        crush      → ~/.config/crush/ (skills only — Crush agents live in crush.json)
                      If omitted, a TTY prompt asks multi-select. In non-TTY
                      mode (e.g. pipe into sh -c) --for is required.

Options:
  --ref <ref>         Git ref to install (branch, tag, or SHA). Default: main
  --repo <owner/name> Source GitHub repo. Default: AlastairThomson/AgentSkills
  --dest <dir>        Override install root. When set, each CLI installs under
                      <dir>/<cli>/ (useful for sandboxed testing). When unset,
                      each CLI uses its native root.
  --list              Print what would be installed; do not write anything.
  --uninstall         Remove everything this script previously installed.
                      Combine with --for to restrict to specific CLIs.
  --from <dir>        Install from a local checkout instead of fetching. Used
                      for development and smoke tests.
  --keep-cache <dir>  After install, move the extracted source to <dir>.
  -y, --yes           Do not prompt; assume yes.
  -h, --help          This message.

Counter-patterns extras (opt-in; default off):
  --counter-patterns-block <mode>
                      Insert the counter-patterns block into a CLAUDE.md.
                      Mode is 'prepend' or 'append'. The block is marker-
                      delimited and reversible (via --uninstall or the
                      bundled install-claude-md-block.sh remove helper).
  --counter-patterns-block-target <path>
                      Override the CLAUDE.md target.
                      Default: ~/.claude/CLAUDE.md
  --counter-patterns-hooks
                      Install Claude Code hook scripts under ~/.claude/hooks/
                      and print a settings.json snippet to merge. Requires
                      'claude' in --for. The installer does NOT edit
                      settings.json automatically.

Environment variables:
  AGENT_SKILLS_REPO, AGENT_SKILLS_REF, AGENT_SKILLS_DEST, AGENT_SKILLS_FOR
EOF
}

# ---- args -----------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --ref) REF="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        --dest) DEST="$2"; shift 2 ;;
        --for) FOR_LIST="$2"; shift 2 ;;
        --from) FROM_LOCAL="$2"; shift 2 ;;
        --list) ACTION="list"; shift ;;
        --uninstall) ACTION="uninstall"; shift ;;
        --keep-cache) KEEP_CACHE="$2"; shift 2 ;;
        --counter-patterns-block)
            case "${2:-}" in
                prepend|append) CP_BLOCK_MODE="$2" ;;
                *) echo "--counter-patterns-block: mode must be 'prepend' or 'append', got '${2:-}'" >&2; exit 2 ;;
            esac
            CP_EXPLICIT=1
            shift 2 ;;
        --counter-patterns-block-target)
            CP_BLOCK_TARGET="$2"
            CP_EXPLICIT=1
            shift 2 ;;
        --counter-patterns-hooks)
            CP_HOOKS_INSTALL=1
            CP_EXPLICIT=1
            shift ;;
        -y|--yes) ASSUME_YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# ---- helpers --------------------------------------------------------------
die() { echo "install.sh: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

tty_read() {
    # Read a line from /dev/tty. Fails if no TTY is available.
    local tty="/dev/tty"
    [ -r "$tty" ] && [ -w "$tty" ] || return 1
    local ans=""
    read -r ans < "$tty" || ans=""
    printf '%s' "$ans"
}

confirm() {
    if [ "$ASSUME_YES" = "1" ]; then return 0; fi
    local tty="/dev/tty"
    if [ ! -r "$tty" ] || [ ! -w "$tty" ]; then
        echo "Non-interactive session; pass -y to confirm." >&2
        exit 3
    fi
    printf '%s [y/N] ' "$1" > "$tty"
    local ans; ans=$(tty_read) || ans=""
    case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ---- CLI target dirs ------------------------------------------------------
cli_root() {
    local cli="$1"
    if [ -n "$DEST" ]; then
        printf '%s/%s' "$DEST" "$cli"
        return
    fi
    case "$cli" in
        claude)   printf '%s/.claude' "$HOME" ;;
        opencode) printf '%s/opencode' "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
        kilo)     printf '%s/.config/kilo' "$HOME" ;;
        codex)    printf '%s/.codex' "$HOME" ;;
        gemini)   printf '%s/.gemini' "$HOME" ;;
        pi)       printf '%s/.pi/agent' "$HOME" ;;
        cursor)   printf '%s/.cursor' "$HOME" ;;
        crush)    printf '%s/crush' "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
        *) die "unknown CLI: $cli" ;;
    esac
}

# Some CLIs only consume skills — they have no subagent concept and so the
# installer should skip the agent rendering loop for them entirely. Pi
# (pi.dev) is the first such CLI: it's a "minimal terminal coding harness"
# whose only customization mechanism is skills (loaded from ~/.pi/agent/skills/
# and ~/.agents/skills/). It has no Agent tool, no subagent_type, no equivalent
# to ~/.claude/agents/.
cli_has_agents() {
    case "$1" in
        pi|crush) return 1 ;;
        *)        return 0 ;;
    esac
}

cli_agent_ext() {
    # Most CLIs use .md; Codex uses .toml; Cursor uses .mdc.
    case "$1" in
        codex)  printf 'toml' ;;
        cursor) printf 'mdc' ;;
        *)      printf 'md' ;;
    esac
}

# cli_skills_dir <cli>
# Where to physically install global skills for a given CLI. Four CLIs
# (opencode, kilo, gemini, codex) all auto-discover ~/.agents/skills/ as a
# cross-CLI compatibility location, so we install once into ~/.agents/skills/
# and let those CLIs pick it up. Claude is the only CLI that doesn't scan
# ~/.agents/, so it gets its own dir. Result: at most TWO physical copies
# on disk regardless of CLI selection — ~/.claude/skills/ and
# ~/.agents/skills/.
#
# Codex was originally installed into ~/.codex/skills/ (its canonical path).
# Empirically Codex also scans ~/.agents/skills/, so installing into both
# surfaces every skill twice in Codex's UI. The migration in prune_removed
# clears stale ~/.codex/skills/ content recorded under the old skills_root.
#
# Honours --dest by re-rooting under <DEST>/<bucket>.
cli_skills_dir() {
    local cli="$1" bucket
    case "$cli" in
        claude)                                 bucket=".claude/skills" ;;
        opencode|kilo|gemini|codex|pi|cursor)   bucket=".agents/skills" ;;
        # Crush scans $XDG_CONFIG_HOME/agents/skills (XDG-rooted) rather than
        # $HOME/.agents/skills (HOME-dot-prefixed) that the other CLIs use, so
        # it gets a distinct third dedup bucket. Source:
        # charmbracelet/crush internal/config/load.go GlobalSkillsDirs().
        crush)                                  bucket=".config/agents/skills" ;;
        *) die "unknown CLI: $cli" ;;
    esac
    if [ -n "$DEST" ]; then
        printf '%s/%s' "$DEST" "$bucket"
    else
        printf '%s/%s' "$HOME" "$bucket"
    fi
}

# ---- validate --for -------------------------------------------------------
normalize_for() {
    # Strip spaces, expand commas, dedupe, validate each.
    local raw="$1" out="" c
    raw=$(printf '%s' "$raw" | tr -d '[:space:]')
    local IFS=,
    for c in $raw; do
        [ -z "$c" ] && continue
        case " $SUPPORTED_CLIS " in
            *" $c "*) ;;
            *) die "--for: '$c' is not a supported CLI (expected one of: $SUPPORTED_CLIS)" ;;
        esac
        case " $out " in *" $c "*) ;; *) out="${out:+$out }$c" ;; esac
    done
    printf '%s' "$out"
}

prompt_for_clis() {
    # Multi-select via /dev/tty. Returns space-separated CLIs.
    local tty="/dev/tty"
    [ -r "$tty" ] && [ -w "$tty" ] || return 1
    {
        echo
        echo "Which CLIs should I install for?"
        echo "  1) claude    → ~/.claude/"
        echo "  2) opencode  → ~/.config/opencode/"
        echo "  3) kilo      → ~/.config/kilo/"
        echo "  4) codex     → ~/.codex/"
        echo "  5) gemini    → ~/.gemini/"
        echo "  6) pi        → ~/.pi/agent/    (skills only)"
        echo "  7) cursor    → ~/.cursor/      (rules-as-MDC)"
        echo "  8) crush     → ~/.config/crush/ (skills only)"
        printf 'Enter comma-separated numbers or names (e.g. "1,2" or "claude,opencode"): '
    } > "$tty"
    local ans; ans=$(tty_read) || return 1
    ans=$(printf '%s' "$ans" | tr -d '[:space:]')
    [ -z "$ans" ] && return 1
    # Map digits → names
    local mapped="" t
    local IFS=,
    for t in $ans; do
        case "$t" in
            1) mapped="${mapped:+$mapped,}claude" ;;
            2) mapped="${mapped:+$mapped,}opencode" ;;
            3) mapped="${mapped:+$mapped,}kilo" ;;
            4) mapped="${mapped:+$mapped,}codex" ;;
            5) mapped="${mapped:+$mapped,}gemini" ;;
            6) mapped="${mapped:+$mapped,}pi" ;;
            7) mapped="${mapped:+$mapped,}cursor" ;;
            8) mapped="${mapped:+$mapped,}crush" ;;
            claude|opencode|kilo|codex|gemini|pi|cursor|crush) mapped="${mapped:+$mapped,}$t" ;;
            *) echo "ignored: $t" > "$tty" ;;
        esac
    done
    printf '%s' "$mapped"
}

resolve_clis() {
    if [ -n "$FOR_LIST" ]; then
        normalize_for "$FOR_LIST"
        return
    fi
    # No --for supplied: try the TTY prompt.
    local picked
    if picked=$(prompt_for_clis) && [ -n "$picked" ]; then
        normalize_for "$picked"
        return
    fi
    die "--for is required (no TTY available to prompt). Try: --for claude"
}

# ---- detect fetcher -------------------------------------------------------
FETCHER=""
if   have curl; then FETCHER="curl"
elif have wget; then FETCHER="wget"
else die "need curl or wget"
fi
have tar || die "need tar"

# ---- stage dir ------------------------------------------------------------
STAGE="$(mktemp -d -t agent-skills.XXXXXX)"
cleanup() {
    if [ -n "$KEEP_CACHE" ] && [ -d "$STAGE/src" ]; then
        mkdir -p "$(dirname "$KEEP_CACHE")"
        rm -rf "$KEEP_CACHE"
        mv "$STAGE/src" "$KEEP_CACHE"
        echo "Source preserved at: $KEEP_CACHE"
    fi
    rm -rf "$STAGE"
}
trap cleanup EXIT

# ---- manifest location ----------------------------------------------------
# Manifest travels with the install: under --dest when set, else in a
# conventional home-rooted directory.
manifest_path() {
    if [ -n "$DEST" ]; then
        printf '%s/%s' "$DEST" "$MANIFEST_NAME"
    else
        printf '%s/.agent-skills/%s' "$HOME" "$MANIFEST_NAME"
    fi
}

# ---- fetch ----------------------------------------------------------------
fetch_tarball() {
    local url="https://codeload.github.com/$REPO/tar.gz/$REF"
    local out="$STAGE/src.tar.gz"
    case "$FETCHER" in
        curl) curl -fsSL "$url" -o "$out" || die "failed to download $url" ;;
        wget) wget -q "$url" -O "$out" || die "failed to download $url" ;;
    esac
    mkdir -p "$STAGE/src"
    tar -xzf "$out" -C "$STAGE/src" --strip-components=1
}

fetch_git() {
    have git || die "need git (or curl/wget) to fetch repo"
    git clone --depth 1 --branch "$REF" "https://github.com/$REPO.git" "$STAGE/src" 2>/dev/null \
        || (git clone "https://github.com/$REPO.git" "$STAGE/src" && (cd "$STAGE/src" && git checkout "$REF"))
}

fetch_local() {
    [ -d "$FROM_LOCAL" ] || die "--from: '$FROM_LOCAL' is not a directory"
    [ -d "$FROM_LOCAL/skills/global-scope" ] || die "--from: '$FROM_LOCAL' missing skills/global-scope"
    [ -d "$FROM_LOCAL/agents/base/global-scope" ] || die "--from: '$FROM_LOCAL' missing agents/base/global-scope"
    mkdir -p "$STAGE/src"
    cp -R "$FROM_LOCAL/skills" "$FROM_LOCAL/agents" "$STAGE/src/"
    # Copy the ato/ subtree too if the parent has one (so merge_ato_into_src
    # below can fold its content into the unified install set).
    if [ -d "$FROM_LOCAL/ato" ]; then
        cp -R "$FROM_LOCAL/ato" "$STAGE/src/"
    fi
}

fetch_source() {
    if [ -n "$FROM_LOCAL" ]; then
        fetch_local
    else
        fetch_tarball || { echo "tarball fetch failed, falling back to git clone"; fetch_git; }
    fi
    merge_ato_into_src
}

# After fetch_source pulls the repo into $STAGE/src, fold ato/skills/global-scope/*
# and ato/agents/base/global-scope/* into the unified install set so the rest
# of this installer naturally walks both subtrees. Names already present in
# the canonical tree win — but today only the renderers have a canonical
# home outside ato/, and renderers aren't installed as skills/agents anyway.
# Everything else (ATO skills, ATO agents, auth-config, auth-interview)
# lives only under ato/, so the dedup is just defensive against future
# accidental duplication.
#
# Net effect: `bash install.sh --for <cli>` installs everything (generic +
# ATO). `bash ato/install.sh --for <cli>` installs only the ATO subset.
merge_ato_into_src() {
    local src="$STAGE/src"
    [ -d "$src/ato" ] || return 0

    if [ -d "$src/ato/skills/global-scope" ]; then
        mkdir -p "$src/skills/global-scope"
        for d in "$src/ato/skills/global-scope"/*/; do
            [ -d "$d" ] || continue
            local n; n=$(basename "$d")
            [ -e "$src/skills/global-scope/$n" ] && continue
            cp -R "$d" "$src/skills/global-scope/$n"
        done
    fi

    if [ -d "$src/ato/agents/base/global-scope" ]; then
        mkdir -p "$src/agents/base/global-scope"
        for d in "$src/ato/agents/base/global-scope"/*/; do
            [ -d "$d" ] || continue
            local n; n=$(basename "$d")
            [ -e "$src/agents/base/global-scope/$n" ] && continue
            cp -R "$d" "$src/agents/base/global-scope/$n"
        done
    fi
}

# ---- agent shape helpers --------------------------------------------------
# A base agent is "directory form" if it bundles references/, evals/, or config.yaml.
agent_is_dir_form() {
    local d="$1"
    [ -d "$d/references" ] || [ -d "$d/evals" ] || [ -f "$d/config.yaml" ]
}

# Some CLIs recursively scan their agents/ directory and register every .md
# file (including bundled references/*.md) as a separate, broken, namespaced
# agent. To avoid that, we install agents flat for those CLIs regardless of
# whether the base bundles references — the renderer inlines the references
# into the agent body instead. Codex (.toml) and Claude don't have this
# problem.
cli_uses_flat_only() {
    case "$1" in
        opencode|kilo|gemini|cursor) return 0 ;;
        *) return 1 ;;
    esac
}

# Copy every sibling file/dir (references, evals, config.yaml) alongside the
# rendered agent. Does NOT copy metadata.yaml or agent.md — those live only
# in the base tree.
copy_agent_bundled() {
    local base="$1" target_dir="$2"
    [ -d "$base/references" ] && cp -R "$base/references" "$target_dir/"
    [ -d "$base/evals" ]      && cp -R "$base/evals"      "$target_dir/"
    [ -f "$base/config.yaml" ] && cp "$base/config.yaml" "$target_dir/"
    return 0
}

# ---- list / install -------------------------------------------------------
list_install_set() {
    local src_skills="$STAGE/src/skills/global-scope"
    local src_agents="$STAGE/src/agents/base/global-scope"

    [ -d "$src_skills" ] || die "source tarball has no skills/global-scope/ — wrong repo or ref?"
    [ -d "$src_agents" ] || die "source tarball has no agents/base/global-scope/ — wrong repo or ref?"

    echo "Selected CLIs: $CLIS"
    for cli in $CLIS; do
        local root; root=$(cli_root "$cli")
        local sdir; sdir=$(cli_skills_dir "$cli")
        echo
        echo "--- $cli → $root ---"
        echo "  skills → $sdir"
        for d in "$src_skills"/*/; do [ -d "$d" ] && echo "    $(basename "$d")"; done
        if ! cli_has_agents "$cli"; then
            echo "  (no agents — $cli only consumes skills)"
            continue
        fi
        echo "  agents/:"
        for d in "$src_agents"/*/; do
            [ -d "$d" ] || continue
            local name ext; name=$(basename "$d"); ext=$(cli_agent_ext "$cli")
            if agent_is_dir_form "$d" && ! cli_uses_flat_only "$cli"; then
                echo "    $name/   (bundles refs)"
                echo "      $name.$ext (rendered)"
            elif agent_is_dir_form "$d"; then
                echo "    $name.$ext   (refs inlined)"
            else
                echo "    $name.$ext"
            fi
        done
        if [ "$cli" = codex ]; then
            echo "  AGENTS.md   (installed-agent inventory)"
        fi
    done

    # Note: opencode/kilo/gemini share ~/.agents/skills/ — listed per CLI
    # above for clarity, but install.sh writes that directory only once.

    if [ -n "$CP_BLOCK_MODE" ] || [ "$CP_HOOKS_INSTALL" = 1 ]; then
        echo
        echo "--- counter-patterns extras ---"
        if [ -n "$CP_BLOCK_MODE" ]; then
            echo "  CLAUDE.md block ($CP_BLOCK_MODE) → ${CP_BLOCK_TARGET:-$(cp_default_block_target)}"
        fi
        if [ "$CP_HOOKS_INSTALL" = 1 ]; then
            echo "  hooks → ${CP_HOOKS_TARGET:-$(cp_default_hooks_target)}"
        fi
    fi
}

# ---- install one CLI ------------------------------------------------------
install_cli() {
    local cli="$1"

    # CLIs without subagents (e.g. pi) only need their skills directory
    # populated, which is handled by install_skills_dedup() in the main loop.
    # Nothing to render or write under <cli-root>/agents/.
    if ! cli_has_agents "$cli"; then
        return 0
    fi

    local src_agents="$STAGE/src/agents/base/global-scope"
    local renderer="$STAGE/src/agents/renderers/$cli.sh"
    local codex_agents_md="$STAGE/src/agents/renderers/codex-agents-md.sh"
    local root; root=$(cli_root "$cli")
    local ext; ext=$(cli_agent_ext "$cli")

    [ -x "$renderer" ] || die "missing or non-executable renderer: $renderer"

    mkdir -p "$root/agents"

    # Note: skills are installed by install_skills_dedup() in the main loop,
    # not here. Each CLI's skills directory is computed by cli_skills_dir,
    # and opencode/kilo/gemini share ~/.agents/skills/ — installing per-CLI
    # would write that directory three times. The dedup helper writes each
    # unique skills directory exactly once.

    # agents: render every base agent through this CLI's renderer.
    local bases=()
    for d in "$src_agents"/*/; do
        [ -d "$d" ] || continue
        local name; name=$(basename "$d")
        bases+=("$d")

        if agent_is_dir_form "$d" && ! cli_uses_flat_only "$cli"; then
            # Directory form: write the rendered file inside <cli-root>/agents/<name>/<name>.<ext>
            local target_dir="$root/agents/$name"
            rm -rf "$target_dir"
            rm -f "$root/agents/$name.$ext"
            mkdir -p "$target_dir"
            "$renderer" "$d" > "$target_dir/$name.$ext"
            copy_agent_bundled "$d" "$target_dir"
        else
            # Flat form: single file at <cli-root>/agents/<name>.<ext>.
            # The rm -rf cleans up any residual directory-form layout from a
            # previous install (important after switching opencode/kilo/gemini
            # away from directory form).
            rm -rf "$root/agents/$name"
            "$renderer" "$d" > "$root/agents/$name.$ext"
        fi
    done

    # Codex extra: AGENTS.md at the cli root (not under agents/).
    if [ "$cli" = codex ]; then
        "$codex_agents_md" "${bases[@]}" > "$root/AGENTS.md"
    fi
}

# ---- install skills (deduped across CLIs) ---------------------------------
# Walk $CLIS, build the set of unique skills directories (opencode/kilo/gemini
# all map to ~/.agents/skills/), and write each one exactly once. Echoes the
# unique directories to stdout, one per line, so the caller can log them.
install_skills_dedup() {
    local src_skills="$STAGE/src/skills/global-scope"
    [ -d "$src_skills" ] || return 0

    local seen=" "
    for cli in $CLIS; do
        local sdir; sdir=$(cli_skills_dir "$cli")
        case "$seen" in *" $sdir "*) continue ;; esac
        seen="$seen$sdir "

        mkdir -p "$sdir"
        for d in "$src_skills"/*/; do
            [ -d "$d" ] || continue
            local n; n=$(basename "$d")
            rm -rf "$sdir/$n"
            cp -R "$d" "$sdir/$n"
        done
        printf '%s\n' "$sdir"
    done
}

# ---- Kilo defensive -------------------------------------------------------
# Only when --for is *exactly* ["kilo"] do we touch Kilo's settings to prevent
# it picking up .claude/.opencode/.agents directories owned by other tools.
# The exact Kilo settings key / file path is a moving target; we check the
# known locations, and if none exist we just print a notice instead of
# inventing a file.
kilo_defensive_setup() {
    [ "$CLIS" = "kilo" ] || return 0

    local kilo_root; kilo_root=$(cli_root kilo)
    local kilo_cfg="$kilo_root/settings.json"
    local kilo_cfg_alt="$kilo_root/kilo.jsonc"

    echo
    if [ -f "$kilo_cfg" ] || [ -f "$kilo_cfg_alt" ]; then
        echo "Kilo cross-scan note:"
        echo "  You installed for Kilo only. Kilo by default scans .claude/ and"
        echo "  .opencode/ directories for agents. To isolate Kilo, add this to"
        echo "  your Kilo settings file (key name may vary by Kilo version):"
        echo
        echo "    { \"agent_scan_paths\": [\"\$HOME/.config/kilo/agents\"] }"
        echo
        echo "  Settings file: ${kilo_cfg:-$kilo_cfg_alt}"
    else
        echo "Kilo cross-scan note:"
        echo "  You installed for Kilo only, but no Kilo settings file was found at"
        echo "  $kilo_cfg or $kilo_cfg_alt. If Kilo picks up stale agents from"
        echo "  .claude/ or .opencode/, create a settings file with a restricted"
        echo "  agent_scan_paths list (key name varies by Kilo version — check"
        echo "  'kilo --help settings' or the current Kilo docs)."
    fi
}

# ---- manifest I/O ---------------------------------------------------------
write_manifest() {
    local resolved_sha="$1"
    local src_skills="$STAGE/src/skills/global-scope"
    local src_agents="$STAGE/src/agents/base/global-scope"
    local mpath; mpath=$(manifest_path)
    mkdir -p "$(dirname "$mpath")"

    # Build per-CLI JSON blocks.
    local blocks=""
    local cli_idx=0
    local cli_count=0
    for cli in $CLIS; do cli_count=$((cli_count+1)); done

    for cli in $CLIS; do
        cli_idx=$((cli_idx+1))
        local skills_json="" flat_json="" dir_json=""

        # Skills are now installed for every CLI (same set, possibly into
        # a shared physical path — see cli_skills_dir).
        for d in "$src_skills"/*/; do
            [ -d "$d" ] || continue
            local n; n=$(basename "$d")
            skills_json="${skills_json}      \"$(json_escape "$n")\",\n"
        done

        # Skills-only CLIs (e.g. pi) have no agents — leave both arrays empty.
        if cli_has_agents "$cli"; then
            for d in "$src_agents"/*/; do
                [ -d "$d" ] || continue
                local n; n=$(basename "$d")
                if agent_is_dir_form "$d" && ! cli_uses_flat_only "$cli"; then
                    dir_json="${dir_json}      \"$(json_escape "$n")\",\n"
                else
                    flat_json="${flat_json}      \"$(json_escape "$n")\",\n"
                fi
            done
        fi

        skills_json=$(printf '%b' "$skills_json" | sed '$s/,$//')
        flat_json=$(printf '%b' "$flat_json" | sed '$s/,$//')
        dir_json=$(printf '%b' "$dir_json" | sed '$s/,$//')

        local trailing_comma=","
        [ "$cli_idx" = "$cli_count" ] && trailing_comma=""

        blocks="$blocks    \"$cli\": {\n"
        blocks="$blocks      \"root\": \"$(json_escape "$(cli_root "$cli")")\",\n"
        blocks="$blocks      \"skills_root\": \"$(json_escape "$(cli_skills_dir "$cli")")\",\n"
        blocks="$blocks      \"skills\": [\n$skills_json\n      ],\n"
        blocks="$blocks      \"agents_flat\": [\n$flat_json\n      ],\n"
        blocks="$blocks      \"agents_dir\": [\n$dir_json\n      ]\n"
        blocks="$blocks    }$trailing_comma\n"
    done

    # Counter-patterns extras block. Omit groups that aren't installed so
    # uninstall can use presence-of-target as the "should remove" signal.
    local extras_block=""
    if [ "$CP_BLOCK_INSTALLED" = 1 ] || [ "$CP_HOOKS_INSTALLED" = 1 ]; then
        extras_block="  \"extras\": {\n"
        if [ "$CP_BLOCK_INSTALLED" = 1 ]; then
            extras_block="$extras_block    \"counter_patterns_block\": {\n"
            extras_block="$extras_block      \"target\": \"$(json_escape "$CP_BLOCK_INSTALLED_TARGET")\",\n"
            extras_block="$extras_block      \"mode\": \"$(json_escape "$CP_BLOCK_INSTALLED_MODE")\"\n"
            if [ "$CP_HOOKS_INSTALLED" = 1 ]; then
                extras_block="$extras_block    },\n"
            else
                extras_block="$extras_block    }\n"
            fi
        fi
        if [ "$CP_HOOKS_INSTALLED" = 1 ]; then
            extras_block="$extras_block    \"counter_patterns_hooks\": {\n"
            extras_block="$extras_block      \"hooks_dir\": \"$(json_escape "$CP_HOOKS_INSTALLED_DIR")\",\n"
            extras_block="$extras_block      \"scripts\": [\n"
            extras_block="$extras_block        \"pre-completion.sh\",\n"
            extras_block="$extras_block        \"pre-tool-branch-guard.sh\",\n"
            extras_block="$extras_block        \"session-start-primer.sh\",\n"
            extras_block="$extras_block        \"user-prompt-resume-detect.sh\"\n"
            extras_block="$extras_block      ]\n"
            extras_block="$extras_block    }\n"
        fi
        extras_block="$extras_block  },\n"
    fi

    {
        printf '{\n'
        printf '  "version": 4,\n'
        printf '  "source": {\n'
        printf '    "repo": "%s",\n' "$(json_escape "$REPO")"
        printf '    "ref": "%s",\n' "$(json_escape "$REF")"
        printf '    "resolved_sha": "%s"\n' "$(json_escape "$resolved_sha")"
        printf '  },\n'
        printf '  "installed_at": "%s",\n' "$(iso_now)"
        printf '  "installer_version": 4,\n'
        printf '  "clis": ['
        local first=1
        for cli in $CLIS; do
            if [ "$first" = 1 ]; then first=0; else printf ','; fi
            printf '"%s"' "$cli"
        done
        printf '],\n'
        printf '%b' "$extras_block"
        printf '  "installed": {\n'
        printf '%b' "$blocks"
        printf '  }\n'
        printf '}\n'
    } > "$mpath"
    chmod 0644 "$mpath"
}

# Extract a list (skills | agents_flat | agents_dir) for a given cli from the
# existing manifest. Tolerant to formatting changes.
manifest_list() {
    local mpath="$1" cli="$2" key="$3"
    awk -v cli="$cli" -v key="$key" '
        $0 ~ "\""cli"\":[[:space:]]*{" { in_cli=1 }
        in_cli && $0 ~ "\""key"\":[[:space:]]*\\[" { in_arr=1; next }
        in_arr && /\]/ { in_arr=0 }
        in_arr { gsub(/[",]/,""); gsub(/^[[:space:]]+/,""); if($0) print }
        in_cli && /^    }/ { in_cli=0 }
    ' "$mpath"
}

# Extract a scalar value (e.g. "skills_root") for a given cli from the
# existing manifest. Empty string if absent (manifest pre-v3 won't have it).
manifest_scalar() {
    local mpath="$1" cli="$2" key="$3"
    awk -v cli="$cli" -v key="$key" '
        $0 ~ "\""cli"\":[[:space:]]*{" { in_cli=1; next }
        in_cli && $0 ~ "\""key"\":" {
            sub(".*\""key"\":[[:space:]]*\"", "")
            sub("\".*", "")
            print
            exit
        }
        in_cli && /^    }/ { in_cli=0 }
    ' "$mpath"
}

prune_removed() {
    # For each CLI we just installed, compare the old manifest's per-CLI list
    # to what we just installed. Remove anything that was in the old list but
    # is no longer in the source tree.
    #
    # Skills can share a physical directory across CLIs (~/.agents/skills/),
    # so we dedup the prune set by path — pruning the same skill twice is
    # idempotent but pruning a skill another CLI still uses would be a bug.
    # Since prune only removes skills that are gone from source entirely,
    # all CLIs lose them at once, so per-path dedup is just an efficiency
    # win, not a correctness one.
    local mpath; mpath=$(manifest_path)
    [ -f "$mpath.old" ] || return 0

    local src_skills="$STAGE/src/skills/global-scope"
    local src_agents="$STAGE/src/agents/base/global-scope"

    local skill_paths_seen=" "
    for cli in $CLIS; do
        local root; root=$(cli_root "$cli")
        local sdir; sdir=$(cli_skills_dir "$cli")
        local ext; ext=$(cli_agent_ext "$cli")
        local old_sdir; old_sdir=$(manifest_scalar "$mpath.old" "$cli" skills_root)

        # If the old manifest recorded a different skills_root for this CLI,
        # the previous install put skills somewhere we no longer use. Remove
        # every skill the old manifest recorded for this CLI from that old
        # path — the user still has them in the new location, so this is
        # purely a cleanup. (Empty old_sdir means a pre-v3 manifest with no
        # skills_root recorded; nothing to migrate.)
        if [ -n "$old_sdir" ] && [ "$old_sdir" != "$sdir" ]; then
            local old_skills_at_old_path; old_skills_at_old_path=$(manifest_list "$mpath.old" "$cli" skills)
            for n in $old_skills_at_old_path; do
                rm -rf "$old_sdir/$n"
            done
            # Remove the directory itself if it's now empty.
            rmdir "$old_sdir" 2>/dev/null || true
        fi

        case "$skill_paths_seen" in
            *" $sdir "*) ;;
            *)
                skill_paths_seen="$skill_paths_seen$sdir "
                local old_skills; old_skills=$(manifest_list "$mpath.old" "$cli" skills)
                for n in $old_skills; do
                    [ -d "$src_skills/$n" ] || rm -rf "$sdir/$n"
                done
                ;;
        esac

        local old_flat old_dir
        old_flat=$(manifest_list "$mpath.old" "$cli" agents_flat)
        old_dir=$(manifest_list "$mpath.old" "$cli" agents_dir)
        for n in $old_flat; do
            if [ ! -d "$src_agents/$n" ]; then rm -f "$root/agents/$n.$ext"; fi
        done
        for n in $old_dir; do
            if [ ! -d "$src_agents/$n" ]; then rm -rf "$root/agents/$n"; fi
        done
    done
}

# ---- uninstall ------------------------------------------------------------
uninstall() {
    local mpath; mpath=$(manifest_path)
    [ -f "$mpath" ] || { echo "No manifest at $mpath — nothing to uninstall."; return 0; }

    # If --for not supplied, uninstall everything recorded in the manifest.
    local target_clis="$CLIS"
    if [ -z "$FOR_LIST" ]; then
        target_clis=$(awk '/"clis":/ { sub(".*\\[",""); sub("\\].*",""); gsub(/[",]/," "); print; exit }' "$mpath")
    fi

    echo "This will remove artifacts for: $target_clis"
    echo "  manifest: $mpath"
    confirm "Proceed?" || { echo "aborted"; exit 1; }

    # Compute which CLIs from the manifest will remain after this uninstall.
    # A shared skills_dir (e.g. ~/.agents/skills/) is only safe to remove if
    # NO remaining CLI still maps to it.
    local all_clis_in_manifest
    all_clis_in_manifest=$(awk '/"clis":/ { sub(".*\\[",""); sub("\\].*",""); gsub(/[",]/," "); print; exit }' "$mpath")
    local remaining_clis=""
    for c in $all_clis_in_manifest; do
        case " $target_clis " in
            *" $c "*) ;;
            *) remaining_clis="${remaining_clis:+$remaining_clis }$c" ;;
        esac
    done

    local skill_paths_processed=" "
    for cli in $target_clis; do
        local root; root=$(cli_root "$cli")
        local sdir; sdir=$(cli_skills_dir "$cli")
        local ext; ext=$(cli_agent_ext "$cli")

        # Skills: only remove if no remaining CLI shares this physical path.
        case "$skill_paths_processed" in
            *" $sdir "*) ;;
            *)
                skill_paths_processed="$skill_paths_processed$sdir "
                local sdir_still_used=0
                for rc in $remaining_clis; do
                    [ "$(cli_skills_dir "$rc")" = "$sdir" ] && { sdir_still_used=1; break; }
                done
                if [ "$sdir_still_used" = 0 ]; then
                    for n in $(manifest_list "$mpath" "$cli" skills); do rm -rf "$sdir/$n"; done
                fi
                ;;
        esac

        for n in $(manifest_list "$mpath" "$cli" agents_flat); do rm -f "$root/agents/$n.$ext"; done
        for n in $(manifest_list "$mpath" "$cli" agents_dir);  do rm -rf "$root/agents/$n"; done
        [ "$cli" = codex ] && rm -f "$root/AGENTS.md"
    done

    # Counter-patterns extras: only undo when we're tearing down everything,
    # OR when claude was in the --for set (the extras only ever attached to
    # the claude CLI). Otherwise leave them — partial CLI uninstalls
    # shouldn't strip the user's CLAUDE.md or hooks.
    local undo_extras=0
    if [ -z "$FOR_LIST" ]; then
        undo_extras=1
    else
        case " $target_clis " in *" claude "*) undo_extras=1 ;; esac
    fi
    if [ "$undo_extras" = 1 ]; then
        local cp_block_target cp_hooks_dir
        cp_block_target=$(manifest_extras_scalar "$mpath" counter_patterns_block target)
        cp_hooks_dir=$(manifest_extras_scalar "$mpath" counter_patterns_hooks hooks_dir)
        if [ -n "$cp_block_target" ] && [ -f "$cp_block_target" ]; then
            echo "  • removing counter-patterns CLAUDE.md block from $cp_block_target"
            cp_block_remove_inline "$cp_block_target"
        fi
        if [ -n "$cp_hooks_dir" ] && [ -d "$cp_hooks_dir" ]; then
            echo "  • removing counter-patterns hooks from $cp_hooks_dir"
            cp_hooks_uninstall_inline "$cp_hooks_dir"
            echo "    (also remove the counter-patterns entries from ~/.claude/settings.json by hand)"
        fi
    fi

    # If uninstalling everything, delete the manifest. Otherwise rewrite it
    # with the remaining CLIs.
    if [ -z "$FOR_LIST" ]; then
        rm -f "$mpath"
    else
        # Simplest path: regenerate manifest by dropping --for CLIs from "clis"
        # and deleting their blocks. For now, prompt the user to re-run
        # install without --for to cleanly regenerate; the manifest is left
        # stale with the removed CLI's lists pointing at now-deleted files.
        echo "Note: manifest still lists uninstalled CLIs. Re-run install to regenerate."
    fi
    echo "Removed."
}

# ---- counter-patterns extras ---------------------------------------------
# Opt-in installers for the counter-patterns CLAUDE.md block and Claude Code
# hooks. Both are no-ops unless the user explicitly opts in via flags or the
# interactive prompt. Both record their state in the manifest so --uninstall
# can reverse them.

cp_default_block_target() {
    if [ -n "$DEST" ]; then
        printf '%s/CLAUDE.md' "$DEST"
    else
        printf '%s/.claude/CLAUDE.md' "$HOME"
    fi
}

cp_default_hooks_target() {
    if [ -n "$DEST" ]; then
        printf '%s/.claude/hooks' "$DEST"
    else
        printf '%s/.claude/hooks' "$HOME"
    fi
}

# Prompt the user about counter-patterns extras if (a) claude is selected,
# (b) no extras flags were set, and (c) we have a TTY. Sets CP_BLOCK_MODE and
# CP_HOOKS_INSTALL based on responses.
cp_prompt_for_extras() {
    case " $CLIS " in *" claude "*) ;; *) return 0 ;; esac
    [ "$CP_EXPLICIT" = 1 ] && return 0
    local tty="/dev/tty"
    [ -r "$tty" ] && [ -w "$tty" ] || return 0
    [ "$ASSUME_YES" = "1" ] && return 0

    {
        echo
        echo "Counter-patterns extras (optional — these touch ~/.claude/ outside the agents/skills dirs):"
        printf '  Install Claude Code hooks (branch-guard, completion-claim guard, resume primer)? [y/N] '
    } > "$tty"
    local ans; ans=$(tty_read) || ans=""
    case "$ans" in y|Y|yes|YES) CP_HOOKS_INSTALL=1 ;; *) ;; esac

    {
        printf '  Insert the counter-patterns block into your CLAUDE.md? [prepend/append/skip] '
    } > "$tty"
    ans=$(tty_read) || ans=""
    case "$ans" in
        prepend|Prepend|PREPEND|p|P) CP_BLOCK_MODE="prepend" ;;
        append|Append|APPEND|a|A)    CP_BLOCK_MODE="append" ;;
        *) ;;
    esac
}

cp_validate_extras() {
    if [ "$CP_HOOKS_INSTALL" = 1 ]; then
        case " $CLIS " in
            *" claude "*) ;;
            *) die "--counter-patterns-hooks requires 'claude' in --for (hooks target Claude Code's hook surface)" ;;
        esac
    fi
}

# Install side: invoke the staged helpers. Records state for the manifest writer.
CP_BLOCK_INSTALLED=0
CP_BLOCK_INSTALLED_TARGET=""
CP_BLOCK_INSTALLED_MODE=""
CP_HOOKS_INSTALLED=0
CP_HOOKS_INSTALLED_DIR=""

cp_run_block_install() {
    [ -n "$CP_BLOCK_MODE" ] || return 0
    local helper="$STAGE/src/skills/global-scope/counter-patterns/install-claude-md-block.sh"
    local block="$STAGE/src/skills/global-scope/counter-patterns/CLAUDE_MD_BLOCK.md"
    [ -f "$helper" ] || die "counter-patterns helper missing in source: $helper"
    [ -f "$block" ] || die "counter-patterns block missing in source: $block"
    local target="${CP_BLOCK_TARGET:-$(cp_default_block_target)}"
    echo "  • counter-patterns CLAUDE.md block ($CP_BLOCK_MODE) → $target"
    bash "$helper" "$CP_BLOCK_MODE" --target "$target" --block "$block" >/dev/null
    CP_BLOCK_INSTALLED=1
    CP_BLOCK_INSTALLED_TARGET="$target"
    CP_BLOCK_INSTALLED_MODE="$CP_BLOCK_MODE"
}

cp_run_hooks_install() {
    [ "$CP_HOOKS_INSTALL" = 1 ] || return 0
    local helper="$STAGE/src/skills/global-scope/counter-patterns/hooks/install-hooks.sh"
    [ -f "$helper" ] || die "counter-patterns hooks installer missing in source: $helper"
    local target="${CP_HOOKS_TARGET:-$(cp_default_hooks_target)}"
    echo "  • counter-patterns hooks → $target"
    bash "$helper" install --target "$target" >/dev/null
    CP_HOOKS_INSTALLED=1
    CP_HOOKS_INSTALLED_DIR="$target"
    echo "    (a settings.json snippet was printed by the helper; merge it into ~/.claude/settings.json by hand)"
    echo "    full snippet:  bash $(cli_skills_dir claude)/counter-patterns/hooks/install-hooks.sh install --snippet-only --target \"$target\""
}

# Uninstall side: inline the removal so we don't need to fetch the source.

CP_BLOCK_BEGIN_MARKER="<!-- BEGIN counter-patterns block (managed by AgentSkills counter-patterns skill) -->"
CP_BLOCK_END_MARKER="<!-- END counter-patterns block -->"

cp_block_remove_inline() {
    # $1 = target file
    local target="$1"
    [ -f "$target" ] || return 0
    grep -qF "$CP_BLOCK_BEGIN_MARKER" "$target" || return 0
    grep -qF "$CP_BLOCK_END_MARKER" "$target" || return 0
    local tmp; tmp=$(mktemp -t agent-skills-cp.XXXXXX)
    /usr/bin/awk -v B="$CP_BLOCK_BEGIN_MARKER" -v E="$CP_BLOCK_END_MARKER" '
        BEGIN { state = 0; held_blank = 0 }
        state == 0 {
            if (index($0, B) > 0) { state = 1; held_blank = 0; next }
            if ($0 == "") { if (held_blank) print prev; prev = $0; held_blank = 1; next }
            if (held_blank) { print prev; held_blank = 0 }
            print
            next
        }
        state == 1 {
            if (index($0, E) > 0) { state = 2 }
            next
        }
        state == 2 {
            if ($0 == "") { state = 3; next }
            state = 3
            print
            next
        }
        state == 3 { print }
        END {
            if (state == 0 && held_blank) print prev
        }
    ' "$target" > "$tmp"
    cp "$target" "${target}.bak"
    mv "$tmp" "$target"
}

cp_hooks_uninstall_inline() {
    # $1 = hooks dir
    local dir="$1"
    [ -d "$dir" ] || return 0
    local h
    for h in pre-completion.sh pre-tool-branch-guard.sh session-start-primer.sh user-prompt-resume-detect.sh; do
        rm -f "$dir/$h"
    done
}

# Read counter-patterns scalars from a manifest file. Returns empty if absent.
manifest_extras_scalar() {
    local mpath="$1" group="$2" key="$3"
    /usr/bin/awk -v group="$group" -v key="$key" '
        $0 ~ "\""group"\":[[:space:]]*{" { in_group = 1; next }
        in_group && $0 ~ "\""key"\":" {
            sub(".*\""key"\":[[:space:]]*\"", "")
            sub("\".*", "")
            print
            exit
        }
        in_group && /^    }/ { in_group = 0 }
    ' "$mpath"
}

# ---- main -----------------------------------------------------------------
case "$ACTION" in
    uninstall)
        # For uninstall, resolve CLIs only if --for was passed.
        if [ -n "$FOR_LIST" ]; then
            CLIS=$(normalize_for "$FOR_LIST")
        else
            CLIS=""
        fi
        uninstall
        ;;

    list)
        CLIS=$(resolve_clis)
        cp_validate_extras
        if [ -n "$FROM_LOCAL" ]; then
            echo "Reading local source at $FROM_LOCAL …"
        else
            echo "Fetching $REPO@$REF for listing …"
        fi
        fetch_source
        list_install_set
        ;;

    install)
        CLIS=$(resolve_clis)

        # Resolve counter-patterns extras intent. Prompt only if no flags were
        # set, claude is in $CLIS, and we have a TTY.
        cp_prompt_for_extras
        cp_validate_extras

        echo "AgentSkills installer"
        echo "  source : $REPO @ $REF"
        echo "  CLIs   : $CLIS"
        if [ -n "$DEST" ]; then
            echo "  dest   : $DEST (override)"
        else
            for cli in $CLIS; do printf '  %-10s -> %s\n' "$cli" "$(cli_root "$cli")"; done
        fi
        if [ -n "$CP_BLOCK_MODE" ]; then
            echo "  extras : counter-patterns block ($CP_BLOCK_MODE) → ${CP_BLOCK_TARGET:-$(cp_default_block_target)}"
        fi
        if [ "$CP_HOOKS_INSTALL" = 1 ]; then
            echo "  extras : counter-patterns hooks → ${CP_HOOKS_TARGET:-$(cp_default_hooks_target)}"
        fi
        MPATH=$(manifest_path)
        if [ -f "$MPATH" ]; then
            echo "  manifest: $MPATH (exists — will be updated)"
        fi
        confirm "Proceed?" || { echo "aborted"; exit 1; }

        if [ -n "$FROM_LOCAL" ]; then
            echo "Reading local source at $FROM_LOCAL …"
        else
            echo "Fetching …"
        fi
        fetch_source

        # Back up existing manifest so prune_removed can diff against it.
        if [ -f "$MPATH" ]; then cp "$MPATH" "$MPATH.old"; fi

        echo "Installing …"
        for cli in $CLIS; do
            if cli_has_agents "$cli"; then
                echo "  • $cli (agents)"
            else
                echo "  • $cli (skills only)"
            fi
            install_cli "$cli"
        done

        # Skills install once per unique physical path (opencode/kilo/gemini
        # all share ~/.agents/skills/).
        echo "Installing skills …"
        install_skills_dedup | while read -r installed_path; do
            echo "  • skills → $installed_path"
        done

        # Counter-patterns extras run after skills land so the bundled helpers
        # are on disk at their install location (used by --uninstall later).
        if [ -n "$CP_BLOCK_MODE" ] || [ "$CP_HOOKS_INSTALL" = 1 ]; then
            echo "Installing counter-patterns extras …"
            cp_run_block_install
            cp_run_hooks_install
        fi

        # Resolve SHA if we cloned with git, else leave as the ref.
        RESOLVED_SHA="$REF"
        if [ -d "$STAGE/src/.git" ]; then
            RESOLVED_SHA=$(git -C "$STAGE/src" rev-parse HEAD 2>/dev/null || echo "$REF")
        fi

        write_manifest "$RESOLVED_SHA"
        prune_removed
        rm -f "$MPATH.old"

        kilo_defensive_setup

        echo
        echo "✓ Installed AgentSkills ($REPO@$REF) for: $CLIS"
        echo "  Manifest: $MPATH"
        echo
        echo "Next steps:"
        echo "  • In any repo, ask your AI CLI to run \`skill-sync\` to install repo-scope artifacts."
        echo "  • If you'll use ATO source skills or multi-model agents that need API keys,"
        echo "    run \`auth-interview\` once to bootstrap ~/.agent-skills/auth/auth.yaml."
        ;;

    *) die "unknown action: $ACTION" ;;
esac
