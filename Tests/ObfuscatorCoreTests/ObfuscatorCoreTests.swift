import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Naming and infrastructure

@Test func obfuscatedNameGeneratorProducesStableNames() {
    var generator = ObfuscatedNameGenerator(prefix: "_o")
    #expect(generator.nextName(avoiding: []) == "_oa")
    #expect(generator.nextName(avoiding: ["_ob"]) == "_oc")
}

@Test func obfuscatedNameGeneratorDefaultPrefixAvoidsLeadingUnderscore() {
    var generator = ObfuscatedNameGenerator()
    #expect(generator.nextName(avoiding: []) == "Oa")
}

@Test func commandRunnerPersistsLogsInConfiguredDirectory() throws {
    let directory = try makeTemporaryDirectory()
    let runner = CommandRunner(logDirectory: directory)

    let result = try runner.run(
        executable: "/bin/sh",
        arguments: ["-c", "printf stdout-message; printf stderr-message >&2"]
    )

    let stdoutLogPath = try #require(result.stdoutLogPath)
    let stderrLogPath = try #require(result.stderrLogPath)
    let stdoutLog = try String(contentsOf: URL(fileURLWithPath: stdoutLogPath), encoding: .utf8)
    let stderrLog = try String(contentsOf: URL(fileURLWithPath: stderrLogPath), encoding: .utf8)

    #expect(result.stdout == "stdout-message")
    #expect(result.stderr == "stderr-message")
    #expect(stdoutLog == "stdout-message")
    #expect(stderrLog == "stderr-message")
    #expect(stdoutLogPath.hasPrefix(directory.path))
    #expect(stderrLogPath.hasPrefix(directory.path))
}

@Test func commandRunnerFailureDescriptionUsesOutputTailAndLogPaths() throws {
    let directory = try makeTemporaryDirectory()
    let runner = CommandRunner(logDirectory: directory)

    do {
        _ = try runner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "i=1; while [ $i -le 130 ]; do printf 'line-%03d\\n' \"$i\"; i=$((i + 1)); done; exit 7",
            ]
        )
        Issue.record("Expected command failure")
    } catch let error as CommandRunner.Error {
        let description = try #require(error.errorDescription)
        #expect(description.contains("Command failed with exit code 7"))
        #expect(description.contains("stdout log: \(directory.path)"))
        #expect(description.contains("stderr log: \(directory.path)"))
        #expect(description.contains("output tail:"))
        #expect(description.contains("line-130"))
        #expect(!description.contains("line-001"))
    }
}

@Test func commandRunnerCanReturnARequestedNonZeroResult() throws {
    let result = try CommandRunner().run(
        executable: "/bin/sh",
        arguments: ["-c", "printf partial-output; exit 9"],
        allowNonZeroExit: true
    )

    #expect(result.exitCode == 9)
    #expect(result.stdout == "partial-output")
    #expect(!result.isSuccessful)
}

@Test func sourceFileFinderSkipsConfiguredOutputDirectory() throws {
    let project = try makeTemporaryDirectory()
    let sources = project.appendingPathComponent("Sources", isDirectory: true)
    let outputSources =
        project
        .appendingPathComponent("output", isDirectory: true)
        .appendingPathComponent("Sources", isDirectory: true)
    let derivedSources =
        project
        .appendingPathComponent("Derived", isDirectory: true)
        .appendingPathComponent("Sources", isDirectory: true)
    let buildBackupSources =
        project
        .appendingPathComponent(".build.virtiofs-backup-20260714", isDirectory: true)
        .appendingPathComponent("checkouts", isDirectory: true)

    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputSources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: derivedSources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: buildBackupSources, withIntermediateDirectories: true)
    let source = sources.appendingPathComponent("main.swift")
    let copiedSource = outputSources.appendingPathComponent("main.swift")
    let generatedSource = derivedSources.appendingPathComponent("Generated.swift")
    let cachedSource = buildBackupSources.appendingPathComponent("Dependency.swift")
    try "print(\"source\")\n".write(to: source, atomically: true, encoding: .utf8)
    try "print(\"copied\")\n".write(to: copiedSource, atomically: true, encoding: .utf8)
    try "print(\"generated\")\n".write(to: generatedSource, atomically: true, encoding: .utf8)
    try "print(\"cached\")\n".write(to: cachedSource, atomically: true, encoding: .utf8)

    let files = try SwiftSourceFinder.swiftFiles(
        in: project,
        excluding: [project.appendingPathComponent("output", isDirectory: true)]
    ).map(\.path)

    #expect(files == [source.standardizedFileURL.path])
}

@Test func indexSourceManifestRejectsChangedSources() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try "let value = 1\n".write(to: file, atomically: true, encoding: .utf8)

    let originalCache = try SourceFileCache(paths: [file.path])
    let manifest = try IndexSourceManifest.capture(sourceCache: originalCache)
    try "let value = 2\n".write(to: file, atomically: true, encoding: .utf8)
    let changedCache = try SourceFileCache(paths: [file.path])

    do {
        try manifest.validate(sourceCache: changedCache)
        Issue.record("Expected changed source validation to fail")
    } catch let error as IndexSourceManifestError {
        #expect(error.localizedDescription.contains("Swift source changed since indexing"))
    }
}

@Test func indexSourceManifestRoundTripsAndValidatesExactSources() throws {
    let directory = try makeTemporaryDirectory()
    let sourceA = directory.appendingPathComponent("A.swift")
    let sourceB = directory.appendingPathComponent("B.swift")
    let manifestURL = directory.appendingPathComponent("manifest.json")
    try "struct A {}\n".write(to: sourceA, atomically: true, encoding: .utf8)
    try "struct B {}\n".write(to: sourceB, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [sourceB.path, sourceA.path])

    let manifest = try IndexSourceManifest.capture(sourceCache: cache)
    try manifest.save(to: manifestURL)
    let loaded = try IndexSourceManifest.load(from: manifestURL)
    try loaded.validate(sourceCache: cache)

    #expect(loaded.entries.map(\.path) == cache.allPaths)
    #expect(loaded.entries.allSatisfy { $0.sha256.count == 64 })
}

@Test func indexSnapshotCacheRoundTripsNormalizedSnapshot() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let cacheURL = directory.appendingPathComponent("snapshot.plist")
    try "struct Sample {}\n".write(to: file, atomically: true, encoding: .utf8)
    let sourceCache = try SourceFileCache(paths: [file.path])
    let manifest = try IndexSourceManifest.capture(sourceCache: sourceCache)
    let symbol = IndexSnapshot.Symbol(
        usr: "usr-sample",
        name: "Sample",
        kind: "struct",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = IndexSnapshot.Occurrence(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "Sample", in: "struct Sample {}"),
        moduleName: "SampleModule",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "declaration",
        symbolProvider: "swift",
        relations: [
            IndexSnapshot.Relation(usr: "usr-owner", name: "Owner", rolesRaw: 2, roles: ["childOf"])
        ]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [symbol],
        occurrences: [occurrence]
    )

    try IndexSnapshotCache.save(snapshot: snapshot, sourceManifest: manifest, to: cacheURL)
    let cacheObject = try #require(
        PropertyListSerialization.propertyList(
            from: Data(contentsOf: cacheURL),
            format: nil
        ) as? [String: Any]
    )
    #expect(
        Set(cacheObject.keys) == [
            "formatVersion", "occurrences", "paths", "sourceFilePathIndices", "sourceManifest",
            "symbols",
        ])
    let cachedSymbol = try #require((cacheObject["symbols"] as? [[String: Any]])?.first)
    #expect(
        Set(cachedSymbol.keys) == [
            "kind", "language", "name", "properties", "propertiesRaw", "usr",
        ])
    let cachedOccurrence = try #require(
        (cacheObject["occurrences"] as? [[String: Any]])?.first
    )
    #expect(
        Set(cachedOccurrence.keys) == [
            "isSystem",
            "line",
            "moduleName",
            "pathIndex",
            "relations",
            "roles",
            "rolesDescription",
            "rolesRaw",
            "symbolIndex",
            "symbolProvider",
            "utf8Column",
        ])
    let cachedRelation = try #require(
        (cachedOccurrence["relations"] as? [[String: Any]])?.first
    )
    #expect(Set(cachedRelation.keys) == ["name", "roles", "rolesRaw", "usr"])
    let loaded = try IndexSnapshotCache.load(from: cacheURL, sourceManifest: manifest)

    #expect(loaded.sourceFiles == snapshot.sourceFiles)
    #expect(loaded.symbols == snapshot.symbols)
    #expect(loaded.occurrences == snapshot.occurrences)
}

@Test func semanticIndexDerivesOwnershipAndRuntimeContractsFromIndexRelations() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("SemanticIndex.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let service = testSymbol("s:6Sample7ServiceP", "Service", .protocol)
    let requirement = testSymbol("s:6Sample7ServiceP3runyyF", "run()", .instanceMethod)
    let localModel = testSymbol("s:6Sample10LocalModelV", "LocalModel", .struct)
    let localExtension = testSymbol("s:e:local-model", "LocalModel", .extension)
    let localHelper = testSymbol(
        "s:6Sample10LocalModelV11localHelperyyF", "localHelper()", .instanceMethod)
    let string = testSymbol("s:SS", "String", .struct)
    let externalExtension = testSymbol("s:e:string", "String", .extension)
    let externalNested = testSymbol("s:external-nested", "ExternalNested", .struct)
    let externalHelper = testSymbol("s:external-helper", "externalHelper()", .instanceMethod)
    let localObjCModel = testSymbol("c:@M@Sample@objc(cs)LocalObjCModel", "LocalObjCModel", .class)
    let localObjCExtension = testSymbol("s:e:local-objc-model", "LocalObjCModel", .extension)
    let localObjCHelper = testSymbol("s:local-objc-helper", "localObjCHelper()", .instanceMethod)
    let runtimeOwner = testSymbol("c:@M@Sample@objc(cs)RuntimeOwner", "RuntimeOwner", .class)
    let runtimeNested = testSymbol("s:runtime-nested", "RuntimeNested", .struct)
    let runtimeValue = testSymbol("s:runtime-value", "value", .instanceProperty)
    let dynamicEntry = testSymbol("s:dynamic-entry", "compilerDynamicallyDispatched()", .function)
    let outlet = testSymbol("s:outlet", "outlet", .variable, propertiesRaw: 1 << 4)
    let runtimeBaseMethod = testSymbol(
        "c:@M@Sample@objc(cs)RuntimeBase(im)run", "run()", .instanceMethod)
    let runtimeOverride = testSymbol("s:runtime-override", "run()", .instanceMethod)
    let localSwiftSubclass = testSymbol(
        "s:6Sample18LocalSwiftSubclassC", "LocalSwiftSubclass", .class)

    let occurrences = [
        testOccurrence(service, path: file.path, line: 1, token: "Service", roles: [.definition]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 1,
            token: "run",
            roles: [.definition, .childOf],
            relations: [testRelation(service, .childOf)]
        ),
        testOccurrence(
            localModel, path: file.path, line: 2, token: "LocalModel", roles: [.definition]),
        testOccurrence(
            localModel,
            path: file.path,
            line: 3,
            token: "LocalModel",
            roles: [.reference, .extendedBy],
            relations: [testRelation(localExtension, .extendedBy)]
        ),
        testOccurrence(
            localExtension, path: file.path, line: 3, token: "LocalModel", roles: [.definition]),
        testOccurrence(
            localHelper,
            path: file.path,
            line: 3,
            token: "localHelper",
            roles: [.definition, .childOf],
            relations: [testRelation(localExtension, .childOf)]
        ),
        testOccurrence(
            string,
            path: file.path,
            line: 4,
            token: "String",
            roles: [.reference, .extendedBy],
            relations: [testRelation(externalExtension, .extendedBy)]
        ),
        testOccurrence(
            externalExtension, path: file.path, line: 4, token: "String", roles: [.definition]),
        testOccurrence(
            externalNested,
            path: file.path,
            line: 4,
            token: "ExternalNested",
            roles: [.definition, .childOf],
            relations: [testRelation(externalExtension, .childOf)]
        ),
        testOccurrence(
            externalHelper,
            path: file.path,
            line: 4,
            token: "externalHelper",
            roles: [.definition, .childOf],
            relations: [testRelation(externalNested, .childOf)]
        ),
        testOccurrence(
            localObjCModel, path: file.path, line: 5, token: "LocalObjCModel", roles: [.definition]),
        testOccurrence(
            localObjCModel,
            path: file.path,
            line: 6,
            token: "LocalObjCModel",
            roles: [.reference, .extendedBy],
            relations: [testRelation(localObjCExtension, .extendedBy)]
        ),
        testOccurrence(
            localObjCExtension, path: file.path, line: 6, token: "LocalObjCModel",
            roles: [.definition]),
        testOccurrence(
            localObjCHelper,
            path: file.path,
            line: 6,
            token: "localObjCHelper",
            roles: [.definition, .childOf],
            relations: [testRelation(localObjCExtension, .childOf)]
        ),
        testOccurrence(
            runtimeOwner, path: file.path, line: 7, token: "RuntimeOwner", roles: [.definition]),
        testOccurrence(
            runtimeNested,
            path: file.path,
            line: 7,
            token: "RuntimeNested",
            roles: [.definition, .childOf],
            relations: [testRelation(runtimeOwner, .childOf)]
        ),
        testOccurrence(
            runtimeValue,
            path: file.path,
            line: 7,
            token: "value",
            roles: [.definition, .childOf],
            relations: [testRelation(runtimeNested, .childOf)]
        ),
        testOccurrence(
            dynamicEntry,
            path: file.path,
            line: 8,
            token: "compilerDynamicallyDispatched",
            roles: [.definition, .dynamic]
        ),
        testOccurrence(outlet, path: file.path, line: 9, token: "outlet", roles: [.definition]),
        IndexSnapshot.Occurrence(
            symbol: runtimeOverride,
            path: file.path,
            line: 10,
            utf8Column: utf8Column(of: "run", in: lines[9]),
            moduleName: "Sample",
            isSystem: false,
            rolesRaw: 1,
            roles: ["definition", "overrideOf"],
            rolesDescription: "[definition|overrideOf]",
            symbolProvider: "swift",
            relations: [testRelation(runtimeBaseMethod, .overrideOf)]
        ),
        testOccurrence(
            localSwiftSubclass,
            path: file.path,
            line: 11,
            token: "LocalSwiftSubclass",
            roles: [.definition]
        ),
        testOccurrence(
            runtimeOwner,
            path: file.path,
            line: 11,
            token: "RuntimeOwner",
            roles: [.reference, .baseOf],
            relations: [testRelation(localSwiftSubclass, .baseOf)]
        ),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            service, requirement, localModel, localExtension, localHelper, string,
            externalExtension, externalNested, externalHelper, localObjCModel,
            localObjCExtension, localObjCHelper, runtimeOwner, runtimeNested,
            runtimeValue, dynamicEntry, outlet, runtimeBaseMethod, runtimeOverride,
            localSwiftSubclass,
        ],
        occurrences: occurrences
    )
    let semanticIndex = SemanticIndex(snapshot: snapshot, obfuscationRoots: [directory])

    #expect(semanticIndex.protocolRequirementUSRs == [requirement.usr])
    #expect(semanticIndex.externallyOwnedUSRs.contains(externalExtension.usr))
    #expect(semanticIndex.externallyOwnedUSRs.contains(externalNested.usr))
    #expect(semanticIndex.externallyOwnedUSRs.contains(externalHelper.usr))
    #expect(semanticIndex.selectedDeclarationUSRs.contains(externalExtension.usr))
    #expect(semanticIndex.selectedDeclarationUSRs.contains(externalNested.usr))
    #expect(semanticIndex.selectedDeclarationUSRs.contains(externalHelper.usr))
    #expect(!semanticIndex.externallyOwnedUSRs.contains(localExtension.usr))
    #expect(!semanticIndex.externallyOwnedUSRs.contains(localHelper.usr))
    #expect(!semanticIndex.externallyOwnedUSRs.contains(localObjCExtension.usr))
    #expect(!semanticIndex.externallyOwnedUSRs.contains(localObjCHelper.usr))
    #expect(semanticIndex.runtimeSensitiveUSRs.contains(runtimeOwner.usr))
    #expect(!semanticIndex.runtimeSensitiveUSRs.contains(runtimeNested.usr))
    #expect(!semanticIndex.runtimeSensitiveUSRs.contains(runtimeValue.usr))
    #expect(!semanticIndex.runtimeSensitiveUSRs.contains(dynamicEntry.usr))
    #expect(semanticIndex.runtimeSensitiveUSRs.contains(outlet.usr))
    #expect(semanticIndex.runtimeSensitiveUSRs.contains(runtimeBaseMethod.usr))
    #expect(semanticIndex.runtimeSensitiveUSRs.contains(runtimeOverride.usr))
    #expect(!semanticIndex.runtimeSensitiveUSRs.contains(localSwiftSubclass.usr))

    let groups = Dictionary(uniqueKeysWithValues: snapshot.occurrenceGroups.map { ($0.usr, $0) })
    let analyzer = RenameEligibilityAnalyzer(sourceRoot: directory)
    let requirementDecision = analyzer.analyze(
        group: try #require(groups[requirement.usr]),
        sourceCache: cache,
        semanticIndex: semanticIndex
    )
    let externalDecision = analyzer.analyze(
        group: try #require(groups[externalHelper.usr]),
        sourceCache: cache,
        semanticIndex: semanticIndex
    )
    let localDecision = analyzer.analyze(
        group: try #require(groups[localHelper.usr]),
        sourceCache: cache,
        semanticIndex: semanticIndex
    )
    let runtimeDecision = analyzer.analyze(
        group: try #require(groups[runtimeOverride.usr]),
        sourceCache: cache,
        semanticIndex: semanticIndex,
        overrideRelatedUSRs: [runtimeBaseMethod.usr, runtimeOverride.usr],
        coordinatedRelatedUSRs: [runtimeBaseMethod.usr, runtimeOverride.usr]
    )

    #expect(
        requirementDecision.reasons.contains(
            "protocol members require relation-aware witness renaming"))
    #expect(externalDecision.isEligible)
    #expect(localDecision.isEligible)
    #expect(
        runtimeDecision.reasons.contains(
            "runtime-reflected or externally linked declaration according to IndexStore semantics"))
}

@Test func renamePlanCacheRequiresMatchingToolAndInputs() throws {
    let directory = try makeTemporaryDirectory()
    let tool = directory.appendingPathComponent("tool")
    let source = directory.appendingPathComponent("Sample.swift")
    let cacheURL = directory.appendingPathComponent("plan.plist")
    try "tool-v1".write(to: tool, atomically: true, encoding: .utf8)
    try "let value = 1\n".write(to: source, atomically: true, encoding: .utf8)
    let sourceCache = try SourceFileCache(paths: [source.path])
    let manifest = try IndexSourceManifest.capture(sourceCache: sourceCache)
    let mappingStore = RenameMappingStore()
    let key = try RenamePlanCache.Key.make(
        toolURL: tool,
        sourceManifest: manifest,
        obfuscationRoots: [directory],
        mappingStore: mappingStore
    )
    let value = RenamePlanCache.Value(
        plan: RenamePlan(renames: [], rejections: [], editConflicts: []),
        outputRenames: [],
        sourceFiles: [source.path],
        indexedSymbolCount: 2,
        indexedOccurrenceCount: 3
    )
    try RenamePlanCache.save(value, key: key, to: cacheURL)
    let cacheObject = try #require(
        PropertyListSerialization.propertyList(
            from: Data(contentsOf: cacheURL),
            format: nil
        ) as? [String: Any]
    )
    #expect(Set(cacheObject.keys) == ["formatVersion", "key", "value"])
    let persistedKey = try #require(cacheObject["key"] as? [String: Any])
    #expect(
        Set(persistedKey.keys) == [
            "inputMappingEntries", "obfuscationRoots", "sourceManifest", "toolSHA256",
        ])
    let persistedValue = try #require(cacheObject["value"] as? [String: Any])
    #expect(
        Set(persistedValue.keys) == [
            "indexedOccurrenceCount",
            "indexedSymbolCount",
            "outputMappingEntries",
            "plan",
            "sourceFiles",
        ])

    let hit = try RenamePlanCache.load(from: cacheURL, matching: key)
    #expect(hit?.indexedSymbolCount == 2)
    #expect(hit?.indexedOccurrenceCount == 3)

    try "tool-v2".write(to: tool, atomically: true, encoding: .utf8)
    let changedToolKey = try RenamePlanCache.Key.make(
        toolURL: tool,
        sourceManifest: manifest,
        obfuscationRoots: [directory],
        mappingStore: mappingStore
    )
    #expect(try RenamePlanCache.load(from: cacheURL, matching: changedToolKey) == nil)
}

@Test func persistedRenameModelsKeepTheirWireKeys() throws {
    func encodedKeys<T: Encodable>(_ value: T) throws -> Set<String> {
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        )
        return Set(object.keys)
    }

    func reportKeys(_ key: String, in object: [String: Any]) throws -> Set<String> {
        Set(try #require(object[key] as? [String: Any]).keys)
    }

    let decision = RenameEligibility(
        usr: "usr-value",
        symbolName: "value",
        symbolKind: "variable",
        isEligible: false,
        originalName: "value",
        reasons: ["denied"]
    )
    let edit = SourcePatcher.Edit(
        path: "/tmp/Value.swift",
        byteOffset: 4,
        length: 5,
        line: 1,
        utf8Column: 5,
        oldName: "value",
        newName: "oa",
        usr: "usr-value"
    )
    let plan = RenamePlan(
        renames: [
            RenamePlan.Entry(
                usr: "usr-value",
                kind: "variable",
                oldName: "value",
                newName: "oa",
                edits: [edit]
            )
        ],
        rejections: [decision],
        editConflicts: []
    )
    let planObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any]
    )

    #expect(
        Set(planObject.keys) == [
            "compilerRawValueFacts",
            "conflicts",
            "denied",
            "entries",
            "enumCaseComponentFacts",
            "enumCaseSyntaxFacts",
            "genericParameterSyntaxFacts",
            "parameterCallArgumentBindingFacts",
            "parameterCallSiteSyntaxFacts",
            "parameterCallableReferenceBindingFacts",
            "parameterCallableReferenceSyntaxFacts",
            "parameterExternalLabelComponentFacts",
            "parameterExternalLabelRenameOutcome",
            "parameterFacts",
            "parameterLocalBindingOutcome",
            "parameterSyntaxFacts",
            "supportReplacements",
            "typealiasSyntaxFacts",
        ])

    let renameObjects = try #require(planObject["entries"] as? [[String: Any]])
    let renameObject = try #require(renameObjects.first)
    #expect(Set(renameObject.keys) == ["kind", "newName", "oldName", "replacements", "usr"])
    let editObjects = try #require(renameObject["replacements"] as? [[String: Any]])
    #expect(
        Set(try #require(editObjects.first).keys) == [
            "byteOffset", "length", "line", "newName", "oldName", "path", "usr", "utf8Column",
        ])

    #expect(
        try reportKeys("parameterFacts", in: planObject) == [
            "callAnchors",
            "components",
            "componentsWithOccurrencesOutsideSelectedRoots",
            "distinctLabelAndBindingParameters",
            "enumCaseComponents",
            "enumCaseParameters",
            "enumCaseReferenceAnchors",
            "explicitParameters",
            "externallyOwnedComponents",
            "functionReferenceAnchors",
            "modeledParameters",
            "omittedExternalLabels",
            "overrideRelatedComponents",
            "protocolRequirementComponents",
            "runtimeSensitiveComponents",
            "sharedLabelAndBindingParameters",
            "structurallyCompleteComponents",
            "structurallyCompleteParameters",
            "subscriptComponents",
            "subscriptParameters",
            "unavailableExternalLabels",
            "unmodeledParameters",
        ])

    #expect(
        try reportKeys("parameterCallSiteSyntaxFacts", in: planObject) == [
            "additionalTrailingClosureLabelTokens",
            "callsWithoutExplicitArgumentDelimiters",
            "componentsWithAllIndexedCallsResolved",
            "componentsWithNamedExternalLabels",
            "componentsWithNonCallReferences",
            "componentsWithoutIndexedCalls",
            "firstTrailingClosures",
            "indexedCallAnchors",
            "namedExternalLabelParameters",
            "namedParametersInComponentsWithAllIndexedCallsResolved",
            "namedParametersInComponentsWithNonCallReferences",
            "namedParametersInComponentsWithoutIndexedCalls",
            "namedParenthesizedArgumentTokens",
            "parenthesizedArguments",
            "resolvedAttributeCalls",
            "resolvedCallAnchors",
            "resolvedEnumCasePatterns",
            "resolvedFunctionCalls",
            "resolvedSubscriptCalls",
            "unlabeledParenthesizedArguments",
            "unresolvedAnchors",
            "unresolvedByReason",
            "unresolvedCallAnchors",
        ])

    #expect(
        try reportKeys("parameterExternalLabelComponentFacts", in: planObject) == [
            "atomicComponents",
            "blockerComponents",
            "blockerNamedParameters",
            "deniedAtomicComponents",
            "deniedComponents",
            "deniedNamedExternalLabelParameters",
            "deniedSourceCallableComponents",
            "eligibleAtomicComponents",
            "eligibleComponents",
            "eligibleNamedExternalLabelParameters",
            "eligibleOverrideRelatedAtomicComponents",
            "eligibleProtocolRelatedAtomicComponents",
            "eligibleRelatedAtomicComponents",
            "eligibleSourceCallableComponents",
            "eligibleStandaloneAtomicComponents",
            "namedExternalLabelParameters",
            "overrideRelatedAtomicComponents",
            "protocolRelatedAtomicComponents",
            "relatedAtomicComponents",
            "sourceCallableComponents",
            "standaloneAtomicComponents",
        ])

    #expect(
        try reportKeys("parameterExternalLabelRenameOutcome", in: planObject) == [
            "candidateAtomicComponents",
            "candidateParameterUSRs",
            "deniedAtomicComponents",
            "deniedComponents",
            "deniedParameterUSRs",
            "renamedAtomicComponents",
            "renamedParameterUSRs",
            "unclassifiedAtomicComponents",
            "unclassifiedParameterUSRs",
        ])

    #expect(
        try reportKeys("parameterLocalBindingOutcome", in: planObject) == [
            "candidates",
            "denialCategories",
            "denied",
            "deniedCandidateUSRs",
            "renamed",
            "unclassified",
        ])

    #expect(
        try reportKeys("enumCaseComponentFacts", in: planObject) == [
            "associatedValueCases",
            "associatedValueParameters",
            "casesWithOccurrencesOutsideSelectedRoots",
            "casesWithoutRawSerializationOrRuntimeContracts",
            "components",
            "explicitEnumCases",
            "externallyOwnedCases",
            "externallyOwnedOwnerComponents",
            "ownerComponents",
            "ownerComponentsWithOccurrencesOutsideSelectedRoots",
            "protocolConformanceCases",
            "protocolConformanceOwnerComponents",
            "protocolWitnessCases",
            "protocolWitnessOwnerComponents",
            "rawTypeCases",
            "rawTypeOwnerComponents",
            "resolvedEnumCases",
            "runtimeSensitiveCases",
            "runtimeSensitiveOwnerComponents",
            "serializationSensitiveCases",
            "serializationSensitiveOwnerComponents",
            "unresolved",
            "unresolvedEnumCases",
        ])

    #expect(
        try reportKeys("enumCaseSyntaxFacts", in: planObject) == [
            "blockerCases",
            "blockerOwnerComponents",
            "casesByOwnerAccessLevel",
            "casesDirectlyInterpolated",
            "casesWithDeclarationAttributes",
            "casesWithMatchingStringLiterals",
            "components",
            "directInterpolationReferences",
            "explicitEnumCases",
            "indexedReferenceOccurrences",
            "matchingStringLiteralTokens",
            "ownerComponents",
            "ownerComponentsByAccessLevel",
            "ownerComponentsWithDeclarationAttributes",
            "preliminaryEligibleAssociatedValueCases",
            "preliminaryEligibleAssociatedValueParameters",
            "preliminaryEligibleCases",
            "preliminaryEligibleOwnerComponents",
            "preliminaryEligibleSimpleCases",
            "resolvedEnumCases",
            "resolvedReferenceOccurrences",
            "unresolved",
            "unresolvedEnumCases",
            "unresolvedReferenceOccurrences",
        ])

    #expect(
        try reportKeys("typealiasSyntaxFacts", in: planObject) == [
            "directTupleTypealiases",
            "functionTypealiases",
            "indexedTypealiasDeclarations",
            "otherTypealiases",
            "resolvedTypealiasDeclarations",
            "syntaxDeclarationsWithoutIndexedUSR",
            "syntaxTypealiasDeclarations",
            "tupleRelatedOwnerUSRs",
            "unresolvedByReason",
            "unresolvedTypealiasDeclarations",
        ])

    let denied = try #require(planObject["denied"] as? [[String: Any]])
    #expect(
        Set(try #require(denied.first).keys) == [
            "allowed", "kind", "oldName", "reasons", "symbolName", "usr",
        ])

    let cacheKey = RenamePlanCache.Key(
        toolSHA256: "digest",
        sourceManifest: IndexSourceManifest(formatVersion: 1, entries: []),
        obfuscationRoots: ["/project"],
        inputRenames: []
    )
    let cacheKeyObject = try #require(
        PropertyListSerialization.propertyList(
            from: PropertyListEncoder().encode(cacheKey),
            format: nil
        ) as? [String: Any]
    )
    #expect(
        Set(cacheKeyObject.keys) == [
            "inputMappingEntries", "obfuscationRoots", "sourceManifest", "toolSHA256",
        ])

    let mappingFile = RenameMappingStore.File(
        version: 1,
        generatedAt: "2026-01-01T00:00:00Z",
        renames: []
    )
    #expect(try encodedKeys(mappingFile) == ["entries", "generatedAt", "version"])

    let eligibleFamily = ExternalLabel.EligibleFamily(
        key: "family",
        relatedCallableUSRs: [],
        sourceCallableUSRs: [],
        slots: []
    )
    #expect(
        try encodedKeys(eligibleFamily) == [
            "key", "ordinalComponents", "relatedCallableUSRs", "sourceCallableUSRs",
        ])

    let blockedFamily = ExternalLabel.BlockedFamily(
        key: "family",
        relatedCallableUSRs: [],
        sourceCallableUSRs: [],
        labeledParameterUSRs: [],
        blockers: [],
        blockerDetails: []
    )
    #expect(
        try encodedKeys(blockedFamily) == [
            "blockerDetails",
            "blockers",
            "key",
            "namedParameterUSRs",
            "relatedCallableUSRs",
            "sourceCallableUSRs",
        ])

    let cohortMember = CoverageCohortMember(
        usr: "usr-value",
        originalName: "value",
        kind: "variable",
        baselineStatus: .notRenamed,
        baselineRejectionCategories: [.overrideBaseFamily]
    )
    #expect(
        try encodedKeys(cohortMember) == [
            "baselineDenialCategories", "baselineStatus", "kind", "originalName", "usr",
        ])

    let coverageMember = CoverageMemberResult(
        usr: "usr-value",
        originalName: "value",
        kind: "variable",
        status: .rejected,
        newName: "Ob",
        rejectionCategories: [.overrideBaseFamily],
        rejectionReasons: ["reason"]
    )
    #expect(
        try encodedKeys(coverageMember) == [
            "denialCategories", "denialReasons", "kind", "newName", "originalName", "status", "usr",
        ])

    let coverageReport = CoverageReport(
        formatVersion: CoverageReport.currentFormatVersion,
        cohortIdentifier: "cohort",
        cohortMembersSHA256: "digest",
        denominator: 1,
        renamed: 0,
        rejected: 1,
        missingFromIndex: 0,
        unclassified: 0,
        coveragePercent: 0,
        indexedSymbols: 1,
        indexedOccurrences: 1,
        plannedSymbols: 0,
        plannedReplacements: 0,
        editConflicts: 0,
        bySymbolKind: [],
        primaryRejectionReasons: [],
        allRejectionReasons: [],
        syntheticAccessors: SyntheticAccessorSummary(
            total: 0,
            getters: 0,
            setters: 0,
            other: 0,
            derivedRenamed: 0,
            derivedUnchanged: 0,
            unresolvedParent: 0,
            unexpectedlyPlanned: 0
        ),
        members: [coverageMember]
    )
    #expect(
        try encodedKeys(coverageReport) == [
            "allDenialReasons",
            "bySymbolKind",
            "cohortIdentifier",
            "cohortMembersSHA256",
            "conflicts",
            "coveragePercent",
            "denied",
            "denominator",
            "formatVersion",
            "indexedOccurrences",
            "indexedSymbols",
            "members",
            "missingFromIndex",
            "plannedReplacements",
            "plannedSymbols",
            "primaryDenialReasons",
            "renamed",
            "syntheticAccessors",
            "unclassified",
        ])
    #expect(
        String(
            decoding: try JSONEncoder().encode(CoverageRejectionCategory.overrideBaseFamily),
            as: UTF8.self)
            == "\"overrideBaseComponent\""
    )
}

@Test func persistedFormatVersionsStayStable() {
    #expect(IndexSourceManifest.currentFormatVersion == 1)
    #expect(IndexSnapshotCache.currentFormatVersion == 1)
    #expect(RenamePlanCache.currentFormatVersion == 1)
    #expect(RenameMappingStore.currentFormatVersion == 1)
    #expect(CoverageCohort.currentFormatVersion == 1)
    #expect(CoverageReport.currentFormatVersion == 1)
}

@Test func compactDryRunReportKeepsPlanWithoutVerboseDetails() {
    let replacement = SourcePatcher.Edit(
        path: "/tmp/Sample.swift",
        byteOffset: 4,
        length: 5,
        line: 1,
        utf8Column: 5,
        oldName: "value",
        newName: "Oa",
        usr: "usr-value"
    )
    let plan = RenamePlan(
        renames: [
            RenamePlan.Entry(
                usr: "usr-value",
                kind: "variable",
                oldName: "value",
                newName: "Oa",
                edits: [replacement]
            )
        ],
        rejections: [
            RenameEligibility(
                usr: "usr-public",
                symbolName: "publicValue",
                symbolKind: "variable",
                isEligible: false,
                originalName: "publicValue",
                reasons: ["externally visible"]
            )
        ],
        editConflicts: []
    )

    let report = ReportRenderer.renderDryRun(plan: plan, compact: true)

    #expect(report.contains("value -> Oa"))
    #expect(report.contains("per-symbol denial details omitted"))
    #expect(!report.contains("/tmp/Sample.swift:1:5"))
    #expect(!report.contains("publicValue"))
}

@Test func sourcePatcherAppliesDescendingReplacements() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    try "let alpha = beta + alpha\n".write(to: file, atomically: true, encoding: .utf8)

    let source = try SourceFile(path: file.path)
    let first = try #require(source.identifierToken(line: 1, utf8Column: 5))
    let second = try #require(source.identifierToken(line: 1, utf8Column: 20))
    let replacements = [
        SourcePatcher.Edit(
            path: file.path, byteOffset: first.byteRange.lowerBound, length: first.byteRange.count,
            line: 1,
            utf8Column: 5, oldName: "alpha", newName: "_oa", usr: "usr-alpha"),
        SourcePatcher.Edit(
            path: file.path, byteOffset: second.byteRange.lowerBound,
            length: second.byteRange.count, line: 1,
            utf8Column: 20, oldName: "alpha", newName: "_oa", usr: "usr-alpha"),
    ]

    try SourcePatcher().apply(replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched == "let _oa = beta + _oa\n")
}

@Test func sourcePatcherWritesSwiftFilesToMatchingOutputPaths() throws {
    let project = try makeTemporaryDirectory()
    let sources = project.appendingPathComponent("Sources", isDirectory: true)
    let output = project.appendingPathComponent("obfuscated", isDirectory: true)
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)

    let patchedSource = sources.appendingPathComponent("Patched.swift")
    let unchangedSource = sources.appendingPathComponent("Unchanged.swift")
    try "let alpha = alpha\n".write(to: patchedSource, atomically: true, encoding: .utf8)
    try "let beta = 1\n".write(to: unchangedSource, atomically: true, encoding: .utf8)

    let source = try SourceFile(path: patchedSource.path)
    let first = try #require(source.identifierToken(line: 1, utf8Column: 5))
    let second = try #require(source.identifierToken(line: 1, utf8Column: 13))
    let replacements = [
        SourcePatcher.Edit(
            path: patchedSource.path, byteOffset: first.byteRange.lowerBound,
            length: first.byteRange.count, line: 1,
            utf8Column: 5, oldName: "alpha", newName: "_oa", usr: "usr-alpha"),
        SourcePatcher.Edit(
            path: patchedSource.path, byteOffset: second.byteRange.lowerBound,
            length: second.byteRange.count, line: 1,
            utf8Column: 13, oldName: "alpha", newName: "_oa", usr: "usr-alpha"),
    ]

    let written = try SourcePatcher().writePatchedCopies(
        sourceFiles: [patchedSource.path, unchangedSource.path],
        edits: replacements,
        sourceRoot: project,
        outputRoot: output
    )

    #expect(
        written.map(\.path).sorted()
            == [
                output.appendingPathComponent("Sources").appendingPathComponent("Patched.swift")
                    .path,
                output.appendingPathComponent("Sources").appendingPathComponent("Unchanged.swift")
                    .path,
            ].sorted())
    #expect(
        try String(
            contentsOf: output.appendingPathComponent("Sources").appendingPathComponent(
                "Patched.swift"),
            encoding: .utf8) == "let _oa = _oa\n")
    #expect(
        try String(
            contentsOf: output.appendingPathComponent("Sources").appendingPathComponent(
                "Unchanged.swift"),
            encoding: .utf8) == "let beta = 1\n")
    #expect(try String(contentsOf: patchedSource, encoding: .utf8) == "let alpha = alpha\n")
}

@Test func sourcePatcherWritesExternalReplacementFilesToOutputPaths() throws {
    let project = try makeTemporaryDirectory()
    let selected = project.appendingPathComponent("Selected", isDirectory: true)
    let other = project.appendingPathComponent("Other", isDirectory: true)
    let output = project.appendingPathComponent("obfuscated", isDirectory: true)
    try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

    let declarationFile = selected.appendingPathComponent("Declaration.swift")
    let referenceFile = other.appendingPathComponent("Reference.swift")
    let declarationLine = "struct LocalModel {}"
    let referenceLine = "let metatype = LocalModel.self"
    try (declarationLine + "\n").write(to: declarationFile, atomically: true, encoding: .utf8)
    try (referenceLine + "\n").write(to: referenceFile, atomically: true, encoding: .utf8)

    let declarationSource = try SourceFile(path: declarationFile.path)
    let referenceSource = try SourceFile(path: referenceFile.path)
    let declarationToken = try #require(
        declarationSource.identifierToken(
            line: 1, utf8Column: utf8Column(of: "LocalModel", in: declarationLine)))
    let referenceToken = try #require(
        referenceSource.identifierToken(
            line: 1, utf8Column: utf8Column(of: "LocalModel", in: referenceLine)))
    let replacements = [
        SourcePatcher.Edit(
            path: declarationFile.path, byteOffset: declarationToken.byteRange.lowerBound,
            length: declarationToken.byteRange.count, line: 1,
            utf8Column: utf8Column(of: "LocalModel", in: declarationLine), oldName: "LocalModel",
            newName: "_oa",
            usr: "usr-localModel"),
        SourcePatcher.Edit(
            path: referenceFile.path, byteOffset: referenceToken.byteRange.lowerBound,
            length: referenceToken.byteRange.count, line: 1,
            utf8Column: utf8Column(of: "LocalModel", in: referenceLine), oldName: "LocalModel",
            newName: "_oa",
            usr: "usr-localModel"),
    ]

    let written = try SourcePatcher().writePatchedCopies(
        sourceFiles: [declarationFile.path],
        edits: replacements,
        sourceRoot: project,
        outputRoot: output
    )

    #expect(
        written.map(\.path).sorted()
            == [
                output.appendingPathComponent("Selected").appendingPathComponent(
                    "Declaration.swift"
                ).path,
                output.appendingPathComponent("Other").appendingPathComponent("Reference.swift")
                    .path,
            ].sorted())
    #expect(
        try String(
            contentsOf: output.appendingPathComponent("Selected").appendingPathComponent(
                "Declaration.swift"),
            encoding: .utf8) == "struct _oa {}\n")
    #expect(
        try String(
            contentsOf: output.appendingPathComponent("Other").appendingPathComponent(
                "Reference.swift"),
            encoding: .utf8) == "let metatype = _oa.self\n")
    #expect(try String(contentsOf: referenceFile, encoding: .utf8) == referenceLine + "\n")
}
