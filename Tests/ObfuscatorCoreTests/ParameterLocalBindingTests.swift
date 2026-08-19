import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Parameter local binding scopes

@Test func renamePlannerSeparatesExternalLabelsFromLocalBindings() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Parameters.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let value = testSymbol("usr-value", "value")
    let local = testSymbol("usr-local", "local")
    let shared = testSymbol("usr-shared", "shared")
    let occurrences = [
        testOccurrence(value, path: file.path, line: 1, token: "value", roles: [.definition]),
        testOccurrence(value, path: file.path, line: 2, token: "value", roles: [.reference]),
        testOccurrence(local, path: file.path, line: 1, token: "local", roles: [.definition]),
        testOccurrence(local, path: file.path, line: 2, token: "local", roles: [.reference]),
        testOccurrence(shared, path: file.path, line: 1, token: "shared", roles: [.definition]),
        testOccurrence(shared, path: file.path, line: 2, token: "shared", roles: [.reference]),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value, local, shared],
        occurrences: occurrences
    )
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    let valueEntry = try #require(plan.entries.first { $0.usr == value.usr })
    let localEntry = try #require(plan.entries.first { $0.usr == local.usr })
    let sharedEntry = try #require(plan.entries.first { $0.usr == shared.usr })
    #expect(plan.entries.count == 3)
    #expect(valueEntry.oldName == "value")
    #expect(valueEntry.newName.first?.isLowercase == true)
    #expect(valueEntry.replacements.count == 2)
    #expect(localEntry.oldName == "local")
    #expect(localEntry.replacements.count == 2)
    #expect(sharedEntry.oldName == "shared")
    #expect(sharedEntry.replacements.count == 2)
    #expect(!plan.denied.contains { $0.usr == local.usr })
    #expect(!plan.denied.contains { $0.usr == shared.usr })
    #expect(plan.parameterSyntaxFacts.localBindingOnlyCoverageCandidates == 3)
    #expect(plan.parameterLocalBindingOutcome.candidates == 3)
    #expect(plan.parameterLocalBindingOutcome.renamed == 3)
    #expect(plan.parameterLocalBindingOutcome.denied == 0)
    #expect(plan.parameterLocalBindingOutcome.unclassified == 0)
    #expect(plan.parameterLocalBindingOutcome.denialCategories.isEmpty)
    #expect(plan.parameterLocalBindingOutcome.deniedCandidateUSRs.isEmpty)
    #expect(!valueEntry.replacements.contains { $0.oldName == "_" })

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(
        patched
            == [
                "func calculate(_ \(valueEntry.newName): Int, wire \(localEntry.newName): Int, shared \(sharedEntry.newName): Int) -> Int {",
                "    \(valueEntry.newName) + \(localEntry.newName) + \(sharedEntry.newName)",
                "}",
                "",
            ].joined(separator: "\n"))
}

@Test func renamePlannerAddsCompilerSyntaxParameterReferencesMissingFromIndex() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Handler.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let label = testSymbol("usr-label", "label")
    let message = testSymbol("usr-message", "message")
    let webView = testSymbol("usr-web-view", "webView")
    let shadowedValue = testSymbol("usr-shadowed-value", "value")
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [label, message, webView, shadowedValue],
        occurrences: [
            testOccurrence(label, path: file.path, line: 3, token: "label", roles: [.definition]),
            testOccurrence(message, path: file.path, line: 6, token: "message", roles: [.definition]),
            testOccurrence(
                webView,
                path: file.path,
                line: 9,
                token: "webView",
                roles: [.definition]
            ),
            testOccurrence(
                shadowedValue,
                path: file.path,
                line: 12,
                token: "value",
                roles: [.definition]
            ),
        ]
    )
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    let labelEntry = try #require(plan.entries.first { $0.usr == label.usr })
    let messageEntry = try #require(plan.entries.first { $0.usr == message.usr })
    let webViewEntry = try #require(plan.entries.first { $0.usr == webView.usr })
    let shadowedValueEntry = try #require(
        plan.entries.first { $0.usr == shadowedValue.usr }
    )
    #expect(plan.entries.count == 4)
    #expect(labelEntry.replacements.count == 2)
    #expect(messageEntry.replacements.count == 2)
    #expect(shadowedValueEntry.replacements.count == 2)
    #expect(webViewEntry.replacements.count == 3)
    #expect(plan.parameterSyntaxFacts.localBindingReferenceTokens == 5)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.parameterLocalBindingOutcome.candidates == 4)
    #expect(plan.parameterLocalBindingOutcome.renamed == 4)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("init(_ \(labelEntry.newName): String)"))
    #expect(patched.contains("self.label = \(labelEntry.newName)"))
    #expect(patched.contains("func format(_ \(messageEntry.newName): String)"))
    #expect(patched.contains("\\(\(messageEntry.newName))"))
    #expect(patched.contains("func evaluate(_ \(webViewEntry.newName): WebView)"))
    #expect(patched.contains("[weak \(webViewEntry.newName)]"))
    #expect(patched.contains("\(webViewEntry.newName)?.run()"))
    #expect(patched.contains("func shadow(_ \(shadowedValueEntry.newName): Int)"))
    #expect(patched.contains("do { let value = 1; _ = value }"))
    #expect(patched.contains("return \(shadowedValueEntry.newName)"))
}

@Test func parameterLocalBindingRenameFailsClosedForImplicitSwiftBindings() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ImplicitBindings.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let error = testSymbol("usr-implicit-error-shadow", "error")
    let newValue = testSymbol("usr-implicit-new-value-shadow", "newValue")
    let oldValue = testSymbol("usr-implicit-old-value-shadow", "oldValue")
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [error, newValue, oldValue],
        occurrences: [
            testOccurrence(error, path: file.path, line: 1, token: "error", roles: [.definition]),
            testOccurrence(
                newValue,
                path: file.path,
                line: 4,
                token: "newValue",
                roles: [.definition]
            ),
            testOccurrence(
                oldValue,
                path: file.path,
                line: 8,
                token: "oldValue",
                roles: [.definition]
            ),
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.entries.isEmpty)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 3)
    #expect(plan.parameterSyntaxFacts.localBindingOnlyCoverageCandidates == 0)
    #expect(plan.denied.map(\.usr).contains(error.usr))
    #expect(plan.denied.map(\.usr).contains(newValue.usr))
    #expect(plan.denied.map(\.usr).contains(oldValue.usr))
}

@Test func parameterLocalBindingRenameFailsClosedForMultiBindingScope() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("MultiBindingShadow.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-multi-binding-shadow",
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
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 1)
    #expect(plan.parameterSyntaxFacts.localBindingOnlyCoverageCandidates == 0)
    #expect(plan.denied.contains { $0.usr == value.usr })

    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}
@Test func localVariableShadowInsideClosureEndsAtClosureBoundary() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ClosureShadow.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let group = SymbolRecord(
        usr: "usr-closure-shadow-boundary",
        name: "group",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [group],
        occurrences: [
            testOccurrence(
                group,
                path: file.path,
                line: 2,
                token: "group",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == group.usr })
    #expect(entry.replacements.count == 2)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Group)"))
    #expect(patched.contains("{ let group = Group(); _ = group }"))
    #expect(patched.contains("return \(entry.newName)"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func switchCasePatternShadowEndsAtCaseBoundary() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("SwitchCaseShadow.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let groupId = SymbolRecord(
        usr: "usr-switch-case-shadow-boundary",
        name: "groupId",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [groupId],
        occurrences: [
            testOccurrence(
                groupId,
                path: file.path,
                line: 2,
                token: "groupId",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == groupId.usr })
    #expect(entry.replacements.count == 3)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func route(_ \(entry.newName): Int"))
    #expect(patched.contains("case .standard: \(entry.newName)"))
    #expect(patched.contains("case .commented(let groupId): groupId"))
    #expect(patched.contains("return result + \(entry.newName)"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func switchCaseMultiPatternShadowFailsClosed() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("SwitchCaseMultiPattern.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let value = SymbolRecord(
        usr: "usr-switch-case-multi-pattern",
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
                line: 2,
                token: "value",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    #expect(!plan.entries.contains { $0.usr == value.usr })
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 1)
    #expect(
        plan.parameterSyntaxFacts.unresolvedShadowingBindingKinds == [
            "switchCasePattern": 1
        ])
    #expect(plan.denied.contains { $0.usr == value.usr })
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}
