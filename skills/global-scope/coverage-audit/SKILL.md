---
name: coverage-audit
description: "Measure test coverage, filter structurally untestable code, compute adjusted coverage, and rank high-impact gaps. Supports Rust, Python, TypeScript/JS, Swift, Java, Kotlin, Go, Ruby, C#, C/C++, PHP. For deep investigation of a specific gap, delegates to an isolated agent."
---

# Coverage Audit

Measure, interpret, and prioritise test coverage gaps. Auto-detects toolchain. Single-shot measurement runs inline; deep gap investigation is offloaded to an agent so the raw file contents don't fill the main conversation.

## Step 1 — Detect toolchain and run coverage

### Rust

```bash
# Install if needed
cargo install cargo-llvm-cov

cargo llvm-cov --workspace --lcov --output-path lcov.info
cargo llvm-cov report --workspace
```

Extract the TOTAL line for: line %, function %, branch %.

### Python

```bash
# pytest-cov
pytest --cov=src --cov-report=term-missing --cov-report=lcov:lcov.info

# or coverage.py directly
coverage run -m pytest
coverage report --show-missing
coverage lcov -o lcov.info
```

Key metric: line coverage % from the TOTAL row.

### TypeScript / JavaScript

```bash
# Jest
npm test -- --coverage --coverageReporters=text lcov

# Vitest
npm run test:run -- --coverage

# nyc / c8 (non-Jest)
npx c8 --reporter=text --reporter=lcov npm test
```

Key metric: lines % and branches % from the summary table.

### Swift / Xcode

```bash
# Build and test with coverage enabled
xcodebuild -project <ProjectName>.xcodeproj \
           -scheme <SchemeName> \
           -enableCodeCoverage YES \
           -resultBundlePath TestResults.xcresult \
           test

# Extract coverage summary (requires xcrun)
xcrun xccov view --report TestResults.xcresult
```

Or use `slather` if configured: `bundle exec slather coverage`.
Key metric: overall line coverage % from the report.

### Java (Maven + JaCoCo)

```bash
mvn test jacoco:report
# Report at: target/site/jacoco/index.html
# Summary: target/site/jacoco/jacoco.csv
awk -F',' 'NR>1 {miss+=$5+$7; covered+=$6+$8} END {printf "Line: %.1f%%\n", covered/(covered+miss)*100}' \
  target/site/jacoco/jacoco.csv
```

### Kotlin / Java (Gradle + JaCoCo or Kover)

```bash
# JaCoCo
./gradlew test jacocoTestReport
# Report at: build/reports/jacoco/test/html/index.html

# Kover (Kotlin-native, preferred for Kotlin projects)
./gradlew koverHtmlReport koverXmlReport
# Summary printed to console with koverReport task
./gradlew koverReport
```

### Go

```bash
go test -coverprofile=coverage.out ./...
go tool cover -func=coverage.out | tail -1    # TOTAL line
go tool cover -html=coverage.out -o coverage.html   # browsable report
```

### Ruby

```bash
# SimpleCov — add to spec_helper.rb / test_helper.rb:
#   require 'simplecov'; SimpleCov.start
bundle exec rspec                               # or: bundle exec rake test
cat coverage/.last_run.json                     # line-coverage summary
```

### C# / .NET

```bash
dotnet test --collect:"XPlat Code Coverage" --results-directory ./coverage
# Output: ./coverage/<guid>/coverage.cobertura.xml
# Summarise with ReportGenerator:
dotnet tool run reportgenerator \
    -reports:./coverage/**/coverage.cobertura.xml \
    -targetdir:./coverage/report \
    -reporttypes:"TextSummary;Html" 2>&1 | grep -E 'Line coverage:|Branch coverage:'
```

### C / C++

```bash
# Configure for coverage (gcc/clang): add -fprofile-arcs -ftest-coverage to compile/link flags
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug \
      -DCMAKE_C_FLAGS='--coverage' -DCMAKE_CXX_FLAGS='--coverage'
cmake --build build
(cd build && ctest)

# gcov (GCC toolchain)
gcovr -r . --print-summary
# or llvm-cov (Clang toolchain)
llvm-cov gcov $(find build -name '*.gcda')
```

### PHP

```bash
# Requires Xdebug or PCOV
XDEBUG_MODE=coverage vendor/bin/phpunit --coverage-text --coverage-clover coverage.xml
```

---

## Step 2 — Report raw numbers

State clearly: language, tool used, line %, branch %, function % (where available).

---

## Step 3 — Apply exclusions for adjusted coverage

Remove structurally untestable code from the denominator. Exclusions by language:

### Rust
| Category | Pattern | Reason |
|---|---|---|
| Unwired BDD stub steps | `steps/*.rs` files at 0% with only `todo!()` bodies | Not a code gap — scenario needs wiring |
| Kubernetes / cloud integration | `kubernetes/`, `k8s/` | Requires live cluster |
| OS-level IPC | `ipc/unix.rs`, `ipc/windows.rs` | Syscall-level, integration only |
| Long-running daemons / services | `*-daemon/`, `*-server/` main entry points | Process startup/shutdown, lifecycle only |

### Python
| Category | Pattern | Reason |
|---|---|---|
| Database migrations | `migrations/`, `alembic/versions/` | Generated, not logic |
| Generated clients | `*_pb2.py`, `*_pb2_grpc.py` | Protobuf generated |
| Config-only modules | `settings.py`, `config.py` with only constants | No logic to test |
| `__init__.py` re-exports | Files that only import/re-export | No executable logic |

### TypeScript / JavaScript
| Category | Pattern | Reason |
|---|---|---|
| Type declaration files | `*.d.ts` | No runtime code |
| Generated API clients | `src/generated/`, `src/api/generated/` | Machine-generated |
| Storybook stories | `*.stories.tsx` | Visual documentation |
| Build config | `vite.config.ts`, `jest.config.ts`, `webpack.config.js` | Infra, not product |
| `index.ts` barrel files | Files that only re-export | No logic |

### Swift
| Category | Pattern | Reason |
|---|---|---|
| Auto-generated files | `*Generated.swift`, `*+CoreDataProperties.swift` | Generated |
| App entry point | `*App.swift` with only `@main` | Untestable bootstrapping |
| SwiftUI preview providers | Files containing only `#Preview` or `PreviewProvider` | UI previews |

### Java / Kotlin
| Category | Pattern | Reason |
|---|---|---|
| Generated code | `build/generated/`, `target/generated-sources/` | Never manually written |
| Database migrations | `db/migration/`, Flyway/Liquibase scripts | SQL, not JVM code |
| DTOs / data classes | Simple data holders with no logic | Usually auto-tested via serialization |
| Android `R.java` | `R.java`, `BuildConfig.java` | Generated by build system |

### Go
| Category | Pattern | Reason |
|---|---|---|
| Generated code | `*_gen.go`, `*.pb.go`, `zz_generated_*.go` | Never manually written |
| `cmd/*/main.go` | Program entry points | Flag parsing + `os.Exit`, usually untestable |
| Vendored deps | `vendor/` | Third-party code |

### Ruby
| Category | Pattern | Reason |
|---|---|---|
| Rails migrations | `db/migrate/` | Schema changes, not logic |
| Initialisers / config | `config/initializers/`, `config/application.rb` | Framework boot |
| Generated schema | `db/schema.rb`, `db/structure.sql` | Regenerated by the framework |

### C# / .NET
| Category | Pattern | Reason |
|---|---|---|
| Generated code | `obj/`, `*.Designer.cs`, `*.g.cs` | Build output |
| EF migrations | `Migrations/*.Designer.cs`, `*ModelSnapshot.cs` | Generated from model |
| Program entry | `Program.cs` when it's just `Host.CreateDefaultBuilder()...Run()` | Framework bootstrap |

### C / C++
| Category | Pattern | Reason |
|---|---|---|
| Generated code | `*.pb.cc` / `*.pb.h`, `moc_*.cpp`, `ui_*.h` | Tooling output |
| Third-party | `third_party/`, `external/`, `vendor/` | Not your code |
| Platform adapters | `*_win32.cpp`, `*_posix.cpp` when only one OS is in CI | Unreachable on this host |

### PHP
| Category | Pattern | Reason |
|---|---|---|
| Framework bootstrap | `public/index.php`, `bootstrap/app.php` | Framework boot |
| Vendored deps | `vendor/` | Third-party |
| Database migrations | `database/migrations/` | Schema, not logic |

Recompute coverage excluding these, and report:
- **Raw coverage**: X% (all code)
- **Adjusted coverage**: Y% (N lines excluded, reason summary)

---

## Step 4 — Rank high-impact gaps

From the remaining testable scope, find files/modules where coverage < 80% AND missed lines > 30.

Sort by missed lines descending. For each, classify effort:

| Effort | Criteria |
|---|---|
| **Low** | Pure functions, data transformations, no I/O |
| **Medium** | Calls external tools (`git`, `gh`, `docker`) — testable with mocks/fixtures |
| **High** | Requires running infrastructure (DB, daemon, device) — skip for unit sprint |

---

## Step 5 — BDD / scenario coverage (if applicable)

If the project has BDD specs, count wired vs total scenarios. Run `/bdd-audit` if ratio < 80%.

---

## Step 6 — Output and recommendation

Report:
1. Adjusted coverage and gap to target (default: **80% line, 70% branch** — adjust to project standard)
2. Top 10 testable files by missed lines
3. Estimated test count to close the gap (rough: 1 test ≈ 8–12 lines covered)

Then recommend:
- Gap > 15 points → `/sprint-plan` with dedicated coverage workstreams
- Gap 5–15 points → single-agent focused effort
- Gap < 5 points → specific file list, targeted additions
- BDD ratio < 80% → `/bdd-audit` first to separate build work from test work

---

## Coverage targets by project type

| Project type | Line % target | Branch % target |
|---|---|---|
| Core library / SDK | 90% | 80% |
| Application backend | 80% | 70% |
| CLI tool | 75% | 65% |
| UI frontend | 70% | 60% |
| Integration / infra | 50% | 40% |

Use these as defaults unless the user has specified different targets.

---

## Deep investigation of a specific gap

When the user asks "why is this file at N% coverage?" or "what would it take to reach target for X?", delegate to the `coverage-investigator` agent. Its job is to read the target file(s), find existing tests, classify each uncovered entry point (pure / injectable / hard-wired / unreachable / integration-only), and return an effort estimate.

Delegate to the **`coverage-investigator`** agent using this harness's subagent mechanism — Claude Code: the `Agent` tool with `subagent_type: "coverage-investigator"`; Pi: the `subagent` tool with `{ agent: "coverage-investigator" }`; otherwise the harness equivalent. If the harness has no subagent mechanism at all, follow the agent's own instructions inline instead of erroring. Pass the target file path(s), the current coverage number, and the project's coverage target as the prompt.

Relay the agent's classification table and recommendation to the user. Do not start writing tests until the user confirms which gaps to tackle.
