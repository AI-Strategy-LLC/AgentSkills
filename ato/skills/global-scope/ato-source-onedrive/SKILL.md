---
name: ato-source-onedrive
description: "Sibling of ato-artifact-collector. Collects NIST 800-53 evidence from OneDrive for Business via the pnp/cli-microsoft365 (`m365`) CLI. Invoked by the orchestrator when OneDrive scope is configured. Strictly read-only, ambient-auth, scope-confirmed. Pairs with the SharePoint sibling — both speak m365 — but operates on per-user OneDrive personal sites rather than team SharePoint sites. Do not invoke this skill directly unless you are running it as part of an ATO artifact collection."
---

# ATO Source — OneDrive for Business

This skill is a sibling of `ato-artifact-collector`. It discovers ATO-relevant
documents in **per-user OneDrive personal sites** (OneDrive for Business) and
hands them to the orchestrator as evidence files plus a citation batch.

OneDrive for Business is implemented as a personal SharePoint site under the
`https://<tenant>-my.sharepoint.com/personal/<upn-escaped>/` URL pattern; many
of the same `m365 spo *` commands work against it. The reason this skill is
separate from `ato-source-sharepoint`:

- **Different scope shape** — SharePoint scopes are sites + libraries +
  folders; OneDrive scopes are users + folders.
- **Different audit / privacy posture** — collecting from personal OneDrives
  needs explicit user buy-in (and often a delegated permission grant) that
  team SharePoint collections don't.
- **Independent enable/disable** — many ATO collections want SharePoint but
  not OneDrive (or vice versa); separate siblings let `--sharepoint` and
  `--onedrive` be independent flags on the orchestrator.

Read `~/.claude/skills/ato-artifact-collector/references/sibling-contract.md`
first — that file is the definitive contract. This skill implements it.

## Hard Rule: scope is the user's, never the working repo's

Same as the SharePoint sibling. When the user has configured a OneDrive
scope (via `.ato-package.yaml`, the orchestrator's interactive prompts, or
the `--onedrive` flag), this skill executes that scope. It does **not**
examine the working repository's license, visibility, owner, or open-source
status to decide whether to run.

The only reasons this skill refuses to scan a configured OneDrive are:

1. `enabled: false` (or absent) in the config / scope object.
2. `m365 status` shows no logged-in session (write `auth_missing` and exit).
3. The user declines at the in-session confirm prompt (`scope_declined`).
4. The scope object fails structural validation (`scope_invalid`).
5. The logged-in identity lacks delegated access to one of the configured
   user OneDrives (record per-user `partial_failures` and continue).

## Hard Rule: this skill never writes

Every command this skill runs is a read verb (`m365 spo file get`,
`m365 spo file list`, `m365 onedrive list list`, etc.). **Never** any write
verb against the tenant. The cheatsheet at
`references/m365-cheatsheet.md` (in the SharePoint sibling) lists the
allow-listed commands; OneDrive shares the same allow list.

## Hard Rule: ambient auth only

Same as the SharePoint sibling. The skill never reads a password, never
stores a token. All authentication happens outside the skill. The scope's
`auth.method` field drives the auth probe and the on-failure instruction —
see the SharePoint sibling's "Hard Rule: ambient auth only" section for the
table; OneDrive uses an identical method set.

**Auth probe**, at start of Step 2:

```bash
m365 status --output json
```

If `connectedAs` is null, write `.staging/onedrive-error.json` with
`auth_missing` and exit. Same fall-through to `~/.agent-skills/auth/auth.yaml`
that the SharePoint sibling uses (see the relevant section there).

## Hard Rule: per-user delegated access only

The logged-in identity must have **delegated access** to each configured
user's OneDrive. This typically means:

- The configured users have explicitly shared their relevant OneDrive
  folders with the operator's account (per-folder, per-user grants), **OR**
- The operator's account is a tenant-level eDiscovery / compliance / global
  admin with cross-OneDrive access (rare; usually only a designated
  compliance officer).

If neither is true, the m365 calls will return `403 Forbidden` and this
skill records the user under `partial_failures` with reason
`access_forbidden` and continues with the remaining users.

**This skill never broadens permissions to gain access.** It does not
suggest the user run `Add-SPOUser`, does not call `m365 spo user add`, does
not change role assignments. Permissions are an out-of-band human process.

## Workflow

```
1.   VALIDATE  → Parse scope object, sanity-check tenant and user UPNs
2.   AUTH      → Probe m365 status, fail fast if not logged in
3.   CONFIRM   → Show resolved scope (per-user OneDrives), ask y/N
4.   DISCOVER  → For each user, derive OneDrive site URL; list candidate files
4.5. PRE-SCAN  → scripts/onedrive-walk-extract.sh + Skill: ato-doc-summarizer
                 → produces .staging/onedrive-inventory.json
5.   COPY      → Move high/medium-confidence files from cache to
                 evidence/<family>/ with onedrive_ prefix
6.   EMIT      → Write .staging/onedrive-citations.json with prescan_id refs
```

## Step 1: Validate scope

The orchestrator passes a scope object shaped like:

```json
{
  "enabled": true,
  "tenant": "contoso",
  "users": [
    "alice@contoso.onmicrosoft.com",
    "bob@contoso.onmicrosoft.com"
  ],
  "folders": {
    "alice@contoso.onmicrosoft.com": ["/Documents/ATO", "/Documents/Compliance"]
  },
  "file_types": [".docx", ".pdf", ".xlsx", ".md"],
  "auth": { "method": "device-code" },
  "prescan": true,
  "staging_dir": "/abs/path/to/docs/ato-package/.staging",
  "evidence_root": "/abs/path/to/docs/ato-package"
}
```

Validate:

- `tenant` is a simple DNS label (no slashes, no scheme).
- `users` is non-empty; every entry is a UPN (`local@host`) shape.
- For each `folders[user]` key, the user must appear in `users`.
- Folder paths are SharePoint-relative (start with `/Documents` or
  another library inside the user's OneDrive). Empty / absent
  `folders[user]` means scan the user's `/Documents` library
  recursively.
- `file_types` is a non-empty subset of `[.docx, .pdf, .xlsx, .pptx,
  .md, .txt]`.
- `prescan` is boolean (default `true`).

Reject on any mismatch with `scope_invalid` and a specific error message.

## Step 2: Auth probe

Same shape as the SharePoint sibling — see the "Hard Rule: ambient auth
only" section above for the probe and on-failure flow.

## Step 3: Confirm scope

Print a block like this and ask for y/N. Do not proceed without an
affirmative answer.

```
About to scan OneDrive with the following scope:

  Tenant: contoso
  Logged in as: compliance-officer@contoso.onmicrosoft.com
  Users (2):
    - alice@contoso.onmicrosoft.com
        Folders (2):
          - /Documents/ATO
          - /Documents/Compliance
    - bob@contoso.onmicrosoft.com
        (entire /Documents library — no folder filter)
  File types: .docx, .pdf, .xlsx, .md

This will issue read-only m365 commands. Nothing in OneDrive will be
modified. Each user's OneDrive must already be shared with the
logged-in identity (delegated access). Proceed? [y/N]
```

The per-user OneDrive URLs are derived from the tenant + UPN:

```
upn         = alice@contoso.onmicrosoft.com
upn-escaped = alice_contoso_onmicrosoft_com   # @ and . → _
site_url    = https://contoso-my.sharepoint.com/personal/alice_contoso_onmicrosoft_com
```

Show the derived URL in the confirm block when the operator runs the
skill in verbose mode (or when `auth.account_hint` is set), so they can
sanity-check.

## Step 4: Discover

For each configured user:

1. **Derive the user's OneDrive site URL** from the UPN (replace `@` and
   `.` with `_`, prepend `https://<tenant>-my.sharepoint.com/personal/`).
2. **Pick discovery folders.** Default: `/Documents`. Per-user override:
   `folders[user]` if set.
3. **List files.** For each folder, run:

   ```bash
   # The user's OneDrive site
   site_url="https://contoso-my.sharepoint.com/personal/alice_contoso_onmicrosoft_com"

   m365 spo file list \
     --webUrl "$site_url" \
     --folder "/personal/alice_contoso_onmicrosoft_com/Documents/ATO" \
     --recursive \
     --output json
   ```

   The `--folder` value is the user's personal-site root joined with the
   configured folder path.

4. **Filter to `file_types`.** Drop entries whose extension is not in
   the allow list.

5. **Filter directory exclusions.** Skip files under any path matching
   `Personal/`, `Recycle Bin/`, `.Trash/`. (Unlike SMB, OneDrive doesn't
   conventionally have `Archive/` or `Old/` directory names — but skip
   them if encountered.)

### 4.x — Persist the merged candidates JSON

Same shape as the SharePoint sibling produces. Each entry has
`site_url`, `server_relative_url`, `filename`, `size_bytes`, `mtime`.
Persist at `.staging/onedrive-discovery.json`.

## Step 4.5: Pre-scan (skippable)

If `scope.prescan: false`, skip to the legacy flow at the end.

### 4.5a — Run the extractor script

```bash
"$skill_dir/scripts/onedrive-walk-extract.sh" \
  --candidates-json "$STAGING_DIR/onedrive-discovery.json" \
  --staging-dir "$STAGING_DIR" \
  --cache-subdir "onedrive-cache" \
  --excerpt-subdir "onedrive-excerpts" \
  --manifest-name "onedrive-manifest.json" \
  --source onedrive
```

### 4.5b — Invoke the summarizer agent

```
Skill: "ato-doc-summarizer"
Args (JSON):
{
  "manifest_path":     "<STAGING_DIR>/onedrive-manifest.json",
  "inventory_path":    "<STAGING_DIR>/onedrive-inventory.json",
  "inventory_md_path": "<STAGING_DIR>/onedrive-inventory.md"
}
```

### 4.5c — Legacy flow (`prescan: false` or summarizer error)

Each matched file is downloaded directly to
`{evidence_root}/{family}/evidence/onedrive_{filename}` with the family
chosen from the filename pattern in `references/discovery-patterns.md`.
Citation rows have `prescan_id: null`.

## Step 5: Copy (high/medium-confidence only)

Same logic as the SharePoint sibling's Step 5:

```bash
jq -r '
  .files
  | map(select(.confidence == "high" or .confidence == "medium"))
  | .[]
  | [.id, .path, .suggested_family, (.suggested_controls | join(",")), .confidence]
  | @tsv
' "$STAGING_DIR/onedrive-inventory.json"
```

For each row, the manifest entry's top-level `cache_file` field points at
the downloaded original. Move it to:

- `{evidence_root}/{suggested_family}/evidence/onedrive_{filename}` for
  SSP-section slugs
- `{evidence_root}/{suggested_family}/evidence/{CONTROL-ID}/onedrive_{filename}`
  for control-folder slugs

**Filename collisions across users.** When two users have a same-named
file (`SSP.docx` from alice + bob), prefix with the user's UPN-local-part:

```
onedrive_alice__SSP.docx
onedrive_bob__SSP.docx
```

The user's UPN local part is read from the manifest's `source_meta.user_upn`
(see manifest schema below).

**Secret scan before writing**: same regexes as the SharePoint sibling.

## Step 6: Emit citation batch

Write `{staging_dir}/onedrive-citations.json`. Placeholder IDs `OD-001`,
`OD-002`, … (the orchestrator renumbers on merge).

Each row carries pre-scan provenance (`prescan_id`, `prescan_confidence`,
`purpose`) per the same shape the SMB and SharePoint siblings use. The
`link` field is the full HTTPS URL into the user's OneDrive — the
assessor must already have access to follow it. Per-user UPN is recorded
in the row's `source_meta` block so an assessor can tell which OneDrive
sourced the evidence.

```json
{
  "id_placeholder": "OD-001",
  "prescan_id": "onedrive-pre-001",
  "prescan_confidence": "high",
  "source": "onedrive",
  "purpose": "<the agent's 2-3 sentence summary>",
  "controls": ["AC-2", "AC-2(3)"],
  "evidence_file": "controls/AC-access-control/evidence/AC-2/onedrive_alice__access-review-Q1.xlsx",
  "link": "https://contoso-my.sharepoint.com/personal/alice_contoso_onmicrosoft_com/Documents/ATO/access-review-Q1.xlsx",
  "source_meta": { "user_upn": "alice@contoso.onmicrosoft.com" }
}
```

## Failure modes

Honor the matrix in `sibling-contract.md` exactly:

| Failure | File written to staging/ | Exit |
|---|---|---|
| m365 not logged in | `onedrive-error.json` with `auth_missing` | return |
| User declines at confirmation | `onedrive-error.json` with `scope_declined` | return |
| Scope validation failed | `onedrive-error.json` with `scope_invalid` | return |
| One user's OneDrive 403 | `onedrive-citations.json` with successes + `partial_failures` array (per-user `access_forbidden`) | return |

Under no circumstances does this skill halt the orchestrator. It always
writes a file into `.staging/` and returns so the next sibling can run.

## References

- `references/discovery-patterns.md` — filename patterns per control family
- `references/evidence-schema.md` — citation batch JSON format and file naming
- `../ato-source-sharepoint/references/m365-cheatsheet.md` — allow-listed
  m365 commands (shared with SharePoint; OneDrive uses the same set)
