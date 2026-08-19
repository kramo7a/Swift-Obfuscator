import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Optional-binding parameter scopes

@Test func explicitIfOptionalBindingShadowEndsBeforeElse() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("IfOptionalShadow.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-if-optional-shadow",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value],
        occurrences: [
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(entry.replacements.count == 3)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Int?)"))
    #expect(patched.contains("if let value = \(entry.newName)"))
    #expect(patched.contains("return value\n    } else"))
    #expect(patched.contains("return \(entry.newName) ?? 0"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}
@Test func shorthandIfOptionalBindingRenamesWithVisibleParameter() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("IfOptionalShorthand.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-if-optional-shorthand-shadow",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value],
        occurrences: [
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(entry.replacements.count == 4)
    #expect(plan.parameterSyntaxFacts.parametersWithCoordinatedShorthandBindings == 1)
    #expect(plan.parameterSyntaxFacts.coordinatedShorthandBindingDeclarations == 1)
    #expect(plan.parameterSyntaxFacts.coordinatedShorthandBindingReferenceTokens == 1)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Int?)"))
    #expect(patched.contains("if let \(entry.newName) { return \(entry.newName) }"))
    #expect(patched.contains("return \(entry.newName) ?? 0"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func shorthandIfOptionalBindingWithNestedSameNameFailsClosed() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("NestedIfOptionalShorthand.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-nested-if-optional-shorthand",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value],
        occurrences: [
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    #expect(!plan.entries.contains { $0.usr == value.usr })
    #expect(plan.parameterSyntaxFacts.parametersWithCoordinatedShorthandBindings == 0)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 1)
    #expect(
        plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds == [
            "ifOptionalBindingCondition": 1
        ])
    #expect(plan.denied.contains { $0.usr == value.usr })
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func shorthandIfInsideExplicitShadowDoesNotBindOuterParameter() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("NestedExplicitIfOptional.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-shorthand-inside-explicit-shadow",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value],
        occurrences: [
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(entry.replacements.count == 3)
    #expect(plan.parameterSyntaxFacts.parametersWithCoordinatedShorthandBindings == 0)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Int??)"))
    #expect(patched.contains("if let value = \(entry.newName)"))
    #expect(patched.contains("if let value { return value }"))
    #expect(patched.contains("return (\(entry.newName) ?? nil) ?? 0"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func finalExplicitGuardOptionalBindingShadowsOnlyAfterGuard() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("GuardOptionalShadow.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-guard-optional-shadow",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value],
        occurrences: [
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(entry.replacements.count == 4)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Int?)"))
    #expect(patched.contains("guard \(entry.newName) != nil, let value = \(entry.newName)"))
    #expect(patched.contains("return \(entry.newName) ?? 0"))
    #expect(patched.contains("return value\n}"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func nonfinalExplicitGuardOptionalBindingUsesDisjointShadowScopes() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("GuardOptionalNonfinal.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-guard-optional-nonfinal",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value],
        occurrences: [
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(entry.replacements.count == 2)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Int?)"))
    #expect(patched.contains("guard let value = \(entry.newName), value > 0"))
    #expect(patched.contains("return value\n}"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func shorthandGuardOptionalBindingRenamesWithVisibleParameter() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("GuardOptionalShorthand.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-guard-optional-shorthand",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value],
        occurrences: [
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(entry.replacements.count == 5)
    #expect(plan.parameterSyntaxFacts.parametersWithCoordinatedShorthandBindings == 1)
    #expect(plan.parameterSyntaxFacts.coordinatedShorthandBindingDeclarations == 1)
    #expect(plan.parameterSyntaxFacts.coordinatedShorthandBindingReferenceTokens == 2)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Int?)"))
    #expect(
        patched.contains(
            "guard let \(entry.newName), \(entry.newName) > 0 else { return \(entry.newName) ?? 0 }"
        ))
    #expect(patched.contains("return \(entry.newName)\n}"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func shorthandGuardOptionalBindingWithNestedSameNameFailsClosed() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("NestedGuardOptionalShorthand.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-nested-guard-optional-shorthand",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value],
        occurrences: [
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    #expect(!plan.entries.contains { $0.usr == value.usr })
    #expect(plan.parameterSyntaxFacts.parametersWithCoordinatedShorthandBindings == 0)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 1)
    #expect(
        plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds == [
            "guardOptionalBindingCondition": 1
        ])
    #expect(plan.denied.contains { $0.usr == value.usr })
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func shorthandGuardInsideExplicitShadowDoesNotBindOuterParameter() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("NestedExplicitGuardOptional.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-shorthand-guard-inside-explicit-shadow",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value],
        occurrences: [
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(entry.replacements.count == 3)
    #expect(plan.parameterSyntaxFacts.parametersWithCoordinatedShorthandBindings == 0)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Int??)"))
    #expect(patched.contains("if let value = \(entry.newName)"))
    #expect(patched.contains("guard let value else { return 0 }"))
    #expect(patched.contains("return (\(entry.newName) ?? nil) ?? 0"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}
