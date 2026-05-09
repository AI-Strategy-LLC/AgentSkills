---
name: honesty-audit
description: "Language-agnostic mechanical scan for honesty failure modes: bypassed tests/hooks, tautological/always-pass tests, disabled or focused tests, stubs in production paths, swallowed errors, weak CI gates, and 'done' claims in commits that lack file:line citations. Auto-detects active toolchains (Rust, Python, JS/TS, Go, Java, Kotlin, C#, Swift, Ruby, PHP, C/C++, Scala, Dart, Elixir, shell) and runs only the relevant patterns. Designed to be fast, deterministic, and portable to CI. Triggers on 'honesty audit', 'honesty check', 'are we cheating', 'find tautological tests', 'find disabled tests', 'stub check', 'no-bypass check', 'pre-commit honesty', 'is this branch actually done', 'cite-the-line audit'. Distinct from /bdd-audit (spec↔code alignment) and /deep-review (broad multi-axis review): this skill only checks the narrow honesty-hygiene surface so it can run on every commit."
---

# Honesty Audit

Catch the failure modes that show up when AI-assisted (or human-rushed) code lies about its own state: bypassed gates, tests that can't fail, stubs claimed as done, errors swallowed, "complete" claims with no cite-the-line proof. Mechanical pattern matching only — no LLM judgment in the scan path. Fast enough to run on every push.

This skill is **not** a replacement for `/bdd-audit` or `/deep-review`. Those need agent-level reasoning. This one is the lint-tier honesty floor that should always be green.

## Scope and what it deliberately does NOT do

| In scope | Out of scope (use other skills) |
|---|---|
| Mechanical patterns: greps with curated regexes | Spec ↔ code alignment → `/bdd-audit` |
| Single-file findings with file:line citations | Threat modeling, security review → `/deep-review` |
| CI workflow gate completeness | User-journey, doc-correctness audits → `/deep-review` |
| Stale "done" claims in recent commit messages | Test coverage measurement → `/coverage-audit` |
| Triage suggestion (severity + suppression hints) | Writing or fixing the offending code (caller decides) |
| Discovering and deferring to in-repo lint scripts | Replacing them — if a project lint already covers a tier, defer |

If a user asks "is this code complete?" — that's a `/deep-review` request. If they ask "is anyone cheating?" — that's this skill.

## Outputs

Always write **two** artefacts so the same run feeds both humans and CI:

1. `docs/honesty-audit/REPORT.md` — human-readable, grouped by severity, includes file:line for every finding and the exact pattern that matched.
2. `docs/honesty-audit/findings.json` — machine-readable, one record per finding:
   ```json
   {"id": "HA-0001", "tier": "critical", "category": "test-bypass",
    "file": "scripts/release.sh", "line": 42,
    "pattern": "git commit --no-verify",
    "match": "  git commit --no-verify -m \"release\"",
    "suggested_action": "Remove --no-verify; if hook genuinely needs to be skipped, document why inline.",
    "suppression": "honesty:ignore line"}
   ```

**Exit summary** the skill prints at the end:
- Counts by tier: `critical: N | high: N | medium: N | info: N`
- A one-line CI verdict: `PASS` (zero critical/high) or `FAIL: N critical, N high`
- Path to both artefacts.

## Step 0 — Detect toolchains and discover existing tooling

### 0a — Build the active language set

Read the repo root and obvious subdirs for toolchain markers. Only run patterns from sections whose language is active. Skip the rest silently — don't flag absences.

| Marker file(s) | Languages enabled |
|---|---|
| `Cargo.toml` | rust |
| `package.json` | js, ts |
| `pyproject.toml` / `setup.py` / `setup.cfg` / `requirements*.txt` | python |
| `go.mod` | go |
| `*.csproj` / `*.sln` / `Directory.Build.props` | csharp |
| `pom.xml` / `build.gradle*` / `settings.gradle*` | java, kotlin |
| `Package.swift` / `*.xcodeproj` / `*.xcworkspace` | swift |
| `Gemfile` / `*.gemspec` | ruby |
| `composer.json` | php |
| `CMakeLists.txt` / `Makefile` listing `.c`/`.cpp` sources / `meson.build` / `Bazel.BUILD` with cc rules | c, cpp |
| `build.sbt` / `*.sbt` | scala |
| `pubspec.yaml` | dart |
| `mix.exs` | elixir |
| `*.bats` files anywhere / `test/bats/` | shell |

A repo can — and usually does — activate several languages at once. The patterns in each tier below are organised as language→regex tables so adding a new language is one row, not a new section.

### 0b — Build the path classifier

Test-path globs (override per-project via `.honesty-audit.toml` if you need to):

- `**/tests/**`, `**/test/**`, `**/__tests__/**`, `**/spec/**`, `**/specs/**`
- `**/*_test.go`, `**/*_test.py`, `**/test_*.py`
- `**/*.test.ts`, `**/*.test.tsx`, `**/*.test.js`, `**/*.spec.ts`, `**/*.spec.js`, `**/*.spec.tsx`
- `**/*Tests.swift`, `**/*Test.swift`
- `**/*Test.java`, `**/*Tests.java`, `**/*Spec.java`, `**/*Test.kt`, `**/*Tests.kt`, `**/*Spec.kt`
- `**/*Tests.cs`, `**/*Test.cs`, `**/*Spec.cs`
- `**/*_spec.rb`, `**/*_test.rb`, `**/spec/**`
- `**/Tests/**` (PHP), `**/*Test.php`
- `**/test/**.dart`, `**/*_test.dart`
- `**/test/**.exs`, `**/*_test.exs`
- `**/*.bats`

Anything not in a test path is **production**. If the repo uses an unusual layout (e.g. tests intermixed with sources), call it out in the report header so the reader knows the classifier might be too narrow.

### 0c — Discover existing in-repo honesty tooling

Before running, list any pre-existing test-quality / honesty / lint scripts the project already maintains:

```bash
ls scripts/ci/check-test-quality.* scripts/ci/honesty-* scripts/lint/honesty* \
   scripts/lint/test-quality* tools/honesty-* tools/lint/honesty* 2>/dev/null
```

If any are found:
- Note them in the report header under "Complementary in-repo tooling" with a one-line summary of what each covers (read the file's header docstring).
- For tiers that the existing tool already covers (e.g. Rust hollow-test detection in `check-test-quality.py`-style scripts), the skill should **not** duplicate the work — instead emit one INFO record per covered tier saying "deferred to <script>".
- This avoids both noise and the "two tools disagree about whether this passes" failure mode.

### 0d — Suppression mechanism

- Repo-root `.honesty-audit-ignore` file. Each non-blank, non-comment line:
  ```
  <category>:<glob-or-finding-id>   reason: <free text — must be non-empty>
  ```
  Examples:
  ```
  test-bypass:scripts/legacy-deploy.sh                reason: legacy script, scheduled for removal in #4521
  stub-prod:lib/plugins/api.rs                        reason: trait default, intentional noop
  HA-0017                                              reason: false positive on protobuf-generated code
  global:^.*generated.*$                               reason: skip auto-generated lines from any source
  ```
- Inline comment `honesty:ignore <reason>` on the matched line or the line directly above. Reason must be non-empty.
- Empty reasons are themselves a Tier-2 finding (an undocumented suppression is itself a smell).

## Tier 1 — Bypass mechanisms (CRITICAL — must fail CI)

These mechanically defeat the test/hook/lint gates. Every match is critical unless suppressed with a documented reason.

### 1.1 Git hook bypass

```bash
rg -n --hidden \
  -g '!**/.git/**' -g '!**/node_modules/**' -g '!**/target/**' -g '!**/dist/**' \
  -g '!**/build/**' -g '!**/.worktrees/**' \
  -e '--no-verify' \
  -e '--no-gpg-sign' \
  -e '-c[[:space:]]+commit\.gpgsign=false' \
  -e 'core\.hooksPath[[:space:]]*=' \
  .
```

Flag every hit in `scripts/`, `.github/`, `Makefile*`, `package.json` scripts, `justfile`, `Taskfile*`, husky config, lefthook config, pre-commit config, `Rakefile`, `mix.exs` aliases, `composer.json` scripts. Calibration: matches inside test fixtures and inside the *banlist* of a security policy module should be suppressed by glob — but the skill emits them once, the maintainer adds the suppression, and they stay quiet thereafter.

### 1.2 CI step skipping

Search the **directory**, not a glob — both `*.yml` and `*.yaml` plus nested workflow files matter:

```bash
rg -n \
  .github/workflows/ \
  .gitlab-ci.yml \
  .circleci/config.yml \
  azure-pipelines.yml \
  Jenkinsfile \
  -e 'continue-on-error:[[:space:]]*true' \
  -e '^[[:space:]]*if:[[:space:]]*false[[:space:]]*$' \
  -e '\|\|[[:space:]]*true[[:space:]]*$' \
  -e '\|\|[[:space:]]*exit[[:space:]]+0' \
  2>/dev/null
```

Then specifically inspect every job step that runs a test command — `cargo test`, `pytest`, `go test`, `npm test`, `dotnet test`, `mvn test`, `gradle test`, `xcodebuild test`, `swift test`, `rspec`, `bundle exec rake test`, `phpunit`, `dart test`, `flutter test`, `mix test`, `ctest`, `bats`. If any of those have `continue-on-error: true` or are `if:`-gated to a condition that's never true on PRs/main, that's the failure mode this tier exists to catch.

### 1.3 Test-runner short-circuits (language-spanning)

| Language(s) | Regex(es) |
|---|---|
| All | `\bSKIP_TESTS\b`, `\bCI_SKIP\b`, `\bNO_TEST\b` env-var reads inside test bootstrap |
| Rust | `cargo test .* --no-default-features` when a `tests` feature exists |
| JS/TS (jest/vitest) | `jest --passWithNoTests` (only flag if no tests exist), `vitest run --passWithNoTests` |
| Python | `pytest --co -q` where a real run was expected; `pytest --collect-only` in CI |
| Go | `go test -run '^$'` (matches nothing) |
| Ruby | `rspec --dry-run`; `--tag ~slow` patterns that exclude full coverage |
| PHP | `phpunit --list-tests` in place of `phpunit` |
| Scala | `sbt "testOnly *MissingClass*"` with no fallback |
| Dart/Flutter | `flutter test --dry-run` |
| Elixir | `mix test --only nope` |
| Shell/Bats | `bats --no-tempdir-cleanup --filter 'never-matches'` |

### 1.4 Coverage threshold of zero or absent

In coverage configs (`pyproject.toml [tool.coverage]`, `jest.config.*`, `.nycrc`, `vitest.config.*`, `codecov.yml`, `.coveragerc`, `simplecov` config, `phpunit.xml` `<coverage>` blocks, `dart_test.yaml`, lcov thresholds in CI):

- `fail_under = 0` or absent
- `coverageThreshold: { global: { lines: 0 } }`
- `target: 0%`
- A coverage step in CI that emits a `::warning::` (or equivalent) but never `exit 1` on threshold breach

A coverage gate set to 0 — or set to "warn only" — is a gate that doesn't gate.

## Tier 2 — Tautological / always-pass tests (HIGH)

A test that cannot fail is worse than no test, because it shows green on dashboards.

### 2.1 Pure tautologies — language-spanning patterns (test files only)

Every regex below should be applied **only inside test paths** (use the classifier from Step 0b).

| Language | Patterns |
|---|---|
| Rust | `assert!\(\s*true\s*\)`, `assert_eq!\(\s*1\s*,\s*1\s*\)`, `assert_eq!\(\s*"([^"]*)"\s*,\s*"\1"\s*\)` |
| Python | `^\s*assert True\s*$`, `^\s*assert 1 == 1\s*$`, `^\s*pass\s*#.*test`, `assertTrue\(True\)`, `assertEqual\(1,\s*1\)` |
| JS/TS | `expect\(true\)\.toBe\(true\)`, `expect\(1\)\.toBe\(1\)`, `expect\([^)]+\)\.toBeDefined\(\)\s*$`, `expect\(.+\)\.not\.toThrow\(\)\s*$`, `assert\.ok\(true\)` |
| Go | (heuristic) test funcs that contain only `t.Log` / `t.Logf` and zero `t.Error*`, `t.Fatal*`, `require.*`, `assert.*` calls |
| Java/Kotlin | `assertTrue\(\s*true\s*\)`, `assertEquals\(\s*1\s*,\s*1\s*\)`, `assertThat\(true\)\.isTrue\(\)` |
| C# | `Assert\.IsTrue\(\s*true\s*\)`, `Assert\.That\(true\)`, `Assert\.AreEqual\(\s*1\s*,\s*1\s*\)` |
| Swift | `#expect\(true\)`, `XCTAssertTrue\(true\)`, `#expect\(1 == 1\)` |
| Ruby | `expect\(true\)\.to be true`, `assert_equal 1, 1`, `assert true` |
| PHP | `assertTrue\(true\)`, `assertEquals\(1,\s*1\)`, `\$this->assertTrue\(true\)` |
| C/C++ | `EXPECT_TRUE\(true\)`, `ASSERT_TRUE\(true\)`, `REQUIRE\(true\)` (Catch2), `CHECK\(true\)` |
| Scala | `assert\(true\)`, `1\s+shouldBe\s+1`, `true\s+should be\s+true` |
| Dart | `expect\(true,\s*isTrue\)`, `expect\(1,\s*equals\(1\)\)` |
| Elixir | `assert true`, `assert 1 == 1` |
| Shell/Bats | `assert_equal 1 1`, `[\s+0\s+-eq\s+0\s+]` |

### 2.2 Empty test bodies (no assertions)

Heuristic, language-spanning: per test file, count test declarations vs assertion-shaped calls. A test file with **N** test declarations and **0** assertion calls is suspect.

| Language | Test-decl pattern | Assertion-shaped patterns |
|---|---|---|
| Rust | `#\[test\]`, `#\[tokio::test\]` | `assert!`, `assert_eq!`, `assert_ne!`, `.unwrap()`, `.expect(`, `panic!`, `#[should_panic]` |
| Python | `def test_`, `@pytest\.fixture` (skip), test class methods | `assert `, `self\.assert`, `raises\(`, `pytest\.raises` |
| JS/TS | `it\(`, `test\(`, `describe\(` (no body if only describes) | `expect\(`, `assert\.`, `\.toThrow\(`, `\.rejects\.` |
| Go | `func Test` | `t\.Error`, `t\.Fatal`, `require\.`, `assert\.`, `t\.Skip` (counts as a documented escape) |
| Java/Kotlin | `@Test` | `assert`, `Assert\.`, `Assertions\.`, `expectThrows` |
| C# | `\[Fact\]`, `\[Theory\]`, `\[Test\]` | `Assert\.`, `Should\.`, `Throws<` |
| Swift | `func test`, `@Test` (Swift Testing) | `XCTAssert`, `#expect\(`, `#require\(` |
| Ruby | `it\s+['"]`, `def test_` | `expect\(`, `assert`, `_should_` |
| PHP | `public function test`, `#\[Test\]` | `\$this->assert`, `static::assert`, `expectException` |
| C/C++ | `TEST\(`, `TEST_F\(`, `TEST_CASE\(` | `EXPECT_`, `ASSERT_`, `REQUIRE`, `CHECK` |
| Scala | `test\(`, `it\s+should`, `"x" in` | `assert\(`, `\sshouldBe\s`, `\sshould be\s` |
| Dart | `test\(`, `testWidgets\(` | `expect\(`, `expectLater\(` |
| Elixir | `test\s+"` | `assert\s`, `refute\s`, `assert_raise` |
| Shell/Bats | `^@test\s+"` | `assert_*`, `\[\s.*\s\]`, `run\s+` |

The script writes a small `empty-test-bodies.sh` helper on first run that does this counting per language and emits one finding per offending file.

### 2.3 Mock-only tautologies

A test that **sets** a mock to return X and then **asserts** the mock returns X is testing the mocking framework, not the system. Heuristic: in a test file, find lines matching `mock.*returns?.*\(([^)]+)\)` (or framework equivalents like `when(...).thenReturn(...)`, `Mock(...).return_value = ...`, `MockedClass::shouldReceive('foo')->andReturn(...)`) and look for `assert.*\1` within ±10 lines. List candidates for human review — false positives expected, so report under "review" not "fail".

## Tier 3 — Disabled / skipped / focused tests (HIGH if undocumented)

Disabling a test is sometimes legitimate. Disabling without a written reason is the smell.

### 3.1 Skip / ignore / disable markers — language-spanning

| Language | Markers |
|---|---|
| Rust | `#\[ignore\]` (bare — no reason string), `#\[ignore =` (only flag if reason is empty or generic like `"WIP"`) |
| Python (pytest) | `@pytest\.mark\.skip\b`, `@pytest\.mark\.skipif\b`, `@pytest\.mark\.xfail\b`, `pytest\.skip\(` |
| Python (unittest) | `@unittest\.skip\b`, `@unittest\.skipIf\b`, `@unittest\.expectedFailure` |
| JS/TS | `\b(xit|xdescribe|it\.skip|test\.skip|describe\.skip)\b`, `pending\(` |
| Java | `@Disabled`, `@Ignore` |
| Kotlin | `@Disabled`, `@Ignore` |
| C# | `\[Ignore\(`, `\[Fact\(Skip\s*=`, `\[Theory\(Skip\s*=` |
| Go | `t\.Skip\(`, `t\.Skipf\(`, `//go:build ignore` on test files |
| Swift | `XCTSkip`, `try XCTSkipUnless`, `try XCTSkipIf` |
| Ruby | `skip\s+['"]`, `pending\s+['"]`, `xit\b`, `xdescribe\b` |
| PHP | `\$this->markTestSkipped\(`, `\$this->markTestIncomplete\(`, `#\[RequiresPhp\(` |
| C/C++ | `GTEST_SKIP\(`, `DISABLED_` prefix on test names, `[!hide]` (Catch2) |
| Scala | `pending`, `assume\(`, `cancel\s*\(` |
| Dart | `, skip:\s*['"]`, `, skip:\s*true` |
| Elixir | `@tag :skip`, `@moduletag :skip` |
| Shell/Bats | `skip\s+["']` |

For each match, look at the line above for a documented reason (`// requires <X>`, `// blocked by #1234`, `honesty:ignore <reason>`). **Undocumented skip = HIGH finding.**

### 3.2 Focused tests (always CRITICAL — scope to test files only)

Focused tests cause the rest of the suite to be silently skipped. Almost always a pre-commit oversight, never legitimate in main.

**Calibration note**: scope this scan to **test files only** via the path classifier. The `\bfit\(` pattern collides with legitimate production APIs (e.g. xterm.js `FitAddon.fit()`, statistical `fit()` methods, animation `fit-content`). On non-test paths these are false positives.

```bash
rg -n \
  -g '**/*.test.*' -g '**/*.spec.*' -g '**/tests/**' \
  -g '**/spec/**' -g '**/__tests__/**' \
  -g '!**/node_modules/**' \
  -e '\bfit\(' -e '\bfdescribe\(' \
  -e '\bit\.only\(' -e '\btest\.only\(' -e '\bdescribe\.only\(' \
  -e '#\[test_only\]' \
  -e 'describe\s*\.\s*only' \
  .
```

A single `.only` can hide hundreds of tests. Always CRITICAL.

### 3.3 Commented-out test functions

```bash
rg -n -B1 \
  -e '^[[:space:]]*//[[:space:]]*(#\[test\]|it\(|test\(|describe\(|TEST\()' \
  -e '^[[:space:]]*#[[:space:]]*def test_' \
  -e '^[[:space:]]*--[[:space:]]*test\s*"' \
  .
```

Report under "review" — sometimes intentional, often the author meant to come back.

## Tier 4 — Stubs in production paths (CRITICAL)

A `todo!()` reachable at runtime is a panic-on-call. A function that returns `Ok(())` and does nothing is a silent lie.

### 4.1 Hard stubs — language-spanning (production paths only)

| Language | Patterns |
|---|---|
| Rust | `^\s*todo!\(`, `^\s*unimplemented!\(`, `panic!\("not (yet )?implemented`, `panic!\("TODO` |
| Python | `raise NotImplementedError` (suppress in `class .+\(.*ABC.*\):` blocks via inline `honesty:ignore abstract`) |
| JS/TS | `throw new Error\(\s*['"]not implemented`, `throw new Error\(\s*['"]TODO` |
| Go | `panic\(\s*"not implemented`, `panic\(\s*"TODO`, `return errors\.New\("not implemented"\)` |
| Java | `throw new UnsupportedOperationException\(\s*\)`, `throw new UnsupportedOperationException\(\s*"(not impl|TODO)` |
| Kotlin | `TODO\(\s*\)`, `TODO\(\s*"(not impl|TBD|FIXME)` |
| C# | `throw new NotImplementedException`, `throw new NotSupportedException\(\s*"TODO` |
| Swift | `fatalError\(\s*"not implemented`, `preconditionFailure\(\s*"TODO`, `assertionFailure\(\s*"TODO` |
| Ruby | `raise NotImplementedError`, `raise "TODO"`, `raise 'not implemented'` |
| PHP | `throw new \\?\w*NotImplementedException`, `throw new \\?Error\(\s*['"]TODO`, `trigger_error\(\s*['"]TODO` |
| C/C++ | `assert\(\s*false\s*&&\s*"not impl`, `throw std::runtime_error\(\s*"not impl`, `__builtin_unreachable\(\)` outside switch defaults |
| Scala | `\?\?\?` (Predef), `throw new NotImplementedError`, `sys\.error\(\s*"TODO` |
| Dart | `throw UnimplementedError\(`, `throw 'TODO'` |
| Elixir | `raise "not implemented"`, `raise "TODO"` |
| Shell | `echo\s+"TODO";\s+exit\s+1`, `echo\s+"not implemented";\s+exit` |

All matches in **production** paths are CRITICAL. Test paths are excluded by the classifier.

### 4.2 Hollow function bodies

A function that **only** returns a success constant is a stub posing as an implementation. This requires a small AST helper rather than pure regex; the script writes `docs/honesty-audit/scripts/hollow-bodies.sh` on first run that:

- Lists each function/method in production paths via tree-sitter or a per-language regex
- Counts non-trivial statements in the body (excluding `return`, comments, blank lines, `pass`, single trace/log calls)
- If the body is *only* `return Ok(())` / `return None` / `return null` / `return undefined` / `pass` / `return true` / `return false` / `return ""` / `return 0` and the function takes arguments that are unused, list it for review.

Mark Tier 4 — but report as "review" not "critical" because legitimate empty trait impls and noop default implementations exist.

### 4.3 TODO/FIXME/XXX/HACK in production

```bash
rg -n -g '!**/tests/**' -g '!**/test_*' -g '!**/*_test.*' \
  -g '!**/docs/**' -g '!**/node_modules/**' -g '!**/target/**' \
  -g '!**/.git/**' -g '!**/.worktrees/**' -g '!**/build/**' \
  -e '\bTODO\b' -e '\bFIXME\b' -e '\bXXX\b' -e '\bHACK\b' .
```

Report as **medium**, grouped by file, capped at 50 in the report (link to JSON for full list). The point is to surface trend and hotspots, not drown the reviewer. Files with > 10 markers each are called out individually; everything else is summarised.

## Tier 5 — Error swallowing (MEDIUM) — language-spanning

| Language | Patterns |
|---|---|
| Rust | `let _ = .*\.(unwrap_or_default\|ok)\(`, `\.unwrap_or\(\s*Default::default\(\)\s*\)`, `\.expect\(\s*""\s*\)`, `\.unwrap\(\)\s*//.*hack` |
| Python | `except[[:space:]]*:[[:space:]]*$`, `except[[:space:]]+\w+[[:space:]]*:[[:space:]]*pass`, `except[[:space:]]+Exception[[:space:]]*:[[:space:]]*pass`, `contextlib\.suppress\(Exception\)` |
| JS/TS | `catch\s*\([^)]*\)\s*\{\s*\}`, `catch\s*\([^)]*\)\s*\{\s*//.*ignore`, `\.catch\(\s*\(\)\s*=>\s*\{\s*\}\s*\)`, `\.catch\(\s*\(\s*_?\s*\)\s*=>\s*\{\s*\}\s*\)` |
| Go | `_,\s*_\s*=\s*\w+\(`, `_\s*=\s*\w+\.Close\(\)`, `defer\s+\w+\.Close\(\)` (without error capture) |
| Java/Kotlin | `catch[[:space:]]*\(\s*\w+\s+\w+\s*\)\s*\{\s*\}`, `catch[[:space:]]*\(\s*\w+\s*:\s*\w+\s*\)\s*\{\s*\}` (Kotlin) |
| C# | `catch\s*\([^)]*\)\s*\{\s*\}`, `catch\s*\{\s*\}` |
| Swift | `try\?\s+\w+`, `catch\s*\{\s*\}` |
| Ruby | `rescue\s*=>\s*\w+\s*$\s*end`, `rescue\s+\w+\s*;\s*end`, `rescue\s+nil` |
| PHP | `catch\s*\(\s*\\?\w+\s+\$\w+\s*\)\s*\{\s*\}` |
| C/C++ | `catch\s*\(\.\.\.\)\s*\{\s*\}`, `(void)\s*\w+\(` (intentional discard, but flag for review) |
| Scala | `Try\(.*\)\.toOption`, `\.recover\s*\{\s*case\s+_\s*=>\s*\(\)\s*\}` |
| Dart | `catch\s*\([^)]*\)\s*\{\s*\}`, `\.catchError\(\(_\)\s*=>\s*null\)` |
| Elixir | `rescue\s+_\s+in\s+\w+\s*->\s*nil`, `try\s+do.*rescue\s+_\s*->\s*:ok\s+end` |
| Shell | `\w+\s+\|\|\s*true`, `\w+\s+2>/dev/null\s*\|\|\s*:` |

Report as **medium** with the line above and below for context.

## Tier 6 — CI gate completeness (MEDIUM)

Walk the CI workflows and answer:

- Does the test job run on **every** push to main and PRs targeting main? (no overly broad `paths-ignore`, no `branches: [some-other-branch]`, no `if:` gating that skips it on common paths)
- Does the lint/typecheck job exist and is it required (no `continue-on-error: true`)?
- Is there a coverage threshold and is it > 0 — and does it actually fail the build, not just emit a warning?
- Are pre-commit hooks (if present) also run in CI? (Searches `.pre-commit-config.yaml`, `lefthook.yml`, husky config and checks for a `pre-commit run --all-files` (or equivalent) step in CI.)
- Is there a job that runs the full test suite, not just changed files?
- For monorepos with `paths-ignore`: is **spec/feature/requirements** content protected? A doc-only `paths-ignore` is fine; one that also skips `Requirements/**` or `features/**` will silently land BDD changes with no validation.

For each gap, a single MEDIUM finding citing the workflow file:line and the missing piece.

## Tier 7 — Cite-the-line audit on recent commits (INFO)

Walks `git log` for the current branch since divergence from `main` (or last 14 days, whichever is shorter):

```bash
git log --no-merges --pretty=format:'%H%x09%s%x09%b%x1e' \
  $(git merge-base HEAD origin/main 2>/dev/null || echo HEAD~30)..HEAD
```

For each commit, scan the message for done-language without citations:

- Phrases: `done`, `complete`, `completed`, `implemented`, `wired`, `ships`, `ready`, `fixed`, `resolved`
- Citation marker: any `path/to/file.ext:NNN` reference, OR a `<file>#L<n>` URL, OR a fenced code block citing the file path, OR a `Closes #NNN` / `Fixes #NNN` referencing an issue with linked code, OR a function/test name that grep finds in the diff (e.g. `test_foo_bar` mentioned in the message and present in the diff).

For each commit message that uses done-language with **zero** citations or issue links, emit an INFO finding citing the commit SHA and the offending sentence.

This tier is INFO not HIGH because commit messages are recoverable evidence — the worst case is a sloppy log, not broken code. Projects that want to enforce it can promote it to HIGH in `.honesty-audit.toml`:

```toml
[tier_overrides]
"cite-the-line" = "high"
```

## Optional — repo-local rubric

If the repo contains any of the following at root, read it and surface its honesty-related rules in the report header so reviewers can cross-reference:

- `HONESTY.md`
- `CONTRIBUTING.md` (look for a section heading containing "honesty", "test quality", "no-stub", or "cite")
- `CLAUDE.md` (look for the same heading patterns — many AI-assisted projects encode honesty rules here)

The skill **does not require** any of these files. If none exist, run with the built-in tier definitions only.

## Suppression conventions (recap)

1. **Inline**: `honesty:ignore <reason>` on the matched line or above. Reason mandatory.
2. **Repo-wide**: `.honesty-audit-ignore` at root. Format: `<category>:<glob-or-id>   reason: <text>`.
3. **Global regex**: a line `global:^<regex>$   reason: <text>` skips matching lines from any source file.
4. Empty reasons are themselves Tier-2 findings.

## Report template

Write `docs/honesty-audit/REPORT.md` with this exact structure (so the diff between runs is meaningful):

```markdown
# Honesty Audit — {YYYY-MM-DD HH:MM} — branch `{branch}`

Languages detected: {list}.
Workflows scanned: {list}.
Complementary in-repo tooling: {discovered scripts and what they cover}.
Repo-local rubric: {path or "none"}.

## Verdict

**{PASS|FAIL}** — critical: {N} | high: {N} | medium: {N} | info: {N} | suppressed: {N}

## Critical findings
{For each: tier badge, category, file:line, the matched line verbatim, suggested action, suppression hint.}

## High findings
{Same structure.}

## Medium findings
{Grouped by category, full file:line list inline up to 20 per category, then a tail-link to the JSON.}

## Info — cite-the-line gaps in recent commits
{Commit SHA, offending sentence, suggestion: "Add `path/to/file.ext:NNN` proving the claim, or rephrase as in-progress."}

## Suppressions applied
{Findings that matched a `.honesty-audit-ignore` rule or inline marker, with the reason.}

## What this audit does NOT cover
(Verbatim from the "Out of scope" table.)

## How to run in CI
(Verbatim copy of the CI snippet.)

## Calibration notes from this run
(Any false-positive classes worth noting for future tuning, plus the suggested `.honesty-audit-ignore` for them.)
```

## CI integration snippet

```yaml
- name: Honesty audit
  run: |
    docs/honesty-audit/scripts/run-honesty-audit.sh
    # exit 1 if findings.json contains any critical or high tier
    jq -e '[.findings[] | select(.tier=="critical" or .tier=="high") |
            select((.suppressed // false) | not)] | length == 0' \
       docs/honesty-audit/findings.json
```

The first time the skill runs, write `docs/honesty-audit/scripts/run-honesty-audit.sh` containing the exact `rg` invocations from Tiers 1–6 plus a JSON aggregator (so CI can run the scan without invoking Claude). Keep the script and this skill in lockstep — the skill's report output and the script's stdout should be byte-equivalent for the same repo state.

## Workflow

1. **Detect** active languages (Step 0a). Build the path classifier (0b). **Discover** existing in-repo tooling (0c) and decide which tiers to defer.
2. **Scan Tiers 1–6** in order. Stream findings into an in-memory list with `{tier, category, file, line, match, suggested_action}`.
3. **Apply suppressions** from `.honesty-audit-ignore` and inline markers. Track count, do not drop them silently.
4. **Run Tier 7** (commit cite-the-line scan) on the current branch.
5. **Write artefacts** — `REPORT.md` and `findings.json` under `docs/honesty-audit/`.
6. **First run only** — also write `docs/honesty-audit/scripts/run-honesty-audit.sh`, `empty-test-bodies.sh`, and `hollow-bodies.sh` so CI can run the same checks without Claude.
7. **Print exit summary** — counts by tier, PASS/FAIL verdict, paths to artefacts. Recommend `/deep-review` only if Tier-4 review-tier findings exceed 20 (signal that mechanical scan is hitting its limit and a semantic review is warranted).
8. **Do not** offer to fix findings unless the user asks. Report and stop.

## Why not delegate to an agent

Every check in this skill is a regex over a known file set. An agent would add latency, non-determinism (different runs surface different findings), and context cost — none of which a tool meant to run on every push can absorb. The whole skill is designed to **become** a CI script the moment the patterns settle.

If the user asks "why is this finding really here?" for a specific entry, that's the moment to spawn an agent (similar pattern to `/coverage-audit` delegating gap investigation to `coverage-investigator`). Until then, stay inline and stay fast.

## Calibration & next steps after the first run

Expect the first run on any repo to surface:

- **Some legitimate-looking matches that need suppression** — add to `.honesty-audit-ignore` with a reason. The first PR after running this skill is usually "add `.honesty-audit-ignore` with N entries documenting known trade-offs." That PR is the *point* of the skill — making the trade-offs explicit.
- **Some patterns that produce too many false positives in this repo's idioms** — note them and tune. Common false-positive sources observed across projects:
  - `\bfit\(` matching xterm.js `FitAddon.fit()`, statistical `model.fit()`, animation `fit-content` (mitigated by scoping T3.2 to test files only)
  - `--no-gpg-sign` in test fixtures where CI sandboxes have no GPG key
  - `unimplemented!()` / `NotImplementedError` in abstract base classes or trait defaults
  - `catch { /* user cancelled */ }` for genuine fire-and-forget UI affordances
- **Tier 4.2 (hollow bodies) and Tier 2.3 (mock tautologies) are the heuristic-heavy ones**; expect manual triage on first run, falling to near-zero once the suppressions stabilise.
- **On a healthy repo with active dev**, expect roughly 1 critical / 2 high / 4 medium per ~15kloc of mixed-language code on the first run, with most matches already named in inline comments. The audit's value in that state is making the trade-offs explicit and trackable, not finding hidden cheats.

Once the repo is clean and `.honesty-audit-ignore` stabilises, wire `run-honesty-audit.sh` into pre-push and CI. That's the destination state.
