import CryptoKit
import Foundation

public struct IndexSourceManifest: Codable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let path: String
        public let sha256: String
    }

    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let entries: [Entry]

    public static func capture(sourceCache: SourceFileCache) throws -> IndexSourceManifest {
        let entries = try sourceCache.allPaths.map { path in
            guard let source = sourceCache.file(for: path) else {
                throw IndexSourceManifestError.sourceUnavailable(path)
            }
            return Entry(path: path, sha256: digest(source.data))
        }
        return IndexSourceManifest(formatVersion: currentFormatVersion, entries: entries)
    }

    public static func load(from url: URL) throws -> IndexSourceManifest {
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(IndexSourceManifest.self, from: data)
        guard manifest.formatVersion == currentFormatVersion else {
            throw IndexSourceManifestError.unsupportedFormat(manifest.formatVersion)
        }
        return manifest
    }

    public func save(to url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public func validate(sourceCache: SourceFileCache) throws {
        let currentPaths = sourceCache.allPaths
        let indexedPaths = entries.map(\.path)
        guard currentPaths == indexedPaths else {
            let current = Set(currentPaths)
            let indexed = Set(indexedPaths)
            throw IndexSourceManifestError.sourceSetChanged(
                added: current.subtracting(indexed).sorted(),
                removed: indexed.subtracting(current).sorted()
            )
        }

        for entry in entries {
            guard let source = sourceCache.file(for: entry.path) else {
                throw IndexSourceManifestError.sourceUnavailable(entry.path)
            }
            guard Self.digest(source.data) == entry.sha256 else {
                throw IndexSourceManifestError.sourceChanged(entry.path)
            }
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum IndexSourceManifestError: LocalizedError {
    case unsupportedFormat(Int)
    case sourceSetChanged(added: [String], removed: [String])
    case sourceChanged(String)
    case sourceUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let version):
            return "Unsupported index source manifest format version: \(version)"
        case .sourceSetChanged(let added, let removed):
            let addedDescription = added.isEmpty ? "none" : added.joined(separator: ", ")
            let removedDescription = removed.isEmpty ? "none" : removed.joined(separator: ", ")
            return "Swift source set changed since indexing (added: \(addedDescription); removed: \(removedDescription)). Run again without --reuse-index."
        case .sourceChanged(let path):
            return "Swift source changed since indexing: \(path). Run again without --reuse-index."
        case .sourceUnavailable(let path):
            return "Swift source is unavailable: \(path)"
        }
    }
}
