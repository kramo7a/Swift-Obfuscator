import Foundation
import IndexStoreDB

public enum IndexReaderError: LocalizedError {
    case missingIndexStore(URL)
    case missingIndexStoreLibrary

    public var errorDescription: String? {
        switch self {
        case .missingIndexStore(let url):
            return "Index store does not exist at \(url.path). Make sure xcodebuild completed with COMPILER_INDEX_STORE_ENABLE=YES."
        case .missingIndexStoreLibrary:
            return "Could not locate libIndexStore.dylib in the active Xcode toolchain."
        }
    }
}

public final class IndexReader {
    private let runner: CommandRunner
    private let fileManager: FileManager

    public init(runner: CommandRunner = CommandRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func read(
        storePath: URL,
        databasePath: URL,
        sourceRoot: URL,
        excludedSourceRoots: [URL] = []
    ) throws -> IndexSnapshot {
        guard fileManager.fileExists(atPath: storePath.path) else {
            throw IndexReaderError.missingIndexStore(storePath)
        }

        try fileManager.createDirectory(at: databasePath, withIntermediateDirectories: true)
        let libraryPath = try locateIndexStoreLibrary()
        let library = try IndexStoreLibrary(dylibPath: libraryPath.path)
        let database = try IndexStoreDB(
            storePath: storePath.path,
            databasePath: databasePath.path,
            library: library,
            waitUntilDoneInitializing: true
        )
        database.pollForUnitChangesAndWait(isInitialScan: true)

        let swiftFiles = try SourceFileFinder.swiftFiles(
            in: sourceRoot,
            excluding: excludedSourceRoots,
            fileManager: fileManager
        )
        var symbolsByUSR: [String: SymbolRecord] = [:]
        var occurrences: Set<OccurrenceRecord> = []

        for file in swiftFiles {
            for candidate in SourcePathNormalizer.indexPathCandidates(for: file) {
                let fileSymbols = database.symbols(inFilePath: candidate)
                let fileOccurrences = database.symbolOccurrences(inFilePath: candidate)
                if fileSymbols.isEmpty && fileOccurrences.isEmpty {
                    continue
                }

                for symbol in fileSymbols {
                    symbolsByUSR[symbol.usr] = SymbolRecord(symbol)
                }
                for occurrence in fileOccurrences {
                    let record = OccurrenceRecord(occurrence)
                    symbolsByUSR[record.symbol.usr] = record.symbol
                    occurrences.insert(record)
                }
            }
        }

        return IndexSnapshot(
            sourceFiles: swiftFiles.map(\.path).sorted(),
            symbols: symbolsByUSR.values.sorted { ($0.name, $0.usr) < ($1.name, $1.usr) },
            occurrences: occurrences.sorted { lhs, rhs in
                (lhs.path, lhs.line, lhs.utf8Column, lhs.usr, lhs.rolesRaw) < (rhs.path, rhs.line, rhs.utf8Column, rhs.usr, rhs.rolesRaw)
            }
        )
    }

    private func locateIndexStoreLibrary() throws -> URL {
        if let swiftPath = try? runner.run(executable: "/usr/bin/xcrun", arguments: ["--find", "swift"]).stdout.trimmedNonEmpty {
            let swiftURL = URL(fileURLWithPath: swiftPath)
            let library = swiftURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("lib/libIndexStore.dylib")
            if fileManager.fileExists(atPath: library.path) {
                return library
            }
        }

        let fallback = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib")
        if fileManager.fileExists(atPath: fallback.path) {
            return fallback
        }

        throw IndexReaderError.missingIndexStoreLibrary
    }
}

public enum SourceFileFinder {
    public static func swiftFiles(
        in root: URL,
        excluding excludedRoots: [URL] = [],
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let root = root.standardizedFileURL
        let excludedRoots = excludedRoots.map { $0.standardizedFileURL }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory, shouldSkipDirectory(name) || isExcludedDirectory(url, excludedRoots: excludedRoots) {
                enumerator.skipDescendants()
                continue
            }

            guard url.pathExtension == "swift" else {
                continue
            }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(url.standardizedFileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func shouldSkipDirectory(_ name: String) -> Bool {
        [".git", ".build", ".swiftpm", ".obfuscator", "Derived", "DerivedData", "Index.noindex"].contains(name)
    }

    private static func isExcludedDirectory(_ url: URL, excludedRoots: [URL]) -> Bool {
        let path = normalizedPath(url)
        return excludedRoots.contains { excludedRoot in
            let excludedPath = normalizedPath(excludedRoot)
            return path == excludedPath || path.hasPrefix(excludedPath + "/")
        }
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path.count > 1, path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }
}

public enum SourcePathNormalizer {
    public static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func indexPathCandidates(for url: URL) -> [String] {
        let absolute = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        var candidates: [String] = [absolute, resolved]

        if resolved.hasPrefix("/private/tmp/") {
            candidates.append("/tmp/" + resolved.dropFirst("/private/tmp/".count))
        }
        if absolute.hasPrefix("/private/tmp/") {
            candidates.append("/tmp/" + absolute.dropFirst("/private/tmp/".count))
        }

        var unique: [String] = []
        for candidate in candidates where !unique.contains(candidate) {
            unique.append(candidate)
        }
        return unique
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
