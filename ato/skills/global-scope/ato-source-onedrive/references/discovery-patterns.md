# OneDrive Discovery Patterns

> **Role of this table after pre-scan landed.** The patterns below are now a
> **first-pass filter** — they decide which files Step 4 (DISCOVER) considers
> as candidates and provide a `filename_hint` the `ato-doc-summarizer` agent
> uses only as a tie-breaker. The primary relevance signal is the agent's
> content-based summary of each candidate's first ~3 pages. In legacy mode
> (`"prescan": false` in the scope, or summarizer error) this table is the
> only signal — the same behavior as before pre-scan landed.

OneDrive for Business is a per-user personal SharePoint site, so the same
filename-pattern → control-family mapping the SharePoint sibling uses applies
here. The relevant difference is **what kinds of documents tend to live in
OneDrive vs. team SharePoint**:

- **In a team SharePoint site (`ato-source-sharepoint`):** the formal SSP,
  IRP, CMP, POA&M, training records, signed authorization letters — the
  artifacts the team has agreed are authoritative.
- **In OneDrive (`ato-source-onedrive`):** working drafts, in-progress
  evidence collections, individual user contributions to ATO evidence (e.g.
  a security architect's draft of the SDD before it's promoted to
  SharePoint), one-off compliance attestations the user has personally
  collected.

Treat OneDrive evidence as **supporting** the SharePoint baseline, not
replacing it. Pre-scan confidence tiers are calibrated the same way.

## Filename → control-family map

Same shape and semantics as the SharePoint sibling's table. See
[`../../ato-source-sharepoint/references/discovery-patterns.md`](../../ato-source-sharepoint/references/discovery-patterns.md)
for the full pattern set; the OneDrive sibling reuses every row. The
agent applies the same per-family rubric.

Pattern matching is case-insensitive.

## Per-user prefix on cross-user collisions

When two users have a same-named file (`SSP.docx` from alice + bob), the
calling skill prefixes the evidence-folder filename with the UPN-local-part:

```
onedrive_alice__SSP.docx
onedrive_bob__SSP.docx
```

The summarizer agent does not care about this — it's purely a filesystem-
collision avoidance step in the skill's COPY phase.

## File type allow list

`.docx`, `.doc`, `.pdf`, `.xlsx`, `.xls`, `.pptx`, `.ppt`, `.md`, `.txt`.
Anything else is skipped.

## Folder exclusions inside a user's OneDrive

OneDrive doesn't conventionally use the `Archive/` / `Old/` directory naming
that SMB shares do. Skip these folder names regardless:

- `Recycle Bin`, `.Trash`, `.Trashes`
- `Forms` (auto-generated SharePoint admin folder)
- Anything starting with `__OneDrive` (tooling-generated)

## Size and traversal limits

- Max file size: 50 MB — larger files are recorded as `too_large` in the
  manifest's `skipped` array.
- The skill's discovery walks recursively from the user's `/Documents`
  library root (or per-user `folders[user]` overrides), with no explicit
  depth limit — OneDrive personal libraries are typically shallow enough
  not to need one. If a future ATO collection lands in a deeply nested
  user OneDrive, add `depth` to the scope schema.
- No max-files-per-user cap by default; if the candidates list exceeds
  ~500 entries, log to `partial_failures` and consider raising the
  question with the user.
