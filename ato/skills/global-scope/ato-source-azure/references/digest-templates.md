# Azure Digest Templates

Concrete Markdown templates for each resource type the Azure sibling
writes a per-resource digest for. Fill in the bracketed placeholders with
values from the JSON; embed verbatim role / policy / NSG documents inside
the fenced code blocks.

The base envelope (header + Summary + Key Settings) is identical across
templates; only the "Critical links" and "Linked resources (noted)"
sections vary by resource type.

---

## Role Assignment — `azure_role-assignment-{shortId}.md`

A role assignment without the role definition is meaningless — embed
both. Best-effort principal resolution: try `az ad sp/group/user show`;
record `principal_resolution: denied` if Graph permission is absent.

```markdown
# Role Assignment: {shortId}

> **Source**: azure (subscription {SubscriptionId})
> **Scope**: `{scope}`
> **Raw evidence**: [azure_role-assignments.json](azure_role-assignments.json) (entry for `{principalId}` at `{scope}`)
> **Definition expansion**: [azure_role-assignment-{shortId}-definition.json](azure_role-assignment-{shortId}-definition.json)
> **Portal**: [open](https://portal.azure.com/#@{tenant}/resource/{scope}/providers/Microsoft.Authorization/roleAssignments/{guid})

## Summary

This assignment grants the {built-in|custom} role `{RoleName}` to
{principal display name | principalId `{principalId}`} ({principalType:
User | Group | ServicePrincipal | ManagedIdentity}) at scope `{scope}`.
The role authorizes `{first 3 actions or wildcard summary, e.g. "*" or
"Microsoft.KeyVault/vaults/read + 23 others"}`.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| Assignment ID | `{guid}` | Identifies assignment |
| Scope | `{scope}` | Subscription / RG / resource — width of access |
| Role definition | `{RoleName} ({built-in|custom})` | What is granted |
| Role definition ID | `{roleDefinitionId}` | |
| Principal ID | `{principalId}` | Whose access this is |
| Principal type | `{User|Group|ServicePrincipal|ManagedIdentity}` | |
| Principal display name | `{name|denied|unknown}` | Human-friendly identity |
| Created | `{createdOn}` | |
| Created by | `{createdBy|null}` | Audit signal |
| Condition | `{condition|none}` | ABAC clause if any |

## Critical links

### Role definition: {RoleName} ({built-in|custom})

> Source: `{roleDefinitionId}`. Fetched via `az role definition show`.

```json
{ ... full role definition with actions, notActions, dataActions,
  notDataActions, assignableScopes ... }
```

### Principal: {display name or "could not resolve"}

(Only if Graph resolution succeeded.)

| Field | Value |
|---|---|
| Display name | `{displayName}` |
| User principal name / app id | `{upn or appId}` |
| Object ID | `{principalId}` |
| Type | `{User|Group|ServicePrincipal}` |

(or)

> Principal resolution: denied. The collector lacks Graph permissions to
> resolve this identity. Object id `{principalId}` is the authoritative
> identifier.

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{scope}` | Resource the assignment grants access to | {digest-link if collected, else "not in scope"} |

## Observations

- (Optional) e.g. "Owner role at subscription scope — confers
  unrestricted management plane access including ability to grant access
  to others."
- (Optional) e.g. "Assignment lacks a `Condition` clause — applies
  unconditionally."
```

---

## Custom Role Definition — `azure_role-definition-{name}.md`

```markdown
# Role Definition: {RoleName}

> **Source**: azure (subscription {SubscriptionId})
> **Raw evidence**: [azure_role-definitions.json](azure_role-definitions.json) (entry for `{name}`)

## Summary

Custom role `{RoleName}` is assignable at {AssignableScopes summary}. It
grants {N} actions and {M} data actions, with {K} excluded actions. {One
sentence on what it's clearly designed for, derivable from action prefixes
e.g. "Read-only access across Key Vault, Storage, and Networking."}

## Key settings

| Setting | Value | Significance |
|---|---|---|
| ID | `{roleDefinitionId}` | |
| Type | `CustomRole` | Always custom for this digest |
| Description | `{description}` | |
| Actions | `{count}` | Management plane operations |
| NotActions | `{count}` | Management plane exclusions |
| DataActions | `{count}` | Data plane operations |
| NotDataActions | `{count}` | Data plane exclusions |
| Assignable scopes | `{count}` | |

## Critical links

### Role rule body

```json
{
  "actions": [...],
  "notActions": [...],
  "dataActions": [...],
  "notDataActions": [...],
  "assignableScopes": [...]
}
```

### Active assignments

| Count | Scope spread | Notes |
|---|---|---|
| `{N}` | `{X subscriptions / Y resource groups / Z resources}` | (do not enumerate) |

## Observations

- (Optional) e.g. "DataActions includes
  `Microsoft.KeyVault/vaults/secrets/getSecret/action` — grants secret
  read at the data plane."
```

---

## Policy Assignment — `azure_policy-assignment-{name}.md`

```markdown
# Policy Assignment: {AssignmentName}

> **Source**: azure (subscription {SubscriptionId})
> **Scope**: `{scope}`
> **Raw evidence**: [azure_policy-assignments.json](azure_policy-assignments.json) (entry for `{name}`)
> **Definition expansion**: [azure_policy-assignment-{name}-definition.json](azure_policy-assignment-{name}-definition.json)
> **Portal**: [open](https://portal.azure.com/#@{tenant}/resource/{scope}/providers/Microsoft.Authorization/policyAssignments/{name}/overview)

## Summary

Assignment `{AssignmentName}` enforces {policy|initiative}
`{DisplayName}` at scope `{scope}`. Effect: `{deny|audit|append|modify|
disabled|deployIfNotExists|auditIfNotExists}`. Currently {N} resources
are non-compliant.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| Assignment ID | `{policyAssignmentId}` | |
| Display name | `{displayName}` | |
| Scope | `{scope}` | Width of enforcement |
| Policy / Initiative | `{policyDefinitionId or policySetDefinitionId}` | What is enforced |
| Enforcement mode | `{Default|DoNotEnforce}` | Audit-only when `DoNotEnforce` |
| Effect (resolved) | `{deny|audit|...}` | What happens on violation |
| Identity | `{None|SystemAssigned|UserAssigned}` | Required for `deployIfNotExists`/`modify` |
| Excluded scopes | `{count}` | NotScopes count |
| Created | `{createdOn}` | |
| Compliance state | `{N noncompliant / M total}` | |

## Critical links

### {Policy|Initiative} definition: {DisplayName}

> Source: `{definitionId}`. Type: `{built-in|custom}`.

```json
{ ... full policyRule.if + policyRule.then + parameters from
  az policy definition show (or set-definition show) ... }
```

### Resolved parameters (if any)

| Parameter | Value | Default |
|---|---|---|
| `{paramName}` | `{value}` | `{defaultFromDefinition}` |

### For initiatives (policy set): member policies

(Do not embed each member's full body — that explodes the digest. List
ID + display name + effect.)

| # | Definition ID | Display name | Effect |
|---|---|---|---|
| 1 | `{id}` | `{name}` | `{effect}` |

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{scope}` | Enforcement target | {digest if collected} |
| Excluded scopes | NotScopes | listed in raw JSON |

## Observations

- (Optional) e.g. "Enforcement mode is `DoNotEnforce` — assignment is
  audit-only and does not block violating resources."
- (Optional) e.g. "Effect resolves to `audit` — violations are recorded
  but resources are still created."
```

---

## NSG — `azure_nsg-{name}.md`

```markdown
# Network Security Group: {Name}

> **Source**: azure (subscription {SubscriptionId}, resource group `{ResourceGroup}`)
> **Raw evidence**: [azure_nsg-rules.json](azure_nsg-rules.json) (entry for `{Name}`)
> **Portal**: [open](https://portal.azure.com/#@{tenant}/resource{resourceId}/overview)

## Summary

NSG `{Name}` has {N} custom rules and {M} default rules. Inbound from
the public internet (`*` or `Internet`) is {allowed on ports {ports} |
denied}. Outbound to the public internet is {restricted | unrestricted}.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| Resource ID | `{resourceId}` | |
| Location | `{location}` | |
| Custom rules | `{count}` | |
| Default rules | `{count}` (always 6) | Azure-supplied baseline |
| Subnets attached | `{count}` | Surface area |
| NICs attached | `{count}` | Surface area |
| Flow logs | `{configured|not configured}` | Observability |

## Critical links

### Custom security rules ({count})

| Priority | Name | Direction | Action | Protocol | Source | Dest | Port |
|---|---|---|---|---|---|---|---|
| `{priority}` | `{name}` | `{direction}` | `{access}` | `{protocol}` | `{sourceAddressPrefix}` | `{destinationAddressPrefix}` | `{destinationPortRange}` |

### Default security rules (Azure baseline)

(Same table for the 6 default rules — they apply unless overridden by
custom rules.)

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{subnets[i].id}` | Attached to subnet | not enumerated |
| `{flowLog.id}` | Flow log destination | (if configured) |

## Observations

- (Optional) e.g. "Custom rule `AllowInbound22` permits SSH from
  `Internet` source — broad attack surface."
```

---

## VNet — `azure_vnet-{name}.md`

```markdown
# Virtual Network: {Name}

> **Source**: azure (subscription {SubscriptionId}, resource group `{ResourceGroup}`)
> **Raw evidence**: [azure_vnets.json](azure_vnets.json) (entry for `{Name}`)
> **Portal**: [open](https://portal.azure.com/#@{tenant}/resource{resourceId}/overview)

## Summary

VNet `{Name}` ({addressSpace}) hosts {N} subnets and has {M} peerings.
{K subnets are delegated to specific Azure services.}

## Key settings

| Setting | Value | Significance |
|---|---|---|
| Resource ID | `{resourceId}` | |
| Address space | `{addressSpace[]}` | |
| DNS servers | `{custom|Azure-provided}` | |
| Subnets | `{count}` | |
| Peerings | `{count}` | Cross-VNet connectivity |
| DDoS protection | `{Standard|Basic}` | |

## Critical links

### Subnets ({count})

| Name | CIDR | NSG | Route table | Delegated to |
|---|---|---|---|---|
| `{name}` | `{addressPrefix}` | `{nsg.id|none}` | `{routeTable.id|default}` | `{delegations[].serviceName|none}` |

### Peerings ({count})

| Name | Remote VNet | State | AllowVnetAccess | AllowGatewayTransit | UseRemoteGateways |
|---|---|---|---|---|---|
| `{name}` | `{remoteVirtualNetwork.id}` | `{peeringState}` | `{bool}` | `{bool}` | `{bool}` |

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{subnet[].nsg.id}` | Subnet NSG | [azure_nsg-{name}.md](azure_nsg-{name}.md) |
| `{peering.remoteVirtualNetwork.id}` | Peered VNet | not in scope |
```

---

## Key Vault — `azure_keyvault-{name}.md`

```markdown
# Key Vault: {Name}

> **Source**: azure (subscription {SubscriptionId}, resource group `{ResourceGroup}`)
> **Raw evidence**: [azure_keyvault-{Name}.json](azure_keyvault-{Name}.json)
> **Portal**: [open](https://portal.azure.com/#@{tenant}/resource{resourceId}/overview)

## Summary

Key Vault `{Name}` is in {RBAC mode | legacy access policy mode} with
soft-delete {enabled (retention {days})|disabled} and purge protection
{enabled|disabled}. Network default action: `{Allow|Deny}`. Public
network access is {permitted|restricted to {N} IPs and {M} VNets}.

> Metadata-only — no secret, key, or certificate values are read.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| Resource ID | `{resourceId}` | |
| Vault URI | `{properties.vaultUri}` | Data plane endpoint |
| Tenant | `{properties.tenantId}` | |
| SKU | `{Standard|Premium}` | HSM-backed when Premium |
| RBAC mode | `{enableRbacAuthorization}` | RBAC vs legacy access policies |
| Soft-delete | `{enableSoftDelete}` | |
| Soft-delete retention | `{softDeleteRetentionInDays}` | |
| Purge protection | `{enablePurgeProtection}` | Cannot force-delete |
| Public network access | `{Enabled|Disabled}` | |
| Network default action | `{Allow|Deny}` | |
| For deployment | `{enabledForDeployment}` | VM deployment access |
| For disk encryption | `{enabledForDiskEncryption}` | |
| For template deployment | `{enabledForTemplateDeployment}` | |

## Critical links

### Network ACLs

```json
{ ... networkAcls block including defaultAction, virtualNetworkRules,
  ipRules, bypass ... }
```

### RBAC mode flag

`enableRbacAuthorization`: `{true|false}`

(If `false`, embed the access policy list:)

### Access policies (if RBAC mode disabled)

| Object ID | Tenant ID | Permissions (keys / secrets / certificates / storage) |
|---|---|---|
| `{objectId}` | `{tenantId}` | `{permissions.keys[]} / {permissions.secrets[]} / {permissions.certificates[]} / {permissions.storage[]}` |

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{networkAcls.virtualNetworkRules[].id}` | Allowed subnet | [azure_vnet-{name}.md](azure_vnet-{name}.md) |
| `{privateEndpointConnections[].id}` | Private endpoint | not enumerated |
| Referencing services (App Service, AKS, etc.) | Consumes secrets | not enumerated |

## Observations

- (Optional) e.g. "Purge protection disabled — vault and its secrets can
  be permanently deleted, possibly bypassing soft-delete recovery."
- (Optional) e.g. "Network default action is `Allow` — public network
  access is open unless explicit deny rules apply."
```

---

## Diagnostic Setting — `azure_diagsetting-{resource-shortId}.md`

```markdown
# Diagnostic Setting: {Name}

> **Source**: azure (subscription {SubscriptionId})
> **Resource**: `{resourceUri}`
> **Raw evidence**: [azure_diagsettings.json](azure_diagsettings.json) (entry for `{name}`)

## Summary

Diagnostic setting `{Name}` collects {log categories} and {metrics}
from `{resourceUri}` and forwards to {destination type:
LogAnalyticsWorkspace | StorageAccount | EventHub | partner solution}.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| Setting name | `{name}` | |
| Source resource | `{resourceUri}` | |
| Log Analytics workspace | `{workspaceId|none}` | |
| Storage account | `{storageAccountId|none}` | |
| Event Hub | `{eventHubAuthorizationRuleId|none}` | |
| Log categories enabled | `{count}` | |
| Metrics enabled | `{count}` | |

## Critical links

### Log categories

| Category | Enabled | Retention (days) |
|---|---|---|
| `{category}` | `{enabled}` | `{retentionPolicy.days}` |

### Metrics

| Category | Enabled | Retention (days) |
|---|---|---|
| `{category}` | `{enabled}` | `{retentionPolicy.days}` |

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{workspaceId}` | Log destination | not enumerated |
| `{storageAccountId}` | Log destination | not enumerated |
```

---

## ARO Cluster — `azure_aro-cluster-{name}.md`

```markdown
# ARO Cluster: {Name}

> **Source**: azure (subscription {SubscriptionId}, resource group `{ResourceGroup}`)
> **Raw evidence**: [azure_aro-cluster-{Name}.json](azure_aro-cluster-{Name}.json)
> **Portal**: [open](https://portal.azure.com/#@{tenant}/resource{resourceId}/overview)

## Summary

ARO cluster `{Name}` runs OpenShift `{clusterProfile.version}` with
{masterProfile.vmSize} master nodes and {N} worker nodes
({workerProfiles[0].vmSize}). API server is
`{apiserverProfile.visibility: Public|Private}` and ingress is
`{ingressProfiles[0].visibility: Public|Private}`. Cluster pinned to
VNet `{masterProfile.subnetId}`.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| Resource ID | `{resourceId}` | |
| Cluster version | `{clusterProfile.version}` | OpenShift version |
| Domain | `{clusterProfile.domain}` | |
| Resource group (managed) | `{clusterProfile.resourceGroupId}` | Shadow resource group |
| API URL | `{apiserverProfile.url}` | |
| API visibility | `{apiserverProfile.visibility}` | |
| Console URL | `{consoleProfile.url}` | |
| Ingress visibility | `{ingressProfiles[0].visibility}` | |
| Master VM size | `{masterProfile.vmSize}` | |
| Master subnet | `{masterProfile.subnetId}` | |
| Worker pool count | `{workerProfiles.length}` | |
| Pod CIDR | `{networkProfile.podCidr}` | |
| Service CIDR | `{networkProfile.serviceCidr}` | |
| FIPS validated crypto | `{clusterProfile.fipsValidatedModules}` | |

## Critical links

### Master profile

```json
{ ... masterProfile object ... }
```

### Worker profiles ({count})

```json
{ ... workerProfiles[] ... }
```

### API server profile

```json
{ ... apiserverProfile ... }
```

### Network profile

```json
{ ... networkProfile ... }
```

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{masterProfile.subnetId}` | Master subnet | [azure_vnet-{name}.md](azure_vnet-{name}.md) |
| `{workerProfiles[].subnetId}` | Worker subnets | [azure_vnet-{name}.md](azure_vnet-{name}.md) |

## Observations

- (Optional) e.g. "API visibility is `Public` — control plane reachable
  from the internet."
- (Optional) e.g. "FIPS validated modules disabled — required for FedRAMP
  Moderate baseline."
```

---

## Aggregate digests

For exports without a per-resource digest (policy compliance, secure
score, activity log), use the table-of-contents form:

```markdown
# {Service} — {Family} summary

> **Source**: azure (subscription {SubscriptionId})
> **Collected**: {timestamp}
> **Raw evidence**: [azure_{file}.json](azure_{file}.json)

## Summary

{Two- to four-sentence overview of what the data shows in aggregate.
Lead with the headline number that matters most.}

## Headline numbers

| Metric | Count | Notes |
|---|---|---|
| ... | ... | ... |

## Per-resource digests

| Resource | Digest | One-line state |
|---|---|---|
| `{name}` | [link](azure_{type}-{name}.md) | {state} |
```

### Policy Compliance digest

Headline numbers: total resources, compliant count, non-compliant count,
exempt count, unknown-state count. Per-resource digests link to each
non-compliant assignment's digest.

### Secure Score digest

Headline numbers: current secure-score percentage, max possible, score
delta vs last collection (if known). Top 5 controls by impact-to-fix
shown in a table. Per-control digests not generated — Defender's own
recommendations are the natural place for them.

### Activity Log Summary digest

Headline numbers: events in last 30 days, broken down by status
(Succeeded / Failed / Started), top 10 caller principal IDs by event
count, top 10 operations by count. Useful for surfacing unusual
operational patterns.
