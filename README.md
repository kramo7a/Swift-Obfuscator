# SwiftObfuscator

SwiftObfuscator is a macOS command-line tool that conservatively renames Swift
identifiers in Xcode projects, workspaces, and Swift packages. It builds the
target with compiler indexing enabled, reads semantic relationships through
IndexStoreDB, uses SwiftSyntax for syntax-only details, and patches exact UTF-8
byte ranges in the indexed source files.

The executable product is `swift-obfuscator`. The reusable planning and
patching pipeline is available as the `ObfuscatorCore` SwiftPM library.

> [!IMPORTANT]
> Keep the target project under version control. Start with `dry-run`, inspect
> every planned and denied rename, and use `apply --verify-build` only when you
> are ready to review source changes. A successful build does not prove that
> application-specific reflection, serialization, persistence, or string-based
> lookup contracts still behave correctly.

> [!CAUTION]
> The directory passed to `--obfuscated-code-output` is treated as generated,
> disposable output and is recreated during command setup, including for a
> dry-run. Never point it at a directory containing files you need to keep.

## How it works

1. Runs `xcodebuild` with `COMPILER_INDEX_STORE_ENABLE=YES`.
2. Imports the compiler index with IndexStoreDB.
3. Builds semantic rename components for declarations, references, parameters,
   enum cases, protocol witnesses, and override relationships.
4. Denies a component when its complete spelling contract cannot be proven.
5. Validates every indexed token and applies replacements by UTF-8 byte offset.

Persisted mappings are keyed by compiler USR, so a successful apply can reuse
the same obfuscated names in later runs.

## Requirements

- macOS 13 or later.
- Swift 6 or later to build this package.
- Xcode and its command-line tools, including `xcrun`, `xcodebuild`, and the
  active toolchain's `libIndexStore.dylib`.
- A target project that builds with `xcodebuild` and exposes a discoverable
  scheme.

Check the active toolchain before troubleshooting an index failure:

```sh
xcode-select -p
xcrun xcodebuild -version
xcrun --find swift
```

## Build

```sh
git clone https://github.com/kramo7a/Swift-Obfuscator.git
cd Swift-Obfuscator
swift build -c release
.build/release/swift-obfuscator --help
```

For local development, `swift run swift-obfuscator ...` can be used instead of
the release binary.

## Quick start

Run the planner without changing project sources:

```sh
.build/release/swift-obfuscator dry-run \
  --project /path/to/MyApp \
  --scheme MyApp \
  --destination 'generic/platform=iOS'
```

The default destination is `platform=macOS`; pass an appropriate destination
for iOS or another Apple platform. If `--scheme` is omitted, the first scheme
reported by `xcodebuild -list -json` is used.

Inspect the generated report and machine-readable summary:

```sh
less /path/to/MyApp/.obfuscator/dry-run-report.txt
less /path/to/MyApp/.obfuscator/run-summary.json
```

When the plan is acceptable, apply it in place and rebuild the patched project:

```sh
.build/release/swift-obfuscator apply \
  --project /path/to/MyApp \
  --scheme MyApp \
  --destination 'generic/platform=iOS' \
  --verify-build
```

Review both the Git diff and the application's runtime behavior after applying.

## Commands

| Command | Behavior |
| --- | --- |
| `dump` | Builds/imports the index and writes a complete symbol, USR, occurrence, and relation dump. |
| `dry-run` | Plans and reports renames without patching selected project sources. This is also the default when no subcommand is given. |
| `apply` | Applies the plan in place or writes source-only copies when `--obfuscated-code-output` is set. |

Run `swift-obfuscator --help` for the complete option list.

## Common workflows

### Limit the obfuscation scope

`--source-root` accepts a Swift file or directory under the project root and is
repeatable. `--source` is an alias.

```sh
.build/release/swift-obfuscator dry-run \
  --project /path/to/MyApp \
  --scheme MyApp \
  --source-root Sources/FeatureA \
  --source-root Sources/FeatureB
```

The roots select declarations for obfuscation. References and semantic
relationships still have to be completely resolvable for a rename to proceed.

### Write source-only copies

To preserve the original project sources, use a dedicated generated directory:

```sh
.build/release/swift-obfuscator apply \
  --project /path/to/MyApp \
  --scheme MyApp \
  --obfuscated-code-output /.ObfuscatedSources
```

This mirrors selected Swift files, including unchanged ones, under the output
root. It does not copy project files, resources, or dependencies, so the result
is not a standalone buildable project. With external output, `--verify-build`
only confirms the initial indexed build; it does not build the copied sources.

### Pass additional build settings

Use repeatable `--xcodebuild-arg` options or put arguments after `--`. They are
inserted before the final `build` action.

```sh
.build/release/swift-obfuscator dry-run \
  --project /path/to/MyApp \
  --scheme MyApp \
  --configuration Release \
  --destination 'generic/platform=iOS' \
  --xcodebuild-arg CODE_SIGNING_ALLOWED=NO \
  -- -sdk iphoneos
```

### Reuse an existing index

After a successful indexed run, `--reuse-index` skips the build and import when
all discovered Swift sources still match the saved SHA-256 manifest.

```sh
.build/release/swift-obfuscator dry-run \
  --project /path/to/MyApp \
  --scheme MyApp \
  --reuse-index
```

Only reuse an index with the same scheme, configuration, destination, build
arguments, and active toolchain. Source-hash validation alone does not prove
that those build inputs match the cached index.

### Consume JSON in automation

`--summary-json` and `--json` print only the run summary JSON to standard output.
Human-readable diagnostics are still saved in the run log.

```sh
.build/release/swift-obfuscator dry-run \
  --project /path/to/MyApp \
  --scheme MyApp \
  --json > obfuscator-summary.json
```

Use `--compact-report` to retain counters and planned renames while omitting
per-symbol and per-occurrence denial detail from `dry-run-report.txt`.

## Generated artifacts

Artifacts default to `<project>/.obfuscator` and can be relocated with
`--output`.

| Artifact | Purpose |
| --- | --- |
| `dry-run-report.txt` | Planned renames, exact replacement locations, denials, and conflicts. |
| `run-summary.json` | Command status, phase, counters, build information, and artifact paths. |
| `mapping.json` | Stable USR-to-name mapping, saved after an apply with replacements. |
| `index-source-manifest.json` | Indexed source paths and SHA-256 hashes used by `--reuse-index`. |
| `IndexDatabase/` | Imported IndexStoreDB database. |
| `IndexDatabase.snapshot.plist` | Cached normalized semantic snapshot. |
| `IndexDatabase.rename-plan.plist` | Cached rename plan for matching tool and source inputs. |
| `DerivedData/` | Indexed `xcodebuild` output. |
| `index-dump.txt` | Full index dump produced by `dump` or `--dump`. |
| `coverage-report.json` | Optional comparison against an immutable USR coverage cohort. |
| `logs/<run-id>/` | CLI, `xcodebuild`, and index-processing logs. |

Generated artifacts, DerivedData, and copied obfuscated output should not be
committed.

## Safety model

The base candidate set includes source-authored types, type aliases, functions,
methods, properties, and variables. Parameters and enum cases are considered
only through stricter coordinated components. The planner fails closed when it
finds unsupported kinds, incomplete occurrences, unsafe semantic relations,
runtime-sensitive declarations, unresolved syntax anchors, source outside the
project, or tokens that no longer match the indexed bytes.

Protocol requirements and witnesses, override graphs, parameter declaration and
call-site roles, associated-value labels, serialization keys, and enum-case
components are renamed atomically when supported. If any required member cannot
be proven safe, the component is denied and its reasons are recorded in the
dry-run report.

This remains a source identifier obfuscator, not encryption or binary hardening.
Treat reflection, custom Codable implementations, persistence and network wire
formats, Interface Builder resources, dynamic lookup, and other string-based
contracts as application-specific test requirements.

## Coverage cohorts

Coverage cohorts provide a stable USR denominator for comparing planner changes
across revisions. Create a baseline with `--create-coverage-cohort`, a stable
`--coverage-cohort-id`, and the exact expected denominator. Later runs use
`--coverage-cohort` and write `coverage-report.json`. Baseline creation refuses
to overwrite an existing cohort or silently accept denominator drift.

## IPA and Mach-O analysis helper

`analyze_ipa_macho.sh` is a separate post-build inventory tool for `.ipa`,
`.app`, and `.xcarchive` inputs. It extracts Mach-O metadata, symbols, printable
strings, and configurable suspicious-pattern reports; it does not modify the
application or provide an automated security verdict.

```sh
cp analyze_ipa_macho.config.example analyze_ipa_macho.config
bash analyze_ipa_macho.sh \
  --input /path/to/MyApp.ipa \
  --output /path/to/dedicated-analysis-output \
  --config analyze_ipa_macho.config
```

Use a dedicated output directory. Run `bash analyze_ipa_macho.sh --help` for all
options and configuration precedence.

## Development

```sh
swift build
swift test
swift test --filter obfuscatedNameGeneratorProducesStableNames
swift run swift-obfuscator --help
bash -n analyze_ipa_macho.sh
```

Tests use Swift Testing (`@Test` and `#expect`). The full suite includes an
integration build of `Fixtures/TinySwiftProject`, so it can take longer than a
focused unit test.

Key paths:

```text
Sources/SwiftObfuscator/       CLI parsing, orchestration, logging, JSON summary
Sources/ObfuscatorCore/        Index reading, safety analysis, planning, patching
Tests/ObfuscatorCoreTests/     Unit and integration coverage
Fixtures/TinySwiftProject/     Minimal xcodebuild/index integration fixture
analyze_ipa_macho.sh           Optional IPA and Mach-O inventory helper
```

## License

This repository does not currently include a license file.
