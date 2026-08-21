import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Runtime and declaration safety

@Test func renameEligibilityAnalyzerDeniesClassesNamedByInterfaceBuilderResources() throws {
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
    let analyzer = RenameEligibilityAnalyzer(sourceRoot: directory)

    func decision(name: String, line: Int) -> RenameEligibility {
        let symbol = IndexSnapshot.Symbol(
            usr: "usr-\(name)",
            name: name,
            kind: "class",
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
        let occurrence = IndexSnapshot.Occurrence(
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
            group: IndexSnapshot.OccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
            sourceCache: cache
        )
    }

    let xibDecision = decision(name: "MainViewController", line: 1)
    #expect(xibDecision.isEligible == false)
    #expect(xibDecision.reasons.contains("Interface Builder resource requires stable class name MainViewController"))

    let storyboardDecision = decision(name: "StoryboardViewController", line: 2)
    #expect(storyboardDecision.isEligible == false)
    #expect(
        storyboardDecision.reasons.contains(
            "Interface Builder resource requires stable class name StoryboardViewController"))

    #expect(decision(name: "PlainViewController", line: 3).isEligible == true)
}

@Test func renameEligibilityAnalyzerAllowsPublicAndOpenDeclarations() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let protocolSymbol = IndexSnapshot.Symbol(
        usr: "usr-analyzer",
        name: "Analyzer",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let protocolOccurrence = IndexSnapshot.Occurrence(
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
    let protocolDecision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: protocolSymbol.usr, symbol: protocolSymbol, occurrences: [protocolOccurrence]),
        sourceCache: cache
    )

    #expect(protocolDecision.isEligible)
    #expect(protocolDecision.originalName == "Analyzer")

    let property = IndexSnapshot.Symbol(
        usr: "usr-count",
        name: "count",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let propertyOccurrence = IndexSnapshot.Occurrence(
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
    let propertyDecision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: property.usr, symbol: property, occurrences: [propertyOccurrence]),
        sourceCache: cache
    )

    #expect(propertyDecision.isEligible)
    #expect(propertyDecision.originalName == "count")

    let function = IndexSnapshot.Symbol(
        usr: "usr-run",
        name: "run",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let functionOccurrence = IndexSnapshot.Occurrence(
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
    let functionDecision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: function.usr, symbol: function, occurrences: [functionOccurrence]),
        sourceCache: cache
    )

    #expect(functionDecision.isEligible)
    #expect(functionDecision.originalName == "run")

    let variable = IndexSnapshot.Symbol(
        usr: "usr-globalCount",
        name: "globalCount",
        kind: "variable",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let variableOccurrence = IndexSnapshot.Occurrence(
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
    let variableDecision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: variable.usr, symbol: variable, occurrences: [variableOccurrence]),
        sourceCache: cache
    )

    #expect(variableDecision.isEligible)
    #expect(variableDecision.originalName == "globalCount")
}

@Test func renameEligibilityAnalyzerConsumesRuntimeSemanticsForPublicDeclarations() throws {
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
    ) -> RenameEligibility {
        let symbol = IndexSnapshot.Symbol(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
        let occurrence = IndexSnapshot.Occurrence(
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
        return RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
            group: IndexSnapshot.OccurrenceGroup(usr: usr, symbol: symbol, occurrences: [occurrence]),
            sourceCache: cache,
            semanticIndex: SemanticIndex(runtimeSensitiveUSRs: runtimeSensitiveUSRs)
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

    #expect(objcMembersClass.isEligible == false)
    #expect(objcMembersMethod.isEligible == false)
    #expect(explicitObjCMethod.isEligible == false)
    #expect(dynamicMethod.isEligible == false)
    #expect(objcUSRClass.isEligible == false)
    #expect(
        [objcMembersClass, objcMembersMethod, explicitObjCMethod, dynamicMethod].allSatisfy {
            $0.reasons.contains { $0.contains("runtime-reflected") }
        })
    #expect(objcUSRClass.reasons.contains { $0.contains("Objective-C-compatible USR") })
}

@Test func semanticIndexDoesNotInferRuntimeDispatchFromOverrideSyntax() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let base = IndexSnapshot.Symbol(
        usr: "s:6Sample4BaseC3runyyF",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let child = IndexSnapshot.Symbol(
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
    let childOccurrence = IndexSnapshot.Occurrence(
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
            IndexSnapshot.Relation(
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
    let semanticIndex = SemanticIndex(snapshot: snapshot, obfuscationRoots: [directory])
    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: child.usr, symbol: child, occurrences: [childOccurrence]),
        sourceCache: cache,
        semanticIndex: semanticIndex,
        overrideRelatedUSRs: [base.usr, child.usr],
        coordinatedRelatedUSRs: [base.usr, child.usr]
    )

    #expect(!semanticIndex.runtimeSensitiveUSRs.contains(child.usr))
    #expect(decision.isEligible)
    #expect(!decision.reasons.contains { $0.contains("runtime-reflected") })
}

@Test func renameEligibilityAnalyzerKeepsNarrowLexicalFallbackForExternalLinkageAttributes() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "@_cdecl(\"exported_entry\") public func exportedEntry() {}"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let symbol = IndexSnapshot.Symbol(
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
    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(!decision.isEligible)
    #expect(decision.reasons.contains { $0.contains("externally linked declaration") })
}

@Test func lexicalRuntimeAttributeFallbackIsLimitedToTheAnnotatedDeclaration() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    func decision(usr: String, name: String, kind: String, line: Int) -> RenameEligibility {
        let symbol = IndexSnapshot.Symbol(
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
        return RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
            group: IndexSnapshot.OccurrenceGroup(usr: usr, symbol: symbol, occurrences: [occurrence]),
            sourceCache: cache
        )
    }

    let runtimeNamed = decision(usr: "s:runtime-named", name: "RuntimeNamed", kind: "class", line: 2)
    let designedValue = decision(usr: "s:designed-value", name: "designedValue", kind: "instanceProperty", line: 3)
    let exposed = decision(usr: "s:exposed", name: "exposedToObjectiveC", kind: "function", line: 4)
    let swiftOnly = decision(usr: "s:swift-only", name: "swiftOnly", kind: "function", line: 5)

    #expect(!runtimeNamed.isEligible)
    #expect(!designedValue.isEligible)
    #expect(!exposed.isEligible)
    #expect(swiftOnly.isEligible)
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

    let typeSymbol = IndexSnapshot.Symbol(
        usr: "s:6Sample11PublicModelV",
        name: "PublicModel",
        kind: "struct",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let functionSymbol = IndexSnapshot.Symbol(
        usr: "s:6Sample9makeModelAA06PublicD0VyF",
        name: "makeModel()",
        kind: "function",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let propertySymbol = IndexSnapshot.Symbol(
        usr: "s:6Sample11PublicModelV11displayNameSSvp",
        name: "displayName",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    func occurrence(
        symbol: IndexSnapshot.Symbol,
        tokenName: String,
        line: Int,
        roles: [String]
    ) -> IndexSnapshot.Occurrence {
        IndexSnapshot.Occurrence(
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
        analyzer: RenameEligibilityAnalyzer(sourceRoot: directory),
        mappingStore: RenameMappingStore()
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.rejections.isEmpty)
    #expect(plan.editConflicts.isEmpty)
    #expect(plan.renames.count == 3)
    #expect(Set(plan.renames.map(\.oldName)) == ["PublicModel", "displayName", "makeModel"])

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    let typeName = try #require(plan.renames.first { $0.oldName == "PublicModel" }?.newName)
    let propertyName = try #require(plan.renames.first { $0.oldName == "displayName" }?.newName)
    let functionName = try #require(plan.renames.first { $0.oldName == "makeModel" }?.newName)
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
