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
- `Sources/ObfuscatorCore/ParameterRenameComponent.swift`: indexed callable/parameter ownership, ordering, external-label, local-binding, and call-anchor facts.
- `Sources/ObfuscatorCore/ParameterSyntaxFacts.swift`: SwiftParser-backed exact parameter declaration roles and byte ranges for facts that IndexStoreDB does not expose.
- `Sources/ObfuscatorCore/ParameterCallSiteSyntaxFacts.swift`: IndexStore-call-anchored SwiftParser ranges for argument labels and call syntax shapes.
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

Parameter planning must keep the external argument label and local binding as
separate roles even when they share one declaration token. Build callable
components from IndexStoreDB `childOf` ownership, callable symbol names, and
occurrence roles. Do not infer parameter ownership or signature boundaries by
scanning source braces or declaration text.

When IndexStoreDB cannot distinguish nested local functions, accessor bindings,
or anonymous enum payloads, use the pinned SwiftParser/SwiftSyntax syntax tree
and match it back to the exact indexed declaration anchor. Do not replace this
with ordering assumptions such as treating the first N parameters as belonging
to the outer callable. A parameter USR whose source role is `_` or an anonymous
payload type is not a renameable local binding even though it remains visible in
coverage-denominator diagnostics.

IndexStoreDB parameter declarations and ownership are semantic anchors, but the
index does not reliably publish lexical references to a parameter binding in
the callable body. For local-binding replacement ranges, walk only the exact
pinned SwiftParser owner body matched to the indexed declaration, and classify
compiler syntax roles such as declaration references and closure captures.
Never approximate these references with raw string matching. Any same-spelled
explicit shadow binding, or implicit Swift binding such as catch `error`, setter
`newValue`, or observer `oldValue`, must fail closed for the whole parameter
USR. Generated parameter and other value-binding identifiers must use
lowerCamelCase spelling. Apply Swift's declaration-kind label semantics before
classifying a parameter: operator-function parameter names and the single name
in `subscript(index:)` are local bindings with no external label, while a
two-name `subscript(label local:)` has an explicit external label. Derive these
roles from the compiler syntax node and its token kind, never from callable
spelling heuristics. Likewise, default-argument and variadic traits must come
from the matched `FunctionParameterSyntax.defaultValue` and `.ellipsis` nodes;
they are inputs to argument-to-ordinal matching, not facts inferred from
callable names or call-site arity.

For external argument labels, IndexStoreDB call occurrences provide callable
identity and the exact semantic call anchor. SwiftParser may map that anchor to
function, subscript, or user-defined attribute syntax and expose label byte
ranges, but it must never infer a call
target from source spelling, overload order, or a text search. Unmatched or
multiply matched anchors fail closed and remain individually reproducible in
the machine-readable report. Once a compiler syntax token is anchored, its raw
UTF-8 range is authoritative for Unicode spelling; do not replace it with an
ASCII-only text scanner. Argument-to-parameter matching must enumerate only
monotonic assignments supported by declaration labels, defaults, variadics,
and trailing-closure syntax. Accept a call only when that deliberately relaxed
model has one assignment; zero or multiple assignments fail closed with the
exact indexed call anchor in the machine-readable report.

Replacement application must remain byte-offset based against the exact files that were indexed. If sources change between indexing and patching, validation should fail rather than guessing.



Safety decisions must stay project-agnostic. Do not add hardcoded allow/deny lists of concrete SDK, framework, or target-project type names such as `String`, `Array`, `UXColor`, or app-specific symbols. If a rule needs to distinguish local code from external code, derive that from IndexStore/source semantics for the current target, such as local declarations, symbol providers, relations, roles, or selected source roots.

Never reconstruct semantic declaration context by scanning Swift braces or parsing declaration headers in `SafetyAnalyzer`. Ownership, protocol requirements, extension targets, override/base relationships, and runtime-dispatch ancestry must come from IndexStoreDB symbol kinds, properties, roles, relations, USR provenance, and declarations inside the selected source roots. Source text is limited to validating exact identifier tokens and byte ranges, plus narrowly documented lexical facts that IndexStoreDB does not expose; every such fallback requires a focused regression test.

## Working Conventions

- Prefer existing pipeline stages over adding broad abstractions.
- Keep CLI concerns in `Sources/SwiftObfuscator/main.swift`; keep semantic planning and patching in `ObfuscatorCore`.
- Preserve stable mappings by USR through `MappingStore`.
- Avoid committing generated `.obfuscator`, DerivedData, IndexDatabase, or copied obfuscated output.
- When validating real project changes, run a dry-run first; use `apply --verify-build` only when source mutation is intended.
