import Foundation

public struct SourceReplacement: Codable, Hashable, Sendable {
    public let path: String
    public let byteOffset: Int
    public let length: Int
    public let line: Int
    public let utf8Column: Int
    public let oldName: String
    public let newName: String
    public let usr: String
}

public enum SourcePatcherError: LocalizedError {
    case invalidRange(SourceReplacement)
    case validationFailed(SourceReplacement, found: String)
    case sourceFileOutsideRoot(String, root: URL)

    public var errorDescription: String? {
        switch self {
        case .invalidRange(let replacement):
            return "Invalid replacement range in \(replacement.path):\(replacement.line):\(replacement.utf8Column)"
        case .validationFailed(let replacement, let found):
            return "Patch validation failed in \(replacement.path):\(replacement.line):\(replacement.utf8Column): expected \(replacement.oldName), found \(found)"
        case .sourceFileOutsideRoot(let path, let root):
            return "Source file is outside source root: \(path) (root: \(root.path))"
        }
    }
}

public final class SourcePatcher {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func apply(_ replacements: [SourceReplacement]) throws {
        let grouped = Dictionary(grouping: replacements) { SourcePathNormalizer.canonicalPath($0.path) }
        for (path, replacements) in grouped {
            var data = try Data(contentsOf: URL(fileURLWithPath: path))
            try apply(replacements, to: &data)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    public func writePatchedCopies(
        sourceFiles: [String],
        replacements: [SourceReplacement],
        sourceRoot: URL,
        outputRoot: URL
    ) throws -> [URL] {
        let sourceRoot = sourceRoot.standardizedFileURL
        let outputRoot = outputRoot.standardizedFileURL
        let grouped = Dictionary(grouping: replacements) { SourcePathNormalizer.canonicalPath($0.path) }
        let sourcePathsToWrite = Set(sourceFiles.map(SourcePathNormalizer.canonicalPath))
            .union(grouped.keys)
        var writtenFiles: [URL] = []

        for sourcePath in sourcePathsToWrite.sorted() {
            var data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
            if let replacements = grouped[sourcePath] {
                try apply(replacements, to: &data)
            }

            let outputURL = try outputURL(forSourcePath: sourcePath, sourceRoot: sourceRoot, outputRoot: outputRoot)
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outputURL, options: .atomic)
            writtenFiles.append(outputURL)
        }

        return writtenFiles
    }

    public func validate(_ replacements: [SourceReplacement]) throws {
        let grouped = Dictionary(grouping: replacements) { SourcePathNormalizer.canonicalPath($0.path) }
        for (path, replacements) in grouped {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            for replacement in replacements {
                let range = replacement.byteOffset..<(replacement.byteOffset + replacement.length)
                guard range.lowerBound >= 0, range.upperBound <= data.count else {
                    throw SourcePatcherError.invalidRange(replacement)
                }
                let found = String(decoding: data[range], as: UTF8.self)
                guard found == replacement.oldName else {
                    throw SourcePatcherError.validationFailed(replacement, found: found)
                }
            }
        }
    }

    private func apply(_ replacements: [SourceReplacement], to data: inout Data) throws {
        for replacement in replacements.sorted(by: { $0.byteOffset > $1.byteOffset }) {
            let range = replacement.byteOffset..<(replacement.byteOffset + replacement.length)
            guard range.lowerBound >= 0, range.upperBound <= data.count else {
                throw SourcePatcherError.invalidRange(replacement)
            }

            let found = String(decoding: data[range], as: UTF8.self)
            guard found == replacement.oldName else {
                throw SourcePatcherError.validationFailed(replacement, found: found)
            }
            data.replaceSubrange(range, with: Data(replacement.newName.utf8))
        }
    }

    private func outputURL(forSourcePath sourcePath: String, sourceRoot: URL, outputRoot: URL) throws -> URL {
        let sourceRootPath = Self.normalizedPath(sourceRoot)
        let sourcePath = Self.normalizedPath(URL(fileURLWithPath: sourcePath))
        guard sourcePath == sourceRootPath || sourcePath.hasPrefix(sourceRootPath + "/") else {
            throw SourcePatcherError.sourceFileOutsideRoot(sourcePath, root: sourceRoot)
        }
        if sourcePath == sourceRootPath {
            return outputRoot
        }

        let relativePath = String(sourcePath.dropFirst(sourceRootPath.count + 1))
        return relativePath.split(separator: "/").reduce(outputRoot) { partial, component in
            partial.appendingPathComponent(String(component))
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
