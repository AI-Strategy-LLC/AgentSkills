# ATO Agent Collection — User Guide

End-to-end instructions for using the ATO (Authority to Operate) skill + agent collection in this repo to produce a NIST 800-53 Rev 5 evidence package for a federal system.

This guide is task-oriented. If you just want to produce a package, jump to [Quick Start](#quick-start). If you want to understand how the pieces fit together first, read [Overview](#overview).

> **Audience.** Engineers, ISSOs, and compliance leads producing or maintaining an ATO package. The collection is read-only against external systems — it never mutates AWS / Azure / SharePoint / SMB resources, never modifies your source code, never installs tools, and never stores credentials.

---

## Table of contents

- [Overview](#overview)
- [What gets produced](#what-gets-produced)
- [The artifacts at a glance](#the-artifacts-at-a-glance)
- [Installation](#installation)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [CLI flags reference](#cli-flags-reference)
- [The orchestrator workflow](#the-orchestrator-workflow)
- [Output structure](#output-structure)
- [Authentication](#authentication)
- [Configuration — `.ato-package.yaml`](#configuration--ato-packageyaml)
- [Re-runs and idempotency](#re-runs-and-idempotency)
- [Standalone modes](#standalone-modes)
- [What controls the package addresses](#what-controls-the-package-addresses)
- [Troubleshooting](#troubleshooting)

---

## Overview

The ATO collection turns an existing source repository (plus optional cloud / SharePoint / SMB scope) into a structured evidence package suitable for an authoring team to walk into an ATO assessment with. The orchestrator does six things in one run:

1. **Discovers** evidence already in the repo (configs, IaC, threat models, IRP attachments, etc.).
2. **Pulls** evidence from external systems you opt into (AWS Config / IAM / CloudTrail; Azure Policy / RBAC / NSGs; SharePoint policy docs; SMB DR runbooks).
3. **Runs a vulnerability baseline** (cargo-audit, npm audit, pip-audit, govulncheck, dependency-check, trivy, gitleaks, semgrep, osv-scanner — whichever apply to the repo's languages and are on PATH).
4. **Generates** narrative documents (per-SSP-section evidence files and per-control-family implementation statements) that synthesize what was discovered.
5. **Indexes** everything in `INDEX.md`, `CHECKLIST.md`, and `CODE_REFERENCES.md` with stable `[CR-NNN]` citations linking back to source files / external resources.
6. **Optional follow-ons** — when you ask for them: a developer-facing remediation punch list and a federal-submission-shaped POA&M.

Everything lands under `docs/ato-package/` in the repo. Nothing is uploaded anywhere.

---

## What gets produced

A complete run with all opt-ins enabled writes:

```
docs/ato-package/
├── INDEX.md                        Master map of every artifact
├── CHECKLIST.md                    Per-item RED/YELLOW/GREEN status
├── CODE_REFERENCES.md              All [CR-NNN] citations resolved
├── REMEDIATION_GUIDANCE.md         (only when --remediation or asked)
│
├── ssp-sections/                   The 14 SSP-section narratives
│   ├── 01-system-description/
│   │   ├── system-description-evidence.md
│   │   └── evidence/               ← collected source files (Dockerfile, etc.)
│   ├── 02-system-inventory/
│   ├── 03-risk-assessment-report/
│   ├── 04-poam/
│   │   ├── poam-gap-analysis.md           ← collected/narrative
│   │   ├── poam-generated.md              ← (only when --poam)
│   │   └── poam-generated.csv             ← federal submission CSV
│   ├── 05-interconnections/
│   ├── 06-policies-procedures/
│   ├── 07-incident-response-plan/
│   ├── 08-contingency-plan/
│   ├── 09-configuration-management-plan/
│   ├── 10-vulnerability-mgmt-plan/
│   │   └── evidence/
│   │       └── vulnerability-scan-2026-04-29.md
│   ├── 11-sdlc-document/
│   ├── 12-supply-chain-risk-mgmt-plan/
│   ├── 13-continuous-monitoring-plan/
│   └── 14-privacy-impact-assessment/
│
└── controls/                       The 20 NIST 800-53 Rev 5 control families
    ├── _master-assessment.csv             ← Master GRC CSV (every Determine If ID across all 20 families)
    ├── AC-access-control/
    │   ├── ac-implementation.md           ← Family narrative; H3 sub-section per Determine If ID
    │   ├── ac-assessment.csv              ← Per-family GRC CSV
    │   └── evidence/
    │       ├── AC-02/                     ← Parent-level evidence files copied here
    │       │   ├── <files>
    │       │   ├── AC-02(a)/AC_AC-02_AC-02(a)_relevant-evidence.md
    │       │   ├── AC-02(d)/AC_AC-02_AC-02(d)_relevant-evidence.md
    │       │   ├── AC-02(01)/AC_AC-02_AC-02(01)_relevant-evidence.md
    │       │   └── AC-02(12)/AC-02(12)(b)/AC_AC-02_AC-02(12)(b)_relevant-evidence.md
    │       ├── AC-03/                     ← Single Determine If ID — no sub-control nesting
    │       │   ├── <files>
    │       │   └── AC_AC-03_relevant-evidence.md
    │       └── ...
    ├── AT-awareness-training/
    ├── AU-audit-accountability/
    ├── CA-assessment-authorization/
    │   └── evidence/CA-5/poam-generated.md     ← (only when --poam, dual-routed)
    ├── CM-configuration-management/
    ├── CP-contingency-planning/
    ├── IA-identification-authentication/
    ├── IR-incident-response/
    ├── MA-maintenance/
    ├── MP-media-protection/
    ├── PE-physical-environmental/
    ├── PL-planning/
    ├── PM-program-management/
    ├── PS-personnel-security/
    ├── PT-pii-processing-transparency/
    ├── RA-risk-assessment/
    │   └── evidence/RA-5/vulnerability-scan-2026-04-29.md   ← primary VS evidence
    ├── SA-system-services-acquisition/
    ├── SC-system-communications-protection/
    ├── SI-system-information-integrity/
    │   └── evidence/SI-2/vulnerability-scan-2026-04-29.md   ← SI-2 dual-route
    └── SR-supply-chain-risk-management/
```

Empty SSP sections and control families are still created — each carries a `*-gap-analysis.md` or `*-implementation.md` that names the gap explicitly. **No empty folders silently mean "no findings."**

---

## The artifacts at a glance

| Component | Type | What it does | Where to find it |
|---|---|---|---|
| `ato-artifact-collector` | Stub skill + agent | Orchestrator. The thing you invoke. 8-step workflow + Step 1.5 vuln scan + post-Step-8 follow-ons. | `skills/global-scope/ato-artifact-collector/` and `agents/base/global-scope/ato-artifact-collector/` |
| `ato-source-aws` | Skill | Read-only AWS evidence collector via `aws` CLI. US regions only. | `skills/global-scope/ato-source-aws/` |
| `ato-source-azure` | Skill | Read-only Azure evidence collector via `az` CLI. US regions only. | `skills/global-scope/ato-source-azure/` |
| `ato-source-sharepoint` | Skill | Read-only SharePoint / M365 / OneDrive collector via `m365` CLI. | `skills/global-scope/ato-source-sharepoint/` |
| `ato-source-smb` | Skill | Read-only SMB / Windows-share collector. macOS / Linux / Windows. | `skills/global-scope/ato-source-smb/` |
| `ato-vulnerability-scanner` | Stub skill + agent | Pre-collection vulnerability baseline (Step 1.5). Default-on. Standalone-invocable. | `skills/global-scope/ato-vulnerability-scanner/` and `agents/base/global-scope/ato-vulnerability-scanner/` |
| `ato-remediation-guidance` | Skill | Developer punch list — turns gaps into RG-NNN action items with file paths + acceptance criteria. | `skills/global-scope/ato-remediation-guidance/` |
| `ato-poam-generator` | Skill | POA&M generator — Markdown + federal-submission CSV. Stable POAM-NNNN across runs. | `skills/global-scope/ato-poam-generator/` |

The orchestrator invokes the others via the Skill tool; you only ever invoke the orchestrator (or the vulnerability scanner standalone, when you want a quick dependency / secret / SAST pass without the rest).

---

## Installation

The ATO collection is installed by the standard `install.sh`:

```bash
# from the AgentSkills repo root
bash install.sh --for claude
# or for multiple CLIs at once:
bash install.sh --for claude,opencode,codex
```

This installs:

- The 5 source skills (`ato-source-*`) and the 3 follow-on skills (`ato-remediation-guidance`, `ato-poam-generator`, `ato-vulnerability-scanner` stub) into your CLI's global skill directory.
- The 2 agents (`ato-artifact-collector`, `ato-vulnerability-scanner`) into your CLI's global agent directory, rendered for the chosen CLI.

Verify with `--list` first if you want a dry run:

```bash
bash install.sh --for claude --list
```

You should see lines for `ato-artifact-collector`, `ato-vulnerability-scanner`, `ato-poam-generator`, `ato-remediation-guidance`, and the four `ato-source-*` skills.

---

## Prerequisites

| For | Required | Optional but recommended |
|---|---|---|
| **Repo-only collection** | Nothing beyond Claude Code (or your CLI) | `gitleaks`, `semgrep`, `osv-scanner` for fuller vuln-scan coverage |
| **Vulnerability scanner — Rust** | `cargo` | `cargo-audit`, `cargo-deny` |
| **Vulnerability scanner — Node** | `npm`, `yarn`, or `pnpm` | (audit is bundled) |
| **Vulnerability scanner — Python** | — | `pip-audit`, `safety` |
| **Vulnerability scanner — Ruby** | — | `bundler-audit` |
| **Vulnerability scanner — Go** | `go` | `govulncheck` |
| **Vulnerability scanner — .NET** | `dotnet` (8+ for JSON output) | — |
| **Vulnerability scanner — Java/Kotlin** | `mvn` or `gradle` | OWASP Dependency-Check plugin |
| **Vulnerability scanner — PHP** | Composer 2.4+ | — |
| **Vulnerability scanner — Containers** | — | `trivy` |
| **Vulnerability scanner — Always** | — | `gitleaks`, `semgrep`, `osv-scanner` |
| **AWS source** | `aws` CLI, ambient AWS session (`aws sso login` etc.) | — |
| **Azure source** | `az` CLI, ambient Azure session | An `azureauth`-style helper script |
| **SharePoint source** | `m365` CLI, ambient M365 session | — |
| **SMB source** | OS mount tools (`mount_smbfs` / `mount.cifs` / native UNC) | Kerberos ticket for sites using AD auth |

The vulnerability scanner **never auto-installs** missing tools. Anything missing becomes a "Coverage gap" entry in the scan report — the run continues with whatever is available. Install what you want covered, then re-run.

For external-source authentication, see [Authentication](#authentication).

---

## Quick start

### Scenario 1 — "Just give me a baseline package for this repo"

```text
/ato-artifact-collector --repo
```

This skips the interactive interview, treats the run as repo-only, runs the vulnerability scanner, and writes the package. Takes ~5–15 minutes depending on toolchain breadth.

### Scenario 2 — "I want a complete federal-shaped package"

```text
/ato-artifact-collector --repo --remediation --poam
```

Same as Scenario 1, but also produces:

- `REMEDIATION_GUIDANCE.md` — developer punch list (RG-NNN items)
- `ssp-sections/04-poam/poam-generated.md` + `.csv` — POA&M tracker
- A CA-5 dual-route copy of the POA&M

### Scenario 3 — "We use AWS and SharePoint; pull in that evidence too"

First, log in:

```bash
aws sso login --profile <your-profile>
m365 login --authType [deviceCode|browser]
```

Then:

```text
/ato-artifact-collector --aws --sharepoint --remediation --poam
```

The orchestrator will read `~/.claude/skills/ato-artifact-collector/config.yaml` and `.ato-package.yaml` for the AWS account / region / SharePoint tenant config. If config is incomplete, it falls back to the interactive interview only for the missing pieces.

### Scenario 4 — "Everything"

```text
/ato-artifact-collector --aws --azure --sharepoint --smb --remediation --poam
```

Full multi-source collection plus the two follow-on artifacts.

### Scenario 5 — "I just want a vuln scan; no full collection"

```text
/ato-vulnerability-scanner
```

Writes to `docs/ato-package/controls/RA-risk-assessment/evidence/RA-5/` directly. Useful as a pre-PR safety check or to refresh the dated RA-5 history without re-running the orchestrator.

---

## CLI flags reference

All flags live on `/ato-artifact-collector`. The `ato-vulnerability-scanner` standalone skill takes no flags.

### Source-selection flags

| Flag | Effect |
|---|---|
| `--repo` | Mark repo scope explicitly. Always implied — the flag exists to make "repo-only, skip the interview" expressible. |
| `--aws` | Enable the AWS source. Skips the AWS y/N prompt. Requires ambient `aws` CLI auth. |
| `--azure` | Enable the Azure source. Skips the Azure y/N prompt. Requires ambient `az` CLI auth. |
| `--sharepoint sites:[<Site URL>]` | Enable the SharePoint / M365 source. Skips the SharePoint y/N prompt. Requires ambient `m365` CLI auth. |
| `--smb` | Enable the SMB source. Skips the SMB y/N prompt. Requires OS mount helpers configured. |

**Precedence rule.** If **any** source flag is present, the interactive scope-confirmation interview is skipped entirely; unflagged sources are disabled. If no source flags are present, the orchestrator falls back to interactive y/N prompts for any source not explicitly disabled in config.

### Output-control flags

| Flag | Effect |
|---|---|
| `--no-vuln-scan` | Disable the pre-collection vulnerability scan. By default the scan runs every collection (Step 1.5). |
| `--no-assessment` | Disable the assessment pass (Step 6.5) AND synthesis (Step 6.6). The orchestrator still emits the family narrative with H3 sub-sections + Determine If Statement, but skips Findings/Result and emits a 7-column CSV (no `Result`/`Findings` columns). |
| `--no-synthesize` | Disable synthesis (Step 6.6) only. Findings + Result still emit; gaps are named textually but no drafts are written and no `SYNTHESIZED_ARTIFACTS.md` inventory is produced. |
| `--accept-synthesized` | Auto-promote each synthesized draft to evidence (one folder up from `synthesized/`); flip Result to Satisfied for that Determine If ID. Loud signaling: end-of-run summary block, `INDEX.md` banner, `CHECKLIST.md` notes column. **Risky** — synthesized drafts make assertions about the system from code inspection alone and may disagree with org policy. The flag exists for fast iteration; review every promoted artifact before authoritative submission. |
| `--remediation` | Auto-invoke `ato-remediation-guidance` after Step 8. Without this flag, remediation guidance runs only when the user explicitly asks afterward. |
| `--poam` | Auto-invoke `ato-poam-generator` after the remediation step. **Implies `--remediation`** (POA&M consumes the remediation output). If passed alone, the orchestrator logs `[INFO] --poam implies --remediation; enabling.` and proceeds with both. |

### Examples

| Invocation | Result |
|---|---|
| (no args) | Interactive interview; default vuln-scan on |
| `--repo` | Skip interview; repo only; vuln scan on |
| `--repo --no-vuln-scan` | Skip interview; repo only; no vuln scan |
| `--repo --remediation` | Skip interview; repo only; vuln scan on; auto-remediation |
| `--repo --poam` | Skip interview; repo only; vuln scan on; auto-remediation (implied); POA&M |
| `--aws --azure` | Skip interview; AWS + Azure (no SharePoint, no SMB); vuln scan on |
| `--aws --azure --sharepoint --smb --remediation --poam` | Full external + follow-ons |

---

## The orchestrator workflow

```text
Step 0    SCOPE      Read config + flag-resolved scope from the stub
Step 1    ORIENT     Detect language, framework, CI/CD, infra, docs, git remote
Step 1.5  VULNSCAN   Pre-collection vulnerability baseline (skipped if --no-vuln-scan)
Step 2    DISCOVER   Scan repo for the 20 artifact categories;
                     invoke enabled sibling skills (AWS / Azure / SharePoint / SMB)
Step 3    COLLECT    Copy discovered files into docs/ato-package/
Step 4    GENERATE   Synthesize narrative documents with embedded Mermaid diagrams,
                     [CR-NNN] citations
Step 4.5  ENUMERATE  Build .staging/sub-control-inventory.json — every Determine If ID
                     for every in-scope control (sub-letters, enhancements, enhancement-with-sub-letter)
Step 4.6  SC-ROUTE   Sub-control evidence routing — emit
                     evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_relevant-evidence.md manifests
Step 5    ANALYZE    Deep code analysis for security-relevant patterns
Step 6    GAP        Identify missing items per sub-item;
                     per-family narrative iterates EVERY Determine If ID with H3 sub-sections
Step 6.5  ASSESS     Assessment pass — for each Determine If ID, generate Findings paragraph
                     + Result (Satisfied / NotSatisfied / blank). (Skipped if --no-assessment.)
Step 6.6  SYNTHESIZE For each NotSatisfied row where the gap is "implementation present,
                     artifact missing", generate a draft document under synthesized/ + a
                     SYNTHESIZED_ARTIFACTS.md inventory at package root. With
                     --accept-synthesized, drafts auto-promote and Result flips to
                     Satisfied (loud signaling: end-of-run summary, INDEX banner, CHECKLIST
                     notes column).
Step 6.7  CSV        Emit per-family <cf>-assessment.csv and _master-assessment.csv
                     (9-column GRC schema with Result/Findings populated, RFC-4180 quoting)
Step 7    CITATIONS  Merge [CR-NNN] from repo + sibling staging batches
                     (sharepoint / aws / azure / smb / vulnscan) into CODE_REFERENCES.md
Step 8    INDEX      Produce INDEX.md and CHECKLIST.md

After Step 8, conditional on flags:
Step 9    REMEDIATION  --remediation → invoke ato-remediation-guidance
Step 10   POAM         --poam → invoke ato-poam-generator
                                (consumes remediation output + vuln findings + checklist)
```

Step 1.5 is synchronous — the orchestrator waits for the vulnerability scan to finish before moving to discovery. The scan caps each tool at 10 minutes; total Step 1.5 time is typically 1–10 minutes depending on toolchain.

External-source siblings (AWS / Azure / SharePoint / SMB) run sequentially after Step 1.5. If one fails (auth missing, scope declined, US-region check), the orchestrator records the failure and continues with the others — graceful degradation is required, not optional.

---

## Output structure

### Citation IDs

Every external reference in the package resolves to a `[CR-NNN]` ID listed in `CODE_REFERENCES.md`. The `Source` column is one of: `repo`, `sharepoint`, `aws`, `azure`, `smb`, `vulnscan`. Permalinks are pinned to the commit SHA from the run, so they remain valid even after the branch moves.

For cloud sources (AWS / Azure), the `Local digest` column links to the human-readable Markdown summary the source sibling synthesized — that's the file you read first; the raw JSON is referenced from inside it.

For `vulnscan`, the link is an in-package anchor (`controls/RA-risk-assessment/evidence/RA-5/vulnerability-scan-{date}.md#vs-NNNN`) — vulnerability findings have no external console.

### CHECKLIST.md status colors

| Color | Meaning |
|---|---|
| 🟢 GREEN | Sub-item has evidence and a generated narrative or implementation statement |
| 🟡 YELLOW | Partial coverage — narrative exists but evidence is thin, or evidence exists but narrative wasn't synthesized |
| 🔴 RED | No evidence and no narrative; flagged as a gap |
| ⚪ GRAY | Inherited (CSP), operational, or otherwise out of scope for this repo |

`ato-remediation-guidance` and `ato-poam-generator` both prioritize RED rows; YELLOW rows feed in only when there's enough context.

### Sub-control evidence layout

Per-control evidence sits inside each control family at sub-control granularity, mirroring the federal assessment-spreadsheet pattern (one row per **Determine If ID**: lettered sub-parts of the control body like `AC-02(a)`–`AC-02(l)`, control enhancements like `AC-02(01)`, and enhancement-with-sub-letter chains like `AC-02(12)(b)`).

```
controls/AC-access-control/
├── ac-implementation.md         ← Family narrative; H3 sub-section per Determine If ID
├── ac-assessment.csv            ← Per-family GRC CSV
└── evidence/
    ├── AC-02/                   ← Parent-level: where files physically live
    │   ├── auth.ts                                         ← copied from repo / sibling
    │   ├── role-check-middleware.ts
    │   ├── role-matrix.yaml
    │   ├── AC-02(a)/AC_AC-02_AC-02(a)_relevant-evidence.md             ← Manifest: relative paths to parent files
    │   ├── AC-02(d)/AC_AC-02_AC-02(d)_relevant-evidence.md
    │   ├── AC-02(01)/AC_AC-02_AC-02(01)_relevant-evidence.md           ← Enhancement, peer of sub-letters
    │   └── AC-02(12)/AC-02(12)(b)/AC_AC-02_AC-02(12)(b)_relevant-evidence.md  ← Enhancement-with-sub-letter, nested
    └── AC-03/                   ← Single Determine If ID — no sub-control nesting
        ├── AuthFilter.php
        └── AC_AC-03_relevant-evidence.md
```

Two rules to know:

- **No file duplication within a family.** Files live once at the parent control level (`evidence/AC-02/`). Each per-Determine-If-ID sub-folder carries a `<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_relevant-evidence.md` manifest pointing back at the parent files by relative path. The family + control + Determine If ID embedded in the filename keeps every manifest uniquely identifiable when an assessor flattens the package or copies files into a GRC tool — `_relevant-evidence.md` files would all collide under flattening.
- **Skip-redundant-nesting for simple controls.** When a control has exactly one Determine If ID (e.g., `AC-03`), evidence sits directly in `evidence/AC-03/` — no `evidence/AC-03/AC-03/` redundant nest.

The full naming rules and folder semantics are in `agents/base/global-scope/ato-artifact-collector/references/sub-control-enumeration.md`.

### GRC assessment CSVs (`<cf>-assessment.csv` + `_master-assessment.csv`)

Step 6.7 emits one CSV per family at `controls/<CF>-<slug>/<cf>-assessment.csv` and a master CSV at `controls/_master-assessment.csv`. Both are designed for direct ingestion into GRC tools (RSA Archer, ServiceNow GRC, Excel-based POA&M trackers).

**9-column schema** (header row exact):

```
Family ID,Family,Control ID,Control,Determine If ID,Determine If Statement,Method,Result,Findings
```

- One row per Determine If ID. Empty rows preserved for un-implemented sub-parts (their Determine If Statement / Method / Result / Findings columns are blank).
- `Method` is always `Review` for orchestrator-emitted rows.
- `Result` is `Satisfied` / `NotSatisfied` / blank — populated by the assessment pass (Step 6.5).
- `Findings` is the assessor narrative — populated by Step 6.5 per the AMIS-style template.
- RFC 4180 quoting: embedded commas / quotes / newlines are quoted; embedded `"` is doubled to `""`. Newlines inside narrative paragraphs are preserved as literal `\n` inside the quoted field.
- `\n` line endings (no `\r\n`); UTF-8 without BOM.

The master CSV is the master file most GRC tools want — all 20 families in one read, sorted by Family ID alphabetical → Control ID → Determine If ID.

**`--no-assessment` flag.** When passed, the orchestrator emits a 7-column variant (drops `Result` and `Findings`) and skips the assessment pass and synthesis. Use this when you want the implementation-statement scaffolding without the assessment.

The full schema spec, sort-order rules, and round-trip validation steps are in `agents/base/global-scope/ato-artifact-collector/references/csv-schema.md`.

### Sub-control assessment and synthesized drafts

The assessment pass (Step 6.5) reads each Determine If ID's requirement text from the inventory, compares it against the Determine If Statement (the implementation narrative just emitted in Step 6), and writes a **Findings paragraph** + a **Result** value into both the per-family narrative and the GRC CSV.

**Findings paragraph shape** (3 sentences, sometimes 4):

1. Positive evidence claim — "The evidence directly supports that [X]."
2. Either sufficiency ("The evidence covers the entire requirement, including [Y].") or gap ("However, the determine if statement also requires [Z], which the evidence does not [explicitly map | document | specify | demonstrate].").
3. Conclusion — "The requirement is satisfied." / "The requirement is not fully satisfied." / "The requirement cannot be assessed without [...]"
4. (Optional) "A draft artifact has been generated at `<path>` for review." (added when Step 6.6 produces a draft)

**Result decision rules:**

| Findings concludes... | Result |
|---|---|
| "The requirement is satisfied." | `Satisfied` |
| "The requirement is not fully satisfied." | `NotSatisfied` |
| "The requirement cannot be assessed without [...]" | _blank_ |
| Determine If Statement is empty (no implementation narrative) | _blank_ — Findings explains un-assessability |

The orchestrator MUST NOT mark a row `Satisfied` if the Findings paragraph contains gap language ("does not", "no document", "lacks", "missing", "is not specified", "cannot be assessed"). This is a hard rule enforced by a hygiene check; halt with a clear error if violated.

The full template, decision rules, and worked examples (drawn from the AMIS spreadsheet) are in `agents/base/global-scope/ato-artifact-collector/references/assessment-template.md`.

### Gap-driven artifact synthesis

When the assessment pass finds a `NotSatisfied` row whose gap is **"implementation present, artifact missing"** — the system enforces the requirement in code but no formal artifact documents it — Step 6.6 generates a draft artifact for human review.

**Default workflow (manual review):**

1. The orchestrator writes the draft to `controls/<CF>-<slug>/evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/synthesized/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md` with a `⚠ DRAFT` banner. The family + control + Determine If ID prefix matches the manifest filename pattern so every orchestrator-generated file remains unambiguous when the package is flattened.
2. A row appears in the top-level `SYNTHESIZED_ARTIFACTS.md` inventory.
3. The Result for that Determine If ID stays `NotSatisfied`; the Findings paragraph adds "A draft artifact has been generated at `<path>` for review."
4. **You review each draft.** Edit as needed. Either:
   - **Accept**: copy/move the file from `synthesized/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md` to `evidence/<CONTROL-ID>/<DETERMINE-IF-ID>/<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_<artifact-slug>.md` (one folder up; preserve the filename). Re-run the orchestrator — Step 6.5 will detect the present artifact and flip the Result to `Satisfied`.
   - **Reject**: delete the draft. The Determine If ID stays `NotSatisfied`; the gap rolls into the next remediation cycle via `--remediation`.

**`--accept-synthesized` (auto-promote):**

When passed, the orchestrator copies each draft to the parent evidence folder immediately, flips the Result to `Satisfied`, and emits **loud signaling**:

- End-of-run summary block listing every promoted artifact.
- Banner at the top of `INDEX.md`: "⚠ AUTO-PROMOTED ARTIFACTS PRESENT. ... Review SYNTHESIZED_ARTIFACTS.md before authoritative submission."
- `Auto-promoted draft — review before submission` note in `CHECKLIST.md` for every flipped row.

**Risk surface for `--accept-synthesized`.** Synthesized drafts make assertions about the system from code inspection alone. They can be wrong — a role matrix derived from `if (role === 'ADMINISTRATOR') return true` correctly classifies `ADMINISTRATOR` as Privileged from a code standpoint, but org policy might classify it differently. Auto-promoted drafts published unreviewed would inject those assertions into ATO evidence. The flag exists for fast iteration cycles; the loud signaling is the safeguard, not a substitute for review.

**Common synthesized artifact patterns:**

| Pattern | Typical Determine If IDs | Output filename |
|---|---|---|
| User role matrix (Internal/External × Privileged/Non-Privileged/No-Logical-Access) | `AC-02(d)`, `AC-06(01)`, `AC-06(02)`, `AC-06(05)` | `<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_role-matrix-draft.md` |
| Account-type definition table | `AC-02(a)` | `<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_account-types-draft.md` |
| Privileged-account inventory | `AC-06(02)`, `AU-09(04)` | `<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_privileged-accounts-draft.md` |
| System-component inventory | `CM-08`, `PL-02` | `<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_system-components-draft.md` |
| Continuous-monitoring sampling plan | `CA-07` | `<FAMILY>_<CONTROL-ID>_<DETERMINE-IF-ID>_conmon-sampling-plan-draft.md` |

Concrete examples: `AC_AC-02_AC-02(d)_role-matrix-draft.md`, `AC_AC-02_AC-02(a)_account-types-draft.md`, `CM_CM-08_system-components-draft.md` (the simple-control case drops the redundant Determine If ID segment).

**The orchestrator does NOT synthesize:**

- When the gap is missing implementation (not just missing artifact). Synthesizing would fabricate behaviour.
- When the missing artifact is operational policy, signed documents, training certificates, or HR data. Those require human authorship.
- When `--no-synthesize` was passed.

The full gap-detection heuristic, draft templates, and auto-promote idempotency rules are in `agents/base/global-scope/ato-artifact-collector/references/synthesis-patterns.md`.

#### Worked example — AC-02(d) end-to-end

Given a system that enforces role-based authorization in code (`auth.ts` defines four roles, middleware enforces them) but has no document mapping those roles onto the federal Privileged / Non-Privileged / No-Logical-Access classification:

1. **Step 6 emits the Determine If Statement** for `AC-02(d)`: "AMIS authorizes only NIH-Login-SAML-authenticated users... The system defines four application role memberships... and enforces access authorizations on each request through the middleware sequence... [CR-042][CR-043][CR-044]."

2. **Step 6.5 generates Findings**: "The evidence and implementation statement support several portions of the requirement by identifying authorized users... and describing role-based and area-based access enforcement. However, the determine if statement also requires specification of the user role matrix attributes for each account type — specifically whether users are Internal or External and whether each account type is Privileged, Non-Privileged, or No Logical Access — and the provided evidence does not explicitly map the identified user roles or account types to those required attributes. The requirement is not fully satisfied."
   Result: `NotSatisfied`.

3. **Step 6.6 detects the synthesizable pattern** (positive evidence claim + missing-artifact gap + synthesis-able from code) and generates a draft at `controls/AC-access-control/evidence/AC-02/AC-02(d)/synthesized/AC_AC-02_AC-02(d)_role-matrix-draft.md`. The draft has YAML frontmatter (`status: DRAFT`, `gap_addressed: "User role matrix..."`), the strong banner, and a populated table inferred from code:

   | Role | Internal/External | Privilege class | Logical access | Source |
   |---|---|---|---|---|
   | ADMINISTRATOR | Internal | Privileged (bypasses checkAreaPermission) | All areas, all actions | [CR-043] |
   | DATA_ENTERER | Internal | Non-Privileged | Per-area write per checkAreaPermission | [CR-044] |
   | VIEWER | Internal | Non-Privileged | Per-area read | [CR-044] |
   | INVESTIGATOR | Internal | Non-Privileged | Per-area read | [CR-044] |

4. **Step 6.6 appends to Findings**: "A draft artifact has been generated at `controls/AC-access-control/evidence/AC-02/AC-02(d)/synthesized/AC_AC-02_AC-02(d)_role-matrix-draft.md` for review."

5. **You review.** The draft's privilege classifications match org policy. You copy `synthesized/AC_AC-02_AC-02(d)_role-matrix-draft.md` up to `evidence/AC-02/AC-02(d)/AC_AC-02_AC-02(d)_role-matrix-draft.md` (preserve the filename so the audit trail stays intact).

6. **You re-run** `/ato-artifact-collector --repo`. Step 6.5 sees the artifact at the parent level, generates new Findings ("The evidence supports the entire requirement, including the role matrix at... The requirement is satisfied."), and flips Result to `Satisfied`. The CSV updates accordingly.

If you'd run the original collection with `--accept-synthesized`, steps 5-6 happen automatically — but the loud signaling tells you to review the auto-promoted file before submission.

### `REMEDIATION_GUIDANCE.md` shape

Each item is `RG-NNN` with:

- Control reference (`AC-2(4)` etc.)
- Type — CODE / CONFIG / INFRA / TEST / DOC-IN-REPO
- Effort — S / M / L
- "Why this matters" paragraph
- "What to change" — concrete file paths and the change to make
- "How to verify" — runnable acceptance checks (`[ ]` checkboxes)

Operational / Policy / Inherited gaps are listed in a single "Out of scope for developer remediation" tail section — not as actions.

### `poam-generated.md` / `poam-generated.csv` shape

Columns: `ID, Weakness Name, Weakness Description, Source Identifier, Origin, Asset/System Component, NIST 800-53 Controls, Severity, Original Detection Date, Scheduled Completion Date, Milestones, Resources Required, Point of Contact, Status, Comments`.

`Source Identifier` traces to `RG-NNN`, `VS-NNNN`, or `CR-NNN`. `Origin` is `gap-analysis | remediation | vuln-scan | hybrid`. `Severity` follows a defined hierarchy: vuln-scan CVSSv3 → RG effort proxy → CHECKLIST status. `Scheduled Completion Date` is severity-derived: Critical=15d, High=30d, Moderate=90d, Low=180d. `Point of Contact` and `Resources Required` are always `<TBD by ISSO>` — never fabricated.

The Markdown file carries an "ID Stability Map" YAML block at the top — that's the parser anchor for re-runs (see [Re-runs and idempotency](#re-runs-and-idempotency)).

### `vulnerability-scan-{YYYY-MM-DD}.md` shape

Each finding is `VS-NNNN` with:

- Severity (Critical / High / Medium / Low / Info, CVSSv3-derived where available)
- CWE / CVE / GHSA where known
- Tool (e.g. `pip-audit`)
- Location (`package@version` or `file:line`; secrets redacted to `<REDACTED>`)
- Description — verbatim from the advisory in a fenced block
- Recommended fix
- Controls (default `RA-5`, `SI-2`; `+ SR-3` for supply chain, `+ IA-5` for secrets, etc.)

Three sections sit at the bottom of every dated scan file:

- **Closed since previous scan** — VS-NNNN IDs from a prior run that no longer surface
- **Coverage** — tools that weren't on PATH at scan time and the install commands
- **Tool failures** — tools that timed out or errored, with stderr truncated

The same content is written to three locations on disk for control coverage: RA-5 (primary), SI-2 (Flaw Remediation), and `ssp-sections/10-vulnerability-mgmt-plan/evidence/`.

---

## Authentication

**Hard rule across the collection: ambient auth only.** No skill or agent ever stores credentials, prompts for passwords, or modifies your shell config. Each source sibling expects you to have already logged in via the source's native CLI before you invoke the orchestrator.

### AWS

```bash
aws sso login --profile <your-profile>
# or, for long-lived credentials (discouraged):
export AWS_PROFILE=<your-profile>
```

Verify with `aws sts get-caller-identity` before launching the orchestrator. Region scope is locked to the US allow-list (`us-east-1`, `us-east-2`, `us-west-1`, `us-west-2`, `us-gov-east-1`, `us-gov-west-1`) — a non-US region in scope causes the AWS source to refuse the run.

### Azure

```bash
az login --use-device-code
# or via a user-owned helper (e.g. an org-internal credential broker):
E.g. a helper that executes the CLI for your password vault to inject the crdentials
```

Verify with `az account show`. Region scope is the Azure US allow-list (`eastus`, `eastus2`, `centralus`, `northcentralus`, `southcentralus`, `westus`, `westus2`, `westus3`, `usgovvirginia`, `usgovtexas`, `usgovarizona`, `usdodeast`, `usdodcentral`).

The Azure source supports a configurable `helper_command` in the auth config — a path to a user-owned script that establishes the `az` session however your environment requires (1Password lookup, federal SSO shim, etc.). The sibling invokes the helper as a subprocess and never reads its contents.

### SharePoint / M365

```bash
m365 login --authType browser (for interative)
```

Verify with `m365 status`. No region restriction — Microsoft 365 is tenant-scoped. Service-account auth and pre-established sessions are supported via `auth.method: service-account` or `existing` in config.

### SMB / Windows shares

Mount the share through whatever mechanism your environment uses **before** launching the orchestrator:

- macOS: Finder → Connect to Server, or `mount_smbfs //user@host/share /local/path`
- Linux: `mount.cifs //host/share /local/path -o user=...,sec=krb5` or GVFS
- Windows: `cmdkey /add:host /user:DOMAIN\user /pass:...` then UNC path access

The SMB sibling traverses the mounted share read-only with a depth limit (default 3 levels). Kerberos tickets and macOS Keychain entries are first-class auth methods.

### What the auth config does and does NOT do

`~/.claude/skills/ato-artifact-collector/config.yaml` (and per-repo `.ato-package.yaml`) records:

- ✅ The auth **method** you've chosen (sso / device-code / helper / etc.)
- ✅ Non-secret parameters (profile name, tenant ID, helper script path)
- ✅ Optional `login_instruction` override that the sibling echoes verbatim on auth failure

It does **not** store:

- ❌ Passwords, API keys, tokens, refresh tokens, client secrets
- ❌ Anything that looks like a stored secret — the orchestrator validates the config and refuses to run if it finds one

If you want a richer auth flow (1Password, Vault, Bitwarden, etc.), use `auth-interview` once to bootstrap `~/.agent-skills/auth/auth.yaml`, and the source siblings will pick up the resolved session.

---

## Configuration — `.ato-package.yaml`

Per-repo scope lives at `.ato-package.yaml` at the repo root. This file is typically gitignored unless your team deliberately shares scope. Add this to `.gitignore`:

```gitignore
# ATO artifact collector scope — may contain tenant-identifying info
.ato-package.yaml
```

A complete file looks like:

```yaml
version: 1

sharepoint:
  enabled: true
  tenant: contoso
  sites:
    - https://contoso.sharepoint.com/sites/app-ato
  folders:
    https://contoso.sharepoint.com/sites/app-ato:
      - /Shared Documents/SSP
      - /Shared Documents/POA&M
      - /Shared Documents/Policies
  auth:
    method: device-code
    account_hint: ato-bot@contoso.onmicrosoft.com

aws:
  enabled: true
  accounts: ["123456789012"]
  regions: [us-east-1]
  services: [iam, config, cloudtrail, securityhub, s3, kms]
  auth:
    method: sso
    profile: ato-read

azure:
  enabled: true
  subscriptions: ["00000000-0000-0000-0000-000000000000"]
  resource_groups: [app-prod]
  regions: [eastus, usgovvirginia]
  auth:
    method: helper
    helper_command: ~/Applications/bin/azureauth
    tenant: 00000000-0000-0000-0000-000000000000
    cloud: AzureCloud

smb:
  enabled: true
  shares:
    - name: corp-ato
      unc: //fileserver.corp/ato
      mount_point: ~/mnt/corp-ato
      credentials_helper: kerberos
  depth: 3

vulnerability_scan:
  enabled: true                # default true; --no-vuln-scan overrides per-run
  # tools_allowlist: []        # empty = run every available tool
  secret_scan_enabled: true    # gitleaks; set false on noisy test-fixture repos

poam:
  enabled: false               # default false; --poam overrides per-run
  severity_to_due_date:
    Critical: 15
    High: 30
    Moderate: 90
    Low: 180

assessment:
  enabled: true                # default true; --no-assessment forces false per-run.
                               # When false, no Findings/Result emitted; CSV becomes 7-column.

synthesis:
  enabled: true                # default true; --no-synthesize forces false.
                               # Auto-skipped when assessment.enabled is false.
  auto_accept: false           # default false (drafts stay under synthesized/ for review).
                               # --accept-synthesized forces true; loud signaling on every run.

csv_export:
  enabled: true                # GRC assessment CSVs (Step 6.7) — default on.
  master_file: true            # Master CSV at controls/_master-assessment.csv.
```

User-global defaults can be set at `~/.claude/skills/ato-artifact-collector/config.yaml` (a starter copy is bundled with the agent). The merge rule is **shallow per source** — if the repo file declares a `sharepoint:` block, it fully replaces the user file's `sharepoint:` block (no field-by-field overlay).

CLI flags win over config: `--no-vuln-scan` disables the scan even if `vulnerability_scan.enabled: true`. `--poam` enables POA&M generation even if `poam.enabled: false`. `--no-assessment` disables the assessment pass even if `assessment.enabled: true`. `--no-synthesize` and `--accept-synthesized` similarly override `synthesis.*`.

---

## Re-runs and idempotency

The collection is designed to be re-run regularly — daily, on every PR, on a cron, ahead of an assessment. Stable identifiers across runs make this practical.

| Identifier | Stability rule |
|---|---|
| `[CR-NNN]` (citations) | Stable per source-row tuple `(source, location, start, end)`. Repo citations are renumbered to a dense table on every Step 7 merge — assessors should reference `Source` + `Location` for cross-run traceability, not the bare CR-NNN. |
| `RG-NNN` (remediation items) | Re-allocated per run (the remediation guidance regenerates from current package state). If you need stable RG-NNN, reference the gap by control + file path. |
| `VS-NNNN` (vuln findings) | **Stable across runs.** The scanner reads the most recent dated finding file, builds an `origin_tool_row → VS-NNNN` map, and reuses the same VS-NNNN whenever the same advisory appears. New findings get IDs at the high-water mark. Findings that drop out appear in a `## Closed since previous scan` section. |
| `POAM-NNNN` (POA&M rows) | **Stable across runs.** The generator parses the existing `poam-generated.md`'s ID Stability Map (a YAML block at the top of the file) and reuses POAM-NNNN when the same source-identifier set is present. Closed weaknesses move to `## Closed Items`, not deleted. |

### Preserving manual ISSO edits

The POA&M generator preserves user-applied annotations across regeneration:

- `Status: Open → In Progress` flips are preserved
- Free-text in `Comments` is preserved
- `Point of Contact` / `Resources Required` updates from the placeholder are preserved

What's regenerated unconditionally: weakness description, controls list, milestones, scheduled completion date (these can change as remediation makes progress or new advisories arrive).

If you've made invasive structural edits and don't want them preserved, ask for a clean regeneration: invoke `ato-poam-generator` and tell it "regenerate cleanly" / "ignore prior IDs" — it'll allocate fresh POAM-NNNN starting at 0001.

### Vuln-scan history

Each vulnerability scan writes a new dated file (`vulnerability-scan-2026-04-29.md`, then `vulnerability-scan-2026-05-15.md`, etc.). Old files are not deleted — the dated history is the audit trail an assessor reads to confirm scan cadence (RA-5 deliverable). The latest file is the one referenced from `INDEX.md` and from the citation batch.

---

## Standalone modes

### Just the vulnerability scan

```text
/ato-vulnerability-scanner
```

Runs the agent directly. Writes findings to `controls/RA-risk-assessment/evidence/RA-5/vulnerability-scan-{date}.md` (and the SI-2 + ssp-sections/10 dual-routes). Useful for:

- Pre-PR safety check before merging dependency upgrades
- Periodic re-scan to refresh RA-5 evidence between full ATO collections
- Quick CVE / secret / SAST baseline on a new repo

### Just the remediation guidance

```text
/ato-remediation-guidance
```

Reads an existing package and produces `REMEDIATION_GUIDANCE.md`. Requires that `ato-artifact-collector` has run at least once already — the package directory must contain at least 5 SSP sections and 10 control families.

### Just the POA&M

```text
/ato-poam-generator
```

Reads an existing package — ideally with `REMEDIATION_GUIDANCE.md` and a recent `vulnerability-scan-*.md` already present — and emits the POA&M Markdown + CSV. If the prerequisites are thin, the generator emits a "reduced fidelity" banner in the report header rather than failing.

### Just one source (debugging)

The four `ato-source-*` skills are documented as not directly invokable — they expect a scope object from the orchestrator. If you need to verify a source in isolation (e.g. after auth setup), invoke the orchestrator with only that source enabled:

```text
/ato-artifact-collector --aws
```

That collects only AWS evidence into the package and skips the others.

---

## What controls the package addresses

The 20 NIST 800-53 Rev 5 control families are always present in `controls/`. Each has an `*-implementation.md` document that either claims the family is implemented (with citations) or explicitly documents the gap. Per-control evidence sits under `evidence/<CONTROL-ID>/` (e.g. `controls/AC-access-control/evidence/AC-2/`, `evidence/AC-2(4)/`).

Specific controls the collection has built-in evidence patterns for:

| Family | Controls with built-in patterns |
|---|---|
| AC | AC-2, AC-2(3), AC-2(4), AC-3, AC-6, AC-17 |
| AU | AU-2, AU-3, AU-12 |
| CA | CA-3 (interconnections), **CA-5 (POA&M)**, CA-7 (continuous monitoring) |
| CM | CM-2, CM-3, CM-6, CM-8 (inventory), CM-9 (CMP) |
| CP | CP-2 (CP/DRP/COOP), CP-9, CP-10 |
| IA | IA-2, IA-5 |
| IR | IR-4, IR-6, IR-8 (IRP) |
| PL | PL-2 (system description) |
| **RA** | **RA-3 (RAR), RA-5 (Vulnerability Scanning)** ← `ato-vulnerability-scanner` writes here |
| SA | SA-3, SA-9, SA-11, SA-15 (SDLC) |
| SC | SC-7, SC-8, SC-12, SC-13 |
| **SI** | **SI-2 (Flaw Remediation)** ← `ato-vulnerability-scanner` dual-routes here, SI-3, SI-7, SI-10 |
| SR | SR-2 (SCRM plan), SR-3, SR-6 |

The 14 SSP sections cover the document-shaped artifacts an SSP package needs: System Description, System Inventory, Risk Assessment Report, POA&M, Interconnections, Policies & Procedures, IRP, Contingency Plan, CMP, Vulnerability Mgmt Plan, SDLC, SCRM Plan, ConMon Plan, Privacy Impact Assessment.

---

## Troubleshooting

### "The orchestrator is asking me about every source even though I passed `--aws`"

You're hitting the precedence rule: any source flag means "skip the interview entirely." If you're still seeing prompts, check that the flag actually reached `$ARGUMENTS` — some CLIs strip unknown flags. Try invoking with the flag verbatim in the prompt: `/ato-artifact-collector --aws`.

### "AWS source failed: scope_invalid: region eu-west-1 not on US allow list"

The collection enforces a US-only region allow-list for AWS and Azure. Remove the non-US region from your `.ato-package.yaml` `aws.regions:` list or your config-file defaults. The allow-list is hard-coded — there's no override; if your system genuinely needs a non-US region for ATO purposes, this collection isn't the right tool.

### "Vulnerability scanner says 'tool unavailable: cargo-audit'"

That's not an error — that's a coverage gap. The scanner records the missing tool and continues with what's installed. Install the missing tool (`cargo install cargo-audit`) and re-run if you want fuller coverage. If you want vuln-scan off entirely for this run, pass `--no-vuln-scan`.

### "The POA&M is regenerating with new POAM-NNNN every time"

The generator preserves POAM-NNNN by parsing the `id_map:` YAML block in the existing `poam-generated.md`'s "ID Stability Map" section. If you've moved or renamed that file, the generator can't find it and will start fresh. Restore the file at `ssp-sections/04-poam/poam-generated.md` before re-running.

### "REMEDIATION_GUIDANCE.md is missing items I expected"

The remediation skill filters to gaps a developer can close inside the repo — code, config, infrastructure declarations, tests, repo-managed docs. Operational records (training logs, HR data, incident tickets), inherited CSP controls, and org-wide policy documents are listed in the "Out of scope for developer remediation" tail section, not as RG-NNN actions. Check that section before assuming an item was dropped.

### "I want to share my scope config across the team"

Commit `.ato-package.yaml` to the repo (skip the `.gitignore` line for it). The config never contains secrets — only tenant/account IDs, region lists, helper-script paths. The orchestrator validates this and refuses to run if it finds anything secret-shaped.

### "The vuln scan times out on a large mono-repo"

Each scanner is capped at 10 minutes. If `mvn dependency-check` or `gradle dependencyCheckAnalyze` is the slow one, restrict scope: set `vulnerability_scan.tools_allowlist: [cargo-audit, npm-audit, gitleaks, semgrep]` in `.ato-package.yaml` to skip the slow plugin. Trade off: less coverage on Java/Kotlin dependencies, faster runs.

### "How do I tell the assessor 'this control is inherited'?"

Edit the relevant `controls/<CF>-…/<cf>-implementation.md` after generation and add an `> **INHERITED**:` blockquote with the CSP/shared-service it inherits from. The orchestrator will preserve user edits to implementation documents on re-run as long as the file structure remains parseable. Best practice: keep the inheritance note at the top, just below the header.

### "I need to feed the package to a remediation agent"

Run with `--remediation` (or invoke `ato-remediation-guidance` after the fact). The output `REMEDIATION_GUIDANCE.md` is structured as a concrete punch list — each `RG-NNN` carries a control ID, type (CODE/CONFIG/INFRA/TEST/DOC-IN-REPO), exact file path, and acceptance criteria. Hand the file to the remediation agent; the format is designed for that hand-off.

### "I want to ship the POA&M to a federal authoring tool"

Use `poam-generated.csv` rather than the Markdown. The CSV uses standard RFC-4180 quoting and the column order matches typical federal POA&M templates. Multi-value cells (Source Identifier, Controls, Milestones) are encoded as `;`-joined within the CSV cell — most authoring tools handle this directly, or split the joined values on import.
