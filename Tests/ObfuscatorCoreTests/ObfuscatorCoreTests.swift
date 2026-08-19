import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Naming and infrastructure

@Test func nameGeneratorProducesStableNames() {
    var generator = NameGenerator(prefix: "_o")
    #expect(generator.nextName(avoiding: []) == "_oa")
    #expect(generator.nextName(avoiding: ["_ob"]) == "_oc")
}

@Test func nameGeneratorDefaultPrefixAvoidsLeadingUnderscore() {
    var generator = NameGenerator()
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
            arguments: ["-c", "i=1; while [ $i -le 130 ]; do printf 'line-%03d\\n' \"$i\"; i=$((i + 1)); done; exit 7"]
        )
        Issue.record("Expected command failure")
    } catch let error as CommandRunnerError {
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
    #expect(!result.succeeded)
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
    try FileManager.default.createDirectory(at: buildBackupSources, withIntermediateDirectories: true)
    let source = sources.appendingPathComponent("main.swift")
    let copiedSource = outputSources.appendingPathComponent("main.swift")
    let generatedSource = derivedSources.appendingPathComponent("Generated.swift")
    let cachedSource = buildBackupSources.appendingPathComponent("Dependency.swift")
    try "print(\"source\")\n".write(to: source, atomically: true, encoding: .utf8)
    try "print(\"copied\")\n".write(to: copiedSource, atomically: true, encoding: .utf8)
    try "print(\"generated\")\n".write(to: generatedSource, atomically: true, encoding: .utf8)
    try "print(\"cached\")\n".write(to: cachedSource, atomically: true, encoding: .utf8)

    let files = try SourceFileFinder.swiftFiles(
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

@Test func indexSnapshotCacheRoundTripsNormalizedRecords() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let cacheURL = directory.appendingPathComponent("snapshot.plist")
    try "struct Sample {}\n".write(to: file, atomically: true, encoding: .utf8)
    let sourceCache = try SourceFileCache(paths: [file.path])
    let manifest = try IndexSourceManifest.capture(sourceCache: sourceCache)
    let symbol = SymbolRecord(
        usr: "usr-sample",
        name: "Sample",
        kind: "struct",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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
            RelationRecord(usr: "usr-owner", name: "Owner", rolesRaw: 2, roles: ["childOf"])
        ]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [symbol],
        occurrences: [occurrence]
    )

    try IndexSnapshotCache.save(snapshot: snapshot, sourceManifest: manifest, to: cacheURL)
    let loaded = try IndexSnapshotCache.load(from: cacheURL, sourceManifest: manifest)

    #expect(loaded.sourceFiles == snapshot.sourceFiles)
    #expect(loaded.symbols == snapshot.symbols)
    #expect(loaded.occurrences == snapshot.occurrences)
}

@Test func indexedSemanticFactsDeriveOwnershipAndRuntimeContractsFromIndexRelations() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("SemanticFacts.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let service = testSymbol("s:6Sample7ServiceP", "Service", .protocol)
    let requirement = testSymbol("s:6Sample7ServiceP3runyyF", "run()", .instanceMethod)
    let localModel = testSymbol("s:6Sample10LocalModelV", "LocalModel", .struct)
    let localExtension = testSymbol("s:e:local-model", "LocalModel", .extension)
    let localHelper = testSymbol("s:6Sample10LocalModelV11localHelperyyF", "localHelper()", .instanceMethod)
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
    let runtimeBaseMethod = testSymbol("c:@M@Sample@objc(cs)RuntimeBase(im)run", "run()", .instanceMethod)
    let runtimeOverride = testSymbol("s:runtime-override", "run()", .instanceMethod)
    let localSwiftSubclass = testSymbol("s:6Sample18LocalSwiftSubclassC", "LocalSwiftSubclass", .class)

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
        testOccurrence(localModel, path: file.path, line: 2, token: "LocalModel", roles: [.definition]),
        testOccurrence(
            localModel,
            path: file.path,
            line: 3,
            token: "LocalModel",
            roles: [.reference, .extendedBy],
            relations: [testRelation(localExtension, .extendedBy)]
        ),
        testOccurrence(localExtension, path: file.path, line: 3, token: "LocalModel", roles: [.definition]),
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
        testOccurrence(externalExtension, path: file.path, line: 4, token: "String", roles: [.definition]),
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
        testOccurrence(localObjCModel, path: file.path, line: 5, token: "LocalObjCModel", roles: [.definition]),
        testOccurrence(
            localObjCModel,
            path: file.path,
            line: 6,
            token: "LocalObjCModel",
            roles: [.reference, .extendedBy],
            relations: [testRelation(localObjCExtension, .extendedBy)]
        ),
        testOccurrence(localObjCExtension, path: file.path, line: 6, token: "LocalObjCModel", roles: [.definition]),
        testOccurrence(
            localObjCHelper,
            path: file.path,
            line: 6,
            token: "localObjCHelper",
            roles: [.definition, .childOf],
            relations: [testRelation(localObjCExtension, .childOf)]
        ),
        testOccurrence(runtimeOwner, path: file.path, line: 7, token: "RuntimeOwner", roles: [.definition]),
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
        OccurrenceRecord(
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
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])

    #expect(facts.protocolRequirementUSRs == [requirement.usr])
    #expect(facts.externallyOwnedUSRs.contains(externalExtension.usr))
    #expect(facts.externallyOwnedUSRs.contains(externalNested.usr))
    #expect(facts.externallyOwnedUSRs.contains(externalHelper.usr))
    #expect(facts.selectedDeclarationUSRs.contains(externalExtension.usr))
    #expect(facts.selectedDeclarationUSRs.contains(externalNested.usr))
    #expect(facts.selectedDeclarationUSRs.contains(externalHelper.usr))
    #expect(!facts.externallyOwnedUSRs.contains(localExtension.usr))
    #expect(!facts.externallyOwnedUSRs.contains(localHelper.usr))
    #expect(!facts.externallyOwnedUSRs.contains(localObjCExtension.usr))
    #expect(!facts.externallyOwnedUSRs.contains(localObjCHelper.usr))
    #expect(facts.runtimeSensitiveUSRs.contains(runtimeOwner.usr))
    #expect(!facts.runtimeSensitiveUSRs.contains(runtimeNested.usr))
    #expect(!facts.runtimeSensitiveUSRs.contains(runtimeValue.usr))
    #expect(!facts.runtimeSensitiveUSRs.contains(dynamicEntry.usr))
    #expect(facts.runtimeSensitiveUSRs.contains(outlet.usr))
    #expect(facts.runtimeSensitiveUSRs.contains(runtimeBaseMethod.usr))
    #expect(facts.runtimeSensitiveUSRs.contains(runtimeOverride.usr))
    #expect(!facts.runtimeSensitiveUSRs.contains(localSwiftSubclass.usr))

    let groups = Dictionary(uniqueKeysWithValues: snapshot.groupsByUSR.map { ($0.usr, $0) })
    let analyzer = SafetyAnalyzer(sourceRoot: directory)
    let requirementDecision = analyzer.analyze(
        group: try #require(groups[requirement.usr]),
        sourceCache: cache,
        indexedFacts: facts
    )
    let externalDecision = analyzer.analyze(
        group: try #require(groups[externalHelper.usr]),
        sourceCache: cache,
        indexedFacts: facts
    )
    let localDecision = analyzer.analyze(
        group: try #require(groups[localHelper.usr]),
        sourceCache: cache,
        indexedFacts: facts
    )
    let runtimeDecision = analyzer.analyze(
        group: try #require(groups[runtimeOverride.usr]),
        sourceCache: cache,
        indexedFacts: facts,
        overrideRelatedUSRs: [runtimeBaseMethod.usr, runtimeOverride.usr],
        coordinatedRelatedUSRs: [runtimeBaseMethod.usr, runtimeOverride.usr]
    )

    #expect(requirementDecision.reasons.contains("protocol members require relation-aware witness renaming"))
    #expect(externalDecision.allowed)
    #expect(localDecision.allowed)
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
    let mappingStore = MappingStore()
    let key = try RenamePlanCacheKey.make(
        toolURL: tool,
        sourceManifest: manifest,
        obfuscationRoots: [directory],
        mappingStore: mappingStore
    )
    let value = CachedRenamePlan(
        plan: RenamePlan(entries: [], denied: [], conflicts: []),
        outputMappingEntries: [],
        sourceFiles: [source.path],
        indexedSymbolCount: 2,
        indexedOccurrenceCount: 3
    )
    try RenamePlanCache.save(value, key: key, to: cacheURL)

    let hit = try RenamePlanCache.load(from: cacheURL, matching: key)
    #expect(hit?.indexedSymbolCount == 2)
    #expect(hit?.indexedOccurrenceCount == 3)

    try "tool-v2".write(to: tool, atomically: true, encoding: .utf8)
    let changedToolKey = try RenamePlanCacheKey.make(
        toolURL: tool,
        sourceManifest: manifest,
        obfuscationRoots: [directory],
        mappingStore: mappingStore
    )
    #expect(try RenamePlanCache.load(from: cacheURL, matching: changedToolKey) == nil)
}

@Test func compactDryRunReportKeepsPlanWithoutVerboseDetails() {
    let replacement = SourceReplacement(
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
        entries: [
            RenamePlanEntry(
                usr: "usr-value",
                kind: "variable",
                oldName: "value",
                newName: "Oa",
                replacements: [replacement]
            )
        ],
        denied: [
            SafetyDecision(
                usr: "usr-public",
                symbolName: "publicValue",
                kind: "variable",
                allowed: false,
                oldName: "publicValue",
                reasons: ["externally visible"]
            )
        ],
        conflicts: []
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
        SourceReplacement(
            path: file.path, byteOffset: first.byteRange.lowerBound, length: first.byteRange.count, line: 1,
            utf8Column: 5, oldName: "alpha", newName: "_oa", usr: "usr-alpha"),
        SourceReplacement(
            path: file.path, byteOffset: second.byteRange.lowerBound, length: second.byteRange.count, line: 1,
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
        SourceReplacement(
            path: patchedSource.path, byteOffset: first.byteRange.lowerBound, length: first.byteRange.count, line: 1,
            utf8Column: 5, oldName: "alpha", newName: "_oa", usr: "usr-alpha"),
        SourceReplacement(
            path: patchedSource.path, byteOffset: second.byteRange.lowerBound, length: second.byteRange.count, line: 1,
            utf8Column: 13, oldName: "alpha", newName: "_oa", usr: "usr-alpha"),
    ]

    let written = try SourcePatcher().writePatchedCopies(
        sourceFiles: [patchedSource.path, unchangedSource.path],
        replacements: replacements,
        sourceRoot: project,
        outputRoot: output
    )

    #expect(
        written.map(\.path).sorted()
            == [
                output.appendingPathComponent("Sources").appendingPathComponent("Patched.swift").path,
                output.appendingPathComponent("Sources").appendingPathComponent("Unchanged.swift").path,
            ].sorted())
    #expect(
        try String(
            contentsOf: output.appendingPathComponent("Sources").appendingPathComponent("Patched.swift"),
            encoding: .utf8) == "let _oa = _oa\n")
    #expect(
        try String(
            contentsOf: output.appendingPathComponent("Sources").appendingPathComponent("Unchanged.swift"),
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
        declarationSource.identifierToken(line: 1, utf8Column: utf8Column(of: "LocalModel", in: declarationLine)))
    let referenceToken = try #require(
        referenceSource.identifierToken(line: 1, utf8Column: utf8Column(of: "LocalModel", in: referenceLine)))
    let replacements = [
        SourceReplacement(
            path: declarationFile.path, byteOffset: declarationToken.byteRange.lowerBound,
            length: declarationToken.byteRange.count, line: 1,
            utf8Column: utf8Column(of: "LocalModel", in: declarationLine), oldName: "LocalModel", newName: "_oa",
            usr: "usr-localModel"),
        SourceReplacement(
            path: referenceFile.path, byteOffset: referenceToken.byteRange.lowerBound,
            length: referenceToken.byteRange.count, line: 1,
            utf8Column: utf8Column(of: "LocalModel", in: referenceLine), oldName: "LocalModel", newName: "_oa",
            usr: "usr-localModel"),
    ]

    let written = try SourcePatcher().writePatchedCopies(
        sourceFiles: [declarationFile.path],
        replacements: replacements,
        sourceRoot: project,
        outputRoot: output
    )

    #expect(
        written.map(\.path).sorted()
            == [
                output.appendingPathComponent("Selected").appendingPathComponent("Declaration.swift").path,
                output.appendingPathComponent("Other").appendingPathComponent("Reference.swift").path,
            ].sorted())
    #expect(
        try String(
            contentsOf: output.appendingPathComponent("Selected").appendingPathComponent("Declaration.swift"),
            encoding: .utf8) == "struct _oa {}\n")
    #expect(
        try String(
            contentsOf: output.appendingPathComponent("Other").appendingPathComponent("Reference.swift"),
            encoding: .utf8) == "let metatype = _oa.self\n")
    #expect(try String(contentsOf: referenceFile, encoding: .utf8) == referenceLine + "\n")
}
