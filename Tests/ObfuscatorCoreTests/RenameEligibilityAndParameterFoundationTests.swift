import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Safety and parameter foundations

@Test func renameEligibilityAnalyzerDeniesUnsupportedKindsByDefault() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try "let localValue = 1\n".write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-module",
        name: "Sample",
        kind: "module",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: 5,
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

    #expect(decision.isEligible == false)
    #expect(decision.reasons.contains { $0.contains("unsupported symbol kind") })
}

@Test func renameEligibilityAnalyzerDeniesParametersBecauseArgumentLabelsAreNotCompleteOccurrences() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try "func run(value: String) { print(value) }\n".write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = IndexSnapshot.Symbol(
        usr: "usr-parameter",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: 10,
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

    #expect(decision.isEligible == false)
    #expect(decision.reasons.contains { $0.contains("unsupported symbol kind parameter") })
}

@Test func renameEligibilityAnalyzerKeepsRuntimeOwnerContractsSeparateFromLocalParameterBindings() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Action.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])
    let symbol = IndexSnapshot.Symbol(
        usr: "usr-sender",
        name: "sender",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let group = IndexSnapshot.OccurrenceGroup(
        usr: symbol.usr,
        symbol: symbol,
        occurrences: [
            testOccurrence(
                symbol,
                path: file.path,
                line: 1,
                token: "sender",
                roles: [.definition]
            ),
            testOccurrence(
                symbol,
                path: file.path,
                line: 2,
                token: "sender",
                roles: [.reference]
            ),
        ]
    )
    let semanticIndex = SemanticIndex(
        externallyOwnedUSRs: [symbol.usr],
        runtimeSensitiveUSRs: [symbol.usr]
    )

    let denied = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: group,
        sourceCache: cache,
        semanticIndex: semanticIndex
    )
    #expect(!denied.isEligible)

    let localBindingDecision = RenameEligibilityAnalyzer(sourceRoot: directory).analyze(
        group: group,
        sourceCache: cache,
        semanticIndex: semanticIndex,
        localBindingOnlyParameterUSRs: [symbol.usr]
    )
    #expect(localBindingDecision.isEligible)
    #expect(localBindingDecision.originalName == "sender")
}

@Test func callableSignaturesSeparateExternalLabelsFromLocalBindings() throws {
    let directory = try makeTemporaryDirectory()
    let selectedFile = directory.appendingPathComponent("Selected.swift")
    let outsideFile = directory.appendingPathComponent("Outside.swift")
    try copyFixture(to: selectedFile)
    try "let outside = combine(1, wire: 2, shorthand: 3)\n".write(
        to: outsideFile,
        atomically: true,
        encoding: .utf8
    )

    let combine = testSymbol("usr-combine", "combine(_:wire:shorthand:)", .function)
    let hidden = testSymbol("usr-hidden", "hidden")
    let local = testSymbol("usr-local", "local")
    let shorthand = testSymbol("usr-shorthand", "shorthand")
    let initializer = testSymbol(
        "usr-initializer",
        "init(loadController:workspaceId:)",
        .constructor
    )
    let loadController = testSymbol("usr-load-controller", "loadController")
    let localWorkspaceID = testSymbol("usr-workspace-id", "localWorkspaceID")
    let broken = testSymbol("usr-broken", "broken(one:two:)", .function)
    let brokenParameter = testSymbol("usr-broken-parameter", "one")
    let enumCase = testSymbol("usr-enum-case", "received(payload:)", .enumConstant)
    let payload = testSymbol("usr-payload", "payload")
    let subscriptDeclaration = testSymbol("usr-subscript", "subscript(offset:)", .instanceProperty)
    let index = testSymbol("usr-index", "index")

    func occurrence(
        _ symbol: IndexSnapshot.Symbol,
        path: URL = selectedFile,
        line: Int,
        token: String,
        roles: [String],
        relations: [IndexSnapshot.Relation] = []
    ) -> IndexSnapshot.Occurrence {
        let sourceLine = fixtureLine(at: path, line: line)
        return IndexSnapshot.Occurrence(
            symbol: symbol,
            path: path.path,
            line: line,
            utf8Column: utf8Column(of: token, in: sourceLine),
            moduleName: "Sample",
            isSystem: false,
            rolesRaw: 0,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relations
        )
    }

    let occurrences = [
        occurrence(combine, line: 1, token: "combine", roles: ["definition"]),
        occurrence(combine, line: 4, token: "combine", roles: ["reference", "call"]),
        occurrence(combine, line: 5, token: "combine", roles: ["reference"]),
        occurrence(
            combine,
            path: outsideFile,
            line: 1,
            token: "combine",
            roles: ["reference", "call"]
        ),
        // Deliberately shuffled: ordinal comes from compiler locations, not snapshot order.
        occurrence(shorthand, line: 1, token: "shorthand", roles: ["definition"], relations: [childOf(combine)]),
        occurrence(hidden, line: 1, token: "hidden", roles: ["definition"], relations: [childOf(combine)]),
        occurrence(local, line: 1, token: "local", roles: ["definition"], relations: [childOf(combine)]),
        occurrence(hidden, line: 2, token: "hidden", roles: ["reference", "read"]),
        occurrence(local, line: 2, token: "local", roles: ["reference", "read"]),
        occurrence(shorthand, line: 2, token: "shorthand", roles: ["reference", "read"]),
        occurrence(initializer, line: 7, token: "init", roles: ["definition"]),
        occurrence(
            loadController,
            line: 7,
            token: "loadController",
            roles: ["definition"],
            relations: [childOf(initializer)]
        ),
        occurrence(
            localWorkspaceID,
            line: 7,
            token: "localWorkspaceID",
            roles: ["definition"],
            relations: [childOf(initializer)]
        ),
        occurrence(loadController, line: 8, token: "loadController", roles: ["reference", "read"]),
        occurrence(localWorkspaceID, line: 8, token: "localWorkspaceID", roles: ["reference", "read"]),
        occurrence(broken, line: 11, token: "broken", roles: ["definition"]),
        occurrence(
            brokenParameter,
            line: 11,
            token: "one",
            roles: ["definition"],
            relations: [childOf(broken)]
        ),
        occurrence(enumCase, line: 12, token: "received", roles: ["definition"]),
        occurrence(
            payload,
            line: 12,
            token: "payload",
            roles: ["definition"],
            relations: [childOf(enumCase)]
        ),
        occurrence(
            subscriptDeclaration,
            line: 13,
            token: "subscript",
            roles: ["definition"]
        ),
        occurrence(
            index,
            line: 13,
            token: "index",
            roles: ["definition"],
            relations: [childOf(subscriptDeclaration)]
        ),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [selectedFile.path, outsideFile.path],
        symbols: [
            combine, hidden, local, shorthand, initializer, loadController,
            localWorkspaceID, broken, brokenParameter, enumCase, payload,
            subscriptDeclaration, index,
        ],
        occurrences: occurrences
    )

    let semanticIndex = SemanticIndex(snapshot: snapshot, obfuscationRoots: [selectedFile])
    #expect(semanticIndex.callableSignatures.count == 5)

    let combineComponent = try #require(
        semanticIndex.callableSignatures.first { $0.callableUSR == combine.usr }
    )
    #expect(combineComponent.isStructurallyComplete)
    #expect(combineComponent.parameters.map(\.parameterUSR) == [hidden.usr, local.usr, shorthand.usr])
    #expect(combineComponent.parameters.map(\.ordinal) == [0, 1, 2])
    #expect(combineComponent.parameters.map(\.localBinding) == ["hidden", "local", "shorthand"])
    #expect(
        combineComponent.parameters.map(\.externalLabel) == [
            .omitted, .named("wire"), .named("shorthand"),
        ])
    #expect(combineComponent.parameters.map { $0.referenceLocations.map(\.line) } == [[2], [2], [2]])
    #expect(combineComponent.callLocations.map(\.line) == [4])
    #expect(combineComponent.nonCallReferenceLocations.map(\.line) == [5])
    #expect(combineComponent.hasOccurrenceOutsideSelectedRoots)

    let initializerComponent = try #require(
        semanticIndex.callableSignatures.first { $0.callableUSR == initializer.usr }
    )
    #expect(initializerComponent.isStructurallyComplete)
    #expect(initializerComponent.parameters.map(\.localBinding) == ["loadController", "localWorkspaceID"])
    #expect(
        initializerComponent.parameters.map(\.externalLabel) == [
            .named("loadController"), .named("workspaceId"),
        ])

    let brokenComponent = try #require(
        semanticIndex.callableSignatures.first { $0.callableUSR == broken.usr }
    )
    #expect(!brokenComponent.isStructurallyComplete)
    #expect(brokenComponent.parameters.map(\.externalLabel) == [.unavailable])
    #expect(
        brokenComponent.structuralReasons == [
            "callable index name does not expose exactly 1 external argument label(s)"
        ])

    let enumCaseComponent = try #require(
        semanticIndex.callableSignatures.first { $0.callableUSR == enumCase.usr }
    )
    #expect(enumCaseComponent.ownerCategory == .enumCase)
    #expect(enumCaseComponent.parameters.map(\.externalLabel) == [.named("payload")])

    let subscriptComponent = try #require(
        semanticIndex.callableSignatures.first { $0.callableUSR == subscriptDeclaration.usr }
    )
    #expect(subscriptComponent.ownerCategory == .subscriptDeclaration)
    #expect(subscriptComponent.parameters.map(\.localBinding) == ["index"])
    #expect(subscriptComponent.parameters.map(\.externalLabel) == [.named("offset")])

    let summary = semanticIndex.callableReport
    #expect(summary.explicitParameters == 8)
    #expect(summary.modeledParameters == 8)
    #expect(summary.unmodeledParameters == 0)
    #expect(summary.signatures == 5)
    #expect(summary.structurallyCompleteSignatures == 4)
    #expect(summary.structurallyCompleteParameters == 7)
    #expect(summary.omittedExternalLabels == 1)
    #expect(summary.sharedLabelAndBindingParameters == 3)
    #expect(summary.distinctLabelAndBindingParameters == 3)
    #expect(summary.unavailableExternalLabels == 1)
    #expect(summary.callAnchors == 1)
    #expect(summary.functionReferenceAnchors == 1)
    #expect(summary.enumCaseReferenceAnchors == 0)
    #expect(summary.signaturesWithOccurrencesOutsideSelectedRoots == 1)
    #expect(summary.protocolRequirementSignatures == 0)
    #expect(summary.overrideRelatedSignatures == 0)
    #expect(summary.runtimeSensitiveSignatures == 0)
    #expect(summary.externallyOwnedSignatures == 0)
    #expect(summary.subscriptSignatures == 1)
    #expect(summary.subscriptParameters == 1)
    #expect(summary.enumCaseSignatures == 1)
    #expect(summary.enumCaseParameters == 1)
}
