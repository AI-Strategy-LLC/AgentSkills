# Azure Discovery Patterns

Maps Azure services to the 20 control families.

| Azure service | Primary family | Also feeds |
|---|---|---|
| Policy (assignments + state) | `controls/CM-configuration-management` | `controls/RA-risk-assessment` |
| RBAC (role assignments) | `controls/AC-access-control` | `controls/SC-system-communications-protection` |
| Entra ID (sign-in, password policy) | `controls/IA-identification-authentication` | `controls/AC-access-control` |
| Diagnostic settings | `controls/AU-audit-accountability` | — |
| Activity Log | `controls/AU-audit-accountability` | `controls/IR-incident-response` |
| Defender for Cloud (assessments) | `controls/SI-system-information-integrity` | `controls/RA-risk-assessment` |
| Defender for Cloud (alerts) | `controls/IR-incident-response` | — |
| Sentinel (incidents) | `controls/IR-incident-response` | `controls/RA-risk-assessment` |
| Backup vaults | `controls/CP-contingency-planning` | — |
| Key Vault (metadata) | `controls/SC-system-communications-protection` | `controls/MP-media-protection` |
| Storage accounts (metadata) | `controls/MP-media-protection` | `controls/SC-system-communications-protection` |
| NSG rules | `controls/SC-system-communications-protection` | — |
| VNet peerings | `controls/SC-system-communications-protection` | `controls/CA-assessment-authorization` |
| Private Endpoints | `controls/SC-system-communications-protection` | `controls/CA-assessment-authorization` |
| ARO clusters | `controls/SA-system-services-acquisition` | `controls/SC-system-communications-protection` |
| Secure Score | `controls/RA-risk-assessment` | — |

## Citation granularity

| Export | Citations |
|---|---|
| `policy-assignments.json` | 1 per non-compliant assignment |
| `policy-compliance.json` | 1 aggregate |
| `role-assignments.json` | 1 per Owner / Contributor at subscription scope |
| `nsg-rules.json` | 1 per NSG with ingress from the internet |
| `defender-assessments.json` | 1 per High severity unhealthy resource |
| `secure-score.json` | 1 aggregate |

## Forbidden extraction targets

Even though `az` supports it, never extract:
- Secret values from Key Vault (`secret show`, `secret list --maxresults` with values)
- Certificate private material (`certificate show --include-private`)
- Storage account keys (`storage account keys list`)
- SAS tokens (`storage account generate-sas`)
- Service principal credentials

## Critical-link expansion

The bare output of `az role assignment list` or `az policy assignment list`
gives the assessor nothing but resource IDs and GUIDs. The digest companion
(see `evidence-schema.md` "Per-resource digest companion") expands the
links so the reader sees the actions a role grants, the rule a policy
enforces, and the principal type that was assigned.

The rule for "should I expand this link?" is:

- **Critical (embed inline in the digest as full JSON):** the linked resource
  *is* the security control. You cannot evaluate the parent resource without
  reading the child. Examples: a role assignment is meaningless without the
  role definition's `actions` array; a policy assignment is meaningless
  without the definition's `policyRule.then.effect`.
- **Noted (one-line cross-reference, no embed):** the parent depends on the
  child, but the child has its own digest elsewhere or is out of scope.
  Example: a Key Vault references a virtual network for its private
  endpoint — note the dependency, point at the VNet's own digest if
  collected.

### Per-resource expansion table

| Parent resource | Critical links — embed full JSON | Noted-only references |
|---|---|---|
| **Role Assignment** | The role definition (`actions`, `notActions`, `dataActions`, `notDataActions`, `assignableScopes`); principal display name + type *(best-effort, may be `denied`)* | The resource scope ID — note its kind (subscription / RG / resource) and link to that resource's own digest if collected |
| **Custom Role Definition** | Built-in or custom (`type` field), assignable scopes | Number of active assignments — note count only, do not enumerate |
| **Policy Assignment** | The policy or policy-set definition (`policyRule.if`, `policyRule.then.effect`, `parameters`); resolved parameter values from the assignment | Resources currently in violation — note count from `policy state summarize`, not per-resource |
| **Policy Set (Initiative) Assignment** | The initiative (`policyDefinitions[]` listing each member policy), resolved parameter values | Each member policy definition is *not* embedded inline (would balloon the digest) — note the IDs and link to each definition's own digest if collected |
| **NSG** | All security rules (already nested in `nsg show`), default rules | Subnets associated (note resource IDs only), network interfaces attached (count only) |
| **VNet** | Address space, subnets (id + range + delegated services), peerings (each peering's remote VNet ID and `allowVnetAccess`/`allowGatewayTransit` flags) | Network interfaces attached (count only), DDoS plan (note id) |
| **Key Vault** | Network ACLs (`networkAcls.defaultAction`, virtualNetworkRules, ipRules), RBAC mode flag (`enableRbacAuthorization`), soft-delete + purge protection (`enableSoftDelete`, `enablePurgeProtection`), access policies *(if RBAC mode disabled)* | Private endpoints (note ids), referencing services (not enumerated) |
| **Storage Account** | Encryption config, blob/file/queue/table service properties (versioning, soft-delete, public-access flag), network ACLs | Containers (not enumerated — would require data-plane read) |
| **Diagnostic Setting** | Log categories enabled, metrics enabled, retention policy | Destination workspace / storage account / event hub (note resource IDs only) |
| **Defender Assessment** *(Unhealthy only)* | Assessment metadata (severity, description), affected resource, status reason | Remediation playbooks (link only) |
| **ARO Cluster** | Master + worker node profiles, API server visibility (`apiserverProfile.visibility`), ingress profile, network profile | The pinned VNet/subnets (note ids) |
| **Sentinel Incident** *(High/Critical only)* | Incident metadata (severity, status, classification), related alerts (count + first 5 alert ids) | Underlying log records (out of scope) |
| **Recovery Services Vault** | Backup policies (each policy's schedule and retention), redundancy setting (`storageType`) | Protected items (count by type only) |

### Implementation rule

When the discover step lists a parent resource, the synthesize step (Step 6)
walks that resource's "Critical links" column above and issues the
corresponding read-only call from `az-cli-cheatsheet.md`. Every fetched
child document is:

1. Written to the *same* JSON evidence file as the parent under a nested
   `_expanded` key, OR written to a sibling JSON file with a clear name
   (e.g. `azure_role-assignment-{shortId}-definition.json`). The digest
   links to whichever path is used.
2. Embedded verbatim in the parent's Markdown digest under a "Critical
   links" section with a heading per child (role definition name, policy
   definition name, etc.).

If a critical-link call fails (e.g. `Forbidden` because the principal
lacks the cross-subscription read), the digest records the failure inline:

```markdown
#### Owner (built-in role) — could not fetch

Error: AuthorizationFailed — read denied on
`/providers/Microsoft.Authorization/roleDefinitions/{guid}`. Check the
collector's RBAC role.
```

…and the run continues.

## Per-resource digest scope

The sibling produces digest companions for these resource types
specifically (not every JSON export):

| Resource | Digest filename | Embedded |
|---|---|---|
| Role assignment | `azure_role-assignment-{shortId}.md` | Role definition + principal (if resolvable) |
| Custom role definition | `azure_role-definition-{name}.md` | Actions / NotActions / DataActions |
| Policy assignment | `azure_policy-assignment-{name}.md` | Policy or initiative definition + parameters |
| Policy definition (custom) | `azure_policy-definition-{name}.md` | Rule body |
| NSG | `azure_nsg-{name}.md` | All rules + default rules |
| VNet | `azure_vnet-{name}.md` | Subnets + peerings |
| Key Vault | `azure_keyvault-{name}.md` | Network ACLs + RBAC mode + soft-delete state |
| Storage account *(in-scope only)* | `azure_storage-{name}.md` | Encryption + service properties + network ACLs |
| Diagnostic setting | `azure_diagsetting-{resource-shortId}.md` | Categories + destination |
| Defender assessment *(Unhealthy)* | `azure_defender-assessment-{id}.md` | Assessment record |
| ARO cluster | `azure_aro-cluster-{name}.md` | Cluster config |
| Sentinel incident *(High/Critical)* | `azure_sentinel-incident-{id}.md` | Incident record |
| Recovery Services vault | `azure_recovery-vault-{name}.md` | Backup policies |

Aggregate exports (`azure_policy-compliance.json`,
`azure_secure-score.json`, `azure_activity-log-summary.json`) get a single
companion `azure_{export}.md` that summarizes the table-of-contents and
links to each per-resource digest.
