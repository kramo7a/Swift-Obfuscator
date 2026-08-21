import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Protocol and override coordination

@Test func renameEligibilityAnalyzerDeniesProtocolMembersUntilWitnessesAreRenamedTogether() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-run",
        name: "run",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
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

    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(
            usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        semanticIndex: SemanticIndex(protocolRequirementUSRs: [symbol.usr])
    )

    #expect(decision.isEligible == false)
    #expect(decision.reasons.contains("protocol members require relation-aware witness renaming"))
}

@Test func renameEligibilityAnalyzerAllowsProtocolNominalConformanceReferences() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-analyzer",
        name: "Analyzer",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let declaration = IndexSnapshot.Occurrence(
        symbol: symbol,
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
    let conformanceReference = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "Analyzer", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 2,
        roles: ["reference"],
        rolesDescription: "ref",
        symbolProvider: "swift",
        relations: [
            IndexSnapshot.Relation(
                usr: "usr-runner",
                name: "Runner",
                rolesRaw: 1,
                roles: ["baseOf"]
            )
        ]
    )

    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(
            usr: symbol.usr, symbol: symbol, occurrences: [declaration, conformanceReference]),
        sourceCache: cache
    )

    #expect(decision.isEligible == true)
    #expect(decision.originalName == "Analyzer")
}

@Test func renameEligibilityAnalyzerDeniesLocalProtocolMembersUntilWitnessesAreRenamedTogether()
    throws
{
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "enum Interval { fileprivate protocol Quality { var title: String { get } } }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-title",
        name: "title",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "title", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: IndexSnapshot.OccurrenceGroup(
            usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        semanticIndex: SemanticIndex(protocolRequirementUSRs: [symbol.usr])
    )

    #expect(decision.isEligible == false)
    #expect(decision.reasons.contains("protocol members require relation-aware witness renaming"))
}

@Test func renamePlannerCoordinatesClosedProtocolRequirementsAndWitnesses() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ProtocolWitnesses.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let protocolSymbol = IndexSnapshot.Symbol(
        usr: "usr-analyzer-protocol",
        name: "Analyzer",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = IndexSnapshot.Symbol(
        usr: "usr-analyzer-run-requirement",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let firstWitness = IndexSnapshot.Symbol(
        usr: "usr-first-run-witness",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let secondWitness = IndexSnapshot.Symbol(
        usr: "usr-second-run-witness",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let childOfProtocol = IndexSnapshot.Relation(
        usr: protocolSymbol.usr,
        name: protocolSymbol.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let overridesRequirement = IndexSnapshot.Relation(
        usr: requirement.usr,
        name: requirement.name,
        rolesRaw: 0,
        roles: ["overrideOf"]
    )

    let occurrences = [
        testOccurrence(
            protocolSymbol, path: file.path, line: 1, token: "Analyzer", roles: [.definition]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 2,
            token: "run",
            roles: [.definition, .childOf],
            relations: [childOfProtocol]
        ),
        testOccurrence(
            firstWitness,
            path: file.path,
            line: 4,
            token: "run",
            roles: [.definition, .overrideOf],
            relations: [overridesRequirement]
        ),
        // This is a semantic conformance edge located at the owner token,
        // not another spelling of `run`; the planner must not patch `First`.
        testOccurrence(
            firstWitness,
            path: file.path,
            line: 4,
            token: "First",
            roles: [.implicit, .overrideOf, .containedBy],
            relations: [overridesRequirement]
        ),
        testOccurrence(
            secondWitness,
            path: file.path,
            line: 5,
            token: "run",
            roles: [.definition, .overrideOf],
            relations: [overridesRequirement]
        ),
        testOccurrence(
            requirement, path: file.path, line: 6, token: "run", roles: [.reference, .call]),
        testOccurrence(
            firstWitness, path: file.path, line: 7, token: "run", roles: [.reference, .call]),
        testOccurrence(
            secondWitness, path: file.path, line: 8, token: "run", roles: [.reference, .call]),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [protocolSymbol, requirement, firstWitness, secondWitness],
        occurrences: occurrences
    )
    let mappingStore = RenameMappingStore()
    var planner = RenamePlanner(
        analyzer: RenameEligibilityAnalyzer(sourceRoot: directory),
        mappingStore: mappingStore
    )

    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let componentEntries = plan.renames.filter {
        [requirement.usr, firstWitness.usr, secondWitness.usr].contains($0.usr)
    }

    #expect(plan.editConflicts.isEmpty)
    #expect(componentEntries.count == 3)
    #expect(Set(componentEntries.map(\.oldName)) == ["run"])
    #expect(Set(componentEntries.map(\.newName)).count == 1)
    #expect(
        plan.rejections.allSatisfy {
            ![requirement.usr, firstWitness.usr, secondWitness.usr].contains($0.usr)
        })
    #expect(
        Set(
            [requirement, firstWitness, secondWitness].compactMap {
                mappingStore.rename(for: $0.usr)?.obfuscatedName
            }
        ).count == 1)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    let newName = try #require(componentEntries.first?.newName)
    #expect(patched.contains("protocol Oa"))
    #expect(patched.contains("func \(newName)()"))
    #expect(patched.contains("First().\(newName)()"))
    #expect(patched.contains("Second().\(newName)()"))
    #expect(patched.contains("struct First:"))
}

@Test func renamePlannerDoesNotApplyStoredPropertyDenialToProtocolRequirements() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ProtocolProperty.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = IndexSnapshot.Symbol(
        usr: "usr-payload-protocol",
        name: "Payload",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = IndexSnapshot.Symbol(
        usr: "usr-payload-value-requirement",
        name: "value",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let witness = IndexSnapshot.Symbol(
        usr: "usr-model-value-witness",
        name: "value",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrences = [
        testOccurrence(owner, path: file.path, line: 1, token: "Payload", roles: [.definition]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 2,
            token: "value",
            roles: [.definition, .childOf],
            relations: [
                IndexSnapshot.Relation(
                    usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["childOf"])
            ]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 5,
            token: "value",
            roles: [.definition, .overrideOf],
            relations: [
                IndexSnapshot.Relation(
                    usr: requirement.usr,
                    name: requirement.name,
                    rolesRaw: 0,
                    roles: ["overrideOf"]
                )
            ]
        ),
    ]
    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, requirement, witness],
            occurrences: occurrences
        ),
        sourceCache: cache
    )
    let entries = plan.renames.filter { $0.usr == requirement.usr || $0.usr == witness.usr }

    #expect(entries.count == 2)
    #expect(Set(entries.map(\.newName)).count == 1)
    #expect(
        !plan.rejections.contains { decision in
            (decision.usr == requirement.usr || decision.usr == witness.usr)
                && decision.reasons.contains(where: { $0.contains("memberwise initializer") })
        })
}

@Test func renamePlannerKeepsProtocolAssociatedTypeWitnessesInTheSemanticOverrideGraph() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("AssociatedType.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = IndexSnapshot.Symbol(
        usr: "usr-payload",
        name: "Payload",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = IndexSnapshot.Symbol(
        usr: "usr-payload-dto",
        name: "DTO",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let witness = IndexSnapshot.Symbol(
        usr: "usr-message-dto",
        name: "DTO",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrences = [
        testOccurrence(owner, path: file.path, line: 1, token: "Payload", roles: [.definition]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 1,
            token: "DTO",
            roles: [.definition, .childOf],
            relations: [
                IndexSnapshot.Relation(
                    usr: owner.usr,
                    name: owner.name,
                    rolesRaw: 0,
                    roles: ["childOf"]
                )
            ]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 2,
            token: "DTO",
            roles: [.definition, .overrideOf, .baseOf],
            relations: [
                IndexSnapshot.Relation(
                    usr: requirement.usr,
                    name: requirement.name,
                    rolesRaw: 0,
                    roles: ["overrideOf"]
                ),
                IndexSnapshot.Relation(
                    usr: requirement.usr,
                    name: requirement.name,
                    rolesRaw: 0,
                    roles: ["baseOf"]
                ),
            ]
        ),
    ]
    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, requirement, witness],
            occurrences: occurrences
        ),
        sourceCache: cache
    )
    let entries = plan.renames.filter { $0.usr == requirement.usr || $0.usr == witness.usr }

    #expect(entries.count == 2)
    #expect(Set(entries.map(\.newName)).count == 1)
    #expect(plan.rejections.allSatisfy { $0.usr != requirement.usr && $0.usr != witness.usr })
}

@Test func renamePlannerDeniesProtocolFamilyThatReachesExternalRequirement() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ExternalRequirement.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = IndexSnapshot.Symbol(
        usr: "usr-local-service",
        name: "LocalService",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = IndexSnapshot.Symbol(
        usr: "usr-local-send",
        name: "send()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let witness = IndexSnapshot.Symbol(
        usr: "usr-client-send",
        name: "send()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let localOverride = IndexSnapshot.Relation(
        usr: requirement.usr,
        name: requirement.name,
        rolesRaw: 0,
        roles: ["overrideOf"]
    )
    let externalOverride = IndexSnapshot.Relation(
        usr: "s:15ExternalPackage0A7ServiceP4sendyyF",
        name: "send()",
        rolesRaw: 0,
        roles: ["overrideOf"]
    )
    let occurrences = [
        testOccurrence(
            owner, path: file.path, line: 1, token: "LocalService", roles: [.definition]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 1,
            token: "send",
            roles: [.definition, .childOf],
            relations: [
                IndexSnapshot.Relation(
                    usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["childOf"])
            ]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 2,
            token: "send",
            roles: [.definition, .overrideOf],
            relations: [localOverride, externalOverride]
        ),
    ]
    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, requirement, witness],
            occurrences: occurrences
        ),
        sourceCache: cache
    )
    let componentUSRs = Set([requirement.usr, witness.usr])
    let componentDenials = plan.rejections.filter { componentUSRs.contains($0.usr) }

    #expect(plan.renames.allSatisfy { !componentUSRs.contains($0.usr) })
    #expect(componentDenials.count == 2)
    #expect(
        componentDenials.allSatisfy { decision in
            decision.reasons.contains(where: {
                $0.contains("coordinated component denied atomically")
                    && $0.contains("no indexed occurrence group")
            })
        })
}

@Test func renamePlannerKeepsObjectiveCProtocolRequirementsDenied() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ObjectiveCProtocol.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = IndexSnapshot.Symbol(
        usr: "c:@M@Sample@objc(pl)LegacyService",
        name: "LegacyService",
        kind: "protocol",
        language: "objective-c",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = IndexSnapshot.Symbol(
        usr: "c:@M@Sample@objc(pl)LegacyService(im)ping",
        name: "ping()",
        kind: "instanceMethod",
        language: "objective-c",
        propertiesRaw: 0,
        properties: "[]"
    )
    let witness = IndexSnapshot.Symbol(
        usr: "s:6Sample7AdapterC4pingyyF",
        name: "ping()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrences = [
        testOccurrence(
            owner, path: file.path, line: 1, token: "LegacyService", roles: [.definition]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 1,
            token: "ping",
            roles: [.definition, .childOf],
            relations: [
                IndexSnapshot.Relation(
                    usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["childOf"])
            ]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 2,
            token: "ping",
            roles: [.definition, .overrideOf],
            relations: [
                IndexSnapshot.Relation(
                    usr: requirement.usr,
                    name: requirement.name,
                    rolesRaw: 0,
                    roles: ["overrideOf"]
                )
            ]
        ),
    ]
    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, requirement, witness],
            occurrences: occurrences
        ),
        sourceCache: cache
    )

    #expect(plan.renames.allSatisfy { $0.usr != requirement.usr && $0.usr != witness.usr })
    #expect(
        plan.rejections.contains { decision in
            decision.usr == requirement.usr
                && decision.reasons.contains(
                    "Objective-C-compatible USR requires a stable runtime name")
        })
    #expect(
        plan.rejections.contains { decision in
            decision.usr == witness.usr
                && decision.reasons.contains("override relations require coordinated renaming")
        })
}
