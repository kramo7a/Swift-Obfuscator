import Foundation
import Testing
@testable import ObfuscatorCore

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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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

@Test func sourceFileFinderSkipsConfiguredOutputDirectory() throws {
    let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sources = project.appendingPathComponent("Sources", isDirectory: true)
    let outputSources = project
        .appendingPathComponent("output", isDirectory: true)
        .appendingPathComponent("Sources", isDirectory: true)
    let derivedSources = project
        .appendingPathComponent("Derived", isDirectory: true)
        .appendingPathComponent("Sources", isDirectory: true)
    let buildBackupSources = project
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("SemanticFacts.swift")
    let lines = [
        "protocol Service { func run() }",
        "struct LocalModel {}",
        "extension LocalModel { func localHelper() {} }",
        "extension String { struct ExternalNested { func externalHelper() {} } }",
        "@objc class LocalObjCModel: NSObject {}",
        "extension LocalObjCModel { func localObjCHelper() {} }",
        "@objcMembers class RuntimeOwner { struct RuntimeNested { var value: Int { 0 } } }",
        "func compilerDynamicallyDispatched() {}",
        "@IBOutlet var outlet: AnyObject?",
        "class RuntimeOverride { override func run() {} }",
        "class LocalSwiftSubclass: RuntimeOwner {}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(
        _ usr: String,
        _ name: String,
        _ kind: String,
        language: String = "swift",
        propertiesRaw: UInt64 = 0
    ) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: language,
            propertiesRaw: propertiesRaw,
            properties: propertiesRaw == 0 ? "[]" : "[indexed]"
        )
    }
    func relation(_ symbol: SymbolRecord, _ role: String) -> RelationRecord {
        RelationRecord(usr: symbol.usr, name: symbol.name, rolesRaw: 0, roles: [role])
    }

    let service = symbol("s:6Sample7ServiceP", "Service", "protocol")
    let requirement = symbol("s:6Sample7ServiceP3runyyF", "run()", "instanceMethod")
    let localModel = symbol("s:6Sample10LocalModelV", "LocalModel", "struct")
    let localExtension = symbol("s:e:local-model", "LocalModel", "extension")
    let localHelper = symbol("s:6Sample10LocalModelV11localHelperyyF", "localHelper()", "instanceMethod")
    let string = symbol("s:SS", "String", "struct")
    let externalExtension = symbol("s:e:string", "String", "extension")
    let externalNested = symbol("s:external-nested", "ExternalNested", "struct")
    let externalHelper = symbol("s:external-helper", "externalHelper()", "instanceMethod")
    let localObjCModel = symbol("c:@M@Sample@objc(cs)LocalObjCModel", "LocalObjCModel", "class")
    let localObjCExtension = symbol("s:e:local-objc-model", "LocalObjCModel", "extension")
    let localObjCHelper = symbol("s:local-objc-helper", "localObjCHelper()", "instanceMethod")
    let runtimeOwner = symbol("c:@M@Sample@objc(cs)RuntimeOwner", "RuntimeOwner", "class")
    let runtimeNested = symbol("s:runtime-nested", "RuntimeNested", "struct")
    let runtimeValue = symbol("s:runtime-value", "value", "instanceProperty")
    let dynamicEntry = symbol("s:dynamic-entry", "compilerDynamicallyDispatched()", "function")
    let outlet = symbol("s:outlet", "outlet", "variable", propertiesRaw: 1 << 4)
    let runtimeBaseMethod = symbol("c:@M@Sample@objc(cs)RuntimeBase(im)run", "run()", "instanceMethod")
    let runtimeOverride = symbol("s:runtime-override", "run()", "instanceMethod")
    let localSwiftSubclass = symbol("s:6Sample18LocalSwiftSubclassC", "LocalSwiftSubclass", "class")

    let occurrences = [
        testOccurrence(service, path: file.path, line: 1, token: "Service", roles: ["definition"]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 1,
            token: "run",
            roles: ["definition", "childOf"],
            relations: [relation(service, "childOf")]
        ),
        testOccurrence(localModel, path: file.path, line: 2, token: "LocalModel", roles: ["definition"]),
        testOccurrence(
            localModel,
            path: file.path,
            line: 3,
            token: "LocalModel",
            roles: ["reference", "extendedBy"],
            relations: [relation(localExtension, "extendedBy")]
        ),
        testOccurrence(localExtension, path: file.path, line: 3, token: "LocalModel", roles: ["definition"]),
        testOccurrence(
            localHelper,
            path: file.path,
            line: 3,
            token: "localHelper",
            roles: ["definition", "childOf"],
            relations: [relation(localExtension, "childOf")]
        ),
        testOccurrence(
            string,
            path: file.path,
            line: 4,
            token: "String",
            roles: ["reference", "extendedBy"],
            relations: [relation(externalExtension, "extendedBy")]
        ),
        testOccurrence(externalExtension, path: file.path, line: 4, token: "String", roles: ["definition"]),
        testOccurrence(
            externalNested,
            path: file.path,
            line: 4,
            token: "ExternalNested",
            roles: ["definition", "childOf"],
            relations: [relation(externalExtension, "childOf")]
        ),
        testOccurrence(
            externalHelper,
            path: file.path,
            line: 4,
            token: "externalHelper",
            roles: ["definition", "childOf"],
            relations: [relation(externalNested, "childOf")]
        ),
        testOccurrence(localObjCModel, path: file.path, line: 5, token: "LocalObjCModel", roles: ["definition"]),
        testOccurrence(
            localObjCModel,
            path: file.path,
            line: 6,
            token: "LocalObjCModel",
            roles: ["reference", "extendedBy"],
            relations: [relation(localObjCExtension, "extendedBy")]
        ),
        testOccurrence(localObjCExtension, path: file.path, line: 6, token: "LocalObjCModel", roles: ["definition"]),
        testOccurrence(
            localObjCHelper,
            path: file.path,
            line: 6,
            token: "localObjCHelper",
            roles: ["definition", "childOf"],
            relations: [relation(localObjCExtension, "childOf")]
        ),
        testOccurrence(runtimeOwner, path: file.path, line: 7, token: "RuntimeOwner", roles: ["definition"]),
        testOccurrence(
            runtimeNested,
            path: file.path,
            line: 7,
            token: "RuntimeNested",
            roles: ["definition", "childOf"],
            relations: [relation(runtimeOwner, "childOf")]
        ),
        testOccurrence(
            runtimeValue,
            path: file.path,
            line: 7,
            token: "value",
            roles: ["definition", "childOf"],
            relations: [relation(runtimeNested, "childOf")]
        ),
        testOccurrence(
            dynamicEntry,
            path: file.path,
            line: 8,
            token: "compilerDynamicallyDispatched",
            roles: ["definition", "dynamic"]
        ),
        testOccurrence(outlet, path: file.path, line: 9, token: "outlet", roles: ["definition"]),
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
            relations: [relation(runtimeBaseMethod, "overrideOf")]
        ),
        testOccurrence(
            localSwiftSubclass,
            path: file.path,
            line: 11,
            token: "LocalSwiftSubclass",
            roles: ["definition"]
        ),
        testOccurrence(
            runtimeOwner,
            path: file.path,
            line: 11,
            token: "RuntimeOwner",
            roles: ["reference", "baseOf"],
            relations: [relation(localSwiftSubclass, "baseOf")]
        )
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            service, requirement, localModel, localExtension, localHelper, string,
            externalExtension, externalNested, externalHelper, localObjCModel,
            localObjCExtension, localObjCHelper, runtimeOwner, runtimeNested,
            runtimeValue, dynamicEntry, outlet, runtimeBaseMethod, runtimeOverride,
            localSwiftSubclass
        ],
        occurrences: occurrences
    )
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])

    #expect(facts.protocolRequirementUSRs == [requirement.usr])
    #expect(facts.externallyOwnedUSRs.contains(externalExtension.usr))
    #expect(facts.externallyOwnedUSRs.contains(externalNested.usr))
    #expect(facts.externallyOwnedUSRs.contains(externalHelper.usr))
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
    #expect(externalDecision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
    #expect(localDecision.allowed)
    #expect(runtimeDecision.reasons.contains("runtime-reflected or externally linked declaration according to IndexStore semantics"))
}

@Test func renamePlanCacheRequiresMatchingToolAndInputs() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    try "let alpha = beta + alpha\n".write(to: file, atomically: true, encoding: .utf8)

    let source = try SourceFile(path: file.path)
    let first = try #require(source.identifierToken(line: 1, utf8Column: 5))
    let second = try #require(source.identifierToken(line: 1, utf8Column: 20))
    let replacements = [
        SourceReplacement(path: file.path, byteOffset: first.byteRange.lowerBound, length: first.byteRange.count, line: 1, utf8Column: 5, oldName: "alpha", newName: "_oa", usr: "usr-alpha"),
        SourceReplacement(path: file.path, byteOffset: second.byteRange.lowerBound, length: second.byteRange.count, line: 1, utf8Column: 20, oldName: "alpha", newName: "_oa", usr: "usr-alpha")
    ]

    try SourcePatcher().apply(replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched == "let _oa = beta + _oa\n")
}

@Test func sourcePatcherWritesSwiftFilesToMatchingOutputPaths() throws {
    let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        SourceReplacement(path: patchedSource.path, byteOffset: first.byteRange.lowerBound, length: first.byteRange.count, line: 1, utf8Column: 5, oldName: "alpha", newName: "_oa", usr: "usr-alpha"),
        SourceReplacement(path: patchedSource.path, byteOffset: second.byteRange.lowerBound, length: second.byteRange.count, line: 1, utf8Column: 13, oldName: "alpha", newName: "_oa", usr: "usr-alpha")
    ]

    let written = try SourcePatcher().writePatchedCopies(
        sourceFiles: [patchedSource.path, unchangedSource.path],
        replacements: replacements,
        sourceRoot: project,
        outputRoot: output
    )

    #expect(written.map(\.path).sorted() == [
        output.appendingPathComponent("Sources").appendingPathComponent("Patched.swift").path,
        output.appendingPathComponent("Sources").appendingPathComponent("Unchanged.swift").path
    ].sorted())
    #expect(try String(contentsOf: output.appendingPathComponent("Sources").appendingPathComponent("Patched.swift"), encoding: .utf8) == "let _oa = _oa\n")
    #expect(try String(contentsOf: output.appendingPathComponent("Sources").appendingPathComponent("Unchanged.swift"), encoding: .utf8) == "let beta = 1\n")
    #expect(try String(contentsOf: patchedSource, encoding: .utf8) == "let alpha = alpha\n")
}

@Test func sourcePatcherWritesExternalReplacementFilesToOutputPaths() throws {
    let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
    let declarationToken = try #require(declarationSource.identifierToken(line: 1, utf8Column: utf8Column(of: "LocalModel", in: declarationLine)))
    let referenceToken = try #require(referenceSource.identifierToken(line: 1, utf8Column: utf8Column(of: "LocalModel", in: referenceLine)))
    let replacements = [
        SourceReplacement(path: declarationFile.path, byteOffset: declarationToken.byteRange.lowerBound, length: declarationToken.byteRange.count, line: 1, utf8Column: utf8Column(of: "LocalModel", in: declarationLine), oldName: "LocalModel", newName: "_oa", usr: "usr-localModel"),
        SourceReplacement(path: referenceFile.path, byteOffset: referenceToken.byteRange.lowerBound, length: referenceToken.byteRange.count, line: 1, utf8Column: utf8Column(of: "LocalModel", in: referenceLine), oldName: "LocalModel", newName: "_oa", usr: "usr-localModel")
    ]

    let written = try SourcePatcher().writePatchedCopies(
        sourceFiles: [declarationFile.path],
        replacements: replacements,
        sourceRoot: project,
        outputRoot: output
    )

    #expect(written.map(\.path).sorted() == [
        output.appendingPathComponent("Selected").appendingPathComponent("Declaration.swift").path,
        output.appendingPathComponent("Other").appendingPathComponent("Reference.swift").path
    ].sorted())
    #expect(try String(contentsOf: output.appendingPathComponent("Selected").appendingPathComponent("Declaration.swift"), encoding: .utf8) == "struct _oa {}\n")
    #expect(try String(contentsOf: output.appendingPathComponent("Other").appendingPathComponent("Reference.swift"), encoding: .utf8) == "let metatype = _oa.self\n")
    #expect(try String(contentsOf: referenceFile, encoding: .utf8) == referenceLine + "\n")
}

@Test func safetyAnalyzerDeniesUnsupportedKindsByDefault() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    try "let localValue = 1\n".write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-module",
        name: "Sample",
        kind: "module",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains { $0.contains("unsupported symbol kind") })
}

@Test func safetyAnalyzerDeniesParametersBecauseArgumentLabelsAreNotCompleteOccurrences() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    try "func run(value: String) { print(value) }\n".write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-parameter",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains { $0.contains("unsupported symbol kind parameter") })
}

@Test func safetyAnalyzerKeepsRuntimeOwnerContractsSeparateFromLocalParameterBindings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Action.swift")
    let lines = [
        "@objc func action(_ sender: Any) {",
        "    _ = sender",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])
    let symbol = SymbolRecord(
        usr: "usr-sender",
        name: "sender",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let group = USROccurrenceGroup(
        usr: symbol.usr,
        symbol: symbol,
        occurrences: [
            testOccurrence(
                symbol,
                path: file.path,
                line: 1,
                token: "sender",
                roles: ["definition"]
            ),
            testOccurrence(
                symbol,
                path: file.path,
                line: 2,
                token: "sender",
                roles: ["reference"]
            )
        ]
    )
    let facts = IndexedSemanticFacts(
        externallyOwnedUSRs: [symbol.usr],
        runtimeSensitiveUSRs: [symbol.usr]
    )

    let denied = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: group,
        sourceCache: cache,
        indexedFacts: facts
    )
    #expect(!denied.allowed)

    let localBindingDecision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: group,
        sourceCache: cache,
        indexedFacts: facts,
        localBindingOnlyParameterUSRs: [symbol.usr]
    )
    #expect(localBindingDecision.allowed)
    #expect(localBindingDecision.oldName == "sender")
}

@Test func indexedParameterComponentsSeparateExternalLabelsFromLocalBindings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let selectedFile = directory.appendingPathComponent("Selected.swift")
    let outsideFile = directory.appendingPathComponent("Outside.swift")
    let lines = [
        "func combine(_ hidden: Int, wire local: Int, shorthand: Int) -> Int {",
        "    hidden + local + shorthand",
        "}",
        "let result = combine(1, wire: 2, shorthand: 3)",
        "let functionValue = combine",
        "struct Box {",
        "    init(loadController: Int, workspaceId localWorkspaceID: Int) {",
        "        _ = loadController + localWorkspaceID",
        "    }",
        "}",
        "func broken(one: Int) {}",
        "enum Event { case received(payload: Int) }",
        "struct Table { subscript(offset index: Int) -> Int { index } }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: selectedFile,
        atomically: true,
        encoding: .utf8
    )
    try "let outside = combine(1, wire: 2, shorthand: 3)\n".write(
        to: outsideFile,
        atomically: true,
        encoding: .utf8
    )

    func symbol(_ usr: String, _ name: String, _ kind: String = "parameter") -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }

    let combine = symbol("usr-combine", "combine(_:wire:shorthand:)", "function")
    let hidden = symbol("usr-hidden", "hidden")
    let local = symbol("usr-local", "local")
    let shorthand = symbol("usr-shorthand", "shorthand")
    let initializer = symbol(
        "usr-initializer",
        "init(loadController:workspaceId:)",
        "constructor"
    )
    let loadController = symbol("usr-load-controller", "loadController")
    let localWorkspaceID = symbol("usr-workspace-id", "localWorkspaceID")
    let broken = symbol("usr-broken", "broken(one:two:)", "function")
    let brokenParameter = symbol("usr-broken-parameter", "one")
    let enumCase = symbol("usr-enum-case", "received(payload:)", "enumConstant")
    let payload = symbol("usr-payload", "payload")
    let subscriptDeclaration = symbol("usr-subscript", "subscript(offset:)", "instanceProperty")
    let index = symbol("usr-index", "index")

    func childOf(_ callable: SymbolRecord) -> RelationRecord {
        RelationRecord(
            usr: callable.usr,
            name: callable.name,
            rolesRaw: 0,
            roles: ["childOf"]
        )
    }

    func occurrence(
        _ symbol: SymbolRecord,
        path: URL = selectedFile,
        line: Int,
        token: String,
        roles: [String],
        relations: [RelationRecord] = []
    ) -> OccurrenceRecord {
        let sourceLine = try! String(contentsOf: path, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)[line - 1]
        return OccurrenceRecord(
            symbol: symbol,
            path: path.path,
            line: line,
            utf8Column: utf8Column(of: token, in: String(sourceLine)),
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
        )
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [selectedFile.path, outsideFile.path],
        symbols: [
            combine, hidden, local, shorthand, initializer, loadController,
            localWorkspaceID, broken, brokenParameter, enumCase, payload,
            subscriptDeclaration, index
        ],
        occurrences: occurrences
    )

    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [selectedFile])
    #expect(facts.parameterRenameComponents.count == 5)

    let combineComponent = try #require(
        facts.parameterRenameComponents.first { $0.callableUSR == combine.usr }
    )
    #expect(combineComponent.isStructurallyComplete)
    #expect(combineComponent.members.map(\.parameterUSR) == [hidden.usr, local.usr, shorthand.usr])
    #expect(combineComponent.members.map(\.ordinal) == [0, 1, 2])
    #expect(combineComponent.members.map(\.localBinding) == ["hidden", "local", "shorthand"])
    #expect(combineComponent.members.map(\.externalLabel) == [
        .omitted, .named("wire"), .named("shorthand")
    ])
    #expect(combineComponent.members.map { $0.referenceLocations.map(\.line) } == [[2], [2], [2]])
    #expect(combineComponent.callLocations.map(\.line) == [4])
    #expect(combineComponent.nonCallReferenceLocations.map(\.line) == [5])
    #expect(combineComponent.hasOccurrenceOutsideSelectedRoots)

    let initializerComponent = try #require(
        facts.parameterRenameComponents.first { $0.callableUSR == initializer.usr }
    )
    #expect(initializerComponent.isStructurallyComplete)
    #expect(initializerComponent.members.map(\.localBinding) == ["loadController", "localWorkspaceID"])
    #expect(initializerComponent.members.map(\.externalLabel) == [
        .named("loadController"), .named("workspaceId")
    ])

    let brokenComponent = try #require(
        facts.parameterRenameComponents.first { $0.callableUSR == broken.usr }
    )
    #expect(!brokenComponent.isStructurallyComplete)
    #expect(brokenComponent.members.map(\.externalLabel) == [.unavailable])
    #expect(brokenComponent.structuralReasons == [
        "callable index name does not expose exactly 1 external argument label(s)"
    ])

    let enumCaseComponent = try #require(
        facts.parameterRenameComponents.first { $0.callableUSR == enumCase.usr }
    )
    #expect(enumCaseComponent.ownerCategory == .enumCase)
    #expect(enumCaseComponent.members.map(\.externalLabel) == [.named("payload")])

    let subscriptComponent = try #require(
        facts.parameterRenameComponents.first { $0.callableUSR == subscriptDeclaration.usr }
    )
    #expect(subscriptComponent.ownerCategory == .subscriptDeclaration)
    #expect(subscriptComponent.members.map(\.localBinding) == ["index"])
    #expect(subscriptComponent.members.map(\.externalLabel) == [.named("offset")])

    let summary = facts.parameterFactsSummary
    #expect(summary.explicitParameters == 8)
    #expect(summary.modeledParameters == 8)
    #expect(summary.unmodeledParameters == 0)
    #expect(summary.components == 5)
    #expect(summary.structurallyCompleteComponents == 4)
    #expect(summary.structurallyCompleteParameters == 7)
    #expect(summary.omittedExternalLabels == 1)
    #expect(summary.sharedLabelAndBindingParameters == 3)
    #expect(summary.distinctLabelAndBindingParameters == 3)
    #expect(summary.unavailableExternalLabels == 1)
    #expect(summary.callAnchors == 1)
    #expect(summary.functionReferenceAnchors == 1)
    #expect(summary.enumCaseReferenceAnchors == 0)
    #expect(summary.componentsWithOccurrencesOutsideSelectedRoots == 1)
    #expect(summary.protocolRequirementComponents == 0)
    #expect(summary.overrideRelatedComponents == 0)
    #expect(summary.runtimeSensitiveComponents == 0)
    #expect(summary.externallyOwnedComponents == 0)
    #expect(summary.subscriptComponents == 1)
    #expect(summary.subscriptParameters == 1)
    #expect(summary.enumCaseComponents == 1)
    #expect(summary.enumCaseParameters == 1)
}

@Test func parameterSyntaxFactsResolveExactRolesWithoutDeclarationTextScanning() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Parameters.swift")
    let lines = [
        "struct Sample {",
        "    var stored: Int = 0 {",
        "        willSet(nextValue) { _ = nextValue }",
        "    }",
        "    func outer(external local: Int) {",
        "        func nested(_ nestedValue: Int, wire inner: Int = 1) {",
        "            _ = local + nestedValue + inner",
        "        }",
        "    }",
        "    subscript(offset index: Int) -> Int { index }",
        "}",
        "enum Event { case payload(label value: Int, _: String, Bool) }",
        "let closure = { (closureValue: Int) in closureValue }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }

    let accessor = symbol("usr-accessor", "willSet:stored", "instanceMethod")
    let nextValue = symbol("usr-next-value", "nextValue", "parameter")
    let outer = symbol("usr-outer", "outer(external:)", "instanceMethod")
    let local = symbol("usr-local", "local", "parameter")
    let nestedValue = symbol("usr-nested-value", "nestedValue", "parameter")
    let inner = symbol("usr-inner", "inner", "parameter")
    let subscriptDeclaration = symbol("usr-subscript", "subscript(offset:)", "instanceProperty")
    let index = symbol("usr-index", "index", "parameter")
    let enumCase = symbol("usr-enum-case", "payload(label:_:_:)", "enumConstant")
    let value = symbol("usr-value", "value", "parameter")
    let omittedValue = symbol("usr-omitted-value", "_", "parameter")
    let sourceNameAbsent = symbol("usr-source-name-absent", "_", "parameter")
    let closureOwner = symbol("usr-closure-owner", "closure", "variable")
    let closureValue = symbol("usr-closure-value", "closureValue", "parameter")

    func childOf(_ owner: SymbolRecord) -> RelationRecord {
        RelationRecord(
            usr: owner.usr,
            name: owner.name,
            rolesRaw: 0,
            roles: ["childOf"]
        )
    }

    let occurrences = [
        testOccurrence(accessor, path: file.path, line: 2, token: "stored", roles: ["definition"]),
        testOccurrence(
            nextValue,
            path: file.path,
            line: 3,
            token: "nextValue",
            roles: ["definition"],
            relations: [childOf(accessor)]
        ),
        testOccurrence(outer, path: file.path, line: 5, token: "outer", roles: ["definition"]),
        testOccurrence(
            local,
            path: file.path,
            line: 5,
            token: "local",
            roles: ["definition"],
            relations: [childOf(outer)]
        ),
        testOccurrence(
            nestedValue,
            path: file.path,
            line: 6,
            token: "nestedValue",
            roles: ["definition"],
            relations: [childOf(outer)]
        ),
        testOccurrence(
            inner,
            path: file.path,
            line: 6,
            token: "inner",
            roles: ["definition"],
            relations: [childOf(outer)]
        ),
        testOccurrence(
            subscriptDeclaration,
            path: file.path,
            line: 10,
            token: "subscript",
            roles: ["definition"]
        ),
        testOccurrence(
            index,
            path: file.path,
            line: 10,
            token: "index",
            roles: ["definition"],
            relations: [childOf(subscriptDeclaration)]
        ),
        testOccurrence(enumCase, path: file.path, line: 12, token: "payload", roles: ["definition"]),
        testOccurrence(
            value,
            path: file.path,
            line: 12,
            token: "value",
            roles: ["definition"],
            relations: [childOf(enumCase)]
        ),
        testOccurrence(
            omittedValue,
            path: file.path,
            line: 12,
            token: "_",
            roles: ["definition"],
            relations: [childOf(enumCase)]
        ),
        testOccurrence(
            sourceNameAbsent,
            path: file.path,
            line: 12,
            token: "Bool",
            roles: ["definition"],
            relations: [childOf(enumCase)]
        ),
        testOccurrence(
            closureOwner,
            path: file.path,
            line: 13,
            token: "closure",
            roles: ["definition"]
        ),
        testOccurrence(
            closureValue,
            path: file.path,
            line: 13,
            token: "closureValue",
            roles: ["definition"],
            relations: [childOf(closureOwner)]
        )
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            accessor, nextValue, outer, local, nestedValue, inner,
            subscriptDeclaration, index, enumCase, value, omittedValue, sourceNameAbsent,
            closureOwner, closureValue
        ],
        occurrences: occurrences
    )

    let facts = ParameterSyntaxFacts(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [file]
    )
    #expect(facts.unresolvedReasonsByUSR.isEmpty)
    #expect(facts.rolesByUSR.count == 9)
    #expect(facts.localBindingOnlyCoverageCandidateUSRs == [
        nestedValue.usr,
        nextValue.usr,
        closureValue.usr
    ])

    let outerRoles = try #require(facts.rolesByUSR[local.usr])
    #expect(outerRoles.kind == .function)
    #expect(outerRoles.localBinding?.name == "local")
    #expect(outerRoles.syntaxOwnerToken?.name == "outer")
    #expect(outerRoles.syntaxOwnerMatchesIndexedOwner)
    if case .named(let label) = outerRoles.externalLabel {
        #expect(label.name == "external")
        #expect(label.byteRange != outerRoles.localBinding?.byteRange)
    } else {
        Issue.record("Expected a named external label")
    }

    let nestedRoles = try #require(facts.rolesByUSR[nestedValue.usr])
    #expect(nestedRoles.kind == .function)
    #expect(nestedRoles.localBinding?.name == "nestedValue")
    #expect(nestedRoles.syntaxOwnerToken?.name == "nested")
    #expect(nestedRoles.isNestedLocalFunctionParameter)
    if case .omitted(let label) = nestedRoles.externalLabel {
        #expect(label.name == "_")
    } else {
        Issue.record("Expected an omitted external label")
    }

    let innerRoles = try #require(facts.rolesByUSR[inner.usr])
    #expect(innerRoles.isNestedLocalFunctionParameter)
    #expect(innerRoles.localBinding?.name == "inner")
    if case .named(let label) = innerRoles.externalLabel {
        #expect(label.name == "wire")
    } else {
        Issue.record("Expected a named nested-function label")
    }
    #expect(innerRoles.hasDefaultValue)
    #expect(!innerRoles.isVariadic)

    let accessorRoles = try #require(facts.rolesByUSR[nextValue.usr])
    #expect(accessorRoles.kind == .accessor)
    #expect(accessorRoles.externalLabel == .none)
    #expect(accessorRoles.localBinding?.name == "nextValue")
    #expect(!accessorRoles.isNestedLocalFunctionParameter)

    let subscriptRoles = try #require(facts.rolesByUSR[index.usr])
    #expect(subscriptRoles.kind == .subscriptDeclaration)
    #expect(subscriptRoles.localBinding?.name == "index")

    let enumRoles = try #require(facts.rolesByUSR[value.usr])
    #expect(enumRoles.kind == .enumCase)
    #expect(enumRoles.localBinding?.name == "value")
    let omittedEnumRoles = try #require(facts.rolesByUSR[omittedValue.usr])
    #expect(omittedEnumRoles.kind == .enumCase)
    #expect(omittedEnumRoles.localBinding == nil)
    if case .omitted(let label) = omittedEnumRoles.externalLabel {
        #expect(label.name == "_")
    } else {
        Issue.record("Expected an omitted enum associated-value label")
    }
    let sourceNameAbsentRoles = try #require(facts.rolesByUSR[sourceNameAbsent.usr])
    #expect(sourceNameAbsentRoles.kind == .enumCase)
    #expect(sourceNameAbsentRoles.externalLabel == .none)
    #expect(sourceNameAbsentRoles.localBinding == nil)
    #expect(sourceNameAbsentRoles.indexedDeclarationAnchor.name == "Bool")

    let closureRoles = try #require(facts.rolesByUSR[closureValue.usr])
    #expect(closureRoles.kind == .closure)
    #expect(closureRoles.externalLabel == .none)
    #expect(closureRoles.localBinding?.name == "closureValue")

    let summary = facts.summary
    #expect(summary.explicitParameters == 9)
    #expect(summary.resolvedParameters == 9)
    #expect(summary.unresolvedParameters == 0)
    #expect(summary.functionParameters == 3)
    #expect(summary.initializerParameters == 0)
    #expect(summary.subscriptParameters == 1)
    #expect(summary.enumCaseParameters == 3)
    #expect(summary.accessorBindings == 1)
    #expect(summary.closureParameters == 1)
    #expect(summary.nestedLocalFunctionParameters == 2)
    #expect(summary.namedExternalLabels == 4)
    #expect(summary.omittedExternalLabels == 2)
    #expect(summary.parametersWithoutExternalLabels == 3)
    #expect(summary.localBindings == 7)
    #expect(summary.parametersWithoutLocalBindings == 2)
    #expect(summary.parametersWithoutSourceNames == 1)
    #expect(summary.parametersWithDefaultValues == 1)
    #expect(summary.variadicParameters == 0)
    #expect(summary.sharedLabelAndBindingTokens == 0)
    #expect(summary.distinctLabelAndBindingTokens == 5)
    #expect(summary.localBindingReferenceTokens == 6)
    #expect(summary.parametersWithShadowingBindingDeclarations == 0)
    #expect(summary.localBindingOnlyCoverageCandidates == 3)
    #expect(summary.parametersRequiringExternalLabelCoordination == 3)
    #expect(summary.nonEnumParametersWithoutLocalBindings == 0)
    #expect(summary.enumCaseParametersExcludedFromParameterStage == 3)
}

@Test func parameterSyntaxFactsRecordDefaultAndVariadicTraits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ParameterTraits.swift")
    let lines = [
        "func configure(",
        "    _ values: Int...,",
        "    retries: Int = 3,",
        "    completion: (() -> Void)? = nil",
        ") {",
        "    _ = values",
        "    _ = retries",
        "    _ = completion",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    let owner = symbol("usr-configure", "configure(_:retries:completion:)", "function")
    let values = symbol("usr-values", "values", "parameter")
    let retries = symbol("usr-retries", "retries", "parameter")
    let completion = symbol("usr-traits-completion", "completion", "parameter")
    let int = symbol("usr-int", "Int", "struct")
    let childOfOwner = RelationRecord(
        usr: owner.usr,
        name: owner.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [owner, values, retries, completion, int],
        occurrences: [
            testOccurrence(
                owner,
                path: file.path,
                line: 1,
                token: "configure",
                roles: ["definition"]
            ),
            testOccurrence(
                values,
                path: file.path,
                line: 2,
                token: "values",
                roles: ["definition"],
                relations: [childOfOwner]
            ),
            testOccurrence(
                values,
                path: file.path,
                line: 6,
                token: "values",
                roles: ["reference"]
            ),
            testOccurrence(int, path: file.path, line: 2, token: "Int", roles: ["reference"]),
            testOccurrence(
                retries,
                path: file.path,
                line: 3,
                token: "retries",
                roles: ["definition"],
                relations: [childOfOwner]
            ),
            testOccurrence(
                retries,
                path: file.path,
                line: 7,
                token: "retries",
                roles: ["reference"]
            ),
            testOccurrence(int, path: file.path, line: 3, token: "Int", roles: ["reference"]),
            testOccurrence(
                completion,
                path: file.path,
                line: 4,
                token: "completion",
                roles: ["definition"],
                relations: [childOfOwner]
            ),
            testOccurrence(
                completion,
                path: file.path,
                line: 8,
                token: "completion",
                roles: ["reference"]
            )
        ]
    )

    let facts = ParameterSyntaxFacts(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [file]
    )
    let valuesRoles = try #require(facts.rolesByUSR[values.usr])
    #expect(!valuesRoles.hasDefaultValue)
    #expect(valuesRoles.isVariadic)
    #expect(valuesRoles.trailingClosureCompatibility == .definitelyNonCallable)
    if case .omitted(let label) = valuesRoles.externalLabel {
        #expect(label.name == "_")
    } else {
        Issue.record("Expected an explicitly omitted variadic label")
    }

    let retriesRoles = try #require(facts.rolesByUSR[retries.usr])
    #expect(retriesRoles.hasDefaultValue)
    #expect(!retriesRoles.isVariadic)
    #expect(retriesRoles.trailingClosureCompatibility == .definitelyNonCallable)
    if case .named(let label) = retriesRoles.externalLabel {
        #expect(label.name == "retries")
    } else {
        Issue.record("Expected a named defaulted label")
    }

    let completionRoles = try #require(facts.rolesByUSR[completion.usr])
    #expect(completionRoles.hasDefaultValue)
    #expect(completionRoles.trailingClosureCompatibility == .definitelyCallable)

    #expect(facts.summary.parametersWithDefaultValues == 2)
    #expect(facts.summary.variadicParameters == 1)
    #expect(facts.summary.definitelyCallableParameters == 1)
    #expect(facts.summary.definitelyNonCallableParameters == 2)
    #expect(facts.summary.parametersWithUnknownCallability == 0)
}

@Test func parameterSyntaxFactsUseSwiftOperatorAndSubscriptLabelSemantics() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ImplicitLabels.swift")
    let lines = [
        "struct Sample {",
        "    static func + (lhs: Sample, rhs: Sample) -> Sample {",
        "        _ = lhs",
        "        return rhs",
        "    }",
        "    subscript(index: Int) -> Int {",
        "        index",
        "    }",
        "    subscript(label localIndex: Int) -> Int {",
        "        localIndex",
        "    }",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    func childOf(_ owner: SymbolRecord) -> RelationRecord {
        RelationRecord(usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["childOf"])
    }

    let plus = symbol("usr-plus", "+(_:_:)", "staticMethod")
    let lhs = symbol("usr-lhs", "lhs", "parameter")
    let rhs = symbol("usr-rhs", "rhs", "parameter")
    let defaultSubscript = symbol("usr-default-subscript", "subscript(_:)", "instanceProperty")
    let index = symbol("usr-index", "index", "parameter")
    let labeledSubscript = symbol(
        "usr-labeled-subscript",
        "subscript(label:)",
        "instanceProperty"
    )
    let localIndex = symbol("usr-local-index", "localIndex", "parameter")
    let occurrences = [
        testOccurrence(plus, path: file.path, line: 2, token: "+", roles: ["definition"]),
        testOccurrence(
            lhs,
            path: file.path,
            line: 2,
            token: "lhs",
            roles: ["definition"],
            relations: [childOf(plus)]
        ),
        testOccurrence(
            rhs,
            path: file.path,
            line: 2,
            token: "rhs",
            roles: ["definition"],
            relations: [childOf(plus)]
        ),
        testOccurrence(lhs, path: file.path, line: 3, token: "lhs", roles: ["reference"]),
        testOccurrence(rhs, path: file.path, line: 4, token: "rhs", roles: ["reference"]),
        testOccurrence(
            defaultSubscript,
            path: file.path,
            line: 6,
            token: "subscript",
            roles: ["definition"]
        ),
        testOccurrence(
            index,
            path: file.path,
            line: 6,
            token: "index",
            roles: ["definition"],
            relations: [childOf(defaultSubscript)]
        ),
        testOccurrence(index, path: file.path, line: 7, token: "index", roles: ["reference"]),
        testOccurrence(
            labeledSubscript,
            path: file.path,
            line: 9,
            token: "subscript",
            roles: ["definition"]
        ),
        testOccurrence(
            localIndex,
            path: file.path,
            line: 9,
            token: "localIndex",
            roles: ["definition"],
            relations: [childOf(labeledSubscript)]
        ),
        testOccurrence(
            localIndex,
            path: file.path,
            line: 10,
            token: "localIndex",
            roles: ["reference"]
        )
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [plus, lhs, rhs, defaultSubscript, index, labeledSubscript, localIndex],
        occurrences: occurrences
    )

    let facts = ParameterSyntaxFacts(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [file]
    )
    #expect(facts.unresolvedReasonsByUSR.isEmpty)
    #expect(facts.localBindingOnlyCoverageCandidateUSRs == [lhs.usr, rhs.usr, index.usr])

    let lhsRoles = try #require(facts.rolesByUSR[lhs.usr])
    #expect(lhsRoles.externalLabel == .none)
    #expect(lhsRoles.localBinding?.name == "lhs")
    #expect(lhsRoles.syntaxOwnerToken?.name == "+")
    #expect(lhsRoles.syntaxOwnerMatchesIndexedOwner)
    #expect(!lhsRoles.isNestedLocalFunctionParameter)
    let rhsRoles = try #require(facts.rolesByUSR[rhs.usr])
    #expect(rhsRoles.externalLabel == .none)

    let indexRoles = try #require(facts.rolesByUSR[index.usr])
    #expect(indexRoles.externalLabel == .none)
    #expect(indexRoles.localBinding?.name == "index")
    #expect(indexRoles.syntaxOwnerMatchesIndexedOwner)

    let localIndexRoles = try #require(facts.rolesByUSR[localIndex.usr])
    if case .named(let label) = localIndexRoles.externalLabel {
        #expect(label.name == "label")
    } else {
        Issue.record("Expected the explicit subscript label to remain named")
    }
    #expect(localIndexRoles.localBinding?.name == "localIndex")

    let summary = facts.summary
    #expect(summary.explicitParameters == 4)
    #expect(summary.resolvedParameters == 4)
    #expect(summary.functionParameters == 2)
    #expect(summary.subscriptParameters == 2)
    #expect(summary.namedExternalLabels == 1)
    #expect(summary.omittedExternalLabels == 0)
    #expect(summary.parametersWithoutExternalLabels == 3)
    #expect(summary.localBindingOnlyCoverageCandidates == 3)
    #expect(summary.parametersRequiringExternalLabelCoordination == 1)

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let lhsEntry = try #require(plan.entries.first { $0.usr == lhs.usr })
    let rhsEntry = try #require(plan.entries.first { $0.usr == rhs.usr })
    let indexEntry = try #require(plan.entries.first { $0.usr == index.usr })
    let localIndexEntry = try #require(plan.entries.first { $0.usr == localIndex.usr })
    #expect(Set(plan.entries.map(\.usr)) == [
        lhs.usr, rhs.usr, index.usr, localIndex.usr
    ])
    #expect(lhsEntry.replacements.count == 2)
    #expect(rhsEntry.replacements.count == 2)
    #expect(indexEntry.replacements.count == 2)
    #expect(plan.parameterLocalBindingOutcome.candidates == 3)
    #expect(plan.parameterLocalBindingOutcome.renamed == 3)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains(
        "static func + (\(lhsEntry.newName): Sample, \(rhsEntry.newName): Sample)"
    ))
    #expect(patched.contains("subscript(\(indexEntry.newName): Int)"))
    #expect(patched.contains(
        "subscript(\(localIndexEntry.newName) \(localIndexEntry.newName): Int)"
    ))
}

@Test func renamePlannerRenamesOnlyParametersWhoseExternalLabelIsAlreadyAbsent() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Parameters.swift")
    let lines = [
        "func calculate(_ value: Int, wire local: Int, shared: Int) -> Int {",
        "    value + local + shared",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func parameter(_ usr: String, _ name: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: "parameter",
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }

    let value = parameter("usr-value", "value")
    let local = parameter("usr-local", "local")
    let shared = parameter("usr-shared", "shared")
    let occurrences = [
        testOccurrence(value, path: file.path, line: 1, token: "value", roles: ["definition"]),
        testOccurrence(value, path: file.path, line: 2, token: "value", roles: ["reference"]),
        testOccurrence(local, path: file.path, line: 1, token: "local", roles: ["definition"]),
        testOccurrence(local, path: file.path, line: 2, token: "local", roles: ["reference"]),
        testOccurrence(shared, path: file.path, line: 1, token: "shared", roles: ["definition"]),
        testOccurrence(shared, path: file.path, line: 2, token: "shared", roles: ["reference"])
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [value, local, shared],
        occurrences: occurrences
    )
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(plan.entries.count == 1)
    #expect(entry.oldName == "value")
    #expect(entry.newName.first?.isLowercase == true)
    #expect(entry.replacements.count == 2)
    #expect(plan.denied.contains { $0.usr == local.usr })
    #expect(plan.denied.contains { $0.usr == shared.usr })
    #expect(plan.parameterSyntaxFacts.localBindingOnlyCoverageCandidates == 1)
    #expect(plan.parameterLocalBindingOutcome.candidates == 1)
    #expect(plan.parameterLocalBindingOutcome.renamed == 1)
    #expect(plan.parameterLocalBindingOutcome.denied == 0)
    #expect(plan.parameterLocalBindingOutcome.unclassified == 0)
    #expect(plan.parameterLocalBindingOutcome.denialCategories.isEmpty)
    #expect(plan.parameterLocalBindingOutcome.deniedCandidateUSRs.isEmpty)
    #expect(!entry.replacements.contains { $0.oldName == "_" })

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched == [
        "func calculate(_ \(entry.newName): Int, wire local: Int, shared: Int) -> Int {",
        "    \(entry.newName) + local + shared",
        "}",
        ""
    ].joined(separator: "\n"))
}

@Test func renamePlannerAddsCompilerSyntaxParameterReferencesMissingFromIndex() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Handler.swift")
    let lines = [
        "struct Handler {",
        "    let label: String",
        "    init(_ label: String) {",
        "        self.label = label",
        "    }",
        "    func format(_ message: String) -> String {",
        "        \"\\(message)\"",
        "    }",
        "    func evaluate(_ webView: WebView) {",
        "        work { [weak webView] in webView?.run() }",
        "    }",
        "    func shadow(_ value: Int) -> Int {",
        "        do { let value = 1; _ = value }",
        "        return value",
        "    }",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func parameter(_ usr: String, _ name: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: "parameter",
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }

    let label = parameter("usr-label", "label")
    let message = parameter("usr-message", "message")
    let webView = parameter("usr-web-view", "webView")
    let shadowedValue = parameter("usr-shadowed-value", "value")
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [label, message, webView, shadowedValue],
        occurrences: [
            testOccurrence(label, path: file.path, line: 3, token: "label", roles: ["definition"]),
            testOccurrence(message, path: file.path, line: 6, token: "message", roles: ["definition"]),
            testOccurrence(
                webView,
                path: file.path,
                line: 9,
                token: "webView",
                roles: ["definition"]
            ),
            testOccurrence(
                shadowedValue,
                path: file.path,
                line: 12,
                token: "value",
                roles: ["definition"]
            )
        ]
    )
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    let labelEntry = try #require(plan.entries.first { $0.usr == label.usr })
    let messageEntry = try #require(plan.entries.first { $0.usr == message.usr })
    let webViewEntry = try #require(plan.entries.first { $0.usr == webView.usr })
    #expect(plan.entries.count == 3)
    #expect(labelEntry.replacements.count == 2)
    #expect(messageEntry.replacements.count == 2)
    #expect(plan.denied.contains { $0.usr == shadowedValue.usr })
    #expect(webViewEntry.replacements.count == 3)
    #expect(plan.parameterSyntaxFacts.localBindingReferenceTokens == 6)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 1)
    #expect(plan.parameterLocalBindingOutcome.candidates == 3)
    #expect(plan.parameterLocalBindingOutcome.renamed == 3)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("init(_ \(labelEntry.newName): String)"))
    #expect(patched.contains("self.label = \(labelEntry.newName)"))
    #expect(patched.contains("func format(_ \(messageEntry.newName): String)"))
    #expect(patched.contains("\\(\(messageEntry.newName))"))
    #expect(patched.contains("func evaluate(_ \(webViewEntry.newName): WebView)"))
    #expect(patched.contains("[weak \(webViewEntry.newName)]"))
    #expect(patched.contains("\(webViewEntry.newName)?.run()"))
    #expect(patched.contains("func shadow(_ value: Int)"))
}

@Test func parameterLocalBindingRenameFailsClosedForImplicitSwiftBindings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ImplicitBindings.swift")
    let lines = [
        "func catchShadow(_ error: Error) {",
        "    do { throw error } catch { _ = error }",
        "}",
        "subscript(_ newValue: Int) -> Int {",
        "    get { newValue }",
        "    set { print(newValue) }",
        "}",
        "func observerShadow(_ oldValue: Int) {",
        "    var value = 0 { didSet { print(oldValue) } }",
        "    print(oldValue, value)",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func parameter(_ usr: String, _ name: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: "parameter",
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }

    let error = parameter("usr-implicit-error-shadow", "error")
    let newValue = parameter("usr-implicit-new-value-shadow", "newValue")
    let oldValue = parameter("usr-implicit-old-value-shadow", "oldValue")
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [error, newValue, oldValue],
        occurrences: [
            testOccurrence(error, path: file.path, line: 1, token: "error", roles: ["definition"]),
            testOccurrence(
                newValue,
                path: file.path,
                line: 4,
                token: "newValue",
                roles: ["definition"]
            ),
            testOccurrence(
                oldValue,
                path: file.path,
                line: 8,
                token: "oldValue",
                roles: ["definition"]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.entries.isEmpty)
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 3)
    #expect(plan.parameterSyntaxFacts.localBindingOnlyCoverageCandidates == 0)
    #expect(plan.denied.map(\.usr).contains(error.usr))
    #expect(plan.denied.map(\.usr).contains(newValue.usr))
    #expect(plan.denied.map(\.usr).contains(oldValue.usr))
}

@Test func parameterCallSiteSyntaxFactsResolveCompilerAnchoredLabelsAndCallShapes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Calls.swift")
    let lines = [
        "struct Box {",
        "    init(first: Int, second: Int = 0) {}",
        "}",
        "func consume<T>(value: T) {}",
        "func use(box: Box) {",
        "    _ = Box(first: 1)",
        "    box.run(value: 2) {}",
        "    consume<Int>(value: 3)",
        "    _ = box[index: 0]",
        "    box.perform(value: 4) {} failure: {}",
        "    @Wrapper(value: 5) var wrapped = 0",
        "    box.show(сallSettingsSource: 6)",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func component(
        usr: String,
        labels: [String],
        ownerCategory: ParameterOwnerCategory = .callable,
        callLine: Int? = nil,
        callToken: String? = nil,
        hasNonCallReference: Bool = false
    ) -> ParameterRenameComponent {
        let callLocations: [IndexedSourceLocation]
        if let callLine, let callToken {
            callLocations = [IndexedSourceLocation(
                path: file.path,
                line: callLine,
                utf8Column: utf8Column(of: callToken, in: lines[callLine - 1])
            )]
        } else {
            callLocations = []
        }
        let nonCallReferenceLocations = hasNonCallReference
            ? [IndexedSourceLocation(
                path: file.path,
                line: 8,
                utf8Column: utf8Column(of: "consume", in: lines[7])
            )]
            : []
        return ParameterRenameComponent(
            callableUSR: usr,
            callableName: "call(\(labels.map { "\($0):" }.joined()))",
            callableKind: ownerCategory == .subscriptDeclaration
                ? "instanceProperty"
                : "instanceMethod",
            ownerCategory: ownerCategory,
            members: labels.enumerated().map { ordinal, label in
                ParameterRenameMember(
                    parameterUSR: "\(usr)-parameter-\(ordinal)",
                    ordinal: ordinal,
                    localBinding: label,
                    externalLabel: .named(label),
                    declarationLocations: [],
                    referenceLocations: []
                )
            },
            declarationLocations: [],
            callLocations: callLocations,
            nonCallReferenceLocations: nonCallReferenceLocations,
            hasOccurrenceOutsideSelectedRoots: false,
            isProtocolRequirement: false,
            isOverrideRelated: false,
            isRuntimeSensitive: false,
            isExternallyOwned: false,
            structuralReasons: []
        )
    }

    let components = [
        component(usr: "usr-box-init", labels: ["first", "second"], callLine: 6, callToken: "Box"),
        component(usr: "usr-run", labels: ["value", "completion"], callLine: 7, callToken: "run"),
        component(usr: "usr-consume", labels: ["value"], callLine: 8, callToken: "consume"),
        component(
            usr: "usr-subscript",
            labels: ["index"],
            ownerCategory: .subscriptDeclaration,
            callLine: 9,
            callToken: "["
        ),
        component(
            usr: "usr-perform",
            labels: ["value", "completion", "failure"],
            callLine: 10,
            callToken: "perform"
        ),
        component(
            usr: "usr-wrapper-init",
            labels: ["value"],
            callLine: 11,
            callToken: "Wrapper"
        ),
        component(
            usr: "usr-unicode-label",
            labels: ["сallSettingsSource"],
            callLine: 12,
            callToken: "show"
        ),
        component(
            usr: "usr-bad-anchor",
            labels: ["value"],
            callLine: 7,
            callToken: "value"
        ),
        component(
            usr: "usr-reference-only",
            labels: ["input"],
            hasNonCallReference: true
        )
    ]

    let facts = ParameterCallSiteSyntaxFacts(components: components, sourceCache: cache)
    let summary = facts.summary
    #expect(summary.componentsWithNamedExternalLabels == 9)
    #expect(summary.namedExternalLabelParameters == 13)
    #expect(summary.indexedCallAnchors == 8)
    #expect(summary.resolvedCallAnchors == 7)
    #expect(summary.unresolvedCallAnchors == 1)
    #expect(summary.resolvedFunctionCalls == 5)
    #expect(summary.resolvedSubscriptCalls == 1)
    #expect(summary.resolvedAttributeCalls == 1)
    #expect(summary.parenthesizedArguments == 7)
    #expect(summary.namedParenthesizedArgumentTokens == 7)
    #expect(summary.unlabeledParenthesizedArguments == 0)
    #expect(summary.firstTrailingClosures == 2)
    #expect(summary.additionalTrailingClosureLabelTokens == 1)
    #expect(summary.callsWithoutExplicitArgumentDelimiters == 0)
    #expect(summary.componentsWithAllIndexedCallsResolved == 7)
    #expect(summary.namedParametersInComponentsWithAllIndexedCallsResolved == 11)
    #expect(summary.componentsWithoutIndexedCalls == 1)
    #expect(summary.namedParametersInComponentsWithoutIndexedCalls == 1)
    #expect(summary.componentsWithNonCallReferences == 1)
    #expect(summary.namedParametersInComponentsWithNonCallReferences == 1)
    #expect(summary.unresolvedByReason == [
        "compiler call syntax unavailable at indexed call anchor": 1
    ])
    #expect(summary.unresolvedAnchors == [
        UnresolvedParameterCallSiteSyntaxFact(
            callableUSR: "usr-bad-anchor",
            callableName: "call(value:)",
            path: file.path,
            line: 7,
            utf8Column: utf8Column(of: "value", in: lines[6]),
            reason: "compiler call syntax unavailable at indexed call anchor"
        )
    ])

    let labelNames = Set(facts.rolesByAnchor.values.flatMap { roles in
        roles.arguments.compactMap { argument -> String? in
            switch argument {
            case .parenthesized(label: let label):
                return label?.name
            case .firstTrailingClosure:
                return nil
            case .additionalTrailingClosure(label: let label):
                return label.name
            }
        }
    })
    #expect(labelNames == ["failure", "first", "index", "value", "сallSettingsSource"])
}

@Test func parameterCallableReferenceSyntaxFactsClassifyBareFullNameAndSubscriptUses() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("CallableReferences.swift")
    let lines = [
        "struct Service {",
        "    func convert(value: Int) -> Int { value }",
        "    subscript(label value: Int) -> Int { value }",
        "}",
        "func use(service: Service) {",
        "    let bare = service.convert",
        "    let full = service.convert(value:)",
        "    _ = service[label: 1]",
        "    let mismatched = service.convert(other:)",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func location(line: Int, token: String) -> IndexedSourceLocation {
        IndexedSourceLocation(
            path: file.path,
            line: line,
            utf8Column: utf8Column(of: token, in: lines[line - 1])
        )
    }

    func component(
        usr: String,
        name: String,
        ownerCategory: ParameterOwnerCategory = .callable,
        references: [IndexedSourceLocation]
    ) -> ParameterRenameComponent {
        ParameterRenameComponent(
            callableUSR: usr,
            callableName: name,
            callableKind: ownerCategory == .subscriptDeclaration
                ? "instanceProperty"
                : "instanceMethod",
            ownerCategory: ownerCategory,
            members: [ParameterRenameMember(
                parameterUSR: "\(usr)-parameter",
                ordinal: 0,
                localBinding: "value",
                externalLabel: .named(
                    ownerCategory == .subscriptDeclaration ? "label" : "value"
                ),
                declarationLocations: [],
                referenceLocations: []
            )],
            declarationLocations: [],
            callLocations: [],
            nonCallReferenceLocations: references,
            hasOccurrenceOutsideSelectedRoots: false,
            isProtocolRequirement: false,
            isOverrideRelated: false,
            isRuntimeSensitive: false,
            isExternallyOwned: false,
            structuralReasons: []
        )
    }

    let convert = component(
        usr: "usr-convert",
        name: "convert(value:)",
        references: [
            location(line: 6, token: "convert"),
            location(line: 7, token: "convert")
        ]
    )
    let subscriptComponent = component(
        usr: "usr-subscript-reference",
        name: "subscript(label:)",
        ownerCategory: .subscriptDeclaration,
        references: [location(line: 8, token: "[")]
    )
    let invalid = component(
        usr: "usr-invalid-reference",
        name: "invalid(value:)",
        references: [location(line: 2, token: "value")]
    )
    let mismatched = component(
        usr: "usr-mismatched-reference",
        name: "mismatched(value:)",
        references: [location(line: 9, token: "convert")]
    )

    let facts = ParameterCallableReferenceSyntaxFacts(
        components: [convert, subscriptComponent, mismatched, invalid],
        sourceCache: cache
    )
    let summary = facts.summary
    #expect(summary.componentsWithNamedExternalLabels == 4)
    #expect(summary.namedExternalLabelParameters == 4)
    #expect(summary.componentsWithIndexedReferences == 4)
    #expect(summary.namedParametersInComponentsWithIndexedReferences == 4)
    #expect(summary.indexedReferenceAnchors == 5)
    #expect(summary.resolvedReferenceAnchors == 4)
    #expect(summary.unresolvedReferenceAnchors == 1)
    #expect(summary.resolvedBareReferences == 1)
    #expect(summary.resolvedFullNameReferences == 2)
    #expect(summary.fullNameArgumentTokens == 2)
    #expect(summary.namedFullNameArgumentTokens == 2)
    #expect(summary.resolvedSubscriptCalls == 1)
    #expect(summary.subscriptArguments == 1)
    #expect(summary.namedSubscriptArgumentLabelTokens == 1)
    #expect(summary.componentsWithAllIndexedReferencesResolved == 3)
    #expect(summary.namedParametersInComponentsWithAllIndexedReferencesResolved == 3)
    #expect(summary.unresolvedByReason == [
        "compiler callable reference syntax unavailable at indexed anchor": 1
    ])
    #expect(summary.unresolvedAnchors == [
        UnresolvedParameterCallableReferenceSyntaxFact(
            callableUSR: invalid.callableUSR,
            callableName: invalid.callableName,
            path: file.path,
            line: 2,
            utf8Column: utf8Column(of: "value", in: lines[1]),
            reason: "compiler callable reference syntax unavailable at indexed anchor"
        )
    ])

    let bareAnchor = ParameterCallableReferenceAnchor(
        callableUSR: convert.callableUSR,
        location: location(line: 6, token: "convert")
    )
    let bareRoles = try #require(facts.rolesByAnchor[bareAnchor])
    #expect(bareRoles.kind == .bareReference)
    #expect(bareRoles.fullNameArgumentTokens.isEmpty)

    let fullNameAnchor = ParameterCallableReferenceAnchor(
        callableUSR: convert.callableUSR,
        location: location(line: 7, token: "convert")
    )
    let fullNameRoles = try #require(facts.rolesByAnchor[fullNameAnchor])
    #expect(fullNameRoles.kind == .fullNameReference)
    #expect(fullNameRoles.fullNameArgumentTokens.map(\.name) == ["value"])

    let subscriptAnchor = ParameterCallableReferenceAnchor(
        callableUSR: subscriptComponent.callableUSR,
        location: location(line: 8, token: "[")
    )
    let subscriptRoles = try #require(facts.rolesByAnchor[subscriptAnchor])
    #expect(subscriptRoles.kind == .subscriptCall)
    if case .parenthesized(label: let label)? = subscriptRoles.subscriptArguments.first {
        #expect(label?.name == "label")
    } else {
        Issue.record("Expected a named subscript argument")
    }

    let source = try #require(cache.file(for: file.path))
    func sourceToken(line: Int, token: String) throws -> SourceTokenRange {
        let column = utf8Column(of: token, in: lines[line - 1])
        let byteOffset = try #require(source.byteOffset(line: line, utf8Column: column))
        let identifier = try #require(source.identifierToken(atByteOffset: byteOffset))
        return SourceTokenRange(
            path: file.path,
            name: identifier.name,
            byteRange: identifier.byteRange,
            isBackticked: identifier.isBackticked
        )
    }

    func parameterRole(
        component: ParameterRenameComponent,
        kind: ParameterDeclarationSyntaxKind,
        externalLabel: SourceTokenRange,
        localBinding: SourceTokenRange
    ) -> ParameterDeclarationSyntaxRoles {
        ParameterDeclarationSyntaxRoles(
            parameterUSR: component.members[0].parameterUSR,
            kind: kind,
            indexedDeclarationAnchor: localBinding,
            externalLabel: .named(externalLabel),
            localBinding: localBinding,
            hasDefaultValue: false,
            isVariadic: false,
            trailingClosureCompatibility: .definitelyNonCallable,
            localBindingReferences: [],
            shadowingBindingDeclarations: [],
            implicitShadowingBindingNames: [],
            syntaxOwnerToken: nil,
            indexedOwnerUSR: component.callableUSR,
            syntaxOwnerMatchesIndexedOwner: true
        )
    }

    let convertParameterToken = try sourceToken(line: 2, token: "value")
    let subscriptLabelToken = try sourceToken(line: 3, token: "label")
    let subscriptBindingToken = try sourceToken(line: 3, token: "value")
    let parameterRoles = [
        convert.members[0].parameterUSR: parameterRole(
            component: convert,
            kind: .function,
            externalLabel: convertParameterToken,
            localBinding: convertParameterToken
        ),
        subscriptComponent.members[0].parameterUSR: parameterRole(
            component: subscriptComponent,
            kind: .subscriptDeclaration,
            externalLabel: subscriptLabelToken,
            localBinding: subscriptBindingToken
        ),
        invalid.members[0].parameterUSR: parameterRole(
            component: invalid,
            kind: .function,
            externalLabel: convertParameterToken,
            localBinding: convertParameterToken
        ),
        mismatched.members[0].parameterUSR: parameterRole(
            component: mismatched,
            kind: .function,
            externalLabel: convertParameterToken,
            localBinding: convertParameterToken
        )
    ]
    let bindingFacts = ParameterCallableReferenceBindingFacts(
        components: [convert, subscriptComponent, mismatched, invalid],
        parameterRolesByUSR: parameterRoles,
        syntaxFacts: facts
    )
    let bindingSummary = bindingFacts.summary
    #expect(bindingSummary.componentsWithNamedExternalLabels == 4)
    #expect(bindingSummary.namedExternalLabelParameters == 4)
    #expect(bindingSummary.componentsWithIndexedReferences == 4)
    #expect(bindingSummary.namedParametersInComponentsWithIndexedReferences == 4)
    #expect(bindingSummary.indexedReferenceAnchors == 5)
    #expect(bindingSummary.syntaxResolvedReferenceAnchors == 4)
    #expect(bindingSummary.bindingResolvedReferenceAnchors == 3)
    #expect(bindingSummary.bindingUnresolvedReferenceAnchors == 2)
    #expect(bindingSummary.boundBareReferences == 1)
    #expect(bindingSummary.boundFullNameReferences == 1)
    #expect(bindingSummary.boundFullNameArgumentTokens == 1)
    #expect(bindingSummary.boundNamedFullNameLabelTokens == 1)
    #expect(bindingSummary.boundSubscriptCalls == 1)
    #expect(bindingSummary.boundSubscriptArguments == 1)
    #expect(bindingSummary.boundNamedSubscriptLabelTokens == 1)
    #expect(bindingSummary.componentsWithAllIndexedReferencesBound == 2)
    #expect(bindingSummary.namedParametersInComponentsWithAllIndexedReferencesBound == 2)
    #expect(bindingSummary.fullNameSignatureMismatches == 1)
    #expect(bindingSummary.ambiguousSubscriptCalls == 0)
    #expect(bindingSummary.unmatchedSubscriptCalls == 0)
    #expect(bindingSummary.unresolvedByReason == [
        "callable reference syntax unresolved: compiler callable reference syntax unavailable at indexed anchor": 1,
        "full-name argument tokens do not match declaration parameter roles": 1
    ])

    let bareBinding = try #require(bindingFacts.bindingsByAnchor[bareAnchor])
    #expect(bareBinding.kind == .bareReference)
    #expect(bareBinding.fullNameArguments.isEmpty)
    #expect(bareBinding.subscriptArguments.isEmpty)

    let fullNameBinding = try #require(bindingFacts.bindingsByAnchor[fullNameAnchor])
    #expect(fullNameBinding.kind == .fullNameReference)
    #expect(fullNameBinding.fullNameArguments.map(\.parameterUSR) == [
        convert.members[0].parameterUSR
    ])
    #expect(fullNameBinding.fullNameArguments.map(\.parameterOrdinal) == [0])
    #expect(fullNameBinding.fullNameArguments.map(\.token.name) == ["value"])

    let subscriptBinding = try #require(bindingFacts.bindingsByAnchor[subscriptAnchor])
    #expect(subscriptBinding.kind == .subscriptCall)
    #expect(subscriptBinding.subscriptArguments.map(\.parameterUSR) == [
        subscriptComponent.members[0].parameterUSR
    ])
    #expect(subscriptBinding.subscriptArguments.map(\.parameterOrdinal) == [0])
}

@Test func parameterExternalLabelComponentsRequireClosedRelationGraphs() throws {
    var nextOffset = 0

    func token(_ name: String) -> SourceTokenRange {
        defer { nextOffset += name.utf8.count + 1 }
        return SourceTokenRange(
            path: "/tmp/ParameterExternalLabelComponents.swift",
            name: name,
            byteRange: nextOffset..<(nextOffset + name.utf8.count)
        )
    }

    func component(
        usr: String,
        label: String,
        isProtocolRequirement: Bool = false,
        isOverrideRelated: Bool = false,
        isRuntimeSensitive: Bool = false
    ) -> ParameterRenameComponent {
        ParameterRenameComponent(
            callableUSR: usr,
            callableName: "call(\(label):)",
            callableKind: "instanceMethod",
            ownerCategory: .callable,
            members: [ParameterRenameMember(
                parameterUSR: "\(usr)-parameter",
                ordinal: 0,
                localBinding: label,
                externalLabel: .named(label),
                declarationLocations: [],
                referenceLocations: []
            )],
            declarationLocations: [],
            callLocations: [],
            nonCallReferenceLocations: [],
            hasOccurrenceOutsideSelectedRoots: false,
            isProtocolRequirement: isProtocolRequirement,
            isOverrideRelated: isOverrideRelated,
            isRuntimeSensitive: isRuntimeSensitive,
            isExternallyOwned: false,
            structuralReasons: []
        )
    }

    let standalone = component(usr: "usr-standalone", label: "value")
    let requirement = component(
        usr: "usr-requirement",
        label: "value",
        isProtocolRequirement: true,
        isOverrideRelated: true
    )
    let witness = component(
        usr: "usr-witness",
        label: "value",
        isOverrideRelated: true
    )
    let externalOverride = component(
        usr: "usr-external-override",
        label: "value",
        isOverrideRelated: true
    )
    let runtime = component(
        usr: "c:objc-runtime-method",
        label: "value",
        isRuntimeSensitive: true
    )
    let mismatchedBase = component(
        usr: "usr-mismatched-base",
        label: "value",
        isOverrideRelated: true
    )
    let mismatchedChild = component(
        usr: "usr-mismatched-child",
        label: "other",
        isOverrideRelated: true
    )
    let components = [
        standalone,
        requirement,
        witness,
        externalOverride,
        runtime,
        mismatchedBase,
        mismatchedChild
    ]

    var parameterRoles: [String: ParameterDeclarationSyntaxRoles] = [:]
    for component in components {
        let label = try #require(component.members.first?.externalLabel)
        guard case .named(let name) = label else {
            Issue.record("Expected named test parameter")
            continue
        }
        let sourceToken = token(name)
        let parameterUSR = try #require(component.members.first?.parameterUSR)
        parameterRoles[parameterUSR] = ParameterDeclarationSyntaxRoles(
            parameterUSR: parameterUSR,
            kind: .function,
            indexedDeclarationAnchor: sourceToken,
            externalLabel: .named(sourceToken),
            localBinding: sourceToken,
            hasDefaultValue: false,
            isVariadic: false,
            trailingClosureCompatibility: .definitelyNonCallable,
            localBindingReferences: [],
            shadowingBindingDeclarations: [],
            implicitShadowingBindingNames: [],
            syntaxOwnerToken: nil,
            indexedOwnerUSR: component.callableUSR,
            syntaxOwnerMatchesIndexedOwner: true
        )
    }

    let selectedUSRs = Set(components.map(\.callableUSR))
    let indexedFacts = IndexedSemanticFacts(
        selectedDeclarationUSRs: selectedUSRs,
        protocolRequirementUSRs: [requirement.callableUSR],
        runtimeSensitiveUSRs: [runtime.callableUSR],
        overrideRelationNeighbors: [
            requirement.callableUSR: [witness.callableUSR],
            witness.callableUSR: [requirement.callableUSR],
            externalOverride.callableUSR: ["s:external-base"],
            "s:external-base": [externalOverride.callableUSR],
            mismatchedBase.callableUSR: [mismatchedChild.callableUSR],
            mismatchedChild.callableUSR: [mismatchedBase.callableUSR]
        ],
        parameterRenameComponents: components
    )
    let cache = try SourceFileCache(paths: [])
    let callSyntaxFacts = ParameterCallSiteSyntaxFacts(
        components: components,
        sourceCache: cache
    )
    let callBindingFacts = ParameterCallArgumentBindingFacts(
        components: components,
        parameterRolesByUSR: parameterRoles,
        callSiteSyntaxFacts: callSyntaxFacts
    )
    let referenceSyntaxFacts = ParameterCallableReferenceSyntaxFacts(
        components: components,
        sourceCache: cache
    )
    let referenceBindingFacts = ParameterCallableReferenceBindingFacts(
        components: components,
        parameterRolesByUSR: parameterRoles,
        syntaxFacts: referenceSyntaxFacts
    )
    let facts = ParameterExternalLabelComponentFacts(
        indexedFacts: indexedFacts,
        parameterRolesByUSR: parameterRoles,
        callBindingFacts: callBindingFacts,
        callableReferenceBindingFacts: referenceBindingFacts
    )

    let summary = facts.summary
    #expect(summary.atomicComponents == 5)
    #expect(summary.sourceCallableComponents == 7)
    #expect(summary.namedExternalLabelParameters == 7)
    #expect(summary.eligibleAtomicComponents == 2)
    #expect(summary.eligibleSourceCallableComponents == 3)
    #expect(summary.eligibleNamedExternalLabelParameters == 3)
    #expect(summary.deniedAtomicComponents == 3)
    #expect(summary.deniedSourceCallableComponents == 4)
    #expect(summary.deniedNamedExternalLabelParameters == 4)
    #expect(summary.standaloneAtomicComponents == 2)
    #expect(summary.eligibleStandaloneAtomicComponents == 1)
    #expect(summary.relatedAtomicComponents == 3)
    #expect(summary.eligibleRelatedAtomicComponents == 1)
    #expect(summary.protocolRelatedAtomicComponents == 1)
    #expect(summary.eligibleProtocolRelatedAtomicComponents == 1)
    #expect(summary.overrideRelatedAtomicComponents == 3)
    #expect(summary.eligibleOverrideRelatedAtomicComponents == 1)
    #expect(summary.blockerComponents == [
        "inconsistentRelatedSignature": 1,
        "objectiveCRuntimeDispatch": 1,
        "relationLeavesSelectedSourceRoots": 1
    ])
    #expect(Set(summary.eligibleComponents.map(\.key)) == [
        standalone.callableUSR,
        requirement.callableUSR
    ])

    let closedProtocol = try #require(facts.components.first { component in
        component.relatedCallableUSRs == [requirement.callableUSR, witness.callableUSR]
    })
    #expect(closedProtocol.isEligible)
    #expect(closedProtocol.ordinalComponents.count == 1)
    #expect(closedProtocol.ordinalComponents[0].originalLabel == "value")
    #expect(closedProtocol.ordinalComponents[0].parameterUSRs == [
        requirement.members[0].parameterUSR,
        witness.members[0].parameterUSR
    ])

    let externalComponent = try #require(facts.components.first {
        $0.relatedCallableUSRs.contains("s:external-base")
    })
    #expect(!externalComponent.isEligible)
    #expect(externalComponent.blockers == [.relationLeavesSelectedSourceRoots])
}

@Test func renamePlannerCoordinatesExternalLabelsAcrossProtocolDeclarationsAndUses() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ExternalLabels.swift")
    let lines = [
        "protocol Service {",
        "    func send(wire requirementValue: Int)",
        "}",
        "struct ServiceImpl: Service {",
        "    func send(wire localValue: Int) {",
        "        _ = localValue",
        "    }",
        "}",
        "func exercise(service: Service) {",
        "    service.send(wire: 1)",
        "    _ = Service.send(wire:)",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }

    let service = symbol("usr-service", "Service", "protocol")
    let implementation = symbol("usr-service-impl", "ServiceImpl", "struct")
    let requirement = symbol("usr-send-requirement", "send(wire:)", "instanceMethod")
    let witness = symbol("usr-send-witness", "send(wire:)", "instanceMethod")
    let requirementValue = symbol(
        "usr-requirement-value",
        "requirementValue",
        "parameter"
    )
    let localValue = symbol("usr-local-value", "localValue", "parameter")

    func relation(_ symbol: SymbolRecord, role: String) -> RelationRecord {
        RelationRecord(
            usr: symbol.usr,
            name: symbol.name,
            rolesRaw: 0,
            roles: [role]
        )
    }

    let occurrences = [
        testOccurrence(
            service,
            path: file.path,
            line: 1,
            token: "Service",
            roles: ["definition"]
        ),
        testOccurrence(
            implementation,
            path: file.path,
            line: 4,
            token: "ServiceImpl",
            roles: ["definition"]
        ),
        testOccurrence(
            requirement,
            path: file.path,
            line: 2,
            token: "send",
            roles: ["definition"],
            relations: [
                relation(service, role: "childOf"),
                relation(witness, role: "baseOf")
            ]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 5,
            token: "send",
            roles: ["definition"],
            relations: [
                relation(implementation, role: "childOf"),
                relation(requirement, role: "overrideOf")
            ]
        ),
        testOccurrence(
            requirement,
            path: file.path,
            line: 10,
            token: "send",
            roles: ["reference", "call"]
        ),
        testOccurrence(
            requirement,
            path: file.path,
            line: 11,
            token: "send",
            roles: ["reference"]
        ),
        testOccurrence(
            requirementValue,
            path: file.path,
            line: 2,
            token: "requirementValue",
            roles: ["definition"],
            relations: [relation(requirement, role: "childOf")]
        ),
        testOccurrence(
            localValue,
            path: file.path,
            line: 5,
            token: "localValue",
            roles: ["definition"],
            relations: [relation(witness, role: "childOf")]
        ),
        testOccurrence(
            localValue,
            path: file.path,
            line: 6,
            token: "localValue",
            roles: ["reference", "read"]
        )
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            service, implementation, requirement, witness,
            requirementValue, localValue
        ],
        occurrences: occurrences
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let requirementEntry = try #require(plan.entries.first {
        $0.usr == requirementValue.usr
    })
    let witnessEntry = try #require(plan.entries.first { $0.usr == localValue.usr })
    #expect(requirementEntry.newName == witnessEntry.newName)
    #expect(requirementEntry.newName.first?.isLowercase == true)
    #expect(Set(requirementEntry.replacements.map(\.oldName)) == [
        "wire", "requirementValue"
    ])
    #expect(Set(witnessEntry.replacements.map(\.oldName)) == ["wire", "localValue"])
    #expect(plan.conflicts.isEmpty)
    #expect(plan.parameterExternalLabelRenameOutcome.candidateAtomicComponents == 1)
    #expect(plan.parameterExternalLabelRenameOutcome.candidateParameterUSRs == 2)
    #expect(plan.parameterExternalLabelRenameOutcome.renamedAtomicComponents == 1)
    #expect(plan.parameterExternalLabelRenameOutcome.renamedParameterUSRs == 2)
    #expect(plan.parameterExternalLabelRenameOutcome.deniedAtomicComponents == 0)
    #expect(plan.parameterExternalLabelRenameOutcome.unclassifiedParameterUSRs == 0)

    try SourcePatcher().apply(
        [requirementEntry, witnessEntry].flatMap(\.replacements)
    )
    let patched = try String(contentsOf: file, encoding: .utf8)
    let newName = requirementEntry.newName
    #expect(patched.contains("func send(\(newName) \(newName): Int)"))
    #expect(patched.contains("_ = \(newName)"))
    #expect(patched.contains("service.send(\(newName): 1)"))
    #expect(patched.contains("Service.send(\(newName):)"))
}

@Test func renamePlannerRenamesInitializerLabelWithoutInventingALocalBinding() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("InitializerLabel.swift")
    let lines = [
        "struct Sink {",
        "    init(event _: Int) {}",
        "}",
        "let sink = Sink(event: 1)"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }

    let sink = symbol("usr-sink", "Sink", "struct")
    let initializer = symbol("usr-sink-init", "init(event:)", "constructor")
    let event = symbol("usr-event", "_", "parameter")
    func childOf(_ owner: SymbolRecord) -> RelationRecord {
        RelationRecord(
            usr: owner.usr,
            name: owner.name,
            rolesRaw: 0,
            roles: ["childOf"]
        )
    }
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [sink, initializer, event],
        occurrences: [
            testOccurrence(
                sink,
                path: file.path,
                line: 1,
                token: "Sink",
                roles: ["definition"]
            ),
            testOccurrence(
                initializer,
                path: file.path,
                line: 2,
                token: "init",
                roles: ["definition"],
                relations: [childOf(sink)]
            ),
            testOccurrence(
                initializer,
                path: file.path,
                line: 4,
                token: "Sink",
                roles: ["reference", "call"]
            ),
            testOccurrence(
                event,
                path: file.path,
                line: 2,
                token: "_",
                roles: ["definition"],
                relations: [childOf(initializer)]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == event.usr })
    #expect(entry.oldName == "event")
    #expect(Set(entry.replacements.map(\.oldName)) == ["event"])
    #expect(entry.replacements.count == 2)
    #expect(!entry.replacements.contains { $0.oldName == "_" })
    #expect(plan.parameterExternalLabelRenameOutcome.renamedParameterUSRs == 1)
    #expect(plan.parameterExternalLabelRenameOutcome.deniedParameterUSRs == 0)

    try SourcePatcher().apply(entry.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("init(\(entry.newName) _: Int)"))
    #expect(patched.contains("Sink(\(entry.newName): 1)"))
}

@Test func renamePlannerCoordinatesKeywordArgumentLabels() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("KeywordArgumentLabel.swift")
    let lines = [
        "func route(for value: Int) {",
        "    _ = value",
        "}",
        "route(for: 1)"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    let route = symbol("usr-route", "route(for:)", "function")
    let value = symbol("usr-route-value", "value", "parameter")
    let childOfRoute = RelationRecord(
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
                roles: ["definition"]
            ),
            testOccurrence(
                route,
                path: file.path,
                line: 4,
                token: "route",
                roles: ["reference", "call"]
            ),
            testOccurrence(
                value,
                path: file.path,
                line: 1,
                token: "value",
                roles: ["definition"],
                relations: [childOfRoute]
            ),
            testOccurrence(
                value,
                path: file.path,
                line: 2,
                token: "value",
                roles: ["reference", "read"]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == value.usr })
    #expect(Set(entry.replacements.map(\.oldName)) == ["for", "value"])
    #expect(entry.replacements.count == 4)
    #expect(plan.parameterExternalLabelRenameOutcome.renamedParameterUSRs == 1)
    #expect(plan.parameterExternalLabelRenameOutcome.deniedParameterUSRs == 0)
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(entry.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func route(\(entry.newName) \(entry.newName): Int)"))
    #expect(patched.contains("_ = \(entry.newName)"))
    #expect(patched.contains("route(\(entry.newName): 1)"))
}

@Test func renamePlannerCoordinatesContextualKeywordParameterBindings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("ContextualKeyword.swift")
    let lines = [
        "func configure(prefix: Int) {",
        "    _ = prefix",
        "}",
        "configure(prefix: 1)"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    let configure = SymbolRecord(
        usr: "usr-contextual-configure",
        name: "configure(prefix:)",
        kind: "function",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let prefix = SymbolRecord(
        usr: "usr-contextual-prefix",
        name: "prefix",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let childOfConfigure = RelationRecord(
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
                roles: ["definition"]
            ),
            testOccurrence(
                configure,
                path: file.path,
                line: 4,
                token: "configure",
                roles: ["reference", "call"]
            ),
            testOccurrence(
                prefix,
                path: file.path,
                line: 1,
                token: "prefix",
                roles: ["definition"],
                relations: [childOfConfigure]
            ),
            testOccurrence(
                prefix,
                path: file.path,
                line: 2,
                token: "prefix",
                roles: ["reference", "read"]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == prefix.usr })
    #expect(entry.oldName == "prefix")
    #expect(entry.newName.first?.isLowercase == true)
    #expect(entry.replacements.count == 3)
    #expect(plan.parameterExternalLabelRenameOutcome.renamedParameterUSRs == 1)
    #expect(plan.parameterExternalLabelRenameOutcome.deniedParameterUSRs == 0)
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(entry.replacements)
    let runner = CommandRunner()
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}

@Test func externalLabelComponentFailsClosedForShorthandClosureShadowing() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ClosureShadow.swift")
    let lines = [
        "func compute(state: Int, commands: (Int) -> Void) {",
        "    work { state in commands(state) }",
        "}",
        "compute(state: 1, commands: { _ in })"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    let compute = symbol(
        "usr-shadowed-compute",
        "compute(state:commands:)",
        "function"
    )
    let state = symbol("usr-shadowed-state", "state", "parameter")
    let commands = symbol("usr-shadowed-commands", "commands", "parameter")
    func childOfCompute() -> RelationRecord {
        RelationRecord(
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
                line: 1,
                token: "compute",
                roles: ["definition"]
            ),
            testOccurrence(
                compute,
                path: file.path,
                line: 4,
                token: "compute",
                roles: ["reference", "call"]
            ),
            testOccurrence(
                state,
                path: file.path,
                line: 1,
                token: "state",
                roles: ["definition"],
                relations: [childOfCompute()]
            ),
            testOccurrence(
                commands,
                path: file.path,
                line: 1,
                token: "commands",
                roles: ["definition"],
                relations: [childOfCompute()]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    #expect(!plan.entries.contains { $0.usr == state.usr || $0.usr == commands.usr })
    #expect(plan.parameterSyntaxFacts.parametersWithShadowingBindingDeclarations == 1)
    #expect(plan.parameterExternalLabelComponentFacts.deniedAtomicComponents == 1)
    #expect(plan.parameterExternalLabelComponentFacts.blockerComponents == [
        "unsafeLocalBindingScope": 1
    ])
    #expect(plan.parameterExternalLabelRenameOutcome.candidateAtomicComponents == 0)
    #expect(plan.conflicts.isEmpty)
}

@Test func externalLabelComponentPreservesDynamicMemberLookupLabel() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("DynamicMember.swift")
    let lines = [
        "struct Root { let value: Int }",
        "@dynamicMemberLookup",
        "struct Wrapper {",
        "    let root: Root",
        "    subscript<T>(dynamicMember keyPath: KeyPath<Root, T>) -> T {",
        "        root[keyPath: keyPath]",
        "    }",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    let wrapper = symbol("usr-dynamic-wrapper", "Wrapper", "struct")
    let dynamicSubscript = symbol(
        "usr-dynamic-subscript",
        "subscript(dynamicMember:)",
        "instanceProperty"
    )
    let keyPath = symbol("usr-dynamic-key-path", "keyPath", "parameter")
    func childOf(_ owner: SymbolRecord) -> RelationRecord {
        RelationRecord(
            usr: owner.usr,
            name: owner.name,
            rolesRaw: 0,
            roles: ["childOf"]
        )
    }
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [wrapper, dynamicSubscript, keyPath],
        occurrences: [
            testOccurrence(
                wrapper,
                path: file.path,
                line: 3,
                token: "Wrapper",
                roles: ["definition"]
            ),
            testOccurrence(
                dynamicSubscript,
                path: file.path,
                line: 5,
                token: "subscript",
                roles: ["definition"],
                relations: [childOf(wrapper)]
            ),
            testOccurrence(
                keyPath,
                path: file.path,
                line: 5,
                token: "keyPath",
                roles: ["definition"],
                relations: [childOf(dynamicSubscript)]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    #expect(!plan.entries.contains { $0.usr == keyPath.usr })
    #expect(plan.parameterExternalLabelComponentFacts.deniedAtomicComponents == 1)
    #expect(plan.parameterExternalLabelComponentFacts.blockerComponents == [
        "languageRequiredExternalLabel": 1
    ])
    #expect(plan.parameterExternalLabelRenameOutcome.candidateAtomicComponents == 0)
    #expect(plan.conflicts.isEmpty)
}

@Test func parameterSyntaxFactsExcludeKeyPathMembersFromLocalBindingReferences() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("KeyPathMember.swift")
    let lines = [
        "struct Model { var position: Int }",
        "func inspect(_ position: Int) {",
        "    _ = \\Model.position",
        "    print(position)",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])
    let position = SymbolRecord(
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
                roles: ["definition"]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let entry = try #require(plan.entries.first { $0.usr == position.usr })
    #expect(entry.replacements.count == 2)
    #expect(plan.parameterSyntaxFacts.localBindingReferenceTokens == 1)
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(entry.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("func inspect(_ \(entry.newName): Int)"))
    #expect(patched.contains("\\Model.position"))
    #expect(patched.contains("print(\(entry.newName))"))
}

@Test func externalLabelComponentPreservesPropertyWrapperInitializerLabel() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("PropertyWrapperInitializer.swift")
    let lines = [
        "@propertyWrapper",
        "struct Wrapper<Value> {",
        "    var wrappedValue: Value",
        "    init(wrappedValue value: Value) {",
        "        wrappedValue = value",
        "    }",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    let wrapper = symbol("usr-wrapper", "Wrapper", "struct")
    let initializer = symbol(
        "usr-wrapper-initializer",
        "init(wrappedValue:)",
        "constructor"
    )
    let value = symbol("usr-wrapper-value", "value", "parameter")
    func childOf(_ owner: SymbolRecord) -> RelationRecord {
        RelationRecord(
            usr: owner.usr,
            name: owner.name,
            rolesRaw: 0,
            roles: ["childOf"]
        )
    }
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [wrapper, initializer, value],
        occurrences: [
            testOccurrence(
                wrapper,
                path: file.path,
                line: 2,
                token: "Wrapper",
                roles: ["definition"]
            ),
            testOccurrence(
                initializer,
                path: file.path,
                line: 4,
                token: "init",
                roles: ["definition"],
                relations: [childOf(wrapper)]
            ),
            testOccurrence(
                value,
                path: file.path,
                line: 4,
                token: "value",
                roles: ["definition"],
                relations: [childOf(initializer)]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    #expect(!plan.entries.contains { $0.usr == value.usr })
    #expect(plan.parameterExternalLabelComponentFacts.deniedAtomicComponents == 1)
    #expect(plan.parameterExternalLabelComponentFacts.blockerComponents == [
        "languageRequiredExternalLabel": 1
    ])
    #expect(plan.parameterExternalLabelRenameOutcome.candidateAtomicComponents == 0)
    #expect(plan.conflicts.isEmpty)
}

@Test func externalLabelComponentDeniesUncoveredInheritedConstructorCalls() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("InheritedInitializer.swift")
    let lines = [
        "class Base {",
        "    init(session: Int, url: String) {}",
        "    convenience init(session: Int) {",
        "        self.init(session: session, url: \"\")",
        "    }",
        "}",
        "class Child: Base {}",
        "let child = Child(session: 1)"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    let base = symbol("usr-inherited-base", "Base", "class")
    let child = symbol("usr-inherited-child", "Child", "class")
    let initializer = symbol(
        "usr-inherited-convenience-initializer",
        "init(session:)",
        "constructor"
    )
    let session = symbol("usr-inherited-session", "session", "parameter")
    func relation(_ owner: SymbolRecord, role: String) -> RelationRecord {
        RelationRecord(
            usr: owner.usr,
            name: owner.name,
            rolesRaw: 0,
            roles: [role]
        )
    }
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [base, child, initializer, session],
        occurrences: [
            testOccurrence(
                base,
                path: file.path,
                line: 1,
                token: "Base",
                roles: ["definition"]
            ),
            testOccurrence(
                child,
                path: file.path,
                line: 7,
                token: "Child",
                roles: ["definition"]
            ),
            testOccurrence(
                base,
                path: file.path,
                line: 7,
                token: "Base",
                roles: ["reference", "baseOf"],
                relations: [relation(child, role: "baseOf")]
            ),
            testOccurrence(
                initializer,
                path: file.path,
                line: 3,
                token: "init",
                roles: ["definition"],
                relations: [relation(base, role: "childOf")]
            ),
            testOccurrence(
                session,
                path: file.path,
                line: 3,
                token: "session",
                roles: ["definition"],
                relations: [relation(initializer, role: "childOf")]
            ),
            testOccurrence(
                child,
                path: file.path,
                line: 8,
                token: "Child",
                roles: ["reference"]
            )
        ]
    )

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    #expect(!plan.entries.contains { $0.usr == session.usr })
    #expect(plan.parameterExternalLabelComponentFacts.deniedAtomicComponents == 1)
    #expect(plan.parameterExternalLabelComponentFacts.blockerComponents == [
        "incompleteInheritedConstructorCoverage": 1
    ])
    #expect(plan.parameterExternalLabelRenameOutcome.candidateAtomicComponents == 0)
    #expect(plan.conflicts.isEmpty)
}

@Test func parameterCallArgumentBindingsResolveDefaultsVariadicsAndTrailingClosures() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ArgumentBindings.swift")
    let lines = [
        "struct Service {",
        "    func send(required: Int, optional: Int = 0, values: Int..., completion: () -> Void, failure: () -> Void) {}",
        "    func choose(first: () -> Void = {}, second: () -> Void = {}) {}",
        "    func finish(animated: Bool = true, completion: (() -> Void)? = nil) {}",
        "}",
        "func use(service: Service) {",
        "    service.send(required: 1, values: 2, 3) {} failure: {}",
        "    service.choose {}",
        "    service.finish {}",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(
        to: file,
        atomically: true,
        encoding: .utf8
    )
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    func childOf(_ owner: SymbolRecord) -> RelationRecord {
        RelationRecord(usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["childOf"])
    }

    let send = symbol(
        "usr-send",
        "send(required:optional:values:completion:failure:)",
        "instanceMethod"
    )
    let required = symbol("usr-required", "required", "parameter")
    let optional = symbol("usr-optional", "optional", "parameter")
    let values = symbol("usr-binding-values", "values", "parameter")
    let completion = symbol("usr-completion", "completion", "parameter")
    let failure = symbol("usr-failure", "failure", "parameter")
    let choose = symbol("usr-choose", "choose(first:second:)", "instanceMethod")
    let first = symbol("usr-first", "first", "parameter")
    let second = symbol("usr-second", "second", "parameter")
    let finish = symbol("usr-finish", "finish(animated:completion:)", "instanceMethod")
    let animated = symbol("usr-animated", "animated", "parameter")
    let finishCompletion = symbol(
        "usr-finish-completion",
        "completion",
        "parameter"
    )
    let bool = symbol("usr-bool", "Bool", "struct")

    let occurrences = [
        testOccurrence(send, path: file.path, line: 2, token: "send", roles: ["definition"]),
        testOccurrence(
            required,
            path: file.path,
            line: 2,
            token: "required",
            roles: ["definition"],
            relations: [childOf(send)]
        ),
        testOccurrence(
            optional,
            path: file.path,
            line: 2,
            token: "optional",
            roles: ["definition"],
            relations: [childOf(send)]
        ),
        testOccurrence(
            values,
            path: file.path,
            line: 2,
            token: "values",
            roles: ["definition"],
            relations: [childOf(send)]
        ),
        testOccurrence(
            completion,
            path: file.path,
            line: 2,
            token: "completion",
            roles: ["definition"],
            relations: [childOf(send)]
        ),
        testOccurrence(
            failure,
            path: file.path,
            line: 2,
            token: "failure",
            roles: ["definition"],
            relations: [childOf(send)]
        ),
        testOccurrence(
            send,
            path: file.path,
            line: 7,
            token: "send",
            roles: ["reference", "call"]
        ),
        testOccurrence(choose, path: file.path, line: 3, token: "choose", roles: ["definition"]),
        testOccurrence(
            first,
            path: file.path,
            line: 3,
            token: "first",
            roles: ["definition"],
            relations: [childOf(choose)]
        ),
        testOccurrence(
            second,
            path: file.path,
            line: 3,
            token: "second",
            roles: ["definition"],
            relations: [childOf(choose)]
        ),
        testOccurrence(
            choose,
            path: file.path,
            line: 8,
            token: "choose",
            roles: ["reference", "call"]
        ),
        testOccurrence(finish, path: file.path, line: 4, token: "finish", roles: ["definition"]),
        testOccurrence(
            animated,
            path: file.path,
            line: 4,
            token: "animated",
            roles: ["definition"],
            relations: [childOf(finish)]
        ),
        testOccurrence(bool, path: file.path, line: 4, token: "Bool", roles: ["reference"]),
        testOccurrence(
            finishCompletion,
            path: file.path,
            line: 4,
            token: "completion",
            roles: ["definition"],
            relations: [childOf(finish)]
        ),
        testOccurrence(
            finish,
            path: file.path,
            line: 9,
            token: "finish",
            roles: ["reference", "call"]
        )
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            send, required, optional, values, completion, failure,
            choose, first, second, finish, animated, finishCompletion, bool
        ],
        occurrences: occurrences
    )
    let indexedFacts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [file])
    let parameterSyntaxFacts = ParameterSyntaxFacts(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [file]
    )
    let callSiteSyntaxFacts = ParameterCallSiteSyntaxFacts(
        components: indexedFacts.parameterRenameComponents,
        sourceCache: cache
    )
    let bindingFacts = ParameterCallArgumentBindingFacts(
        components: indexedFacts.parameterRenameComponents,
        parameterRolesByUSR: parameterSyntaxFacts.rolesByUSR,
        callSiteSyntaxFacts: callSiteSyntaxFacts
    )

    let sendAnchor = ParameterCallSiteAnchor(
        callableUSR: send.usr,
        location: IndexedSourceLocation(
            path: file.path,
            line: 7,
            utf8Column: utf8Column(of: "send", in: lines[6])
        )
    )
    let sendBindings = try #require(bindingFacts.bindingsByAnchor[sendAnchor])
    #expect(sendBindings.arguments.map(\.parameterUSR) == [
        required.usr,
        values.usr,
        values.usr,
        completion.usr,
        failure.usr
    ])
    #expect(sendBindings.arguments.map(\.parameterOrdinal) == [0, 2, 2, 3, 4])

    let finishAnchor = ParameterCallSiteAnchor(
        callableUSR: finish.usr,
        location: IndexedSourceLocation(
            path: file.path,
            line: 9,
            utf8Column: utf8Column(of: "finish", in: lines[8])
        )
    )
    let finishBindings = try #require(bindingFacts.bindingsByAnchor[finishAnchor])
    #expect(finishBindings.arguments.map(\.parameterUSR) == [finishCompletion.usr])
    #expect(finishBindings.arguments.map(\.parameterOrdinal) == [1])

    let summary = bindingFacts.summary
    #expect(summary.componentsWithNamedExternalLabels == 3)
    #expect(summary.namedExternalLabelParameters == 9)
    #expect(summary.indexedCallAnchors == 3)
    #expect(summary.syntaxResolvedCallAnchors == 3)
    #expect(summary.bindingResolvedCallAnchors == 2)
    #expect(summary.bindingUnresolvedCallAnchors == 1)
    #expect(summary.boundArguments == 6)
    #expect(summary.boundNamedLabelTokens == 3)
    #expect(summary.ambiguousCallAnchors == 1)
    #expect(summary.unmatchedCallAnchors == 0)
    #expect(summary.componentsWithAllIndexedCallsBound == 2)
    #expect(summary.namedParametersInComponentsWithAllIndexedCallsBound == 7)
    #expect(summary.componentsWithoutIndexedCalls == 0)
    #expect(summary.namedParametersInComponentsWithoutIndexedCalls == 0)
    #expect(summary.unresolvedByReason == [
        "call argument-to-parameter ordinal mapping is ambiguous": 1
    ])
    #expect(summary.unresolvedAnchors == [
        UnresolvedParameterCallArgumentBindingFact(
            callableUSR: choose.usr,
            callableName: choose.name,
            path: file.path,
            line: 8,
            utf8Column: utf8Column(of: "choose", in: lines[7]),
            reason: "call argument-to-parameter ordinal mapping is ambiguous"
        )
    ])
}

@Test func safetyAnalyzerDeniesClassesNamedByInterfaceBuilderResources() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Controllers.swift")
    let lines = [
        "class MainViewController {}",
        "class StoryboardViewController {}",
        "class PlainViewController {}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
    #expect(storyboardDecision.reasons.contains("Interface Builder resource requires stable class name StoryboardViewController"))

    #expect(decision(name: "PlainViewController", line: 3).allowed == true)
}

@Test func safetyAnalyzerAllowsPublicAndOpenDeclarations() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "public protocol Analyzer {}",
        "open class Sample { public var count: Int { 1 }; public func run() {} }",
        "public var globalCount = 1"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "@objcMembers public class RuntimeModel {",
        "    public func inheritedExposure() {}",
        "}",
        "@objc",
        "public func explicitlyExposed() {}",
        "public dynamic func dynamicallyDispatched() {}",
        "public class RuntimeController {}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let runtimeSensitiveUSRs: Set<String> = [
        "usr-runtime-model", "usr-inherited-exposure", "usr-explicit", "usr-dynamic"
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
    let objcMembersMethod = decision(usr: "usr-inherited-exposure", name: "inheritedExposure", kind: "instanceMethod", line: 2)
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
    #expect([objcMembersClass, objcMembersMethod, explicitObjCMethod, dynamicMethod].allSatisfy {
        $0.reasons.contains { $0.contains("runtime-reflected") }
    })
    #expect(objcUSRClass.reasons.contains { $0.contains("Objective-C-compatible USR") })
}

@Test func indexedSemanticFactsDoNotInferRuntimeDispatchFromOverrideSyntax() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "class Base { func run() {} }",
        "class Child: Base { override func run() {} }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
        roles: ["definition"]
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        roles: ["definition"]
    )
    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(!decision.allowed)
    #expect(decision.reasons.contains { $0.contains("externally linked declaration") })
}

@Test func lexicalRuntimeAttributeFallbackIsLimitedToTheAnnotatedDeclaration() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "@objc(StableRuntimeName)",
        "public class RuntimeNamed {}",
        "@IBInspectable public var designedValue: Int { 0 }",
        "@objc public func exposedToObjectiveC() {}",
        "public func swiftOnly() {}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
            roles: ["definition"]
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
    #expect([runtimeNamed, designedValue, exposed].allSatisfy {
        $0.reasons.contains { $0.contains("runtime-reflected") }
    })
}

@Test func renamePlannerPlansAndPatchesPublicSymbols() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("PublicAPI.swift")
    let lines = [
        "public struct PublicModel {",
        "    public var displayName: String { \"name\" }",
        "}",
        "public func makeModel() -> PublicModel {",
        "    PublicModel()",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
            occurrence(symbol: typeSymbol, tokenName: "PublicModel", line: 5, roles: ["reference"])
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
    #expect(patched == [
        "public struct \(typeName) {",
        "    public var \(propertyName): String { \"name\" }",
        "}",
        "public func \(functionName)() -> \(typeName) {",
        "    \(typeName)()",
        "}",
        ""
    ].joined(separator: "\n"))
}

@Test func safetyAnalyzerDeniesProtocolMembersUntilWitnessesAreRenamedTogether() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "public protocol Analyzer {",
        "    func run()",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-run",
        name: "run",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        indexedFacts: IndexedSemanticFacts(protocolRequirementUSRs: [symbol.usr])
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("protocol members require relation-aware witness renaming"))
}

@Test func safetyAnalyzerAllowsProtocolNominalConformanceReferences() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "protocol Analyzer {}",
        "struct Runner: Analyzer {}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-analyzer",
        name: "Analyzer",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let declaration = OccurrenceRecord(
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
    let conformanceReference = OccurrenceRecord(
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
            RelationRecord(
                usr: "usr-runner",
                name: "Runner",
                rolesRaw: 1,
                roles: ["baseOf"]
            )
        ]
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [declaration, conformanceReference]),
        sourceCache: cache
    )

    #expect(decision.allowed == true)
    #expect(decision.oldName == "Analyzer")
}

@Test func safetyAnalyzerDeniesLocalProtocolMembersUntilWitnessesAreRenamedTogether() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "enum Interval { fileprivate protocol Quality { var title: String { get } } }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-title",
        name: "title",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
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

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        indexedFacts: IndexedSemanticFacts(protocolRequirementUSRs: [symbol.usr])
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("protocol members require relation-aware witness renaming"))
}

@Test func renamePlannerCoordinatesClosedProtocolRequirementsAndWitnesses() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ProtocolWitnesses.swift")
    let lines = [
        "protocol Analyzer {",
        "    func run()",
        "}",
        "struct First: Analyzer { func run() {} }",
        "struct Second: Analyzer { func run() {} }",
        "func exercise(_ value: any Analyzer) { value.run() }",
        "func exerciseFirst() { First().run() }",
        "func exerciseSecond() { Second().run() }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let protocolSymbol = SymbolRecord(
        usr: "usr-analyzer-protocol",
        name: "Analyzer",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = SymbolRecord(
        usr: "usr-analyzer-run-requirement",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let firstWitness = SymbolRecord(
        usr: "usr-first-run-witness",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let secondWitness = SymbolRecord(
        usr: "usr-second-run-witness",
        name: "run()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let childOfProtocol = RelationRecord(
        usr: protocolSymbol.usr,
        name: protocolSymbol.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let overridesRequirement = RelationRecord(
        usr: requirement.usr,
        name: requirement.name,
        rolesRaw: 0,
        roles: ["overrideOf"]
    )

    let occurrences = [
        testOccurrence(protocolSymbol, path: file.path, line: 1, token: "Analyzer", roles: ["definition"]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 2,
            token: "run",
            roles: ["definition", "childOf"],
            relations: [childOfProtocol]
        ),
        testOccurrence(
            firstWitness,
            path: file.path,
            line: 4,
            token: "run",
            roles: ["definition", "overrideOf"],
            relations: [overridesRequirement]
        ),
        // This is a semantic conformance edge located at the owner token,
        // not another spelling of `run`; the planner must not patch `First`.
        testOccurrence(
            firstWitness,
            path: file.path,
            line: 4,
            token: "First",
            roles: ["implicit", "overrideOf", "containedBy"],
            relations: [overridesRequirement]
        ),
        testOccurrence(
            secondWitness,
            path: file.path,
            line: 5,
            token: "run",
            roles: ["definition", "overrideOf"],
            relations: [overridesRequirement]
        ),
        testOccurrence(requirement, path: file.path, line: 6, token: "run", roles: ["reference", "call"]),
        testOccurrence(firstWitness, path: file.path, line: 7, token: "run", roles: ["reference", "call"]),
        testOccurrence(secondWitness, path: file.path, line: 8, token: "run", roles: ["reference", "call"])
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [protocolSymbol, requirement, firstWitness, secondWitness],
        occurrences: occurrences
    )
    let mappingStore = MappingStore()
    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(sourceRoot: directory),
        mappingStore: mappingStore
    )

    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let componentEntries = plan.entries.filter {
        [requirement.usr, firstWitness.usr, secondWitness.usr].contains($0.usr)
    }

    #expect(plan.conflicts.isEmpty)
    #expect(componentEntries.count == 3)
    #expect(Set(componentEntries.map(\.oldName)) == ["run"])
    #expect(Set(componentEntries.map(\.newName)).count == 1)
    #expect(plan.denied.allSatisfy {
        ![requirement.usr, firstWitness.usr, secondWitness.usr].contains($0.usr)
    })
    #expect(Set([requirement, firstWitness, secondWitness].compactMap {
        mappingStore.entry(for: $0.usr)?.obfuscatedName
    }).count == 1)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    let newName = try #require(componentEntries.first?.newName)
    #expect(patched.contains("protocol Oa"))
    #expect(patched.contains("func \(newName)()"))
    #expect(patched.contains("First().\(newName)()"))
    #expect(patched.contains("Second().\(newName)()"))
    #expect(patched.contains("struct First:"))
}

@Test func renamePlannerDoesNotApplyStoredPropertyDenialToProtocolRequirements() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ProtocolProperty.swift")
    let lines = [
        "protocol Payload {",
        "    var value: Int",
        "        { get }",
        "}",
        "struct Model: Payload { var value: Int { 42 } }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = SymbolRecord(
        usr: "usr-payload-protocol",
        name: "Payload",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = SymbolRecord(
        usr: "usr-payload-value-requirement",
        name: "value",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let witness = SymbolRecord(
        usr: "usr-model-value-witness",
        name: "value",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrences = [
        testOccurrence(owner, path: file.path, line: 1, token: "Payload", roles: ["definition"]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 2,
            token: "value",
            roles: ["definition", "childOf"],
            relations: [RelationRecord(usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["childOf"])]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 5,
            token: "value",
            roles: ["definition", "overrideOf"],
            relations: [RelationRecord(
                usr: requirement.usr,
                name: requirement.name,
                rolesRaw: 0,
                roles: ["overrideOf"]
            )]
        )
    ]
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, requirement, witness],
            occurrences: occurrences
        ),
        sourceCache: cache
    )
    let entries = plan.entries.filter { $0.usr == requirement.usr || $0.usr == witness.usr }

    #expect(entries.count == 2)
    #expect(Set(entries.map(\.newName)).count == 1)
    #expect(!plan.denied.contains { decision in
        (decision.usr == requirement.usr || decision.usr == witness.usr)
            && decision.reasons.contains(where: { $0.contains("memberwise initializer") })
    })
}

@Test func renamePlannerKeepsProtocolAssociatedTypeWitnessesInTheSemanticOverrideGraph() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("AssociatedType.swift")
    let lines = [
        "protocol Payload { associatedtype DTO }",
        "struct Message: Payload { typealias DTO = String }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = SymbolRecord(
        usr: "usr-payload",
        name: "Payload",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = SymbolRecord(
        usr: "usr-payload-dto",
        name: "DTO",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let witness = SymbolRecord(
        usr: "usr-message-dto",
        name: "DTO",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrences = [
        testOccurrence(owner, path: file.path, line: 1, token: "Payload", roles: ["definition"]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 1,
            token: "DTO",
            roles: ["definition", "childOf"],
            relations: [RelationRecord(
                usr: owner.usr,
                name: owner.name,
                rolesRaw: 0,
                roles: ["childOf"]
            )]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 2,
            token: "DTO",
            roles: ["definition", "overrideOf", "baseOf"],
            relations: [
                RelationRecord(
                    usr: requirement.usr,
                    name: requirement.name,
                    rolesRaw: 0,
                    roles: ["overrideOf"]
                ),
                RelationRecord(
                    usr: requirement.usr,
                    name: requirement.name,
                    rolesRaw: 0,
                    roles: ["baseOf"]
                )
            ]
        )
    ]
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, requirement, witness],
            occurrences: occurrences
        ),
        sourceCache: cache
    )
    let entries = plan.entries.filter { $0.usr == requirement.usr || $0.usr == witness.usr }

    #expect(entries.count == 2)
    #expect(Set(entries.map(\.newName)).count == 1)
    #expect(plan.denied.allSatisfy { $0.usr != requirement.usr && $0.usr != witness.usr })
}

@Test func renamePlannerDeniesProtocolComponentThatReachesExternalRequirement() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ExternalRequirement.swift")
    let lines = [
        "protocol LocalService { func send() }",
        "struct Client: LocalService { func send() {} }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = SymbolRecord(
        usr: "usr-local-service",
        name: "LocalService",
        kind: "protocol",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = SymbolRecord(
        usr: "usr-local-send",
        name: "send()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let witness = SymbolRecord(
        usr: "usr-client-send",
        name: "send()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let localOverride = RelationRecord(
        usr: requirement.usr,
        name: requirement.name,
        rolesRaw: 0,
        roles: ["overrideOf"]
    )
    let externalOverride = RelationRecord(
        usr: "s:15ExternalPackage0A7ServiceP4sendyyF",
        name: "send()",
        rolesRaw: 0,
        roles: ["overrideOf"]
    )
    let occurrences = [
        testOccurrence(owner, path: file.path, line: 1, token: "LocalService", roles: ["definition"]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 1,
            token: "send",
            roles: ["definition", "childOf"],
            relations: [RelationRecord(usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["childOf"])]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 2,
            token: "send",
            roles: ["definition", "overrideOf"],
            relations: [localOverride, externalOverride]
        )
    ]
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, requirement, witness],
            occurrences: occurrences
        ),
        sourceCache: cache
    )
    let componentUSRs = Set([requirement.usr, witness.usr])
    let componentDenials = plan.denied.filter { componentUSRs.contains($0.usr) }

    #expect(plan.entries.allSatisfy { !componentUSRs.contains($0.usr) })
    #expect(componentDenials.count == 2)
    #expect(componentDenials.allSatisfy { decision in
        decision.reasons.contains(where: {
            $0.contains("coordinated component denied atomically")
                && $0.contains("no indexed occurrence group")
        })
    })
}

@Test func renamePlannerKeepsObjectiveCProtocolRequirementsDenied() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ObjectiveCProtocol.swift")
    let lines = [
        "@objc protocol LegacyService { func ping() }",
        "final class Adapter: NSObject, LegacyService { func ping() {} }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = SymbolRecord(
        usr: "c:@M@Sample@objc(pl)LegacyService",
        name: "LegacyService",
        kind: "protocol",
        language: "objective-c",
        propertiesRaw: 0,
        properties: "[]"
    )
    let requirement = SymbolRecord(
        usr: "c:@M@Sample@objc(pl)LegacyService(im)ping",
        name: "ping()",
        kind: "instanceMethod",
        language: "objective-c",
        propertiesRaw: 0,
        properties: "[]"
    )
    let witness = SymbolRecord(
        usr: "s:6Sample7AdapterC4pingyyF",
        name: "ping()",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrences = [
        testOccurrence(owner, path: file.path, line: 1, token: "LegacyService", roles: ["definition"]),
        testOccurrence(
            requirement,
            path: file.path,
            line: 1,
            token: "ping",
            roles: ["definition", "childOf"],
            relations: [RelationRecord(usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["childOf"])]
        ),
        testOccurrence(
            witness,
            path: file.path,
            line: 2,
            token: "ping",
            roles: ["definition", "overrideOf"],
            relations: [RelationRecord(
                usr: requirement.usr,
                name: requirement.name,
                rolesRaw: 0,
                roles: ["overrideOf"]
            )]
        )
    ]
    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, requirement, witness],
            occurrences: occurrences
        ),
        sourceCache: cache
    )

    #expect(plan.entries.allSatisfy { $0.usr != requirement.usr && $0.usr != witness.usr })
    #expect(plan.denied.contains { decision in
        decision.usr == requirement.usr
            && decision.reasons.contains("Objective-C-compatible USR requires a stable runtime name")
    })
    #expect(plan.denied.contains { decision in
        decision.usr == witness.usr
            && decision.reasons.contains("override relations require coordinated renaming")
    })
}

@Test func safetyAnalyzerAllowsStoredPropertiesBecauseMemberwiseLabelsAreIndexedByPropertyUSR() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "struct Sample { let count: Int }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-count",
        name: "count",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "count", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed)
    #expect(!decision.reasons.contains { $0.contains("memberwise initializer") })
}

@Test func renamePlannerPreservesMemberwiseLabelsExplicitInitializerLabelsAndCodableKeys() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixture = repositoryRoot
        .appendingPathComponent("Fixtures/StoredPropertySafety/main.swift")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let sourceURL = directory.appendingPathComponent("main.swift")
    try FileManager.default.copyItem(at: fixture, to: sourceURL)
    let sourceText = try String(contentsOf: sourceURL, encoding: .utf8)
    let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let cache = try SourceFileCache(paths: [sourceURL.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    func relation(_ target: SymbolRecord, _ roles: [String]) -> RelationRecord {
        RelationRecord(
            usr: target.usr,
            name: target.name,
            rolesRaw: 0,
            roles: roles
        )
    }
    func occurrence(
        _ symbol: SymbolRecord,
        line: Int,
        token: String,
        roles: [String],
        relations: [RelationRecord] = []
    ) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: sourceURL.path,
            line: line,
            utf8Column: utf8Column(of: token, in: lines[line - 1]),
            moduleName: "StoredPropertySafety",
            isSystem: false,
            rolesRaw: 0,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relations
        )
    }

    let envelope = symbol("s:fixture-envelope", "Envelope", "struct")
    let payload = symbol("s:fixture-payload", "MemberwisePayload", "struct")
    let explicitPayload = symbol("s:fixture-explicit", "ExplicitPayload", "struct")
    let serverName = symbol("s:fixture-server-name", "serverName", "instanceProperty")
    let retryCount = symbol("s:fixture-retry-count", "retryCount", "instanceProperty")
    let diagnosticText = symbol("s:fixture-diagnostic-text", "diagnosticText", "instanceProperty")
    let storedValue = symbol("s:fixture-stored-value", "storedValue", "instanceProperty")
    let localValue = symbol("s:fixture-local-value", "localValue", "parameter")
    let serverNameGetter = symbol("s:fixture-server-name-getter", "getter:serverName", "instanceMethod")
    let retryCountGetter = symbol("s:fixture-retry-count-getter", "getter:retryCount", "instanceMethod")
    let diagnosticTextGetter = symbol("s:fixture-diagnostic-text-getter", "getter:diagnosticText", "instanceMethod")
    let storedValueGetter = symbol("s:fixture-stored-value-getter", "getter:storedValue", "instanceMethod")
    let wrapperOwner = symbol("s:fixture-wrapper-owner", "WrapperOwner", "struct")
    let wrappedNumber = symbol("s:fixture-wrapped-number", "wrappedNumber", "instanceProperty")
    let wrappedNumberGetter = symbol("s:fixture-wrapped-number-getter", "getter:wrappedNumber", "instanceMethod")
    let projectedWrappedNumber = symbol(
        "s:fixture-projected-wrapped-number",
        "$wrappedNumber",
        "instanceProperty"
    )
    let decodable = symbol("s:Se", "Decodable", "protocol")
    let encodable = symbol("s:SE", "Encodable", "protocol")

    var occurrences: [OccurrenceRecord] = [
        occurrence(envelope, line: 3, token: "Envelope", roles: ["definition", "canonical"]),
        occurrence(
            payload,
            line: 4,
            token: "MemberwisePayload",
            roles: ["definition", "childOf", "canonical"],
            relations: [relation(envelope, ["childOf"])]
        ),
        occurrence(explicitPayload, line: 14, token: "ExplicitPayload", roles: ["definition", "canonical"]),
        occurrence(
            serverName,
            line: 5,
            token: "serverName",
            roles: ["definition", "childOf", "canonical"],
            relations: [relation(payload, ["childOf"])]
        ),
        occurrence(
            retryCount,
            line: 6,
            token: "retryCount",
            roles: ["definition", "childOf", "canonical"],
            relations: [relation(payload, ["childOf"])]
        ),
        occurrence(
            diagnosticText,
            line: 8,
            token: "diagnosticText",
            roles: ["definition", "childOf", "canonical"],
            relations: [relation(payload, ["childOf"])]
        ),
        occurrence(
            storedValue,
            line: 15,
            token: "storedValue",
            roles: ["definition", "childOf", "canonical"],
            relations: [relation(explicitPayload, ["childOf"])]
        ),
        occurrence(
            serverNameGetter,
            line: 5,
            token: "serverName",
            roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
            relations: [relation(serverName, ["childOf", "accessorOf"])]
        ),
        occurrence(
            retryCountGetter,
            line: 6,
            token: "retryCount",
            roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
            relations: [relation(retryCount, ["childOf", "accessorOf"])]
        ),
        occurrence(
            diagnosticTextGetter,
            line: 8,
            token: "diagnosticText",
            roles: ["definition", "childOf", "accessorOf", "canonical"],
            relations: [relation(diagnosticText, ["childOf", "accessorOf"])]
        ),
        occurrence(
            storedValueGetter,
            line: 15,
            token: "storedValue",
            roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
            relations: [relation(storedValue, ["childOf", "accessorOf"])]
        ),
        occurrence(
            decodable,
            line: 4,
            token: "Codable",
            roles: ["reference", "implicit", "baseOf"],
            relations: [relation(payload, ["baseOf"])]
        ),
        occurrence(
            encodable,
            line: 4,
            token: "Codable",
            roles: ["reference", "implicit", "baseOf"],
            relations: [relation(payload, ["baseOf"])]
        ),
        occurrence(wrapperOwner, line: 41, token: "WrapperOwner", roles: ["definition", "canonical"]),
        occurrence(
            wrappedNumber,
            line: 42,
            token: "wrappedNumber",
            roles: ["definition", "childOf", "canonical"],
            relations: [relation(wrapperOwner, ["childOf"])]
        ),
        occurrence(
            wrappedNumberGetter,
            line: 42,
            token: "wrappedNumber",
            roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
            relations: [relation(wrappedNumber, ["childOf", "accessorOf"])]
        ),
        occurrence(
            projectedWrappedNumber,
            line: 42,
            token: "FixtureBox",
            roles: ["definition", "implicit", "childOf", "canonical"],
            relations: [relation(wrapperOwner, ["childOf"])]
        )
    ]

    occurrences.append(contentsOf: [
        occurrence(envelope, line: 22, token: "Envelope", roles: ["reference"]),
        occurrence(envelope, line: 27, token: "Envelope", roles: ["reference"]),
        occurrence(payload, line: 22, token: "MemberwisePayload", roles: ["reference", "call"]),
        occurrence(payload, line: 27, token: "MemberwisePayload", roles: ["reference"]),
        occurrence(explicitPayload, line: 32, token: "ExplicitPayload", roles: ["reference", "call"]),
        occurrence(serverName, line: 9, token: "serverName", roles: ["reference", "read"]),
        occurrence(serverName, line: 22, token: "serverName", roles: ["reference"]),
        occurrence(serverName, line: 28, token: "serverName", roles: ["reference", "read"]),
        occurrence(retryCount, line: 9, token: "retryCount", roles: ["reference", "read"]),
        occurrence(retryCount, line: 22, token: "retryCount", roles: ["reference"]),
        occurrence(retryCount, line: 29, token: "retryCount", roles: ["reference", "read"]),
        occurrence(diagnosticText, line: 30, token: "diagnosticText", roles: ["reference", "read"]),
        occurrence(storedValue, line: 18, token: "storedValue", roles: ["reference", "write"]),
        occurrence(storedValue, line: 33, token: "storedValue", roles: ["reference", "read"]),
        occurrence(localValue, line: 17, token: "localValue", roles: ["definition", "childOf"]),
        occurrence(localValue, line: 18, token: "localValue", roles: ["reference", "read"]),
        occurrence(localValue, line: 32, token: "externalLabel", roles: ["reference"]),
        occurrence(wrapperOwner, line: 46, token: "WrapperOwner", roles: ["reference", "call"]),
        occurrence(wrappedNumber, line: 47, token: "wrappedNumber", roles: ["reference", "read"]),
        occurrence(
            projectedWrappedNumber,
            line: 43,
            token: "$wrappedNumber",
            roles: ["reference", "read"]
        )
    ])

    let symbols = [
        envelope, payload, explicitPayload, serverName, retryCount, diagnosticText, storedValue,
        localValue, serverNameGetter, retryCountGetter, diagnosticTextGetter, storedValueGetter,
        wrapperOwner, wrappedNumber, wrappedNumberGetter, projectedWrappedNumber, decodable, encodable
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [sourceURL.path],
        symbols: symbols,
        occurrences: occurrences
    )
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])
    #expect(facts.storedPropertyUSRs == [
        serverName.usr, retryCount.usr, storedValue.usr, wrappedNumber.usr
    ])
    #expect(!facts.storedPropertyUSRs.contains(diagnosticText.usr))
    #expect(facts.serializationSensitiveOwnerUSRs == [payload.usr])

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.conflicts.isEmpty)
    #expect(plan.supportReplacements.count == 2)
    #expect(plan.entries.contains { $0.usr == serverName.usr })
    #expect(plan.entries.contains { $0.usr == retryCount.usr })
    #expect(plan.entries.contains { $0.usr == diagnosticText.usr })
    #expect(plan.entries.contains { $0.usr == storedValue.usr })
    #expect(plan.entries.contains { $0.usr == wrappedNumber.usr })
    #expect(!plan.entries.contains { $0.usr == localValue.usr })

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: sourceURL, encoding: .utf8)
    let serverNameEntry = try #require(plan.entries.first { $0.usr == serverName.usr })
    let retryCountEntry = try #require(plan.entries.first { $0.usr == retryCount.usr })
    #expect(patched.contains("case \(serverNameEntry.newName) = \"serverName\""))
    #expect(patched.contains("case \(retryCountEntry.newName) = \"retryCount\""))
    #expect(!patched.contains("case diagnosticText"))
    #expect(patched.contains("externalLabel: 4"))
    #expect(patched.contains("externalLabel localValue"))
    let wrappedNumberEntry = try #require(plan.entries.first { $0.usr == wrappedNumber.usr })
    #expect(patched.contains("$\(wrappedNumberEntry.newName)"))
    #expect(!patched.contains("$wrappedNumber"))

    let executable = directory.appendingPathComponent("StoredPropertySafety")
    let runner = CommandRunner(logDirectory: directory.appendingPathComponent("logs", isDirectory: true))
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", sourceURL.path, "-o", executable.path]
    )
    _ = try runner.run(executable: executable.path, arguments: [])
}

@Test func renamePlannerDeniesSerializedPropertiesWithExistingCustomCodingKeys() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("CustomCodingKeys.swift")
    let lines = [
        "struct Schema: Codable {",
        "    let value: Int",
        "    enum CodingKeys: String, CodingKey { case value = \"wire_value\" }",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    func occurrence(
        _ symbol: SymbolRecord,
        line: Int,
        token: String,
        roles: [String],
        relations: [RelationRecord] = []
    ) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: file.path,
            line: line,
            utf8Column: utf8Column(of: token, in: lines[line - 1]),
            moduleName: "CustomCodingKeys",
            isSystem: false,
            rolesRaw: 0,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relations
        )
    }
    func childOf(_ symbol: SymbolRecord) -> RelationRecord {
        RelationRecord(usr: symbol.usr, name: symbol.name, rolesRaw: 0, roles: ["childOf"])
    }
    func baseOf(_ symbol: SymbolRecord) -> RelationRecord {
        RelationRecord(usr: symbol.usr, name: symbol.name, rolesRaw: 0, roles: ["baseOf"])
    }

    let owner = symbol("s:custom-schema", "Schema", "struct")
    let property = symbol("s:custom-schema-value", "value", "instanceProperty")
    let getter = symbol("s:custom-schema-value-getter", "getter:value", "instanceMethod")
    let codingKeys = symbol("s:custom-schema-coding-keys", "CodingKeys", "enum")
    let decodable = symbol("s:Se", "Decodable", "protocol")
    let encodable = symbol("s:SE", "Encodable", "protocol")
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [owner, property, getter, codingKeys, decodable, encodable],
        occurrences: [
            occurrence(owner, line: 1, token: "Schema", roles: ["definition", "canonical"]),
            occurrence(
                property,
                line: 2,
                token: "value",
                roles: ["definition", "childOf", "canonical"],
                relations: [childOf(owner)]
            ),
            occurrence(
                getter,
                line: 2,
                token: "value",
                roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
                relations: [RelationRecord(
                    usr: property.usr,
                    name: property.name,
                    rolesRaw: 0,
                    roles: ["childOf", "accessorOf"]
                )]
            ),
            occurrence(
                codingKeys,
                line: 3,
                token: "CodingKeys",
                roles: ["definition", "childOf", "canonical"],
                relations: [childOf(owner)]
            ),
            occurrence(
                decodable,
                line: 1,
                token: "Codable",
                roles: ["reference", "implicit", "baseOf"],
                relations: [baseOf(owner)]
            ),
            occurrence(
                encodable,
                line: 1,
                token: "Codable",
                roles: ["reference", "implicit", "baseOf"],
                relations: [baseOf(owner)]
            )
        ]
    )
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])
    #expect(facts.explicitCodingKeysOwnerUSRs == [owner.usr])

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.supportReplacements.isEmpty)
    #expect(!plan.entries.contains { $0.usr == property.usr })
    #expect(plan.denied.contains { decision in
        decision.usr == property.usr
            && decision.reasons.contains("serialized stored property requires explicit key preservation")
    })
}

@Test func renamePlannerDeniesSerializedPropertiesWithCustomCodableImplementation() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixture = repositoryRoot
        .appendingPathComponent("Fixtures/ManualCodableSafety/main.swift")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let sourceURL = directory.appendingPathComponent("main.swift")
    try FileManager.default.copyItem(at: fixture, to: sourceURL)
    let sourceText = try String(contentsOf: sourceURL, encoding: .utf8)
    let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let cache = try SourceFileCache(paths: [sourceURL.path])

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    func relation(_ target: SymbolRecord, _ roles: [String]) -> RelationRecord {
        RelationRecord(
            usr: target.usr,
            name: target.name,
            rolesRaw: 0,
            roles: roles
        )
    }
    func occurrence(
        _ symbol: SymbolRecord,
        line: Int,
        token: String,
        roles: [String],
        relations: [RelationRecord] = []
    ) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: sourceURL.path,
            line: line,
            utf8Column: utf8Column(of: token, in: lines[line - 1]),
            moduleName: "ManualCodableSafety",
            isSystem: false,
            rolesRaw: 0,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relations
        )
    }

    let owner = symbol("s:manual-payload", "ManualPayload", "struct")
    let property = symbol("s:manual-payload-value", "value", "instanceProperty")
    let getter = symbol("s:manual-payload-value-getter", "getter:value", "instanceMethod")
    let customDecoder = symbol("s:manual-payload-decoder", "init(from:)", "constructor")
    let decodingRequirement = symbol("s:Se4fromxs7Decoder_p_tKcfc", "init(from:)", "constructor")
    let decodable = symbol("s:Se", "Decodable", "protocol")
    let encodable = symbol("s:SE", "Encodable", "protocol")
    let snapshot = IndexSnapshot(
        sourceFiles: [sourceURL.path],
        symbols: [owner, property, getter, customDecoder, decodingRequirement, decodable, encodable],
        occurrences: [
            occurrence(owner, line: 3, token: "ManualPayload", roles: ["definition", "canonical"]),
            occurrence(owner, line: 12, token: "ManualPayload", roles: ["reference"]),
            occurrence(
                property,
                line: 4,
                token: "value",
                roles: ["definition", "childOf", "canonical"],
                relations: [relation(owner, ["childOf"])]
            ),
            occurrence(
                property,
                line: 8,
                token: "value",
                roles: ["reference", "write"]
            ),
            occurrence(
                property,
                line: 13,
                token: "value",
                roles: ["reference", "read"]
            ),
            occurrence(
                getter,
                line: 4,
                token: "value",
                roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
                relations: [relation(property, ["childOf", "accessorOf"])]
            ),
            occurrence(
                customDecoder,
                line: 6,
                token: "init",
                roles: ["definition", "childOf", "overrideOf", "canonical"],
                relations: [
                    relation(decodingRequirement, ["overrideOf"]),
                    relation(owner, ["childOf"])
                ]
            ),
            occurrence(
                decodable,
                line: 3,
                token: "Codable",
                roles: ["reference", "implicit", "baseOf"],
                relations: [relation(owner, ["baseOf"])]
            ),
            occurrence(
                encodable,
                line: 3,
                token: "Codable",
                roles: ["reference", "implicit", "baseOf"],
                relations: [relation(owner, ["baseOf"])]
            )
        ]
    )
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])
    #expect(facts.customSerializationImplementationOwnerUSRs == [owner.usr])

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.supportReplacements.isEmpty)
    #expect(!plan.entries.contains { $0.usr == property.usr })
    #expect(plan.denied.contains { decision in
        decision.usr == property.usr
            && decision.reasons.contains("serialized stored property requires explicit key preservation")
    })

    try SourcePatcher().apply(plan.replacements)
    let executable = directory.appendingPathComponent("ManualCodableSafety")
    let runner = CommandRunner(logDirectory: directory.appendingPathComponent("logs", isDirectory: true))
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", sourceURL.path, "-o", executable.path]
    )
    _ = try runner.run(executable: executable.path, arguments: [])
}

@Test func safetyAnalyzerAllowsTypeStoredPropertiesWithoutMemberwiseInitializerSupport() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("StoredProperties.swift")
    let lines = [
        "struct Settings { static let timeout = 3; let title: String }",
        "final class Registry { static let shared = Registry() }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let analyzer = SafetyAnalyzer(sourceRoot: directory)

    func decision(
        usr: String,
        name: String,
        kind: String,
        ownerUSR: String,
        ownerName: String,
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
            moduleName: "Fixture",
            isSystem: false,
            rolesRaw: 1,
            roles: ["declaration"],
            rolesDescription: "decl",
            symbolProvider: "swift",
            relations: [
                RelationRecord(usr: ownerUSR, name: ownerName, rolesRaw: 1, roles: ["childOf"])
            ]
        )
        return analyzer.analyze(
            group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
            sourceCache: cache
        )
    }

    let structTypeProperty = decision(
        usr: "usr-timeout",
        name: "timeout",
        kind: "staticProperty",
        ownerUSR: "usr-settings",
        ownerName: "Settings",
        line: 1
    )
    #expect(structTypeProperty.allowed)
    #expect(!structTypeProperty.reasons.contains("stored property declarations require memberwise initializer label support"))

    let structInstanceProperty = decision(
        usr: "usr-title",
        name: "title",
        kind: "instanceProperty",
        ownerUSR: "usr-settings",
        ownerName: "Settings",
        line: 1
    )
    #expect(structInstanceProperty.allowed)
    #expect(!structInstanceProperty.reasons.contains { $0.contains("memberwise initializer") })

    let classTypeProperty = decision(
        usr: "usr-shared",
        name: "shared",
        kind: "classProperty",
        ownerUSR: "usr-registry",
        ownerName: "Registry",
        line: 2
    )
    #expect(classTypeProperty.allowed)
    #expect(!classTypeProperty.reasons.contains("stored property declarations require memberwise initializer label support"))
}

@Test func safetyAnalyzerDeniesPropertyWrapperRequiredNames() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "var wrappedValue: String { value }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-wrappedValue",
        name: "wrappedValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "wrappedValue", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("language-required declaration name wrappedValue"))
}

@Test func safetyAnalyzerDeniesResultBuilderRequiredNames() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "static func buildBlock<T>(_ value: T) -> T { value }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-buildBlock",
        name: "buildBlock",
        kind: "staticMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "buildBlock", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("language-required declaration name buildBlock"))
}

@Test func safetyAnalyzerDeniesStringInterpolationRequiredNames() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "mutating func appendInterpolation(json data: Data) {}"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-appendInterpolation",
        name: "appendInterpolation",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "appendInterpolation", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("language-required declaration name appendInterpolation"))
}

@Test func safetyAnalyzerDeniesExtensionsOnExternalOwners() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "extension Array {",
        "    func firstValue() -> Element? { first }",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-firstValue",
        name: "firstValue",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "firstValue", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        indexedFacts: IndexedSemanticFacts(externallyOwnedUSRs: [symbol.usr])
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
}

@Test func safetyAnalyzerDeniesStdlibModuleExtensionOwners() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "extension String.StringInterpolation {",
        "    mutating func jsonData(_ data: Data) {}",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-jsonData",
        name: "jsonData",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 2,
        utf8Column: utf8Column(of: "jsonData", in: lines[1]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        indexedFacts: IndexedSemanticFacts(externallyOwnedUSRs: [symbol.usr])
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
}

@Test func safetyAnalyzerAllowsExtensionsOnLocalNominalOwners() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "struct LocalModel {}",
        "extension LocalModel {",
        "    func helper() {}",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-helper",
        name: "helper",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 3,
        utf8Column: utf8Column(of: "helper", in: lines[2]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed == true)
    #expect(decision.oldName == "helper")
}

@Test func safetyAnalyzerDeniesExtensionsOnTypealiasOwners() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "typealias LocalAlias = String",
        "extension LocalAlias {",
        "    func helper() {}",
        "}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-helper",
        name: "helper",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 3,
        utf8Column: utf8Column(of: "helper", in: lines[2]),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache,
        indexedFacts: IndexedSemanticFacts(externallyOwnedUSRs: [symbol.usr])
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("extensions on external Swift or Objective-C owners are not self-contained"))
}

@Test func safetyAnalyzerDeniesGenericTypeParameters() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "struct Box<Value> { let value: Value }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-value",
        name: "Value",
        kind: "typealias",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "Value", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("generic type parameter occurrences are incomplete"))
}

@Test func safetyAnalyzerDeniesAccessorContextualKeywords() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "protocol Analyzer { var isRunning: Bool { get set } }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let getter = SymbolRecord(
        usr: "usr-getter",
        name: "getter:isRunning",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let getterOccurrence = OccurrenceRecord(
        symbol: getter,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "get", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let getterDecision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: getter.usr, symbol: getter, occurrences: [getterOccurrence]),
        sourceCache: cache
    )

    #expect(getterDecision.allowed == false)
    #expect(getterDecision.reasons.contains { $0.contains("non-plain identifier get") })

    let setter = SymbolRecord(
        usr: "usr-setter",
        name: "setter:isRunning",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let setterOccurrence = OccurrenceRecord(
        symbol: setter,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "set", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )
    let setterDecision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: setter.usr, symbol: setter, occurrences: [setterOccurrence]),
        sourceCache: cache
    )

    #expect(setterDecision.allowed == false)
    #expect(setterDecision.reasons.contains { $0.contains("non-plain identifier set") })
}

@Test func renamePlannerIncludesExternalReferencesForSelectedDeclarations() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
    #expect(entry.replacements.map(\.path).sorted() == [
        SourcePathNormalizer.canonicalPath(declarationFile.path),
        SourcePathNormalizer.canonicalPath(referenceFile.path)
    ].sorted())
    #expect(plan.denied.isEmpty)
}

@Test func renamePlannerCoordinatesClosedOverrideComponents() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "class Base { func run() {} }",
        "class Child: Base { override func run() {} }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
    #expect(Set([baseSymbol, childSymbol].compactMap {
        mappingStore.entry(for: $0.usr)?.obfuscatedName
    }).count == 1)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    let newName = try #require(plan.entries.first?.newName)
    #expect(patched.contains("func \(newName)()"))
    #expect(patched.contains("override func \(newName)()"))
}

@Test func renamePlannerCoordinatesBaseOfOnlyOverrideComponents() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("BaseOf.swift")
    let lines = [
        "class Base { func render() {} }",
        "class Child: Base { override func render() {} }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
            roles: ["definition", "baseOf"],
            relations: [RelationRecord(
                usr: child.usr,
                name: child.name,
                rolesRaw: 0,
                roles: ["baseOf"]
            )]
        ),
        testOccurrence(child, path: file.path, line: 2, token: "render", roles: ["definition"])
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ClassHierarchy.swift")
    let lines = [
        "class Base {}",
        "class Child: Base {}"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
            roles: ["definition", "baseOf"],
            relations: [RelationRecord(
                usr: child.usr,
                name: child.name,
                rolesRaw: 0,
                roles: ["baseOf"]
            )]
        ),
        testOccurrence(child, path: file.path, line: 2, token: "Child", roles: ["definition"]),
        testOccurrence(base, path: file.path, line: 2, token: "Base", roles: ["reference"])
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        roles: ["definition", "overrideOf"],
        relations: [RelationRecord(
            usr: externalBaseUSR,
            name: "run()",
            rolesRaw: 0,
            roles: ["overrideOf"]
        )]
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
    #expect(denial.reasons.contains { reason in
        reason.contains("coordinated override/base component denied atomically")
            && reason.contains("no indexed occurrence group: \(externalBaseUSR)")
    })
}

@Test func renamePlannerDeniesOverrideComponentThatReachesObjectiveCRuntimeDispatch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("RuntimeOverride.swift")
    let lines = [
        "class LegacyBase { func run() {} }",
        "class Child: LegacyBase { override func run() {} }"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
        testOccurrence(base, path: file.path, line: 1, token: "run", roles: ["definition"]),
        testOccurrence(
            child,
            path: file.path,
            line: 2,
            token: "run",
            roles: ["definition", "overrideOf"],
            relations: [RelationRecord(
                usr: base.usr,
                name: base.name,
                rolesRaw: 0,
                roles: ["overrideOf"]
            )]
        )
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
    #expect(plan.denied.allSatisfy { decision in
        decision.reasons.contains { $0.contains("coordinated override/base component denied atomically") }
    })
    #expect(plan.denied.contains { decision in
        decision.usr == child.usr
            && decision.reasons.contains { $0.contains("runtime-reflected") }
    })
}

@Test func renamePlannerDeniesTupleTypealiasesAndTheirNominalOwners() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("Sample.swift")
    let lines = [
        "enum Namespace {",
        "    typealias Payload = (id: Int, value: String)",
        "}",
        "let payload = Namespace.Payload(id: 1, value: \"one\")"
    ]
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])
    let owner = SymbolRecord(
        usr: "usr-namespace",
        name: "Namespace",
        kind: "enum",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let typealiasSymbol = SymbolRecord(
        usr: "usr-payload",
        name: "Payload",
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
    let typealiasOccurrence = OccurrenceRecord(
        symbol: typealiasSymbol,
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

    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(sourceRoot: directory),
        mappingStore: MappingStore()
    )
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [owner, typealiasSymbol],
            occurrences: [ownerOccurrence, typealiasOccurrence]
        ),
        sourceCache: cache
    )

    #expect(plan.entries.isEmpty)
    #expect(plan.denied.count == 2)
    #expect(plan.denied.allSatisfy { $0.reasons.contains("tuple typealias constructor occurrences are incomplete") })
}

@Test func renamePlannerDoesNotSelectSymbolsDeclaredOutsideSelectedSources() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
    #expect(plan.denied.first?.reasons.contains { $0.contains("no declaration or definition occurrence inside selected source roots") } == true)
}

@Test func coverageCohortUsesExplicitSourceSurfaceIndependentOfRenameEligibility() throws {
    let path = "/tmp/CoverageSample.swift"
    let outsidePath = "/tmp/OutsideSelection.swift"
    let renamedProperty = SymbolRecord(
        usr: "usr-renamed-property",
        name: "renamedValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let deniedProperty = SymbolRecord(
        usr: "usr-denied-property",
        name: "storedValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let getter = SymbolRecord(
        usr: "usr-getter",
        name: "getter:renamedValue",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let setter = SymbolRecord(
        usr: "usr-setter",
        name: "setter:storedValue",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let parameter = SymbolRecord(
        usr: "usr-parameter",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let enumCase = SymbolRecord(
        usr: "usr-enum-case",
        name: "ready",
        kind: "enumConstant",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let runtimeProperty = SymbolRecord(
        usr: "c:objc-runtime-property",
        name: "runtimeValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let constructor = SymbolRecord(
        usr: "usr-constructor",
        name: "init(value:)",
        kind: "constructor",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let compilerDerivedProperty = SymbolRecord(
        usr: "usr-compiler-derived-property",
        name: "$value",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let outsideProperty = SymbolRecord(
        usr: "usr-outside-property",
        name: "outsideValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )

    func occurrence(
        _ symbol: SymbolRecord,
        path occurrencePath: String? = nil,
        roles: [String] = ["declaration"],
        relation: RelationRecord? = nil
    ) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: occurrencePath ?? path,
            line: 1,
            utf8Column: 1,
            moduleName: "CoverageSample",
            isSystem: false,
            rolesRaw: 1,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relation.map { [$0] } ?? []
        )
    }

    let snapshot = IndexSnapshot(
        sourceFiles: [path, outsidePath],
        symbols: [
            renamedProperty,
            deniedProperty,
            getter,
            setter,
            parameter,
            enumCase,
            runtimeProperty,
            constructor,
            compilerDerivedProperty,
            outsideProperty
        ],
        occurrences: [
            occurrence(renamedProperty),
            occurrence(deniedProperty),
            occurrence(getter, relation: RelationRecord(
                usr: renamedProperty.usr,
                name: renamedProperty.name,
                rolesRaw: 1,
                roles: ["accessorOf"]
            )),
            occurrence(setter),
            occurrence(parameter),
            occurrence(enumCase),
            occurrence(runtimeProperty),
            occurrence(constructor),
            occurrence(compilerDerivedProperty, roles: ["definition", "implicit"]),
            occurrence(outsideProperty, path: outsidePath)
        ]
    )
    let plan = RenamePlan(
        entries: [
            RenamePlanEntry(
                usr: renamedProperty.usr,
                kind: renamedProperty.kind,
                oldName: renamedProperty.name,
                newName: "oa",
                replacements: []
            )
        ],
        denied: [
            SafetyDecision(
                usr: deniedProperty.usr,
                symbolName: deniedProperty.name,
                kind: deniedProperty.kind,
                allowed: false,
                oldName: deniedProperty.name,
                reasons: [
                    "stored property declarations require memberwise initializer label support",
                    "implicit occurrence at \(path):1:1"
                ]
            ),
            SafetyDecision(
                usr: getter.usr,
                symbolName: getter.name,
                kind: getter.kind,
                allowed: false,
                oldName: nil,
                reasons: ["implicit occurrence at \(path):1:1"]
            ),
            SafetyDecision(
                usr: setter.usr,
                symbolName: setter.name,
                kind: setter.kind,
                allowed: false,
                oldName: nil,
                reasons: ["implicit occurrence at \(path):1:1"]
            ),
            SafetyDecision(
                usr: parameter.usr,
                symbolName: parameter.name,
                kind: parameter.kind,
                allowed: false,
                oldName: parameter.name,
                reasons: ["unsupported symbol kind parameter"]
            ),
            SafetyDecision(
                usr: enumCase.usr,
                symbolName: enumCase.name,
                kind: enumCase.kind,
                allowed: false,
                oldName: enumCase.name,
                reasons: ["unsupported symbol kind enumConstant"]
            ),
            SafetyDecision(
                usr: runtimeProperty.usr,
                symbolName: runtimeProperty.name,
                kind: runtimeProperty.kind,
                allowed: false,
                oldName: runtimeProperty.name,
                reasons: ["Objective-C-compatible USR requires a stable runtime name"]
            ),
            SafetyDecision(
                usr: constructor.usr,
                symbolName: constructor.name,
                kind: constructor.kind,
                allowed: false,
                oldName: "init",
                reasons: ["unsupported symbol kind constructor"]
            ),
            SafetyDecision(
                usr: compilerDerivedProperty.usr,
                symbolName: compilerDerivedProperty.name,
                kind: compilerDerivedProperty.kind,
                allowed: false,
                oldName: compilerDerivedProperty.name,
                reasons: ["implicit occurrence at \(path):1:1"]
            ),
            SafetyDecision(
                usr: outsideProperty.usr,
                symbolName: outsideProperty.name,
                kind: outsideProperty.kind,
                allowed: false,
                oldName: outsideProperty.name,
                reasons: ["no declaration or definition occurrence inside selected source roots"]
            )
        ],
        conflicts: []
    )

    let cohort = try CoverageAnalyzer.makeBaselineCohort(
        identifier: "fixture@1",
        expectedCount: 5,
        snapshot: snapshot,
        plan: plan,
        selectedSourceFiles: [path]
    )
    let report = try CoverageAnalyzer.makeReport(cohort: cohort, snapshot: snapshot, plan: plan)

    #expect(cohort.population == .explicitSourceSurface)
    #expect(cohort.members.map(\.usr) == [
        deniedProperty.usr,
        enumCase.usr,
        parameter.usr,
        renamedProperty.usr,
        runtimeProperty.usr
    ].sorted())
    #expect(cohort.denominator == 5)
    #expect(report.renamed == 1)
    #expect(report.denied == 4)
    #expect(report.bySymbolKind.first { $0.kind == "parameter" }?.denominator == 1)
    #expect(report.bySymbolKind.first { $0.kind == "parameter" }?.renamed == 0)
    #expect(report.bySymbolKind.first { $0.kind == "enumConstant" }?.denominator == 1)
    #expect(report.syntheticAccessors.total == 2)
    #expect(report.syntheticAccessors.getters == 1)
    #expect(report.syntheticAccessors.setters == 1)
    #expect(report.syntheticAccessors.derivedRenamed == 1)
    #expect(report.syntheticAccessors.derivedUnchanged == 0)
    #expect(report.syntheticAccessors.unresolvedParent == 1)
    #expect(report.syntheticAccessors.unexpectedlyPlanned == 0)

    do {
        _ = try CoverageAnalyzer.makeBaselineCohort(
            identifier: "fixture@1",
            expectedCount: 6,
            snapshot: snapshot,
            plan: plan,
            selectedSourceFiles: [path]
        )
        Issue.record("Expected fixed denominator validation to fail")
    } catch let error as CoverageReportError {
        #expect(error.localizedDescription.contains("expected 6"))
    }
}

@Test func enumCaseComponentFactsUseIndexedOwnersAndSemanticContracts() throws {
    let root = URL(fileURLWithPath: "/tmp/enum-case-component-facts", isDirectory: true)
    let insidePath = root.appendingPathComponent("Enums.swift").path
    let outsidePath = "/tmp/enum-case-component-facts-outside.swift"

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    func relation(_ symbol: SymbolRecord, _ role: String) -> RelationRecord {
        RelationRecord(usr: symbol.usr, name: symbol.name, rolesRaw: 0, roles: [role])
    }
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

    let plainOwner = symbol("s:plain-owner", "Plain", "enum")
    let plainCase = symbol("s:plain-case", "ready", "enumConstant")
    let payloadCase = symbol("s:payload-case", "payload(value:)", "enumConstant")
    let payloadParameter = symbol("s:payload-parameter", "value", "parameter")
    let rawOwner = symbol("s:raw-owner", "Raw", "enum")
    let rawCase = symbol("s:raw-case", "wire", "enumConstant")
    let rawType = symbol("s:raw-type", "WireValue", "struct")
    let serializedOwner = symbol("s:serialized-owner", "Serialized", "enum")
    let serializedCase = symbol("s:serialized-case", "stored", "enumConstant")
    let decodable = symbol("s:Se", "Decodable", "protocol")
    let runtimeOwner = symbol("c:@E@Runtime", "Runtime", "enum")
    let runtimeCase = symbol("c:@E@Runtime@RuntimeCase", "runtime", "enumConstant")

    let snapshot = IndexSnapshot(
        sourceFiles: [insidePath, outsidePath],
        symbols: [
            plainOwner, plainCase, payloadCase, payloadParameter,
            rawOwner, rawCase, rawType,
            serializedOwner, serializedCase, decodable,
            runtimeOwner, runtimeCase
        ],
        occurrences: [
            occurrence(plainOwner, roles: ["definition"]),
            occurrence(plainCase, roles: ["definition"], relations: [
                relation(plainOwner, "childOf")
            ]),
            occurrence(plainCase, path: outsidePath, roles: ["reference"]),
            occurrence(payloadCase, roles: ["definition"], relations: [
                relation(plainOwner, "childOf")
            ]),
            occurrence(payloadParameter, roles: ["definition"], relations: [
                relation(payloadCase, "childOf")
            ]),
            occurrence(rawOwner, roles: ["definition"]),
            occurrence(rawType, roles: ["reference", "baseOf"], relations: [
                relation(rawOwner, "baseOf")
            ]),
            occurrence(rawCase, roles: ["definition"], relations: [
                relation(rawOwner, "childOf")
            ]),
            occurrence(serializedOwner, roles: ["definition"]),
            occurrence(decodable, roles: ["reference", "implicit", "baseOf"], relations: [
                relation(serializedOwner, "baseOf")
            ]),
            occurrence(serializedCase, roles: ["definition"], relations: [
                relation(serializedOwner, "childOf")
            ]),
            occurrence(runtimeOwner, roles: ["definition"]),
            occurrence(runtimeCase, roles: ["definition"], relations: [
                relation(runtimeOwner, "childOf")
            ])
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

@Test func enumCaseSyntaxFactsProtectVisibilityReflectionAndProtocolContracts() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("EnumSyntax.swift")
    let source = [
        "private enum Safe {",
        "    case idle",
        "    case payload(value: Int)",
        "    static func match(_ value: Safe) {",
        "        switch value {",
        "        case .idle: break",
        "        case .payload: break",
        "        }",
        "    }",
        "}",
        "private enum Reflected {",
        "    case logged",
        "}",
        "let reflectedText = \"\\(Reflected.logged)\"",
        "let reflectedWire = \"logged\"",
        "public enum Visible {",
        "    case shown",
        "}",
        "@available(*, deprecated)",
        "private enum Attributed {",
        "    case marked",
        "}",
        "private enum Conforming: Equatable {",
        "    case equal",
        "}"
    ].joined(separator: "\n") + "\n"
    try source.write(to: file, atomically: true, encoding: .utf8)

    func symbol(_ usr: String, _ name: String, _ kind: String) -> SymbolRecord {
        SymbolRecord(
            usr: usr,
            name: name,
            kind: kind,
            language: "swift",
            propertiesRaw: 0,
            properties: "[]"
        )
    }
    func childOf(_ owner: SymbolRecord) -> RelationRecord {
        RelationRecord(usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["childOf"])
    }
    func baseOf(_ owner: SymbolRecord) -> RelationRecord {
        RelationRecord(usr: owner.usr, name: owner.name, rolesRaw: 0, roles: ["baseOf"])
    }

    let safe = symbol("s:safe", "Safe", "enum")
    let idle = symbol("s:safe-idle", "idle", "enumConstant")
    let payload = symbol("s:safe-payload", "payload(value:)", "enumConstant")
    let value = symbol("s:safe-payload-value", "value", "parameter")
    let reflected = symbol("s:reflected", "Reflected", "enum")
    let logged = symbol("s:reflected-logged", "logged", "enumConstant")
    let visible = symbol("s:visible", "Visible", "enum")
    let shown = symbol("s:visible-shown", "shown", "enumConstant")
    let attributed = symbol("s:attributed", "Attributed", "enum")
    let marked = symbol("s:attributed-marked", "marked", "enumConstant")
    let conforming = symbol("s:conforming", "Conforming", "enum")
    let equal = symbol("s:conforming-equal", "equal", "enumConstant")
    let equatable = symbol("s:SQ", "Equatable", "protocol")

    let occurrences = [
        testOccurrence(safe, path: file.path, line: 1, token: "Safe", roles: ["definition"]),
        testOccurrence(idle, path: file.path, line: 2, token: "idle", roles: ["definition"], relations: [childOf(safe)]),
        testOccurrence(payload, path: file.path, line: 3, token: "payload", roles: ["definition"], relations: [childOf(safe)]),
        testOccurrence(value, path: file.path, line: 3, token: "value", roles: ["definition"], relations: [childOf(payload)]),
        testOccurrence(idle, path: file.path, line: 6, token: "idle", roles: ["reference"]),
        testOccurrence(payload, path: file.path, line: 7, token: "payload", roles: ["reference"]),
        testOccurrence(reflected, path: file.path, line: 11, token: "Reflected", roles: ["definition"]),
        testOccurrence(logged, path: file.path, line: 12, token: "logged", roles: ["definition"], relations: [childOf(reflected)]),
        testOccurrence(logged, path: file.path, line: 14, token: "logged", roles: ["reference"]),
        testOccurrence(visible, path: file.path, line: 16, token: "Visible", roles: ["definition"]),
        testOccurrence(shown, path: file.path, line: 17, token: "shown", roles: ["definition"], relations: [childOf(visible)]),
        testOccurrence(attributed, path: file.path, line: 20, token: "Attributed", roles: ["definition"]),
        testOccurrence(marked, path: file.path, line: 21, token: "marked", roles: ["definition"], relations: [childOf(attributed)]),
        testOccurrence(conforming, path: file.path, line: 23, token: "Conforming", roles: ["definition"]),
        testOccurrence(equatable, path: file.path, line: 23, token: "Equatable", roles: ["reference", "baseOf"], relations: [baseOf(conforming)]),
        testOccurrence(equal, path: file.path, line: 24, token: "equal", roles: ["definition"], relations: [childOf(conforming)])
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            safe, idle, payload, value,
            reflected, logged,
            visible, shown,
            attributed, marked,
            conforming, equal, equatable
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

    #expect(facts.summary.explicitEnumCases == 6)
    #expect(facts.summary.resolvedEnumCases == 6)
    #expect(facts.summary.unresolvedEnumCases == 0)
    #expect(facts.summary.indexedReferenceOccurrences == 3)
    #expect(facts.summary.resolvedReferenceOccurrences == 3)
    #expect(facts.summary.unresolvedReferenceOccurrences == 0)
    #expect(facts.summary.casesWithMatchingStringLiterals == 1)
    #expect(facts.summary.casesDirectlyInterpolated == 1)
    #expect(facts.summary.preliminaryEligibleOwnerComponents == 1)
    #expect(facts.summary.preliminaryEligibleCases == 2)
    #expect(facts.summary.preliminaryEligibleSimpleCases == 1)
    #expect(facts.summary.preliminaryEligibleAssociatedValueCases == 1)
    #expect(facts.summary.preliminaryEligibleAssociatedValueParameters == 1)

    let safeFacts = try #require(facts.components.first { $0.ownerUSR == safe.usr })
    #expect(safeFacts.accessLevel == .private)
    #expect(safeFacts.blockers.isEmpty)

    let reflectedFacts = try #require(
        facts.components.first { $0.ownerUSR == reflected.usr }
    )
    #expect(reflectedFacts.blockers.contains(.stringLiteralSpelling))
    #expect(reflectedFacts.blockers.contains(.directStringInterpolation))

    let visibleFacts = try #require(facts.components.first { $0.ownerUSR == visible.usr })
    #expect(visibleFacts.accessLevel == .public)
    #expect(visibleFacts.blockers.contains(.nonFileScopedAccess))

    let attributedFacts = try #require(
        facts.components.first { $0.ownerUSR == attributed.usr }
    )
    #expect(attributedFacts.blockers.contains(.declarationAttribute))

    let conformingFacts = try #require(
        facts.components.first { $0.ownerUSR == conforming.usr }
    )
    #expect(conformingFacts.blockers.contains(.protocolConformance))
}

private func utf8Column(of needle: String, in line: String) -> Int {
    let range = line.range(of: needle)!
    return line[..<range.lowerBound].utf8.count + 1
}

private func testOccurrence(
    _ symbol: SymbolRecord,
    path: String,
    line: Int,
    token: String,
    roles: [String],
    relations: [RelationRecord] = []
) -> OccurrenceRecord {
    let sourceLine = try! String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)[line - 1]
    return OccurrenceRecord(
        symbol: symbol,
        path: path,
        line: line,
        utf8Column: utf8Column(of: token, in: String(sourceLine)),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 0,
        roles: roles,
        rolesDescription: roles.joined(separator: ","),
        symbolProvider: "swift",
        relations: relations
    )
}
