import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Runtime and declaration safety

@Test func safetyAnalyzerDeniesClassesNamedByInterfaceBuilderResources() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Controllers.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    try "<document/>\n".write(
        to: directory.appendingPathComponent("MainViewController.xib"),
        atomically: true,
        encoding: .utf8
    )
    try #"<document><viewController customClass="StoryboardViewController"/></document>"#.write(
        to: directory.appendingPathComponent("Scene.storyboard"),
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])
    let analyzer = SafetyAnalyzer(sourceRoot: directory)

    func decision(name: String, line: Int) -> SafetyDecision {
        let symbol = SymbolRecord(
            usr: "usr-\(name)",
            name: name,
            kind: "class",
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
        let occurrence = OccurrenceRecord(
            symbol: symbol,
            path: file.path,
            line: line,
            utf8Column: utf8Column(of: name, in: lines[line - 1]),
            moduleName: "Fixture",
            isSystem: false,
            rolesRaw: 1,
            roles: ["declaration"],
            rolesDescription: "decl",
            symbolProvider: "swift",
            relations: []
        )
        return analyzer.analyze(
            group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
            sourceCache: cache
        )
    }

    let xibDecision = decision(name: "MainViewController", line: 1)
    #expect(xibDecision.allowed == false)
    #expect(xibDecision.reasons.contains("Interface Builder resource requires stable class name MainViewController"))

    let storyboardDecision = decision(name: "StoryboardViewController", line: 2)
    #expect(storyboardDecision.allowed == false)
    #expect(
        storyboardDecision.reasons.contains(
            "Interface Builder resource requires stable class name StoryboardViewController"))

    #expect(decision(name: "PlainViewController", line: 3).allowed == true)
}

@Test func safetyAnalyzerAllowsPublicAndOpenDeclarations() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let protocolSymbol = SymbolRecord(
        usr: "usr-analyzer",
        name: "Analyzer",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let protocolOccurrence = OccurrenceRecord(
        symbol: protocolSymbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "Analyzer", in: lines[0]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let protocolDecision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: protocolSymbol.usr, symbol: protocolSymbol, occurrences: [protocolOccurrence]),
        sourceCache: cache
    )

    #expect(protocolDecision.allowed)
    #expect(protocolDecision.oldName == "Analyzer")

    let property = SymbolRecord(
        usr: "usr-count",
        name: "count",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let propertyOccurrence = OccurrenceRecord(
        symbol: property,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "count", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let propertyDecision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: property.usr, symbol: property, occurrences: [propertyOccurrence]),
        sourceCache: cache
    )

    #expect(propertyDecision.allowed)
    #expect(propertyDecision.oldName == "count")

    let function = SymbolRecord(
        usr: "usr-run",
        name: "run",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let functionOccurrence = OccurrenceRecord(
        symbol: function,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "run", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let functionDecision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: function.usr, symbol: function, occurrences: [functionOccurrence]),
        sourceCache: cache
    )

    #expect(functionDecision.allowed)
    #expect(functionDecision.oldName == "run")

    let variable = SymbolRecord(
        usr: "usr-globalCount",
        name: "globalCount",
        kind: "variable",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let variableOccurrence = OccurrenceRecord(
        symbol: variable,
        path: file.path,
        line: 3,
        utf8Column: utf8Column(of: "globalCount", in: lines[2]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let variableDecision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: variable.usr, symbol: variable, occurrences: [variableOccurrence]),
        sourceCache: cache
    )

    #expect(variableDecision.allowed)
    #expect(variableDecision.oldName == "globalCount")
}

@Test func safetyAnalyzerConsumesIndexedRuntimeFactsForPublicDeclarations() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])
    let runtimeSensitiveUSRs: Set<String> = [
        "usr-runtime-model", "usr-inherited-exposure", "usr-explicit", "usr-dynamic",
    ]

    func decision(
        usr: String,
        name: String,
        kind: String,
        line: Int
    ) -> SafetyDecision {
        let symbol = SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
        let occurrence = OccurrenceRecord(
            symbol: symbol,
            path: file.path,
            line: line,
            utf8Column: utf8Column(of: name, in: lines[line - 1]),
            moduleName: "Sample",
            isSystem: false,
            rolesRaw: 1,
            roles: ["declaration"],
            rolesDescription: "decl",
            symbolProvider: "swift",
            relations: []
        )
        return SafetyAnalyzer(sourceRoot: directory).analyze(
            group: USROccurrenceGroup(usr: usr, symbol: symbol, occurrences: [occurrence]),
            sourceCache: cache,
            indexedFacts: IndexedSemanticFacts(runtimeSensitiveUSRs: runtimeSensitiveUSRs)
        )
    }

    let objcMembersClass = decision(usr: "usr-runtime-model", name: "RuntimeModel", kind: "class", line: 1)
    let objcMembersMethod = decision(
        usr: "usr-inherited-exposure", name: "inheritedExposure", kind: "instanceMethod", line: 2)
    let explicitObjCMethod = decision(usr: "usr-explicit", name: "explicitlyExposed", kind: "function", line: 5)
    let dynamicMethod = decision(usr: "usr-dynamic", name: "dynamicallyDispatched", kind: "function", line: 6)
    let objcUSRClass = decision(
        usr: "c:@M@Sample@objc(cs)RuntimeController",
        name: "RuntimeController",
        kind: "class",
        line: 7
    )

    #expect(objcMembersClass.allowed == false)
    #expect(objcMembersMethod.allowed == false)
    #expect(explicitObjCMethod.allowed == false)
    #expect(dynamicMethod.allowed == false)
    #expect(objcUSRClass.allowed == false)
    #expect(
        [objcMembersClass, objcMembersMethod, explicitObjCMethod, dynamicMethod].allSatisfy {
            $0.reasons.contains { $0.contains("runtime-reflected") }
        })
    #expect(objcUSRClass.reasons.contains { $0.contains("Objective-C-compatible USR") })
}

@Test func indexedSemanticFactsDoNotInferRuntimeDispatchFromOverrideSyntax() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let base = SymbolRecord(
        usr: "s:6Sample4BaseC3runyyF",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let child = SymbolRecord(
        usr: "s:6Sample5ChildC3runyyF",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let baseOccurrence = testOccurrence(
        base,
        path: file.path,
        line: 1,
        token: "run",
        roles: [.definition]
    )
    let childOccurrence = OccurrenceRecord(
        symbol: child,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "run", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["definition", "overrideOf"],
        rolesDescription: "[definition|overrideOf]",
        symbolProvider: "swift",
        relations: [
            RelationRecord(
                usr: base.usr,
                name: base.name,
                rolesRaw: 1 << 11,
                roles: ["overrideOf"]
            )
        ]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [base, child],
        occurrences: [baseOccurrence, childOccurrence]
    )
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])
    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: child.usr, symbol: child, occurrences: [childOccurrence]),
        sourceCache: cache,
        indexedFacts: facts,
        overrideRelatedUSRs: [base.usr, child.usr],
        coordinatedRelatedUSRs: [base.usr, child.usr]
    )

    #expect(!facts.runtimeSensitiveUSRs.contains(child.usr))
    #expect(decision.allowed)
    #expect(!decision.reasons.contains { $0.contains("runtime-reflected") })
}

@Test func safetyAnalyzerKeepsNarrowLexicalFallbackForExternalLinkageAttributes() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "@_cdecl(\"exported_entry\") public func exportedEntry() {}"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let symbol = SymbolRecord(
        usr: "s:6Sample13exportedEntryyyF",
        name: "exportedEntry()",
        kind: "function",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = testOccurrence(
        symbol,
        path: file.path,
        line: 1,
        token: "exportedEntry",
        roles: [.definition]
    )
    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(!decision.allowed)
    #expect(decision.reasons.contains { $0.contains("externally linked declaration") })
}

@Test func lexicalRuntimeAttributeFallbackIsLimitedToTheAnnotatedDeclaration() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    func decision(usr: String, name: String, kind: String, line: Int) -> SafetyDecision {
        let symbol = SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
        let occurrence = testOccurrence(
            symbol,
            path: file.path,
            line: line,
            token: name,
            roles: [.definition]
        )
        return SafetyAnalyzer(sourceRoot: directory).analyze(
            group: USROccurrenceGroup(usr: usr, symbol: symbol, occurrences: [occurrence]),
            sourceCache: cache
        )
    }

    let runtimeNamed = decision(usr: "s:runtime-named", name: "RuntimeNamed", kind: "class", line: 2)
    let designedValue = decision(usr: "s:designed-value", name: "designedValue", kind: "instanceProperty", line: 3)
    let exposed = decision(usr: "s:exposed", name: "exposedToObjectiveC", kind: "function", line: 4)
    let swiftOnly = decision(usr: "s:swift-only", name: "swiftOnly", kind: "function", line: 5)

    #expect(!runtimeNamed.allowed)
    #expect(!designedValue.allowed)
    #expect(!exposed.allowed)
    #expect(swiftOnly.allowed)
    #expect(
        [runtimeNamed, designedValue, exposed].allSatisfy {
            $0.reasons.contains { $0.contains("runtime-reflected") }
        })
}

@Test func renamePlannerPlansAndPatchesPublicSymbols() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("PublicAPI.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let typeSymbol = SymbolRecord(
        usr: "s:6Sample11PublicModelV",
        name: "PublicModel",
        kind: "struct",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let functionSymbol = SymbolRecord(
        usr: "s:6Sample9makeModelAA06PublicD0VyF",
        name: "makeModel()",
        kind: "function",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let propertySymbol = SymbolRecord(
        usr: "s:6Sample11PublicModelV11displayNameSSvp",
        name: "displayName",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    func occurrence(
        symbol: SymbolRecord,
        tokenName: String,
        line: Int,
        roles: [String]
    ) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: file.path,
            line: line,
            utf8Column: utf8Column(of: tokenName, in: lines[line - 1]),
            moduleName: "Sample",
            isSystem: false,
            rolesRaw: roles.contains("declaration") ? 1 : 2,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: []
        )
    }

    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [typeSymbol, functionSymbol, propertySymbol],
        occurrences: [
            occurrence(symbol: typeSymbol, tokenName: "PublicModel", line: 1, roles: ["declaration"]),
            occurrence(symbol: propertySymbol, tokenName: "displayName", line: 2, roles: ["declaration"]),
            occurrence(symbol: functionSymbol, tokenName: "makeModel", line: 4, roles: ["declaration"]),
            occurrence(symbol: typeSymbol, tokenName: "PublicModel", line: 4, roles: ["reference"]),
            occurrence(symbol: typeSymbol, tokenName: "PublicModel", line: 5, roles: ["reference"]),
        ]
    )
    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(sourceRoot: directory),
        mappingStore: MappingStore()
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.denied.isEmpty)
    #expect(plan.conflicts.isEmpty)
    #expect(plan.entries.count == 3)
    #expect(Set(plan.entries.map(\.oldName)) == ["PublicModel", "displayName", "makeModel"])

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    let typeName = try #require(plan.entries.first { $0.oldName == "PublicModel" }?.newName)
    let propertyName = try #require(plan.entries.first { $0.oldName == "displayName" }?.newName)
    let functionName = try #require(plan.entries.first { $0.oldName == "makeModel" }?.newName)
    #expect(typeName.first?.isUppercase == true)
    #expect(propertyName.first?.isLowercase == true)
    #expect(functionName.first?.isLowercase == true)
    #expect(
        patched
            == [
                "public struct \(typeName) {",
                "    public var \(propertyName): String { \"name\" }",
                "}",
                "public func \(functionName)() -> \(typeName) {",
                "    \(typeName)()",
                "}",
                "",
            ].joined(separator: "\n"))
}
