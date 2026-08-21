import Foundation

public final class RenameMappingStore {
    public static let currentFormatVersion = 1

    public struct Entry: Codable, Hashable, Sendable {
        public let usr: String
        public let originalName: String
        public let obfuscatedName: String
        public let kind: String
    }

    public struct File: Codable, Sendable {
        public var version: Int
        public var generatedAt: String
        public var renames: [RenameMappingStore.Entry]

        private enum CodingKeys: String, CodingKey {
            case version
            case generatedAt
            case renames = "entries"
        }
    }

    private var renamesByUSR: [String: RenameMappingStore.Entry]

    public init(renames: [RenameMappingStore.Entry] = []) {
        self.renamesByUSR = Dictionary(uniqueKeysWithValues: renames.map { ($0.usr, $0) })
    }

    public static func load(
        from url: URL,
        fileManager: FileManager = .default
    ) throws -> RenameMappingStore {
        guard fileManager.fileExists(atPath: url.path) else {
            return RenameMappingStore()
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(RenameMappingStore.File.self, from: data)
        return RenameMappingStore(renames: file.renames)
    }

    public func rename(for usr: String) -> RenameMappingStore.Entry? {
        renamesByUSR[usr]
    }

    public func record(usr: String, originalName: String, obfuscatedName: String, kind: String) {
        renamesByUSR[usr] = RenameMappingStore.Entry(
            usr: usr,
            originalName: originalName,
            obfuscatedName: obfuscatedName,
            kind: kind
        )
    }

    public func allRenames() -> [RenameMappingStore.Entry] {
        renamesByUSR.values.sorted { ($0.originalName, $0.usr) < ($1.originalName, $1.usr) }
    }

    public func save(to url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = RenameMappingStore.File(
            version: Self.currentFormatVersion,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            renames: allRenames()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }
}
