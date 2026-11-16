# Summary Rubric — Mapping Excerpts to Control Families

The agent applies this rubric to each excerpt to pick a `suggested_family`
slug and a list of `suggested_controls`. The rubric is **content-based** —
it cares about cue words and document structure, not the filename. A
`filename_hint` from the manifest is only a tie-breaker when the excerpt
itself is ambiguous.

## How to use this rubric

1. Read the excerpt.
2. Identify the **document type** from structural cues (heading conventions,
   numbered procedures, role tables, dated entries, etc.). Look for one of
   the known shapes: policy, procedure, runbook, plan, matrix, log,
   schedule, report, template, agreement.
3. Identify **content domain** cue words from the tables below. The
   strongest match (multiple cues, directly about the family's scope) wins.
4. Pick the **most specific** slug. SSP-section slugs (under
   `ssp-sections/`) are reserved for documents that are *the* SSP-section
   artifact (a CMP, an IRP, a CP). Per-control evidence (a single role
   matrix, a quarterly review export, a baseline diff) goes under
   `controls/<CF>-<slug>/`.
5. Assign confidence (`high` / `medium` / `low`) per the criteria in the
   agent body.
6. For `suggested_controls`, pick the listed base controls from the family
   row plus any enhancement that's clearly named in the excerpt (e.g. a
   document explicitly about "inactive account disable" → `AC-2(3)`).

## Slug → family → cue table (SSP-section artifacts)

These slugs are reserved for *the* document that satisfies an SSP section.
A general policy goes under `ssp-sections/06-policies-procedures` only if
it's the umbrella policy/procedures document; per-family policies (e.g. an
AC-only policy) go under `controls/AC-access-control/` instead.

| Slug | Document types | Cue words / phrases | Plausible base controls |
|---|---|---|---|
| `ssp-sections/01-system-description` | system design doc, architecture overview | "system architecture", "boundary", "components", "data flow", "diagram" | PL-2, PL-8, SA-3 |
| `ssp-sections/02-system-inventory` | inventory, CMDB export, asset list | "inventory", "asset", "CMDB", "hardware list", "software list", "FIPS-199" | CM-8, PM-5 |
| `ssp-sections/03-risk-assessment-report` | RA report, system risk assessment | "risk assessment", "threat", "likelihood", "impact rating", "residual risk" | RA-3, CA-2 |
| `ssp-sections/04-poam` | POA&M, plan of action and milestones | "POA&M", "plan of action and milestones", "milestone", "remediation date", "weakness ID" | CA-5, PM-4 |
| `ssp-sections/05-interconnections` | ISA, MOU, interconnection security agreement | "ISA", "MOU", "interconnection", "data exchange agreement", "trust boundary" | CA-3, SA-9 |
| `ssp-sections/06-policies-procedures` | umbrella SSP, master policy, procedures manual | "policy", "applies to all", "procedures manual", "SSP-v", "system security plan" | PL-2 |
| `ssp-sections/07-incident-response-plan` | IRP, incident response plan, playbook | "incident response", "IR plan", "playbook", "containment", "eradication", "post-incident" | IR-1, IR-4, IR-8 |
| `ssp-sections/08-contingency-plan` | CP, contingency plan, DR plan, BCP, runbook | "contingency", "RTO", "RPO", "disaster recovery", "DR drill", "BCP", "alternate site", "failover" | CP-1, CP-2, CP-9, CP-10 |
| `ssp-sections/09-configuration-management-plan` | CMP, configuration management plan | "configuration management plan", "baseline configuration", "change control board", "CCB", "hardening" | CM-1, CM-2, CM-9 |
| `ssp-sections/10-vulnerability-mgmt-plan` | VM plan, vulnerability management plan | "vulnerability management", "scan cadence", "remediation SLA", "patch", "CVE" | RA-5, SI-2 |
| `ssp-sections/11-sdlc-document` | SDLC doc, secure development lifecycle | "SDLC", "secure development", "code review", "threat modeling", "static analysis", "SCA" | SA-3, SA-8, SA-11, SA-15 |
| `ssp-sections/12-supply-chain-risk-mgmt-plan` | SCRM plan, vendor risk plan | "supply chain", "SBOM", "vendor risk", "third-party assessment" | SR-1, SR-2, SR-6 |
| `ssp-sections/13-conmon-plan` | continuous monitoring strategy | "continuous monitoring", "ConMon", "monthly scan cadence", "metrics dashboard" | CA-7, PM-31 |
| `ssp-sections/14-ato-letter` | ATO letter, AO authorization | "authorization to operate", "ATO", "authorizing official", "ATO memo" | CA-6 |

## Slug → family → cue table (per-control evidence)

These slugs hold control-level evidence: artifacts that demonstrate one or
more controls but are not themselves an SSP-section deliverable. The
calling skill writes them to `controls/<CF>-<slug>/evidence/<CONTROL-ID>/`.

| Slug | Document types | Cue words / phrases | Plausible base controls |
|---|---|---|---|
| `controls/AC-access-control` | RBAC matrix, access-request form, account review export | "RBAC", "role assignment", "least privilege", "account review", "access request", "account lockout", "session timeout" | AC-2, AC-3, AC-5, AC-6, AC-7, AC-11, AC-12 |
| `controls/AT-awareness-training` | training plan, completion report, awareness brief | "security awareness", "annual training", "phishing simulation", "completion rate" | AT-2, AT-3, AT-4 |
| `controls/AU-audit-accountability` | audit policy, log retention policy, SIEM design, audit-record review | "audit log", "log retention", "SIEM", "audit reduction", "audit record", "non-repudiation" | AU-2, AU-3, AU-6, AU-9, AU-11, AU-12 |
| `controls/CA-assessment-authorization` | assessment report, security control assessment, ATO package list | "control assessment", "SAR", "assessment plan", "interconnection ICA" | CA-2, CA-3, CA-7 |
| `controls/CM-configuration-management` | baseline config, hardening guide, change ticket export, software inventory diff | "baseline", "STIG", "CIS benchmark", "change ticket", "configuration item", "least functionality", "denylist", "approved software" | CM-2, CM-3, CM-6, CM-7, CM-8, CM-10 |
| `controls/CP-contingency-planning` | DR test record, backup verification report, CP training roster | "backup test", "restore test", "DR exercise", "tabletop", "alternate processing site" | CP-3, CP-4, CP-9 |
| `controls/IA-identification-authentication` | password policy, MFA design doc, PKI/credential lifecycle | "MFA", "multi-factor", "password complexity", "PIV", "FIDO2", "credential issuance", "device authentication" | IA-2, IA-3, IA-5, IA-8 |
| `controls/IR-incident-response` | incident report, post-incident review, IR drill record | "incident report", "after-action review", "IR drill", "lessons learned", "incident ticket" | IR-3, IR-4, IR-5, IR-6 |
| `controls/MA-maintenance` | maintenance log, vendor maintenance contract, change-window record | "maintenance window", "maintenance log", "remote maintenance", "vendor escort" | MA-2, MA-4, MA-5 |
| `controls/MP-media-protection` | media handling policy, sanitization log, media transport record | "media handling", "sanitization", "DBAN", "NIST 800-88", "media transport", "removable media" | MP-2, MP-4, MP-5, MP-6 |
| `controls/PE-physical-environmental` | facility access list, badge-system export, datacenter walkthrough log | "physical access", "badge", "visitor log", "datacenter", "fire suppression", "HVAC", "uninterruptible" | PE-2, PE-3, PE-6, PE-13, PE-14 |
| `controls/PL-planning` | system planning artifacts not covered elsewhere, rules-of-behavior signed forms | "rules of behavior", "ROB", "system planning" | PL-2, PL-4 |
| `controls/PM-program-management` | program-level governance, security program plan | "security program plan", "program governance", "security strategy" | PM-1, PM-2, PM-9 |
| `controls/PS-personnel-security` | personnel screening record, separation checklist, position-risk designation | "background check", "screening", "position risk", "separation", "transfer", "clearance" | PS-2, PS-3, PS-4, PS-5, PS-7 |
| `controls/PT-pii-processing-transparency` | privacy notice, PII inventory, data subject request log | "PII", "personal data", "data subject", "consent", "privacy notice", "system of records notice" | PT-2, PT-3, PT-5 |
| `controls/RA-risk-assessment` | risk register, threat model, vulnerability scan summary (system-level) | "risk register", "threat model", "STRIDE", "DREAD", "scan summary" | RA-3, RA-5, RA-9 |
| `controls/SA-system-services-acquisition` | acquisition policy, contract security clauses, developer security training | "acquisition", "FAR clause", "supplier security requirements", "SSDF", "developer training" | SA-3, SA-4, SA-9, SA-10, SA-11 |
| `controls/SC-system-communications-protection` | network design, NSG / firewall ruleset export, TLS policy, VPN config | "firewall rule", "NSG", "DMZ", "boundary protection", "TLS", "VPN", "DNSSEC", "key management" | SC-7, SC-8, SC-12, SC-13, SC-23 |
| `controls/SI-system-information-integrity` | flaw remediation policy, malware definitions update record, monitoring plan | "flaw remediation", "patch deployment", "malware", "EDR", "input validation", "monitoring" | SI-2, SI-3, SI-4, SI-7, SI-10 |
| `controls/SR-supply-chain-risk-management` | SBOM, supplier audit report, provenance attestation | "SBOM", "supplier audit", "provenance", "attestation", "tamper-evident" | SR-3, SR-4, SR-5, SR-6 |

## Confidence calibration examples

To keep confidence calls consistent across runs, use these calibration
examples:

**HIGH:**
- Excerpt is the first 3 pages of a numbered runbook with sections named
  "Trigger", "Containment", "Eradication", "Recovery", "Lessons Learned".
  Clearly an IR runbook → `ssp-sections/07-incident-response-plan`,
  controls `IR-4`, `IR-8`, confidence `high`.
- Excerpt is a table with headers `Role | Permissions | Approver` and rows
  like `App-Admin | Read+Write | Director of Engineering`. Clearly an RBAC
  matrix → `controls/AC-access-control`, controls `AC-2`, `AC-3`, `AC-5`,
  `AC-6`, confidence `high`.

**MEDIUM:**
- Excerpt mentions "procedures" multiple times but is generic boilerplate
  ("All employees shall follow appropriate security practices when handling
  data"). Could be PL-2 or PS-6 or a corporate handbook excerpt →
  `ssp-sections/06-policies-procedures`, controls `PL-2`, confidence
  `medium`, rationale notes the genericity.
- Excerpt is a few paragraphs about "backup" but doesn't specify whether
  it's testing, transport, or retention → `controls/CP-contingency-planning`,
  controls `CP-9`, confidence `medium`.

**LOW:**
- Excerpt is a meeting agenda or a fax cover sheet — no rubric hit.
  `suggested_family: null`, `suggested_controls: []`, confidence `low`,
  rationale "Excerpt appears to be administrative correspondence; no
  rubric match".
- Excerpt is empty (extractor returned no text). `summary: "(no text
  extracted)"`, confidence `low`.

## Cross-cutting documents

Some documents hit multiple families. Pick the **primary** family for
`suggested_family` and put every relevant control across families in
`suggested_controls`. Examples:

- An IR plan that mandates AC-2 lockout → primary
  `ssp-sections/07-incident-response-plan`, controls
  `IR-4, IR-8, AC-7`.
- A CMP that defines audit log baselines → primary
  `ssp-sections/09-configuration-management-plan`, controls
  `CM-2, CM-6, AU-12`.

The calling skill is responsible for routing to multiple destinations
(see the sibling-contract `cited_by` field). The agent's job is to label
the document accurately, not to do the routing.
