# SMB Discovery Patterns

> **Role of this table after pre-scan landed.** The patterns below are now
> a **first-pass filter** — they decide which extensions and which
> directories the walker considers, and they provide a `filename_hint`
> that the `ato-doc-summarizer` agent uses only as a tie-breaker. The
> primary relevance signal is the agent's content-based summary of each
> file's first ~3 pages. In legacy mode (`"prescan": false` in the
> scope, or summarizer error) this table is the only signal — the same
> behavior as before pre-scan landed.

Same shape as the SharePoint pattern table — filename patterns mapped to
the 20 control families. Matching is case-insensitive.

| Family | Filename patterns |
|---|---|
| `ssp-sections/01-system-description` | `*SDD*`, `*System Design*`, `*Architecture*` |
| `ssp-sections/02-system-inventory` | `*Inventory*`, `*CMDB*`, `*Asset*` |
| `ssp-sections/09-configuration-management-plan` | `*CMP*`, `*Baseline*`, `*Hardening*`, `*Change Request*` |
| `controls/AC-access-control` | `*Access Control*`, `*RBAC*`, `*Access Request*` |
| `controls/IA-identification-authentication` | `*Authentication*`, `*MFA*`, `*Password Policy*` |
| `controls/AU-audit-accountability` | `*Audit*`, `*Log Retention*`, `*SIEM*` |
| `ssp-sections/10-vulnerability-mgmt-plan` | `*Vulnerability*`, `*Patch*`, `*POA&M*` |
| `ssp-sections/07-incident-response-plan` | `*IR*`, `*Incident*`, `*Playbook*` |
| `ssp-sections/08-contingency-plan` | `*CP*`, `*Contingency*`, `*DR*`, `*Runbook*`, `*BCP*` |
| `ssp-sections/06-policies-procedures` | `*Policy*`, `*Policies*`, `*SSP*` |
| `controls/PS-personnel-security` | `*Personnel*`, `*Background*`, `*Clearance*` |
| `controls/AT-awareness-training` | `*Training*`, `*Awareness*` |
| `controls/MA-maintenance` | `*Maintenance*`, `*Change Log*` |
| `controls/PE-physical-environmental` | `*Physical*`, `*Facility*`, `*Datacenter*` |
| `controls/MP-media-protection` | `*Media*`, `*Sanitization*`, `*Disposal*` |
| `controls/SC-system-communications-protection` | `*Network*`, `*Firewall*`, `*VPN*` |
| `ssp-sections/11-sdlc-document` | `*SDLC*`, `*Code Review*` |
| `ssp-sections/12-supply-chain-risk-mgmt-plan` | `*Supply Chain*`, `*SBOM*`, `*Vendor*` |
| `ssp-sections/05-interconnections` | `*ISA*`, `*MOU*`, `*Interconnection*` |
| `ssp-sections/03-risk-assessment-report` | `*Risk Assessment*`, `*Assessment Report*`, `*POA&M*` |

## File type allow list

Only `.docx`, `.doc`, `.pdf`, `.xlsx`, `.xls`, `.pptx`, `.ppt`, `.md`,
`.txt`. Anything else is skipped.

## Directory exclusions

Hard-skip these directories regardless of depth:

- `Archive`, `Archives`, `Old`, `Obsolete`, `Deprecated`
- `Personal`, `My Documents` (user-scoped content is out of scope)
- `Recycle Bin`, `$RECYCLE.BIN`, `.Trash`, `.Trashes`
- Anything matching `Backup*` older than 2 years (use mtime)

## Size and traversal limits

- Max file size: 50 MB — larger files are logged as `too_large`
- Max depth: from config (`smb.depth`, default 3)
- Max files per share: 500 — if exceeded, stop and log `truncated_results`
