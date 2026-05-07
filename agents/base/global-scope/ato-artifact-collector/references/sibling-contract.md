# Sibling Skill Contract

Every `ato-source-*` sibling skill implements this contract. The
`ato-artifact-collector` orchestrator invokes siblings via the Skill tool and
relies on their outputs landing in well-known locations. Siblings that deviate
from this contract will not integrate cleanly.

## Identity

Sibling skills live at `~/.claude/skills/ato-source-{name}/` where `{name}` is
one of: `sharepoint`, `aws`, `azure`, `smb`. Each sibling has:

```
ato-source-{name}/
├── SKILL.md                          ← Hard rules, scope query, discovery, handoff
└── references/
    ├── discovery-patterns.md         ← What to look for, per control family
    ├── evidence-schema.md            ← File naming, citation batch format
    └── {tool}-cheatsheet.md          ← CLI/MCP commands the skill uses
```

## Hard rules — every sibling must state these up front

Every sibling's SKILL.md opens with these rules. They are not optional.

1. **Read-only.** The skill uses only `get`, `list`, `describe`, and `download`
   verbs. Any mutating API (`put`, `create`, `delete`, `update`, `attach`, etc.)
   is forbidden in the skill's instructions. If the user asks the sibling to
   "also fix X" — refuse, escalate to the orchestrator, and let the user run a
   different skill.

2. **Ambient auth only, never stored credentials.** The sibling requires the
   user to have already logged in via whatever native flow the operator's
   environment uses. The sibling never reads credentials from the config
   file, never prompts for a password and caches it, never stores a token.
   On auth failure, fail loud with a specific login instruction.

   **The config's `auth:` block (per source) is environment-configurable.**
   Each sibling supports multiple `auth.method` values — for example Azure
   supports `device-code`, `interactive`, `helper`, and `existing`; AWS
   supports `sso`, `profile`, `env`, and `instance`; SharePoint supports
   `device-code`, `interactive`, `service-account`, and `existing`. The
   sibling picks its probe and its on-failure instruction based on the
   configured method. A user-supplied `login_instruction` override (string
   from config) replaces the default failure message verbatim, so teams can
   point operators at their own runbooks without the sibling needing to know
   anything about those flows.

   The Azure sibling additionally supports a `helper_command` — a path to a
   **user-owned executable** that wraps whatever credential-acquisition flow
   the environment uses (1Password → `az login`, an internal identity broker,
   a federal SSO shim, etc.). The sibling invokes the helper as a subprocess
   and checks its exit code; it **never reads the helper's contents** and
   never sees any secrets the helper touches. This is the extension point
   for environment-specific auth without weakening the "sibling never holds
   credentials" rule.

   What stays constant across all methods: no secrets in the config file; no
   login attempts beyond the one optional helper invocation; no interactive
   password prompts from inside the sibling itself.

3. **Scope confirmation in-session.** Even when the scope object is fully
   pre-configured, the sibling displays a human-readable summary of what it's
   about to touch (tenant, sites, accounts, regions, UNC paths) and asks for
   explicit y/N confirmation before the first external call. This is the last
   line of defense against misconfiguration.

4. **US-only for cloud sources.** AWS and Azure siblings validate every region
   in scope against the hard-coded US allow list in
   `ato-artifact-collector/references/config-schema.md`. A single non-US region
   in scope causes the sibling to refuse the whole run with a specific error
   naming the offending region. No "skip and continue" — fail closed.

5. **Never exfiltrate secrets.** If a sibling stumbles onto something that
   looks like a secret (`password=`, API key, private key PEM, etc.) inside
   an evidence file it would otherwise download, the sibling skips the file,
   logs the skip, and continues. Evidence is for assessors, not an attacker
   dump.

## Inputs

The orchestrator invokes the sibling with a scope object resolved from the
merged config. The sibling's SKILL.md defines its own scope shape; see each
sibling for specifics. Common fields:

- `enabled: true` — always true when the orchestrator invokes the sibling
  (disabled sources are never called)
- Source-specific scope fields (sites, accounts, subscriptions, shares, etc.)
- `staging_dir` — absolute path to `docs/ato-package/.staging/` in the repo
- `evidence_root` — absolute path to `docs/ato-package/` (so the sibling knows
  where to drop files under either `ssp-sections/<NN>-<slug>/evidence/` or
  `controls/<CF>-<slug>/evidence/<CONTROL-ID>/`)

## Outputs

The sibling writes to two locations:

### 1. Evidence files

Copied or exported files land in **one** of the two destinations
defined by the orchestrator's Step 3 layout, with a source prefix so
they can never collide with repo-sourced evidence:

- `docs/ato-package/ssp-sections/<NN>-<slug>/evidence/<source>_<file>` —
  for document-shaped artifacts that satisfy an SSP section (an SSP
  itself, an IRP attachment, a CMP, an ISA/MOU, a POA&M).
- `docs/ato-package/controls/<CF>-<slug>/evidence/<CONTROL-ID>/<source>_<file>` —
  for per-control evidence (an IAM role definition for AC-2, an NSG
  rule for SC-7, a CloudTrail trail for AU-2, etc.).

**Siblings always write at the base-control level** (e.g.
`controls/AC-access-control/evidence/AC-02/aws_iam-role.json`). They do
**not** write into per-Determine-If-ID sub-folders
(`controls/AC-access-control/evidence/AC-02/AC-02(a)/...`). Sub-control
routing is the orchestrator's responsibility — Step 4.6 reads each
sibling's evidence file and emits per-Determine-If-ID
`<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_relevant-evidence.md` manifests that reference parent-level files by
relative path. This keeps siblings simple (no need to classify which
sub-letter or enhancement an IAM role addresses) and keeps the package
free of duplicate evidence files. The citation batch's `controls` array
(see "Citation batch" below) MAY include sub-control IDs like `AC-2(3)`
when the sibling is confident about the mapping; the orchestrator uses
those hints when generating manifests, but does not require them.

Source prefixes:

- `sharepoint_*` — SharePoint downloads (almost always SSP-section)
- `aws_*` — AWS JSON exports, IAM reports, Config compliance JSON, etc.
  (almost always control-folder, sub-folder named for the control ID)
- `azure_*` — Azure JSON exports, policy state, NSG rules, etc.
  (almost always control-folder)
- `smb_*` — copies from SMB shares (mix of SSP-section docs and
  control evidence — depends on what the file is)
- `vulnscan` (no prefix on filenames) — the vulnerability scanner
  writes dated finding reports as
  `vulnerability-scan-{YYYY-MM-DD}.md` directly into
  `controls/RA-risk-assessment/evidence/RA-5/`,
  `controls/SI-system-information-integrity/evidence/SI-2/`, and
  `ssp-sections/10-vulnerability-mgmt-plan/evidence/`. The dated
  filename is itself the source identifier; no `vulnscan_*` prefix
  is applied. The scanner is invoked as an **agent + thin stub** rather
  than a skill (the only sibling shaped that way) and runs in Step 1.5,
  before the cloud/share siblings — so its citation batch is in
  `.staging/` by the time Step 7's merge runs.

The slug and routing target come from the discovery-pattern table in
the sibling's own `references/discovery-patterns.md`, which
cross-references the orchestrator's `references/artifact-mappings.md`
and the routing table at the bottom of the orchestrator's Step 4
("File naming convention").

#### 1a. Per-resource digest companions

Cloud siblings (`aws`, `azure`) additionally write a Markdown digest
companion next to each significant JSON evidence file. The digest:

- Sits in the same `evidence/` folder as the JSON, with the same source
  prefix and a per-resource name (e.g. `aws_iam-role-app-runtime.md`,
  `azure_role-assignment-22222222.md`).
- Contains a 1–3 sentence plain-English summary, a Key Settings table
  (5–12 rows), every "critical" linked resource embedded inline as full
  JSON (e.g. an IAM user's attached policy documents, a role
  assignment's role definition body), and a noted-only references table
  for non-critical dependencies.
- Is the **human-facing** evidence; the JSON remains the verbatim ground
  truth. Step 7 prefers the digest as the link target in
  `CODE_REFERENCES.md` when both are present.

The full digest spec lives in each cloud sibling's
`references/evidence-schema.md` "Per-resource digest companion" section
and `references/digest-templates.md` ready-to-fill templates.

SharePoint and SMB siblings do not produce digests — their evidence is
already a human-readable document.

### 2. Citation batch

One JSON file per sibling at
`docs/ato-package/.staging/{source}-citations.json`:

```json
{
  "source": "sharepoint",
  "generated_at": "2026-04-14T10:32:00Z",
  "scope_summary": "tenant=contoso, 1 site, 3 folders",
  "citations": [
    {
      "id_placeholder": "SP-001",
      "cited_by": ["ssp-sections/06-policies-procedures/policies-procedures-evidence.md"],
      "location": "SSP-v2.docx",
      "link": "https://contoso.sharepoint.com/sites/app-ato/Shared%20Documents/SSP-v2.docx",
      "purpose": "Prior approved SSP — baseline for this revision",
      "ssp_section": "06-policies-procedures",
      "control_families": [],
      "controls": ["PL-2"],
      "evidence_file": "ssp-sections/06-policies-procedures/evidence/sharepoint_SSP-v2.docx"
    },
    {
      "id_placeholder": "SP-002",
      "cited_by": ["controls/AC-access-control/ac-implementation.md"],
      "location": "Account-Review-2026-Q1.xlsx",
      "link": "https://contoso.sharepoint.com/sites/app-ato/Shared%20Documents/Account-Review-2026-Q1.xlsx",
      "purpose": "Quarterly account-review evidence for AC-2(3) inactive disable",
      "ssp_section": null,
      "control_families": ["AC"],
      "controls": ["AC-2", "AC-2(3)"],
      "evidence_file": "controls/AC-access-control/evidence/AC-2(3)/sharepoint_Account-Review-2026-Q1.xlsx"
    }
  ]
}
```

Field reference:

- `id_placeholder` — the sibling uses its own prefix (`SP-`, `AWS-`, `AZ-`,
  `SMB-`) and monotonic numbering within its batch. Step 7 renumbers these
  to contiguous `CR-NNN` IDs on merge.
- `cited_by` — array of paths (relative to `docs/ato-package/`) for the
  generated documents that should cite this evidence. May contain an
  SSP-section narrative, one or more control-family implementation
  statements, or both. The orchestrator concatenates the list into the
  `Cited by` column of `CODE_REFERENCES.md` (semicolon-separated). When
  the sibling can't pick a specific narrative, leave the array as
  `[evidence_file]` so the human author can incorporate it during review.
- `location` — human-readable locator: file name, ARN, resource ID, UNC path.
- `link` — the external URL or URI (see the link format table in Step 7 of
  the orchestrator).
- `purpose` — one-line description of why this matters.
- `ssp_section` — the slug of the SSP section this evidence supports
  (e.g. `06-policies-procedures`), or `null` if the evidence is purely
  per-control. Drives placement under `ssp-sections/<slug>/evidence/`.
- `control_families` — array of NIST 800-53 family two-letter codes
  whose implementation statement should pick up this evidence. May be
  empty when `ssp_section` is set and the evidence has no
  control-folder copy. Drives placement under each
  `controls/<CF>-<slug>/`.
- `controls` — array of one or more NIST 800-53 Rev 5 control identifiers
  that the citation is evidence for. Use the most specific form
  available: family code (`AC`), base control (`AC-2`), or enhancement
  (`AC-2(4)`). The orchestrator copies this list into the `Controls`
  column of `CODE_REFERENCES.md` during merge in Step 7. Required and
  drives the `evidence/<CONTROL-ID>/` sub-folder placement inside each
  control-family folder.
- `evidence_file` — path (relative to `docs/ato-package/`) of the local copy
  the sibling wrote. Must actually exist at merge time. For cloud
  siblings this is the raw JSON.
- `digest_file` *(optional, cloud siblings only)* — path (relative to
  `docs/ato-package/`) of the Markdown digest companion. Required when a
  per-resource digest was synthesized; omitted for aggregate-only
  exports where the digest *is* the evidence file. Step 7 prefers
  `digest_file` as the human-facing link in `CODE_REFERENCES.md`.

When the same evidence supports both an SSP section and one or more
control families (typical for things like the IRP document, an OpenShift
NetworkPolicy file, a CloudTrail config), copy the file into every
applicable destination and list every destination in `cited_by`.
`evidence_file` is the **canonical primary copy**; the sibling is
responsible for `cp`-ing the file into each additional destination it
declares so each top-level folder is self-contained.

### Staging cleanup

The staging directory is transient. The orchestrator deletes
`docs/ato-package/.staging/` at the end of Step 7 after successful merge.
Siblings must not assume files in `.staging/` persist beyond a single run.

## Document summarization protocol (optional)

Source siblings that produce **document evidence** (PDFs, Word, Markdown,
plain text — i.e. SMB and any future SharePoint / OneDrive / Box / S3-
documents sibling) MAY use the shared `ato-doc-summarizer` agent to
summarize candidate documents before deciding which to copy. This is
the only sibling-to-sibling invocation allowed by this contract;
summarization is a utility, not a peer source.

The contract:

1. **The sibling produces a manifest.** A source-specific extractor
   (e.g. `scripts/smb-walk-extract.sh`) walks the source, extracts the
   first ~3 pages of text from each candidate document into
   `.staging/{source}-excerpts/<sha1>.txt`, and writes a
   source-agnostic manifest at
   `.staging/{source}-manifest.json` matching the schema in
   `agents/base/global-scope/ato-doc-summarizer/references/manifest-contract.md`.
2. **The sibling invokes the summarizer.** Via
   `Skill: ato-doc-summarizer` with `manifest_path`,
   `inventory_path`, and `inventory_md_path` arguments. The agent reads
   each excerpt in its own context, applies the per-family rubric, and
   writes a JSON inventory (`{source}-inventory.json`) plus a
   glance-able Markdown summary (`{source}-inventory.md`).
3. **The sibling consumes the inventory** in its own DISCOVER /
   COPY / EMIT steps — copies high/medium-confidence files, records
   low-confidence files in `partial_failures` with reason
   `low_relevance_signal`, and threads `prescan_id` +
   `prescan_confidence` into citation batch rows.
4. **Document text never leaves the agent's context.** The sibling's
   own context only sees the agent's neutral 2–3 sentence summaries.
   The original documents are still copied byte-for-byte at COPY time
   (the secret-scan in Step 6 runs against the original, not the
   excerpt).

The summarizer is invoked **inside the sibling's own flow** — the
orchestrator does not invoke it directly. Cloud siblings (`ato-source-aws`,
`ato-source-azure`) collect JSON, not documents, so they have no use for
this protocol; they continue to write per-resource Markdown digests
inline.

## Failure modes

Siblings must handle these specific failure modes with specific exit behavior.
The orchestrator relies on these to distinguish "keep going with other
sources" from "halt the run".

| Failure | Sibling behavior | Orchestrator response |
|---|---|---|
| Ambient auth missing | Write `.staging/{source}-error.json` with `{"error": "auth_missing", "instruction": "Run: m365 login --authType deviceCode"}` and exit | Record failure, print instruction, continue with next source |
| Scope rejected at confirmation prompt | Write `.staging/{source}-error.json` with `{"error": "scope_declined"}` and exit | Record, continue with next source |
| Scope validation failed (non-US region, bad config) | Write `.staging/{source}-error.json` with `{"error": "scope_invalid", "detail": "region eu-west-1 not on US allow list"}` and exit | Record, continue with next source |
| Partial success (some files downloaded, one API call failed) | Write the citation batch with what succeeded; append `partial_failures: [...]` array to the batch JSON with per-failure detail | Merge the successful rows; note partials in INDEX.md under the family |
| Mutating API detected in instructions | Sibling refuses to run at all, writes error, exits | Halt the whole package — this is a bug in the sibling skill itself |

## Invocation pattern from the orchestrator

After Step 1 (Orient), for each source with `enabled: true` in the resolved
scope, the orchestrator invokes:

```
Skill: "ato-source-{name}"
Args: JSON-encoded scope object for this source + staging_dir + evidence_root
```

The orchestrator waits for the sibling to return before invoking the next
sibling. Siblings do not call each other. The orchestrator does not pass
credentials — the sibling relies entirely on ambient auth set up by the user.

After all enabled siblings have returned (success or failure), the
orchestrator proceeds to Step 4 (Generate) with evidence and staging
already populated.

## What siblings do NOT do

- **Do not generate narrative documents.** That's the orchestrator's job in
  Step 4. Siblings only collect evidence and register citations.
- **Do not write to `CODE_REFERENCES.md`.** Siblings write citation batches
  to `.staging/`. The orchestrator merges them in Step 7.
- **Do not modify files outside `docs/ato-package/`.** Especially: do not
  write to `~/.claude/skills/`, `~/.aws/`, `~/.azure/`, or any config
  location. Siblings are strictly output-to-package-only.
- **Do not run their own gap analysis.** The orchestrator owns the control
  family completeness model. Siblings just deliver what they find.
- **Do not prompt for credentials.** If ambient auth is missing, fail loud
  with a login instruction and exit.
