import Foundation

public final class SourcePatcher {
    public struct Edit: Codable, Hashable, Sendable {
        public let path: String
        public let byteOffset: Int
        public let length: Int
        public let line: Int
        public let utf8Column: Int
        public let oldName: String
        public let newName: String
        public let usr: String
    }

    public enum Error: LocalizedError {
        case invalidRange(SourcePatcher.Edit)
        case validationFailed(SourcePatcher.Edit, found: String)
        case sourceFileOutsideRoot(String, root: URL)

        public var errorDescription: String? {
            switch self {
            case .invalidRange(let edit):
                return "Invalid replacement range in \(edit.path):\(edit.line):\(edit.utf8Column)"
            case .validationFailed(let edit, let found):
                return
                    "Patch validation failed in \(edit.path):\(edit.line):\(edit.utf8Column): expected \(edit.oldName), found \(found)"
            case .sourceFileOutsideRoot(let path, let root):
                return "Source file is outside source root: \(path) (root: \(root.path))"
            }
        }
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func apply(_ edits: [SourcePatcher.Edit]) throws {
        let editsByPath = Dictionary(grouping: edits) {
            SourcePathNormalizer.canonicalPath($0.path)
        }
        for (path, fileEdits) in editsByPath {
            var data = try Data(contentsOf: URL(fileURLWithPath: path))
            try apply(fileEdits, to: &data)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    public func writePatchedCopies(
        sourceFiles: [String],
        edits: [SourcePatcher.Edit],
        sourceRoot: URL,
        outputRoot: URL
    ) throws -> [URL] {
        let sourceRoot = sourceRoot.standardizedFileURL
        let outputRoot = outputRoot.standardizedFileURL
        let editsByPath = Dictionary(grouping: edits) {
            SourcePathNormalizer.canonicalPath($0.path)
        }
        let sourcePathsToWrite = Set(sourceFiles.map(SourcePathNormalizer.canonicalPath))
            .union(editsByPath.keys)
        var writtenFiles: [URL] = []

        for sourcePath in sourcePathsToWrite.sorted() {
            var data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
            if let fileEdits = editsByPath[sourcePath] {
                try apply(fileEdits, to: &data)
            }

            let outputURL = try outputURL(
                forSourcePath: sourcePath, sourceRoot: sourceRoot, outputRoot: outputRoot)
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outputURL, options: .atomic)
            writtenFiles.append(outputURL)
        }

        return writtenFiles
    }

    public func validate(_ edits: [SourcePatcher.Edit]) throws {
        let editsByPath = Dictionary(grouping: edits) {
            SourcePathNormalizer.canonicalPath($0.path)
        }
        for (path, fileEdits) in editsByPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            for edit in fileEdits {
                let range = edit.byteOffset..<(edit.byteOffset + edit.length)
                guard range.lowerBound >= 0, range.upperBound <= data.count else {
                    throw SourcePatcher.Error.invalidRange(edit)
                }
                let found = String(decoding: data[range], as: UTF8.self)
                guard found == edit.oldName else {
                    throw SourcePatcher.Error.validationFailed(edit, found: found)
                }
            }
        }
    }

    private func apply(_ edits: [SourcePatcher.Edit], to data: inout Data) throws {
        for edit in edits.sorted(by: { $0.byteOffset > $1.byteOffset }) {
            let range = edit.byteOffset..<(edit.byteOffset + edit.length)
            guard range.lowerBound >= 0, range.upperBound <= data.count else {
                throw SourcePatcher.Error.invalidRange(edit)
            }

            let found = String(decoding: data[range], as: UTF8.self)
            guard found == edit.oldName else {
                throw SourcePatcher.Error.validationFailed(edit, found: found)
            }
            data.replaceSubrange(range, with: Data(edit.newName.utf8))
        }
    }

    private func outputURL(forSourcePath sourcePath: String, sourceRoot: URL, outputRoot: URL)
        throws -> URL
    {
        let sourceRootPath = Self.normalizedPath(sourceRoot)
        let sourcePath = Self.normalizedPath(URL(fileURLWithPath: sourcePath))
        guard sourcePath == sourceRootPath || sourcePath.hasPrefix(sourceRootPath + "/") else {
            throw SourcePatcher.Error.sourceFileOutsideRoot(sourcePath, root: sourceRoot)
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
