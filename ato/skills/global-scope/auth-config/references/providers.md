# Provider cheatsheet

For each provider type in `auth.yaml`, this file documents:

- **CLI to install** — what the user needs before this provider works
- **Schema fields** — the yaml keys beyond `provider:`
- **How the consumer uses it** — the actual shell command expansion
- **Source mode** (for `sources.*`) vs **Key-lookup mode** (for `model_providers.*`)

Conventions used in examples: `$KEY` is the env var the caller wants set; `<item>` / `<field>` are user-supplied identifiers.

---

## `onepassword` — 1Password

**Install:** `brew install 1password-cli` (macOS) / `apt install 1password-cli` / see 1password.com/downloads/command-line.

**Schema:**

```yaml
provider: onepassword
account: my.1password.com      # optional; if user has multiple accounts
# Option A — template injection (for sources with multiple env vars at once)
template: ~/Library/AWS/awsauth.sh.tpl
# Option B — single-value lookup (for model_providers)
op_path: op://Private/Anthropic/api_key
```

**Source mode expansion (Option A):**

```bash
op inject -i <template> | bash
```

Template file example (`awsauth.sh.tpl`):

```bash
export AWS_ACCESS_KEY_ID="{{ op://Private/AWS-Prod/access_key_id }}"
export AWS_SECRET_ACCESS_KEY="{{ op://Private/AWS-Prod/secret_access_key }}"
export AWS_SESSION_TOKEN="{{ op://Private/AWS-Prod/session_token }}"
```

**Key-lookup mode expansion (Option B):**

```bash
export $env_var="$(op read <op_path>)"
```

**Gotchas:** `op` prompts for biometric unlock on first use per session. In headless contexts, set `OP_SERVICE_ACCOUNT_TOKEN` (user configures out-of-band; we don't store it).

---

## `bitwarden` — Bitwarden

**Install:** `brew install bitwarden-cli` / `npm i -g @bitwarden/cli`.

**Schema:**

```yaml
provider: bitwarden
item: AWS-Prod                 # item name or id
field: password                # username | password | totp | notes | fields.<name>
session_env: BW_SESSION        # optional; env var holding the unlock session (default BW_SESSION)
```

**Expansion:**

```bash
# Precondition: user has exported BW_SESSION via `bw unlock --raw` in their shell
export $env_var="$(bw get $field <item>)"
```

**Gotchas:** Requires `bw unlock` before the session can read items. If `$BW_SESSION` is unset, preauth should halt with: "Run `export BW_SESSION=\"\$(bw unlock --raw)\"` and retry."

---

## `lastpass` — LastPass (legacy)

**Install:** `brew install lastpass-cli` / `apt install lastpass-cli`.

**Schema:**

```yaml
provider: lastpass
item: AWS-Prod
field: password                # password | username | notes
```

**Expansion:**

```bash
# Precondition: `lpass login <email>` has been run in this shell
export $env_var="$(lpass show --$field <item>)"
```

**Note:** LastPass CLI has seen reduced investment; several orgs are migrating. Keep the typed provider for existing users, but don't recommend it for new setups.

---

## `keeper` — Keeper Enterprise / Commander

**Install:** `pip install keepercommander` (Keeper's CLI is Python-based).

**Schema:**

```yaml
provider: keeper
record: AWS-Prod               # record UID or title
field: password                # password | login | url | note | custom.<name>
```

**Expansion:**

```bash
# Precondition: `keeper` is logged in (persistent config in ~/.keeper)
export $env_var="$(keeper get <record> --field <field>)"
```

**Gotchas:** Commander uses a local `.keeper/config.json`; MFA/SSO configured there once and reused.

---

## `vault` — HashiCorp Vault

**Install:** `brew install vault`.

**Schema:**

```yaml
provider: vault
address: https://vault.example.com     # optional; else $VAULT_ADDR
path: secret/data/aws/prod             # KV v1: secret/aws/prod; KV v2: secret/data/aws/prod
field: access_key_id
```

**Expansion:**

```bash
# Precondition: VAULT_TOKEN is set (user ran `vault login <method>` already)
export $env_var="$(vault kv get -field=<field> <path>)"
```

**Gotchas:** Vault auth itself is out-of-band. For dynamic AWS/Azure credentials (Vault's AWS secrets engine), combine with a `script:` entry that calls `vault read aws/creds/<role>` and parses the JSON.

---

## `macos_keychain` — macOS Keychain

**Install:** Nothing — `security` is built into macOS.

**Schema:**

```yaml
provider: macos_keychain
kind: generic                  # generic | internet
service: anthropic-api         # for generic
# or:
server: api.openai.com         # for internet
account: alastair
```

**Expansion (generic):**

```bash
export $env_var="$(security find-generic-password -s <service> -a <account> -w)"
```

**Expansion (internet):**

```bash
export $env_var="$(security find-internet-password -s <server> -a <account> -w)"
```

**Apple Passwords gotcha:** Items created in the Apple Passwords app (macOS 14+) are NOT guaranteed to appear in the legacy Keychain that `security` reads. If a user chose `macos_keychain`, `auth-interview` prompts them to verify the item is accessible by running `security find-generic-password -s <service> -a <account>` before saving the config. If that fails, the user should either (a) duplicate the credential into Keychain via `security add-generic-password -s <service> -a <account> -w <value>`, or (b) pick a different provider.

---

## `windows_cred_manager` — Windows Credential Manager

**Install:** Nothing — `cmdkey` is built in; `Get-StoredCredential` requires the `CredentialManager` PowerShell module (`Install-Module CredentialManager`).

**Schema:**

```yaml
provider: windows_cred_manager
target: anthropic-api          # the Target name in Credential Manager
```

**Expansion (PowerShell):**

```powershell
$cred = Get-StoredCredential -Target <target>
$env:<env_var> = $cred.GetNetworkCredential().Password
```

**Gotchas:** Credential Manager distinguishes Generic / Web / Windows credentials. This provider targets Generic. For Windows credentials used in RDP/SMB, see the `smb:` patterns below.

---

## `linux_secret_tool` — libsecret (GNOME Keyring, KeePassXC-libsecret, others)

**Install:** `apt install libsecret-tools` / `dnf install libsecret` (GNOME) or `apt install kwalletcli` (KDE).

**Schema (libsecret):**

```yaml
provider: linux_secret_tool
backend: libsecret             # libsecret | kwallet
attributes:                    # arbitrary key/value attribute match
  service: anthropic-api
  account: alastair
```

**Expansion (libsecret):**

```bash
export $env_var="$(secret-tool lookup service <service> account <account>)"
```

**Expansion (KWallet):**

```bash
export $env_var="$(kwallet-query -f <folder> -r <entry> <wallet>)"
```

**Gotchas:** Requires the user's desktop session to have unlocked the keyring (usually happens at login). On headless servers, this provider won't work — use `script:` with a keyring-unlock helper.

---

## `oauth_interactive` — CLI-driven OAuth flows

**Install:** Whatever CLI handles the flow (`az`, `m365`, `gh`, `gcloud`).

**Schema:**

```yaml
provider: oauth_interactive
login_command: az login        # or `m365 login`, `gcloud auth login`, `gh auth login`
logout_command: az logout      # optional; only used on user request
```

**Source mode expansion:**

```bash
# Only runs if `validate` initially failed
<login_command>
```

**Gotchas:** These CLIs may open a browser or show a device code. The preauth step is interactive by definition. Halt with a clear message if the CLI is not installed. **Never** automate OAuth credential extraction — the whole point is that the user's session lives in the CLI's own store (`~/.azure`, `~/.config/m365/`, etc.).

---

## `env` — Already in environment

**Install:** Nothing.

**Schema:**

```yaml
provider: env
env_var: ANTHROPIC_API_KEY     # for model_providers, this is both input and the consumer's expected var
```

**Expansion:** No-op. The validate step checks `[ -n "$ANTHROPIC_API_KEY" ]` or runs a canary API call.

**Use when:** The user manages env vars via `direnv`, `envchain`, a `.envrc`, or shell init — and doesn't want this skill touching their setup.

---

## `script` — Arbitrary command (escape hatch)

**Install:** Whatever the script needs.

**Schema:**

```yaml
provider: script
command: <shell command>       # for source mode: run for side effect
                               # for key-lookup mode: stdout is the credential value
env_var: <NAME>                # for key-lookup mode only
```

**Source mode expansion:**

```bash
eval "<command>"               # runs in a subshell; exports propagate if user uses `export`
```

**Key-lookup mode expansion:**

```bash
export $env_var="$(<command>)"
```

**Use when:** The user's vault isn't on the typed list, or they want a chain (try X then Y), or they have a pre-existing `azureauth.sh` / `get-aws-creds` / `keychain-wrap` script.

**Example patterns to show as comments in `auth.yaml`:**

```yaml
# --- 1Password service account (headless CI-friendly) ---
# provider: script
# command: op inject -i ~/Library/AWS/awsauth.sh.tpl | bash
# validate: aws sts get-caller-identity

# --- Dashlane (no CLI — via their sharing URL + `curl`, brittle) ---
# provider: script
# command: ~/.agent-skills/auth/dashlane-wrapper.sh aws-prod
# validate: aws sts get-caller-identity

# --- CyberArk (Central Credential Provider via psPAS / REST) ---
# provider: script
# command: |
#   response=$(curl -s -H "Authorization: $CYBERARK_TOKEN" \
#     "https://cyberark.example.com/PasswordVault/api/Accounts/<id>/Password/Retrieve")
#   export AWS_ACCESS_KEY_ID=$(echo "$response" | jq -r .content)
# validate: aws sts get-caller-identity

# --- Keeper Commander (same as typed `keeper` provider, shown for completeness) ---
# provider: script
# command: |
#   export AWS_ACCESS_KEY_ID=$(keeper get AWS-Prod --field login)
#   export AWS_SECRET_ACCESS_KEY=$(keeper get AWS-Prod --field password)
# validate: aws sts get-caller-identity

# --- Vault with AWS secrets engine (dynamic creds) ---
# provider: script
# command: |
#   creds=$(vault read -format=json aws/creds/prod-role)
#   export AWS_ACCESS_KEY_ID=$(echo "$creds" | jq -r .data.access_key)
#   export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | jq -r .data.secret_key)
#   export AWS_SESSION_TOKEN=$(echo "$creds" | jq -r .data.security_token)
# validate: aws sts get-caller-identity

# --- SailPoint IdentityIQ-issued AWS key from IdentityNow API (org-specific) ---
# provider: script
# command: ~/bin/sailpoint-aws-fetch prod
# validate: aws sts get-caller-identity
```

---

## `none` — No authentication

**Install:** Nothing.

**Schema:**

```yaml
provider: none
base_url: http://localhost:11434   # required for local model providers
```

**Use when:** A local LLM server (Ollama, llama.cpp, vLLM, LM Studio) runs on localhost with no auth, or a source is fully open. For model providers, the consumer sets `<PROVIDER>_BASE_URL=<base_url>` and omits the API key.

---

## `subscription` — Provider access via a consumer subscription, no API key

**Install:** Whatever CLI manages the subscription session (`claude` for Claude Pro/Max/Team; `codex` for ChatGPT Plus/Team if Codex CLI is installed; `gemini` for AI Studio personal).

**Schema:**

```yaml
provider: subscription
cli: claude                    # claude | codex | gemini | <other>
plan: max                      # optional, free-form: pro | max | team | enterprise
validate: claude --version     # optional; caller-supplied check that the CLI is installed
                               # (most subscription CLIs have no offline auth-check command)
note: |                        # optional; surfaced in error messages to callers
  Anthropic auth is via Claude Pro/Max subscription managed by the
  `claude` CLI. There is no separate API key — skills that require
  raw API access must use a different provider entry or skip.
```

**Source mode expansion:** No-op. Subscription credentials live inside the CLI's own session store (`~/.claude/`, `~/.codex/`, etc.). The CLI manages refresh and re-auth itself.

**Key-lookup mode:** **Unsupported.** A subscription session does NOT expose an API key. When `auth-config` is asked to resolve a model-provider entry whose `provider: subscription`, it returns a typed error: `subscription_no_api_key`. Callers handle this in one of two ways:

1. **Skip** — the caller is itself running inside the subscribing CLI (e.g., a Claude Code skill calling Anthropic) and inherits the subscription's model access transparently. No env var is needed; the parent runtime has already provisioned the model.
2. **Fall back** — the caller needs raw API access (e.g., a multi-model agent that fans out to Claude as one of several models from a non-Claude harness). It should fail loudly with a clear message naming the user's options: add a separate `provider: env` / `provider: onepassword` / etc. entry pointing at an API key, or accept that this skill cannot run for subscription-only users.

**Validation:** When `validate:` is provided, run it; non-zero exit means the CLI is not installed / not logged in. When omitted, validation is a no-op (most subscription CLIs lack a portable offline auth-check command). The validation step never tries to extract a key.

**Use when:** The user pays for the provider via a consumer subscription (Claude Pro / Max / Team; ChatGPT Plus / Team via the Codex CLI's auth flow; Gemini via Google account) and uses the provider's own CLI rather than a separate API workspace. **Common for individual developers and small teams** — subscription-only access is often the cheapest path to the underlying model and is increasingly the default for Claude Code users.

**Gotchas:**

- Don't pair `provider: subscription` with `env_var:`. Subscriptions don't produce a key to export. If the user actually has both a subscription AND a separate API key, model that as two separate entries (e.g., `anthropic_subscription:` + `anthropic_api:`) and let consumers pick.
- The `cli:` field is informational; this skill never invokes the CLI on the user's behalf. If the CLI's session is missing or expired, the caller surfaces that and the user runs `/login` (Claude Code), `codex login`, etc., themselves.
- Subscription terms vary by provider — quota, rate limits, and which models are accessible. The config records *which* subscription, not its terms; callers should not assume any particular model is available.

---

## Enterprise PAM tools NOT yet typed

These appear in the PasswordTools survey but don't have a typed provider yet. Use `script:` with the pattern sketched in the comment, or request a typed provider by opening an issue:

- **Dashlane Business** — no first-class CLI; script pattern uses their browser extension's export or the `dcli` community tool
- **CyberArk** — covered via `script:` with REST retrieval (see `script` examples)
- **SailPoint IdentityIQ / IdentityNow** — script pattern calls their identity API to retrieve broker-issued creds
- **Rippling / Okta** — for SSO-federated AWS, use `script:` around `aws-okta`, `aws-sso-util`, or `granted`
- **OpenText NetIQ / Omada / Fischer Identity / Specops / Dell Password Manager / Bravura Pass / ManageEngine ADSelfService / Namescape / Netwrix / JiJi / Certero Passworks / Activate IAM** — these are self-service password reset tools for human AD/SSO passwords, not CLI-accessible API-key vaults. If your org uses one of these for human login and a separate tool for API keys, type the API-key vault here and leave the SSPR out of scope.
