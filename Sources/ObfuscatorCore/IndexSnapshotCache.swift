import Foundation

public enum IndexSnapshotCache {
    public static let currentFormatVersion = 1

    public enum Error: LocalizedError {
        case unsupportedFormat(Int)
        case sourceManifestMismatch
        case invalidPathIndex(Int)
        case invalidSymbolIndex(Int)
        case missingSymbol(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let version):
                return "Unsupported index snapshot cache format version: \(version)"
            case .sourceManifestMismatch:
                return "Index snapshot cache does not match the validated source manifest. Run again without --reuse-index."
            case .invalidPathIndex(let index):
                return "Index snapshot cache contains an invalid path index: \(index)"
            case .invalidSymbolIndex(let index):
                return "Index snapshot cache contains an invalid symbol index: \(index)"
            case .missingSymbol(let usr):
                return "Index snapshot cache cannot find symbol for USR: \(usr)"
            }
        }
    }

    public static func save(
        snapshot: IndexSnapshot,
        sourceManifest: IndexSourceManifest,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        let file = try CacheFile(snapshot: snapshot, sourceManifest: sourceManifest)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(file)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public static func load(
        from url: URL,
        sourceManifest: IndexSourceManifest
    ) throws -> IndexSnapshot {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let file = try PropertyListDecoder().decode(CacheFile.self, from: data)
        guard file.formatVersion == currentFormatVersion else {
            throw IndexSnapshotCache.Error.unsupportedFormat(file.formatVersion)
        }
        guard file.sourceManifest == sourceManifest else {
            throw IndexSnapshotCache.Error.sourceManifestMismatch
        }
        return try file.snapshot()
    }
}

private struct CacheFile: Codable {
    let formatVersion: Int
    let sourceManifest: IndexSourceManifest
    let paths: [String]
    let sourceFilePathIndices: [Int]
    let symbols: [IndexSnapshot.Symbol]
    let occurrences: [CachedOccurrence]

    init(snapshot: IndexSnapshot, sourceManifest: IndexSourceManifest) throws {
        formatVersion = IndexSnapshotCache.currentFormatVersion
        self.sourceManifest = sourceManifest

        paths = Array(Set(snapshot.sourceFiles + snapshot.occurrences.map(\.path))).sorted()
        let pathIndices = Dictionary(uniqueKeysWithValues: paths.enumerated().map { ($1, $0) })
        sourceFilePathIndices = try snapshot.sourceFiles.map { path in
            guard let index = pathIndices[path] else {
                throw IndexSnapshotCache.Error.invalidPathIndex(-1)
            }
            return index
        }

        symbols = snapshot.symbols
        let symbolIndices = Dictionary(uniqueKeysWithValues: symbols.enumerated().map { ($1.usr, $0) })
        occurrences = try snapshot.occurrences.map { occurrence in
            guard let pathIndex = pathIndices[occurrence.path] else {
                throw IndexSnapshotCache.Error.invalidPathIndex(-1)
            }
            guard let symbolIndex = symbolIndices[occurrence.usr] else {
                throw IndexSnapshotCache.Error.missingSymbol(occurrence.usr)
            }
            return CachedOccurrence(
                symbolIndex: symbolIndex,
                pathIndex: pathIndex,
                line: occurrence.line,
                utf8Column: occurrence.utf8Column,
                moduleName: occurrence.moduleName,
                isSystem: occurrence.isSystem,
                rolesRaw: occurrence.rolesRaw,
                roles: occurrence.roles,
                rolesDescription: occurrence.rolesDescription,
                symbolProvider: occurrence.symbolProvider,
                relations: occurrence.relations
            )
        }
    }

    func snapshot() throws -> IndexSnapshot {
        let sourceFiles = try sourceFilePathIndices.map(path(at:))
        let occurrences = try occurrences.map { cached in
            guard symbols.indices.contains(cached.symbolIndex) else {
                throw IndexSnapshotCache.Error.invalidSymbolIndex(cached.symbolIndex)
            }
            return IndexSnapshot.Occurrence(
                symbol: symbols[cached.symbolIndex],
                path: try path(at: cached.pathIndex),
                line: cached.line,
                utf8Column: cached.utf8Column,
                moduleName: cached.moduleName,
                isSystem: cached.isSystem,
                rolesRaw: cached.rolesRaw,
                roles: cached.roles,
                rolesDescription: cached.rolesDescription,
                symbolProvider: cached.symbolProvider,
                relations: cached.relations
            )
        }
        return IndexSnapshot(sourceFiles: sourceFiles, symbols: symbols, occurrences: occurrences)
    }

    private func path(at index: Int) throws -> String {
        guard paths.indices.contains(index) else {
            throw IndexSnapshotCache.Error.invalidPathIndex(index)
        }
        return paths[index]
    }
}

private struct CachedOccurrence: Codable {
    let symbolIndex: Int
    let pathIndex: Int
    let line: Int
    let utf8Column: Int
    let moduleName: String
    let isSystem: Bool
    let rolesRaw: UInt64
    let roles: [String]
    let rolesDescription: String
    let symbolProvider: String
    let relations: [IndexSnapshot.Relation]
}
