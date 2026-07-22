import Foundation

public struct MappingEntry: Codable, Hashable, Sendable {
    public let usr: String
    public let originalName: String
    public let obfuscatedName: String
    public let kind: String
}

public struct MappingFile: Codable, Sendable {
    public var version: Int
    public var generatedAt: String
    public var entries: [MappingEntry]
}

public final class MappingStore {
    private var entriesByUSR: [String: MappingEntry]

    public init(entries: [MappingEntry] = []) {
        self.entriesByUSR = Dictionary(uniqueKeysWithValues: entries.map { ($0.usr, $0) })
    }

    public static func load(from url: URL, fileManager: FileManager = .default) throws -> MappingStore {
        guard fileManager.fileExists(atPath: url.path) else {
            return MappingStore()
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(MappingFile.self, from: data)
        return MappingStore(entries: file.entries)
    }

    public func entry(for usr: String) -> MappingEntry? {
        entriesByUSR[usr]
    }

    public func record(usr: String, originalName: String, obfuscatedName: String, kind: String) {
        entriesByUSR[usr] = MappingEntry(
            usr: usr,
            originalName: originalName,
            obfuscatedName: obfuscatedName,
            kind: kind
        )
    }

    public func allEntries() -> [MappingEntry] {
        entriesByUSR.values.sorted { ($0.originalName, $0.usr) < ($1.originalName, $1.usr) }
    }

    public func save(to url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = MappingFile(
            version: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            entries: allEntries()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }
}
