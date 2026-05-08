# AWS CLI Cheatsheet (read-only allow list)

All commands invoked via `mcp__AWS_API_MCP_Server__call_aws`. Profile
argument omitted below for brevity — always add `--profile {profile}
--region {region} --output json`.

## Auth probe

```
aws sts get-caller-identity
```

Must succeed before anything else. The returned `Account` must match one of
`scope.accounts` or the sibling refuses the run.

## IAM → controls/AC-access-control

### Inventory (list-style)

```
aws iam get-account-summary
aws iam list-users --max-items 1000
aws iam list-roles --max-items 1000
aws iam list-policies --scope Local --max-items 1000
aws iam list-groups
aws iam list-account-aliases
aws iam generate-credential-report
aws iam get-credential-report
aws iam get-account-password-policy
```

### Per-resource expansion (called during digest synthesis)

These are the read-only calls required to embed a principal's effective
permissions inline in its digest. See
`references/discovery-patterns.md` "Critical-link expansion" for which
resources trigger which calls.

Per-user expansion:

```
aws iam get-user --user-name {name}
aws iam list-user-policies --user-name {name}
aws iam list-attached-user-policies --user-name {name}
aws iam get-user-policy --user-name {name} --policy-name {policy}
aws iam list-groups-for-user --user-name {name}
```

Per-role expansion:

```
aws iam get-role --role-name {name}
aws iam list-role-policies --role-name {name}
aws iam list-attached-role-policies --role-name {name}
aws iam get-role-policy --role-name {name} --policy-name {policy}
```

Per-group expansion:

```
aws iam get-group --group-name {name}
aws iam list-group-policies --group-name {name}
aws iam list-attached-group-policies --group-name {name}
aws iam get-group-policy --group-name {name} --policy-name {policy}
```

Managed-policy document fetch (after `list-attached-*-policies` returns
ARNs):

```
aws iam get-policy --policy-arn {arn}
aws iam get-policy-version --policy-arn {arn} --version-id {versionId}
```

Permissions boundary (when `get-user`/`get-role` returns a `PermissionsBoundary` block):

```
aws iam get-policy --policy-arn {boundaryArn}
aws iam get-policy-version --policy-arn {boundaryArn} --version-id {versionId}
```

## Config → controls/CM-configuration-management

```
aws configservice describe-configuration-recorders
aws configservice describe-config-rules
aws configservice describe-compliance-by-config-rule
aws configservice describe-delivery-channels
```

## CloudTrail → controls/AU-audit-accountability

```
aws cloudtrail describe-trails --include-shadow-trails
aws cloudtrail get-trail-status --name {trail-arn}
aws cloudtrail get-event-selectors --trail-name {trail-arn}
aws cloudtrail get-insight-selectors --trail-name {trail-arn}
```

## Security Hub → controls/RA-risk-assessment

```
aws securityhub describe-hub
aws securityhub get-enabled-standards
aws securityhub get-findings --max-items 500 \
  --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"},{"Value":"HIGH","Comparison":"EQUALS"}],"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}'
```

Always pass a `--max-items` cap — never fetch unbounded.

## GuardDuty → controls/IR-incident-response

```
aws guardduty list-detectors
aws guardduty get-detector --detector-id {id}
aws guardduty list-findings --detector-id {id} --max-items 500
aws guardduty get-findings --detector-id {id} --finding-ids {ids...}
```

## S3 → controls/MP-media-protection

```
aws s3api list-buckets
aws s3api get-bucket-policy --bucket {name}
aws s3api get-bucket-encryption --bucket {name}
aws s3api get-bucket-versioning --bucket {name}
aws s3api get-bucket-logging --bucket {name}
aws s3api get-public-access-block --bucket {name}
```

Only run per-bucket calls against buckets that pass the filter in
`discovery-patterns.md` — do not enumerate every bucket.

## KMS → controls/SC-system-communications-protection

```
aws kms list-keys --limit 1000
aws kms list-aliases --limit 1000
aws kms describe-key --key-id {id}
aws kms get-key-policy --key-id {id} --policy-name default
aws kms list-grants --key-id {id} --limit 100
aws kms list-resource-tags --key-id {id}
```

## VPC / Security Groups → controls/SC-system-communications-protection

```
aws ec2 describe-vpcs
aws ec2 describe-security-groups
aws ec2 describe-network-acls
aws ec2 describe-flow-logs
aws ec2 describe-subnets
aws ec2 describe-route-tables
aws ec2 describe-vpc-peering-connections
```

## Forbidden verbs

Everything that isn't on this file is forbidden. Specifically banned — even
if you think they're harmless:

- Any `create-*`, `put-*`, `delete-*`, `update-*`, `modify-*`, `attach-*`,
  `detach-*`, `assume-*`, `tag-*`, `untag-*`, `enable-*`, `disable-*`
- `iam change-password`, `iam reset-service-specific-credential`
- `sts assume-role` (use ambient credentials only)
- `s3 cp`, `s3 mv`, `s3 sync`, `s3 rb`, `s3 rm` (use `s3api get-*` only)
- `kms encrypt`, `decrypt`, `generate-data-key`
- Any `aws ssm send-command`, `start-session`, `run-command`

If `suggest_aws_commands` proposes a command not on this list, ignore the
suggestion and refuse.
