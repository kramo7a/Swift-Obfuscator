import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Enum-case planning

@Test func enumCaseComponentFactsUseIndexedOwnersAndSemanticContracts() throws {
    let root = URL(fileURLWithPath: "/tmp/enum-case-component-facts", isDirectory: true)
    let insidePath = root.appendingPathComponent("Enums.swift").path
    let outsidePath = "/tmp/enum-case-component-facts-outside.swift"

    func occurrence(
        _ symbol: SymbolRecord,
        path: String = insidePath,
        roles: [String],
        relations: [RelationRecord] = []
    ) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: path,
            line: 1,
            utf8Column: 1,
            moduleName: "EnumFacts",
            isSystem: false,
            rolesRaw: 0,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relations
        )
    }

    let plainOwner = testSymbol("s:plain-owner", "Plain", .enum)
    let plainCase = testSymbol("s:plain-case", "ready", .enumConstant)
    let payloadCase = testSymbol("s:payload-case", "payload(value:)", .enumConstant)
    let payloadParameter = testSymbol("s:payload-parameter", "value", .parameter)
    let rawOwner = testSymbol("s:raw-owner", "Raw", .enum)
    let rawCase = testSymbol("s:raw-case", "wire", .enumConstant)
    let rawType = testSymbol("s:raw-type", "WireValue", .struct)
    let serializedOwner = testSymbol("s:serialized-owner", "Serialized", .enum)
    let serializedCase = testSymbol("s:serialized-case", "stored", .enumConstant)
    let decodable = testSymbol("s:Se", "Decodable", .protocol)
    let runtimeOwner = testSymbol("c:@E@Runtime", "Runtime", .enum)
    let runtimeCase = testSymbol("c:@E@Runtime@RuntimeCase", "runtime", .enumConstant)

    let snapshot = IndexSnapshot(
        sourceFiles: [insidePath, outsidePath],
        symbols: [
            plainOwner, plainCase, payloadCase, payloadParameter,
            rawOwner, rawCase, rawType,
            serializedOwner, serializedCase, decodable,
            runtimeOwner, runtimeCase,
        ],
        occurrences: [
            occurrence(plainOwner, roles: ["definition"]),
            occurrence(
                plainCase, roles: ["definition"],
                relations: [
                    testRelation(plainOwner, .childOf)
                ]),
            occurrence(plainCase, path: outsidePath, roles: ["reference"]),
            occurrence(
                payloadCase, roles: ["definition"],
                relations: [
                    testRelation(plainOwner, .childOf)
                ]),
            occurrence(
                payloadParameter, roles: ["definition"],
                relations: [
                    testRelation(payloadCase, .childOf)
                ]),
            occurrence(rawOwner, roles: ["definition"]),
            occurrence(
                rawType, roles: ["reference", "baseOf"],
                relations: [
                    testRelation(rawOwner, .baseOf)
                ]),
            occurrence(
                rawCase, roles: ["definition"],
                relations: [
                    testRelation(rawOwner, .childOf)
                ]),
            occurrence(serializedOwner, roles: ["definition"]),
            occurrence(
                decodable, roles: ["reference", "implicit", "baseOf"],
                relations: [
                    testRelation(serializedOwner, .baseOf)
                ]),
            occurrence(
                serializedCase, roles: ["definition"],
                relations: [
                    testRelation(serializedOwner, .childOf)
                ]),
            occurrence(runtimeOwner, roles: ["definition"]),
            occurrence(
                runtimeCase, roles: ["definition"],
                relations: [
                    testRelation(runtimeOwner, .childOf)
                ]),
        ]
    )
    let indexedFacts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [root])
    let facts = EnumCaseComponentFacts(
        snapshot: snapshot,
        indexedFacts: indexedFacts,
        obfuscationRoots: [root]
    )

    #expect(facts.summary.explicitEnumCases == 5)
    #expect(facts.summary.resolvedEnumCases == 5)
    #expect(facts.summary.unresolvedEnumCases == 0)
    #expect(facts.summary.ownerComponents == 4)
    #expect(facts.summary.rawTypeOwnerComponents == 1)
    #expect(facts.summary.rawTypeCases == 1)
    #expect(facts.summary.protocolConformanceOwnerComponents == 1)
    #expect(facts.summary.protocolConformanceCases == 1)
    #expect(facts.summary.protocolWitnessOwnerComponents == 0)
    #expect(facts.summary.protocolWitnessCases == 0)
    #expect(facts.summary.serializationSensitiveOwnerComponents == 1)
    #expect(facts.summary.serializationSensitiveCases == 1)
    #expect(facts.summary.runtimeSensitiveOwnerComponents == 1)
    #expect(facts.summary.runtimeSensitiveCases == 1)
    #expect(facts.summary.ownerComponentsWithOccurrencesOutsideSelectedRoots == 1)
    #expect(facts.summary.casesWithOccurrencesOutsideSelectedRoots == 2)
    #expect(facts.summary.associatedValueCases == 1)
    #expect(facts.summary.associatedValueParameters == 1)
    #expect(facts.summary.casesWithoutRawSerializationOrRuntimeContracts == 2)

    let plain = try #require(facts.components.first { $0.ownerUSR == plainOwner.usr })
    #expect(plain.caseUSRs == [payloadCase.usr, plainCase.usr].sorted())
    #expect(plain.associatedValueParameterUSRs == [payloadParameter.usr])
    #expect(plain.hasOccurrencesOutsideSelectedRoots)

    let raw = try #require(facts.components.first { $0.ownerUSR == rawOwner.usr })
    #expect(raw.rawTypeUSRs == [rawType.usr])
    #expect(!raw.isSerializationSensitive)

    let serialized = try #require(
        facts.components.first { $0.ownerUSR == serializedOwner.usr }
    )
    #expect(serialized.protocolConformanceUSRs == [decodable.usr])
    #expect(serialized.isSerializationSensitive)

    let runtime = try #require(facts.components.first { $0.ownerUSR == runtimeOwner.usr })
    #expect(runtime.isRuntimeSensitive)
}

@Test func enumCaseSyntaxFactsAllowSourceClosedVisibilityAndProtectExternalReferences() throws {
    let directory = try makeTemporaryDirectory()
    let outsideDirectory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("EnumSyntax.swift")
    try copyFixture(to: file)
    let outsideFile = outsideDirectory.appendingPathComponent("ExternalUse.swift")
    try "let escaped = Escaping.exported\n"
        .write(to: outsideFile, atomically: true, encoding: .utf8)

    let safe = testSymbol("s:safe", "Safe", .enum)
    let idle = testSymbol("s:safe-idle", "idle", .enumConstant)
    let payload = testSymbol("s:safe-payload", "payload(value:)", .enumConstant)
    let value = testSymbol("s:safe-payload-value", "value", .parameter)
    let reflected = testSymbol("s:reflected", "Reflected", .enum)
    let logged = testSymbol("s:reflected-logged", "logged", .enumConstant)
    let visible = testSymbol("s:visible", "Visible", .enum)
    let shown = testSymbol("s:visible-shown", "shown", .enumConstant)
    let attributed = testSymbol("s:attributed", "Attributed", .enum)
    let marked = testSymbol("s:attributed-marked", "marked", .enumConstant)
    let conforming = testSymbol("s:conforming", "Conforming", .enum)
    let equal = testSymbol("s:conforming-equal", "equal", .enumConstant)
    let equatable = testSymbol("s:SQ", "Equatable", .protocol)
    let escaping = testSymbol("s:escaping", "Escaping", .enum)
    let exported = testSymbol("s:escaping-exported", "exported", .enumConstant)

    let occurrences = [
        testOccurrence(safe, path: file.path, line: 1, token: "Safe", roles: [.definition]),
        testOccurrence(
            idle, path: file.path, line: 2, token: "idle", roles: [.definition], relations: [childOf(safe)]),
        testOccurrence(
            payload, path: file.path, line: 3, token: "payload", roles: [.definition], relations: [childOf(safe)]),
        testOccurrence(
            value, path: file.path, line: 3, token: "value", roles: [.definition], relations: [childOf(payload)]),
        testOccurrence(idle, path: file.path, line: 6, token: "idle", roles: [.reference]),
        testOccurrence(payload, path: file.path, line: 7, token: "payload", roles: [.reference]),
        testOccurrence(reflected, path: file.path, line: 11, token: "Reflected", roles: [.definition]),
        testOccurrence(
            logged, path: file.path, line: 12, token: "logged", roles: [.definition], relations: [childOf(reflected)]),
        testOccurrence(logged, path: file.path, line: 14, token: "logged", roles: [.reference]),
        testOccurrence(visible, path: file.path, line: 16, token: "Visible", roles: [.definition]),
        testOccurrence(
            shown, path: file.path, line: 17, token: "shown", roles: [.definition], relations: [childOf(visible)]),
        testOccurrence(attributed, path: file.path, line: 20, token: "Attributed", roles: [.definition]),
        testOccurrence(
            marked, path: file.path, line: 21, token: "marked", roles: [.definition], relations: [childOf(attributed)]),
        testOccurrence(conforming, path: file.path, line: 23, token: "Conforming", roles: [.definition]),
        testOccurrence(
            equatable, path: file.path, line: 23, token: "Equatable", roles: [.reference, .baseOf],
            relations: [baseOf(conforming)]),
        testOccurrence(
            equal, path: file.path, line: 24, token: "equal", roles: [.definition], relations: [childOf(conforming)]),
        testOccurrence(escaping, path: file.path, line: 26, token: "Escaping", roles: [.definition]),
        testOccurrence(
            exported, path: file.path, line: 27, token: "exported", roles: [.definition],
            relations: [childOf(escaping)]),
        testOccurrence(exported, path: outsideFile.path, line: 1, token: "exported", roles: [.reference]),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path, outsideFile.path],
        symbols: [
            safe, idle, payload, value,
            reflected, logged,
            visible, shown,
            attributed, marked,
            conforming, equal, equatable,
            escaping, exported,
        ],
        occurrences: occurrences
    )
    let cache = try SourceFileCache(paths: [file.path])
    let indexedFacts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])
    let semanticFacts = EnumCaseComponentFacts(
        snapshot: snapshot,
        indexedFacts: indexedFacts,
        obfuscationRoots: [directory]
    )
    let facts = EnumCaseSyntaxFacts(
        snapshot: snapshot,
        semanticFacts: semanticFacts,
        sourceCache: cache,
        obfuscationRoots: [directory]
    )

    #expect(facts.summary.explicitEnumCases == 7)
    #expect(facts.summary.resolvedEnumCases == 7)
    #expect(facts.summary.unresolvedEnumCases == 0)
    #expect(facts.summary.indexedReferenceOccurrences == 3)
    #expect(facts.summary.resolvedReferenceOccurrences == 3)
    #expect(facts.summary.unresolvedReferenceOccurrences == 0)
    #expect(facts.summary.casesWithMatchingStringLiterals == 1)
    #expect(facts.summary.casesDirectlyInterpolated == 1)
    #expect(facts.summary.preliminaryEligibleOwnerComponents == 3)
    #expect(facts.summary.preliminaryEligibleCases == 4)
    #expect(facts.summary.preliminaryEligibleSimpleCases == 3)
    #expect(facts.summary.preliminaryEligibleAssociatedValueCases == 1)
    #expect(facts.summary.preliminaryEligibleAssociatedValueParameters == 1)

    let safeFacts = try #require(facts.components.first { $0.ownerUSR == safe.usr })
    #expect(safeFacts.accessLevel == .private)
    #expect(safeFacts.blockers.isEmpty)

    let reflectedFacts = try #require(
        facts.components.first { $0.ownerUSR == reflected.usr }
    )
    #expect(reflectedFacts.blockers.contains(.directStringInterpolation))
    let loggedFacts = try #require(
        reflectedFacts.members.first { $0.caseUSR == logged.usr }
    )
    #expect(loggedFacts.blockers == [.stringLiteralSpelling])

    let visibleFacts = try #require(facts.components.first { $0.ownerUSR == visible.usr })
    #expect(visibleFacts.accessLevel == .public)
    #expect(visibleFacts.blockers.isEmpty)

    let escapingFacts = try #require(
        facts.components.first { $0.ownerUSR == escaping.usr }
    )
    #expect(escapingFacts.accessLevel == .public)
    #expect(escapingFacts.blockers.contains(.occurrenceLeavesSelectedRoots))

    let attributedFacts = try #require(
        facts.components.first { $0.ownerUSR == attributed.usr }
    )
    #expect(attributedFacts.blockers.contains(.declarationAttribute))

    let conformingFacts = try #require(
        facts.components.first { $0.ownerUSR == conforming.usr }
    )
    #expect(conformingFacts.blockers.isEmpty)
}

@Test func enumCasePlannerCoordinatesInternalAssociatedLabelsWithoutRenamingPatternBindings() throws {
    let directory = try makeTemporaryDirectory()
    let declarationsFile = directory.appendingPathComponent("Declarations.swift")
    try copyFixture(to: declarationsFile)
    let usesFile = directory.appendingPathComponent("Uses.swift")
    try copyFixture(to: usesFile)

    let internalOwner = testSymbol("s:internal-state", "InternalState", .enum)
    let idle = testSymbol("s:internal-state-idle", "idle", .enumConstant)
    let ready = testSymbol("s:internal-state-ready", "ready", .enumConstant)
    let payloadOwner = testSymbol("s:internal-payload", "InternalPayload", .enum)
    let payload = testSymbol("s:internal-payload-case", "payload(value:)", .enumConstant)
    let value = testSymbol("s:internal-payload-value", "value", .parameter)
    let publicOwner = testSymbol("s:public-state", "PublicState", .enum)
    let visible = testSymbol("s:public-state-visible", "visible", .enumConstant)

    let occurrences = [
        testOccurrence(
            internalOwner,
            path: declarationsFile.path,
            line: 1,
            token: "InternalState",
            roles: [.definition]
        ),
        testOccurrence(
            idle,
            path: declarationsFile.path,
            line: 2,
            token: "idle",
            roles: [.definition],
            relations: [childOf(internalOwner)]
        ),
        testOccurrence(
            ready,
            path: declarationsFile.path,
            line: 3,
            token: "ready",
            roles: [.definition],
            relations: [childOf(internalOwner)]
        ),
        testOccurrence(
            payloadOwner,
            path: declarationsFile.path,
            line: 5,
            token: "InternalPayload",
            roles: [.definition]
        ),
        testOccurrence(
            payload,
            path: declarationsFile.path,
            line: 6,
            token: "payload",
            roles: [.definition],
            relations: [childOf(payloadOwner)]
        ),
        testOccurrence(
            value,
            path: declarationsFile.path,
            line: 6,
            token: "value",
            roles: [.definition],
            relations: [childOf(payload)]
        ),
        testOccurrence(
            publicOwner,
            path: declarationsFile.path,
            line: 8,
            token: "PublicState",
            roles: [.definition]
        ),
        testOccurrence(
            visible,
            path: declarationsFile.path,
            line: 9,
            token: "visible",
            roles: [.definition],
            relations: [childOf(publicOwner)]
        ),
        testOccurrence(
            internalOwner,
            path: usesFile.path,
            line: 1,
            token: "InternalState",
            roles: [.reference]
        ),
        testOccurrence(
            ready,
            path: usesFile.path,
            line: 2,
            token: "ready",
            roles: [.reference]
        ),
        testOccurrence(
            internalOwner,
            path: usesFile.path,
            line: 4,
            token: "InternalState",
            roles: [.reference]
        ),
        testOccurrence(
            idle,
            path: usesFile.path,
            line: 4,
            token: "idle",
            roles: [.reference]
        ),
        testOccurrence(
            payloadOwner,
            path: usesFile.path,
            line: 5,
            token: "InternalPayload",
            roles: [.reference]
        ),
        testOccurrence(
            payload,
            path: usesFile.path,
            line: 5,
            token: "payload",
            roles: [.reference, .call]
        ),
        testOccurrence(
            payloadOwner,
            path: usesFile.path,
            line: 6,
            token: "InternalPayload",
            roles: [.reference]
        ),
        testOccurrence(
            payload,
            path: usesFile.path,
            line: 8,
            token: "payload",
            roles: [.reference]
        ),
        testOccurrence(
            payloadOwner,
            path: usesFile.path,
            line: 12,
            token: "InternalPayload",
            roles: [.reference]
        ),
        testOccurrence(
            payload,
            path: usesFile.path,
            line: 14,
            token: "payload",
            roles: [.reference]
        ),
        testOccurrence(
            payloadOwner,
            path: usesFile.path,
            line: 18,
            token: "InternalPayload",
            roles: [.reference]
        ),
        testOccurrence(
            payload,
            path: usesFile.path,
            line: 20,
            token: "payload",
            roles: [.reference]
        ),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [declarationsFile.path, usesFile.path],
        symbols: [
            internalOwner, idle, ready,
            payloadOwner, payload, value,
            publicOwner, visible,
        ],
        occurrences: occurrences
    )
    let cache = try SourceFileCache(paths: [declarationsFile.path, usesFile.path])
    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(sourceRoot: directory),
        generator: NameGenerator(prefix: "Case")
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let internalEntries = plan.entries.filter {
        [idle.usr, ready.usr, payload.usr].contains($0.usr)
    }
    #expect(internalEntries.count == 3)
    #expect(internalEntries.flatMap(\.replacements).count == 9)
    let valueEntry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(valueEntry.replacements.count == 3)
    let visibleEntry = try #require(plan.entries.first { $0.usr == visible.usr })
    #expect(visibleEntry.replacements.count == 1)
    #expect(plan.enumCaseSyntaxFacts.preliminaryEligibleOwnerComponents == 3)
    #expect(plan.enumCaseSyntaxFacts.preliminaryEligibleCases == 4)
    #expect(plan.enumCaseSyntaxFacts.preliminaryEligibleSimpleCases == 3)
    #expect(plan.enumCaseSyntaxFacts.preliminaryEligibleAssociatedValueCases == 1)
    #expect(plan.enumCaseSyntaxFacts.preliminaryEligibleAssociatedValueParameters == 1)
    #expect(plan.parameterCallSiteSyntaxFacts.resolvedEnumCasePatterns == 1)
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patchedDeclarations = try String(contentsOf: declarationsFile, encoding: .utf8)
    let patchedUses = try String(contentsOf: usesFile, encoding: .utf8)
    for entry in internalEntries {
        #expect(patchedDeclarations.contains("case \(entry.newName)"))
        #expect(patchedUses.contains(".\(entry.newName)"))
    }
    #expect(patchedDeclarations.contains("(\(valueEntry.newName): Int)"))
    #expect(patchedUses.contains("(\(valueEntry.newName): 1)"))
    #expect(patchedUses.contains("(let value)"))
    #expect(patchedUses.contains("(\(valueEntry.newName): let value)"))
    #expect(patchedDeclarations.contains("case \(visibleEntry.newName)"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", declarationsFile.path, usesFile.path]
    )
}
