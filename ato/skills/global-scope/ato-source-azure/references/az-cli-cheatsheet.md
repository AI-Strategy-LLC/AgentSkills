# az CLI Cheatsheet (read-only allow list)

All commands take `--subscription {id} --output json`. Do not call
`az account set` — switch per-command instead.

## Auth probe

```bash
az account show
az account list
```

## Policy → controls/CM-configuration-management

### Inventory

```bash
az policy assignment list --subscription {id}
az policy state summarize --subscription {id}
az policy definition list --subscription {id}
az policy set-definition list --subscription {id}
```

### Per-assignment expansion (called during digest synthesis)

After listing assignments, the digest synthesis step resolves the policy
or policy-set definition each assignment points at — the definition body
*is* the enforcement rule and must be embedded inline in the assignment's
digest:

```bash
az policy definition show --name {policyName} --subscription {id}
az policy definition show --name {policyName}                # built-in
az policy set-definition show --name {setName} --subscription {id}
az policy set-definition show --name {setName}               # built-in
```

## RBAC → controls/AC-access-control

### Inventory

```bash
az role assignment list --all --subscription {id}
az role definition list --custom-role-only true --subscription {id}
```

### Per-assignment expansion (called during digest synthesis)

A role assignment is meaningless without the role definition it grants.
After listing assignments, fetch each unique `roleDefinitionId` to embed
the role's `actions`, `notActions`, `dataActions`, and `notDataActions`
inline in the assignment's digest:

```bash
az role definition show --name {roleDefinitionId} --subscription {id}
az role definition list --name "{roleName}" --subscription {id}
```

Best-effort principal resolution (skip silently on `Forbidden` — Graph
permissions are separate and the user enumeration block above stays
conservative):

```bash
az ad sp show --id {principalId}      # service principal
az ad group show --group {principalId} # security group
az ad user show --id {principalId}     # user (often denied; that's fine)
```

If any of these returns `Forbidden`, record `principal_resolution: denied`
in the digest and continue. The `principalId` itself is enough evidence
to identify the assignment; the display name is a nicety.

## Entra ID → controls/IA-identification-authentication

```bash
az ad signed-in-user show
# User enumeration is deliberately not attempted — scope-creep risk.
```

## Diagnostic settings & activity log → controls/AU-audit-accountability

```bash
az monitor diagnostic-settings list --resource {resourceId}
az monitor activity-log list --max-events 500 --offset 30d
```

## Defender for Cloud → controls/SI-system-information-integrity / controls/IR-incident-response

```bash
az security assessment list --subscription {id}
az security sub-assessment list --subscription {id}
az security alert list --subscription {id}
az security secure-scores list --subscription {id}
az security secure-score-controls list --subscription {id}
```

## Key Vault → controls/SC-system-communications-protection (metadata only)

```bash
az keyvault list --subscription {id}
az keyvault show --name {name} --subscription {id}
az keyvault network-rule list --name {name} --subscription {id}
# FORBIDDEN: az keyvault secret show / list-versions / download
# FORBIDDEN: az keyvault key show / backup
# FORBIDDEN: az keyvault certificate show --include-private
```

## Network → controls/SC-system-communications-protection

```bash
az network vnet list
az network vnet peering list --vnet-name {name} --resource-group {rg}
az network nsg list
az network nsg rule list --nsg-name {name} --resource-group {rg}
az network private-endpoint list
az network flow-log list
```

## ARO → controls/SA-system-services-acquisition

```bash
az aro list --subscription {id}
az aro show --name {cluster} --resource-group {rg}
```

## Forbidden verbs

Any `az * create`, `update`, `delete`, `set`, `add`, `remove`, `assign`,
`grant`, `revoke`, `enable`, `disable`, `rotate`, `generate-sas`,
`keys list`, `secret show`, `login`, `logout`, `account set`.

If `az` suggests a command not on this file, refuse.
