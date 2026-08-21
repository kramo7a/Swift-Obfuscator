import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Parameter external labels

@Test func renamePlannerCoordinatesExternalLabelsAcrossProtocolDeclarationsAndUses() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ExternalLabels.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let service = testSymbol("usr-service", "Service", .protocol)
    let implementation = testSymbol("usr-service-impl", "ServiceImpl", .struct)
    let requirement = testSymbol("usr-send-requirement", "send(wire:)", .instanceMethod)
    let witness = testSymbol("usr-send-witness", "send(wire:)", .instanceMethod)
    let requirementValue = testSymbol(
        "usr-requirement-value",
        "requirementValue",
        .parameter
    )
    let localValue = testSymbol("usr-local-value", "localValue", .parameter)

    let occurrences = [
        testOccurrence(
            service,
            path: file.path,
            line: 1,
            token: "Service",
            roles: [.definition]
        ),
        testOccurrence(
            implementation,
            path: file.path,
            line: 4,
            token: "ServiceImpl",
            roles: [.definition]
        ),
        testOccurrence(
            requirement,
            path: file.path,
            line: 2,
            token: "send",
            roles: [.definition],
            relations: [
                testRelation(service, role: .childOf),
                testRelation(witness, role: .baseOf),
            ]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 5,
            token: "send",
            roles: [.definition],
            relations: [
                testRelation(implementation, role: .childOf),
                testRelation(requirement, role: .overrideOf),
            ]
        ),
        testOccurrence(
            requirement,
            path: file.path,
            line: 10,
            token: "send",
            roles: [.reference, .call]
        ),
        testOccurrence(
            requirement,
            path: file.path,
            line: 11,
            token: "send",
            roles: [.reference]
        ),
        testOccurrence(
            requirementValue,
            path: file.path,
            line: 2,
            token: "requirementValue",
            roles: [.definition],
            relations: [testRelation(requirement, role: .childOf)]
        ),
        testOccurrence(
            localValue,
            path: file.path,
            line: 5,
            token: "localValue",
            roles: [.definition],
            relations: [testRelation(witness, role: .childOf)]
        ),
        testOccurrence(
            localValue,
            path: file.path,
            line: 6,
            token: "localValue",
            roles: [.reference, .read]
        ),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            service, implementation, requirement, witness,
            requirementValue, localValue,
        ],
        occurrences: occurrences
    )

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let requirementEntry = try #require(
        plan.renames.first {
            $0.usr == requirementValue.usr
        })
    let witnessEntry = try #require(plan.renames.first { $0.usr == localValue.usr })
    #expect(requirementEntry.newName == witnessEntry.newName)
    #expect(requirementEntry.newName.first?.isLowercase == true)
    #expect(
        Set(requirementEntry.edits.map(\.oldName)) == [
            "wire", "requirementValue",
        ])
    #expect(Set(witnessEntry.edits.map(\.oldName)) == ["wire", "localValue"])
    #expect(plan.editConflicts.isEmpty)
    #expect(plan.externalLabelRenameReport.candidateFamilyCount == 1)
    #expect(plan.externalLabelRenameReport.candidateParameterCount == 2)
    #expect(plan.externalLabelRenameReport.renamedFamilyCount == 1)
    #expect(plan.externalLabelRenameReport.renamedParameterCount == 2)
    #expect(plan.externalLabelRenameReport.rejectedFamilyCount == 0)
    #expect(plan.externalLabelRenameReport.unclassifiedParameterCount == 0)

    try SourcePatcher().apply(
        [requirementEntry, witnessEntry].flatMap(\.edits)
    )
    let patched = try String(contentsOf: file, encoding: .utf8)
    let newName = requirementEntry.newName
    #expect(patched.contains("func send(\(newName) \(newName): Int)"))
    #expect(patched.contains("_ = \(newName)"))
    #expect(patched.contains("service.send(\(newName): 1)"))
    #expect(patched.contains("Service.send(\(newName):)"))
}

@Test func renamePlannerRenamesInitializerLabelWithoutInventingALocalBinding() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("InitializerLabel.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let sink = testSymbol("usr-sink", "Sink", .struct)
    let initializer = testSymbol("usr-sink-init", "init(event:)", .constructor)
    let event = testSymbol("usr-event", "_", .parameter)
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [sink, initializer, event],
        occurrences: [
            testOccurrence(
                sink,
                path: file.path,
                line: 1,
                token: "Sink",
                roles: [.definition]
            ),
            testOccurrence(
                initializer,
                path: file.path,
                line: 2,
                token: "init",
                roles: [.definition],
                relations: [childOf(sink)]
            ),
            testOccurrence(
                initializer,
                path: file.path,
                line: 4,
                token: "Sink",
                roles: [.reference, .call]
            ),
            testOccurrence(
                event,
                path: file.path,
                line: 2,
                token: "_",
                roles: [.definition],
                relations: [childOf(initializer)]
            ),
        ]
    )

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.renames.first { $0.usr == event.usr })
    #expect(entry.oldName == "event")
    #expect(Set(entry.edits.map(\.oldName)) == ["event"])
    #expect(entry.edits.count == 2)
    #expect(!entry.edits.contains { $0.oldName == "_" })
    #expect(plan.externalLabelRenameReport.renamedParameterCount == 1)
    #expect(plan.externalLabelRenameReport.rejectedParameterCount == 0)

    try SourcePatcher().apply(entry.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("init(\(entry.newName) _: Int)"))
    #expect(patched.contains("Sink(\(entry.newName): 1)"))
}

@Test func renamePlannerCoordinatesKeywordArgumentLabels() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("KeywordArgumentLabel.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let route = testSymbol("usr-route", "route(for:)", .function)
    let value = testSymbol("usr-route-value", "value", .parameter)
    let childOfRoute = IndexSnapshot.Relation(
        usr: route.usr,
        name: route.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [route, value],
        occurrences: [
            testOccurrence(
                route,
                path: file.path,
                line: 1,
                token: "route",
                roles: [.definition]
            ),
            testOccurrence(
                route,
                path: file.path,
                line: 4,
                token: "route",
                roles: [.reference, .call]
            ),
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: [.definition],
                relations: [childOfRoute]
            ),
            testOccurrence(
                value,
                path: file.path,
                line: 2,
                token: "value",
                roles: [.reference, .read]
            ),
        ]
    )

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.renames.first { $0.usr == value.usr })
    #expect(Set(entry.edits.map(\.oldName)) == ["for", "value"])
    #expect(entry.edits.count == 4)
    #expect(plan.externalLabelRenameReport.renamedParameterCount == 1)
    #expect(plan.externalLabelRenameReport.rejectedParameterCount == 0)
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(entry.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func route(\(entry.newName) \(entry.newName): Int)"))
    #expect(patched.contains("_ = \(entry.newName)"))
    #expect(patched.contains("route(\(entry.newName): 1)"))
}

@Test func renamePlannerCoordinatesContextualKeywordParameterBindings() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ContextualKeyword.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let configure = IndexSnapshot.Symbol(
        usr: "usr-contextual-configure",
        name: "configure(prefix:)",
        kind: "function",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let prefix = IndexSnapshot.Symbol(
        usr: "usr-contextual-prefix",
        name: "prefix",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let childOfConfigure = IndexSnapshot.Relation(
        usr: configure.usr,
        name: configure.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [configure, prefix],
        occurrences: [
            testOccurrence(
                configure,
                path: file.path,
                line: 1,
                token: "configure",
                roles: [.definition]
            ),
            testOccurrence(
                configure,
                path: file.path,
                line: 4,
                token: "configure",
                roles: [.reference, .call]
            ),
            testOccurrence(
                prefix,
                path: file.path,
                line: 1,
                token: "prefix",
                roles: [.definition],
                relations: [childOfConfigure]
            ),
            testOccurrence(
                prefix,
                path: file.path,
                line: 2,
                token: "prefix",
                roles: [.reference, .read]
            ),
        ]
    )

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.renames.first { $0.usr == prefix.usr })
    #expect(entry.oldName == "prefix")
    #expect(entry.newName.first?.isLowercase == true)
    #expect(entry.edits.count == 3)
    #expect(plan.externalLabelRenameReport.renamedParameterCount == 1)
    #expect(plan.externalLabelRenameReport.rejectedParameterCount == 0)
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(entry.edits)
    let runner = CommandRunner()
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}
@Test func externalLabelFamilyResolvesShorthandClosureShadowingScope() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ClosureShadow.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let compute = testSymbol(
        "usr-shadowed-compute",
        "compute(state:commands:)",
        .function
    )
    let state = testSymbol("usr-shadowed-state", "state", .parameter)
    let commands = testSymbol("usr-shadowed-commands", "commands", .parameter)
    func childOfCompute() -> IndexSnapshot.Relation {
        IndexSnapshot.Relation(
            usr: compute.usr,
            name: compute.name,
            rolesRaw: 0,
            roles: ["childOf"]
        )
    }
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [compute, state, commands],
        occurrences: [
            testOccurrence(
                compute,
                path: file.path,
                line: 2,
                token: "compute",
                roles: [.definition]
            ),
            testOccurrence(
                compute,
                path: file.path,
                line: 9,
                token: "compute",
                roles: [.reference, .call]
            ),
            testOccurrence(
                state,
                path: file.path,
                line: 2,
                token: "state",
                roles: [.definition],
                relations: [childOfCompute()]
            ),
            testOccurrence(
                commands,
                path: file.path,
                line: 2,
                token: "commands",
                roles: [.definition],
                relations: [childOfCompute()]
            ),
        ]
    )

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let computeEntry = try #require(plan.renames.first { $0.usr == compute.usr })
    let stateEntry = try #require(plan.renames.first { $0.usr == state.usr })
    let commandsEntry = try #require(plan.renames.first { $0.usr == commands.usr })
    #expect(stateEntry.edits.count == 5)
    #expect(commandsEntry.edits.count == 6)
    #expect(plan.parameterSyntaxReport.parametersWithShadowingBindingDeclarations == 0)
    #expect(plan.externalLabelReport.eligibleFamilyCount == 1)
    #expect(plan.externalLabelReport.familyCountsByBlocker.isEmpty)
    #expect(plan.externalLabelRenameReport.renamedFamilyCount == 1)
    #expect(plan.externalLabelRenameReport.renamedParameterCount == 2)
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(
        patched.contains(
            "func nested(state: Int) { \(commandsEntry.newName)(state) }"
        ))
    #expect(
        patched.contains(
            "work { state in \(commandsEntry.newName)(state) }"
        ))
    #expect(
        patched.contains(
            "work { [state = \(stateEntry.newName)] _ in "
                + "\(commandsEntry.newName)(state) }"
        ))
    #expect(
        patched.contains(
            "nested(state: \(stateEntry.newName))"
        ))
    #expect(
        patched.contains(
            "\(commandsEntry.newName)(\(stateEntry.newName))"
        ))
    #expect(
        patched.contains(
            "\(computeEntry.newName)(\(stateEntry.newName): 1, "
                + "\(commandsEntry.newName): { _ in })"
        ))

    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func externalLabelFamilyPreservesDynamicMemberLookupLabelAndRenamesBinding() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("DynamicMember.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let wrapper = testSymbol("usr-dynamic-wrapper", "Wrapper", .struct)
    let dynamicSubscript = testSymbol(
        "usr-dynamic-subscript",
        "subscript(dynamicMember:)",
        .instanceProperty
    )
    let keyPath = testSymbol("usr-dynamic-key-path", "keyPath", .parameter)
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [wrapper, dynamicSubscript, keyPath],
        occurrences: [
            testOccurrence(
                wrapper,
                path: file.path,
                line: 3,
                token: "Wrapper",
                roles: [.definition]
            ),
            testOccurrence(
                dynamicSubscript,
                path: file.path,
                line: 5,
                token: "subscript",
                roles: [.definition],
                relations: [childOf(wrapper)]
            ),
            testOccurrence(
                keyPath,
                path: file.path,
                line: 5,
                token: "keyPath",
                roles: [.definition],
                relations: [childOf(dynamicSubscript)]
            ),
        ]
    )

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.renames.first { $0.usr == keyPath.usr })
    #expect(entry.edits.count == 2)
    #expect(plan.externalLabelReport.blockedFamilyCount == 1)
    #expect(
        plan.externalLabelReport.familyCountsByBlocker == [
            "languageRequiredExternalLabel": 1
        ])
    #expect(plan.externalLabelRenameReport.candidateFamilyCount == 0)
    #expect(plan.localBindingRenameReport.candidateCount == 1)
    #expect(plan.localBindingRenameReport.renamedCount == 1)
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("subscript<T>(dynamicMember \(entry.newName): KeyPath<Root, T>)"))
    #expect(patched.contains("root[keyPath: \(entry.newName)]"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func parameterSyntaxExcludesKeyPathMembersFromLocalBindingReferences() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("KeyPathMember.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let position = IndexSnapshot.Symbol(
        usr: "usr-key-path-position",
        name: "position",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [position],
        occurrences: [
            testOccurrence(
                position,
                path: file.path,
                line: 2,
                token: "position",
                roles: [.definition]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.renames.first { $0.usr == position.usr })
    #expect(entry.edits.count == 2)
    #expect(plan.parameterSyntaxReport.localBindingReferenceTokens == 1)
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(entry.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Int)"))
    #expect(patched.contains("\\Model.position"))
    #expect(patched.contains("print(\(entry.newName))"))
}

@Test func externalLabelFamilyPreservesPropertyWrapperInitializerLabelAndRenamesBinding() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("PropertyWrapperInitializer.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let wrapper = testSymbol("usr-wrapper", "Wrapper", .struct)
    let initializer = testSymbol(
        "usr-wrapper-initializer",
        "init(wrappedValue:)",
        .constructor
    )
    let value = testSymbol("usr-wrapper-value", "value", .parameter)
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [wrapper, initializer, value],
        occurrences: [
            testOccurrence(
                wrapper,
                path: file.path,
                line: 2,
                token: "Wrapper",
                roles: [.definition]
            ),
            testOccurrence(
                initializer,
                path: file.path,
                line: 4,
                token: "init",
                roles: [.definition],
                relations: [childOf(wrapper)]
            ),
            testOccurrence(
                value,
                path: file.path,
                line: 4,
                token: "value",
                roles: [.definition],
                relations: [childOf(initializer)]
            ),
        ]
    )

    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.renames.first { $0.usr == value.usr })
    #expect(entry.edits.count == 2)
    #expect(plan.externalLabelReport.blockedFamilyCount == 1)
    #expect(
        plan.externalLabelReport.familyCountsByBlocker == [
            "languageRequiredExternalLabel": 1
        ])
    #expect(plan.externalLabelRenameReport.candidateFamilyCount == 0)
    #expect(plan.localBindingRenameReport.candidateCount == 1)
    #expect(plan.localBindingRenameReport.renamedCount == 1)
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("init(wrappedValue \(entry.newName): Value)"))
    #expect(patched.contains("wrappedValue = \(entry.newName)"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}
