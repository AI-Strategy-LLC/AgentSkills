# SharePoint Discovery Patterns

> **Role of this table after pre-scan landed.** The patterns below are now a
> **first-pass filter** — they decide which files Step 4 (DISCOVER) considers
> as candidates and provide a `filename_hint` the `ato-doc-summarizer` agent
> uses only as a tie-breaker. The primary relevance signal is the agent's
> content-based summary of each candidate's first ~3 pages. In legacy mode
> (`"prescan": false` in the scope, or summarizer error) this table is the
> only signal — the same behavior as before pre-scan landed.

Maps filename patterns and SharePoint locations to the 20 control families in
`ato-artifact-collector/references/artifact-mappings.md`. When a file matches
multiple patterns, map it to every family that claims it and download-once /
copy-many across `{family}/evidence/`.

Pattern matching is case-insensitive.

## Full pattern table

| Family | Filename patterns | Notes |
|---|---|---|
| `ssp-sections/01-system-description` | `*SDD*`, `*System Design*`, `*Architecture*`, `*HLA*`, `*LLA*` | Also pull SSP for design sections |
| `ssp-sections/02-system-inventory` | `*Inventory*`, `*CMDB*`, `*Asset List*`, `*Component List*` | |
| `ssp-sections/09-configuration-management-plan` | `*CMP*`, `*Configuration Management Plan*`, `*Baseline*`, `*Hardening*` | |
| `controls/AC-access-control` | `*Access Control*`, `*RBAC*`, `*Role Matrix*`, `*Access Request*` | |
| `controls/IA-identification-authentication` | `*Authentication*`, `*MFA*`, `*Session*`, `*Password Policy*` | |
| `controls/AU-audit-accountability` | `*Audit*`, `*Logging*`, `*Log Retention*`, `*SIEM*` | Exclude "audit findings" → those go to risk-assessment |
| `ssp-sections/10-vulnerability-mgmt-plan` | `*Vulnerability*`, `*Patch*`, `*Scan Report*`, `*POA&M*` | POA&M also goes to risk-assessment |
| `ssp-sections/07-incident-response-plan` | `*IR*`, `*Incident Response*`, `*IRP*`, `*Playbook*` | |
| `ssp-sections/08-contingency-plan` | `*CP*`, `*Contingency*`, `*DR*`, `*Disaster Recovery*`, `*BCP*` | |
| `ssp-sections/06-policies-procedures` | `*Policy*`, `*Policies*`, `*SSP*`, `*System Security Plan*` | |
| `controls/PS-personnel-security` | `*Personnel*`, `*Background Check*`, `*Clearance*`, `*Onboarding*` | |
| `controls/AT-awareness-training` | `*Training*`, `*Awareness*`, `*Education*` | |
| `controls/MA-maintenance` | `*Maintenance*`, `*Patch Schedule*`, `*Change Log*` | |
| `controls/PE-physical-environmental` | `*Physical*`, `*Facility*`, `*Datacenter*`, `*Environmental*` | |
| `controls/MP-media-protection` | `*Media*`, `*Sanitization*`, `*Disposal*` | |
| `controls/SC-system-communications-protection` | `*Network*`, `*Topology*`, `*Firewall*`, `*TLS*`, `*VPN*` | |
| `ssp-sections/11-sdlc-document` | `*SDLC*`, `*Secure Development*`, `*Code Review*`, `*SAST*` | |
| `ssp-sections/12-supply-chain-risk-mgmt-plan` | `*Supply Chain*`, `*SBOM*`, `*Vendor*`, `*Third Party*` | |
| `ssp-sections/05-interconnections` | `*Interconnection*`, `*ISA*`, `*MOU*`, `*Data Sharing Agreement*` | |
| `ssp-sections/03-risk-assessment-report` | `*Risk Assessment*`, `*RA*`, `*POA&M*`, `*Audit Findings*`, `*Assessment Report*` | |

## Multi-family files

These filename shapes typically belong in multiple families:

| Filename shape | Families |
|---|---|
| `SSP*.docx` | `ssp-sections/06-policies-procedures` (primary), `ssp-sections/01-system-description`, `controls/AC-access-control`, `controls/IA-identification-authentication` |
| `POA&M*.xlsx` | `ssp-sections/10-vulnerability-mgmt-plan`, `ssp-sections/03-risk-assessment-report` |
| `ATO Package*` | all 20 — treat as an archive, inventory rather than download |
| `Risk Assessment*.docx` | `ssp-sections/03-risk-assessment-report`, `ssp-sections/10-vulnerability-mgmt-plan` |

## File types

Only download these extensions (from `file_types` in scope):

- `.docx`, `.doc`
- `.pdf`
- `.xlsx`, `.xls`
- `.pptx`, `.ppt`
- `.md`, `.txt`

Skip: any extension not in the scope's `file_types`, any file larger than
50 MB (log as `partial_failure: too_large`), any file inside a folder named
`Archive*` or `Old*` unless the scope explicitly includes it.

## Exclusions

Hard-skip these regardless of pattern match:
- Files whose name contains `DRAFT` if a same-named non-DRAFT version exists
  in the same folder (prefer the finalized version)
- Files inside `Recycle Bin` or `Preservation Hold Library`
- Files with `.tmp`, `.~lock`, `~$` prefixes (Office lock files)
