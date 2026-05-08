# auth.yaml schema

Canonical example — every shape the schema supports, with inline comments.

```yaml
# ~/.agent-skills/auth/auth.yaml
# -----------------------------------------------------------------------------
# Permissions MUST be 0600. This file may contain secrets depending on the
# provider types you chose. Never commit it. Never share it.
#   chmod 600 ~/.agent-skills/auth/auth.yaml
# -----------------------------------------------------------------------------

version: 1

# Optional: default vault used when a source/provider omits `provider:`.
# If unset and the entry has no `provider:`, reading that entry fails.
default_vault: onepassword

# =============================================================================
# External cloud / data sources
# Consumed by ato-source-aws, ato-source-azure, ato-source-sharepoint,
# ato-source-smb, and any future skill that authenticates against an external
# resource. Lifecycle: validate → (preauth if needed) → re-validate → proceed.
# =============================================================================
sources:

  # ---------------------------------------------------------------------------
  # AWS — example: 1Password template injection
  # ---------------------------------------------------------------------------
  aws:
    provider: onepassword
    account: my.1password.com          # omit if you only have one account
    template: ~/Library/AWS/awsauth.sh.tpl
    validate: aws sts get-caller-identity
    validate_timeout: 15

  # Alternative: script-based AWS auth (comment-in to use)
  # aws:
  #   provider: script
  #   command: aws-okta exec prod --
  #   validate: aws sts get-caller-identity

  # ---------------------------------------------------------------------------
  # Azure — OAuth interactive (az login device code)
  # ---------------------------------------------------------------------------
  azure:
    provider: oauth_interactive
    login_command: az login
    validate: az account show

  # ---------------------------------------------------------------------------
  # SharePoint / M365 — OAuth interactive (m365 device code)
  # ---------------------------------------------------------------------------
  sharepoint:
    provider: oauth_interactive
    login_command: m365 login
    validate: m365 status

  # ---------------------------------------------------------------------------
  # SMB — user-provided mount script
  # ---------------------------------------------------------------------------
  smb:
    provider: script
    command: ~/.agent-skills/auth/mount-smb.sh
    validate: mount | grep -q 'fileshare.example.com'

# =============================================================================
# Model providers
# Consumed by multi-model agent frameworks (opencode, TokenRing Coder,
# OpenDevin, Aider, continue.dev, …). Each entry is resolved to an env var
# the framework reads. Local providers use `provider: none` + base_url.
# =============================================================================
model_providers:

  # ---------------------------------------------------------------------------
  # Anthropic — 1Password single-value lookup
  # ---------------------------------------------------------------------------
  anthropic:
    provider: onepassword
    op_path: op://Private/Anthropic/api_key
    env_var: ANTHROPIC_API_KEY

  # ---------------------------------------------------------------------------
  # OpenAI — already exported by the user's shell (direnv, envchain, etc.)
  # ---------------------------------------------------------------------------
  openai:
    provider: env
    env_var: OPENAI_API_KEY

  # ---------------------------------------------------------------------------
  # Google Gemini — macOS Keychain
  # ---------------------------------------------------------------------------
  gemini:
    provider: macos_keychain
    kind: generic
    service: google-gemini-api
    account: alastair@example.com
    env_var: GOOGLE_API_KEY

  # ---------------------------------------------------------------------------
  # Groq — Bitwarden
  # ---------------------------------------------------------------------------
  groq:
    provider: bitwarden
    item: Groq API
    field: password
    env_var: GROQ_API_KEY

  # ---------------------------------------------------------------------------
  # HuggingFace — Vault
  # ---------------------------------------------------------------------------
  huggingface:
    provider: vault
    path: secret/data/tokens/huggingface
    field: token
    env_var: HF_TOKEN

  # ---------------------------------------------------------------------------
  # Mistral — script (arbitrary pattern)
  # ---------------------------------------------------------------------------
  mistral:
    provider: script
    command: op read op://Private/Mistral/api_key
    env_var: MISTRAL_API_KEY

  # ---------------------------------------------------------------------------
  # Cohere — Linux libsecret
  # ---------------------------------------------------------------------------
  cohere:
    provider: linux_secret_tool
    backend: libsecret
    attributes:
      service: cohere-api
      account: alastair
    env_var: COHERE_API_KEY

  # ---------------------------------------------------------------------------
  # Local Ollama — no key, just a base URL
  # ---------------------------------------------------------------------------
  ollama:
    provider: none
    base_url: http://localhost:11434

  # ---------------------------------------------------------------------------
  # Local llama.cpp server — no key
  # ---------------------------------------------------------------------------
  llamacpp:
    provider: none
    base_url: http://localhost:8080

  # ---------------------------------------------------------------------------
  # Local vLLM / LM Studio — API-key-compatible, but key is arbitrary
  # ---------------------------------------------------------------------------
  vllm:
    provider: env
    env_var: VLLM_API_KEY           # user sets to any string; vLLM accepts it
    base_url: http://localhost:8000/v1
```

## Per-repo override

A repo may ship `<repo>/.agent-skills-auth.yaml` to override specific entries (e.g. point AWS to a different 1Password item for this project). Override rules:

- Same `0600` permission requirement.
- Top-level keys merge: an override's `sources.aws` replaces the global `sources.aws` wholesale (no deep merge — too error-prone with multiple fields).
- Override entries that reference `script:` use paths relative to the repo root.
- Missing entries in the override inherit from the global file unchanged.

```yaml
# <repo>/.agent-skills-auth.yaml
version: 1
sources:
  aws:
    provider: onepassword
    template: ./auth/customer-X-aws.sh.tpl   # repo-relative
    validate: aws sts get-caller-identity
```

## Validation

The schema is intentionally loose (no JSON Schema artifact shipped). `auth-config` validates just two invariants on read:

1. `version:` is `1`.
2. Every entry has a `provider:` (or `default_vault` covers it).

Per-provider fields are validated lazily — only when that entry is actually consumed. A misconfigured `keeper:` entry doesn't fail until a skill tries to use it.
