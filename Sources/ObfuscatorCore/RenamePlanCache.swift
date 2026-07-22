import CryptoKit
import Foundation

public struct RenamePlanCacheKey: Codable, Equatable, Sendable {
    public let toolSHA256: String
    public let sourceManifest: IndexSourceManifest
    public let obfuscationRoots: [String]
    public let inputMappingEntries: [MappingEntry]

    public static func make(
        toolURL: URL,
        sourceManifest: IndexSourceManifest,
        obfuscationRoots: [URL],
        mappingStore: MappingStore
    ) throws -> RenamePlanCacheKey {
        let toolData = try Data(contentsOf: toolURL, options: .mappedIfSafe)
        return RenamePlanCacheKey(
            toolSHA256: SHA256.hash(data: toolData).map { String(format: "%02x", $0) }.joined(),
            sourceManifest: sourceManifest,
            obfuscationRoots: obfuscationRoots
                .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
                .sorted(),
            inputMappingEntries: mappingStore.allEntries()
        )
    }
}

public struct CachedRenamePlan: Codable, Sendable {
    public let plan: RenamePlan
    public let outputMappingEntries: [MappingEntry]
    public let sourceFiles: [String]
    public let indexedSymbolCount: Int
    public let indexedOccurrenceCount: Int

    public init(
        plan: RenamePlan,
        outputMappingEntries: [MappingEntry],
        sourceFiles: [String],
        indexedSymbolCount: Int,
        indexedOccurrenceCount: Int
    ) {
        self.plan = plan
        self.outputMappingEntries = outputMappingEntries
        self.sourceFiles = sourceFiles
        self.indexedSymbolCount = indexedSymbolCount
        self.indexedOccurrenceCount = indexedOccurrenceCount
    }
}

public enum RenamePlanCache {
    public static let currentFormatVersion = 1

    public static func load(from url: URL, matching key: RenamePlanCacheKey) throws -> CachedRenamePlan? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let file = try PropertyListDecoder().decode(CacheFile.self, from: data)
        guard file.formatVersion == currentFormatVersion, file.key == key else {
            return nil
        }
        return file.value
    }

    public static func save(
        _ value: CachedRenamePlan,
        key: RenamePlanCacheKey,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(CacheFile(
            formatVersion: currentFormatVersion,
            key: key,
            value: value
        ))
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private struct CacheFile: Codable {
    let formatVersion: Int
    let key: RenamePlanCacheKey
    let value: CachedRenamePlan
}
