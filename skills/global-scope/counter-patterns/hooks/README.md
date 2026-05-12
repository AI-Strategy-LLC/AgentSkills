# Counter-patterns hooks

These hook scripts are the **mechanical guards** for the counter-patterns rules.
Text-only reminders in CLAUDE.md catch roughly 80% of the failure modes (CP-019);
hooks fire at the moment of action and catch the load-bearing rest. The
companion `/counter-patterns` skill provides the agent-facing checklist for
end-of-task / resume / checkpoint moments.

## Compatibility

**Claude Code only.** Other CLIs (OpenCode, Kilo, OpenAI Codex, Gemini, Pi) do
not currently expose the same `SessionStart` / `UserPromptSubmit` / `PreToolUse`
/ `Stop` hook surface, so these scripts will not run there. The skill body
(SKILL.md, counter-patterns.yaml) remains portable across CLIs even though
the hooks do not.

If a future Claude Code release changes its hook payload shape, the four
scripts here will need to be re-validated against the new shape.

## What each hook does

| Script | Hook event | Behavior | Rule |
|---|---|---|---|
| `pre-tool-branch-guard.sh` | `PreToolUse` (Edit/Write/NotebookEdit/Bash) | **Blocks** writes/commits on protected branches. Exit 2 with deny message. | CP-008 |
| `session-start-primer.sh` | `SessionStart` | Prints the 5 highest-leverage rules + a resume hint if `AGENT_STATE.md` is present at repo root. Non-blocking. | CP-008, CP-006, CP-003, CP-014, CP-010 |
| `user-prompt-resume-detect.sh` | `UserPromptSubmit` | Detects resume / continuation / pivot cues in the prompt and injects the state-reconciliation reminder. Non-blocking. | CP-010, CP-011 |
| `pre-completion.sh` | `Stop` | Two-stage detection. Stage 1: regex pre-filter for completion language. Stage 2 (opt-in, `CP_USE_AI=1`): asks a cheap AI judge (Haiku) whether the message is a completion claim missing required evidence. Blocks stops on insufficient evidence. | CP-001, CP-002, CP-003, CP-004, CP-012 |

The branch guard and the Stop hook are the load-bearing ones — they actively
prevent the failure mode rather than just describing it. The other two are
reminder injection at moments where the agent has the chance to act on them.

## Install

```sh
bash install-hooks.sh install
```

That copies the four scripts into `~/.claude/hooks/`, makes them executable,
and prints a `settings.json` snippet with the resolved absolute paths. Merge
the printed `hooks` block into `~/.claude/settings.json` — **do not overwrite**
the file if other hooks are configured there. Choose a different target dir
with `--target /path/to/hooks`.

```sh
bash install-hooks.sh status                       # report what's installed
bash install-hooks.sh uninstall                    # remove the scripts only
bash install-hooks.sh install --snippet-only       # print snippet, skip copy
```

`install-hooks.sh` does NOT modify `settings.json`. That's deliberate — JSON
merge across hand-authored settings is risky to automate, and the user often
already has hooks in place (status-line scripts, integrations) that must be
preserved per-event.

## Optional: AI completion judge

`pre-completion.sh` runs purely on regex by default — fast and free. Set
`CP_USE_AI=1` to enable Stage 2, where a cheap AI judge decides whether the
regex hit is a real completion claim and which evidence it's missing. Cost is
roughly $0.0005 per fired stop. The judge fails open (exit 0) on any error.

Other env vars:

```
CP_AI_CMD       Command to invoke the judge. Default: "claude --bare -p"
CP_AI_MODEL     Model to pass. Default: claude-haiku-4-5
CP_AI_TIMEOUT   Seconds before giving up. Default: 20
CP_DEBUG=1      Append decisions to /tmp/cp-pre-completion.log
```

## Uninstall

```sh
bash install-hooks.sh uninstall
```

Then remove the matching `counter-patterns/` entries from `~/.claude/settings.json`
by hand. The CLAUDE.md block (if installed) is uninstalled separately via
`install-claude-md-block.sh remove` at the skill root.
