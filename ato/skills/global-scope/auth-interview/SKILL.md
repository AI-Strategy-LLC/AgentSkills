---
name: auth-interview
description: "Interactive setup for ~/.agent-skills/auth/auth.yaml — walks the user through which external sources (AWS, Azure, SharePoint/M365, SMB) they use, which LLM providers they use (Anthropic, OpenAI, Gemini, Groq, HuggingFace, Mistral, Cohere, local Ollama/llama.cpp/vLLM), and where each credential lives (1Password, Bitwarden, Keeper, Vault, macOS Keychain, Windows Credential Manager, Linux libsecret, OAuth interactive, env vars, custom script, or a consumer subscription like Claude Pro/Max/Team where there is no API key). Writes the config with chmod 0600. Use when the user says 'set up auth', 'configure credentials', 'first-time setup', or when `auth-config` reports no config file exists."
---

# Auth Interview

This skill bootstraps `~/.agent-skills/auth/auth.yaml`. It asks the user a focused sequence of questions via `AskUserQuestion`, produces a yaml config, writes it with permissions `0600`, and leaves the user with a working credential-resolver config that `auth-config` and the ATO source skills can consume.

**Not a migration tool.** If `~/.agent-skills/auth/auth.yaml` already exists, offer three choices: add a new entry, modify an existing entry, or start over (with a timestamped backup of the existing file).

## Pre-flight

1. Check the directory. If `~/.agent-skills/auth/` does not exist, `mkdir -p ~/.agent-skills/auth && chmod 700 ~/.agent-skills/auth`. **Directory** permissions are `0700`; **file** permissions will be `0600`.
2. If `auth.yaml` exists with permissions looser than `0600`, tell the user and `chmod 0600` it before doing anything else.
3. Detect available vault CLIs (`op`, `bw`, `lpass`, `keeper`, `vault`, `security`, `cmdkey`, `secret-tool`, `kwallet-query`, `az`, `m365`, `gcloud`, `gh`). Use `command -v <tool>` for each. The detected set drives which provider options you offer — don't show `bitwarden` if `bw` isn't installed, but explain how to install it if the user's vault is Bitwarden.
4. Read `references/providers.md` (sibling file under this skill's directory) for the full list of provider-type schemas. That document is the source of truth for which keys each provider needs.

## Section 1 — External cloud / data sources

For each of AWS, Azure, SharePoint/M365, SMB, ask:

> `AskUserQuestion`: Do you collect evidence from <source>?
> Options: Yes · No · Not yet but soon

If **Yes** (or "soon"), ask:

> `AskUserQuestion`: Where are your <source> credentials stored?
> Options — filtered to detected CLIs, always include `script:` and `oauth_interactive` where relevant:
> - 1Password (detected: `op` CLI)
> - Bitwarden (detected: `bw` CLI)
> - Keeper Commander (detected: `keeper` CLI)
> - HashiCorp Vault (detected: `vault` CLI)
> - macOS Keychain (detected: `security`) — **macOS only**
> - Windows Credential Manager (detected: `cmdkey`) — **Windows only**
> - Linux libsecret / KWallet (detected: `secret-tool` or `kwallet-query`) — **Linux only**
> - OAuth interactive flow (`az login`, `m365 login`) — **only for Azure, SharePoint**
> - Already in environment variables
> - Custom script (I'll provide the command)
> - Skip — I'll edit the yaml manually

**For each provider type, ask the follow-ups defined in `references/providers.md`.** Examples:

- **1Password, template mode** → "Path to your op template file?" (e.g. `~/Library/AWS/awsauth.sh.tpl`)
- **1Password, single-value mode** → "Full `op://` path?" (e.g. `op://Private/Anthropic/api_key`)
- **Bitwarden** → "Item name?" + "Field? (password / username / totp / custom field name)"
- **Keeper** → "Record UID or title?" + "Field?"
- **Vault** → "Secret path?" + "Field?" + "Vault address (optional, defaults to $VAULT_ADDR)?"
- **macOS Keychain** → "generic or internet?" + "service/server?" + "account?"
   - **Apple Passwords gotcha:** After the user picks macOS Keychain, run `security find-generic-password -s <service> -a <account> 2>&1 >/dev/null` to verify the item is visible via the `security` CLI. If the command exits non-zero, warn: "This item isn't visible to the `security` CLI. If you created it in the Apple Passwords app, it may not be synced into the legacy Keychain that `security` reads. Options: (1) run `security add-generic-password -s <service> -a <account> -w <value>` to duplicate it, or (2) pick a different vault." Offer to re-prompt for the provider.
- **Windows Cred Manager** → "Target name?"
- **Linux libsecret** → "Attribute key/value pairs?" (service=X account=Y)
- **OAuth interactive** → confirm the login command (pre-filled based on source: `az login` / `m365 login`)
- **env** → "Env var name?"
- **Custom script** → "Shell command or path to script?"

After the provider fields, ask:

> `AskUserQuestion`: Validation command? (runs after preauth to confirm the session works)
> Pre-filled defaults by source:
> - AWS → `aws sts get-caller-identity`
> - Azure → `az account show`
> - SharePoint → `m365 status`
> - SMB → `mount | grep -q '<your share>'` (ask user to fill in the share hostname)
>
> Options: Accept default · Customize · Skip (not recommended)

Repeat for the next source.

## Section 2 — Model providers

Ask once which providers the user uses:

> `AskUserQuestion`: Which LLM providers do you use?
> Multi-select from:
> - Anthropic · OpenAI · Google Gemini · Groq · HuggingFace · Mistral · Cohere
> - Local Ollama · Local llama.cpp · Local vLLM · Local LM Studio
> - Other (specify)

### 2a — Subscription vs API key (ask first, before any vault questions)

For each hosted provider that has a consumer-subscription path (currently **Anthropic** via Claude Pro/Max/Team, **OpenAI** via ChatGPT Plus/Team if the user is on Codex CLI, **Google Gemini** via a personal Google account in AI Studio), ask **before** the vault question:

> `AskUserQuestion`: How do you access <provider>?
> Options:
> - **API key** (separate paid API workspace; key lives in a vault / env var / etc.)
> - **Subscription** (e.g., Claude Pro/Max/Team via the `claude` CLI; no separate API key — auth is managed by the CLI's `/login` flow)
> - **Both** (API key for raw API calls; subscription for the CLI itself)

Branch on the answer:

- **API key** → fall through to the vault flow below (Section 2b).
- **Subscription** → record the subscription entry only. Skip the vault question and the env-var question entirely. Schema:

  ```yaml
  model_providers:
    anthropic:
      provider: subscription
      cli: claude                # or codex / gemini
      plan: max                  # optional, free-form: pro / max / team / enterprise
      validate: claude --version # optional; most subscription CLIs lack an offline auth check
      note: |
        Anthropic auth is via Claude Pro/Max subscription managed by the
        `claude` CLI. There is no separate API key — skills that require
        raw API access must use a different provider entry or skip.
  ```

  Tell the user clearly: *"`auth-config` will return `subscription_no_api_key` to any caller asking for an `ANTHROPIC_API_KEY`. Skills running inside Claude Code itself inherit the subscription transparently and don't need the key. Skills that need raw API access (multi-model orchestration, fan-out from a non-Claude harness) will halt with a clear error pointing the user back here to add a separate API-key entry."*

- **Both** → record TWO entries: a `subscription` entry as above, AND an API-key entry under a distinct key (e.g., `anthropic_api:` alongside `anthropic:`). Run the vault flow for the API-key entry. Document the dual entry in the yaml's leading comment so future-you knows why there are two.

### 2b — Vault flow for API-key providers

For each provider that took the **API key** path (or has no subscription option, e.g., Groq / HuggingFace / Mistral / Cohere), run the same provider-type question flow as Section 1 (1Password / Bitwarden / Keychain / env / script / …), then ask:

> `AskUserQuestion`: Env var name to export the key into?
> Pre-filled defaults:
> - Anthropic → `ANTHROPIC_API_KEY`
> - OpenAI → `OPENAI_API_KEY`
> - Google Gemini → `GOOGLE_API_KEY` (or `GEMINI_API_KEY`)
> - Groq → `GROQ_API_KEY`
> - HuggingFace → `HF_TOKEN`
> - Mistral → `MISTRAL_API_KEY`
> - Cohere → `COHERE_API_KEY`

For each selected local provider, ask only the base URL (prefilled):

- Ollama → `http://localhost:11434`
- llama.cpp → `http://localhost:8080`
- vLLM → `http://localhost:8000/v1` + env_var for the arbitrary key (vLLM's API-key check is a string match — any value works)
- LM Studio → `http://localhost:1234/v1`

## Section 3 — Preview + write

Render the generated yaml and show it to the user:

> `AskUserQuestion`: Review the generated config. Write it to `~/.agent-skills/auth/auth.yaml`?
> Options: Write it · Edit before writing · Cancel

On **Write it**:

```bash
mkdir -p ~/.agent-skills/auth
chmod 700 ~/.agent-skills/auth
# If a previous file exists, back it up first
if [ -f ~/.agent-skills/auth/auth.yaml ]; then
    cp ~/.agent-skills/auth/auth.yaml ~/.agent-skills/auth/auth.yaml.bak.$(date +%Y%m%d-%H%M%S)
fi
# Write via an intermediate file then move, so a failed write never leaves a half-written config
tmp=$(mktemp)
cat > "$tmp" <<'YAML'
<generated yaml>
YAML
chmod 600 "$tmp"
mv "$tmp" ~/.agent-skills/auth/auth.yaml
```

Post-write: run a **dry validation** — for each source entry, call its `validate` command and report the result. Do **not** run preauth during the interview; just check whether the session is already good. Show a table like:

```
source       provider         validate           result
aws          onepassword      aws sts get-...    ✗ (not yet authenticated — preauth will run on first use)
azure        oauth_interactive az account show   ✓ (already logged in)
sharepoint   oauth_interactive m365 status       ✗ (run `m365 login` once to establish)
smb          script           mount | grep ...   ✗ (will mount on first use)
```

Tell the user: "Non-✓ rows aren't errors — preauth will run when the skill first needs that source. But if a source fails repeatedly, re-run `auth-interview` to fix the config."

For model providers, do the same dry validation: try to resolve each entry (run the lookup, check the env var gets a non-empty value) and report. Do not print the actual values — just "resolved" vs "failed" vs "needs unlock (e.g. `bw unlock`)."

For `provider: subscription` entries, validation is different:

- If a `validate:` command was supplied, run it and report ✓/✗.
- If no `validate:` was supplied, report `subscription (no offline check; verify by running the CLI itself)`.
- **Never** flag a subscription entry as failed because there's no API key to expand — that's the whole point of the subscription provider type. The post-write summary should make this clear with a note: *"Subscription entries don't expose an API key. `auth-config` will return `subscription_no_api_key` to callers asking for one. Skills that run inside the subscribing CLI inherit access transparently."*

## Section 4 — Update mode

If `auth.yaml` already exists and the user picked "add a new entry" or "modify existing":

- **Add**: skip to the relevant section and add the new entry. Preserve all other entries.
- **Modify**: `AskUserQuestion`: which entry to modify? Show existing keys under `sources:` and `model_providers:`. Re-ask that entry's questions; replace the entry in the yaml; preserve the rest. Always back up to `.bak.<timestamp>` before writing.
- **Start over**: back up, then run the full interview.

## Edge cases

- **User picks a vault whose CLI isn't installed.** Don't fail silently. Tell them what to install (link the install command) and offer to continue anyway (they'll see `validate` errors later) or switch to another provider.
- **User has multiple 1Password accounts.** If `op account list` returns more than one, ask which to use and record it as `account:` in the entry.
- **User is on Windows + says "macOS Keychain" (or vice versa).** The question should have been filtered by OS; if it wasn't, warn and re-ask.
- **User wants per-repo overrides.** Mention `<repo>/.agent-skills-auth.yaml` at the end of the interview but don't ask about it — override files are typically set up per-project later, not during global bootstrap.
- **Headless / CI context.** If `stdin` isn't a TTY or `AskUserQuestion` isn't available, refuse to run and emit an example yaml the user can copy. Never write a half-filled config in non-interactive mode.

## What this skill does NOT do

- **No credential entry.** Never asks the user to type a password, API key, or token. The whole point is that credentials live in their vault; we only record *where* to look.
- **No vault-side writes.** Never creates items in 1Password / Bitwarden / etc. If the user's vault doesn't have the item yet, tell them to create it and come back.
- **No shell-init edits.** Doesn't touch `~/.zshrc`, `~/.bashrc`, `~/.envrc`, or shell-integration scripts. If the user picked `provider: env`, they manage the env var themselves.
- **No skill-sync changes.** `auth-interview` is global-scope and does not run `skill-sync` or touch `~/.claude/skill-sync.config.yaml`.

## Follow-up after interview

Tell the user:

1. **File is at `~/.agent-skills/auth/auth.yaml`, permissions 0600.**
2. **The ATO source skills (and any future external-resource skill) will read this file before making credentialed calls.** If a source isn't listed, those skills fall back to ambient session.
3. **To add or change entries later, re-run this skill.** It supports incremental updates.
4. **Never commit the file.** It's outside every repo by design, but if you move or symlink it, keep it out of git.
