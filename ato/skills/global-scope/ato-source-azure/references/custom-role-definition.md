# Azure Custom RBAC Role — ato-source-azure

`custom-role-definition.json` is the minimum custom RBAC role needed to run
the `ato-source-azure` collector. Every action corresponds to a command in
`az-cli-cheatsheet.md`; nothing more, nothing less.

## What this is — and why "custom role" is the right shape

Azure's equivalent of an AWS IAM permission-set JSON is a **custom role
definition**. A role definition is a JSON document containing `Actions` (the
control plane) and (deliberately empty here) `DataActions`, assigned at one
or more scopes (subscription / resource group / management group).

Built-in alternatives considered and rejected:

| Built-in role | Why not |
|---|---|
| `Reader` | Covers most of these but lacks Defender/Security Center reads, Policy Insights summarize, Sentinel incident reads. Operator would need to layer additional roles. |
| `Security Reader` | Covers Defender/Security Center but lacks the network/policy-state/RBAC reads. |
| `Reader` + `Security Reader` | Workable, but over-grants (e.g. read on every resource type Azure has) and isn't a single auditable artifact. |

The custom role gives one auditable JSON file that exactly matches the
collector's behavior — useful for the ATO package itself.

## Deploying

Replace the placeholder subscription ID in `AssignableScopes`, then:

```bash
az role definition create \
  --role-definition @custom-role-definition.json
```

Then assign it to the principal (user, group, or service principal) that
runs the collector:

```bash
az role assignment create \
  --role "ATO Read-Only Collector" \
  --assignee {object-id-or-upn} \
  --scope /subscriptions/{subscription-id}
```

For multiple subscriptions, list each one in `AssignableScopes` and create
one role assignment per subscription, **or** assign the role at a management
group scope and list that scope in `AssignableScopes` instead.

## What's deliberately excluded

| Excluded | Reason |
|---|---|
| Any `*/write`, `*/delete`, `*/action` (except the read-style PolicyInsights actions) | Skill is read-only by contract |
| All `DataActions` | No data-plane access — Key Vault secrets, storage blob contents, SQL data, etc. are out of scope |
| `Microsoft.KeyVault/vaults/secrets/*`, `keys/*`, `certificates/*` | Forbidden by the skill: Key Vault is metadata-only |
| `Microsoft.Storage/storageAccounts/listKeys/action` | Storage account keys are explicitly forbidden |
| `Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action` | SAS generation forbidden |
| `Microsoft.Graph/*` (any flavor) | `az ad signed-in-user show` works with the user's own token; no Graph role needed |
| Subscription / RBAC mutations | No write actions, period |

## What's intentionally included that may surprise you

- `Microsoft.PolicyInsights/policyStates/queryResults/action` and
  `Microsoft.PolicyInsights/policyStates/summarize/action` — Azure
  classifies these as `/action` because they're POST operations, but they
  return data only and are required for `az policy state summarize`.
- `Microsoft.RedHatOpenShift/locations/operationsstatus/read` — needed
  alongside `openShiftClusters/read` to query ARO cluster state.
- `Microsoft.Storage/storageAccounts/read` and child reads — required to
  collect storage-account metadata for `controls/MP-media-protection` evidence
  even though the cheatsheet does not yet enumerate storage-account
  commands. Included to future-proof the role; remove if you want a
  strictly-current minimum.
- `Microsoft.RecoveryServices/vaults/read` and `backupPolicies/read` —
  required to enumerate Backup Vaults for `controls/CP-contingency-planning` evidence.
- `Microsoft.Authorization/policyExemptions/read` — needed by the policy-
  assignment digest to enumerate any exemption that overrides a policy's
  effect on specific scopes. Without this the digest would over-state the
  enforcement footprint.
- `Microsoft.Authorization/classicAdministrators/read` — required to
  surface any legacy co-admin assignments alongside RBAC. These bypass
  RBAC entirely and would be invisible without explicit collection.

## What's required for digest synthesis

The Synthesize step (Step 6 in the SKILL workflow) issues these reads
*per resource* to build the per-resource Markdown digest:

- `Microsoft.Authorization/roleDefinitions/read` — embed the role's
  actions/notActions inline in each role-assignment digest. (Already
  granted above.)
- `Microsoft.Authorization/policyDefinitions/read` and
  `policySetDefinitions/read` — embed the rule body in each policy-
  assignment digest. (Already granted above.)
- `Microsoft.Network/networkSecurityGroups/securityRules/read` and
  `defaultSecurityRules/read` — embed every rule in each NSG digest.
  (Already granted above.)
- `Microsoft.KeyVault/vaults/read` — embed network ACLs, RBAC mode flag,
  and soft-delete state. (Already granted above.)
- `Microsoft.Network/virtualNetworks/peerings/read` — embed peering
  topology in each VNet digest. (Already granted above.)

Best-effort principal resolution for role-assignment digests
(`az ad sp/group/user show`) uses Microsoft Graph, not RBAC. See the
"Microsoft Graph (Entra ID) note" below.

## Cloud / sovereign notes

This role definition is identical for AzureCloud (commercial) and
AzureUSGovernment. Action names do not change between sovereign clouds.
Create the custom role separately in each cloud you operate in — custom
role definitions do not replicate across sovereigns.

## Microsoft Graph (Entra ID) note

The skill calls `az ad signed-in-user show`, which uses Microsoft Graph,
not Azure Resource Manager. Graph permissions are governed separately (app
registration / delegated scopes), not by this RBAC role. Reading the
signed-in user's own profile is permitted by default for any authenticated
user — no extra Graph permission needed for what the skill does today.

If you later extend the skill to read other directory objects (groups, sign-
in logs, conditional-access policies, etc.), grant the principal the
appropriate Graph application permissions (e.g. `Directory.Read.All`,
`AuditLog.Read.All`, `Policy.Read.All`) **separately** from this role — RBAC
and Graph are different permission systems.
