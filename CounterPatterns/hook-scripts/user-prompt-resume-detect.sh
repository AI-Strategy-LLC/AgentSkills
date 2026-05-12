#!/usr/bin/env bash
# UserPromptSubmit hook — detect resume/compaction signals in the user's prompt
# and inject a reminder to reconcile state before doing anything.
#
# Stdin: JSON envelope with the user's prompt text under .prompt
# Stdout: text appended to the conversation as a system note

set -euo pipefail

PROMPT=$(jq -r '.prompt // ""' 2>/dev/null || cat)

# Resume-style cues
if echo "$PROMPT" | grep -qiE 'resum(e|ing)|continue (from|the)|pick up|where (we|did) (left|leave)|carry on|where were we'; then
  cat <<'EOF'
## Resume detected

The user's message looks like a resume / continuation. CLAUDE.md says:

- First tool call: `git status && git branch -vv && gh pr list --author @me --state open && git worktree list`
- Then: `git log --oneline -20` on the target branch.
- If `AGENT_STATE.md` exists at repo root, read it and reconcile against live git/gh state.
- Surface any drift to the user before proceeding. Do not silently restart from scratch.
EOF
  exit 0
fi

# Pivot cues
if echo "$PROMPT" | grep -qiE '^(actually|wait|stop|hold on|let.?s shift|pivot|instead|change of plans|new direction)'; then
  cat <<'EOF'
## Pivot detected

The user's message looks like a mid-session pivot. CLAUDE.md says: explicitly summarize what you're abandoning and what you're keeping before continuing. Do not silently mix old and new direction.
EOF
  exit 0
fi
