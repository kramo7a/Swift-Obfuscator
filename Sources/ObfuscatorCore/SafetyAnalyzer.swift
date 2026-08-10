import Foundation

public struct SafetyDecision: Codable, Sendable {
    public let usr: String
    public let symbolName: String
    public let kind: String
    public let allowed: Bool
    public let oldName: String?
    public let reasons: [String]
}

public struct SafetyAnalyzer: Sendable {
    public static let defaultAllowedKinds: Set<String> = [
        "class",
        "struct",
        "enum",
        "protocol",
        "typealias",
        "function",
        "instanceMethod",
        "staticMethod",
        "classMethod",
        "instanceProperty",
        "staticProperty",
        "classProperty",
        "variable"
    ]

    public let sourceRoot: URL
    public let obfuscationRoots: [URL]
    public let allowedKinds: Set<String>
    private let interfaceBuilderClassNames: Set<String>
    private let declarationContextCache: DeclarationContextCache

    public init(
        sourceRoot: URL,
        obfuscationRoots: [URL] = [],
        allowedKinds: Set<String> = SafetyAnalyzer.defaultAllowedKinds
    ) {
        let canonicalSourceRoot = sourceRoot.resolvingSymlinksInPath().standardizedFileURL
        self.sourceRoot = canonicalSourceRoot
        self.obfuscationRoots = obfuscationRoots.isEmpty
            ? [canonicalSourceRoot]
            : obfuscationRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.allowedKinds = allowedKinds
        self.interfaceBuilderClassNames = Self.discoverInterfaceBuilderClassNames(under: canonicalSourceRoot)
        self.declarationContextCache = DeclarationContextCache()
    }

    public func analyze(
        group: USROccurrenceGroup,
        sourceCache: SourceFileCache,
        localNominalTypeNames: Set<String> = [],
        overrideRelatedUSRs: Set<String> = [],
        tupleTypealiasRelatedUSRs: Set<String> = []
    ) -> SafetyDecision {
        var reasons: [String] = []
        var tokenNames: Set<String> = []
        var hasDeclarationOrDefinition = false
        var hasSelectedDeclarationOrDefinition = false

        if group.usr.isEmpty {
            reasons.append("empty USR")
        }
        if group.usr.hasPrefix("c:") {
            reasons.append("Objective-C-compatible USR requires a stable runtime name")
        }
        if !allowedKinds.contains(group.symbol.kind) {
            reasons.append("unsupported symbol kind \(group.symbol.kind)")
        }
        if group.occurrences.isEmpty {
            reasons.append("no occurrences")
        }
        if overrideRelatedUSRs.contains(group.usr) {
            reasons.append("override relations require coordinated renaming")
        }
        if tupleTypealiasRelatedUSRs.contains(group.usr) {
            reasons.append("tuple typealias constructor occurrences are incomplete")
        }

        for occurrence in group.occurrences {
            if occurrence.isSystem {
                reasons.append("system occurrence at \(occurrence.path):\(occurrence.line)")
            }
            if !isUnderSourceRoot(occurrence.path) {
                reasons.append("occurrence outside source root at \(occurrence.path):\(occurrence.line)")
            }
            if occurrence.roles.contains("implicit") {
                reasons.append("implicit occurrence at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)")
            }
            if occurrence.roles.contains("declaration") || occurrence.roles.contains("definition") {
                hasDeclarationOrDefinition = true
                if isUnderObfuscationRoots(occurrence.path) {
                    hasSelectedDeclarationOrDefinition = true
                }
            }
            if occurrence.relations.contains(where: { hasUnsafeRelation($0, symbolKind: group.symbol.kind) }) {
                reasons.append("unsafe relation at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)")
            }

            guard let source = sourceCache.file(for: occurrence.path) else {
                reasons.append("source file unavailable for \(occurrence.path)")
                continue
            }
            guard let token = source.identifierToken(line: occurrence.line, utf8Column: occurrence.utf8Column) else {
                reasons.append("identifier token unavailable at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)")
                continue
            }
            if token.isBackticked {
                reasons.append("backticked identifier \(token.name)")
            }
            if !isPlainSwiftIdentifier(token.name) {
                reasons.append("non-plain identifier \(token.name)")
            }
            tokenNames.insert(token.name)

            if occurrence.roles.contains("declaration") || occurrence.roles.contains("definition") {
                let contexts = declarationContexts(source: source, beforeByteOffset: token.byteRange.lowerBound)
                if group.symbol.kind != "protocol", contexts.contains(.protocolBody) {
                    reasons.append("protocol members require relation-aware witness renaming")
                }
                if group.symbol.kind == "typealias",
                   declarationLineLooksGenericTypeParameter(source: source, occurrence: occurrence, token: token) {
                    reasons.append("generic type parameter occurrences are incomplete")
                }
                if contexts.contains(where: { isExternalExtensionContext($0, localNominalTypeNames: localNominalTypeNames) }) {
                    reasons.append("extensions on external Swift or Objective-C owners are not self-contained")
                }
                if isLanguageRequiredDeclarationName(token.name) {
                    reasons.append("language-required declaration name \(token.name)")
                }
                if group.symbol.kind == "class", interfaceBuilderClassNames.contains(token.name) {
                    reasons.append("Interface Builder resource requires stable class name \(token.name)")
                }
                if storedPropertyRequiresMemberwiseInitializerSupport(group.symbol.kind),
                   declarationLineLooksStoredProperty(source: source, occurrence: occurrence, token: token) {
                    reasons.append("stored property declarations require memberwise initializer label support")
                }
                if contexts.contains(.objectiveCRuntimeBody)
                    || declarationRequiresStableRuntimeName(source: source, occurrence: occurrence, token: token) {
                    reasons.append("runtime-reflected or externally linked declaration at \(occurrence.path):\(occurrence.line)")
                }
            }
        }

        if !hasDeclarationOrDefinition {
            reasons.append("no declaration or definition occurrence")
        }
        if !hasSelectedDeclarationOrDefinition {
            reasons.append("no declaration or definition occurrence inside selected source roots")
        }
        if tokenNames.count > 1 {
            reasons.append("occurrences resolve to multiple source tokens: \(tokenNames.sorted().joined(separator: ", "))")
        }

        let oldName = tokenNames.count == 1 ? tokenNames.first : nil
        return SafetyDecision(
            usr: group.usr,
            symbolName: group.symbol.name,
            kind: group.symbol.kind,
            allowed: reasons.isEmpty && oldName != nil,
            oldName: oldName,
            reasons: reasons.isEmpty ? ["allowed by local deny-by-default checks"] : Array(Set(reasons)).sorted()
        )
    }

    private func isUnderSourceRoot(_ path: String) -> Bool {
        let canonicalPath = SourcePathNormalizer.canonicalPath(path)
        let rootPath = sourceRoot.path
        return canonicalPath == rootPath || canonicalPath.hasPrefix(rootPath + "/")
    }

    private func isUnderObfuscationRoots(_ path: String) -> Bool {
        let canonicalPath = SourcePathNormalizer.canonicalPath(path)
        return obfuscationRoots.contains { root in
            let rootPath = root.path
            return canonicalPath == rootPath || canonicalPath.hasPrefix(rootPath + "/")
        }
    }

    private func hasUnsafeRelation(_ relation: RelationRecord, symbolKind: String) -> Bool {
        relation.roles.contains("overrideOf")
            || (symbolKind != "protocol" && relation.roles.contains("baseOf"))
            || relation.roles.contains("specializationOf")
            || relation.roles.contains("ibTypeOf")
    }

    private func isLanguageRequiredDeclarationName(_ name: String) -> Bool {
        let names: Set<String> = [
            "wrappedValue",
            "projectedValue",
            "appendInterpolation",
            "buildBlock",
            "buildPartialBlock",
            "buildExpression",
            "buildEither",
            "buildArray",
            "buildOptional",
            "buildLimitedAvailability",
            "buildFinalResult"
        ]
        return names.contains(name)
    }

    private func storedPropertyRequiresMemberwiseInitializerSupport(_ kind: String) -> Bool {
        // IndexStore's property kinds already encode owner-aware dispatch:
        // `staticProperty` and `classProperty` are type members and never form
        // labels in a synthesized instance memberwise initializer.
        kind == "instanceProperty"
    }

    private func declarationLineLooksStoredProperty(
        source: SourceFile,
        occurrence: OccurrenceRecord,
        token: IdentifierToken
    ) -> Bool {
        guard let line = source.lineText(line: occurrence.line) else {
            return true
        }
        guard let tokenRange = line.range(of: token.name) else {
            return true
        }
        return !line[tokenRange.upperBound...].contains("{")
    }

    private func declarationLineLooksGenericTypeParameter(
        source: SourceFile,
        occurrence: OccurrenceRecord,
        token: IdentifierToken
    ) -> Bool {
        guard let line = source.lineText(line: occurrence.line),
              let tokenRange = line.range(of: token.name) else {
            return false
        }

        let before = line[..<tokenRange.lowerBound]
        let after = line[tokenRange.upperBound...]
        let declarationKeywords = ["class", "struct", "enum", "protocol", "func"]
        return before.contains("<")
            && after.contains(">")
            && declarationKeywords.contains { containsSwiftWord(String(before), word: $0) }
    }

    private func declarationRequiresStableRuntimeName(
        source: SourceFile,
        occurrence: OccurrenceRecord,
        token: IdentifierToken
    ) -> Bool {
        guard let line = source.lineText(line: occurrence.line),
              let tokenRange = line.range(of: token.name) else {
            return true
        }

        let beforeName = line[..<tokenRange.lowerBound]
        let declarationSegment = beforeName.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == ";" || $0 == "{" || $0 == "}" }
        ).last.map(String.init) ?? String(beforeName)
        var declarationSegments = [String(declarationSegment)]
        var precedingLine = occurrence.line - 1
        while precedingLine > 0, let line = source.lineText(line: precedingLine) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.hasPrefix("@") else {
                break
            }
            declarationSegments.append(trimmedLine)
            precedingLine -= 1
        }

        let sensitiveWords = [
            "dynamic",
            "override",
            "objc",
            "objcMembers",
            "IBAction",
            "IBOutlet",
            "IBInspectable",
            "IBDesignable",
            "IBSegueAction",
            "GKInspectable",
            "NSManaged",
            "_cdecl",
            "_silgen_name"
        ]
        return declarationSegments.contains { segment in
            sensitiveWords.contains { containsSwiftWord(segment, word: $0) }
        }
    }

    private static func discoverInterfaceBuilderClassNames(under sourceRoot: URL) -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let customClassPattern = try? NSRegularExpression(
            pattern: "customClass\\s*=\\s*\"([A-Za-z_][A-Za-z0-9_]*)\""
        )
        var classNames: Set<String> = []

        for case let resourceURL as URL in enumerator {
            let pathExtension = resourceURL.pathExtension.lowercased()
            guard pathExtension == "xib" || pathExtension == "storyboard" else {
                continue
            }

            if pathExtension == "xib" {
                classNames.insert(resourceURL.deletingPathExtension().lastPathComponent)
            }

            guard let customClassPattern,
                  let contents = try? String(contentsOf: resourceURL, encoding: .utf8) else {
                continue
            }
            let fullRange = NSRange(contents.startIndex..<contents.endIndex, in: contents)
            for match in customClassPattern.matches(in: contents, range: fullRange) {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: contents) else {
                    continue
                }
                classNames.insert(String(contents[range]))
            }
        }

        return classNames
    }

    private enum SourceDeclarationContext: Equatable {
        case protocolBody
        case extensionBody(owner: String)
        case objectiveCRuntimeBody
        case otherBody
    }

    private struct DeclarationContextCheckpoint {
        let byteOffset: Int
        let contexts: [SourceDeclarationContext]
    }

    private struct DeclarationContextIndex {
        let byteCount: Int
        let checkpoints: [DeclarationContextCheckpoint]

        func contexts(beforeByteOffset byteOffset: Int) -> [SourceDeclarationContext] {
            let boundedOffset = min(max(byteOffset, 0), byteCount)
            var lowerBound = 0
            var upperBound = checkpoints.count
            while lowerBound < upperBound {
                let middle = lowerBound + (upperBound - lowerBound) / 2
                if checkpoints[middle].byteOffset <= boundedOffset {
                    lowerBound = middle + 1
                } else {
                    upperBound = middle
                }
            }
            return checkpoints[max(0, lowerBound - 1)].contexts
        }
    }

    private final class DeclarationContextCache: @unchecked Sendable {
        private let lock = NSLock()
        private var indexesByPath: [String: DeclarationContextIndex] = [:]

        func index(
            for source: SourceFile,
            makeIndex: () -> DeclarationContextIndex
        ) -> DeclarationContextIndex {
            lock.lock()
            defer { lock.unlock() }
            if let existing = indexesByPath[source.path] {
                return existing
            }
            let index = makeIndex()
            indexesByPath[source.path] = index
            return index
        }
    }

    private func declarationContexts(source: SourceFile, beforeByteOffset byteOffset: Int) -> [SourceDeclarationContext] {
        declarationContextCache.index(for: source) {
            makeDeclarationContextIndex(source: source)
        }.contexts(beforeByteOffset: byteOffset)
    }

    private func makeDeclarationContextIndex(source: SourceFile) -> DeclarationContextIndex {
        let bytes = [UInt8](source.data)
        var stack: [SourceDeclarationContext] = []
        var checkpoints = [DeclarationContextCheckpoint(byteOffset: 0, contexts: [])]
        var headerStart = 0
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                index += 2
                while index < bytes.count, bytes[index] != UInt8(ascii: "\n") {
                    index += 1
                }
                continue
            }
            if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "*") {
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/")) {
                    index += 1
                }
                index = min(index + 2, bytes.count)
                continue
            }
            if byte == UInt8(ascii: "\"") {
                index += 1
                while index < bytes.count {
                    if bytes[index] == UInt8(ascii: "\\") {
                        index = min(index + 2, bytes.count)
                    } else if bytes[index] == UInt8(ascii: "\"") {
                        index += 1
                        break
                    } else {
                        index += 1
                    }
                }
                continue
            }

            if byte == UInt8(ascii: "{") {
                stack.append(contextFromHeader(String(decoding: source.data[headerStart..<index], as: UTF8.self)))
                checkpoints.append(DeclarationContextCheckpoint(byteOffset: index + 1, contexts: stack))
                headerStart = index + 1
            } else if byte == UInt8(ascii: "}") {
                if !stack.isEmpty {
                    stack.removeLast()
                }
                checkpoints.append(DeclarationContextCheckpoint(byteOffset: index + 1, contexts: stack))
                headerStart = index + 1
            } else if byte == UInt8(ascii: ";") {
                headerStart = index + 1
            }
            index += 1
        }

        return DeclarationContextIndex(byteCount: bytes.count, checkpoints: checkpoints)
    }

    private func contextFromHeader(_ header: String) -> SourceDeclarationContext {
        if containsSwiftWord(header, word: "protocol") {
            return .protocolBody
        }
        if let owner = extensionOwner(in: header) {
            return .extensionBody(owner: owner)
        }
        if containsSwiftWord(header, word: "objcMembers") {
            return .objectiveCRuntimeBody
        }
        return .otherBody
    }

    private func extensionOwner(in header: String) -> String? {
        guard let extensionRange = header.range(of: #"\bextension\b"#, options: .regularExpression) else {
            return nil
        }
        let afterExtension = header[extensionRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if afterExtension.hasPrefix("[") {
            return "Array"
        }
        if afterExtension.hasPrefix("(") {
            return "<tuple>"
        }
        return swiftIdentifierPathTokens(in: afterExtension).first
    }

    private func isExternalExtensionContext(
        _ context: SourceDeclarationContext,
        localNominalTypeNames: Set<String>
    ) -> Bool {
        guard case let .extensionBody(owner) = context else {
            return false
        }
        let rootOwner = owner.split(separator: ".").first.map(String.init) ?? owner
        return !localNominalTypeNames.contains(rootOwner)
    }

    private func containsSwiftWord(_ text: String, word: String) -> Bool {
        swiftIdentifierPathTokens(in: text).contains(word)
    }

    private func swiftIdentifierPathTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if scalar == "." {
                if !current.isEmpty, current.last != "." {
                    current.append(".")
                }
            } else if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                current.unicodeScalars.append(scalar)
            } else {
                if !current.isEmpty {
                    tokens.append(current.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                    current.removeAll()
                }
            }
        }
        if !current.isEmpty {
            tokens.append(current.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        return tokens.filter { !$0.isEmpty }
    }
}
