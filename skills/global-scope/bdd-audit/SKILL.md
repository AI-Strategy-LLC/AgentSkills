---
name: bdd-audit
description: "Three-phase BDD alignment audit: (1) specs without implementation/wiring, (2) implementation without spec coverage, (3) requirements ↔ BDD/code drift. Writes a comprehensive report at docs/bdd-audit/REPORT.md and enters plan mode to develop a resolution plan. Accepts --no-spec-to-code / --no-code-to-spec / --no-requirements to skip phases. Use when the user asks about BDD coverage, Gherkin specs, step wiring, untested code, or requirement-to-spec drift."
---

# BDD Audit

This skill is a thin stub that triggers on BDD-audit-shaped requests, runs a three-phase alignment audit via the `bdd-audit` agent, and then enters plan mode to draft a resolution plan.

## What this audits

The audit is **bidirectional + traceable** — three independent phases, each on by default:

1. **`spec-to-code`** — For every BDD feature, classify status (wired / partially wired / stubbed / missing) and determine root cause (implemented-but-untested vs truly-missing vs deferred).
2. **`code-to-spec`** — Walk the implementation surface (routes, CLI commands, UI screens, public modules, jobs) and find shipped functionality with **no** backing `.feature` coverage. Catches features built without BDD.
3. **`requirements`** — Read requirements / PRD / RFC / ADR documents and three-way reconcile requirement ↔ BDD ↔ code. Detects:
   - Requirements with no BDD or implementation.
   - BDD or code that has evolved **beyond** the requirements (new behaviour with no anchoring requirement — intentional or scope creep).
   - Requirements that have drifted from the shipped behaviour and were never updated.

## Flags

Parse the user's invocation arguments:

| Flag | Effect |
|---|---|
| `--no-spec-to-code` | Skip Phase 1 |
| `--no-code-to-spec` | Skip Phase 2 |
| `--no-requirements` | Skip Phase 3 |

Default (no flags): run all three phases. At least one phase must remain enabled — if the user passes all three `--no-*` flags, refuse and ask which phase they want.

## What to do

1. **Parse flags** from the user's invocation. Build the enabled-phase list.
2. **Invoke the agent** via the `Agent` tool with `subagent_type: "bdd-audit"`. In the prompt, state:
   - The working directory.
   - The enabled phases (named explicitly, e.g. "Run phases: spec-to-code, code-to-spec" — omit the skipped ones).
3. The agent will write `docs/bdd-audit/REPORT.md` and return a compact structured summary plus the prioritised action list.
4. **Read** `docs/bdd-audit/REPORT.md`.
5. **Enter plan mode** (`EnterPlanMode`) and present a resolution plan derived from the report. Group plan items by action category:
   - **Build first** — truly missing functionality (Phase 1 + Phase 3 "Requirement, no code").
   - **Wire now** — implementation exists, BDD exists, steps unwired (Phase 1).
   - **Spec now** — code exists, no BDD; write scenarios to lock in the contract (Phase 2).
   - **Resolve drift** — requirement vs code/BDD disagreement (Phase 3 "Spec drift").
   - **Anchor or remove** — beyond-spec functionality needing a product decision (Phase 3).
   - **Update requirements** — stale requirement docs to refresh (Phase 3).
   - **Defer** — out of scope by intent.
6. Within plan mode, order items by impact, call out any blockers between items, and surface the top 3 highest-priority items at the top of the plan.

## Why this is an agent, not inline skill work

Each phase reads many files (every `.feature`, every step file, the public-API surface, every requirements doc) and greps the source tree for domain concepts. That evidence is verbose and one-time; sequestering it in an agent's context keeps the main conversation lean and lets the plan-mode step work from a compact summary.
