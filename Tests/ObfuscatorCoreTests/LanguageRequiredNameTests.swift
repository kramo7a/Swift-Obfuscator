import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Language-required names

@Test func safetyAnalyzerAllowsTypeStoredPropertiesWithoutMemberwiseInitializerSupport() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("StoredProperties.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
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
    #expect(
        !structTypeProperty.reasons.contains(
            "stored property declarations require memberwise initializer label support"))

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
    #expect(
        !classTypeProperty.reasons.contains("stored property declarations require memberwise initializer label support")
    )
}

@Test func safetyAnalyzerDeniesPropertyWrapperRequiredNames() throws {
    let directory = try makeTemporaryDirectory()
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
    let directory = try makeTemporaryDirectory()
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
    let directory = try makeTemporaryDirectory()
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
