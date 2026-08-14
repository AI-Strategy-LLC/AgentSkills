# Pi support

[Pi](https://pi.dev) (`@earendil-works/pi-coding-agent`) is a minimal terminal coding harness. This directory holds the one piece of Pi-specific glue AgentSkills needs: a script that installs Pi's bundled subagent extension so the agents rendered by `install.sh --for pi` actually have something to run them.

## Two naming traps

Both cost time if you hit them cold:

- **The npm package is `@earendil-works/pi-coding-agent`.** `@mariozechner/pi` is an unrelated CLI for deploying vLLM on GPU pods, by the same author.
- **The repo is [`earendil-works/pi`](https://github.com/earendil-works/pi).** `badlogic/pi-mono` redirects there. Docs are at `pi.dev/docs/latest/…` — the `/docs/…` prefix without `latest` 404s.

## What Pi gives you natively

| Capability | Native? |
|---|---|
| Skills (`SKILL.md`, agentskills.io spec) | **Yes** — reads `~/.agents/skills/`, which is where `install.sh` already writes |
| Hooks | **Yes** — 32 `pi.on()` events; a `tool_call` handler can return `{ block: true, reason }` |
| Slash commands, prompt templates, themes | **Yes** |
| Extension API | **Yes** — `registerTool`, `registerCommand`, `registerShortcut`, `registerFlag` |
| Subagents, MCP, plan mode, to-dos, background bash | **No — excluded from core by design** |

That last row is a stated position, not an oversight (`docs/usage.md`): *"It intentionally does not include built-in MCP, sub-agents, permission popups, plan mode, to-dos, or background bash. You can build or install those workflows as extensions or packages."*

## Installing subagent support

```bash
bash pi/install-subagent-extension.sh
```

This copies Pi's own bundled `examples/extensions/subagent/` into `~/.pi/agent/extensions/subagent/`. It gives you a `subagent` tool with isolated context per agent (each runs as its own `pi` subprocess), parallel fan-out (max 8 tasks, 4 concurrent), chaining, streaming output and per-agent cost tracking.

Then install the agents themselves:

```bash
bash install.sh --for pi
```

Verify it actually works — not that the files exist, but that the tool fires:

```bash
pi -p 'Use the subagent tool with agent "branch-review" to summarize this repo'
```

### Why copy at install time instead of vendoring the extension here

The extension imports `@earendil-works/pi-coding-agent` and uses its internal API (`ExtensionAPI`, `parseFrontmatter`, `getAgentDir`, `CONFIG_DIR_NAME`). A copy vendored at one Pi version would rot silently against a later one. Copying from your own installed Pi keeps the extension matched to the Pi that loads it. Re-run the script after upgrading Pi.

### Why copy instead of symlink

Pi's own README suggests symlinking. Don't — the source lives inside the package directory, so `brew upgrade`, `npm -g update`, or `pi update self` replaces it and leaves a dangling link.

## How agents are rendered for Pi

`agents/renderers/pi.sh`. Four things differ from every other renderer, each for a verified reason:

1. **`tools` is a comma-separated string, not a YAML list.** The loader does `frontmatter.tools?.split(",")`. A YAML list would be mis-parsed.
2. **Tool names are mapped, and unmapped ones are dropped rather than passed through.** The list becomes `pi --tools <list>` on the subprocess, and an unrecognized name makes that subprocess fail outright.
   `Bash→bash · Read→read · Write→write · Edit→edit · Grep→grep · Glob→find · Agent→subagent`; `Skill`, `WebFetch`, `WebSearch` are dropped.
3. **`model:` is not emitted.** Pi passes it to `pi --model`, which wants a concrete provider ID (`claude-haiku-4-5`), not our canonical `opus`/`sonnet`/`haiku` aliases. Pi's default provider is Google, so an alias would not resolve. Omitting it means each subagent inherits your configured model.
4. **Agents are flat with references inlined.** `loadAgentsFromDir()` is a single non-recursive `readdirSync()` over `*.md`, so a bundled `references/` directory is never read.

`Agent → subagent` is deliberate rather than dropped: `deep-review` declares `Agent` and its body fans out to child agents, so dropping it would leave a documented capability silently unwired. Nesting works because the extension spawns children *without* `--no-extensions`, and `--tools` applies to extension tools as well as built-ins. Recursion is bounded by the extension's own 8-task / 4-concurrent caps.

### The failure mode worth knowing about

Pi's `loadAgentsFromDir()` has **no `try`/`catch` around `parseFrontmatter`**. One agent with invalid YAML throws and kills discovery for *every* agent. `agents/renderers/tests/smoke.sh` validates all rendered agents against Pi's own parser whenever Pi is installed locally.

## Project-local agents are off by default — and we keep it that way

The extension's `agentScope` defaults to `"user"`, so agents in a repo's `<repo>/.pi/agents/` are **not** loaded unless the caller passes `agentScope: "both"`.

We deliberately do not change that default. The confirmation prompt that gates project-local agents is skipped when there is no UI (`ctx.hasUI` is false), so flipping the default would mean any repo you open in `pi -p` could execute agent prompts it ships, unprompted. Since `agents/base/repo-scope/` is empty today, the default costs us nothing.

If you want repo-local agents, pass `agentScope: "both"` explicitly in the tool call, and only in repos you trust.

## Optional third-party packages

Pi has a large package ecosystem (`pi.dev/packages`). AgentSkills bundles **none** of it and installs none of it automatically. Two caveats before you install anything:

- Pi extensions run **in-process with full system access**. Pi's own docs say to review the source first.
- Published reviews of the ecosystem ([thevinter](https://www.thevinter.com/blog/bad-vibes-from-pi), [Composio](https://composio.dev/content/pi-agent-vs-claude-code)) report that many community extensions are themselves thinly-reviewed LLM-generated code. Download counts are a more reliable signal than GitHub stars here — star counts in this ecosystem do not survive scrutiny.

With that said, the packages that fill the remaining gaps, with monthly install counts verified against `api.npmjs.org`:

| Gap | Package | Installs/mo |
|---|---|---|
| MCP — **no first-party option exists** | `pi install npm:pi-mcp-adapter` | 354k |
| Web search / fetch (needed for `WebFetch`/`WebSearch`) | `pi install npm:pi-web-access` | 222k |
| Subagents (alternative to the bundled example) | `pi install npm:pi-subagents` | 214k |
| Worktree isolation + cost accounting | `pi install npm:@quintinshaw/pi-dynamic-workflows` | 30k |

For **plan mode** and **to-dos**, prefer Pi's own bundled examples (`examples/extensions/plan-mode/`, `examples/extensions/todo.ts`) over third-party equivalents — same first-party provenance as the subagent extension.
