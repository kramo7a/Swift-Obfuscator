import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Extensions, generics, and type relations

@Test func renameEligibilityAnalyzerDeniesExtensionsOnExternalOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-firstValue",
        name: "firstValue",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "firstValue", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        semanticIndex: SemanticIndex(externallyOwnedUSRs: [symbol.usr])
    )

    #expect(decision.isEligible == false)
    #expect(decision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
}

@Test func renamePlannerAllowsSourceAuthoredMembersOnExternalOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ExternalOwnerExtension.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let string = IndexSnapshot.Symbol(
        usr: "s:SS",
        name: "String",
        kind: "struct",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let externalExtension = IndexSnapshot.Symbol(
        usr: "s:e:FixtureStringExtension",
        name: "String",
        kind: "extension",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let framed = IndexSnapshot.Symbol(
        usr: "s:SS7FixtureE6framedSSyF",
        name: "framed()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let extendedBy = IndexSnapshot.Relation(
        usr: externalExtension.usr,
        name: externalExtension.name,
        rolesRaw: 0,
        roles: ["extendedBy"]
    )
    let childOf = IndexSnapshot.Relation(
        usr: externalExtension.usr,
        name: externalExtension.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [string, externalExtension, framed],
        occurrences: [
            testOccurrence(
                string,
                path: file.path,
                line: 1,
                token: "String",
                roles: [.reference, .extendedBy],
                relations: [extendedBy]
            ),
            testOccurrence(
                externalExtension,
                path: file.path,
                line: 1,
                token: "String",
                roles: [.definition]
            ),
            testOccurrence(
                framed,
                path: file.path,
                line: 2,
                token: "framed",
                roles: [.definition, .childOf],
                relations: [childOf]
            ),
            testOccurrence(
                framed,
                path: file.path,
                line: 4,
                token: "framed",
                roles: [.reference, .call]
            ),
        ]
    )
    let analysis = SemanticIndex(snapshot: snapshot, obfuscationRoots: [directory])
    #expect(analysis.externallyOwnedUSRs.contains(externalExtension.usr))
    #expect(analysis.externallyOwnedUSRs.contains(framed.usr))
    #expect(analysis.selectedDeclarationUSRs.contains(framed.usr))

    let beforeExecutable = directory.appendingPathComponent("Before")
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", beforeExecutable.path]
    )
    _ = try CommandRunner().run(executable: beforeExecutable.path, arguments: [])

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.renames.first { $0.usr == framed.usr })
    #expect(entry.oldName == "framed")
    #expect(entry.edits.count == 2)
    #expect(!plan.renames.contains { $0.usr == externalExtension.usr })
    #expect(!plan.renames.contains { $0.usr == string.usr })
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func \(entry.newName)()"))
    #expect(patched.contains(".\(entry.newName)()"))
    #expect(patched.contains("extension String"))

    let afterExecutable = directory.appendingPathComponent("After")
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", afterExecutable.path]
    )
    _ = try CommandRunner().run(executable: afterExecutable.path, arguments: [])
}

@Test func renameEligibilityAnalyzerDeniesStdlibModuleExtensionOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-jsonData",
        name: "jsonData",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "jsonData", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        semanticIndex: SemanticIndex(externallyOwnedUSRs: [symbol.usr])
    )

    #expect(decision.isEligible == false)
    #expect(decision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
}

@Test func renameEligibilityAnalyzerAllowsExtensionsOnLocalNominalOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-helper",
        name: "helper",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 3,
        utf8Column: utf8Column(of: "helper", in: lines[2]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.isEligible == true)
    #expect(decision.originalName == "helper")
}

@Test func renameEligibilityAnalyzerDeniesExtensionsOnTypeAliasOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-helper",
        name: "helper",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 3,
        utf8Column: utf8Column(of: "helper", in: lines[2]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        semanticIndex: SemanticIndex(externallyOwnedUSRs: [symbol.usr])
    )

    #expect(decision.isEligible == false)
    #expect(decision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
}

@Test func renameEligibilityAnalyzerDeniesGenericTypeParameters() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "struct Box<Value> { let value: Value }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-value",
        name: "Value",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "Value", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        genericParameterUSRs: [symbol.usr]
    )

    #expect(decision.isEligible == false)
    #expect(decision.reasons.contains("generic type parameter occurrences are incomplete"))
}

@Test func renamePlannerUsesIndexedGenericParameterOccurrencesAfterSyntaxAnchoring() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let genericParameter = IndexSnapshot.Symbol(
        usr: "usr-generic-value",
        name: "Value",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let ordinaryTypeAlias = IndexSnapshot.Symbol(
        usr: "usr-alias",
        name: "Alias",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    func occurrence(
        _ symbol: IndexSnapshot.Symbol,
        line: Int,
        roles: [String]
    ) -> IndexSnapshot.Occurrence {
        IndexSnapshot.Occurrence(
            symbol: symbol,
            path: file.path,
            line: line,
            utf8Column: utf8Column(of: symbol.name, in: lines[line - 1]),
            moduleName: "Sample",
            isSystem: false,
            rolesRaw: roles.contains("definition") ? 2 : 4,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: []
        )
    }
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [genericParameter, ordinaryTypeAlias],
        occurrences: [
            occurrence(genericParameter, line: 1, roles: ["definition"]),
            occurrence(genericParameter, line: 2, roles: ["reference"]),
            occurrence(genericParameter, line: 3, roles: ["reference"]),
            occurrence(genericParameter, line: 4, roles: ["reference"]),
            occurrence(ordinaryTypeAlias, line: 7, roles: ["definition"]),
        ]
    )

    let analysis = GenericParameterAnalysis.Index(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [directory]
    )
    #expect(analysis.genericParameterUSRs == [genericParameter.usr])
    #expect(analysis.supportedGenericParameterUSRs == [genericParameter.usr])
    #expect(analysis.issueReasonsByUSR.isEmpty)
    #expect(analysis.report.syntaxGenericParameters == 1)
    #expect(analysis.report.indexedGenericParameters == 1)
    #expect(analysis.report.supportedGenericParameters == 1)
    #expect(analysis.report.indexedOccurrences == 4)

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.renames.first { $0.usr == genericParameter.usr })
    #expect(entry.edits.count == 4)
    #expect(plan.genericParameterReport.supportedGenericParameters == 1)
    #expect(plan.renames.contains { $0.usr == ordinaryTypeAlias.usr })
    #expect(plan.rejections.allSatisfy { $0.usr != genericParameter.usr })

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("struct Box<\(entry.newName): Hashable>"))
    #expect(patched.contains("let stored: \(entry.newName)"))
    #expect(patched.contains("func accept(_ input: \(entry.newName))"))
    #expect(patched.contains("let _: \(entry.newName) = input"))
}

@Test func renameEligibilityAnalyzerDeniesAccessorContextualKeywords() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "protocol Analyzer { var isRunning: Bool { get set } }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let getter = IndexSnapshot.Symbol(
        usr: "usr-getter",
        name: "getter:isRunning",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let getterOccurrence = IndexSnapshot.Occurrence(
        symbol: getter,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "get", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let getterDecision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: getter.usr, symbol: getter, occurrences: [getterOccurrence]),
        sourceCache: cache
    )

    #expect(getterDecision.isEligible == false)
    #expect(
        getterDecision.reasons.contains {
            $0.contains("synthetic accessor is derived from its parent declaration")
        })

    let setter = IndexSnapshot.Symbol(
        usr: "usr-setter",
        name: "setter:isRunning",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let setterOccurrence = IndexSnapshot.Occurrence(
        symbol: setter,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "set", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let setterDecision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: setter.usr, symbol: setter, occurrences: [setterOccurrence]),
        sourceCache: cache
    )

    #expect(setterDecision.isEligible == false)
    #expect(
        setterDecision.reasons.contains {
            $0.contains("synthetic accessor is derived from its parent declaration")
        })
}
