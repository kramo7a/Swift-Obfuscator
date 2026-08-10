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

@Test func safetyAnalyzerStillDeniesRuntimeExposedPublicDeclarations() throws {
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
            sourceCache: cache
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
        sourceCache: cache
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
        sourceCache: cache
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

@Test func safetyAnalyzerDeniesStoredPropertiesUntilMemberwiseLabelsAreRewritten() throws {
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

    #expect(decision.allowed == false)
    #expect(decision.reasons.contains("stored property declarations require memberwise initializer label support"))
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
    #expect(structInstanceProperty.allowed == false)
    #expect(structInstanceProperty.reasons.contains("stored property declarations require memberwise initializer label support"))

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
        sourceCache: cache
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
        sourceCache: cache
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
        sourceCache: cache,
        localNominalTypeNames: ["LocalModel"]
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
        localNominalTypeNames: []
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

@Test func renamePlannerDeniesBothEndsOfOverrideRelations() throws {
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

    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(sourceRoot: directory),
        mappingStore: MappingStore()
    )
    let plan = planner.makePlan(
        snapshot: IndexSnapshot(
            sourceFiles: [file.path],
            symbols: [baseSymbol, childSymbol],
            occurrences: [baseOccurrence, childOccurrence]
        ),
        sourceCache: cache
    )

    #expect(plan.entries.isEmpty)
    #expect(plan.denied.count == 2)
    #expect(plan.denied.allSatisfy { $0.reasons.contains("override relations require coordinated renaming") })
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

@Test func coverageCohortKeepsFixedEngineeringDenominatorAndExcludesSyntheticAccessors() throws {
    let path = "/tmp/CoverageSample.swift"
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
    let runtimeProperty = SymbolRecord(
        usr: "c:objc-runtime-property",
        name: "runtimeValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )

    func occurrence(_ symbol: SymbolRecord, relation: RelationRecord? = nil) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: path,
            line: 1,
            utf8Column: 1,
            moduleName: "CoverageSample",
            isSystem: false,
            rolesRaw: 1,
            roles: ["declaration"],
            rolesDescription: "declaration",
            symbolProvider: "swift",
            relations: relation.map { [$0] } ?? []
        )
    }

    let snapshot = IndexSnapshot(
        sourceFiles: [path],
        symbols: [renamedProperty, deniedProperty, getter, setter, parameter, runtimeProperty],
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
            occurrence(runtimeProperty)
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
                usr: runtimeProperty.usr,
                symbolName: runtimeProperty.name,
                kind: runtimeProperty.kind,
                allowed: false,
                oldName: runtimeProperty.name,
                reasons: ["Objective-C-compatible USR requires a stable runtime name"]
            )
        ],
        conflicts: []
    )

    let cohort = try CoverageAnalyzer.makeBaselineCohort(
        identifier: "fixture@1",
        expectedCount: 2,
        snapshot: snapshot,
        plan: plan
    )
    let report = try CoverageAnalyzer.makeReport(cohort: cohort, snapshot: snapshot, plan: plan)

    #expect(cohort.members.map(\.usr) == [deniedProperty.usr, renamedProperty.usr].sorted())
    #expect(cohort.denominator == 2)
    #expect(report.renamed == 1)
    #expect(report.denied == 1)
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
            expectedCount: 3,
            snapshot: snapshot,
            plan: plan
        )
        Issue.record("Expected fixed denominator validation to fail")
    } catch let error as CoverageReportError {
        #expect(error.localizedDescription.contains("expected 3"))
    }
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
