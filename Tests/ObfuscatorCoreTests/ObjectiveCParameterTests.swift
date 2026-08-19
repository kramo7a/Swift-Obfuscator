import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Objective-C and inherited parameter labels

@Test func parameterPlannerPreservesObjectiveCLabelAndRenamesOnlyLocalBinding() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("RuntimeParameter.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let runtimeMethod = SymbolRecord(
        usr: "c:@M@Fixture@objc(cs)RuntimeBridge(im)executePayload:",
        name: "execute(payload:)",
        kind: "instanceMethod",
        language: "objective-c",
        propertiesRaw: 0,
        properties: "[]"
    )
    let value = SymbolRecord(
        usr: "s:FixtureRuntimeParameterValue",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let childOfMethod = RelationRecord(
        usr: runtimeMethod.usr,
        name: runtimeMethod.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [runtimeMethod, value],
        occurrences: [
            testOccurrence(
                runtimeMethod,
                path: file.path,
                line: 4,
                token: "execute",
                roles: [.definition]
            ),
            testOccurrence(
                value,
                path: file.path,
                line: 4,
                token: "value",
                roles: [.definition],
                relations: [childOfMethod]
            ),
        ]
    )

    let beforeExecutable = directory.appendingPathComponent("Before")
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", beforeExecutable.path]
    )
    _ = try CommandRunner().run(executable: beforeExecutable.path, arguments: [])

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(entry.replacements.count == 2)
    #expect(
        plan.parameterExternalLabelComponentFacts.blockerComponents == [
            "objectiveCRuntimeDispatch": 1
        ])
    #expect(plan.parameterExternalLabelRenameOutcome.candidateParameterUSRs == 0)
    #expect(plan.parameterLocalBindingOutcome.candidates == 1)
    #expect(plan.parameterLocalBindingOutcome.renamed == 1)
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("@objc(executePayload:)"))
    #expect(patched.contains("func execute(payload \(entry.newName): Int)"))
    #expect(patched.contains("execute(payload: 41)"))
    #expect(!patched.contains("payload \(entry.newName): Int) -> Int { value"))

    let afterExecutable = directory.appendingPathComponent("After")
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", afterExecutable.path]
    )
    _ = try CommandRunner().run(executable: afterExecutable.path, arguments: [])
}

@Test func parameterPlannerSplitsSharedObjectiveCLabelFromLocalBinding() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("SharedRuntimeParameter.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let runtimeMethod = SymbolRecord(
        usr: "c:@M@Fixture@objc(cs)RuntimeBridge(im)executePayload:",
        name: "execute(payload:)",
        kind: "instanceMethod",
        language: "objective-c",
        propertiesRaw: 0,
        properties: "[]"
    )
    let payload = SymbolRecord(
        usr: "s:FixtureSharedRuntimeParameterPayload",
        name: "payload",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let childOfMethod = RelationRecord(
        usr: runtimeMethod.usr,
        name: runtimeMethod.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [runtimeMethod, payload],
        occurrences: [
            testOccurrence(
                runtimeMethod,
                path: file.path,
                line: 4,
                token: "execute",
                roles: [.definition]
            ),
            testOccurrence(
                payload,
                path: file.path,
                line: 4,
                token: "payload",
                roles: [.definition],
                relations: [childOfMethod]
            ),
        ]
    )

    let beforeExecutable = directory.appendingPathComponent("Before")
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", beforeExecutable.path]
    )
    _ = try CommandRunner().run(executable: beforeExecutable.path, arguments: [])

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == payload.usr })
    #expect(entry.replacements.count == 2)
    #expect(
        entry.replacements.contains {
            $0.length == 0 && $0.oldName.isEmpty && $0.newName == " \(entry.newName)"
        })
    #expect(
        plan.parameterExternalLabelComponentFacts.blockerComponents == [
            "objectiveCRuntimeDispatch": 1
        ])
    #expect(plan.parameterExternalLabelRenameOutcome.candidateParameterUSRs == 0)
    #expect(plan.parameterLocalBindingOutcome.candidates == 1)
    #expect(plan.parameterLocalBindingOutcome.renamed == 1)
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("@objc(executePayload:)"))
    #expect(patched.contains("func execute(payload \(entry.newName): Int)"))
    #expect(patched.contains("{ \(entry.newName) + 1 }"))
    #expect(patched.contains("execute(payload: 41)"))

    let afterExecutable = directory.appendingPathComponent("After")
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", afterExecutable.path]
    )
    _ = try CommandRunner().run(executable: afterExecutable.path, arguments: [])
}

@Test func parameterPlannerSplitsSharedNestedFunctionLabelFromLocalBinding() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("NestedFunctionParameter.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let outer = SymbolRecord(
        usr: "s:FixtureOuterFunction",
        name: "outer()",
        kind: "function",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let layer = SymbolRecord(
        usr: "s:FixtureNestedFunctionLayer",
        name: "layer",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let childOfOuter = RelationRecord(
        usr: outer.usr,
        name: outer.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [outer, layer],
        occurrences: [
            testOccurrence(
                outer,
                path: file.path,
                line: 1,
                token: "outer",
                roles: [.definition]
            ),
            testOccurrence(
                layer,
                path: file.path,
                line: 2,
                token: "layer",
                roles: [.definition],
                relations: [childOfOuter]
            ),
            testOccurrence(
                outer,
                path: file.path,
                line: 5,
                token: "outer",
                roles: [.reference]
            ),
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == layer.usr })
    #expect(entry.replacements.count == 2)
    #expect(
        entry.replacements.contains {
            $0.length == 0 && $0.oldName.isEmpty && $0.newName == " \(entry.newName)"
        })
    #expect(plan.parameterSyntaxFacts.nestedLocalFunctionParameters == 1)
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("configure(layer \(entry.newName): Int)"))
    #expect(patched.contains("{ \(entry.newName) }"))
    #expect(patched.contains("configure(layer: 41)"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", directory.appendingPathComponent("After").path]
    )
}
@Test func inheritedInitializerKeepsLabelWhileSplittingLocalBinding() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("InheritedInitializer.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let base = testSymbol("usr-inherited-base", "Base", .class)
    let child = testSymbol("usr-inherited-child", "Child", .class)
    let initializer = testSymbol(
        "usr-inherited-convenience-initializer",
        "init(session:)",
        .constructor
    )
    let session = testSymbol("usr-inherited-session", "session", .parameter)
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [base, child, initializer, session],
        occurrences: [
            testOccurrence(
                base,
                path: file.path,
                line: 1,
                token: "Base",
                roles: [.definition]
            ),
            testOccurrence(
                child,
                path: file.path,
                line: 7,
                token: "Child",
                roles: [.definition]
            ),
            testOccurrence(
                base,
                path: file.path,
                line: 7,
                token: "Base",
                roles: [.reference, .baseOf],
                relations: [testRelation(child, role: .baseOf)]
            ),
            testOccurrence(
                initializer,
                path: file.path,
                line: 3,
                token: "init",
                roles: [.definition],
                relations: [testRelation(base, role: .childOf)]
            ),
            testOccurrence(
                session,
                path: file.path,
                line: 3,
                token: "session",
                roles: [.definition],
                relations: [testRelation(initializer, role: .childOf)]
            ),
            testOccurrence(
                child,
                path: file.path,
                line: 8,
                token: "Child",
                roles: [.reference]
            ),
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == session.usr })
    #expect(entry.replacements.count == 2)
    #expect(
        entry.replacements.contains {
            $0.length == 0 && $0.oldName.isEmpty && $0.newName == " \(entry.newName)"
        })
    #expect(plan.parameterExternalLabelComponentFacts.deniedAtomicComponents == 1)
    #expect(
        plan.parameterExternalLabelComponentFacts.blockerComponents == [
            "incompleteInheritedConstructorCoverage": 1
        ])
    #expect(plan.parameterExternalLabelRenameOutcome.candidateAtomicComponents == 0)
    #expect(plan.parameterLocalBindingOutcome.candidates == 1)
    #expect(plan.parameterLocalBindingOutcome.renamed == 1)
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("convenience init(session \(entry.newName): Int)"))
    #expect(patched.contains("self.init(session: \(entry.newName), url: \"\")"))
    #expect(patched.contains("(session: 1)"))
    #expect(!patched.contains("(\(entry.newName): 1)"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}
