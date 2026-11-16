# AWS IAM Permission Set — ato-source-aws

`iam-permission-set.json` is the minimum IAM policy needed to run the
`ato-source-aws` collector. Every action listed corresponds to a command in
`aws-cli-cheatsheet.md`; nothing more, nothing less.

## What this is

A standard AWS IAM policy document (version `2012-10-17`). It can be used in
any of these ways:

- **IAM Identity Center (SSO) Permission Set** — paste the JSON into a new
  inline policy on the permission set, or upload it as a customer-managed
  policy and attach it to the permission set. Recommended approach.
- **IAM Role** — attach as an inline or customer-managed policy on a role
  that the collector assumes (e.g. a cross-account `ATO-Read` role).
- **IAM User** — attach as a customer-managed policy. Only for hosts that
  cannot use SSO (rare; prefer SSO).

## Deploying as a customer-managed policy

```bash
aws iam create-policy \
  --policy-name ATOReadOnlyCollector \
  --policy-document file://iam-permission-set.json \
  --description "Read-only permissions for the ato-source-aws evidence collector"
```

Then attach it to the permission set / role / user as appropriate.

## Deploying as an Identity Center permission set inline policy

In the AWS console: IAM Identity Center → Permission sets → Create →
"Custom permissions" → paste the JSON into the inline policy editor.
Assign the permission set to the user or group that runs ATO collection,
across the accounts in scope.

## What's deliberately excluded

These would be tempting "just in case" additions but are **not** included
because the skill never invokes them:

| Excluded action prefix | Reason |
|---|---|
| `*:Create*`, `*:Put*`, `*:Delete*`, `*:Update*`, `*:Modify*`, `*:Attach*`, `*:Detach*`, `*:Tag*`, `*:Untag*` | Skill is read-only by contract |
| `sts:AssumeRole` | Skill consumes ambient credentials only |
| `ssm:SendCommand`, `ssm:StartSession` | Out of scope; not on the cheatsheet |
| `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey` | Data-plane crypto operations are forbidden |
| `s3:GetObject`, `s3:ListBucket` (object listing) | Skill reads bucket *metadata* only, never object content |
| Any IAM data-plane secret access (e.g. retrieving access keys) | Forbidden by the redaction rule |

## What's intentionally included that may surprise you

- `iam:GenerateCredentialReport` — this is technically a "write" verb in
  AWS terminology (it creates the report file) but the report *is* the
  evidence and the operation has no other side effects. `SecurityAudit` and
  `ViewOnlyAccess` AWS-managed policies both include it.
- `s3:GetBucketLocation` and `ec2:DescribeRegions` — needed to build correct
  console permalinks for citations and to validate the region allow list at
  runtime.
- `cloudtrail:ListTrails` — included alongside `DescribeTrails` because the
  CLI may fall back to it for cross-region enumeration.
- `iam:GetPolicy`, `iam:GetPolicyVersion`, `iam:List*Policies`,
  `iam:Get*Policy`, `iam:ListGroupsForUser`, `iam:GetUser`, `iam:GetGroup`,
  `iam:ListEntitiesForPolicy` — required by Step 6 (Synthesize) to expand
  each principal's effective permissions inline in its Markdown digest.
  Without these, the assessor would only see policy ARNs and have to look
  the contents up by hand. These are the same reads `SecurityAudit` and
  `ViewOnlyAccess` grant; we name them explicitly for an auditable
  least-privilege definition.
- `kms:GetKeyRotationStatus`, `kms:ListGrants`, `kms:ListResourceTags` —
  needed to embed each customer-managed key's rotation state and grants in
  its digest.
- `ec2:DescribeSubnets`, `ec2:DescribeRouteTables`,
  `ec2:DescribeVpcPeeringConnections` — needed for the per-VPC digest's
  noted-only references table.

## Comparison to AWS-managed policies

You could substitute the AWS-managed `SecurityAudit` policy and get most of
these permissions plus a lot more. We deliberately do **not** recommend that:
this custom policy is tighter (least privilege), and changes to
`SecurityAudit` over time would silently expand the collector's reach.

If you must use a managed policy, `ViewOnlyAccess` is the closest fit but
omits `iam:GenerateCredentialReport` and `iam:GetCredentialReport`, which
the skill needs.

## GovCloud notes

The same JSON works in GovCloud (`us-gov-east-1`, `us-gov-west-1`). Service
principals and ARNs differ but action names are identical. Deploy the policy
into each partition (commercial and GovCloud) separately if you operate in
both.
