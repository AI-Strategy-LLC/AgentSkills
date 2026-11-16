# Threat Model Template

Fill this template in during Phase 1 of axis E. The output becomes the threat-model section of the final report. Do not skip sections — an omitted section is a finding.

A threat model is not a vibe; it is a matrix. The goal is coverage, not prose.

---

## 1. System in scope

**Project:** {name}
**Commit:** {short SHA}
**Deployment model:** {desktop app / server / CLI / library / multi-tenant SaaS / …}
**Primary use case:** {one sentence}
**Out-of-scope components:** {anything deliberately excluded with justification}

---

## 2. Actors

Enumerate everyone who interacts with the system or whose code runs inside it. Adversarial capability notes tell you what each actor can do if it becomes hostile.

| # | Actor | Adversarial capability |
|---|---|---|
| 1 | End user (legitimate) | Can submit arbitrary prompts, arbitrary config, arbitrary MCP entries. On multi-user deployments, can act against other users. |
| 2 | Developer / contributor | Commits code; may introduce vulnerability inadvertently or deliberately. Supply-chain-adjacent. |
| 3 | CI/build system | Runs untrusted dep code at build; signs artifacts; holds signing keys. Compromise yields supply-chain RCE. |
| 4 | Agent inside the trust boundary | **Most important adversary for LLM products.** Can become hostile via jailbreak, compromised model, attacker-crafted task, poisoned memory. Has all the capabilities the daemon granted it. |
| 5 | Peer agent | Agent-to-agent attack path. In multi-agent products, peers must be treated as untrusted. |
| 6 | External network attacker | Attacks any listener (HTTP/WebSocket/gRPC/UDS). |
| 7 | Upstream supply chain | MCP servers, plugins, crate/npm deps, Docker base images, LLM provider. Each is a potential RCE/data-exfil vector. |
| 8 | Lateral same-UID process | Another process running as the same OS user. VS Code extension, npm postinstall, compromised dev tool. |
| 9 | Other tenant | Only if the product is or becomes multi-tenant. |
| … | {project-specific actor} | {capability} |

---

## 3. Assets

What the attacker wants or what must be protected. Sensitivity column drives severity of any threat that touches this asset.

| Asset | Location | Sensitivity |
|---|---|---|
| API keys (LLM provider) | {Keychain / `.swarm/secrets/` / env / …} | Critical |
| OAuth refresh tokens | {…} | Critical |
| Signing / updater keys | {…} | Critical |
| IPC token | `~/.swarm/swarm.sock.token` (typically) | High |
| Sidecar auth token | container env | High |
| User repo source code | `$HOME/…` | High (integrity) |
| Agent conversation state | daemon memory + session disk | High (confidentiality) |
| Agent prompts | in-memory + possibly logged | Medium–High |
| Memory store (cross-session) | `.swarm/memory/` or similar | High (integrity — see T6) |
| Inbox messages | `.swarm/inbox/<agent-id>/` | High (integrity — see T3) |
| Plugin code | `.swarm/plugins/` | High (integrity — see S2) |
| Config files | `.swarm/*.toml`, `~/.swarm/*.toml` | High (integrity — see S3, S4) |
| LLM provider billing | external | Medium (cost DoS) |
| Host filesystem | — | High |
| Network egress capability | — | High |
| … | … | … |

---

## 4. Trust boundaries

Each boundary is a place where data or control crosses from one trust level to another and must be revalidated.

| Boundary | From → To | Authn required | Authz required | Validation required |
|---|---|---|---|---|
| UI IPC | UI process → daemon | Yes | Per-command | Message schema |
| Daemon→agent (PTY) | daemon → local agent | Process-parent | Inherited | Input sanitization |
| Daemon→agent (gRPC) | daemon → sidecar | Yes — bearer | Per-method | Protobuf schema |
| Agent→MCP | agent → MCP subprocess | — | — | Arg allowlist, output sanitization |
| Agent→plugin | agent → plugin | — | Sandbox | Manifest verification |
| Agent→filesystem | agent → FS | — | Path containment | Canonicalize |
| Agent→network | agent → external | — | Egress allowlist | URL/scheme validation |
| Agent A → Agent B | via inbox/memory | Yes (identity) | Per-recipient | Sanitize + wrap |
| User repo → daemon | config-file ingest | — | — | Signature / approval |
| … | … | … | … | … |

Any row with "Yes" in authn/authz column where the code does not actually enforce is a CRITICAL finding.

---

## 5. Attack surfaces

Every entry point. One row per surface. Used to ground the actor × surface × threat matrix below.

| # | Surface | Description | Reachable by |
|---|---|---|---|
| AS-01 | IPC commands | every `Command::` variant | actors 1, 8 |
| AS-02 | gRPC endpoints | every tonic RPC | actors 6, 7 |
| AS-03 | WebSocket endpoints | every `/ws` route | actors 1, 6 |
| AS-04 | HTTP REST endpoints | if any | actors 1, 6 |
| AS-05 | Config-file ingest | every `.toml` / `.md` / `.json` read from repo or user dir | actor 1 (who controls what repo gets cloned) |
| AS-06 | MCP server response ingestion | stdout of MCP child process | actor 7 |
| AS-07 | Plugin load | plugin code execution | actor 7 |
| AS-08 | Inbox ingest | messages read from `.swarm/inbox/` | actors 4, 5 |
| AS-09 | Memory read | cross-session memory content | actors 4, 5 |
| AS-10 | Task assignment files | `.swarm/agents/*.md` | actors 4, 5 |
| AS-11 | Tool calls (outbound) | every tool an agent can invoke | driven by actor 4 |
| AS-12 | Git branches the agent rebases | cross-agent contamination via shared branches | actor 5 |
| AS-13 | Environment variables passed to subprocesses | `AGENT_AUTH_TOKEN`, secrets | actor 4 (can log the env of subprocesses it spawns) |
| AS-14 | LLM provider API responses | every completion that comes back | actor 7 |
| … | … | … | … |

---

## 6. Threat catalog

Threats numbered T1–Tn. For each, record the surface(s) it applies to, the likelihood/impact, the mitigation expected, and the mitigation status.

### STRIDE (per surface)

For each surface AS-01 through AS-n, apply STRIDE:

| # | Surface | Spoofing | Tampering | Repudiation | Info disclosure | DoS | EoP |
|---|---|---|---|---|---|---|---|
| AS-01 IPC | Mutual authn? | Message integrity? | Audit? | Error leaks? | Rate limit? | Privilege escalation? |
| AS-02 gRPC | … | … | … | … | … | … |
| … | … | … | … | … | … | … |

Each cell is either "not applicable" (with a one-line reason) or "applicable — mitigation at `{file:line}` / MISSING".

### LLM-specific threats (T-series)

From `axis-details.md §E Phase 3`:

| # | Threat | Applies to surfaces | Mitigation site | Status |
|---|---|---|---|---|
| T1 | Direct prompt injection (user) | AS-01 (user-provided prompts) | System prompt robustness | {assessed} |
| T2 | Indirect prompt injection (external content) | AS-06, AS-14, AS-05, tool outputs | sanitize + wrap at read time | {assessed} |
| T3 | Agent-to-agent injection | AS-08, AS-09, AS-10, AS-12 | wrap + authorship + capability check | {assessed} |
| T4 | Tool-use exploitation | AS-11 | per-tool allowlist + approval | {assessed} |
| T5 | Output exfiltration via tool args | AS-11 | egress allowlist + redaction | {assessed} |
| T6 | Context poisoning | AS-09, AS-05 | provenance tagging + integrity | {assessed} |
| T7 | Jailbreak propagation | AS-08, AS-09 | same as T2+T3 | {assessed} |
| T8 | Supply-chain prompt injection | AS-06, AS-07, AS-14 | treat as T2; allowlist servers | {assessed} |
| T9 | Side-channel exfiltration | AS-11, AS-06 | egress monitoring | {assessed} |

---

## 7. Actor × surface × threat matrix (compressed)

Top actors crossed with top surfaces. Fill each cell with the highest-severity realized threat. This is the "what does the attacker actually get?" view.

|                  | IPC | gRPC | WS | Config | MCP resp | Inbox | Memory | Tool calls |
|---|---|---|---|---|---|---|---|---|
| End user         |     |      |    |        |          |       |        |            |
| Compromised peer agent |     |      |    |        |          |       |        |            |
| Network attacker |     |      |    |        |          |       |        |            |
| Same-UID process |     |      |    |        |          |       |        |            |
| MCP server       |     |      |    |        |          |       |        |            |
| Plugin           |     |      |    |        |          |       |        |            |

Empty cell = actor cannot reach this surface. Non-empty cell references a threat number and its mitigation status.

---

## 8. Risk assessment summary

| Actor | Worst unmitigated threat | Severity | Mitigation gap |
|---|---|---|---|
| Compromised peer agent | {e.g. prompt-injection into peer via unsanitized inbox} | CRITICAL | Sanitizer wraps memory only |
| Network attacker on WS | {e.g. auth via query-string token} | HIGH | Query-token fallback accepted |
| Malicious MCP server | {e.g. subprocess RCE on host} | CRITICAL | No allowlist, no metachar reject |
| … | … | … | … |

Every CRITICAL and HIGH row in this summary must appear as a numbered finding in the main report.

---

## 9. Residual risk (explicit)

After mitigations, what remains? This section is where the reviewer declares what the product *cannot* defend against and the user must accept.

Examples:
- Direct prompt injection from the legitimate user is not mitigated. The user is the authority.
- A fully-compromised LLM provider can inject arbitrary content into the agent. No mitigation inside this system.
- A sophisticated kernel-level attacker on the host can bypass the Seatbelt sandbox. This product does not defend against post-privesc attackers.

If this section is empty, the reviewer did not try hard enough.

---

## 10. Recommendations

Priority-ordered list of mitigations that would close the highest-severity gaps. Not a menu — the product is not secure until all CRITICAL and HIGH gaps close.

- [ ] {remediation}
- [ ] {remediation}
- [ ] {remediation}

---

## Using this template as a live artifact

The threat model is not a one-shot document. Mark it with the commit SHA and revisit on every architectural change. The `deep-review` skill, when re-run on a later SHA, diffs against the prior threat model and flags new surfaces / new actors / new assets that were not covered.
