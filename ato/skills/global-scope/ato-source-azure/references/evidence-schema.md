# Azure Evidence Schema

Each significant Azure resource leaves three kinds of artifact in the
package:

1. **Raw JSON** (primary evidence) — the verbatim result of the read-only
   `az` call. This is what the assessor inspects when they want ground
   truth.
2. **Per-resource Markdown digest** (companion) — a short, human-readable
   explanation of the JSON with critical linked resources embedded inline.
   This is what the assessor reads first.
3. **Citation row** (in `.staging/azure-citations.json`) — the
   orchestrator's pointer that resolves a `[CR-NNN]` tag in the narrative
   back to both files above and a portal permalink.

## File naming

`{evidence_root}/{family}/evidence/azure_{service}-{artifact}.json`.

Examples:
- `azure_policy-assignments.json`
- `azure_policy-compliance.json`
- `azure_role-assignments.json`
- `azure_nsg-rules.json`
- `azure_defender-assessments.json`
- `azure_defender-alerts.json`
- `azure_activity-log-summary.json`
- `azure_keyvault-inventory.json`
- `azure_secure-score.json`
- `azure_aro-cluster-{name}.json`

Per-resource expansion JSON (when a list-* parent is fanned out) uses:

```
azure_{service}-{type}-{name}-{aspect}.json
```

Examples:
- `azure_role-assignment-{shortId}-definition.json`
- `azure_policy-assignment-{name}-definition.json`
- `azure_keyvault-{name}-network-rules.json`

## Per-resource digest companion

Every resource listed in `discovery-patterns.md` "Per-resource digest
scope" gets a Markdown sibling alongside its JSON:

```
azure_{service}-{resource}-{name}.md
```

Examples:
- `azure_role-assignment-22222222.md`
- `azure_policy-assignment-deny-public-network.md`
- `azure_nsg-app-web.md`
- `azure_keyvault-app-prod-vault.md`
- `azure_aro-cluster-app-prod.md`

Aggregate exports get a single companion that table-of-contents the
per-resource digests:

- `azure_role-assignments.md`     ← rolls up `azure_role-assignment-*.md`
- `azure_policy-assignments.md`   ← rolls up `azure_policy-assignment-*.md`
- `azure_nsg-rules.md`            ← rolls up `azure_nsg-*.md`
- `azure_secure-score.md`
- `azure_policy-compliance.md`

### Digest required sections

Every per-resource digest follows this structure. See
`references/digest-templates.md` for ready-to-fill templates per resource
type.

```markdown
# {Resource Type}: {Identifier}

> **Source**: azure (subscription {id}, scope {scopePath})
> **Collected**: {ISO-8601 timestamp}
> **Raw evidence**: [azure_{file}.json](azure_{file}.json)
> **Portal**: [open](https://portal.azure.com/#@{tenant}/resource{resourceId}/overview)

## Summary

One to three sentences in plain English. Lead with the security-relevant
state ("This assignment grants the built-in `Owner` role to security
group `SG-App-Admins` at subscription scope, conferring full management
plane access to every resource in the subscription"), not boilerplate.
Mention specific values that matter: the role's actions, the policy's
effect, whether public network access is allowed, soft-delete state.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| {field} | {value from JSON} | {why it matters} |

Five to twelve rows. Pick the settings the assessor will be asked about.
Typical examples: resource id, scope, principal type, role-definition id,
RBAC mode flag, soft-delete + purge protection, network default action,
encryption algorithm.

## Critical links

(Only if the resource has critical links per `discovery-patterns.md`.)

For each linked resource that the discovery patterns table marks as
"embed full JSON", produce a sub-section with the child's name as a
heading and the child's document as a fenced ```json block.

### {Linked resource name} ({type — built-in / custom / ...})

```json
{ ... full document ... }
```

## Linked resources (noted)

(Only if the resource has noted-only references.)

| Resource | Relationship | Where to look |
|---|---|---|
| {resourceId or name} | {one-line description} | {digest-link if collected, else "not in scope"} |

## Observations

(Optional — include only if the data clearly shows a state worth
flagging.)

- Bullets that summarise findings *visible in the data* (e.g. "Network
  default action is `Allow` — public network access is open unless
  specific deny rules apply.").

Do not invent risk findings from nothing — observations must reference
specific values from the Key Settings table or the embedded JSON.
```

The digest is **read-only narrative**. It does not invent values that
aren't in the JSON. Every claim it makes must be verifiable against the
companion `.json` file.

### Aggregate digest (table-of-contents)

For aggregate-only exports (`policy-compliance`, `secure-score`,
`activity-log-summary`):

```markdown
# {Service} — {Family} summary

> **Source**: azure (subscription {id})
> **Collected**: {timestamp}
> **Raw evidence**: [azure_{file}.json](azure_{file}.json)

## Summary

Two- to four-sentence overview of what the data shows in aggregate.

## Headline numbers

| Metric | Count | Notes |
|---|---|---|
| ... | ... | ... |

## Per-resource digests

| Resource | Digest | One-line state |
|---|---|---|
| {id} | [link](azure_{type}-{id}.md) | {state from row} |
```

## Citation batch JSON

`{staging_dir}/azure-citations.json`:

```json
{
  "source": "azure",
  "generated_at": "2026-04-14T10:45:00Z",
  "scope_summary": "subscription=00000000-0000-0000-0000-000000000000, 1 RG, 2 regions",
  "tenant_id": "11111111-1111-1111-1111-111111111111",
  "citations": [
    {
      "id_placeholder": "AZ-001",
      "cited_by": "controls/AC-access-control/access-control-evidence.md",
      "location": "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/22222222",
      "link": "https://portal.azure.com/#@contoso/resource/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/22222222",
      "purpose": "Owner role at subscription scope — assigned to SG-App-Admins",
      "control_family": "controls/AC-access-control",
      "evidence_file": "controls/AC-access-control/evidence/azure_role-assignments.json",
      "digest_file": "controls/AC-access-control/evidence/azure_role-assignment-22222222.md"
    },
    {
      "id_placeholder": "AZ-002",
      "cited_by": "controls/SC-system-communications-protection/network-communications-evidence.md",
      "location": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/app-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-app-web",
      "link": "https://portal.azure.com/#@contoso/resource/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/app-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-app-web/overview",
      "purpose": "Web tier NSG — ingress rules for 443/80",
      "control_family": "controls/SC-system-communications-protection",
      "evidence_file": "controls/SC-system-communications-protection/evidence/azure_nsg-rules.json",
      "digest_file": "controls/SC-system-communications-protection/evidence/azure_nsg-app-web.md"
    }
  ],
  "partial_failures": []
}
```

The new `digest_file` field is **required** when a Markdown digest exists
for the cited resource, and **omitted** when only the raw JSON is the
evidence (e.g., aggregate-only exports where the digest companion is
itself the evidence file). The orchestrator's CODE_REFERENCES.md merge
prefers `digest_file` for the human-facing link when present, and falls
back to `evidence_file`.

## Portal link template

```
https://portal.azure.com/#@{tenantDomain}/resource{resourceId}/overview
```

- `tenantDomain` is the friendly tenant name (e.g., `contoso`) or tenant GUID
- `resourceId` starts with `/subscriptions/...` and is the ARM resource ID

For Azure US Government, use `https://portal.azure.us` instead of
`portal.azure.com`.

## Redaction

Before writing a JSON blob, scan recursively for keys matching (case-
insensitive): `password`, `secret`, `connectionString`, `clientSecret`,
`primaryKey`, `secondaryKey`, `privateKey`, `accessToken`, `refreshToken`.
Replace the value with `"[REDACTED by ato-source-azure]"` and log the path
in `partial_failures` with `reason: redacted`.

The same redaction pass runs over the Markdown digest before write — if a
critical-link expansion includes a policy parameter or NSG rule
referencing a literal credential, the value is redacted in the embedded
JSON block too.

## Error file

`{staging_dir}/azure-error.json`. Codes: `auth_missing`, `scope_declined`,
`scope_invalid`, `tool_not_installed`.
