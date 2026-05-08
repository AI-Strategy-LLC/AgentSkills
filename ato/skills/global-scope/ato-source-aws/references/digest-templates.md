# AWS Digest Templates

Concrete Markdown templates for each resource type the AWS sibling writes
a per-resource digest for. Fill in the bracketed placeholders with values
from the JSON; embed verbatim policy documents inside the fenced code
blocks.

The base envelope (header + Summary + Key Settings) is identical across
templates; only the "Critical links" and "Linked resources (noted)"
sections vary by resource type.

---

## IAM User — `aws_iam-user-{name}.md`

Effective permissions equal the union of: direct attached managed
policies + direct inline policies + (for each group the user is in) the
group's attached + inline policies + permissions boundary clip.

```markdown
# IAM User: {UserName}

> **Source**: aws (account {AccountId})
> **Collected**: {ISO-8601}
> **Raw evidence**: [aws_iam-users.json](aws_iam-users.json) (entry for `{UserName}`)
> **Per-user expansion**: [aws_iam-user-{UserName}-policies.json](aws_iam-user-{UserName}-policies.json)
> **Console**: [open](https://console.aws.amazon.com/iam/home?region=us-east-1#/users/{UserName})

## Summary

User `{UserName}` was created on {CreateDate} and {has|has not} signed in
since {LastUsedDate}. Console access is {enabled|disabled}; MFA is
{enabled|absent}. {N} access keys are active. The user receives
permissions {directly via M attached managed policies and K inline policies
| through {N} group memberships | both}.

> Replace the second sentence with whatever single fact most matters: e.g.
> "This user has `AdministratorAccess` attached directly, granting `*:*`."

## Key settings

| Setting | Value | Significance |
|---|---|---|
| ARN | `{Arn}` | Identifies user |
| Created | `{CreateDate}` | Account age |
| Path | `{Path}` | Logical grouping |
| Console access | `{enabled|disabled}` | Interactive login allowed |
| MFA enabled | `{true|false}` | Strong auth required |
| Active access keys | `{count}` | Programmatic credentials |
| Last password use | `{date|never}` | Activity signal |
| Permissions boundary | `{arn|none}` | Caps effective permissions |
| Attached managed policies | `{count}` | Sum of permissions sources |
| Inline policies | `{count}` | Direct permission grants |
| Group memberships | `{count}` | Inherited permissions |

## Critical links

### Direct attached managed policies ({count})

#### {PolicyName} ({AWS-managed | Customer-managed})

> Source ARN: `{PolicyArn}`. Default version: `{VersionId}`.

```json
{ ... full policy document from get-policy-version ... }
```

(Repeat per policy. If `count == 0`, write "None.")

### Inline policies ({count})

#### {PolicyName}

```json
{ ... full policy document from get-user-policy ... }
```

(Repeat per inline policy.)

### Group memberships ({count})

For each group the user belongs to, embed the group's attached and inline
policies. If a managed policy already appeared in "Direct attached managed
policies" above, write a one-line cross-reference instead of duplicating
the JSON.

#### Group: {GroupName}

##### Attached managed policies on this group

###### {PolicyName} ({AWS-managed | Customer-managed})

```json
{ ... full policy document from get-policy-version ... }
```

(or)

###### {PolicyName} — already shown above
> Same `{PolicyArn}` already embedded in "Direct attached managed
> policies".

##### Inline policies on this group

###### {PolicyName}

```json
{ ... full policy document from get-group-policy ... }
```

### Permissions boundary

(Only if `PermissionsBoundary` is set on the user.)

#### {BoundaryPolicyName}

```json
{ ... full policy document from get-policy-version ... }
```

> All effective permissions above are clipped by this boundary. The user
> can do the *intersection* of (direct + group) permissions and the
> boundary's allowed actions.

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| (any specific S3 / DynamoDB / etc. ARNs that appear in the embedded policies) | Granted by `{PolicyName}` | {digest-link if collected, else "not in scope"} |

## Observations

- (Optional) e.g. "Console access is enabled but no MFA device is
  registered."
- (Optional) e.g. "`AdministratorAccess` attached directly — broader than
  least privilege."
```

---

## IAM Role — `aws_iam-role-{name}.md`

Same shape as IAM User, with the trust policy front-and-center and group
membership replaced by service principals / cross-account principals in
the trust policy.

```markdown
# IAM Role: {RoleName}

> **Source**: aws (account {AccountId})
> **Raw evidence**: [aws_iam-roles.json](aws_iam-roles.json) (entry for `{RoleName}`)
> **Console**: [open](https://console.aws.amazon.com/iam/home?region=us-east-1#/roles/{RoleName})

## Summary

Role `{RoleName}` is assumed by {service|account|federated identity} and
grants {one-line gist of permissions, e.g. "S3 read on `app-data` and
DynamoDB write on `app-sessions`"}. Trust policy {does|does not} cross
account boundaries.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| ARN | `{Arn}` | Identifies role |
| Created | `{CreateDate}` | Role age |
| Max session duration | `{seconds}` | Token lifetime |
| Permissions boundary | `{arn|none}` | Caps effective permissions |
| Attached managed policies | `{count}` | Sum of permissions sources |
| Inline policies | `{count}` | Direct permission grants |
| Last used | `{LastUsedDate|never}` | Activity signal |

## Trust policy

Who may assume this role:

```json
{ ... AssumeRolePolicyDocument from get-role ... }
```

## Critical links

### Attached managed policies ({count})

(Same structure as IAM User.)

### Inline policies ({count})

(Same structure as IAM User.)

### Permissions boundary

(Same structure as IAM User.)

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{S3 bucket ARN}` | Granted r/w by `{PolicyName}` | [aws_s3-bucket-{name}.md](aws_s3-bucket-{name}.md) |
| `{DynamoDB table ARN}` | Granted access | not in scope |

## Observations

- (Optional) e.g. "Trust policy uses `Principal: '*'` with no `Condition`
  block — any AWS principal can assume."
```

---

## IAM Group — `aws_iam-group-{name}.md`

```markdown
# IAM Group: {GroupName}

> **Source**: aws (account {AccountId})
> **Raw evidence**: [aws_iam-groups.json](aws_iam-groups.json) (entry for `{GroupName}`)

## Summary

Group `{GroupName}` has {N} members and grants permissions via {M}
attached managed policies and {K} inline policies. {Any user in this
group inherits all of the below.}

## Key settings

| Setting | Value | Significance |
|---|---|---|
| ARN | `{Arn}` | Identifies group |
| Created | `{CreateDate}` | Group age |
| Members | `{count}` | Users granted these permissions |
| Attached managed policies | `{count}` | |
| Inline policies | `{count}` | |

## Members ({count})

| User | ARN |
|---|---|
| `{UserName}` | `{Arn}` |

## Critical links

### Attached managed policies

(Same structure as IAM User.)

### Inline policies

(Same structure as IAM User.)

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{user ARN}` | Member of this group | [aws_iam-user-{name}.md](aws_iam-user-{name}.md) |
```

---

## KMS CMK — `aws_kms-key-{keyId}.md`

```markdown
# KMS Key: {KeyId}

> **Source**: aws (account {AccountId}, region {region})
> **Raw evidence**: [aws_kms-keys.json](aws_kms-keys.json) (entry for `{KeyId}`)
> **Console**: [open](https://console.aws.amazon.com/kms/home?region={region}#/kms/keys/{KeyId})

## Summary

Customer-managed key `{KeyId}` ({KeySpec}) is used for {usage gist from
KeyUsage / aliases}. Rotation is {enabled|disabled}; last rotation
{date|never}. Multi-region: {true|false}.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| Key ID | `{KeyId}` | Identifies key |
| ARN | `{Arn}` | |
| Key state | `{Enabled|PendingDeletion|Disabled}` | Operational status |
| Key spec | `{SYMMETRIC_DEFAULT|RSA_4096|...}` | Algorithm class |
| Key usage | `{ENCRYPT_DECRYPT|SIGN_VERIFY|...}` | Operations allowed |
| Origin | `{AWS_KMS|EXTERNAL|AWS_CLOUDHSM}` | Key material source |
| Rotation enabled | `{true|false}` | Annual rotation |
| Multi-region | `{true|false}` | Cross-region replicas |
| Aliases | `{count}` | Friendly names pointing here |
| Active grants | `{count}` | Programmatic access entries |

## Critical links

### Key policy

```json
{ ... result of get-key-policy --policy-name default ... }
```

### Aliases ({count})

| Alias | Last updated |
|---|---|
| `{AliasName}` | `{LastUpdatedDate}` |

### Grants ({count})

| Grantee | Operations | Issued |
|---|---|---|
| `{GranteePrincipal}` | `{Operations[]}` | `{IssuingAccount}` |

(If grant count > 50, summarize: "Top 5 by recency shown; full list in
`aws_kms-key-{keyId}-grants.json`.")

## Linked resources (noted)

(Encrypted resources are not enumerated — KMS does not expose this
without scanning every consumer service.)

## Observations

- (Optional) e.g. "Rotation disabled — manual key replacement required
  for compliance with annual rotation policy."
```

---

## S3 Bucket — `aws_s3-bucket-{name}.md`

```markdown
# S3 Bucket: {BucketName}

> **Source**: aws (account {AccountId}, region {LocationConstraint})
> **Raw evidence**: [aws_s3-{BucketName}.json](aws_s3-{BucketName}.json)
> **Console**: [open](https://s3.console.aws.amazon.com/s3/buckets/{BucketName}?region={region})

## Summary

Bucket `{BucketName}` is {public|private — public access blocked at all
four levels}. Default encryption: {SSE-S3 | SSE-KMS using `{KeyArn}` |
none}. Versioning: {enabled|suspended|disabled}. Server access logging:
{configured to `{TargetBucket}` | not configured}.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| ARN | `arn:aws:s3:::{BucketName}` | |
| Region | `{LocationConstraint}` | |
| Block public ACLs | `{true|false}` | Account-level safety net |
| Block public policy | `{true|false}` | |
| Ignore public ACLs | `{true|false}` | |
| Restrict public buckets | `{true|false}` | |
| Default encryption | `{SSE-S3|SSE-KMS|none}` | Data-at-rest |
| KMS key ARN | `{KmsMasterKeyID|none}` | |
| Bucket key enabled | `{true|false}` | Reduces KMS API calls |
| Versioning | `{Enabled|Suspended|Disabled}` | Immutability support |
| MFA delete | `{Enabled|Disabled}` | Versioning hardening |
| Server access logging | `{TargetBucket|none}` | Audit trail |
| Has bucket policy | `{true|false}` | Resource-based access control |

## Critical links

### Bucket policy

(Only if a bucket policy is set.)

```json
{ ... result of get-bucket-policy ... }
```

### Encryption configuration

```json
{ ... result of get-bucket-encryption ... }
```

### Public access block

```json
{ ... result of get-public-access-block ... }
```

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{KMS key ARN}` | Default encryption | [aws_kms-key-{keyId}.md](../controls/SC-system-communications-protection/evidence/aws_kms-key-{keyId}.md) |
| `{Logging target bucket}` | Server access logs delivered here | not in scope |

## Observations

- (Optional) e.g. "Default encryption disabled — objects written without
  explicit `x-amz-server-side-encryption` header are unencrypted."
```

---

## CloudTrail Trail — `aws_cloudtrail-trail-{name}.md`

```markdown
# CloudTrail Trail: {Name}

> **Source**: aws (account {AccountId}, region {region})
> **Raw evidence**: [aws_cloudtrail-trails.json](aws_cloudtrail-trails.json) (entry for `{Name}`)
> **Console**: [open](https://console.aws.amazon.com/cloudtrail/home?region={region}#/trails/{TrailARN})

## Summary

Trail `{Name}` is {logging|stopped} and writes to S3 bucket
`{S3BucketName}{/S3KeyPrefix if set}`. {Multi-region|Single-region}.
{Includes management events|Excludes management events}; {includes data
events|no data events}. Log file validation: {enabled|disabled}. Last
delivery {success at {date} | error: {LatestDeliveryError}}.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| ARN | `{TrailARN}` | |
| Multi-region | `{IsMultiRegionTrail}` | Cross-region coverage |
| Organization trail | `{IsOrganizationTrail}` | Cross-account coverage |
| S3 destination | `{S3BucketName}{/S3KeyPrefix}` | Where logs land |
| KMS key | `{KmsKeyId|none}` | Log-at-rest encryption |
| Log file validation | `{LogFileValidationEnabled}` | Tamper detection |
| Logging | `{IsLogging from get-trail-status}` | On / off |
| Last delivery | `{LatestDeliveryTime}` | Freshness |
| Last delivery error | `{LatestDeliveryError|none}` | Health |
| Insight events | `{count}` | Anomaly detection on |

## Critical links

### Event selectors

```json
{ ... result of get-event-selectors ... }
```

### Insight selectors (if configured)

```json
{ ... result of get-insight-selectors ... }
```

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{S3BucketName}` | Log destination | [aws_s3-bucket-{S3BucketName}.md](../controls/MP-media-protection/evidence/aws_s3-bucket-{S3BucketName}.md) |
| `{KMS key ARN}` | Encrypts log files | [aws_kms-key-{keyId}.md](../controls/SC-system-communications-protection/evidence/aws_kms-key-{keyId}.md) |
| `{CloudWatchLogsLogGroupArn}` | Optional CloudWatch destination | not in scope |

## Observations

- (Optional) e.g. "Log file validation disabled — tamper detection not
  available."
```

---

## VPC — `aws_vpc-{vpcId}.md`

```markdown
# VPC: {VpcId}

> **Source**: aws (account {AccountId}, region {region})
> **Raw evidence**: [aws_ec2-vpcs.json](aws_ec2-vpcs.json) (entry for `{VpcId}`)

## Summary

VPC `{VpcId}` ({CidrBlock}) hosts {N} subnets, {M} security groups, and
{K} flow log configurations. {Default VPC | Application VPC tagged
`{Tag}`}. Flow logs are {enabled to `{LogDestination}` | not configured}.

## Key settings

| Setting | Value | Significance |
|---|---|---|
| VPC ID | `{VpcId}` | |
| CIDR block | `{CidrBlock}` | Address space |
| Is default | `{IsDefault}` | Default VPC |
| State | `{State}` | |
| DNS hostnames | `{enableDnsHostnames}` | |
| DNS support | `{enableDnsSupport}` | |
| Subnets | `{count}` | |
| Security groups | `{count}` | |
| Flow logs | `{count}` | Network observability |

## Critical links

### Security groups summary

| GroupId | Name | Inbound rules | Outbound rules |
|---|---|---|---|
| `{GroupId}` | `{GroupName}` | `{count}` | `{count}` |

(First 10 ingress rules — full list in `aws_ec2-security-groups.json`.)

| GroupId | Direction | Protocol | Port | Source/Dest |
|---|---|---|---|---|
| `{GroupId}` | inbound | `{IpProtocol}` | `{FromPort}-{ToPort}` | `{CidrIp\|GroupId}` |

### Flow log destinations

| Log destination | Type | Traffic type |
|---|---|---|
| `{LogDestination}` | `{cloud-watch-logs|s3}` | `{ALL|ACCEPT|REJECT}` |

## Linked resources (noted)

| Resource | Relationship | Where to look |
|---|---|---|
| `{Subnets[].SubnetId}` | Subnets in this VPC | not enumerated; see `aws_ec2-subnets.json` |
| `{RouteTables[].RouteTableId}` | Route tables | not enumerated; see `aws_ec2-route-tables.json` |
| `{VpcPeeringConnections[].VpcPeeringConnectionId}` | Peerings | not enumerated; see `aws_ec2-vpc-peering-connections.json` |
```

---

## Aggregate digests

For exports without a per-resource digest (account summary, credential
report, findings summary), use the table-of-contents form:

```markdown
# {Service} — {Family} summary

> **Source**: aws (account {AccountId}, region {region})
> **Collected**: {timestamp}
> **Raw evidence**: [aws_{file}.json](aws_{file}.json)

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
| `{name}` | [link](aws_{type}-{name}.md) | {state} |
```

### IAM Account Summary digest

Headline numbers should include: `Users`, `Groups`, `Roles`,
`MFADevices`, `MFADevicesInUse`, `Policies`, `AccountSigningCertificates`,
`PolicyVersionsInUse`, with a Notes column flagging anything > 0 that
should be 0 (e.g. account signing certificates).

### Credential Report digest

Per-row state per IAM user: password age, MFA, access keys age, last
used. Flag any user with: console enabled + no MFA, access key never
rotated + last used recently, root user with active access keys.

### Security Hub Findings Summary digest

Headline numbers: total findings, breakdown by severity (CRITICAL,
HIGH, MEDIUM, LOW), breakdown by `WorkflowState`, top 10 finding types
by count. Per-resource digests only for CRITICAL findings.
