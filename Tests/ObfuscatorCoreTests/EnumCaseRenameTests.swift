import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Enum-case rename planning

@Test func enumCasePlannerKeepsStringMatchedCaseDeniedWithoutBlockingSafeSibling() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("EnumCaseRename.swift")
    try copyFixture(to: file)

    let safe = testSymbol("s:planner-safe", "Safe", .enum)
    let idle = testSymbol("s:planner-safe-idle", "idle", .enumConstant)
    let payload = testSymbol("s:planner-safe-payload", "payload(value:)", .enumConstant)
    let value = testSymbol("s:planner-safe-payload-value", "value", .parameter)
    let blocked = testSymbol("s:planner-blocked", "Blocked", .enum)
    let logged = testSymbol("s:planner-blocked-logged", "logged", .enumConstant)
    let queued = testSymbol("s:planner-blocked-queued", "queued(value:)", .enumConstant)
    let blockedValue = testSymbol("s:planner-blocked-queued-value", "value", .parameter)

    let occurrences = [
        testOccurrence(safe, path: file.path, line: 1, token: "Safe", roles: [.definition]),
        testOccurrence(
            idle, path: file.path, line: 2, token: "idle", roles: [.definition], relations: [childOf(safe)]),
        testOccurrence(
            payload, path: file.path, line: 3, token: "payload", roles: [.definition], relations: [childOf(safe)]),
        testOccurrence(
            value, path: file.path, line: 3, token: "value", roles: [.definition], relations: [childOf(payload)]),
        testOccurrence(idle, path: file.path, line: 7, token: "idle", roles: [.reference]),
        testOccurrence(payload, path: file.path, line: 8, token: "payload", roles: [.reference]),
        testOccurrence(payload, path: file.path, line: 9, token: "payload", roles: [.reference]),
        testOccurrence(idle, path: file.path, line: 10, token: "idle", roles: [.reference]),
        testOccurrence(blocked, path: file.path, line: 15, token: "Blocked", roles: [.definition]),
        testOccurrence(
            logged, path: file.path, line: 16, token: "logged", roles: [.definition], relations: [childOf(blocked)]),
        testOccurrence(
            queued, path: file.path, line: 17, token: "queued", roles: [.definition], relations: [childOf(blocked)]),
        testOccurrence(
            blockedValue, path: file.path, line: 17, token: "value", roles: [.definition], relations: [childOf(queued)]
        ),
        testOccurrence(queued, path: file.path, line: 20, token: "queued", roles: [.reference, .call]),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [safe, idle, payload, value, blocked, logged, queued, blockedValue],
        occurrences: occurrences
    )
    let cache = try SourceFileCache(paths: [file.path])
    var planner = RenamePlanner(
        analyzer: RenameEligibilityAnalyzer(sourceRoot: directory),
        generator: ObfuscatedNameGenerator(prefix: "Case")
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    let safeEntries = plan.renames.filter { [idle.usr, payload.usr].contains($0.usr) }
    #expect(safeEntries.count == 2)
    #expect(safeEntries.allSatisfy { $0.kind == "enumConstant" })
    #expect(safeEntries.allSatisfy { $0.newName.first?.isLowercase == true })
    #expect(safeEntries.flatMap(\.edits).count == 6)
    let valueEntry = try #require(plan.renames.first { $0.usr == value.usr })
    #expect(valueEntry.edits.count == 2)
    let queuedEntry = try #require(plan.renames.first { $0.usr == queued.usr })
    let blockedValueEntry = try #require(plan.renames.first { $0.usr == blockedValue.usr })
    #expect(queuedEntry.edits.count == 2)
    #expect(blockedValueEntry.edits.count == 2)
    #expect(plan.callSiteSyntaxReport.resolvedEnumCasePatterns == 1)
    #expect(!plan.renames.contains { $0.usr == logged.usr })
    let loggedDenial = try #require(plan.rejections.first { $0.usr == logged.usr })
    #expect(
        loggedDenial.reasons.contains { reason in
            reason.contains("candidate subset") && reason.contains("stringLiteralSpelling")
        }
    )
    #expect(!plan.rejections.contains { $0.usr == queued.usr || $0.usr == blockedValue.usr })
    #expect(
        plan.rejections.filter { $0.usr == logged.usr }.allSatisfy {
            $0.reasons.contains { reason in
                reason.contains("denied atomically") && reason.contains("stringLiteralSpelling")
            }
        })
    #expect(plan.editConflicts.isEmpty)

    let idleEntry = try #require(safeEntries.first { $0.usr == idle.usr })
    let payloadEntry = try #require(safeEntries.first { $0.usr == payload.usr })
    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("case \(idleEntry.newName)"))
    #expect(patched.contains("case \(payloadEntry.newName)(\(valueEntry.newName): Int)"))
    #expect(patched.contains(".\(payloadEntry.newName)(\(valueEntry.newName): 1)"))
    #expect(patched.contains("case .\(payloadEntry.newName):"))
    #expect(patched.contains("case logged"))
    #expect(patched.contains("case \(queuedEntry.newName)(\(blockedValueEntry.newName): Int)"))
    #expect(patched.contains(".\(queuedEntry.newName)(\(blockedValueEntry.newName): 2)"))
    #expect(patched.contains("\"logged\""))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func enumCasePlannerRenamesExplicitAndCompilerMaterializedRawCases() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ExplicitRawEnum.swift")
    try copyFixture(to: file)

    let owner = testSymbol("s:explicit-wire", "ExplicitWire", .enum)
    let implicit = testSymbol("s:explicit-wire-implicit", "implicit", .enumConstant)
    let stable = testSymbol("s:explicit-wire-stable", "stable", .enumConstant)
    let rawType = testSymbol("s:explicit-raw-type", "String", .struct)

    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [owner, implicit, stable, rawType],
        occurrences: [
            testOccurrence(owner, path: file.path, line: 1, token: "ExplicitWire", roles: [.definition]),
            testOccurrence(
                rawType,
                path: file.path,
                line: 1,
                token: "String",
                roles: [.reference, .baseOf],
                relations: [testRelation(owner, .baseOf)]
            ),
            testOccurrence(
                implicit,
                path: file.path,
                line: 2,
                token: "implicit",
                roles: [.definition],
                relations: [testRelation(owner, .childOf)]
            ),
            testOccurrence(
                stable,
                path: file.path,
                line: 3,
                token: "stable",
                roles: [.definition],
                relations: [testRelation(owner, .childOf)]
            ),
            testOccurrence(owner, path: file.path, line: 5, token: "ExplicitWire", roles: [.reference]),
            testOccurrence(implicit, path: file.path, line: 5, token: "implicit", roles: [.reference]),
            testOccurrence(owner, path: file.path, line: 6, token: "ExplicitWire", roles: [.reference]),
            testOccurrence(stable, path: file.path, line: 6, token: "stable", roles: [.reference]),
        ]
    )
    let cache = try SourceFileCache(paths: [file.path])
    var planner = RenamePlanner(
        analyzer: RenameEligibilityAnalyzer(sourceRoot: directory),
        generator: ObfuscatedNameGenerator(prefix: "Case")
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    let syntaxOwner = try #require(
        plan.enumCaseSyntaxReport.owners.first { $0.ownerUSR == owner.usr }
    )
    #expect(syntaxOwner.blockers.isEmpty)
    let implicitMember = try #require(
        syntaxOwner.members.first { $0.caseUSR == implicit.usr }
    )
    let stableMember = try #require(
        syntaxOwner.members.first { $0.caseUSR == stable.usr }
    )
    #expect(!implicitMember.hasExplicitRawValue)
    #expect(implicitMember.implicitRawValueLiteral == "\"implicit\"")
    #expect(implicitMember.blockers.isEmpty)
    #expect(stableMember.hasExplicitRawValue)
    #expect(stableMember.blockers.isEmpty)
    let implicitEntry = try #require(plan.renames.first { $0.usr == implicit.usr })
    let stableEntry = try #require(plan.renames.first { $0.usr == stable.usr })
    #expect(implicitEntry.edits.count == 2)
    #expect(stableEntry.edits.count == 2)
    let implicitSupportUSR = "implicit-raw-value:\(implicit.usr)"
    let implicitSupport = plan.preservationEdits.first { replacement in
        replacement.usr == implicitSupportUSR
    }
    #expect(implicitSupport?.newName == " = \"implicit\"")
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("case \(implicitEntry.newName) = \"implicit\""))
    #expect(patched.contains("case \(stableEntry.newName) = \"wire_stable\""))
    #expect(!patched.contains("case stable"))
    let executable = directory.appendingPathComponent("ExplicitRawEnum")
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", executable.path]
    )
    _ = try CommandRunner().run(executable: executable.path, arguments: [])
}

@Test func enumCasePlannerRenamesExplicitRawCodableSiblingAndDeniesManualContracts() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ExplicitRawCodable.swift")
    try copyFixture(to: file)

    let store = directory.appendingPathComponent("IndexStore", isDirectory: true)
    let database = directory.appendingPathComponent("IndexDatabase", isDirectory: true)
    let beforeExecutable = directory.appendingPathComponent("Before")
    let runner = CommandRunner(
        logDirectory: directory.appendingPathComponent("logs", isDirectory: true)
    )
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: [
            "swiftc",
            "-module-name", "ExplicitRawCodableFixture",
            "-index-store-path", store.path,
            file.path,
            "-o", beforeExecutable.path,
        ]
    )
    _ = try runner.run(executable: beforeExecutable.path, arguments: [])

    let snapshot = try IndexSnapshotReader().read(
        storePath: store,
        databasePath: database,
        sourceRoot: directory
    )
    let cache = try SourceFileCache(paths: [file.path])
    var planner = RenamePlanner(
        analyzer: RenameEligibilityAnalyzer(sourceRoot: directory),
        generator: ObfuscatedNameGenerator(prefix: "Case")
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    let stableOwner = try #require(
        plan.enumCaseSemanticsReport.owners.first {
            $0.ownerName == "StableWire"
        })
    let implicitOwner = try #require(
        plan.enumCaseSemanticsReport.owners.first {
            $0.ownerName == "ImplicitWire"
        })
    let customOwner = try #require(
        plan.enumCaseSemanticsReport.owners.first {
            $0.ownerName == "CustomWire"
        })
    #expect(stableOwner.hasRawType)
    #expect(stableOwner.isSerializationSensitive)
    #expect(!stableOwner.hasManualSerializationContract)
    #expect(customOwner.hasCustomSerializationImplementation)

    let stableSyntax = try #require(
        plan.enumCaseSyntaxReport.owners.first {
            $0.ownerUSR == stableOwner.ownerUSR
        })
    let implicitSyntax = try #require(
        plan.enumCaseSyntaxReport.owners.first {
            $0.ownerUSR == implicitOwner.ownerUSR
        })
    let customSyntax = try #require(
        plan.enumCaseSyntaxReport.owners.first {
            $0.ownerUSR == customOwner.ownerUSR
        })
    #expect(stableSyntax.blockers.isEmpty)
    #expect(!implicitSyntax.blockers.contains(.rawType))
    #expect(!implicitSyntax.blockers.contains(.serializationContract))
    let implicitFirstSyntax = try #require(
        implicitSyntax.members.first {
            $0.declarationToken?.name == "first"
        })
    let implicitSecondSyntax = try #require(
        implicitSyntax.members.first {
            $0.declarationToken?.name == "second"
        })
    #expect(implicitFirstSyntax.implicitRawValueLiteral == "\"first\"")
    #expect(implicitFirstSyntax.blockers.isEmpty)
    #expect(!implicitSecondSyntax.blockers.contains(.rawType))
    #expect(implicitSecondSyntax.blockers.isEmpty)
    #expect(customSyntax.blockers.contains(.serializationContract))

    let plannedUSRs = Set(plan.renames.map(\.usr))
    #expect(Set(stableOwner.caseUSRs).isSubset(of: plannedUSRs))
    #expect(plannedUSRs.contains(implicitFirstSyntax.caseUSR))
    #expect(plannedUSRs.contains(implicitSecondSyntax.caseUSR))
    #expect(Set(customOwner.caseUSRs).isDisjoint(with: plannedUSRs))
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("= \"wire_first\""))
    #expect(patched.contains("= \"wire_second\""))
    #expect(patched.contains("= \"first\""))
    #expect(!patched.contains("case first\n"))
    #expect(!patched.contains("case second = \"wire_second\""))
    #expect(patched.contains("case visible = \"wire_visible\""))

    let afterExecutable = directory.appendingPathComponent("After")
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", afterExecutable.path]
    )
    _ = try runner.run(executable: afterExecutable.path, arguments: [])
}

@Test func indexedEnumCaseProtocolWitnessRelationsAreExplicit() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ProtocolEnum.swift")
    try copyFixture(to: file)
    let store = directory.appendingPathComponent("IndexStore", isDirectory: true)
    let database = directory.appendingPathComponent("IndexDatabase", isDirectory: true)
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: [
            "swiftc", "-typecheck",
            "-module-name", "ProtocolEnumFixture",
            "-index-store-path", store.path,
            file.path,
        ]
    )
    let snapshot = try IndexSnapshotReader().read(
        storePath: store,
        databasePath: database,
        sourceRoot: directory
    )
    func enumCaseDeclaration(line: Int) -> IndexSnapshot.Occurrence? {
        snapshot.occurrences.first {
            $0.line == line
                && $0.symbol.kind == "enumConstant"
                && ($0.roles.contains("declaration") || $0.roles.contains("definition"))
        }
    }
    let witnessIdle = try #require(enumCaseDeclaration(line: 6))
    let witnessPayload = try #require(enumCaseDeclaration(line: 7))
    let ordinaryIdle = try #require(enumCaseDeclaration(line: 10))
    #expect(witnessIdle.roles.contains("overrideOf"))
    #expect(witnessPayload.roles.contains("overrideOf"))
    #expect(witnessIdle.relations.contains { $0.roles.contains("overrideOf") })
    #expect(witnessPayload.relations.contains { $0.roles.contains("overrideOf") })
    #expect(!ordinaryIdle.roles.contains("overrideOf"))
    #expect(!ordinaryIdle.relations.contains { $0.roles.contains("overrideOf") })

    let cache = try SourceFileCache(paths: [file.path])
    let semanticIndex = SemanticIndex(
        snapshot: snapshot,
        obfuscationRoots: [directory]
    )
    let semantics = EnumCaseSemantics.Index(
        snapshot: snapshot,
        semanticIndex: semanticIndex,
        obfuscationRoots: [directory]
    )
    let witness = try #require(
        semantics.owners.first {
            $0.ownerName == "Witness"
        })
    let ordinary = try #require(
        semantics.owners.first {
            $0.ownerName == "Ordinary"
        })
    #expect(witness.hasProtocolConformance)
    #expect(witness.hasProtocolCaseWitness)
    #expect(witness.members.allSatisfy { $0.isProtocolRequirementWitness })
    #expect(ordinary.hasProtocolConformance)
    #expect(!ordinary.hasProtocolCaseWitness)
    #expect(ordinary.members.allSatisfy { !$0.isProtocolRequirementWitness })
    #expect(semantics.report.protocolConformanceOwnerCount == 2)
    #expect(semantics.report.protocolConformanceCases == 4)
    #expect(semantics.report.protocolWitnessOwnerCount == 1)
    #expect(semantics.report.protocolWitnessCases == 2)

    let syntaxIndex = EnumCaseSyntax.Index(
        snapshot: snapshot,
        semantics: semantics,
        sourceCache: cache,
        obfuscationRoots: [directory]
    )
    let witnessSyntax = try #require(
        syntaxIndex.owners.first {
            $0.ownerUSR == witness.ownerUSR
        })
    let ordinarySyntax = try #require(
        syntaxIndex.owners.first {
            $0.ownerUSR == ordinary.ownerUSR
        })
    #expect(witnessSyntax.blockers.contains(.protocolConformance))
    #expect(ordinarySyntax.blockers.isEmpty)

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let plannedUSRs = Set(plan.renames.map(\.usr))
    #expect(Set(ordinary.caseUSRs).isSubset(of: plannedUSRs))
    #expect(Set(witness.caseUSRs).isDisjoint(with: plannedUSRs))
    for usr in witness.caseUSRs {
        let decisions = plan.rejections.filter { $0.usr == usr }
        #expect(decisions.count == 1)
        #expect(
            decisions.first?.reasons.contains {
                $0.contains("enum case blocker: protocolConformance")
            } == true)
        #expect(
            decisions.first?.reasons.contains {
                $0.contains("protocol members require relation-aware witness renaming")
            } == true)
    }
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func enumCasePlannerMaterializesCompilerDerivedImplicitRawValues() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ImplicitRawValues.swift")
    try copyFixture(to: file)

    let store = directory.appendingPathComponent("IndexStore", isDirectory: true)
    let database = directory.appendingPathComponent("IndexDatabase", isDirectory: true)
    let beforeExecutable = directory.appendingPathComponent("Before")
    let runner = CommandRunner(
        logDirectory: directory.appendingPathComponent("logs", isDirectory: true)
    )
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: [
            "swiftc",
            "-module-name", "ImplicitRawValuesFixture",
            "-index-store-path", store.path,
            file.path,
            "-o", beforeExecutable.path,
        ]
    )
    _ = try runner.run(executable: beforeExecutable.path, arguments: [])

    let snapshot = try IndexSnapshotReader().read(
        storePath: store,
        databasePath: database,
        sourceRoot: directory
    )
    let cache = try SourceFileCache(paths: [file.path])
    var planner = RenamePlanner(
        analyzer: RenameEligibilityAnalyzer(sourceRoot: directory),
        generator: ObfuscatedNameGenerator(prefix: "Raw")
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    func entry(_ name: String) throws -> RenamePlan.Entry {
        try #require(
            plan.renames.first {
                $0.kind == "enumConstant" && $0.oldName == name
            })
    }
    let alpha = try entry("alpha")
    let beta = try entry("beta")
    let zero = try entry("zero")
    _ = try entry("two")
    let three = try entry("three")
    #expect(
        !plan.renames.contains {
            $0.kind == "enumConstant" && $0.oldName == "visible"
        })
    let codingKeyUSR = try #require(
        snapshot.occurrenceGroups.first {
            $0.symbol.kind == "enumConstant"
                && $0.symbol.name == "value"
                && $0.occurrences.contains { occurrence in
                    occurrence.relations.contains { relation in
                        relation.roles.contains("childOf") && relation.name == "CodingKeys"
                    }
                }
        }
    ).usr
    let codingKeyEntry = try #require(plan.renames.first { $0.usr == codingKeyUSR })
    let codingPropertyEntry = try #require(
        plan.renames.first {
            $0.kind == "instanceProperty" && $0.oldName == "value"
        })
    #expect(codingKeyEntry.newName == codingPropertyEntry.newName)
    #expect(plan.enumRawValueReport.resolvedImplicitRawValues >= 5)
    #expect(
        plan.preservationEdits.count { replacement in
            replacement.usr.hasPrefix("implicit-raw-value:")
        } == 5)
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("case \(alpha.newName) = \"alpha\""))
    #expect(patched.contains("case \(beta.newName) = \"beta\""))
    #expect(patched.contains("case \(zero.newName) = 0"))
    #expect(patched.contains("case \(three.newName) = 3"))
    #expect(patched.contains("case \(codingKeyEntry.newName) = \"value\" }"))

    let afterExecutable = directory.appendingPathComponent("After")
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", afterExecutable.path]
    )
    _ = try runner.run(executable: afterExecutable.path, arguments: [])
}
