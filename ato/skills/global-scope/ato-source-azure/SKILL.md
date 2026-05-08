---
name: ato-source-azure
description: "Sibling of ato-artifact-collector. Collects NIST 800-53 evidence from Azure via the `az` CLI. Invoked by the orchestrator when Azure scope is configured. Strictly read-only, ambient-auth, US-region-only, scope-confirmed. Do not invoke directly unless running an ATO collection."
---

# ATO Source — Azure

Read `~/.claude/skills/ato-artifact-collector/references/sibling-contract.md`
first. This skill implements that contract for Azure.

## Hard Rule: this skill never writes

Every `az` command invoked must be a `show`, `list`, `get-*`, or `export`
verb. **Never** `create`, `update`, `delete`, `set`, `add`, `remove`,
`assign`, `grant`, `revoke`, `enable`, `disable`, `rotate`. If asked to
"also fix X" in Azure, refuse and escalate.

Allow-listed commands live in `references/az-cli-cheatsheet.md`. Any `az`
command not on that list is forbidden.

## Hard Rule: ambient auth only

The skill consumes whatever `az` session the host already has. It never
stores a service principal secret, never calls `az login --password`, never
reads `~/.azure/` directly.

**Azure is the source where auth flows vary the most by environment** —
federal tenants, device-code SSH flows, 1Password-wrapped helpers, MSI on a
CI runner, etc. The sibling therefore supports a pluggable auth-method
selector driven by `scope.auth.method` from config:

| `auth.method` | What the sibling does on probe failure | Default instruction |
|---|---|---|
| `device-code` *(default — works over SSH, CI, no browser)* | Emits the `auth_missing` error with the default instruction | `Run: az login --use-device-code` *(plus `--tenant {tenant}` if configured)* |
| `interactive` | Emits `auth_missing`; expects the user to run the browser flow | `Run: az login` *(plus `--tenant {tenant}` if configured)* |
| `helper` | Invokes `scope.auth.helper_command` as a subprocess, checks exit code, then re-probes with `az account show`. If the re-probe still fails, emits `auth_missing` | `Run: {helper_command}  (your org-specific az-login wrapper)` |
| `existing` | Emits `auth_missing` with no suggested command | `az is not logged in — run whatever login flow your environment requires, then re-run` |

The `helper` method is how environment-specific flows plug in. Example: on
the developer's machine `helper_command` points at
`~/Applications/bin/azureauth` (a user-owned script that pulls creds from
1Password and runs `az login`). On a federal GovCloud host it might be
`/usr/local/bin/gcc-az-login`. **The sibling never reads the helper's
contents** — it just invokes it and checks the exit code. If the helper
exits non-zero, emit `auth_missing` with stderr in the `detail` field; the
operator is responsible for fixing their own helper.

If `scope.auth.login_instruction` is set, use it verbatim instead of the
default instruction — lets teams point operators at their own runbook.

Before invoking `helper_command`, verify:
1. The path exists and is executable by the current user
2. The path resolves under `$HOME` or a standard system `bin` directory — do
   not invoke arbitrary paths from other locations
3. The config-schema validator has already rejected any helper_command
   containing shell metacharacters

**Auth probe, first attempt:**

```bash
az account show --output json
```

If it succeeds → proceed to scope verification. If it fails:

1. **Check `~/.agent-skills/auth/auth.yaml` first.** If the file exists with
   permissions `0600` and has an entry at `sources.azure`, invoke the
   `auth-config` skill to run that entry's preauth command (typically
   `az login`, a helper script, or an `op inject` template), then re-probe.
   If the yaml file exists but has looser permissions, emit `auth_missing`
   with detail `"~/.agent-skills/auth/auth.yaml must be chmod 600"` and stop.
2. **Otherwise fall back to `scope.auth.method`.** If
   `scope.auth.method == "helper"` → invoke the helper once, re-probe, then
   proceed or fail. Any other method → go straight to `auth_missing`.

An `auth.yaml` entry takes precedence over `scope.auth.method` — it's how
users generalize the `helper_command` pattern to any vault without the
sibling knowing the vault's CLI.

On final failure write `.staging/azure-error.json`:

```json
{
  "error": "auth_missing",
  "method": "helper",
  "instruction": "Run: ~/Applications/bin/azureauth",
  "detail": "helper exited with code 1: 1Password CLI not signed in"
}
```

Do not attempt to log in yourself beyond the one `helper` invocation. Do not
prompt the user for a password. Do not shell out to `op`, `keychain`, or
`lastpass` — if the environment needs those, they belong in the helper
script, not in this skill.

## Hard Rule: respect the configured cloud

`scope.auth.cloud` selects between `AzureCloud` (commercial) and
`AzureUSGovernment`. Before the auth probe, run:

```bash
az cloud show --query name --output tsv
```

If the result doesn't match `scope.auth.cloud`, switch it with
`az cloud set --name {cloud}` (this is a local CLI setting, not a mutating
API call — allowed). This ensures GovCloud subscriptions are never probed
against the commercial endpoint and vice versa.

## Hard Rule: US regions only

Validate every region in scope against the Azure US allow list in
`ato-artifact-collector/references/config-schema.md`:

```
eastus, eastus2, centralus, northcentralus, southcentralus,
westus, westus2, westus3,
usgovvirginia, usgovtexas, usgovarizona,
usdodeast, usdodcentral
```

A single non-US region causes `scope_invalid` and the whole sibling refuses.

## Workflow

```
1. VALIDATE  → Parse scope, check region allow list
2. AUTH      → az account show probe, verify subscription matches scope
3. CONFIRM   → Show resolved scope, ask y/N
4. DISCOVER  → Per scope: policy, defender, rbac, nsg, keyvault, activity log
5. EXPORT    → Write JSON exports to evidence/ with azure_ prefix
6. SYNTHESIZE → Walk critical-link table, fetch linked resources,
                 write per-resource Markdown digests next to each JSON
7. EMIT      → Write .staging/azure-citations.json (with digest_file refs)
```

The Synthesize step is what turns raw `az` output into something an
assessor can read in under a minute. The skill still pulls the full JSON
(that's the primary evidence), but for every significant resource it
also writes a Markdown digest with a one-paragraph summary, a key-
settings table, and any critical linked configuration embedded inline.
See `references/discovery-patterns.md` "Critical-link expansion" for
which children get embedded vs noted, and `references/digest-templates.md`
for the exact Markdown shape per resource type.

## Step 1: Validate scope

Scope object shape:

```json
{
  "enabled": true,
  "subscriptions": ["00000000-0000-0000-0000-000000000000"],
  "resource_groups": ["app-prod"],
  "regions": ["eastus", "usgovvirginia"],
  "tag_filter": {"environment": "production"},
  "staging_dir": "/abs/path/.staging",
  "evidence_root": "/abs/path/docs/ato-package"
}
```

Validate:
- every `subscriptions[]` is a UUID
- every `regions[]` is on the Azure US allow list
- `resource_groups[]` entries are plain resource group names (no paths)
- `tag_filter` is a flat string→string map

## Step 2: Auth probe + subscription verification

```bash
az account show --output json
az account list --output json
```

The active subscription (or any subscription in the logged-in tenant) must
include at least one subscription from `scope.subscriptions`. If not, refuse
with `scope_invalid`: the user's credentials don't cover the requested
scope.

Switch the active subscription per-call via `--subscription {id}` rather
than mutating global CLI state with `az account set`.

## Step 3: Confirm scope

```
About to scan Azure with the following scope:

  Tenant: Contoso
  Logged in as: alice@contoso.onmicrosoft.com
  Subscriptions (1):
    - 00000000-0000-0000-0000-000000000000 (App-Production)
  Resource groups: app-prod
  Regions: eastus, usgovvirginia
  Tag filter: environment=production

This skill will issue read-only `az` commands. No create/update/delete
verbs will be used. Proceed? [y/N]
```

## Step 4: Discover

Per family:

| Family | Az commands |
|---|---|
| `controls/CM-configuration-management` | `az policy assignment list`, `az policy state summarize` |
| `controls/AC-access-control` | `az role assignment list --all`, `az role definition list --custom-role-only` |
| `controls/IA-identification-authentication` | `az ad signed-in-user show`, `az ad user list --filter` (limited) |
| `controls/AU-audit-accountability` | `az monitor diagnostic-settings list`, `az monitor activity-log list --max-events 500` |
| `controls/SI-system-information-integrity` | `az security assessment list` (Defender for Cloud), `az security sub-assessment list` |
| `controls/IR-incident-response` | `az security alert list`, `az sentinel incident list` (if Sentinel workspace exists) |
| `controls/SC-system-communications-protection` (KV) | `az keyvault list`, `az keyvault show` (metadata only — never `secret show`) |
| `controls/SC-system-communications-protection` | `az network nsg list`, `az network nsg rule list`, `az network vnet list`, `az network vnet peering list` |
| `controls/SA-system-services-acquisition` | ARO cluster configs if present: `az aro list`, `az aro show` |
| `controls/RA-risk-assessment` | `az security secure-score controls list`, `az security secure-scores list` |

Exact command forms and flags live in `references/az-cli-cheatsheet.md`.

## Step 5: Export

JSON exports land in
`{evidence_root}/{family}/evidence/azure_{service}-{artifact}.json`.

Examples:
- `controls/CM-configuration-management/evidence/azure_policy-assignments.json`
- `controls/CM-configuration-management/evidence/azure_policy-compliance.json`
- `controls/AC-access-control/evidence/azure_role-assignments.json`
- `controls/SC-system-communications-protection/evidence/azure_nsg-rules.json`
- `controls/SI-system-information-integrity/evidence/azure_defender-assessments.json`
- `controls/RA-risk-assessment/evidence/azure_secure-score.json`

**Never export Key Vault secret values.** `az keyvault secret show`,
`secret list`, `key show`, `certificate show` (with `--include-private`),
and any `get-value` form are forbidden. Metadata-only commands (`keyvault
list`, `keyvault show`) are allowed.

**Redaction**: before writing, scan for field names (case-insensitive)
matching `password`, `secret`, `connection_string`, `client_secret`,
`private_key`, `primary_key`, `secondary_key`. Replace values with
`"[REDACTED by ato-source-azure]"`.

## Step 6: Synthesize per-resource digests

Raw JSON is necessary but not sufficient. For every resource in
`references/discovery-patterns.md` "Per-resource digest scope", walk its
"Critical links" column, issue the corresponding read-only calls from
`az-cli-cheatsheet.md`, and write a Markdown digest companion next to
the JSON.

The digest must:

1. **Lead with a plain-English summary.** One to three sentences naming
   the resource, what it does, and the security-relevant state. Cite
   specific values from the JSON ("`Owner` role at subscription scope",
   "`networkAcls.defaultAction = Allow`", "`enablePurgeProtection = false`").
2. **Include a Key Settings table.** 5–12 rows, each row picking a value
   the assessor will be asked about (resource id, scope, principal type,
   role-definition id, RBAC mode flag, default network action, encryption
   alg) with a short Significance column.
3. **Embed critical linked resources inline.** When the discovery patterns
   table marks a child as "embed full JSON", fetch it via the cheatsheet's
   per-resource expansion calls and include the document verbatim under a
   "Critical links" section, one heading per child. *Example:* a role
   assignment's digest must contain the role definition's `actions`,
   `notActions`, `dataActions`, and `notDataActions`. A policy
   assignment's digest must contain the policy definition's `policyRule`
   body and the resolved parameter values.
4. **List noted-only references in a table.** When a child is "noted",
   record the resource id + a one-line relationship + a pointer to the
   child's own digest if it was collected, else "not in scope".
5. **Resolve principals best-effort.** For role assignments, attempt
   `az ad sp show` / `ad group show` / `ad user show` to get a friendly
   display name and principal type. If any returns `Forbidden`, record
   `principal_resolution: denied` and continue — the principal id is
   enough.
6. **Never invent observations.** The "Observations" section is optional
   and may only contain bullets directly traceable to values shown
   elsewhere in the digest.

For aggregate-only exports (policy compliance, secure score, activity-log
summary), write a single roll-up digest that table-of-contents the
per-resource digests instead of duplicating their detail.

If a critical-link API call fails (`AuthorizationFailed`, throttling,
etc.), do not skip the digest — write it with an inline failure record
where the embedded JSON would have been:

```markdown
#### Owner (built-in role) — could not fetch

Error: AuthorizationFailed — read denied on
`/providers/Microsoft.Authorization/roleDefinitions/{guid}`. Check the
collector's RBAC role.
```

…and append a `partial_failures` row to the citation batch.

The digest's redaction pass is the same as the JSON's: any value under a
field named `password`, `secret`, `connectionString`, `clientSecret`,
`privateKey`, `primaryKey`, `secondaryKey`, `accessToken`, `refreshToken`
is replaced with `"[REDACTED by ato-source-azure]"` before write — this
applies to the embedded JSON inside the Markdown too.

See `references/digest-templates.md` for ready-to-fill templates per
resource type, and `references/evidence-schema.md` for required digest
sections and the aggregate-digest shape.

## Step 7: Emit citation batch

`{staging_dir}/azure-citations.json`. Placeholder IDs `AZ-001`, `AZ-002`, …

Each row must include the new `digest_file` field whenever a per-resource
digest was synthesized in Step 6 (see `evidence-schema.md`). The
orchestrator prefers the digest as the human-facing link in
`CODE_REFERENCES.md` when both are present.

See `references/evidence-schema.md`.

## Failure modes

Same matrix as AWS. Error codes: `auth_missing`, `scope_declined`,
`scope_invalid`, `tool_not_installed`.

## References

- `references/discovery-patterns.md` — per-family az commands, critical-
  link expansion table, per-resource digest scope
- `references/evidence-schema.md` — JSON naming, digest companion format,
  citation batch format (incl. `digest_file`)
- `references/az-cli-cheatsheet.md` — allow-listed commands, including
  the per-resource expansion calls used during digest synthesis
- `references/digest-templates.md` — ready-to-fill Markdown templates for
  each resource type the digest covers
- `references/custom-role-definition.json` / `.md` — minimum RBAC role
  required to run the collector, including the new actions needed for
  digest synthesis
