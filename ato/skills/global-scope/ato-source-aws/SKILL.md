---
name: ato-source-aws
description: "Sibling of ato-artifact-collector. Collects NIST 800-53 evidence from AWS via the mcp__AWS_API_MCP_Server__call_aws MCP tool. Invoked by the orchestrator when AWS scope is configured. Strictly read-only, ambient-auth, US-region-only, scope-confirmed. Do not invoke directly unless running an ATO collection."
---

# ATO Source — AWS

Read `~/.claude/skills/ato-artifact-collector/references/sibling-contract.md`
first. This skill implements that contract for AWS.

## Hard Rule: this skill never writes

Every call to `mcp__AWS_API_MCP_Server__call_aws` must be a `get-*`,
`list-*`, `describe-*`, or `download-*` verb on a read-only AWS IAM action.
**Never** `create-*`, `put-*`, `delete-*`, `update-*`, `attach-*`, `detach-*`,
`modify-*`, or `tag-*`. If the orchestrator or user asks this skill to fix an
IAM policy, rotate a key, remediate a finding, or change anything — refuse
and escalate.

The allow-listed commands live in `references/aws-cli-cheatsheet.md`. Any
command not on that list is forbidden.

## Hard Rule: ambient auth only

The skill never runs `aws configure`, never stores an access key, never
reads `~/.aws/credentials`. It only consumes whatever credentials the MCP
server can already see in its environment.

The `scope.auth.method` field tells the sibling which flow the user has set
up on this host, and drives both the auth probe and the on-failure
instruction. Supported methods:

| `auth.method` | Expectation | Default auth_missing instruction |
|---|---|---|
| `sso` *(recommended)* | IAM Identity Center session via a named profile | `Run: aws sso login --profile {profile}` — plus the `sso_start_url` from config if set |
| `profile` | Long-lived keys in `~/.aws/credentials` under `[{profile}]` | `Refresh credentials for profile {profile} (edit ~/.aws/credentials or run your org's key-rotation flow)` |
| `env` | `AWS_ACCESS_KEY_ID` / `AWS_SESSION_TOKEN` exported in the environment | `Export AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN (e.g. from 'aws sso login' or your identity broker), then re-run` |
| `instance` | Running on EC2/ECS/Lambda with an instance profile | `Instance role missing or expired — verify the host's IAM role is attached and has read-only permissions` |

If `scope.auth.login_instruction` is set, echo it verbatim in the
`aws-error.json` output instead of the default. This lets a team point its
operators at whatever identity broker they actually use (Okta, PingFederate,
`gimme-aws-creds`, etc.) without the skill needing to know anything about it.

**Auth probe:**

```
call_aws("aws sts get-caller-identity" + (profile ? " --profile " + profile : ""))
```

If the probe returns an `ExpiredToken`, `InvalidClientTokenId`,
`UnauthorizedOperation`, or similar auth error, write
`.staging/aws-error.json` with the resolved instruction and exit. Do not
attempt to refresh credentials yourself. Do not invoke `aws sso login`,
`aws configure`, or any browser flow — the skill only reads, it does not
manage sessions.

## Preauth via auth-config (optional)

Before the auth probe above, check for `~/.agent-skills/auth/auth.yaml`:

- If the file exists with permissions `0600` **and** contains an entry at
  `sources.aws`, invoke the `auth-config` skill to run that entry's preauth
  command (typically `op inject -i ...`, a vault lookup, an `aws-okta exec`
  wrapper, or a user-provided script). After preauth, rerun the probe.
- If the file is missing, or has no `sources.aws` entry, skip this step and
  proceed with the existing ambient-auth probe — the user hasn't opted in.
- If the file has permissions looser than `0600`, emit `auth_missing` with
  the detail `"~/.agent-skills/auth/auth.yaml must be chmod 600 before it
  will be read"` and stop.

`auth-config` is read-only: it reads the user's yaml, runs the preauth
command they configured, and returns. It never stores credentials or
modifies the yaml. If `sources.aws` references a vault CLI that isn't
installed, emit `auth_missing` with the install instruction.

This is additive to `scope.auth.method` — an `auth.yaml` entry takes
precedence when present, and the `scope.auth.method` defaults still apply
when it isn't.

## Hard Rule: US regions only

Before the first non-auth call, validate every region in scope against the
allow list in `ato-artifact-collector/references/config-schema.md`:

```
us-east-1, us-east-2, us-west-1, us-west-2, us-gov-east-1, us-gov-west-1
```

A single non-US region in scope causes this skill to refuse the entire run:

```json
{
  "error": "scope_invalid",
  "detail": "Region 'eu-west-1' is not on the US allow list. Allowed: us-east-1, us-east-2, us-west-1, us-west-2, us-gov-east-1, us-gov-west-1"
}
```

No "skip the bad region and continue" — fail closed on the whole sibling run.

## Workflow

```
1. VALIDATE  → Parse scope, check region allow list
2. AUTH      → sts get-caller-identity probe, verify account matches scope
3. CONFIRM   → Show resolved scope, ask y/N
4. DISCOVER  → Per service: list + describe read-only calls
5. EXPORT    → Write JSON exports to evidence/ with aws_ prefix
6. SYNTHESIZE → Walk critical-link table, fetch linked resources,
                 write per-resource Markdown digests next to each JSON
7. EMIT      → Write .staging/aws-citations.json (with digest_file refs)
```

The Synthesize step is what turns raw API output into something an
assessor can read in under a minute. The skill still pulls the full JSON
(that's the primary evidence), but for every significant resource it
also writes a Markdown digest with a one-paragraph summary, a key-
settings table, and any critical linked configuration embedded inline.
See `references/discovery-patterns.md` "Critical-link expansion" for
which children get embedded vs noted, and `references/digest-templates.md`
for the exact Markdown shape per resource type.

## Step 1: Validate scope

Scope object shape:

```json
{
  "enabled": true,
  "accounts": ["123456789012"],
  "regions": ["us-east-1"],
  "services": ["iam", "config", "cloudtrail", "securityhub", "guardduty", "s3", "kms"],
  "profile": "ato-read",
  "staging_dir": "/abs/path/.../.staging",
  "evidence_root": "/abs/path/.../docs/ato-package"
}
```

Validate:
- every `accounts[]` is a 12-digit string
- every `regions[]` is on the US allow list (see above)
- every `services[]` is a known discovery target
- `profile` is a plain identifier (no paths, no spaces)

## Step 2: Auth probe + account verification

```
call_aws("aws sts get-caller-identity --profile {profile} --output json")
```

The returned `Account` must match one of `scope.accounts`. If it doesn't,
refuse with `scope_invalid`: the user's active credentials point at a
different account than the scope claims. This prevents a misconfigured
profile from scanning the wrong environment.

## Step 3: Confirm scope

Print a human block and ask for y/N. On rejection, write `scope_declined`.

```
About to scan AWS with the following scope:

  Profile: ato-read
  Caller identity: arn:aws:sts::123456789012:assumed-role/ATO-Read/alice
  Accounts: 123456789012
  Regions: us-east-1
  Services: iam, config, cloudtrail, securityhub, guardduty, s3, kms

This skill will issue read-only AWS API calls via the AWS MCP server. No
create/put/delete verbs will be used. Proceed? [y/N]
```

## Step 4: Discover

For each service in scope, run the discovery commands from
`references/aws-cli-cheatsheet.md` and save output. High-level map:

| Service | Family | Key calls |
|---|---|---|
| IAM | `controls/AC-access-control` | `iam list-users`, `list-roles`, `list-policies`, `get-account-summary`, `generate-credential-report` |
| Config | `controls/CM-configuration-management` | `configservice describe-config-rules`, `describe-compliance-by-config-rule` |
| CloudTrail | `controls/AU-audit-accountability` | `cloudtrail describe-trails`, `get-trail-status`, `get-event-selectors` |
| Security Hub | `controls/RA-risk-assessment` | `securityhub get-findings --max-items 500` (summary only) |
| GuardDuty | `controls/IR-incident-response` | `guardduty list-detectors`, `get-detector`, `list-findings --max-items 500` |
| S3 | `controls/MP-media-protection` | `s3api list-buckets`, `get-bucket-policy`, `get-bucket-encryption` for in-scope buckets |
| KMS | `controls/SC-system-communications-protection` (crypto) | `kms list-keys`, `describe-key`, `list-aliases` |

See the cheatsheet for exact command forms, required flags, and output
handling.

## Step 5: Export

JSON exports go to `{evidence_root}/{family}/evidence/aws_{service}-{artifact}.json`.
Examples:

- `controls/AC-access-control/evidence/aws_iam-account-summary.json`
- `controls/AC-access-control/evidence/aws_iam-roles.json`
- `controls/CM-configuration-management/evidence/aws_config-compliance.json`
- `controls/AU-audit-accountability/evidence/aws_cloudtrail-trails.json`
- `controls/RA-risk-assessment/evidence/aws_securityhub-findings-summary.json`

**Secret scan before writing**: if a JSON blob contains a field matching
`password`, `secret`, `token`, `private_key`, `access_key` (case-insensitive),
redact that field's value to `"[REDACTED by ato-source-aws]"` before writing.
Most AWS read APIs don't return secrets, but IAM credential reports and
some findings may include access key IDs — those stay (IDs, not secrets)
but anything labeled `SecretAccessKey` is redacted.

For every JSON export, also compute a console permalink and include it in
the citation batch. Console link template:

```
https://console.aws.amazon.com/{service}/home?region={region}#{anchor}
```

Per-service anchor guidance lives in the cheatsheet.

## Step 6: Synthesize per-resource digests

Raw JSON is necessary but not sufficient. For every resource in
`references/discovery-patterns.md` "Per-resource digest scope", walk its
"Critical links" column, issue the corresponding read-only calls from
`aws-cli-cheatsheet.md`, and write a Markdown digest companion next to
the JSON.

The digest must:

1. **Lead with a plain-English summary.** One to three sentences naming
   the resource, what it does, and the security-relevant state. Cite
   specific values from the JSON ("`Action: *`", "console-access enabled
   without MFA", "rotation disabled, last used 2024-09-12").
2. **Include a Key Settings table.** 5–12 rows, each row picking a value
   the assessor will be asked about (ARN, creation, MFA, encryption alg,
   public-access flag) with a short Significance column.
3. **Embed critical linked resources inline.** When the discovery patterns
   table marks a child as "embed full JSON", fetch it via the cheatsheet's
   per-resource expansion calls and include the document verbatim under a
   "Critical links" section, one heading per child. *Example:* an IAM
   user's digest must contain the full JSON of every attached managed-
   policy current version, every inline policy, and the same for every
   group the user belongs to.
4. **List noted-only references in a table.** When a child is "noted",
   record the ARN/name + a one-line relationship + a pointer to the
   child's own digest if it was collected, else "not in scope".
5. **Never invent observations.** The "Observations" section is optional
   and may only contain bullets directly traceable to values shown
   elsewhere in the digest.

For aggregate-only exports (account summary, credential report, findings
summary, compliance summary), write a single roll-up digest that table-
of-contents the per-resource digests instead of duplicating their detail.

If a critical-link API call fails (`AccessDenied`, throttling, etc.),
do not skip the digest — write it with an inline failure record where
the embedded JSON would have been:

```markdown
#### AdministratorAccess (AWS-managed) — could not fetch

Error: AccessDenied — `iam:GetPolicyVersion` denied on
`arn:aws:iam::aws:policy/AdministratorAccess`. Check the collector's IAM
permission set.
```

…and append a `partial_failures` row to the citation batch.

The digest's redaction pass is the same as the JSON's: any value under a
field named `SecretAccessKey`, `Password`, `OAuthToken`, `ClientSecret`,
`PrivateKey` (case-insensitive) is replaced with
`"[REDACTED by ato-source-aws]"` before write — this applies to the
embedded JSON inside the Markdown too.

See `references/digest-templates.md` for ready-to-fill templates per
resource type, and `references/evidence-schema.md` for required digest
sections and the aggregate-digest shape.

## Step 7: Emit citation batch

Write `{staging_dir}/aws-citations.json`. One row per significant resource
(not one per JSON file — a single `iam-roles.json` may spawn 20 rows, one
per role). Use placeholder IDs `AWS-001`, `AWS-002`, …

Each row must include the new `digest_file` field whenever a per-resource
digest was synthesized in Step 6 (see `evidence-schema.md`). The
orchestrator prefers the digest as the human-facing link in
`CODE_REFERENCES.md` when both are present.

See `references/evidence-schema.md` for the exact JSON format.

## Failure modes

| Failure | File | Exit |
|---|---|---|
| sts get-caller-identity fails | `aws-error.json` with `auth_missing` | return |
| Caller account doesn't match scope | `aws-error.json` with `scope_invalid` | return |
| Non-US region in scope | `aws-error.json` with `scope_invalid` | return |
| User declines at confirmation | `aws-error.json` with `scope_declined` | return |
| One service API throttles or 403s | `aws-citations.json` with successes + `partial_failures` | return |

## References

- `references/discovery-patterns.md` — service → family map, per-resource
  citation granularity, critical-link expansion table, per-resource
  digest scope
- `references/evidence-schema.md` — JSON export naming, digest companion
  format, citation batch format (incl. `digest_file`)
- `references/aws-cli-cheatsheet.md` — allow-listed commands and anchors,
  including the per-resource expansion calls used during digest synthesis
- `references/digest-templates.md` — ready-to-fill Markdown templates for
  each resource type the digest covers
