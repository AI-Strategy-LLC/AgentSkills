# ATO Artifact Collector — Config Schema

This file describes the YAML configuration format read by Step 0 (Scope Selection)
of the `ato-artifact-collector` skill.

## File locations and precedence

Config is read from two places and merged **shallowly per source**:

1. **User defaults** — `~/.claude/skills/ato-artifact-collector/config.yaml`
   Used across every repository. Good place for tenant IDs, account numbers,
   default region lists — values that rarely change.
2. **Repo override** — `.ato-package.yaml` at the repo root.
   Per-repo scope. This file should be listed in `.gitignore` by default; the
   user can choose to commit it if their team shares scope across the whole
   repo.

**Merge rule: shallow per source.** If the repo file declares a `sharepoint:`
block, it fully replaces the user file's `sharepoint:` block — no deep merge,
no field-by-field overlay. This avoids surprises where a user's default site
list bleeds into a repo that deliberately scoped itself down.

If neither file exists, the skill prompts interactively in Step 0 and runs
repo-only if the user declines every external source.

## Full schema

```yaml
# ~/.claude/skills/ato-artifact-collector/config.yaml
# or .ato-package.yaml at repo root

version: 1                                    # Schema version. Must be 1.

sharepoint:
  enabled: true                               # If false, skip and don't prompt.
  tenant: contoso                             # {tenant}.sharepoint.com
  sites:                                      # List of SharePoint site URLs.
    - https://contoso.sharepoint.com/sites/ato
    - https://contoso.sharepoint.com/sites/security-policies
  libraries:                                  # REQUIRED: explicit document libraries per site.
                                              # Sites can have multiple libraries (default
                                              # 'Documents' plus org-created ones like
                                              # 'ATO Evidence', 'Compliance', 'Site Assets').
                                              # Listing only the default library silently
                                              # misses evidence stored elsewhere — the kind
                                              # of failure that's invisible until an assessor
                                              # asks for a doc the package doesn't have.
                                              # If the user doesn't know the library names,
                                              # they can answer `list` interactively and the
                                              # orchestrator will fetch them via
                                              # `m365 spo list list` (filter BaseTemplate=101).
    https://contoso.sharepoint.com/sites/ato:
      - Documents
      - ATO Evidence
      - Compliance
    https://contoso.sharepoint.com/sites/security-policies:
      - Documents
  folders:                                    # OPTIONAL: per-(site, library) folder filter.
                                              # When omitted for a (site, library) pair, the
                                              # entire library is scanned recursively.
                                              # Folder paths are relative to the library root
                                              # (e.g., 'Current ATO' under 'Documents' library
                                              # resolves to /sites/ato/Shared Documents/Current ATO).
    https://contoso.sharepoint.com/sites/ato:
      Documents:
        - /Current ATO
        - /POA&M
      ATO Evidence:
        - /2026 Q1
      # 'Compliance' library has no folder filter — scan the whole library.
  file_types:                                 # Optional: restrict extensions.
    - .docx
    - .pdf
    - .xlsx
    - .md
  auth:                                       # How the sibling should obtain ambient auth.
    method: device-code                       # device-code | interactive | service-account | existing
    # device-code    → m365 login --authType deviceCode (default; interactive user flow)
    # interactive    → m365 login --authType browser   (opens browser on the host)
    # service-account → expect m365 session already established for an app/service identity;
    #                   the sibling will NOT log in, only verify via `m365 status`
    # existing       → assume m365 is already logged in; sibling only calls `m365 status`
    account_hint: ato-bot@contoso.onmicrosoft.com   # Optional: shown in confirm prompt
    login_instruction: |                      # Optional override: shown on auth_missing failure.
      Run: m365 login --authType deviceCode --appId <your app>

aws:
  enabled: true
  accounts:                                   # AWS account IDs in scope.
    - "123456789012"
  regions:                                    # Must be on US allow list.
    - us-east-1
    - us-gov-west-1
  services:                                   # Optional: narrow discovery.
    - iam
    - config
    - cloudtrail
    - securityhub
    - guardduty
    - s3
    - kms
  auth:                                       # How the sibling should obtain ambient auth.
    method: sso                               # sso | profile | env | instance
    # sso       → IAM Identity Center / AWS SSO via `aws sso login --profile {profile}`
    # profile   → named profile in ~/.aws/credentials (long-lived keys — discouraged)
    # env       → AWS_ACCESS_KEY_ID / AWS_SESSION_TOKEN already in the environment
    # instance  → running on EC2/ECS/Lambda with an instance profile
    profile: ato-read                         # Required for sso and profile methods.
    sso_start_url: https://my-sso.awsapps.com/start   # Optional: shown on auth failure.
    region: us-east-1                         # Optional default CLI region (not scope).
    login_instruction: |                      # Optional override for the auth_missing message.
      Run: aws sso login --profile ato-read

azure:
  enabled: true
  subscriptions:                              # Subscription IDs in scope.
    - 00000000-0000-0000-0000-000000000000
  resource_groups:                            # Optional filter.
    - app-prod
    - app-shared
  regions:                                    # Must be on US allow list.
    - eastus
    - usgovvirginia
  tag_filter:                                 # Optional: only tagged resources.
    environment: production
  auth:                                       # How the sibling should obtain ambient auth.
    method: device-code                       # device-code | interactive | helper | existing
    # device-code → `az login --use-device-code` (works over SSH, CI, no browser)
    # interactive → `az login` (opens a browser on the host)
    # helper      → run a user-supplied command that leaves `az` logged in
    # existing    → assume `az account show` already succeeds; sibling only probes it
    helper_command: ~/Applications/bin/azureauth   # Required when method=helper. User-owned
                                              # script; sibling invokes it but never reads
                                              # its contents. Examples: a script that pulls
                                              # creds from 1Password and runs `az login`, or
                                              # an org-provided wrapper like `azureauth`.
    tenant: 00000000-0000-0000-0000-000000000000   # Optional: pin tenant for multi-tenant accounts.
    cloud: AzureCloud                         # AzureCloud | AzureUSGovernment
    login_instruction: |                      # Optional override for auth_missing message.
      Run: az login --use-device-code --tenant <your-tenant>

smb:
  enabled: true
  shares:
    - name: ato-policies
      unc: //fileserver.corp/ato               # Windows UNC (also works as smb://)
      mount_point: ~/mnt/ato-policies          # macOS/Linux only; Windows ignored
      credentials_helper: keychain             # keychain | kerberos | prompt | cmdkey
      # keychain → macOS Keychain entry, created by user via Finder → Connect to Server
      # kerberos → valid Kerberos ticket (verified with `klist`)
      # prompt   → let the OS mount tool prompt the user interactively
      # cmdkey   → Windows saved credential (user ran `cmdkey /add:host /user:... /pass:...`)
      account_hint: DOMAIN\\ato-svc            # Optional: shown in confirm prompt
    - name: dr-runbooks
      unc: //fileserver.corp/dr
      credentials_helper: kerberos
  depth: 3                                    # Traversal depth limit (default 3).
  file_types:
    - .docx
    - .pdf
    - .md
    - .txt

vulnerability_scan:                           # Pre-collection vulnerability baseline
                                              # (Step 1.5 of the agent workflow).
  enabled: true                               # Default true. Set false to skip the scan
                                              # by config; equivalent to `--no-vuln-scan`.
                                              # The CLI flag wins when both are present.
  tools_allowlist:                            # Optional: restrict to a subset of scanners.
    []                                        # Empty list (or omitted) means "run every
                                              # available tool". When non-empty, only the
                                              # listed tools are invoked even if others are
                                              # on PATH. Valid entries: cargo-audit,
                                              # npm-audit, pip-audit, safety, bundler-audit,
                                              # govulncheck, dotnet-list, dependency-check,
                                              # composer-audit, trivy, gitleaks, semgrep,
                                              # osv-scanner.
  secret_scan_enabled: true                   # Default true. When false, gitleaks is
                                              # skipped even if installed (use this when
                                              # the repo has many test fixtures that
                                              # gitleaks consistently false-positives on).

poam:                                         # POA&M generator behavior (post-Step-8).
  enabled: false                              # Default false — POAM generation is opt-in
                                              # via the `--poam` flag. When set true here,
                                              # POAM is generated on every run that
                                              # completes Step 8.
  severity_to_due_date:                       # SLA mapping in days from detection date.
    Critical: 15                              # Common federal practice; assessors may
    High: 30                                  # require tighter windows.
    Moderate: 90
    Low: 180

assessment:                                   # Per-Determine-If-ID assessment pass
                                              # (Step 6.5: generate Findings + Result for
                                              # every Determine If ID).
  enabled: true                               # PR-B default: true. The orchestrator
                                              # populates Findings + Result for every
                                              # Determine If ID per the AMIS-style
                                              # assessment template. The CLI flag
                                              # `--no-assessment` forces this to false
                                              # per-run; when false, the orchestrator
                                              # still emits the H3 scaffolding and the
                                              # Determine If Statement but skips
                                              # Findings/Result and emits a 7-column CSV
                                              # without the Result/Findings columns.
                                              # See `references/assessment-template.md`.

synthesis:                                    # Gap-driven artifact synthesis
                                              # (Step 6.6: draft missing artifacts for
                                              # "implementation present, artifact missing"
                                              # gaps).
  enabled: true                               # Default true. Drafts land under
                                              # `synthesized/` with a DRAFT banner. The
                                              # CLI flag `--no-synthesize` forces this
                                              # to false per-run. When false, gaps are
                                              # named textually in Findings paragraphs
                                              # but no draft files are written.
                                              # Synthesis is automatically skipped when
                                              # `assessment.enabled` is false.
  auto_accept: false                          # Default false (drafts stay under
                                              # `synthesized/` for human review). The
                                              # CLI flag `--accept-synthesized` forces
                                              # this to true per-run; auto-promoted
                                              # artifacts are loudly signaled (end-of-run
                                              # summary, INDEX.md banner, CHECKLIST notes
                                              # column). See `references/synthesis-patterns.md`.
                                              # Risk: synthesized drafts make assertions
                                              # about the system from code inspection
                                              # alone; org policy may disagree. The flag
                                              # exists for fast iteration; loud signaling
                                              # is the safeguard.

csv_export:                                   # GRC assessment CSV emission (Step 6.7).
  enabled: true                               # Default true. When false, no
                                              # `<cf>-assessment.csv` files are written
                                              # and `_master-assessment.csv` is skipped.
  master_file: true                           # Default true. When false, only per-family
                                              # CSVs are emitted; the master CSV
                                              # (`controls/_master-assessment.csv`) is
                                              # skipped. Useful when the package consumer
                                              # works exclusively per-family.
```

## US-region allow lists

AWS and Azure scopes are validated against hard-coded US allow lists before
the sibling makes any API call. Any region not on these lists causes the
sibling to refuse the run with a specific error.

**AWS allow list**: `us-east-1`, `us-east-2`, `us-west-1`, `us-west-2`,
`us-gov-east-1`, `us-gov-west-1`.

**Azure allow list**: `eastus`, `eastus2`, `centralus`, `northcentralus`,
`southcentralus`, `westus`, `westus2`, `westus3`, `usgovvirginia`,
`usgovtexas`, `usgovarizona`, `usdodeast`, `usdodcentral`.

## Authentication configuration

Every source has its own `auth:` block (SMB uses `credentials_helper` at the
share level for historical reasons — same idea). The config **never stores
secrets**. What it stores is:

1. **Which method** the user has chosen to establish ambient auth on this host
   (device-code, browser-interactive, SSO profile, a local helper script,
   Kerberos, etc.).
2. **Non-secret parameters** for that method — a profile name, a tenant ID, an
   SSO start URL, a Keychain account hint, a path to a user-owned helper script.
3. **An optional `login_instruction` override** that the sibling echoes verbatim
   when it detects missing auth, instead of its built-in default. Use this to
   tell your team exactly how to log in in your environment ("run `./tools/ato-login.sh`"
   or "pull the break-glass creds from 1Password").

### Helper commands are user-owned

The Azure sibling's `helper_command` and any equivalent future hook is a path
to a **user-owned script or binary**. The sibling invokes it as a subprocess
and checks the exit code — it never reads the script's contents, never
inspects what it does, and never sees any credentials the script may touch.
This is how environment-specific flows (e.g. Alastair's `~/Applications/bin/azureauth`
that pulls creds from 1Password) plug in without the sibling skill needing to
know anything about 1Password.

If you don't have such a helper, use `method: device-code` or
`method: interactive` and let the native CLI handle the login flow directly.

### Service accounts vs personal credentials

SharePoint and AWS both support running under a shared service identity
instead of a personal account. The config doesn't enforce this — it's up to
whoever sets up the host that runs the collector. What the config does is:

- Let you set `method: service-account` (SharePoint) or `method: sso` with a
  dedicated read-only profile (AWS) so the intent is explicit.
- Let you set `account_hint` / `profile` so the Step 3 confirm screen shows
  *which* identity the sibling is about to act as. If the hint doesn't match
  what the probe returns, the sibling refuses to proceed.

## Worked examples

### Minimal — repo-only

No config file needed. The orchestrator prompts in Step 0; the user answers
"no" to every external source.

```yaml
# .ato-package.yaml  (optional — equivalent to no file at all)
version: 1
sharepoint: { enabled: false }
aws:        { enabled: false }
azure:      { enabled: false }
smb:        { enabled: false }
```

### Full — all four sources

```yaml
# .ato-package.yaml at repo root
version: 1

sharepoint:
  enabled: true
  tenant: contoso
  sites:
    - https://contoso.sharepoint.com/sites/app-ato
  libraries:
    https://contoso.sharepoint.com/sites/app-ato:
      - Documents
      - ATO Evidence
  folders:
    https://contoso.sharepoint.com/sites/app-ato:
      Documents:
        - /SSP
        - /POA&M
        - /Policies
      # 'ATO Evidence' library: no folder filter — scan the whole library

aws:
  enabled: true
  accounts: ["123456789012"]
  regions: [us-east-1]
  profile: ato-read
  services: [iam, config, cloudtrail, securityhub, s3]

azure:
  enabled: true
  subscriptions: ["11111111-2222-3333-4444-555555555555"]
  resource_groups: [app-prod]
  regions: [eastus, usgovvirginia]

smb:
  enabled: true
  shares:
    - name: corp-ato
      unc: //fileserver.corp/ato
      mount_point: ~/mnt/corp-ato
      credentials_helper: kerberos
  depth: 3
```

## Merge example

User file `~/.claude/skills/ato-artifact-collector/config.yaml`:

```yaml
version: 1
sharepoint:
  enabled: true
  tenant: contoso
  sites: [https://contoso.sharepoint.com/sites/global-policies]
aws:
  enabled: true
  accounts: ["999999999999"]
  regions: [us-east-1]
```

Repo file `.ato-package.yaml`:

```yaml
version: 1
sharepoint:
  enabled: true
  tenant: contoso
  sites: [https://contoso.sharepoint.com/sites/app-ato]
```

**Merged result** (repo's `sharepoint:` block fully replaces the user's;
`aws:` is inherited unchanged because the repo file didn't mention it):

```yaml
version: 1
sharepoint:
  enabled: true
  tenant: contoso
  sites: [https://contoso.sharepoint.com/sites/app-ato]   # repo wins entirely
aws:
  enabled: true
  accounts: ["999999999999"]                              # inherited from user
  regions: [us-east-1]
```

## `.gitignore` recommendation

Add this to the repo's `.gitignore` unless the team has deliberately chosen
to share the file:

```
# ATO artifact collector scope — may contain tenant-identifying info
.ato-package.yaml
```

## Ready-to-copy template

Save as `.ato-package.yaml` at the repo root and edit the values:

```yaml
version: 1

# Uncomment and fill in the sources you want to scan. Any section omitted or
# set to enabled:false will be skipped silently.

# sharepoint:
#   enabled: true
#   tenant: your-tenant                     # {tenant}.sharepoint.com
#   sites:
#     - https://your-tenant.sharepoint.com/sites/your-site
#   folders:
#     https://your-tenant.sharepoint.com/sites/your-site:
#       - /Shared Documents/ATO

# aws:
#   enabled: true
#   accounts: ["123456789012"]
#   regions: [us-east-1]                    # US allow list only
#   profile: your-sso-profile

# azure:
#   enabled: true
#   subscriptions: ["00000000-0000-0000-0000-000000000000"]
#   resource_groups: [your-rg]
#   regions: [eastus]                       # US allow list only

# smb:
#   enabled: true
#   shares:
#     - name: ato-shared
#       unc: //fileserver.corp/ato
#       mount_point: ~/mnt/ato-shared       # macOS/Linux only
#       credentials_helper: kerberos        # keychain | kerberos | prompt
#   depth: 3
```

## Validation rules

The orchestrator rejects a config that:

- Has a `version` other than `1`
- Declares an AWS or Azure region not on the US allow list
- Declares a `credentials_helper` other than `keychain`, `kerberos`, `prompt`,
  or `cmdkey`
- Declares an `auth.method` not on the per-source allow list (sharepoint:
  `device-code`|`interactive`|`service-account`|`existing`; aws: `sso`|
  `profile`|`env`|`instance`; azure: `device-code`|`interactive`|`helper`|
  `existing`)
- Sets `azure.auth.method: helper` without a `helper_command`, or sets
  `aws.auth.method: sso`/`profile` without a `profile`
- Sets `azure.auth.helper_command` to a path that doesn't exist or isn't
  executable by the current user
- Contains any field that looks like a stored secret (`password`, `token`,
  `client_secret`, `api_key`, `secret_access_key`, `refresh_token`, etc.) —
  these are forbidden; all auth is ambient. The Azure helper script IS allowed
  to touch secrets internally; the config file is not.
- Sets `vulnerability_scan.tools_allowlist` to a tool name not on the
  allow-list above (cargo-audit, npm-audit, pip-audit, safety, bundler-audit,
  govulncheck, dotnet-list, dependency-check, composer-audit, trivy, gitleaks,
  semgrep, osv-scanner)
- Sets `poam.severity_to_due_date` with a non-positive integer or a missing
  key from the canonical set {Critical, High, Moderate, Low}
- Has `sharepoint.enabled: true` but is missing `sharepoint.libraries`, OR has
  `sharepoint.libraries` keyed by a site URL not in `sharepoint.sites`, OR has
  `sharepoint.folders[site][library]` referring to a library not in
  `sharepoint.libraries[site]`. (Legacy `folders`-only configs with no
  `libraries` field are accepted with a deprecation warning — the SharePoint
  sibling defaults `libraries` to `["Documents"]` per site in legacy mode and
  treats each legacy folder string as `Documents/<path>`.)
- Sets `assessment.enabled` to a value other than `true` or `false`
- Sets `synthesis.enabled` to a value other than `true` or `false`
- Sets `synthesis.auto_accept` to a value other than `true` or `false`
- Sets `csv_export.enabled` to a value other than `true` or `false`
- Sets `csv_export.master_file` to a value other than `true` or `false`

On validation failure, the skill prints the offending field path and refuses
to proceed. The user fixes the config and re-runs.
