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

@Test func safetyAnalyzerDeniesPublicAndOpenDeclarations() throws {
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

    #expect(protocolDecision.allowed == false)
    #expect(protocolDecision.oldName == "Analyzer")
    #expect(protocolDecision.reasons.contains { $0.contains("externally visible") })

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

    #expect(propertyDecision.allowed == false)
    #expect(propertyDecision.oldName == "count")
    #expect(propertyDecision.reasons.contains { $0.contains("externally visible") })

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

    #expect(functionDecision.allowed == false)
    #expect(functionDecision.oldName == "run")
    #expect(functionDecision.reasons.contains { $0.contains("externally visible") })

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

    #expect(variableDecision.allowed == false)
    #expect(variableDecision.oldName == "globalCount")
    #expect(variableDecision.reasons.contains { $0.contains("externally visible") })
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

private func utf8Column(of needle: String, in line: String) -> Int {
    let range = line.range(of: needle)!
    return line[..<range.lowerBound].utf8.count + 1
}
