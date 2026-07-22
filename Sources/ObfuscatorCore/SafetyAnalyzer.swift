import Foundation

public struct SafetyDecision: Sendable {
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

    public init(
        sourceRoot: URL,
        obfuscationRoots: [URL] = [],
        allowedKinds: Set<String> = SafetyAnalyzer.defaultAllowedKinds
    ) {
        self.sourceRoot = sourceRoot.resolvingSymlinksInPath().standardizedFileURL
        self.obfuscationRoots = obfuscationRoots.isEmpty
            ? [self.sourceRoot]
            : obfuscationRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.allowedKinds = allowedKinds
    }

    public func analyze(
        group: USROccurrenceGroup,
        sourceCache: SourceFileCache,
        localNominalTypeNames: Set<String> = []
    ) -> SafetyDecision {
        var reasons: [String] = []
        var tokenNames: Set<String> = []
        var hasDeclarationOrDefinition = false
        var hasSelectedDeclarationOrDefinition = false

        if group.usr.isEmpty {
            reasons.append("empty USR")
        }
        if !allowedKinds.contains(group.symbol.kind) {
            reasons.append("unsupported symbol kind \(group.symbol.kind)")
        }
        if group.occurrences.isEmpty {
            reasons.append("no occurrences")
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
                if isPropertyKind(group.symbol.kind),
                   declarationLineLooksStoredProperty(source: source, occurrence: occurrence, token: token) {
                    reasons.append("stored property declarations require memberwise initializer label support")
                }
                if declarationLineLooksExternallyVisible(source: source, occurrence: occurrence, token: token) {
                    reasons.append("externally visible or runtime-reflected declaration at \(occurrence.path):\(occurrence.line)")
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

    private func isPropertyKind(_ kind: String) -> Bool {
        kind == "instanceProperty" || kind == "staticProperty" || kind == "classProperty"
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

    private func declarationLineLooksExternallyVisible(
        source: SourceFile,
        occurrence: OccurrenceRecord,
        token: IdentifierToken
    ) -> Bool {
        guard let line = source.lineText(line: occurrence.line) else {
            return true
        }
        let sensitiveMarkers = [
            "@objc",
            "@IBAction",
            "@IBOutlet",
            "@IBInspectable",
            "@GKInspectable",
            " dynamic ",
            " override "
        ]
        return sensitiveMarkers.contains { line.contains($0) }
    }

    private enum SourceDeclarationContext: Equatable {
        case protocolBody
        case extensionBody(owner: String)
        case otherBody
    }

    private func declarationContexts(source: SourceFile, beforeByteOffset byteOffset: Int) -> [SourceDeclarationContext] {
        let bytes = [UInt8](source.data)
        let end = min(max(byteOffset, 0), bytes.count)
        var stack: [SourceDeclarationContext] = []
        var headerStart = 0
        var index = 0

        while index < end {
            let byte = bytes[index]
            if byte == UInt8(ascii: "/"), index + 1 < end, bytes[index + 1] == UInt8(ascii: "/") {
                index += 2
                while index < end, bytes[index] != UInt8(ascii: "\n") {
                    index += 1
                }
                continue
            }
            if byte == UInt8(ascii: "/"), index + 1 < end, bytes[index + 1] == UInt8(ascii: "*") {
                index += 2
                while index + 1 < end, !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/")) {
                    index += 1
                }
                index = min(index + 2, end)
                continue
            }
            if byte == UInt8(ascii: "\"") {
                index += 1
                while index < end {
                    if bytes[index] == UInt8(ascii: "\\") {
                        index += 2
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
                headerStart = index + 1
            } else if byte == UInt8(ascii: "}") {
                if !stack.isEmpty {
                    stack.removeLast()
                }
                headerStart = index + 1
            } else if byte == UInt8(ascii: ";") {
                headerStart = index + 1
            }
            index += 1
        }

        return stack
    }

    private func contextFromHeader(_ header: String) -> SourceDeclarationContext {
        if containsSwiftWord(header, word: "protocol") {
            return .protocolBody
        }
        if let owner = extensionOwner(in: header) {
            return .extensionBody(owner: owner)
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
