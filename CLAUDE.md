# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS-only SwiftPM tool (`swift-obfuscator`) that obfuscates Swift identifiers in Xcode projects. It builds the target project with `xcodebuild COMPILER_INDEX_STORE_ENABLE=YES`, reads the resulting index store via IndexStoreDB, plans semantically-safe renames, and patches source files byte-by-byte. Requires Xcode (uses `xcrun`, `libIndexStore.dylib` from the active toolchain).

## Commands

```sh
swift build                                # build
swift test                                 # run all tests
swift test --filter nameGeneratorProducesStableNames   # run one test
swift run swift-obfuscator --help          # CLI usage
```

Tests use Swift Testing (`@Test` / `#expect`), not XCTest. Integration tests build `Fixtures/TinySwiftProject` with xcodebuild, so the full test run is slow and needs Xcode.

CLI subcommands: `dump` (print index), `dry-run` (default; plan only), `apply` (patch sources in-place, or copy to `--obfuscated-code-output`). Useful flags: `--summary-json` for machine-readable output, `--verify-build` to rebuild after apply. Artifacts (logs, reports, DerivedData, IndexDatabase, mapping.json) go to `<project>/.obfuscator` by default.

## Architecture

Two targets: `SwiftObfuscator` (executable; all CLI concerns live in the single `main.swift` — argument parsing, `RunSummary` JSON, `CLIOutput` logging) and `ObfuscatorCore` (library with the pipeline).

Pipeline stages, in execution order (each is one file in `Sources/ObfuscatorCore/`):

1. **ProjectBuilder** — infers the xcodebuild container/scheme and builds with the index store enabled; the index lands in `DerivedData/Index.noindex/DataStore`.
2. **IndexReader** — opens the store with IndexStoreDB, walks Swift files under the source roots (`SourceFileFinder`), and collects symbols/occurrences into an **IndexSnapshot** (plain Codable records grouped by USR). `SourcePathNormalizer` handles symlink/`/tmp` vs `/private/tmp` path mismatches between the index and the filesystem.
3. **SafetyAnalyzer** — deny-by-default per-USR checks: only allowlisted symbol kinds; rejects system/implicit occurrences, occurrences outside the selected roots, override/baseOf/specialization relations, backticked or non-plain identifiers, and declaration lines containing `public`, `open`, `@objc`, `@IB*`, `dynamic`, or `override` (textual line scan). Every denial carries human-readable reasons that surface in the dry-run report.
4. **RenamePlanner** — for allowed USRs, assigns names from **NameGenerator** (`_oa`, `_ob`, … base-52 counter), reuses prior names from **MappingStore** (`mapping.json`, keyed by USR, so re-runs are stable), verifies each occurrence's source token matches via **SourceFile** (byte-offset tokenizer), and drops whole entries on byte-offset conflicts.
5. **SourcePatcher** — validates that every replacement's byte range still contains the expected old name before writing, then applies replacements back-to-front per file. Two modes: in-place `apply` or `writePatchedCopies` mirroring the source tree under an output root.

Cross-cutting: **CommandRunner** executes subprocesses and tees stdout/stderr to per-run log files; **ReportRenderer** formats the index dump and dry-run reports.

Key invariant: replacements are byte-offset based against the exact file contents that were indexed — anything that edits sources between the index build and patching will fail patch validation (by design).

`Fixtures/TinySwiftProject` is the integration-test target; `obfuscated/` holds output from manual runs against real projects and is not part of the package.
