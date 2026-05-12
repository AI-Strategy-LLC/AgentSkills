#!/usr/bin/env bash
# SessionStart hook — prime the agent with the highest-leverage counter-patterns
# and trigger /counter-patterns --resume if compaction-resume signals are detected.
#
# Hook context: stdin is the JSON envelope from Claude Code; we mostly care about
# whether this is a fresh session or a continuation. We emit text to stdout which
# Claude Code surfaces in the conversation as a system note.

set -euo pipefail

CWD="${CLAUDE_CODE_CWD:-$(pwd)}"

# Detect whether we're in a git repo at all
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0  # nothing to do outside a repo
fi

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "?")
WORKTREE=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "?")

# Has an AGENT_STATE.md checkpoint? Then this is likely a resume.
RESUME_HINT=""
if [[ -f "$WORKTREE/AGENT_STATE.md" ]]; then
  AGE_MIN=$(( ($(date +%s) - $(stat -f %m "$WORKTREE/AGENT_STATE.md" 2>/dev/null || stat -c %Y "$WORKTREE/AGENT_STATE.md")) / 60 ))
  RESUME_HINT="AGENT_STATE.md present (updated ${AGE_MIN}m ago) — run /counter-patterns --resume before any code change."
fi

# On a protected branch?
PROTECTED_HINT=""
case "$BRANCH" in
  main|master|develop|trunk|prod|production)
    PROTECTED_HINT="WARNING: on protected branch '$BRANCH'. CLAUDE.md says: stop and ask to branch before any change."
    ;;
esac

cat <<EOF
## Counter-patterns primer (auto-loaded at session start)

Repo: $WORKTREE
Branch: $BRANCH

Highest-leverage rules from ~/.claude/CLAUDE.md (full text in the file):

1. **Branch first.** First tool call in a code-modifying session is \`git status && git branch --show-current\`. Never edit on main.
2. **Source-of-truth.** When multiple sources could answer "what should this do?", name the canonical one before writing.
3. **Wiring-vs-backend.** A feature is done only when entry-point → handler is traceable end-to-end with a test. Cite both file:line.
4. **Multi-axis briefs.** Allocate budget per axis up front; report per axis at end. Empty axes are findings.
5. **Post-compaction.** First tool call after any compaction marker is the state-reconciliation block.

${RESUME_HINT:+$RESUME_HINT}
${PROTECTED_HINT:+$PROTECTED_HINT}
EOF
