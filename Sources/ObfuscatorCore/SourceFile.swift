import Foundation

public final class SourceFileCache {
    private let fileManager: FileManager
    private var filesByCanonicalPath: [String: SourceFile] = [:]

    public init(paths: [String], fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        for path in paths {
            let sourceFile = try SourceFile(path: path, fileManager: fileManager)
            filesByCanonicalPath[SourcePathNormalizer.canonicalPath(path)] = sourceFile
        }
    }

    public func file(for path: String) -> SourceFile? {
        filesByCanonicalPath[SourcePathNormalizer.canonicalPath(path)]
    }

    public var allPaths: [String] {
        filesByCanonicalPath.values.map(\.path).sorted()
    }
}

public struct SourceFile: Sendable {
    public struct IdentifierToken: Sendable {
        public let name: String
        public let byteRange: Range<Int>
        public let isBackticked: Bool
    }

    public let path: String
    public let data: Data
    private let lineStarts: [Int]

    public init(path: String, fileManager: FileManager = .default) throws {
        let canonical = SourcePathNormalizer.canonicalPath(path)
        self.path = canonical
        self.data = try Data(contentsOf: URL(fileURLWithPath: canonical))
        self.lineStarts = Self.computeLineStarts(data)
    }

    public func byteOffset(line: Int, utf8Column: Int) -> Int? {
        guard line > 0, line <= lineStarts.count, utf8Column > 0 else {
            return nil
        }
        let offset = lineStarts[line - 1] + utf8Column - 1
        guard offset >= 0, offset <= data.count else {
            return nil
        }
        return offset
    }

    public func sourceLocation(atByteOffset byteOffset: Int) -> (
        line: Int,
        utf8Column: Int
    )? {
        guard byteOffset >= 0, byteOffset <= data.count else {
            return nil
        }
        var lowerBound = 0
        var upperBound = lineStarts.count
        while lowerBound + 1 < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if lineStarts[middle] <= byteOffset {
                lowerBound = middle
            } else {
                upperBound = middle
            }
        }
        return (
            line: lowerBound + 1,
            utf8Column: byteOffset - lineStarts[lowerBound] + 1
        )
    }

    public func identifierToken(line: Int, utf8Column: Int) -> IdentifierToken? {
        guard let offset = byteOffset(line: line, utf8Column: utf8Column) else {
            return nil
        }
        return identifierToken(atByteOffset: offset)
    }

    public func identifierToken(atByteOffset offset: Int) -> IdentifierToken? {
        let bytes = [UInt8](data)
        guard offset >= 0, offset < bytes.count else {
            return nil
        }

        if bytes[offset] == UInt8(ascii: "`") {
            var cursor = offset + 1
            while cursor < bytes.count, bytes[cursor] != UInt8(ascii: "`") {
                cursor += 1
            }
            guard cursor < bytes.count else {
                return nil
            }
            let name = String(decoding: data[(offset + 1)..<cursor], as: UTF8.self)
            return IdentifierToken(name: name, byteRange: (offset + 1)..<cursor, isBackticked: true)
        }

        guard isIdentifierBody(bytes[offset]) else {
            return nil
        }

        var start = offset
        while start > 0, isIdentifierBody(bytes[start - 1]) {
            start -= 1
        }
        guard isIdentifierHead(bytes[start]) else {
            return nil
        }

        var end = offset
        while end < bytes.count, isIdentifierBody(bytes[end]) {
            end += 1
        }

        let name = String(decoding: data[start..<end], as: UTF8.self)
        return IdentifierToken(name: name, byteRange: start..<end, isBackticked: false)
    }

    public func lineText(line: Int) -> String? {
        guard line > 0, line <= lineStarts.count else {
            return nil
        }
        let start = lineStarts[line - 1]
        let nextStart = line < lineStarts.count ? lineStarts[line] : data.count
        var end = nextStart
        while end > start, data[end - 1] == UInt8(ascii: "\n") || data[end - 1] == UInt8(ascii: "\r") {
            end -= 1
        }
        return String(decoding: data[start..<end], as: UTF8.self)
    }

    public func text(in byteRange: Range<Int>) -> String? {
        guard byteRange.lowerBound >= 0, byteRange.upperBound <= data.count else {
            return nil
        }
        return String(decoding: data[byteRange], as: UTF8.self)
    }

    private static func computeLineStarts(_ data: Data) -> [Int] {
        var starts = [0]
        for index in data.indices where data[index] == UInt8(ascii: "\n") {
            let next = index + 1
            if next < data.count {
                starts.append(next)
            }
        }
        return starts
    }
}

public func isPlainSwiftIdentifier(_ value: String) -> Bool {
    let bytes = [UInt8](value.utf8)
    guard let first = bytes.first, isIdentifierHead(first) else {
        return false
    }
    guard bytes.allSatisfy(isIdentifierBody) else {
        return false
    }
    return !SwiftKeywords.all.contains(value)
}

/// Returns whether `value` is an unescaped ASCII argument-label token.
///
/// Swift permits contextual use of keywords such as `for` and `in` as
/// argument labels. They are not plain declaration identifiers, but they are
/// still exact source tokens that can be renamed when declaration and use-site
/// labels are coordinated semantically.
public func isPlainSwiftArgumentLabel(_ value: String) -> Bool {
    let bytes = [UInt8](value.utf8)
    guard let first = bytes.first, isIdentifierHead(first) else {
        return false
    }
    return bytes.allSatisfy(isIdentifierBody)
}

private func isIdentifierHead(_ byte: UInt8) -> Bool {
    (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
        || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
        || byte == UInt8(ascii: "_")
}

private func isIdentifierBody(_ byte: UInt8) -> Bool {
    isIdentifierHead(byte) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
}

private enum SwiftKeywords {
    static let all: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
        "func", "import", "init", "inout", "internal", "let", "open", "operator",
        "private", "precedencegroup", "protocol", "public", "rethrows", "static",
        "struct", "subscript", "typealias", "var", "break", "case", "catch",
        "continue", "default", "defer", "do", "else", "fallthrough", "for",
        "guard", "if", "in", "repeat", "return", "throw", "switch", "where",
        "while", "as", "Any", "false", "is", "nil", "self", "Self", "super",
        "throws", "true", "try", "associativity", "convenience", "didSet",
        "dynamic", "final", "get", "infix", "indirect", "lazy", "left",
        "mutating", "none", "nonmutating", "optional", "override", "postfix",
        "precedence", "prefix", "Protocol", "required", "right", "set",
        "some", "Type", "unowned", "weak", "willSet", "_modify", "_read"
    ]
}
