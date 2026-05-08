# AWS Evidence Schema

Each significant AWS resource leaves three kinds of artifact in the
package:

1. **Raw JSON** (primary evidence) — the verbatim result of the read-only
   API call. This is what the assessor inspects when they want ground truth.
2. **Per-resource Markdown digest** (companion) — a short, human-readable
   explanation of the JSON with critical linked resources embedded inline.
   This is what the assessor reads first.
3. **Citation row** (in `.staging/aws-citations.json`) — the orchestrator's
   pointer that resolves a `[CR-NNN]` tag in the narrative back to both
   files above and a console permalink.

## File naming

JSON exports land in `{evidence_root}/{NN-CF-section-slug}/evidence/` with:

```
aws_{service}-{artifact}.json
```

Examples:
- `aws_iam-account-summary.json`
- `aws_iam-roles.json`
- `aws_iam-credential-report.json`
- `aws_config-rules.json`
- `aws_config-compliance.json`
- `aws_cloudtrail-trails.json`
- `aws_securityhub-findings-summary.json`
- `aws_guardduty-detectors.json`
- `aws_s3-{bucket-name}.json`
- `aws_kms-keys.json`

Per-resource expansion JSON (when a list-* parent is fanned out) uses:

```
aws_{service}-{type}-{name}-policies.json   # for principals' attached policy docs
aws_{service}-{type}-{name}-detail.json     # for single get-* expansions
```

Examples:
- `aws_iam-user-alice-policies.json`
- `aws_iam-role-app-runtime-policies.json`
- `aws_kms-key-1234abcd-grants.json`

## Per-resource digest companion

Every resource listed in `discovery-patterns.md` "Per-resource digest scope"
gets a Markdown sibling alongside its JSON:

```
aws_{service}-{resource}-{name}.md
```

Examples:
- `aws_iam-user-alice.md`
- `aws_iam-role-app-runtime.md`
- `aws_kms-key-1234abcd-5678-90ef-1234-567890abcdef.md`
- `aws_s3-bucket-app-data.md`
- `aws_cloudtrail-trail-org-trail.md`

Aggregate exports get a single companion that table-of-contents the
per-resource digests:

- `aws_iam-roles.md`              ← rolls up `aws_iam-role-*.md`
- `aws_iam-users.md`              ← rolls up `aws_iam-user-*.md`
- `aws_kms-keys.md`               ← rolls up `aws_kms-key-*.md`
- `aws_securityhub-findings-summary.md`
- `aws_config-compliance.md`

### Digest required sections

Every per-resource digest follows this structure. See
`references/digest-templates.md` for ready-to-fill templates per resource
type.

```markdown
# {Resource Type}: {Identifier}

> **Source**: aws (account {id}, region {region})
> **Collected**: {ISO-8601 timestamp}
> **Raw evidence**: [aws_{file}.json](aws_{file}.json)
> **Console**: [open](https://console.aws.amazon.com/...)

## Summary

One to three sentences in plain English. Lead with the security-relevant
state ("This role grants full administrative access to any principal in
account 222222222222"), not boilerplate ("This is an IAM role"). Mention
specific values that matter: who can assume, what's granted, whether MFA
is required, key rotation state, encryption algorithm, etc.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| {field} | {value from JSON} | {why it matters} |

Five to twelve rows. Pick the settings the assessor will be asked about,
not every field in the JSON. Typical examples:
- ARN, creation date, last activity, MFA state, console-access flag, key-
  rotation state, encryption algorithm, public-access state.

## Critical links

(Only if the resource has critical links per `discovery-patterns.md`.)

For each linked resource that the discovery patterns table marks as
"embed full JSON", produce a sub-section with the child's name as a
heading and the child's policy/document as a fenced ```json block.

### {Linked resource name} ({source})

```json
{ ... full document ... }
```

## Linked resources (noted)

(Only if the resource has noted-only references.)

| Resource | Relationship | Where to look |
|---|---|---|
| {arn or name} | {one-line description} | {digest-link if collected, else "not in scope"} |

## Observations

(Optional — include only if the data clearly shows a state worth flagging.)

- Bullets that summarise findings *visible in the data* (e.g. "Console
  access is enabled but no MFA device is registered.").

Do not invent risk findings from nothing — observations must reference
specific values from the Key Settings table or the embedded JSON.
```

The digest is **read-only narrative**. It does not invent values that
aren't in the JSON. Every claim it makes must be verifiable against the
companion `.json` file.

### Aggregate digest (table-of-contents)

For aggregate-only exports (`account-summary`, `credential-report`,
`compliance`, `findings-summary`):

```markdown
# {Service} — {Family} summary

> **Source**: aws (account {id}, region {region})
> **Collected**: {timestamp}
> **Raw evidence**: [aws_{file}.json](aws_{file}.json)

## Summary

Two- to four-sentence overview of what the data shows in aggregate.

## Headline numbers

| Metric | Count | Notes |
|---|---|---|
| ... | ... | ... |

## Per-resource digests

| Resource | Digest | One-line state |
|---|---|---|
| {id} | [link](aws_{type}-{id}.md) | {state from row} |
```

## Citation batch JSON

`{staging_dir}/aws-citations.json`:

```json
{
  "source": "aws",
  "generated_at": "2026-04-14T10:40:00Z",
  "scope_summary": "account=123456789012, region=us-east-1, 7 services",
  "caller_identity": "arn:aws:sts::123456789012:assumed-role/ATO-Read/alice",
  "citations": [
    {
      "id_placeholder": "AWS-001",
      "cited_by": "controls/AC-access-control/access-control-evidence.md",
      "location": "arn:aws:iam::123456789012:role/app-runtime",
      "link": "https://console.aws.amazon.com/iam/home?region=us-east-1#/roles/app-runtime",
      "purpose": "Runtime role trust policy — assumed by ARO workload identity",
      "control_family": "controls/AC-access-control",
      "evidence_file": "controls/AC-access-control/evidence/aws_iam-roles.json",
      "digest_file": "controls/AC-access-control/evidence/aws_iam-role-app-runtime.md"
    },
    {
      "id_placeholder": "AWS-002",
      "cited_by": "controls/AU-audit-accountability/audit-logging-evidence.md",
      "location": "arn:aws:cloudtrail:us-east-1:123456789012:trail/org-trail",
      "link": "https://console.aws.amazon.com/cloudtrail/home?region=us-east-1#/trails/arn:aws:cloudtrail:us-east-1:123456789012:trail/org-trail",
      "purpose": "Multi-region management event trail — immutable log source",
      "control_family": "controls/AU-audit-accountability",
      "evidence_file": "controls/AU-audit-accountability/evidence/aws_cloudtrail-trails.json",
      "digest_file": "controls/AU-audit-accountability/evidence/aws_cloudtrail-trail-org-trail.md"
    }
  ],
  "partial_failures": [
    {
      "service": "guardduty",
      "region": "us-east-1",
      "reason": "service_disabled",
      "detail": "GuardDuty has no detectors in us-east-1 — detection capability absent"
    }
  ]
}
```

The new `digest_file` field is **required** when a Markdown digest exists
for the cited resource, and **omitted** when only the raw JSON is the
evidence (e.g., aggregate-only exports where the digest companion is
itself the evidence file). The orchestrator's CODE_REFERENCES.md merge
prefers `digest_file` for the human-facing link when present, and falls
back to `evidence_file`.

## Console link anchors

| Service | URL template |
|---|---|
| IAM user | `https://console.aws.amazon.com/iam/home?region={region}#/users/{name}` |
| IAM role | `https://console.aws.amazon.com/iam/home?region={region}#/roles/{name}` |
| IAM policy | `https://console.aws.amazon.com/iam/home?region={region}#/policies/{arn}` |
| Config rule | `https://console.aws.amazon.com/config/home?region={region}#/rules/details?configRuleName={name}` |
| CloudTrail | `https://console.aws.amazon.com/cloudtrail/home?region={region}#/trails/{arn}` |
| Security Hub | `https://console.aws.amazon.com/securityhub/home?region={region}#/findings` |
| GuardDuty | `https://console.aws.amazon.com/guardduty/home?region={region}#/findings` |
| S3 bucket | `https://s3.console.aws.amazon.com/s3/buckets/{name}?region={region}` |
| KMS key | `https://console.aws.amazon.com/kms/home?region={region}#/kms/keys/{keyId}` |

GovCloud uses `console.amazonaws-us-gov.com` instead of
`console.aws.amazon.com` — if the region is `us-gov-*`, substitute.

## Redaction

Before writing any JSON blob to `evidence/`, scan for fields named
(case-insensitive): `SecretAccessKey`, `Password`, `OAuthToken`,
`ClientSecret`, `PrivateKey`. Replace each value with
`"[REDACTED by ato-source-aws]"`. Log the redaction in `partial_failures`
with `reason: redacted`.

The same redaction pass runs over the Markdown digest before write — if a
critical-link expansion includes a policy document with a `Condition`
block referencing a literal credential, the value is redacted in the
embedded JSON block too.

Access key IDs (`AKIA*`) are not secrets — they stay.

## Error file

`{staging_dir}/aws-error.json` when the run cannot proceed. Error codes:
`auth_missing`, `scope_declined`, `scope_invalid`, `mcp_unavailable`.
