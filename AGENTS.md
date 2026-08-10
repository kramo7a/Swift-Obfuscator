# Repository Guidelines

## Project

This is a macOS-only SwiftPM tool named `SwiftObfuscator`. The executable product is `swift-obfuscator`; reusable pipeline code lives in the `ObfuscatorCore` library target.

The tool builds a target Xcode project with `xcodebuild COMPILER_INDEX_STORE_ENABLE=YES`, reads the resulting index store through IndexStoreDB, plans conservative Swift identifier renames, and patches source files by byte range. It requires Xcode and the active toolchain's `xcrun`/`libIndexStore.dylib`.

## Commands

Use these from the repository root:

```sh
swift build
swift test
swift test --filter nameGeneratorProducesStableNames
swift run swift-obfuscator --help
```

Tests use Swift Testing (`@Test` and `#expect`), not XCTest. Full test runs can be slow because integration coverage builds `Fixtures/TinySwiftProject` with `xcodebuild`.

## Layout

- `Sources/SwiftObfuscator/main.swift`: CLI parsing, run summary JSON, logging, and command orchestration.
- `Sources/ObfuscatorCore/ProjectBuilder.swift`: `xcodebuild` invocation and index-store location.
- `Sources/ObfuscatorCore/IndexReader.swift`: IndexStoreDB snapshot extraction and source file discovery.
- `Sources/ObfuscatorCore/IndexedSemanticFacts.swift`: compiler-index-derived ownership, extension, protocol, and runtime-dispatch facts.
- `Sources/ObfuscatorCore/SafetyAnalyzer.swift`: deny-by-default rename eligibility checks.
- `Sources/ObfuscatorCore/RenamePlanner.swift`: stable name assignment and replacement planning.
- `Sources/ObfuscatorCore/SourcePatcher.swift`: validation and source rewriting/copying.
- `Fixtures/TinySwiftProject`: small integration fixture.
- `Tests/ObfuscatorCoreTests`: Swift Testing suite.

## CLI Behavior

Subcommands are `dump`, `dry-run`, and `apply`; `dry-run` is the default. Important flags include:

- `--summary-json` / `--json` for machine-readable output.
- `--verify-build` to rebuild after in-place apply.
- `--source` / `--source-root` to limit selected obfuscation roots.
- `--obfuscated-code-output` to mirror patched files into a separate output tree.
- Extra `xcodebuild` arguments go after `--` or via repeated `--xcodebuild-arg`.

By default, generated artifacts are written under `<project>/.obfuscator`, including logs, reports, DerivedData, IndexDatabase, `mapping.json`, and `run-summary.json`.

## Safety Invariants

Keep rename logic conservative. `SafetyAnalyzer` intentionally denies unsupported kinds, system or implicit occurrences, occurrences outside selected roots, unsafe relations, non-plain/backticked identifiers, and externally visible/runtime-reflected declarations such as `public`, `open`, `@objc`, `@IB*`, `dynamic`, and `override`.

Do not re-enable `parameter` renames without a regression test proving external argument labels stay valid. A known failure mode is a verify-build error like:

```text
incorrect argument label in call (have 'name:', expected '_oe:')
```

Replacement application must remain byte-offset based against the exact files that were indexed. If sources change between indexing and patching, validation should fail rather than guessing.



Safety decisions must stay project-agnostic. Do not add hardcoded allow/deny lists of concrete SDK, framework, or target-project type names such as `String`, `Array`, `UXColor`, or app-specific symbols. If a rule needs to distinguish local code from external code, derive that from IndexStore/source semantics for the current target, such as local declarations, symbol providers, relations, roles, or selected source roots.

Never reconstruct semantic declaration context by scanning Swift braces or parsing declaration headers in `SafetyAnalyzer`. Ownership, protocol requirements, extension targets, override/base relationships, and runtime-dispatch ancestry must come from IndexStoreDB symbol kinds, properties, roles, relations, USR provenance, and declarations inside the selected source roots. Source text is limited to validating exact identifier tokens and byte ranges, plus narrowly documented lexical facts that IndexStoreDB does not expose; every such fallback requires a focused regression test.

## Working Conventions

- Prefer existing pipeline stages over adding broad abstractions.
- Keep CLI concerns in `Sources/SwiftObfuscator/main.swift`; keep semantic planning and patching in `ObfuscatorCore`.
- Preserve stable mappings by USR through `MappingStore`.
- Avoid committing generated `.obfuscator`, DerivedData, IndexDatabase, or copied obfuscated output.
- When validating real project changes, run a dry-run first; use `apply --verify-build` only when source mutation is intended.
