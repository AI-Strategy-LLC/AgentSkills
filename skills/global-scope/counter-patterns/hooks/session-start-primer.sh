#!/usr/bin/env bash
# SessionStart hook — prime the agent with the highest-leverage counter-patterns
# and surface compaction-resume cues if AGENT_STATE.md is present.
#
# Hook context: stdin is the JSON envelope from Claude Code; the script emits
# text on stdout which Claude Code surfaces in the conversation as a system note.

set -euo pipefail

CWD="${CLAUDE_CODE_CWD:-$(pwd)}"

if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "?")
WORKTREE=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "?")

RESUME_HINT=""
if [[ -f "$WORKTREE/AGENT_STATE.md" ]]; then
  AGE_MIN=$(( ($(date +%s) - $(stat -f %m "$WORKTREE/AGENT_STATE.md" 2>/dev/null || stat -c %Y "$WORKTREE/AGENT_STATE.md")) / 60 ))
  RESUME_HINT="AGENT_STATE.md present (updated ${AGE_MIN}m ago) — run /counter-patterns --resume before any code change."
fi

PROTECTED="${CP_PROTECTED_BRANCHES:-main master develop trunk prod production}"
PROTECTED_HINT=""
for p in $PROTECTED; do
  if [[ "$BRANCH" == "$p" ]]; then
    PROTECTED_HINT="WARNING: on protected branch '$BRANCH'. Policy: stop and ask to branch before any change (CP-008)."
    break
  fi
done

cat <<EOF
## Counter-patterns primer (auto-loaded at session start)

Repo: $WORKTREE
Branch: $BRANCH

Highest-leverage rules:

1. **Branch first (CP-008).** First tool call in a code-modifying session is \`git status && git branch --show-current\`. Never edit on a protected branch.
2. **Source-of-truth (CP-006).** When multiple sources could answer "what should this do?", name the canonical one before writing.
3. **Wiring-vs-backend (CP-003).** A feature is done only when entry-point → handler is traceable end-to-end with a test. Cite both file:line.
4. **Multi-axis briefs (CP-014).** Allocate budget per axis up front; report per axis at end. Empty axes are findings.
5. **Post-compaction (CP-010).** First tool call after any compaction marker is the state-reconciliation block.

${RESUME_HINT:+$RESUME_HINT}
${PROTECTED_HINT:+$PROTECTED_HINT}
EOF
