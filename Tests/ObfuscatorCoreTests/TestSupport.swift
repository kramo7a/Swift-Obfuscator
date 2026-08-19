import Foundation

@testable import ObfuscatorCore

// MARK: - Test support

enum SwiftFixtureError: Error, CustomStringConvertible {
    case missingResourceDirectory
    case missingResource(URL)

    var description: String {
        switch self {
        case .missingResourceDirectory:
            return "The ObfuscatorCoreTests resource directory is unavailable"
        case let .missingResource(expectedURL):
            return "Missing Swift fixture at '\(expectedURL.path)'"
        }
    }
}

func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SwiftObfuscatorTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func copyFixture(
    to destination: URL,
    testFilePath: StaticString = #filePath,
    testFunction: StaticString = #function
) throws {
    guard let resourceDirectory = Bundle.module.resourceURL else {
        throw SwiftFixtureError.missingResourceDirectory
    }
    let testFileName = URL(fileURLWithPath: String(describing: testFilePath))
        .deletingPathExtension()
        .lastPathComponent
    let functionName = String(describing: testFunction).prefix { $0 != "(" }
    let source = resourceDirectory
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent(testFileName, isDirectory: true)
        .appendingPathComponent(String(functionName), isDirectory: true)
        .appendingPathComponent(destination.lastPathComponent)
    guard FileManager.default.fileExists(atPath: source.path) else {
        throw SwiftFixtureError.missingResource(source)
    }

    try FileManager.default.copyItem(at: source, to: destination)
}

func utf8Column(of needle: String, in line: String) -> Int {
    guard let range = line.range(of: needle) else {
        preconditionFailure("Fixture token '\(needle)' is missing from line '\(line)'")
    }
    return line[..<range.lowerBound].utf8.count + 1
}

func fixtureLines(at path: String) -> [String] {
    let source: String
    do {
        source = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    } catch {
        preconditionFailure("Unable to read test fixture at '\(path)': \(error)")
    }
    return source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

func fixtureLines(at url: URL) -> [String] {
    fixtureLines(at: url.path)
}

func fixtureLine(at path: String, line: Int) -> String {
    let sourceLines = fixtureLines(at: path)
    guard sourceLines.indices.contains(line - 1) else {
        preconditionFailure("Fixture line \(line) is outside '\(path)'")
    }
    return sourceLines[line - 1]
}

func fixtureLine(at url: URL, line: Int) -> String {
    fixtureLine(at: url.path, line: line)
}

func testSymbol(
    _ usr: String,
    _ name: String,
    _ kind: IndexSymbolKind = .parameter,
    language: String = "swift",
    propertiesRaw: UInt64 = 0
) -> SymbolRecord {
    SymbolRecord(
        usr: usr,
        name: name,
        kind: kind.rawValue,
        language: language,
        propertiesRaw: propertiesRaw,
        properties: propertiesRaw == 0 ? "[]" : "[indexed]"
    )
}

func testRelation(_ symbol: SymbolRecord, _ roles: [IndexRole]) -> RelationRecord {
    RelationRecord(
        usr: symbol.usr,
        name: symbol.name,
        rolesRaw: 0,
        roles: roles.map(\.rawValue)
    )
}

func testRelation(_ symbol: SymbolRecord, _ role: IndexRole) -> RelationRecord {
    testRelation(symbol, [role])
}

func testRelation(_ symbol: SymbolRecord, role: IndexRole) -> RelationRecord {
    testRelation(symbol, role)
}

func childOf(_ owner: SymbolRecord) -> RelationRecord {
    testRelation(owner, .childOf)
}

func baseOf(_ owner: SymbolRecord) -> RelationRecord {
    testRelation(owner, .baseOf)
}

func testOccurrence(
    _ symbol: SymbolRecord,
    path: String,
    line: Int,
    token: String,
    roles: [IndexRole],
    relations: [RelationRecord] = []
) -> OccurrenceRecord {
    let sourceLine = fixtureLine(at: path, line: line)
    let rawRoles = roles.map(\.rawValue)
    return OccurrenceRecord(
        symbol: symbol,
        path: path,
        line: line,
        utf8Column: utf8Column(of: token, in: sourceLine),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 0,
        roles: rawRoles,
        rolesDescription: rawRoles.joined(separator: ","),
        symbolProvider: "swift",
        relations: relations
    )
}
