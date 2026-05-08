#!/usr/bin/env bash
# ato/install.sh — install ONLY the ATO (Authority to Operate) skill + agent
# collection for one or more AI coding CLIs. This is a self-contained,
# independently-shareable subset of the AgentSkills installer.
#
# What it installs:
#   - 9 ATO skills    (ato-artifact-collector + 5 source skills + the
#                      vulnerability-scanner stub + remediation-guidance + poam-generator)
#   - 2 auth skills   (auth-config, auth-interview) — every ATO source sibling
#                      preauths through them. They live canonically here under
#                      ato/skills/global-scope/ since ATO is currently their
#                      only consumer. The main installer also installs them
#                      via merge_ato_into_src; if a future non-ATO consumer
#                      appears, a one-line git mv promotes them back to the
#                      generic skills/global-scope/ tree.
#   - 3 ATO agents    (ato-artifact-collector, ato-vulnerability-scanner,
#                      ato-doc-summarizer)
# Nothing else. The general AgentSkills corpus (deep-review, branch-review,
# coverage-audit, the language preflights, etc.) is NOT touched.
#
# The ato/ folder is self-contained: it bundles the per-CLI renderers it
# needs under ato/agents/renderers/, so this script works whether you've
# cloned the parent AgentSkills repo or copied just the ato/ folder somewhere
# else (an internal share, a separate repo, an archive).
#
# Usage (from the repo root, when you've cloned AI-Strategy-LLC/AgentSkills):
#   bash ato/install.sh --for claude
#   bash ato/install.sh --for claude,opencode,codex
#   bash ato/install.sh --for claude --list             # dry run
#   bash ato/install.sh --uninstall                     # remove everything we installed
#   bash ato/install.sh --uninstall --for claude        # remove for a single CLI
#
# Usage (one-liner, once the branch is merged to main):
#   curl -fsSL https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/ato/install.sh \
#     | bash -s -- --for claude
#
# What it does:
#   1. Locates the source tree (local checkout, --from <dir>, or fetched via
#      tarball / git clone of the parent repo, looking for the ato/ subfolder).
#   2. For each selected CLI, renders every ATO base agent through
#      ato/agents/renderers/<cli>.sh and writes the result into the CLI's
#      global agents directory. Skills land in the CLI's global skills
#      directory. Codex additionally gets a small AGENTS.md inventory.
#   3. Writes a per-CLI manifest at ~/.agent-skills/ato-installer-manifest.json
#      so re-runs are idempotent and --uninstall removes only what we wrote.
#
# What it does NOT do:
#   - Install the rest of AgentSkills. Use the top-level install.sh for that.
#   - Modify shell configs.
#   - Store credentials. For that, run the auth-interview skill after install.

set -euo pipefail

# Re-exec under bash if invoked via `sh ato/install.sh`.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo "ato/install.sh: needs bash" >&2
    exit 1
fi

# ---- defaults -------------------------------------------------------------
REPO="${AGENT_SKILLS_REPO:-AI-Strategy-LLC/AgentSkills}"
REF="${AGENT_SKILLS_REF:-main}"
DEST="${AGENT_SKILLS_DEST:-}"                         # unset = each CLI uses its native root
FOR_LIST="${AGENT_SKILLS_FOR:-}"                      # CSV: claude,opencode,kilo,codex,gemini,pi
FROM_LOCAL="${AGENT_SKILLS_FROM:-}"                   # local path containing ato/ (or being the ato/ folder)
ACTION="install"
ASSUME_YES=0
KEEP_CACHE=""

MANIFEST_NAME="ato-installer-manifest.json"

SUPPORTED_CLIS="claude opencode kilo codex gemini pi cursor"

# ---- usage ----------------------------------------------------------------
usage() {
    cat <<EOF
ATO Agent Collection installer

Usage:
  ato/install.sh --for <cli>[,<cli>...] [options]

Required:
  --for <list>        Comma-separated list of CLIs. Any of:
                        claude     → ~/.claude/
                        opencode   → ~/.config/opencode/
                        kilo       → ~/.config/kilo/
                        codex      → ~/.codex/
                        gemini     → ~/.gemini/
                        pi         → ~/.pi/agent/   (skills only — Pi has no subagents)
                        cursor     → ~/.cursor/     (rules-as-MDC)
                      If omitted, a TTY prompt asks multi-select. In non-TTY
                      mode (e.g. pipe into sh -c) --for is required.

Options:
  --ref <ref>         Git ref to install when fetching remotely. Default: main
  --repo <owner/name> Source GitHub repo (must contain ato/). Default: AI-Strategy-LLC/AgentSkills
  --dest <dir>        Override install root. When set, each CLI installs under
                      <dir>/<cli>/.
  --list              Print what would be installed; do not write anything.
  --uninstall         Remove everything this script previously installed.
                      Combine with --for to restrict to specific CLIs.
  --from <dir>        Install from a local checkout. <dir> may either be the
                      AgentSkills repo root (we'll use <dir>/ato/) or the ato/
                      folder itself (we detect skills/global-scope/ inside it).
  --keep-cache <dir>  After install, move the extracted source to <dir>.
  -y, --yes           Do not prompt; assume yes.
  -h, --help          This message.

Manifest:
  ~/.agent-skills/${MANIFEST_NAME}    (per-user; separate from the main
                                       AgentSkills installer manifest)
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
        -y|--yes) ASSUME_YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# ---- helpers --------------------------------------------------------------
die() { echo "ato/install.sh: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

tty_read() {
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
    if [ -n "$DEST" ]; then printf '%s/%s' "$DEST" "$cli"; return; fi
    case "$cli" in
        claude)   printf '%s/.claude' "$HOME" ;;
        opencode) printf '%s/opencode' "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
        kilo)     printf '%s/.config/kilo' "$HOME" ;;
        codex)    printf '%s/.codex' "$HOME" ;;
        gemini)   printf '%s/.gemini' "$HOME" ;;
        pi)       printf '%s/.pi/agent' "$HOME" ;;
        cursor)   printf '%s/.cursor' "$HOME" ;;
        *) die "unknown CLI: $cli" ;;
    esac
}

# Pi has no subagents — only consumes skills.
cli_has_agents() {
    case "$1" in
        pi) return 1 ;;
        *)  return 0 ;;
    esac
}

cli_agent_ext() {
    case "$1" in
        codex)  printf 'toml' ;;
        cursor) printf 'mdc' ;;
        *)      printf 'md' ;;
    esac
}

# Same dedup rule as the main installer: opencode/kilo/gemini/codex/pi all
# auto-discover ~/.agents/skills/, so we install once into that shared
# location. Claude is the only CLI that doesn't scan ~/.agents/, so it gets
# its own ~/.claude/skills/.
cli_skills_dir() {
    local cli="$1" bucket
    case "$cli" in
        claude)                                 bucket=".claude/skills" ;;
        opencode|kilo|gemini|codex|pi|cursor)   bucket=".agents/skills" ;;
        *) die "unknown CLI: $cli" ;;
    esac
    if [ -n "$DEST" ]; then printf '%s/%s' "$DEST" "$bucket"
    else                    printf '%s/%s' "$HOME" "$bucket"
    fi
}

# ---- validate --for -------------------------------------------------------
normalize_for() {
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
    local tty="/dev/tty"
    [ -r "$tty" ] && [ -w "$tty" ] || return 1
    {
        echo
        echo "Which CLIs should I install the ATO collection for?"
        echo "  1) claude    → ~/.claude/"
        echo "  2) opencode  → ~/.config/opencode/"
        echo "  3) kilo      → ~/.config/kilo/"
        echo "  4) codex     → ~/.codex/"
        echo "  5) gemini    → ~/.gemini/"
        echo "  6) pi        → ~/.pi/agent/   (skills only)"
        echo "  7) cursor    → ~/.cursor/     (rules-as-MDC)"
        printf 'Enter comma-separated numbers or names (e.g. "1,2" or "claude,opencode"): '
    } > "$tty"
    local ans; ans=$(tty_read) || return 1
    ans=$(printf '%s' "$ans" | tr -d '[:space:]')
    [ -z "$ans" ] && return 1
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
            claude|opencode|kilo|codex|gemini|pi|cursor) mapped="${mapped:+$mapped,}$t" ;;
            *) echo "ignored: $t" > "$tty" ;;
        esac
    done
    printf '%s' "$mapped"
}

resolve_clis() {
    if [ -n "$FOR_LIST" ]; then normalize_for "$FOR_LIST"; return; fi
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
STAGE="$(mktemp -d -t ato-installer.XXXXXX)"
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

# ATO_ROOT is the folder containing skills/global-scope/, agents/base/global-scope/,
# and agents/renderers/. Set by fetch_source() once the layout is known.
ATO_ROOT=""

# ---- manifest location ----------------------------------------------------
manifest_path() {
    if [ -n "$DEST" ]; then printf '%s/%s' "$DEST" "$MANIFEST_NAME"
    else                    printf '%s/.agent-skills/%s' "$HOME" "$MANIFEST_NAME"
    fi
}

# ---- fetch ----------------------------------------------------------------
# A directory is a valid "ATO root" if it has the three subtrees we need
# AND the orchestrator skill+agent at the top-level skills/agents (rather
# than under ato/). This second check distinguishes the dedicated ato/ folder
# from the parent AgentSkills repo root, which also has the three subtrees
# but with the ATO content nested under ato/.
is_ato_root() {
    local d="$1"
    [ -d "$d/skills/global-scope/ato-artifact-collector" ] && \
    [ -d "$d/agents/base/global-scope/ato-artifact-collector" ] && \
    [ -d "$d/agents/renderers" ]
}

fetch_local() {
    [ -d "$FROM_LOCAL" ] || die "--from: '$FROM_LOCAL' is not a directory"
    mkdir -p "$STAGE/src"
    if is_ato_root "$FROM_LOCAL"; then
        # User pointed at the ato/ folder directly.
        cp -R "$FROM_LOCAL/skills" "$FROM_LOCAL/agents" "$STAGE/src/"
        ATO_ROOT="$STAGE/src"
    elif is_ato_root "$FROM_LOCAL/ato"; then
        # User pointed at a parent repo that contains ato/.
        cp -R "$FROM_LOCAL/ato/skills" "$FROM_LOCAL/ato/agents" "$STAGE/src/"
        ATO_ROOT="$STAGE/src"
    else
        die "--from: neither '$FROM_LOCAL' nor '$FROM_LOCAL/ato' looks like an ATO source root (need skills/global-scope, agents/base/global-scope, agents/renderers)"
    fi
}

fetch_tarball() {
    local url="https://codeload.github.com/$REPO/tar.gz/$REF"
    local out="$STAGE/src.tar.gz"
    case "$FETCHER" in
        curl) curl -fsSL "$url" -o "$out" || die "failed to download $url" ;;
        wget) wget -q "$url" -O "$out" || die "failed to download $url" ;;
    esac
    mkdir -p "$STAGE/full"
    tar -xzf "$out" -C "$STAGE/full" --strip-components=1
    if is_ato_root "$STAGE/full/ato"; then
        ATO_ROOT="$STAGE/full/ato"
    elif is_ato_root "$STAGE/full"; then
        ATO_ROOT="$STAGE/full"
    else
        die "fetched tarball at $REPO@$REF doesn't contain a recognizable ato/ folder"
    fi
}

fetch_git() {
    have git || die "need git (or curl/wget) to fetch repo"
    git clone --depth 1 --branch "$REF" "https://github.com/$REPO.git" "$STAGE/full" 2>/dev/null \
        || (git clone "https://github.com/$REPO.git" "$STAGE/full" && (cd "$STAGE/full" && git checkout "$REF"))
    if is_ato_root "$STAGE/full/ato"; then
        ATO_ROOT="$STAGE/full/ato"
    elif is_ato_root "$STAGE/full"; then
        ATO_ROOT="$STAGE/full"
    else
        die "cloned $REPO@$REF doesn't contain a recognizable ato/ folder"
    fi
}

# Implicit-local: when invoked from inside a clone (the script's own
# directory satisfies is_ato_root), use that. Saves a round-trip.
fetch_implicit_local() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 1
    [ -n "$script_dir" ] || return 1
    if is_ato_root "$script_dir"; then
        ATO_ROOT="$script_dir"
        return 0
    fi
    return 1
}

fetch_source() {
    if [ -n "$FROM_LOCAL" ]; then
        fetch_local
        return
    fi
    if fetch_implicit_local; then
        return
    fi
    fetch_tarball || { echo "tarball fetch failed, falling back to git clone"; fetch_git; }
}

# ---- agent shape helpers --------------------------------------------------
agent_is_dir_form() {
    local d="$1"
    [ -d "$d/references" ] || [ -d "$d/evals" ] || [ -f "$d/config.yaml" ]
}

cli_uses_flat_only() {
    case "$1" in
        opencode|kilo|gemini|cursor) return 0 ;;
        *) return 1 ;;
    esac
}

copy_agent_bundled() {
    local base="$1" target_dir="$2"
    [ -d "$base/references" ] && cp -R "$base/references" "$target_dir/"
    [ -d "$base/evals" ]      && cp -R "$base/evals"      "$target_dir/"
    [ -f "$base/config.yaml" ] && cp "$base/config.yaml" "$target_dir/"
    return 0
}

# ---- list / install -------------------------------------------------------
list_install_set() {
    local src_skills="$ATO_ROOT/skills/global-scope"
    local src_agents="$ATO_ROOT/agents/base/global-scope"

    [ -d "$src_skills" ] || die "ATO_ROOT '$ATO_ROOT' has no skills/global-scope/"
    [ -d "$src_agents" ] || die "ATO_ROOT '$ATO_ROOT' has no agents/base/global-scope/"

    echo "Selected CLIs: $CLIS"
    echo "ATO source root: $ATO_ROOT"
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
            echo "  AGENTS.md   (ATO-only inventory at $root/ATO_AGENTS.md)"
        fi
    done
}

# ---- install one CLI ------------------------------------------------------
install_cli() {
    local cli="$1"

    if ! cli_has_agents "$cli"; then return 0; fi

    local src_agents="$ATO_ROOT/agents/base/global-scope"
    local renderer="$ATO_ROOT/agents/renderers/$cli.sh"
    local codex_agents_md="$ATO_ROOT/agents/renderers/codex-agents-md.sh"
    local root; root=$(cli_root "$cli")
    local ext; ext=$(cli_agent_ext "$cli")

    [ -x "$renderer" ] || die "missing or non-executable renderer: $renderer"

    mkdir -p "$root/agents"

    local bases=()
    for d in "$src_agents"/*/; do
        [ -d "$d" ] || continue
        local name; name=$(basename "$d")
        bases+=("$d")

        if agent_is_dir_form "$d" && ! cli_uses_flat_only "$cli"; then
            local target_dir="$root/agents/$name"
            rm -rf "$target_dir"
            rm -f "$root/agents/$name.$ext"
            mkdir -p "$target_dir"
            "$renderer" "$d" > "$target_dir/$name.$ext"
            copy_agent_bundled "$d" "$target_dir"
        else
            rm -rf "$root/agents/$name"
            "$renderer" "$d" > "$root/agents/$name.$ext"
        fi
    done

    # Codex extra: ATO_AGENTS.md (a separate inventory, so we don't clobber
    # the main installer's AGENTS.md when both installers are used).
    if [ "$cli" = codex ]; then
        "$codex_agents_md" "${bases[@]}" > "$root/ATO_AGENTS.md"
    fi
}

# ---- install skills (deduped across CLIs) ---------------------------------
install_skills_dedup() {
    local src_skills="$ATO_ROOT/skills/global-scope"
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

# ---- manifest I/O ---------------------------------------------------------
write_manifest() {
    local resolved_sha="$1"
    local src_skills="$ATO_ROOT/skills/global-scope"
    local src_agents="$ATO_ROOT/agents/base/global-scope"
    local mpath; mpath=$(manifest_path)
    mkdir -p "$(dirname "$mpath")"

    local blocks=""
    local cli_idx=0 cli_count=0
    for cli in $CLIS; do cli_count=$((cli_count+1)); done

    for cli in $CLIS; do
        cli_idx=$((cli_idx+1))
        local skills_json="" flat_json="" dir_json=""

        for d in "$src_skills"/*/; do
            [ -d "$d" ] || continue
            local n; n=$(basename "$d")
            skills_json="${skills_json}      \"$(json_escape "$n")\",\n"
        done

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

    {
        printf '{\n'
        printf '  "version": 1,\n'
        printf '  "kind": "ato-only",\n'
        printf '  "source": {\n'
        printf '    "repo": "%s",\n' "$(json_escape "$REPO")"
        printf '    "ref": "%s",\n' "$(json_escape "$REF")"
        printf '    "resolved_sha": "%s"\n' "$(json_escape "$resolved_sha")"
        printf '  },\n'
        printf '  "installed_at": "%s",\n' "$(iso_now)"
        printf '  "installer_version": 1,\n'
        printf '  "clis": ['
        local first=1
        for cli in $CLIS; do
            if [ "$first" = 1 ]; then first=0; else printf ','; fi
            printf '"%s"' "$cli"
        done
        printf '],\n'
        printf '  "installed": {\n'
        printf '%b' "$blocks"
        printf '  }\n'
        printf '}\n'
    } > "$mpath"
    chmod 0644 "$mpath"
}

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
    local mpath; mpath=$(manifest_path)
    [ -f "$mpath.old" ] || return 0

    local src_skills="$ATO_ROOT/skills/global-scope"
    local src_agents="$ATO_ROOT/agents/base/global-scope"

    local skill_paths_seen=" "
    for cli in $CLIS; do
        local root; root=$(cli_root "$cli")
        local sdir; sdir=$(cli_skills_dir "$cli")
        local ext; ext=$(cli_agent_ext "$cli")
        local old_sdir; old_sdir=$(manifest_scalar "$mpath.old" "$cli" skills_root)

        if [ -n "$old_sdir" ] && [ "$old_sdir" != "$sdir" ]; then
            local old_skills_at_old_path; old_skills_at_old_path=$(manifest_list "$mpath.old" "$cli" skills)
            for n in $old_skills_at_old_path; do rm -rf "$old_sdir/$n"; done
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
    [ -f "$mpath" ] || { echo "No ATO manifest at $mpath — nothing to uninstall."; return 0; }

    local target_clis="$CLIS"
    if [ -z "$FOR_LIST" ]; then
        target_clis=$(awk '/"clis":/ { sub(".*\\[",""); sub("\\].*",""); gsub(/[",]/," "); print; exit }' "$mpath")
    fi

    echo "This will remove the ATO collection's artifacts for: $target_clis"
    echo "  manifest: $mpath"
    confirm "Proceed?" || { echo "aborted"; exit 1; }

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
        [ "$cli" = codex ] && rm -f "$root/ATO_AGENTS.md"
    done

    if [ -z "$FOR_LIST" ]; then
        rm -f "$mpath"
    else
        echo "Note: ATO manifest still lists uninstalled CLIs. Re-run install to regenerate."
    fi
    echo "Removed."
}

# ---- main -----------------------------------------------------------------
case "$ACTION" in
    uninstall)
        if [ -n "$FOR_LIST" ]; then CLIS=$(normalize_for "$FOR_LIST")
        else CLIS=""
        fi
        uninstall
        ;;

    list)
        CLIS=$(resolve_clis)
        if [ -n "$FROM_LOCAL" ]; then
            echo "Reading local source at $FROM_LOCAL …"
        else
            echo "Resolving ATO source …"
        fi
        fetch_source
        list_install_set
        ;;

    install)
        CLIS=$(resolve_clis)
        echo "ATO Agent Collection installer"
        echo "  source : $REPO @ $REF"
        echo "  CLIs   : $CLIS"
        if [ -n "$DEST" ]; then
            echo "  dest   : $DEST (override)"
        else
            for cli in $CLIS; do printf '  %-10s -> %s\n' "$cli" "$(cli_root "$cli")"; done
        fi
        MPATH=$(manifest_path)
        if [ -f "$MPATH" ]; then
            echo "  manifest: $MPATH (exists — will be updated)"
        fi
        confirm "Proceed?" || { echo "aborted"; exit 1; }

        if [ -n "$FROM_LOCAL" ]; then
            echo "Reading local source at $FROM_LOCAL …"
        else
            echo "Resolving ATO source …"
        fi
        fetch_source
        echo "  ato root: $ATO_ROOT"

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

        echo "Installing skills …"
        install_skills_dedup | while read -r installed_path; do
            echo "  • skills → $installed_path"
        done

        RESOLVED_SHA="$REF"
        if [ -d "$STAGE/full/.git" ]; then
            RESOLVED_SHA=$(git -C "$STAGE/full" rev-parse HEAD 2>/dev/null || echo "$REF")
        fi

        write_manifest "$RESOLVED_SHA"
        prune_removed
        rm -f "$MPATH.old"

        echo
        echo "✓ Installed ATO Agent Collection ($REPO@$REF) for: $CLIS"
        echo "  Manifest: $MPATH"
        echo
        echo "Next steps:"
        echo "  • Run /ato-artifact-collector inside any repo to start an ATO collection."
        echo "  • For external sources (AWS / Azure / SharePoint / OneDrive / SMB),"
        echo "    log in to the matching CLI first (see ato/README.md → Authentication),"
        echo "    or run \`auth-interview\` once for a guided vault-backed setup"
        echo "    (1Password / Bitwarden / Keychain / Vault / env vars / user scripts)."
        ;;

    *) die "unknown action: $ACTION" ;;
esac
