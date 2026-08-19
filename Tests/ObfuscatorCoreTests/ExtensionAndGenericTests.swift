import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Extensions, generics, and type relations

@Test func safetyAnalyzerDeniesExtensionsOnExternalOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-firstValue",
        name: "firstValue",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        indexedFacts: IndexedSemanticFacts(externallyOwnedUSRs: [symbol.usr])
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
}

@Test func renamePlannerAllowsSourceAuthoredMembersOnExternalOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ExternalOwnerExtension.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let string = SymbolRecord(
        usr: "s:SS",
        name: "String",
        kind: "struct",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let externalExtension = SymbolRecord(
        usr: "s:e:FixtureStringExtension",
        name: "String",
        kind: "extension",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let framed = SymbolRecord(
        usr: "s:SS7FixtureE6framedSSyF",
        name: "framed()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let extendedBy = RelationRecord(
        usr: externalExtension.usr,
        name: externalExtension.name,
        rolesRaw: 0,
        roles: ["extendedBy"]
    )
    let childOf = RelationRecord(
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
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])
    #expect(facts.externallyOwnedUSRs.contains(externalExtension.usr))
    #expect(facts.externallyOwnedUSRs.contains(framed.usr))
    #expect(facts.selectedDeclarationUSRs.contains(framed.usr))

    let beforeExecutable = directory.appendingPathComponent("Before")
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", beforeExecutable.path]
    )
    _ = try CommandRunner().run(executable: beforeExecutable.path, arguments: [])

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == framed.usr })
    #expect(entry.oldName == "framed")
    #expect(entry.replacements.count == 2)
    #expect(!plan.entries.contains { $0.usr == externalExtension.usr })
    #expect(!plan.entries.contains { $0.usr == string.usr })
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(plan.replacements)
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

@Test func safetyAnalyzerDeniesStdlibModuleExtensionOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-jsonData",
        name: "jsonData",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        indexedFacts: IndexedSemanticFacts(externallyOwnedUSRs: [symbol.usr])
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
}

@Test func safetyAnalyzerAllowsExtensionsOnLocalNominalOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-helper",
        name: "helper",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed == true)
    #expect(decision.oldName == "helper")
}

@Test func safetyAnalyzerDeniesExtensionsOnTypealiasOwners() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-helper",
        name: "helper",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        indexedFacts: IndexedSemanticFacts(externallyOwnedUSRs: [symbol.usr])
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
}

@Test func safetyAnalyzerDeniesGenericTypeParameters() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "struct Box<Value> { let value: Value }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-value",
        name: "Value",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        genericParameterUSRs: [symbol.usr]
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("generic type parameter occurrences are incomplete"))
}

@Test func renamePlannerUsesIndexedGenericParameterOccurrencesAfterSyntaxAnchoring() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let genericParameter = SymbolRecord(
        usr: "usr-generic-value",
        name: "Value",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let ordinaryTypealias = SymbolRecord(
        usr: "usr-alias",
        name: "Alias",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    func occurrence(
        _ symbol: SymbolRecord,
        line: Int,
        roles: [String]
    ) -> OccurrenceRecord {
        OccurrenceRecord(
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
        symbols: [genericParameter, ordinaryTypealias],
        occurrences: [
            occurrence(genericParameter, line: 1, roles: ["definition"]),
            occurrence(genericParameter, line: 2, roles: ["reference"]),
            occurrence(genericParameter, line: 3, roles: ["reference"]),
            occurrence(genericParameter, line: 4, roles: ["reference"]),
            occurrence(ordinaryTypealias, line: 7, roles: ["definition"]),
        ]
    )

    let facts = GenericParameterSyntaxFacts(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [directory]
    )
    #expect(facts.genericParameterUSRs == [genericParameter.usr])
    #expect(facts.supportedGenericParameterUSRs == [genericParameter.usr])
    #expect(facts.unresolvedReasonsByUSR.isEmpty)
    #expect(facts.summary.syntaxGenericParameters == 1)
    #expect(facts.summary.indexedGenericParameters == 1)
    #expect(facts.summary.supportedGenericParameters == 1)
    #expect(facts.summary.indexedOccurrences == 4)

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == genericParameter.usr })
    #expect(entry.replacements.count == 4)
    #expect(plan.genericParameterSyntaxFacts.supportedGenericParameters == 1)
    #expect(plan.entries.contains { $0.usr == ordinaryTypealias.usr })
    #expect(plan.denied.allSatisfy { $0.usr != genericParameter.usr })

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("struct Box<\(entry.newName): Hashable>"))
    #expect(patched.contains("let stored: \(entry.newName)"))
    #expect(patched.contains("func accept(_ input: \(entry.newName))"))
    #expect(patched.contains("let _: \(entry.newName) = input"))
}

@Test func safetyAnalyzerDeniesAccessorContextualKeywords() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "protocol Analyzer { var isRunning: Bool { get set } }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let getter = SymbolRecord(
        usr: "usr-getter",
        name: "getter:isRunning",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let getterOccurrence = OccurrenceRecord(
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
    let getterDecision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: getter.usr, symbol: getter, occurrences: [getterOccurrence]),
        sourceCache: cache
    )

    #expect(getterDecision.allowed == false)
    #expect(
        getterDecision.reasons.contains {
            $0.contains("synthetic accessor is derived from its parent declaration")
        })

    let setter = SymbolRecord(
        usr: "usr-setter",
        name: "setter:isRunning",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let setterOccurrence = OccurrenceRecord(
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
    let setterDecision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: setter.usr, symbol: setter, occurrences: [setterOccurrence]),
        sourceCache: cache
    )

    #expect(setterDecision.allowed == false)
    #expect(
        setterDecision.reasons.contains {
            $0.contains("synthetic accessor is derived from its parent declaration")
        })
}
