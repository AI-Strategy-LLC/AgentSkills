# Language-Specific Patterns

Catalog of stub, no-op, and "working but lying" signals by language. Use with the axis techniques in `axis-details.md`.

## Stub and no-op signals

| Language | Stub macros / calls | Common "not implemented" strings | Empty-body idioms |
|---|---|---|---|
| **Rust** | `todo!()`, `unimplemented!()`, `panic!("TODO")`, `panic!("not yet")` | `"not yet implemented"`, `"Not implemented"`, `"TODO:"`, `"FIXME:"` | `fn foo() {}`, `Variant => {}`, `Variant => Ok(())` |
| **Python** | `raise NotImplementedError`, `raise NotImplementedError()`, `pytest.skip` | `"TODO"`, `"FIXME"`, `"XXX"` | `def foo(): pass`, `def foo(): ...`, `def foo(): return None` |
| **TypeScript / JS** | `throw new Error("not implemented")`, `throw new Error("TODO")` | `"TODO:"`, `"FIXME:"`, `"XXX:"` | `function foo() {}`, `() => {}`, `() => undefined`, `() => null` |
| **Go** | `return godog.ErrPending`, `panic("not implemented")`, `panic("TODO")` | `"not implemented"`, `"TODO"`, `"FIXME"` | `func foo() {}`, `func foo() error { return nil }` without real work |
| **Swift** | `fatalError("not implemented")`, `preconditionFailure("TODO")` | `"TODO:"`, `"FIXME:"` | `func foo() {}`, `return //`  |
| **Java / Kotlin** | `throw new PendingException()`, `TODO("...")`, `throw new UnsupportedOperationException()` | `"TODO:"`, `"FIXME:"`, `"XXX:"` | `void foo() {}`, `fun foo() {}`, `return null /* TODO */` |
| **Ruby** | `raise NotImplementedError`, `raise "TODO"` | `"# TODO"`, `"# FIXME"` | `def foo; end`, `def foo; nil; end` |
| **PHP** | `throw new \Exception("not implemented")` | `"// TODO"`, `"// FIXME"` | `function foo() {}`, `function foo() { return null; }` |

## Test framework signals

Where the step / test body is purely cosmetic — logs something and returns green.

| Framework | "Verifies nothing" body patterns |
|---|---|
| **cucumber-rs** (Rust) | Body is only `tracing::info!(...)`, `println!(...)`, `eprintln!(...)`, or `log::info!(...)` |
| **cucumber-js** (JS/TS) | Body is only `console.log(...)` / `console.info(...)` |
| **behave** (Python) | Body is only `print(...)` / `logger.info(...)` / `pass` |
| **godog** (Go) | Body is only `fmt.Println` / `log.Printf` / `return nil` |
| **cucumber-jvm** (Java/Kotlin) | Body is only `System.out.println(...)` / `logger.info(...)` / empty |
| **pytest** | Body is only a print; no `assert` / no `pytest.raises` / no marker assertion |
| **JUnit / Jest** | Body has no `assertThat` / `assertEquals` / `expect(...)` |
| **Swift Testing / XCTest** | Body has no `#expect` / `#require` / `XCTAssert` family |

## "Working but lying" signals

These are patterns where a grep for stubs finds nothing, but the code still does not do what its surface claims.

| Pattern | What it looks like | Why it's a finding |
|---|---|---|
| **Collapsed match arm** | `A | B | C => shared_fn(...)` in an enum whose variants are advertised as distinct | The shared dispatch is fine — the lie is in the docs claiming distinct capabilities |
| **Factory rejection** | `ProviderType::X => Err("not yet implemented")` | User-selectable variant that cannot actually run |
| **No-op trait impl** | `fn send_task(...) -> Response { Response { success: false, error: "Not implemented".into() } }` | The trait compiles, the tests that hit the trait silently fail green, the surface advertises capability |
| **Defined but never called** | `pub fn build_standard_volumes() -> Vec<Mount> { ... }` — only test callers | Function looks like it belongs in a production path but isn't wired up |
| **Hollow handler** | `async fn ws_handler(...) { drop(socket); drop(state); }` with a `// TODO: integrate` | Request path accepted and silently discarded |
| **Protocol without parser** | `write!(stream, "APPROVAL:{}:{}", id, response)` with no corresponding `parse` elsewhere | Invented protocol that nothing listens to |
| **Docstring fiction** | Module header: `env = { X = "${X}" }` interpolation documented | Grep for the interpolation regex in the implementation — if absent, docstring lies |
| **Config without reader** | `config.toml` key described in docs; `rg <key>` in `src/` returns only the docs | Config surface without runtime effect |
| **Disabled workflow** | `.github/workflows/release.yml.disabled` | Capability was scaffolded and is not currently active |
| **Dev-mode bypass** | `if env::var("DEV_MODE").is_ok() { return Ok(None); }` as the only "support" for auth | Production code that silently skips the auth check |
| **Query-param auth fallback** | `req.uri().query().and_then(..."token=")` in a WebSocket handler | Tokens leak through logs, browser history |

## Recommended grep commands

First-pass: stubs across all languages:

```bash
rg -n --type-add 'src:*.{rs,py,ts,tsx,js,jsx,go,java,kt,swift,rb,php}' \
  'todo!\(\)|unimplemented!\(\)|NotImplementedError|PendingException|godog\.ErrPending|"not yet implemented"|"Not implemented"|TODO:|FIXME:|XXX:|HACK:' \
  -tsrc
```

Second-pass: collapsed match arms (Rust-specific example):

```bash
# Look for match arms where multiple variants share a block
rg -n --multiline '(\w+::)\w+\s*\|\s*\1\w+\s*(?:\|\s*\1\w+\s*)*=>' --type rust
```

Third-pass: `let _ =` and `.ok()` in state-bearing modules:

```bash
rg -n 'let _ =' crates/*/src/{orchestrator,session,lifecycle,config,billing}/*.rs 2>/dev/null
rg -n '\.ok\(\);' crates/*/src/{orchestrator,session,lifecycle,config,billing}/*.rs 2>/dev/null
```

Fourth-pass: test-step bodies with no assertions (cucumber-rs example):

```bash
# Find #[then]/#[when]/#[given] functions whose body is only a log call
# (Requires ast-grep or similar for robust AST queries; rg approximation below)
rg -n -B1 -A6 '#\[(then|when|given)\(' --type rust | rg -A5 'tracing::info!' | head -100
```

Fifth-pass: disabled workflows and relative build paths:

```bash
ls .github/workflows/*.disabled 2>/dev/null
rg -n '"(\.\./)+' **/{tauri.conf.json,package.json,Cargo.toml,build.gradle} 2>/dev/null
```
