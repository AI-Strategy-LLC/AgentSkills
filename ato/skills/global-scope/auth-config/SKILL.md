---
name: auth-config
description: "Resolve credentials for external resources (AWS, Azure, SharePoint/M365, SMB, model-provider APIs) via `~/.agent-skills/auth/auth.yaml`. Supports 1Password, Bitwarden, LastPass, Keeper, HashiCorp Vault, macOS Keychain, Windows Credential Manager, Linux libsecret, OAuth interactive flows, env vars, user scripts, and consumer subscription sessions (e.g., Claude Pro/Max/Team via the `claude` CLI — returns `subscription_no_api_key` when callers ask for an API key). Use when a skill is about to make a credentialed external call (AWS/Azure/SharePoint/SMB discovery, LLM API call from a multi-model agent) and needs to validate the session first. Read-only — never writes credentials."
---

# Auth Config

This skill is the **credential resolver** that other skills call into before making external calls. It reads a user-owned config file, runs whichever vault / script / OAuth flow the user chose, validates the session, and either returns control to the caller or halts with an actionable error.

It never stores, rotates, or transmits credentials. It only reads the user's config and invokes the CLI the user already has installed.

## Config file location

- `~/.agent-skills/auth/auth.yaml` — user-global, required permissions `0600` (user read/write only)
- `<repo>/.agent-skills-auth.yaml` — optional per-repo override (fields merge onto the global file; array fields like `sources.aws.items` replace wholesale)

If the global file exists with permissions looser than `0600`, this skill **refuses to read it** and tells the user to `chmod 0600 ~/.agent-skills/auth/auth.yaml`. Credentials in a world-readable file is treated as a hard error, not a warning.

If no file exists at all, this skill returns a `no-config` signal and the caller may choose to fall back to ambient session. It does not bootstrap a config — for that, invoke `auth-interview`.

## Schema

Top-level keys:

```yaml
version: 1                    # schema version; current = 1
default_vault: onepassword    # optional; if a source/provider omits `provider`, this is used
sources: {}                   # external cloud / data sources used by collection skills
model_providers: {}           # LLM API keys used by multi-model agent frameworks
```

### Sources

Each entry under `sources` describes how to establish ambient authentication for one external scope before a collection skill runs against it.

```yaml
sources:
  <source-name>:             # e.g. aws, azure, sharepoint, smb
    provider: <type>         # one of the provider types below
    # <type-specific fields>
    validate: <command>      # REQUIRED — shell command that exits 0 when the session is ready
    validate_timeout: 15     # optional; seconds before `validate` is considered failed (default 30)
```

The lifecycle a consumer runs:

1. **Permission check** — confirm `~/.agent-skills/auth/auth.yaml` is `0600`.
2. **Quick validate** — run `validate`. If it already exits 0, the session is good, skip to step 4.
3. **Preauth** — run the provider-specific command(s) to establish the session. For OAuth flows, this may prompt the user (device code, browser).
4. **Re-validate** — run `validate` again. If it still fails, halt with the `validate` command's stderr.
5. **Proceed** — hand control back to the caller with the ambient session ready.

### Model providers

Each entry under `model_providers` describes where an API key for one LLM provider lives. Consumers (multi-model agent frameworks like opencode, TokenRing Coder, OpenDevin) look up the key, export it under the named env var, and call the provider's SDK/CLI.

```yaml
model_providers:
  <provider-name>:           # e.g. anthropic, openai, groq, huggingface, ollama
    provider: <type>         # one of the provider types below
    # <type-specific fields>
    env_var: <NAME>          # env var to export the fetched value into
    base_url: <url>          # optional; for local or self-hosted endpoints
```

For purely local providers (Ollama, llama.cpp, vLLM) with no API key, use `provider: none` and just set `base_url`.

For consumer-subscription access (Claude Pro/Max/Team via the `claude` CLI; ChatGPT via Codex CLI; Gemini via personal Google account), use `provider: subscription`. There is no API key to extract — the subscription session lives in the CLI's own store. When a caller asks `auth-config` to resolve such an entry into an env var, it returns the typed error `subscription_no_api_key`. Skills running inside the subscribing CLI itself inherit access transparently and don't need the env var; skills that need raw API access must halt with a clear message naming the user's options (add a separate `provider: env` / `onepassword` / etc. entry pointing at an API key, or accept that the skill cannot run for subscription-only users).

## Provider types

See `references/providers.md` for the full cheatsheet. Summary:

| Type | What the user needs installed | Typical use |
|---|---|---|
| `onepassword` | `op` CLI (1Password) | Fields or template injection |
| `bitwarden` | `bw` CLI + unlocked session | Get item field |
| `lastpass` | `lpass` CLI | Legacy; `lpass show` |
| `keeper` | Keeper Commander | `keeper get` record field |
| `vault` | HashiCorp `vault` CLI | `vault kv get -field=<f> <path>` |
| `macos_keychain` | macOS `security` (built-in) | Generic or internet password |
| `windows_cred_manager` | `cmdkey` or PowerShell `Get-StoredCredential` | Credential Manager entries |
| `linux_secret_tool` | `secret-tool` (libsecret) or `kwallet-query` | GNOME Keyring / KWallet |
| `oauth_interactive` | The scoped CLI itself (`az login`, `m365 login`) | Device code / browser flow |
| `env` | Nothing | Value already exported in shell |
| `script` | Whatever the script needs | Escape hatch — arbitrary command |
| `none` | Nothing | No authentication required |
| `subscription` | The provider's CLI (`claude`, `codex`, `gemini`) | Consumer subscription session (e.g., Claude Pro/Max). Returns `subscription_no_api_key` when callers ask for an API key — callers either skip (running inside the subscribing CLI) or fail loudly with guidance to add a separate API-key entry. |

**Apple Passwords gotcha.** The Apple Passwords app on macOS does not expose a CLI. Data is synced into the macOS Keychain but not programmatically guaranteed to be there — especially for items created directly in Passwords rather than migrated from Keychain. If a credential lives in Apple Passwords only, the user must either (a) duplicate it into macOS Keychain (`security add-generic-password ...`) or (b) pick a different vault. `auth-interview` surfaces this warning when the user selects macOS Keychain.

## Consumer contract

A skill that needs to authenticate against an external source should implement this sequence:

```bash
AUTH_FILE=~/.agent-skills/auth/auth.yaml

# 1. Permission check
if [ -f "$AUTH_FILE" ]; then
    perms=$(stat -f '%Lp' "$AUTH_FILE" 2>/dev/null || stat -c '%a' "$AUTH_FILE")
    if [ "$perms" != "600" ]; then
        echo "ERROR: $AUTH_FILE has permissions $perms; expected 600." >&2
        echo "Run: chmod 600 $AUTH_FILE" >&2
        exit 2
    fi
fi

# 2. If no file, fall back to ambient session (caller decides whether that's ok)
# 3. Otherwise, resolve the source entry, run preauth if `validate` fails,
#    then re-run validate. On still-failing validate, halt.
```

For yaml parsing, prefer `yq` (`brew install yq`) if available. If not, the skill asks the user once and records the answer. Never ship a Python/Node dependency for parsing — use the system `yq` or a tiny Bash parser that handles the documented schema shapes.

## Config file contract

- **Permissions.** Always `0600`. `auth-interview` sets this on write. `auth-config` refuses to read otherwise.
- **Contents.** May contain raw secrets (when the user picks `env` with a literal value, or inline tokens). That is why the `0600` rule is non-negotiable.
- **Commit policy.** Never commit `auth.yaml` to any repo. `auth-interview` adds `~/.agent-skills/auth/` to `.gitignore` when bootstrapping a new repo, but the file is outside every repo by design.
- **Per-repo override.** `<repo>/.agent-skills-auth.yaml` is the only approved per-repo location. It follows the same `0600` rule. Do not read `<repo>/.claude/**` for credentials.

## What this skill does NOT do

- **No credential rotation.** If the user's token is expired, the `validate` step fails and the caller halts. The user refreshes in their vault; this skill re-resolves on the next invocation.
- **No password extraction for display.** Even internally, fetched values are not logged, printed, or surfaced to the caller. The only observable effect is that the ambient session is authenticated or an env var is set.
- **No fallback chains.** One provider per entry. If a user wants "try 1Password, fall back to Keychain," they write a `script:` that does that.
- **No MFA orchestration.** If the provider CLI needs MFA (e.g. 1Password biometric unlock), the user deals with that interactively when preauth runs. Automating MFA is a future concern.

## Forward compatibility

The `provider` field is an open enum. A future plugin system (Approach C in the design discussion) will load provider implementations from `~/.agent-skills/auth/plugins/<type>.sh` — existing typed providers will continue to work without changes. When designing new provider types, keep the schema flat (no nested objects beyond one level) so a UI layer can render the form without custom logic.
