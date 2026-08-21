import CryptoKit
import Foundation

public enum RenamePlanCache {
    public static let currentFormatVersion = 1

    public struct Key: Codable, Equatable, Sendable {
        public let toolSHA256: String
        public let sourceManifest: IndexSourceManifest
        public let obfuscationRoots: [String]
        public let inputRenames: [RenameMappingStore.Entry]

        public init(
            toolSHA256: String,
            sourceManifest: IndexSourceManifest,
            obfuscationRoots: [String],
            inputRenames: [RenameMappingStore.Entry]
        ) {
            self.toolSHA256 = toolSHA256
            self.sourceManifest = sourceManifest
            self.obfuscationRoots = obfuscationRoots
            self.inputRenames = inputRenames
        }

        public static func make(
            toolURL: URL,
            sourceManifest: IndexSourceManifest,
            obfuscationRoots: [URL],
            mappingStore: RenameMappingStore
        ) throws -> RenamePlanCache.Key {
            let toolData = try Data(contentsOf: toolURL, options: .mappedIfSafe)
            return RenamePlanCache.Key(
                toolSHA256: SHA256.hash(data: toolData)
                    .map { String(format: "%02x", $0) }
                    .joined(),
                sourceManifest: sourceManifest,
                obfuscationRoots: obfuscationRoots
                    .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
                    .sorted(),
                inputRenames: mappingStore.allRenames()
            )
        }

        private enum CodingKeys: String, CodingKey {
            case toolSHA256
            case sourceManifest
            case obfuscationRoots
            case inputRenames = "inputMappingEntries"
        }
    }

    public struct Value: Codable, Sendable {
        public let plan: RenamePlan
        public let outputRenames: [RenameMappingStore.Entry]
        public let sourceFiles: [String]
        public let indexedSymbolCount: Int
        public let indexedOccurrenceCount: Int

        public init(
            plan: RenamePlan,
            outputRenames: [RenameMappingStore.Entry],
            sourceFiles: [String],
            indexedSymbolCount: Int,
            indexedOccurrenceCount: Int
        ) {
            self.plan = plan
            self.outputRenames = outputRenames
            self.sourceFiles = sourceFiles
            self.indexedSymbolCount = indexedSymbolCount
            self.indexedOccurrenceCount = indexedOccurrenceCount
        }

        private enum CodingKeys: String, CodingKey {
            case plan
            case outputRenames = "outputMappingEntries"
            case sourceFiles
            case indexedSymbolCount
            case indexedOccurrenceCount
        }
    }

    public static func load(
        from url: URL,
        matching key: RenamePlanCache.Key
    ) throws -> RenamePlanCache.Value? {
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
        _ value: RenamePlanCache.Value,
        key: RenamePlanCache.Key,
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
    let key: RenamePlanCache.Key
    let value: RenamePlanCache.Value
}
