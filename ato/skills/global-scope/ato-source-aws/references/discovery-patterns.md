# AWS Discovery Patterns

Maps AWS services and resources to the 20 control families.

## Service → family map

| Service | Primary family | Also feeds |
|---|---|---|
| IAM (users, roles, groups, policies) | `controls/AC-access-control` | `controls/IA-identification-authentication`, `controls/SC-system-communications-protection` |
| IAM credential report | `controls/AC-access-control` | `controls/IA-identification-authentication`, `controls/PS-personnel-security` |
| Config rules + compliance | `controls/CM-configuration-management` | `controls/RA-risk-assessment` |
| CloudTrail trails + event selectors | `controls/AU-audit-accountability` | `controls/SA-system-services-acquisition` |
| CloudWatch Logs groups (metadata) | `controls/AU-audit-accountability` | — |
| Security Hub findings summary | `controls/RA-risk-assessment` | `controls/SI-system-information-integrity` |
| GuardDuty detectors + findings summary | `controls/IR-incident-response` | `controls/RA-risk-assessment` |
| S3 bucket policies + encryption | `controls/MP-media-protection` | `controls/SC-system-communications-protection` |
| KMS keys + aliases | `controls/SC-system-communications-protection` (crypto) | `controls/MP-media-protection` |
| VPC + security groups | `controls/SC-system-communications-protection` | — |
| WAF rules | `controls/SC-system-communications-protection` | `controls/SI-system-information-integrity` |
| Backup plans | `controls/CP-contingency-planning` | — |

## Citation granularity

A single JSON export may generate many citations — one per significant
resource. Rules of thumb:

| Export | Citations per export |
|---|---|
| `iam-account-summary.json` | 1 (the summary itself) |
| `iam-roles.json` | 1 per role with a trust policy that crosses account boundaries, otherwise 1 aggregate |
| `iam-policies.json` | 1 aggregate (too many to cite individually) |
| `config-compliance.json` | 1 per non-compliant rule |
| `cloudtrail-trails.json` | 1 per trail |
| `securityhub-findings-summary.json` | 1 aggregate + 1 per Critical severity finding |
| `guardduty-findings.json` | 1 aggregate + 1 per High severity finding |
| `s3-buckets.json` | 1 per bucket with a bucket policy |
| `kms-keys.json` | 1 per customer-managed key |

Aggregate rows use `location: "AWS account 123456789012 — IAM policies"` and
point at the console index page rather than a specific ARN.

## Resource filters

- **S3**: only describe buckets whose name appears in a repo config (`.env*`,
  terraform, CloudFormation) or whose name matches a pattern like
  `*-ato-*`, `*-audit-*`, `*-logs-*`, `*-evidence-*`. Do not enumerate every
  bucket in the account — that's out of scope.
- **KMS**: only customer-managed keys (CMKs). Skip AWS-managed keys
  (`aws/s3`, `aws/rds`, etc.) — they're inherited from the CSP.
- **IAM users**: skip if the account has zero IAM users (all-SSO accounts),
  log as `all_federated`.
- **GuardDuty / Security Hub**: if the service is disabled in the region,
  log a citation row noting the disable state (that itself is evidence for
  a finding: detection capability absent).

## Critical-link expansion

A raw JSON export from a `list-*` or `describe-*` call leaves the assessor
holding nothing but ARNs. The sibling expands those ARNs into the digest
companion (see `evidence-schema.md` "Per-resource digest companion") so a
reader sees the user's effective permission set, not just a managed-policy
ARN.

The rule for "should I expand this link?" is:

- **Critical (embed inline in the digest as full JSON):** the linked resource
  *is* the security control. You cannot evaluate the parent resource without
  reading the child. Examples: an IAM user is meaningless without their
  attached policies; a KMS key is meaningless without its key policy.
- **Noted (one-line cross-reference, no embed):** the parent depends on the
  child, but the child has its own digest elsewhere or is out of scope.
  Example: a Lambda's execution role grants access to bucket `app-data` —
  note the dependency, point at the bucket's own digest if collected.

### Per-resource expansion table

| Parent resource | Critical links — embed full JSON | Noted-only references |
|---|---|---|
| **IAM User** | All attached managed policies (current version doc), all inline policy docs, group memberships → each group's attached + inline policies, permissions boundary (current version doc) | Last-activity timestamps, MFA device serial, console login URL |
| **IAM Role** | Trust policy (already in `get-role` output), all attached managed policies, all inline policies, permissions boundary | Resources granted *inside* the policies (S3 buckets, DynamoDB tables, KMS keys — note ARNs only; if the bucket/key is in scope it has its own digest) |
| **IAM Group** | All attached managed policies, all inline policies | Members (note count + first 5 user ARNs) |
| **IAM Policy** *(customer-managed)* | Current default-version policy document, attachments list (which roles/users/groups use it) | (no further expansion) |
| **KMS Key** | Key policy, key aliases (note which alias resolves to this key), grants list | Resources encrypted with this key (not enumerated — would require ListAliases on every service) |
| **S3 Bucket** | Bucket policy, encryption config, public-access-block, versioning, server access logging target *(target bucket name noted only)* | Object inventory (forbidden — metadata only) |
| **CloudTrail Trail** | Event selectors, insight selectors, trail status (logging on/off, last delivery error) | S3 destination bucket (noted; if in scope it has its own digest), CloudWatch Logs group (noted) |
| **Config Rule** | Rule definition (parameters, source, scope), compliance summary | Per-resource compliance results (aggregate count only — too long) |
| **GuardDuty Detector** | Detector config (status, finding publishing frequency, data sources), enabled features | Underlying VPC flow logs / DNS logs (noted as data sources only) |
| **Security Hub Finding** *(Critical only)* | Finding record (severity, types, resources, compliance), workflow status | Affected resource's own digest if collected |
| **VPC** | Security group rule summary (count + first 10 ingress rules), NACL rule summary, flow log destination *(name noted)* | Subnets (note count; one-line subnet table), route tables (note count) |
| **Security Group** | Inbound + outbound rules (already in `describe-security-groups`) | Network interfaces / instances attached (note count only) |

### Implementation rule

When the discover step lists a parent resource, the synthesize step (Step 6)
walks that resource's "Critical links" column above and issues the
corresponding read-only call from `aws-cli-cheatsheet.md`. Every fetched
child policy/document is:

1. Written to the *same* JSON evidence file as the parent, under a nested
   `_expanded` key, OR written to a sibling JSON file with a clear name (e.g.
   `aws_iam-user-alice-policies.json`). The digest links to whichever path is
   used.
2. Embedded verbatim in the parent's Markdown digest under a "Critical
   links" section with a heading per child (policy name, group name, etc.).

If a critical-link call fails (e.g. `AccessDenied` because the role exists
but the principal lacks `iam:GetPolicyVersion` for a specific managed
policy), the digest records the failure inline:

```markdown
#### AdministratorAccess (AWS-managed) — could not fetch
Error: AccessDenied — `iam:GetPolicyVersion` denied on `arn:aws:iam::aws:policy/AdministratorAccess`.
```

…and the run continues. The collector's IAM permission set already grants
`iam:GetPolicy*` on `*`; if it's still failing, an SCP or boundary is
clipping it and that's itself useful evidence.

## Per-resource digest scope

The sibling produces digest companions for these resource types specifically
(not every JSON export):

| Resource | Digest filename | Embedded |
|---|---|---|
| IAM user | `aws_iam-user-{name}.md` | Effective permissions tree |
| IAM role | `aws_iam-role-{name}.md` | Effective permissions tree + trust policy |
| IAM group | `aws_iam-group-{name}.md` | Effective permissions tree + members count |
| IAM customer-managed policy | `aws_iam-policy-{name}.md` | Document + attachments |
| KMS CMK | `aws_kms-key-{keyId}.md` | Key policy + aliases + grants count |
| S3 bucket *(in-scope buckets only)* | `aws_s3-bucket-{name}.md` | Bucket policy + encryption + public-access-block + versioning |
| CloudTrail trail | `aws_cloudtrail-trail-{name}.md` | Event selectors + status + destination |
| Config rule *(non-compliant only)* | `aws_config-rule-{name}.md` | Rule + compliance summary |
| GuardDuty detector | `aws_guardduty-detector-{id}.md` | Detector config + finding-count by severity |
| Security Hub finding *(Critical only)* | `aws_securityhub-finding-{id-shortened}.md` | Finding record |
| VPC | `aws_vpc-{vpcId}.md` | Security groups summary + flow log target |

Aggregate exports (`aws_iam-account-summary.json`,
`aws_iam-credential-report.json`, `aws_securityhub-findings-summary.json`)
get a single companion `aws_{export}.md` that summarizes the table-of-contents
and links to each per-resource digest, but does not duplicate per-resource
detail.
