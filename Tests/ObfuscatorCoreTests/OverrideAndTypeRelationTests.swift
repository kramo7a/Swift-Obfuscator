import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Overrides and type relations

@Test func renamePlannerIncludesExternalReferencesForSelectedDeclarations() throws {
    let directory = try makeTemporaryDirectory()
    let selectedDirectory = directory.appendingPathComponent("Selected", isDirectory: true)
    let otherDirectory = directory.appendingPathComponent("Other", isDirectory: true)
    try FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)

    let declarationFile = selectedDirectory.appendingPathComponent("Declaration.swift")
    let referenceFile = otherDirectory.appendingPathComponent("Reference.swift")
    let declarationLine = "struct LocalModel {}"
    let referenceLine = "let metatype = LocalModel.self"
    try (declarationLine + "\n").write(to: declarationFile, atomically: true, encoding: .utf8)
    try (referenceLine + "\n").write(to: referenceFile, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [declarationFile.path, referenceFile.path])

    let symbol = SymbolRecord(
        usr: "usr-localModel",
        name: "LocalModel",
        kind: "struct",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let declaration = OccurrenceRecord(
        symbol: symbol,
        path: declarationFile.path,
        line: 1,
        utf8Column: utf8Column(of: "LocalModel", in: declarationLine),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let reference = OccurrenceRecord(
        symbol: symbol,
        path: referenceFile.path,
        line: 1,
        utf8Column: utf8Column(of: "LocalModel", in: referenceLine),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 2,
        roles: ["reference"],
        rolesDescription: "ref",
        symbolProvider: "swift",
        relations: []
    )

    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(
            sourceRoot: directory,
            obfuscationRoots: [declarationFile]
        ),
        mappingStore: MappingStore()
    )
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [declarationFile.path, referenceFile.path],
            symbols: [symbol],
            occurrences: [declaration, reference]
        ),
        sourceCache: cache
    )
    let entry = try #require(plan.entries.first)

    #expect(plan.entries.count == 1)
    #expect(entry.oldName == "LocalModel")
    #expect(entry.newName == "Oa")
    #expect(
        entry.replacements.map(\.path).sorted()
            == [
                SourcePathNormalizer.canonicalPath(declarationFile.path),
                SourcePathNormalizer.canonicalPath(referenceFile.path),
            ].sorted())
    #expect(plan.denied.isEmpty)
}

@Test func renamePlannerCoordinatesClosedOverrideComponents() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let baseSymbol = SymbolRecord(
        usr: "usr-base-run",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let childSymbol = SymbolRecord(
        usr: "usr-child-run",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let baseOccurrence = OccurrenceRecord(
        symbol: baseSymbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "run", in: lines[0]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let childOccurrence = OccurrenceRecord(
        symbol: childSymbol,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "run", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: [
            RelationRecord(
                usr: baseSymbol.usr,
                name: baseSymbol.name,
                rolesRaw: 1,
                roles: ["overrideOf"]
            )
        ]
    )

    let mappingStore = MappingStore()
    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(sourceRoot: directory),
        mappingStore: mappingStore
    )
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [baseSymbol, childSymbol],
            occurrences: [baseOccurrence, childOccurrence]
        ),
        sourceCache: cache
    )

    #expect(plan.conflicts.isEmpty)
    #expect(plan.entries.count == 2)
    #expect(plan.denied.isEmpty)
    #expect(Set(plan.entries.map(\.oldName)) == ["run"])
    #expect(Set(plan.entries.map(\.newName)).count == 1)
    #expect(
        Set(
            [baseSymbol, childSymbol].compactMap {
                mappingStore.entry(for: $0.usr)?.obfuscatedName
            }
        ).count == 1)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    let newName = try #require(plan.entries.first?.newName)
    #expect(patched.contains("func \(newName)()"))
    #expect(patched.contains("override func \(newName)()"))
}

@Test func renamePlannerCoordinatesBaseOfOnlyOverrideComponents() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("BaseOf.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let base = SymbolRecord(
        usr: "usr-base-render",
        name: "render()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let child = SymbolRecord(
        usr: "usr-child-render",
        name: "render()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrences = [
        testOccurrence(
            base,
            path: file.path,
            line: 1,
            token: "render",
            roles: [.definition, .baseOf],
            relations: [
                RelationRecord(
                    usr: child.usr,
                    name: child.name,
                    rolesRaw: 0,
                    roles: ["baseOf"]
                )
            ]
        ),
        testOccurrence(child, path: file.path, line: 2, token: "render", roles: [.definition]),
    ]
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [base, child],
            occurrences: occurrences
        ),
        sourceCache: cache
    )

    #expect(plan.conflicts.isEmpty)
    #expect(plan.entries.count == 2)
    #expect(Set(plan.entries.map(\.newName)).count == 1)
    #expect(plan.denied.isEmpty)
}

@Test func renamePlannerRenamesNominalClassHierarchyWithoutCoordinatingTypeNames() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ClassHierarchy.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let base = SymbolRecord(
        usr: "usr-base-class",
        name: "Base",
        kind: "class",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let child = SymbolRecord(
        usr: "usr-child-class",
        name: "Child",
        kind: "class",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrences = [
        testOccurrence(
            base,
            path: file.path,
            line: 1,
            token: "Base",
            roles: [.definition, .baseOf],
            relations: [
                RelationRecord(
                    usr: child.usr,
                    name: child.name,
                    rolesRaw: 0,
                    roles: ["baseOf"]
                )
            ]
        ),
        testOccurrence(child, path: file.path, line: 2, token: "Child", roles: [.definition]),
        testOccurrence(base, path: file.path, line: 2, token: "Base", roles: [.reference]),
    ]
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [base, child],
            occurrences: occurrences
        ),
        sourceCache: cache
    )
    let entries = plan.entries.filter { $0.usr == base.usr || $0.usr == child.usr }

    #expect(entries.count == 2)
    #expect(Set(entries.map(\.newName)).count == 2)
    #expect(plan.denied.allSatisfy { $0.usr != base.usr && $0.usr != child.usr })
}

@Test func renamePlannerDeniesOverrideComponentThatLeavesSelectedSourceRoots() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ExternalBase.swift")
    let line = "class Child: ExternalBase { override func run() {} }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let child = SymbolRecord(
        usr: "usr-local-child-run",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let externalBaseUSR = "s:15ExternalPackage0A4BaseC3runyyF"
    let occurrence = testOccurrence(
        child,
        path: file.path,
        line: 1,
        token: "run",
        roles: [.definition, .overrideOf],
        relations: [
            RelationRecord(
                usr: externalBaseUSR,
                name: "run()",
                rolesRaw: 0,
                roles: ["overrideOf"]
            )
        ]
    )
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [child],
            occurrences: [occurrence]
        ),
        sourceCache: cache
    )

    #expect(plan.entries.isEmpty)
    let denial = try #require(plan.denied.first { $0.usr == child.usr })
    #expect(
        denial.reasons.contains { reason in
            reason.contains("coordinated override/base component denied atomically")
                && reason.contains("no indexed occurrence group: \(externalBaseUSR)")
        })
}

@Test func renamePlannerDeniesOverrideComponentThatReachesObjectiveCRuntimeDispatch() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("RuntimeOverride.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let base = SymbolRecord(
        usr: "c:@M@Sample@objc(cs)LegacyBase(im)run",
        name: "run()",
        kind: "instanceMethod",
        language: "objective-c",
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
    let occurrences = [
        testOccurrence(base, path: file.path, line: 1, token: "run", roles: [.definition]),
        testOccurrence(
            child,
            path: file.path,
            line: 2,
            token: "run",
            roles: [.definition, .overrideOf],
            relations: [
                RelationRecord(
                    usr: base.usr,
                    name: base.name,
                    rolesRaw: 0,
                    roles: ["overrideOf"]
                )
            ]
        ),
    ]
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [base, child],
            occurrences: occurrences
        ),
        sourceCache: cache
    )

    #expect(plan.entries.isEmpty)
    #expect(plan.denied.count == 2)
    #expect(
        plan.denied.allSatisfy { decision in
            decision.reasons.contains { $0.contains("coordinated override/base component denied atomically") }
        })
    #expect(
        plan.denied.contains { decision in
            decision.usr == child.usr
                && decision.reasons.contains { $0.contains("runtime-reflected") }
        })
}

@Test func renamePlannerDistinguishesTupleAndFunctionTypealiasesByCompilerSyntax() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = SymbolRecord(
        usr: "usr-namespace",
        name: "Namespace",
        kind: "enum",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let payloadTypealias = SymbolRecord(
        usr: "usr-payload",
        name: "Payload",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let handlerTypealias = SymbolRecord(
        usr: "usr-handler",
        name: "Handler",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let ownerOccurrence = OccurrenceRecord(
        symbol: owner,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "Namespace", in: lines[0]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let payloadTypealiasOccurrence = OccurrenceRecord(
        symbol: payloadTypealias,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "Payload", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: [
            RelationRecord(usr: owner.usr, name: owner.name, rolesRaw: 1, roles: ["childOf"])
        ]
    )
    let handlerTypealiasOccurrence = OccurrenceRecord(
        symbol: handlerTypealias,
        path: file.path,
        line: 3,
        utf8Column: utf8Column(of: "Handler", in: lines[2]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: [
            RelationRecord(usr: owner.usr, name: owner.name, rolesRaw: 1, roles: ["childOf"])
        ]
    )
    let handlerReference = OccurrenceRecord(
        symbol: handlerTypealias,
        path: file.path,
        line: 7,
        utf8Column: utf8Column(of: "Handler", in: lines[6]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 4,
        roles: ["reference"],
        rolesDescription: "ref",
        symbolProvider: "swift",
        relations: []
    )

    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(sourceRoot: directory),
        mappingStore: MappingStore()
    )
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, payloadTypealias, handlerTypealias],
            occurrences: [
                ownerOccurrence,
                payloadTypealiasOccurrence,
                handlerTypealiasOccurrence,
                handlerReference,
            ]
        ),
        sourceCache: cache
    )

    let handlerEntry = try #require(plan.entries.first { $0.usr == handlerTypealias.usr })
    #expect(handlerEntry.replacements.count == 2)
    #expect(plan.denied.count == 2)
    #expect(plan.denied.allSatisfy { $0.reasons.contains("tuple typealias constructor occurrences are incomplete") })
    #expect(Set(plan.denied.map(\.usr)) == [owner.usr, payloadTypealias.usr])
    #expect(plan.typealiasSyntaxFacts.directTupleTypealiases == 1)
    #expect(plan.typealiasSyntaxFacts.functionTypealiases == 1)
    #expect(plan.typealiasSyntaxFacts.tupleRelatedOwnerUSRs == 1)
    #expect(plan.typealiasSyntaxFacts.unresolvedTypealiasDeclarations == 0)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("typealias \(handlerEntry.newName) =\n        (Int) -> Void"))
    #expect(patched.contains("Namespace.\(handlerEntry.newName)"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func renamePlannerDoesNotSelectSymbolsDeclaredOutsideSelectedSources() throws {
    let directory = try makeTemporaryDirectory()
    let selectedDirectory = directory.appendingPathComponent("Selected", isDirectory: true)
    let otherDirectory = directory.appendingPathComponent("Other", isDirectory: true)
    try FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)

    let selectedFile = selectedDirectory.appendingPathComponent("Reference.swift")
    let declarationFile = otherDirectory.appendingPathComponent("Declaration.swift")
    let selectedLine = "let metatype = ExternalModel.self"
    let declarationLine = "struct ExternalModel {}"
    try (selectedLine + "\n").write(to: selectedFile, atomically: true, encoding: .utf8)
    try (declarationLine + "\n").write(to: declarationFile, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [selectedFile.path, declarationFile.path])

    let symbol = SymbolRecord(
        usr: "usr-externalModel",
        name: "ExternalModel",
        kind: "struct",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let reference = OccurrenceRecord(
        symbol: symbol,
        path: selectedFile.path,
        line: 1,
        utf8Column: utf8Column(of: "ExternalModel", in: selectedLine),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 2,
        roles: ["reference"],
        rolesDescription: "ref",
        symbolProvider: "swift",
        relations: []
    )
    let declaration = OccurrenceRecord(
        symbol: symbol,
        path: declarationFile.path,
        line: 1,
        utf8Column: utf8Column(of: "ExternalModel", in: declarationLine),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(
            sourceRoot: directory,
            obfuscationRoots: [selectedFile]
        ),
        mappingStore: MappingStore()
    )
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [selectedFile.path, declarationFile.path],
            symbols: [symbol],
            occurrences: [reference, declaration]
        ),
        sourceCache: cache
    )

    #expect(plan.entries.isEmpty)
    #expect(plan.denied.count == 1)
    #expect(
        plan.denied.first?.reasons.contains {
            $0.contains("no declaration or definition occurrence inside selected source roots")
        } == true)
}
