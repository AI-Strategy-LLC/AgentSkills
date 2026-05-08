# Artifact Mappings Reference

This reference maps each NIST 800-53 artifact area — SSP-section
documents and per-control-family implementation evidence — to specific
file patterns, code patterns, and search strategies for discovering
evidence in a repository.

The numbering below preserves the original section order for backward
compatibility with existing site-specific runbooks. The orchestrator's
**Step 4 routing table** in `agent.md` is the authoritative mapping
from these areas to the new `ssp-sections/<NN>-<slug>/` and
`controls/<CF>-<slug>/evidence/<CONTROL-ID>/` paths. The `Routes to`
column on each section header below summarises that routing.

## Table of Contents
1. [System Design Document](#1-pl--system-design-document) → `ssp-sections/01-system-description/`
2. [System Inventory](#2-cm--system-inventory) → `ssp-sections/02-system-inventory/` + `controls/CM-configuration-management/evidence/CM-8/`
3. [Configuration Management Plan](#3-cm--configuration-management-plan) → `ssp-sections/09-configuration-management-plan/` + `controls/CM-configuration-management/`
4. [Access Control & Account Management](#4-ac--access-control--account-management) → `controls/AC-access-control/`
5. [Authentication & Session Configuration](#5-ia--authentication--session-configuration) → `controls/IA-identification-authentication/`
6. [Audit Logging & Monitoring](#6-au--audit-logging--monitoring) → `controls/AU-audit-accountability/`
7. [Vulnerability & Patch Management](#7-si--vulnerability--patch-management) → `ssp-sections/10-vulnerability-mgmt-plan/` + `controls/SI-system-information-integrity/` + `controls/RA-risk-assessment/evidence/RA-5/`
8. [Incident Response Plan](#8-ir--incident-response-plan) → `ssp-sections/07-incident-response-plan/` + `controls/IR-incident-response/`
9. [Contingency Plan](#9-cp--contingency-plan) → `ssp-sections/08-contingency-plan/` + `controls/CP-contingency-planning/`
10. [Security Policies & Procedures](#10-pl--security-policies--procedures) → `ssp-sections/06-policies-procedures/` + every `controls/<CF>/evidence/<CF>-1/`
11. [Personnel Security Records](#11-ps--personnel-security-records) → `controls/PS-personnel-security/`
12. [Security Awareness & Training](#12-at--security-awareness--training) → `controls/AT-awareness-training/`
13. [System Maintenance Records](#13-ma--system-maintenance-records) → `controls/MA-maintenance/`
14. [Physical & Environmental Protection](#14-pe--physical--environmental-protection) → `controls/PE-physical-environmental/`
15. [Media Protection Records](#15-mp--media-protection-records) → `controls/MP-media-protection/`
16. [Network & Communications Security](#16-sc--network--communications-security) → `controls/SC-system-communications-protection/`
17. [SDLC & Secure Development](#17-sa--sdlc--secure-development) → `ssp-sections/11-sdlc-document/` + `controls/SA-system-services-acquisition/`
18. [Supply Chain Risk Management](#18-sr--supply-chain-risk-management) → `ssp-sections/12-supply-chain-risk-mgmt-plan/` + `controls/SR-supply-chain-risk-management/`
19. [Interconnection & External Services](#19-ca--interconnection--external-services) → `ssp-sections/05-interconnections/` + `controls/CA-assessment-authorization/`
20. [Risk Assessment & Categorization](#20-ra--risk-assessment--categorization) → `ssp-sections/03-risk-assessment-report/` + `controls/RA-risk-assessment/`
21. [POA&M (Plan of Action & Milestones)](#21-poam) → `ssp-sections/04-poam/` + `controls/CA-assessment-authorization/evidence/CA-5/`
22. [Continuous Monitoring Plan](#22-ca--continuous-monitoring-plan) → `ssp-sections/13-continuous-monitoring-plan/` + `controls/CA-assessment-authorization/evidence/CA-7/`
23. [Privacy Impact Assessment / SORN](#23-pt--privacy-impact-assessment) → `ssp-sections/14-privacy-impact-assessment/` + `controls/PT-pii-processing-transparency/`
24. [Program Management evidence](#24-pm--program-management) → `controls/PM-program-management/`
25. [Planning controls (separate from policy docs)](#25-pl--planning-controls) → `controls/PL-planning/`

---

## 1. PL — System Design Document

### File patterns
```
docs/**/architect*.md, docs/**/design*.md, docs/**/sdd*.md
README.md, REPO-README.md
docs/**/overview*.md, docs/**/system*.md
**/diagrams/**, **/images/architecture*
```

### Code patterns for generation
```
# Component inventory
Dockerfile*, docker-compose*.yml, **/Deployment.yaml, **/deployment*.yaml
**/BuildConfig.yaml, **/Service.yaml, **/Ingress.yaml

# Data flows
**/routes.php, **/Routes.php, **/urls.py, **/routes.*, **/router.*
**/controllers/**, **/Controllers/**, **/handlers/**
**/api/**, **/endpoints/**

# Auth design
**/auth*.*, **/Auth*.*, **/middleware/auth*
**/Filters/Auth*, **/guards/**, **/policies/**
config/saml/**, **/oauth/**, **/oidc/**

# Crypto
**/encrypt*.*, **/crypto*.*, **/tls*.*, **/ssl*.*
**/cert/**, **/certs/**, **/certificates/**
```

### Sub-items to check
- [ ] System name, purpose, high-level description
- [ ] System boundary definition
- [ ] Architecture diagrams (network, data flow, deployment)
- [ ] All system components described
- [ ] Data flows between components and external systems
- [ ] Ports, protocols, services with justification
- [ ] Trust boundaries and security zones
- [ ] Separation of user/admin functionality
- [ ] Data/tenant separation
- [ ] Memory protection and process isolation
- [ ] Authentication and authorization design
- [ ] Cryptographic design
- [ ] Collaborative computing devices, mobile code, shared resources

---

## 2. CM — System Inventory

### File patterns
```
# PHP
composer.json, composer.lock
# Node (TS + JS)
package.json, package-lock.json, yarn.lock, pnpm-lock.yaml, tsconfig.json
# Python
requirements.txt, Pipfile, Pipfile.lock, poetry.lock, pyproject.toml, setup.py, setup.cfg
# Rust
Cargo.toml, Cargo.lock
# Go
go.mod, go.sum
# Ruby
Gemfile, Gemfile.lock, *.gemspec, Rakefile
# JVM (Java / Kotlin)
**/pom.xml, **/build.gradle, **/build.gradle.kts, gradle/libs.versions.toml
# C# / .NET
**/*.csproj, **/*.sln, **/Directory.Build.props, **/Directory.Packages.props, **/appsettings*.json, **/packages.config
# Swift / Objective-C (SPM + Xcode)
Package.swift, Package.resolved, Podfile, Podfile.lock, **/*.xcodeproj/project.pbxproj
# C / C++
**/CMakeLists.txt, **/Makefile, configure.ac, configure.in, meson.build, vcpkg.json, conanfile.txt
# R
DESCRIPTION, renv.lock, packrat/, install.R
# SAS (no universal manifest — treat *.sas presence as the marker)
**/*.sas
# Perl
Makefile.PL, cpanfile, cpanfile.snapshot, MANIFEST, META.json
# SQL (standalone, no host-language marker)
.sqlfluff, **/schema.sql, **/migrations/**/*.sql
```

### Code patterns for generation
```
# Infrastructure components
Dockerfile*, docker-compose*.yml
**/Deployment.yaml, **/StatefulSet.yaml
**/terraform/*.tf, **/cloudformation/*.yaml
openshift/**/*.yaml

# Database
**/migrations/**, **/schema*.sql, **/database*.*
**/models/**, **/entities/**

# Third-party integrations
.env.sample (look for service URLs and API endpoints)
```

### Sub-items to check
- [ ] Hardware components (servers, network, storage, endpoints, mobile)
- [ ] Software (OS, middleware, apps, databases, libraries, agents)
- [ ] Firmware components
- [ ] Version/release numbers for every component
- [ ] Responsible owner/role per component
- [ ] Physical or logical location
- [ ] Installation/last-updated dates
- [ ] Vendor support status (EOL flags)
- [ ] Data types per component
- [ ] Components awaiting/returning from service

---

## 3. CM — Configuration Management Plan

### File patterns
```
.github/**, .gitlab-ci.yml, Jenkinsfile, azure-pipelines.yml
.github/PULL_REQUEST_TEMPLATE*, .github/CODEOWNERS
**/CONTRIBUTING.md, **/DEVELOPMENT.md
docs/**/config*.md, docs/**/change*.md
```

### Code patterns for generation
```
# Baseline configs
Dockerfile (base image = baseline)
config/**/*, **/Config/**/*
.editorconfig, .eslintrc*, .prettierrc*, tslint.json
**/phpcs.xml, **/phpstan.neon, **/psalm.xml

# Change detection
.gitleaks.toml, .gitattributes
**/renovate.json, **/dependabot.yml

# Hardening references (in comments or docs)
Grep: "STIG", "CIS", "USGCB", "hardening", "benchmark"
```

### Sub-items to check
- [ ] CCB or governance body identified
- [ ] Change proposal/review/approval/test/implement process
- [ ] Security impact analysis for changes
- [ ] Pre-production testing evidence
- [ ] Baseline configuration per component type
- [ ] Hardening standards referenced (STIG, CIS, etc.)
- [ ] Baseline review frequency
- [ ] Older baseline version retention
- [ ] Unauthorized change detection (FIM, SIEM)
- [ ] Software allowlist/denylist
- [ ] User software installation restrictions
- [ ] Mobile device configuration policies
- [ ] Change ticket history

---

## 4. AC — Access Control & Account Management

### File patterns
```
docs/**/access*.md, docs/**/account*.md
**/RBAC*.*, **/roles*.*, **/permissions*.*
```

### Code patterns for generation
```
# Role definitions
**/Filters/Role*, **/middleware/role*
**/guards/**, **/policies/**, **/permissions/**
**/config/auth*.*, **/config/roles*.*
Grep: "role", "permission", "privilege", "admin", "superuser"

# Account management
**/controllers/account/**, **/Controllers/Auth*
**/models/user*.*, **/models/User*.*
**/migrations/*user*, **/migrations/*account*, **/migrations/*role*

# Separation of duties
Grep: "separation.*duties", "dual.*control", "segregat"
```

### Sub-items to check
- [ ] Complete account roster
- [ ] Access request tickets with approvals
- [ ] Periodic account reviews
- [ ] Separation of duties matrix
- [ ] Privileged account justification/approval
- [ ] Separate non-privileged accounts for admin users
- [ ] Shared/functional account inventory with justification
- [ ] Onboarding records
- [ ] Offboarding records
- [ ] Transfer/reassignment records
- [ ] Remote access authorization
- [ ] Mobile/wireless access authorization
- [ ] External system access authorization

---

## 5. IA — Authentication & Session Configuration

### File patterns
```
config/**/auth*.*, config/**/session*.*
**/Config/App.*, **/config/config.*
config/saml/**, **/oauth*.*, **/oidc*.*
```

### Code patterns for generation
```
# Password policy
Grep: "password.*length", "password.*complex", "password.*history"
Grep: "lockout", "max.*attempt", "failed.*login"

# Session config
Grep: "session.*timeout", "session.*expir", "session.*idle"
Grep: "concurrent.*session", "session.*limit"

# MFA
Grep: "mfa", "multi.*factor", "two.*factor", "2fa", "totp", "yubikey"

# Banner
Grep: "banner", "warning.*message", "system.*use.*notification"
**/views/auth/**, **/templates/login*

# PIV/CAC
Grep: "piv", "cac", "smart.*card", "x509.*client"
```

### Sub-items to check
- [ ] Password length, complexity, history, age settings
- [ ] Account lockout threshold, duration, observation window
- [ ] Session lock timeout
- [ ] Concurrent session limits
- [ ] Network session termination
- [ ] MFA for privileged and non-privileged accounts
- [ ] Replay-resistant auth mechanisms
- [ ] Temporary password first-login change
- [ ] Password blocklist checking
- [ ] System use notification banner
- [ ] Default credentials changed
- [ ] PIV/CAC or federation config
- [ ] Contractor/foreign national account identifiers
- [ ] Session re-authentication and expiration
- [ ] Authentication feedback obscured
- [ ] Identity proofing process

---

## 6. AU — Audit Logging & Monitoring

### File patterns
```
**/logging*.*, **/log_config*.*, **/log4j*.*, **/logback*.*
**/syslog*.*, **/rsyslog*.*, **/fluentd*.*, **/filebeat*.*
**/datadog*.*, **/newrelic*.*, **/splunk*.*
docs/**/audit*.md, docs/**/logging*.md, docs/**/monitoring*.md
```

### Code patterns for generation
```
# What's logged
Grep: "log\.(info|warn|error|debug|critical)", "logger\.", "Log::"
Grep: "audit.*log", "security.*log", "access.*log"
Grep: "log_message", "write_log", "LoggerInterface"

# Monitoring
Grep: "alert", "notify", "siem", "splunk", "datadog", "cloudwatch"
Grep: "ntp", "time.*source", "chronyd", "ntpd"

# Log protection
Grep: "log.*permission", "log.*access.*control", "log.*encrypt"
```

### Sub-items to check
- [ ] Audit policy: which events are logged
- [ ] Rationale for selected auditable events
- [ ] Sample log exports with required content (who, what, when, where, outcome)
- [ ] Audit storage capacity and retention
- [ ] NTP configuration (authoritative time source)
- [ ] Audit log protection (access controls)
- [ ] Log access restricted to authorized reviewers
- [ ] Alerting for audit failures/capacity thresholds
- [ ] SIEM/log aggregation integration
- [ ] Log correlation across repositories
- [ ] Log review/analysis process

---

## 7. SI — Vulnerability & Patch Management

### File patterns
```
.github/workflows/*audit*, .github/workflows/*scan*
.github/workflows/*security*, .github/workflows/*snyk*
.github/workflows/*dependabot*, .github/dependabot.yml
**/renovate.json, **/renovate.json5
docs/**/vuln*.md, docs/**/patch*.md
.gitleaks.toml, .snyk, .trivyignore
```

### Code patterns for generation
```
# Scan configs
Grep: "vulnerability", "cve", "security.*scan"
Grep: "npm.*audit", "composer.*audit", "pip.*audit", "cargo.*audit"
Grep: "trivy", "grype", "snyk", "sonarqube", "veracode", "checkmarx"

# Malware/AV
Grep: "antivirus", "malware", "endpoint.*protection", "edr"
Grep: "clamav", "windows.*defender", "crowdstrike", "sentinel"

# FIM
Grep: "file.*integrity", "tripwire", "aide", "ossec", "wazuh"
```

### Sub-items to check
- [ ] Vulnerability scan reports (quarterly minimum)
- [ ] Patch remediation timeframes by severity
- [ ] Patch application records
- [ ] Pre-production patch testing
- [ ] Scan findings shared with stakeholders
- [ ] Risk acceptance records for deferred findings
- [ ] File integrity monitoring results
- [ ] Malware protection configuration
- [ ] Malware definition auto-update
- [ ] Scheduled full system scans
- [ ] On-access file scanning
- [ ] Malware detection response actions
- [ ] False positive handling records
- [ ] Public vulnerability disclosure process

---

## 8. IR — Incident Response Plan

### File patterns
```
docs/**/incident*.md, docs/**/ir-*.md, docs/**/irp*.*
**/INCIDENT*.md, **/SECURITY.md
.github/ISSUE_TEMPLATE/incident*, .github/ISSUE_TEMPLATE/security*
```

### Code patterns for generation
```
Grep: "incident.*response", "escalation", "us-cert", "cisa"
Grep: "breach", "compromise", "forensic"
```

### Sub-items to check
- [ ] Written IRP with roles, escalation, reporting requirements
- [ ] IRP distributed to all personnel
- [ ] IR training materials
- [ ] Training completion records
- [ ] IR test plan and results
- [ ] IR test coordination with other plan owners
- [ ] Incident tracking log
- [ ] Sample incident tickets
- [ ] Customer/AO/oversight notification records
- [ ] Automated IR support tool

---

## 9. CP — Contingency Plan

### File patterns
```
docs/**/contingency*.md, docs/**/disaster*.md, docs/**/dr-*.*
docs/**/backup*.md, docs/**/recovery*.md, docs/**/bcp*.*
```

### Code patterns for generation
```
# Backup evidence
Grep: "backup", "snapshot", "replicate", "failover"
Grep: "rto", "rpo", "recovery.*time", "recovery.*point"

# HA/DR configs
**/replicas*, **/replication*.*
Grep: "availability.*zone", "multi.*az", "cross.*region"
```

### Sub-items to check
- [ ] Written CP with RTO/RPO for all functions
- [ ] CP coordinated with IRP, DRP, other plans
- [ ] CP training materials and completion records
- [ ] CP test plan and results
- [ ] Critical asset inventory
- [ ] Alternate storage site documentation
- [ ] Alternate processing site documentation
- [ ] Telecom service agreements
- [ ] Backup schedule and evidence
- [ ] Backup testing/restoration records
- [ ] Backup encryption, access control, integrity verification
- [ ] Vendor SLAs for component failure
- [ ] Transaction recovery (if applicable)

---

## 10. PL — Security Policies & Procedures

### File patterns
```
docs/**/polic*.md, docs/**/procedure*.md
docs/**/ac-*.md, docs/**/at-*.md, docs/**/au-*.md
docs/**/ca-*.md, docs/**/cm-*.md, docs/**/cp-*.md
docs/**/ia-*.md, docs/**/ir-*.md, docs/**/ma-*.md
docs/**/mp-*.md, docs/**/pe-*.md, docs/**/pl-*.md
docs/**/pm-*.md, docs/**/ps-*.md, docs/**/pt-*.md
docs/**/ra-*.md, docs/**/sa-*.md, docs/**/sc-*.md
docs/**/si-*.md, docs/**/sr-*.md
```

### Sub-items to check
For each of the 20 control families (AC, AT, AU, CA, CM, CP, IA, IR, MA, MP, PE, PL, PM, PS, PT, RA, SA, SC, SI, SR):
- [ ] Policy document exists
- [ ] Procedure document exists
- [ ] Purpose and scope stated
- [ ] Roles and responsibilities defined
- [ ] Policy statements tied to NIST requirements
- [ ] Review frequency and last review date
- [ ] Version history / revision log
- [ ] Update notification mechanism

---

## 11. PS — Personnel Security Records

Typically OPERATIONAL — not in code repos.

### File patterns
```
docs/**/personnel*.md, docs/**/hr-*.md, docs/**/onboarding*.*
docs/**/offboarding*.*, docs/**/background*.*
**/rules-of-behavior*.*, **/acceptable-use*.*
```

### Sub-items to check
- [ ] Position risk designations
- [ ] Background check records
- [ ] Signed Rules of Behavior
- [ ] Signed access agreements and NDAs
- [ ] Vendor/contractor security agreements
- [ ] Personnel sanctions process communicated
- [ ] Job descriptions with security duties
- [ ] Screening/rescreening policy

---

## 12. AT — Security Awareness & Training

Typically OPERATIONAL — not in code repos.

### File patterns
```
docs/**/training*.md, docs/**/awareness*.*
docs/**/security-training*.*
```

### Sub-items to check
- [ ] Security awareness training completion records
- [ ] Role-based security training records
- [ ] CP training records
- [ ] IR training records
- [ ] Training materials (general, insider threat, phishing, role-specific)
- [ ] Training before access/duties

---

## 13. MA — System Maintenance Records

### File patterns
```
docs/**/maintenance*.md
**/CHANGELOG.md, **/CHANGES.md
```

### Code patterns for generation
```
# Git history as maintenance evidence
git log (recent maintenance activities)
```

### Sub-items to check
- [ ] Maintenance schedule and historical records
- [ ] Sample maintenance tickets
- [ ] Authorized maintenance organizations/personnel
- [ ] Offsite maintenance controls
- [ ] Diagnostic/maintenance tooling inspection records
- [ ] Nonlocal maintenance approval/monitoring
- [ ] Media sanitization/disposal records

---

## 14. PE — Physical & Environmental Protection

Typically INHERITED for cloud-hosted systems.

### File patterns
```
docs/**/physical*.md, docs/**/pe-*.md
docs/**/facility*.md, docs/**/data-center*.*
```

### Sub-items to check
- [ ] Authorized physical access list
- [ ] Physical access logs
- [ ] Visitor access records
- [ ] Physical access device inventory
- [ ] Key/combination change records
- [ ] UPS/power/fire/water test records
- [ ] Environmental monitoring logs
- [ ] Equipment entry/exit records
- [ ] Alternate work site agreements

---

## 15. MP — Media Protection Records

### File patterns
```
docs/**/media*.md, docs/**/mp-*.md
docs/**/sanitiz*.md, docs/**/disposal*.*
```

### Code patterns for generation
```
# USB/media controls
Grep: "usb", "removable.*media", "external.*storage"
```

### Sub-items to check
- [ ] Media type inventory with access restrictions
- [ ] Security classification labels
- [ ] Secure physical storage evidence
- [ ] Chain-of-custody records
- [ ] Media sanitization/disposal records
- [ ] Unauthorized media usage restrictions (USB controls)

---

## 16. SC — Network & Communications Security

### File patterns
```
**/firewall*.*, **/iptables*.*, **/nftables*.*
**/NetworkPolicy*.yaml, **/security-group*.*
**/ingress*.yaml, **/Ingress*.yaml
**/nginx*.conf, **/httpd*.conf, **/apache*.*
**/tls*.*, **/ssl*.*, **/certificates/**
```

### Code patterns for generation
```
# Firewall rules
Grep: "firewall", "iptables", "security.*group", "network.*policy"
Grep: "allow", "deny", "ingress", "egress" (in K8s/cloud configs)

# TLS
Grep: "tls", "ssl", "https", "certificate", "cipher"
Grep: "FIPS", "fips.*140", "validated"

# DNS
Grep: "dns", "nameserver", "resolver", "dnssec"

# DoS protection
Grep: "ddos", "rate.*limit", "throttl", "waf"

# Input validation
Grep: "filter", "sanitiz", "validat", "escap", "htmlspecialchars"
Grep: "csrf", "xss", "injection"

# Error handling
Grep: "error.*handler", "exception.*handler", "display.*errors"
Grep: "stack.*trace", "debug.*mode", "CI_DEBUG"
```

### Sub-items to check
- [ ] Firewall rulesets and ACL configurations
- [ ] Public/internal network separation
- [ ] DMZ and boundary protection
- [ ] External access point limits
- [ ] FIPS 140-2 validated crypto
- [ ] TLS configuration (version, ciphers)
- [ ] VPN configuration
- [ ] Data-at-rest encryption
- [ ] Key management documentation
- [ ] DNS security
- [ ] DoS/DDoS protection
- [ ] Split tunneling prevention
- [ ] Controlled egress point
- [ ] Process memory separation
- [ ] Collaboration device policies
- [ ] Active/executable content controls
- [ ] Spam filter configuration
- [ ] Input validation
- [ ] Error message suppression

---

## 17. SA — SDLC & Secure Development

### File patterns
```
docs/**/sdlc*.md, docs/**/development*.md
.github/**, .gitlab-ci.yml, Jenkinsfile
CONTRIBUTING.md, DEVELOPMENT.md
**/PULL_REQUEST_TEMPLATE*
.github/CODEOWNERS
tests/**, **/tests/**, spec/**, **/spec/**
```

### Code patterns for generation
```
# Testing
**/phpunit.xml, **/jest.config.*, **/pytest.ini
**/mocha*, **/.nycrc, **/coverage/**
Grep: "test", "spec", "assert", "expect", "mock"

# Security engineering principles
Grep: "least.*privilege", "defense.*in.*depth", "fail.*secure"
Grep: "separation.*duties", "minimize.*attack"

# Defect tracking
Grep: "bug", "defect", "vulnerability", "security.*issue"
.github/ISSUE_TEMPLATE/**
```

### Sub-items to check
- [ ] Written SDLC document
- [ ] Security requirements in design docs
- [ ] Security engineering principles applied
- [ ] Interface/endpoint/port/service inventory
- [ ] Developer defect tracking records
- [ ] Change management records
- [ ] Pre-production testing evidence
- [ ] Criticality analysis at SDLC decision points
- [ ] Development process review records
- [ ] Acquisition contracts with security requirements
- [ ] Test results for acquired products
- [ ] Supply chain risk assessments for developers

---

## 18. SR — Supply Chain Risk Management

### File patterns
```
docs/**/supply-chain*.md, docs/**/scrm*.md, docs/**/sr-*.md
**/SECURITY.md, **/SUPPLY_CHAIN*.*
```

### Code patterns for generation
```
# Dependency tracking
composer.lock, package-lock.json, Pipfile.lock, Cargo.lock
**/dependabot.yml, **/renovate.json

# Vendor assessment
Grep: "vendor.*assessment", "supply.*chain", "third.*party.*risk"
```

### Sub-items to check
- [ ] SCRM Plan
- [ ] SCRM team roster
- [ ] Supply chain risk assessments
- [ ] Acquisition contracts with security requirements
- [ ] Incident notification agreements
- [ ] Anti-tamper mechanisms
- [ ] Counterfeit detection procedures
- [ ] End-of-life disposition records
- [ ] Vendor support status tracking
- [ ] Awaiting/returning components config mgmt

---

## 19. CA — Interconnection & External Services

### File patterns
```
docs/**/interconnection*.md, docs/**/isa-*.md, docs/**/mou*.*
docs/**/external*.md, docs/**/integration*.*
```

### Code patterns for generation
```
# External connections
.env.sample (look for external URLs, API endpoints)
Grep: "api.*url", "endpoint", "external.*service", "third.*party"
Grep: "soap", "rest", "graphql", "webhook"

# Service connections
docker-compose.yml (external service dependencies)
**/Deployment.yaml (external service references)
```

### Sub-items to check
- [ ] ISAs, MOUs, SLAs for external connections
- [ ] Internal connection documentation
- [ ] Security assessments for external providers
- [ ] FedRAMP authorization evidence for providers
- [ ] Functions/ports/protocols from each provider
- [ ] Managed interfaces for telecom services
- [ ] Portable storage restrictions on external systems

---

## 20. RA — Risk Assessment & Categorization

### File patterns
```
docs/**/risk*.md, docs/**/ra-*.md
docs/**/fips-199*.*, docs/**/categoriz*.*
docs/**/assessment*.md
```

### Code patterns for generation
```
Grep: "fips.*199", "security.*categori", "impact.*level"
Grep: "confidentiality", "integrity", "availability"
Grep: "low.*moderate.*high", "risk.*assess"
```

### Sub-items to check
- [ ] FIPS-199 categorization (C/I/A impact levels with rationale)
- [ ] Risk assessment report (threats, vulnerabilities, likelihood, impact)
- [ ] Supply chain risk assessment
- [ ] Criticality analysis
- [ ] Risk response documentation
- [ ] Risk results reported to management
- [ ] Continuous monitoring plan

---

## 21. POA&M

### File patterns
```
docs/**/poam*.md, docs/**/poa-m*.*, docs/**/poam.xlsx
docs/**/findings*.md, docs/**/open-findings*.*
.github/issues/**, gh issue list (security-labelled tickets)
```

### Sub-items to check
- [ ] Open findings inventory with target dates
- [ ] Risk acceptance records for deferred findings
- [ ] Status updates for in-progress remediations
- [ ] Closed-finding evidence trail
- [ ] CA-5 milestone schedule

Routes to: `ssp-sections/04-poam/` + `controls/CA-assessment-authorization/evidence/CA-5/`

---

## 22. CA — Continuous Monitoring Plan

### File patterns
```
docs/**/conmon*.md, docs/**/continuous-monitoring*.*
docs/**/iscm*.*, docs/**/monitoring-strategy*.*
.github/workflows/*-monitoring.yml, .github/workflows/*-conmon.yml
```

### Code patterns for generation
```
# Cadence and scope evidence
Grep: "monthly.*scan", "quarterly.*review", "annual.*assessment"
Grep: "metric", "kpi", "control.*sampling"

# Reporting workflow
Grep: "report.*to.*ao", "monitoring.*report", "risk.*dashboard"
```

### Sub-items to check
- [ ] Documented monitoring strategy
- [ ] Control sampling plan and frequency
- [ ] Metrics with thresholds
- [ ] Reporting cadence to AO and stakeholders
- [ ] Trigger conditions for ad-hoc assessment

Routes to: `ssp-sections/13-continuous-monitoring-plan/` + `controls/CA-assessment-authorization/evidence/CA-7/`

---

## 23. PT — Privacy Impact Assessment

### File patterns
```
docs/**/pia*.*, docs/**/sorn*.*, docs/**/privacy*.md
docs/**/pii-inventory*.*, docs/**/data-classification*.*
**/privacy-policy*.*, **/cookie-policy*.*
```

### Code patterns for generation
```
# PII handling
Grep: "pii", "personal.*data", "personal.*information"
Grep: "ssn", "date.*of.*birth", "email.*address" (in column / field names only — never log values)
Grep: "encrypt.*at.*rest", "redact", "mask"

# Consent + transparency
Grep: "consent", "opt.*in", "opt.*out", "data.*subject"
```

### Sub-items to check
- [ ] PIA / Privacy Threshold Analysis filed
- [ ] SORN published (federal systems with Privacy Act records)
- [ ] PII inventory with data flows
- [ ] Consent collection mechanism (PT-2)
- [ ] Data minimisation evidence (PT-3)
- [ ] Privacy notice on user-facing surfaces (PT-5)
- [ ] Data retention/disposition policy (PT-6, SI-12)

Routes to: `ssp-sections/14-privacy-impact-assessment/` + `controls/PT-pii-processing-transparency/`

---

## 24. PM — Program Management

### File patterns
```
docs/**/program-management*.*, docs/**/security-program*.*
docs/**/pm-*.md
docs/**/governance*.*, docs/**/security-roles*.*
```

### Code patterns for generation
```
# Program-level governance
Grep: "ciso", "cso", "security.*officer", "isso", "issm"
Grep: "risk.*tolerance", "executive.*risk", "governance.*board"
.github/CODEOWNERS (security-team ownership lines)
```

### Sub-items to check
- [ ] Information security program plan (PM-1)
- [ ] Senior agency information security officer (PM-2)
- [ ] Information-security workforce (PM-13)
- [ ] Information-security measures of performance (PM-6)
- [ ] Enterprise architecture (PM-7)
- [ ] Critical infrastructure plan (PM-8)
- [ ] Risk management strategy (PM-9)
- [ ] Authorization process (PM-10)
- [ ] Mission/business process definition (PM-11)
- [ ] Insider threat program (PM-12)
- [ ] Testing, training, and monitoring (PM-14)

Routes to: `controls/PM-program-management/`. Most PM evidence is
program-level, organisation-wide — typically OPERATIONAL gaps that
the development team can't close.

---

## 25. PL — Planning Controls

> **Note**: This is the controls-level companion to Section 10
> (Security Policies & Procedures). PL-1 (policy) lives there; PL-2
> (system security plan), PL-4 (rules of behavior), PL-7 (concept of
> operations), PL-8 (security and privacy architectures), PL-9
> (central management), PL-10 (baseline selection), PL-11 (baseline
> tailoring) live here.

### File patterns
```
docs/**/ssp*.*, docs/**/system-security-plan*.*
docs/**/rules-of-behavior*.*, docs/**/rob*.md
docs/**/conops*.md, docs/**/concept-of-operations*.*
docs/**/architecture*.md, docs/**/security-architecture*.*
docs/**/baseline*.md
```

### Sub-items to check
- [ ] System Security Plan (PL-2) — full SSP document
- [ ] Rules of Behavior (PL-4) — signed by all users
- [ ] Concept of Operations (PL-7)
- [ ] Security and Privacy Architectures (PL-8)
- [ ] Baseline Selection (PL-10) — LOW/MOD/HIGH per FIPS-199
- [ ] Baseline Tailoring (PL-11) — additions and removals justified

Routes to: `controls/PL-planning/`. The SSP itself also lives in
`ssp-sections/01-system-description/` — copy where applicable.
