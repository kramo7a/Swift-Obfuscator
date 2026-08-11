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
    }

    public func analyze(
        group: USROccurrenceGroup,
        sourceCache: SourceFileCache,
        indexedFacts: IndexedSemanticFacts = IndexedSemanticFacts(),
        overrideRelatedUSRs: Set<String> = [],
        tupleTypealiasRelatedUSRs: Set<String> = [],
        coordinatedRelatedUSRs: Set<String> = [],
        coordinatedProtocolRequirementUSRs: Set<String> = [],
        genericParameterUSRs: Set<String> = [],
        supportedGenericParameterUSRs: Set<String> = [],
        serializationKeyPreservedUSRs: Set<String> = [],
        propertyWrapperSupportedUSRs: Set<String> = [],
        localBindingOnlyParameterUSRs: Set<String> = [],
        coordinatedExternalLabelParameterUSRs: Set<String> = [],
        externalLabelOnlyParameterUSRs: Set<String> = [],
        coordinatedEnumCaseUSRs: Set<String> = []
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
        if isSyntheticAccessorName(group.symbol.name) {
            reasons.append("synthetic accessor is derived from its parent declaration")
        }
        if Self.isAccessorOccurrenceGroup(group) {
            reasons.append("synthetic accessor is derived from its parent declaration")
        }
        let isSupportedLocalBindingParameter = group.symbol.kind == "parameter"
            && localBindingOnlyParameterUSRs.contains(group.usr)
        let isSupportedExternalLabelParameter = group.symbol.kind == "parameter"
            && coordinatedExternalLabelParameterUSRs.contains(group.usr)
        let isSupportedParameter = isSupportedLocalBindingParameter
            || isSupportedExternalLabelParameter
        let isSupportedEnumCase = group.symbol.kind == "enumConstant"
            && coordinatedEnumCaseUSRs.contains(group.usr)
        if !allowedKinds.contains(group.symbol.kind)
            && !isSupportedParameter
            && !isSupportedEnumCase {
            reasons.append("unsupported symbol kind \(group.symbol.kind)")
        }
        if group.occurrences.isEmpty {
            reasons.append("no occurrences")
        }
        if indexedFacts.protocolRequirementUSRs.contains(group.usr),
           !coordinatedProtocolRequirementUSRs.contains(group.usr) {
            reasons.append("protocol members require relation-aware witness renaming")
        }
        // External nominal ownership is structural. A descendant with its own
        // explicit selected declaration is source-authored and can use the
        // same occurrence-closure and runtime checks as any other local symbol.
        let isSourceAuthoredExternalExtensionDeclaration =
            indexedFacts.externallyOwnedUSRs.contains(group.usr)
                && indexedFacts.selectedDeclarationUSRs.contains(group.usr)
        if indexedFacts.externallyOwnedUSRs.contains(group.usr),
           !isSourceAuthoredExternalExtensionDeclaration,
           !isSupportedLocalBindingParameter {
            reasons.append("extensions on external Swift or Objective-C owners are not self-contained")
        }
        if !group.usr.hasPrefix("c:"),
           indexedFacts.runtimeSensitiveUSRs.contains(group.usr),
           !isSupportedLocalBindingParameter {
            reasons.append("runtime-reflected or externally linked declaration according to IndexStore semantics")
        }
        if overrideRelatedUSRs.contains(group.usr), !coordinatedRelatedUSRs.contains(group.usr) {
            reasons.append("override relations require coordinated renaming")
        }
        if tupleTypealiasRelatedUSRs.contains(group.usr) {
            reasons.append("tuple typealias constructor occurrences are incomplete")
        }
        if genericParameterUSRs.contains(group.usr),
           !supportedGenericParameterUSRs.contains(group.usr) {
            reasons.append("generic type parameter occurrences are incomplete")
        }
        if indexedFacts.propertyWrapperDerivedUSRsByPropertyUSR[group.usr] != nil,
           !propertyWrapperSupportedUSRs.contains(group.usr) {
            reasons.append("property-wrapper derived names require coordinated renaming")
        }

        for occurrence in group.occurrences {
            if isSemanticOnlyCoordinatedOccurrence(
                occurrence,
                coordinatedRelatedUSRs: coordinatedRelatedUSRs
            ) {
                continue
            }
            if occurrence.isSystem {
                reasons.append("system occurrence at \(occurrence.path):\(occurrence.line)")
            }
            if !isUnderSourceRoot(occurrence.path) {
                reasons.append("occurrence outside source root at \(occurrence.path):\(occurrence.line)")
            }
            if occurrence.roles.contains("declaration") || occurrence.roles.contains("definition") {
                hasDeclarationOrDefinition = true
                if isUnderObfuscationRoots(occurrence.path) {
                    hasSelectedDeclarationOrDefinition = true
                }
            }
            if occurrence.relations.contains(where: {
                hasUnsafeRelation($0, symbolKind: group.symbol.kind)
                    && !coordinatedRelatedUSRs.contains($0.usr)
            }) {
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
            if Self.isSemanticSelfTypeReference(
                occurrence: occurrence,
                token: token,
                symbolKind: group.symbol.kind
            ) {
                continue
            }
            if occurrence.roles.contains("implicit") {
                reasons.append("implicit occurrence at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)")
            }
            let isExternalLabelOnlyUnderscore = isSupportedExternalLabelParameter
                && externalLabelOnlyParameterUSRs.contains(group.usr)
                && token.name == "_"
            let isCompilerValidatedParameterToken = isSupportedParameter
                && isPlainSwiftArgumentLabel(token.name)
            let isCompilerValidatedEnumCaseToken = isSupportedEnumCase
                && isPlainSwiftArgumentLabel(token.name)
            if token.isBackticked && !isCompilerValidatedEnumCaseToken {
                reasons.append("backticked identifier \(token.name)")
            }
            // The indexed project has already proved that an unescaped ASCII
            // token is legal in every recorded declaration/reference context.
            // Replacing it with a generated plain identifier is therefore
            // safe even when the old spelling is a contextual keyword such as
            // `get`, `set`, `open`, or `prefix`. Language entities are denied
            // independently by semantic accessor relations or by the
            // declaration-name check below.
            let isCompilerAcceptedUnescapedIdentifier = !token.isBackticked
                && isPlainSwiftArgumentLabel(token.name)
            if !isExternalLabelOnlyUnderscore
                && !isCompilerValidatedParameterToken
                && !isCompilerValidatedEnumCaseToken
                && !isCompilerAcceptedUnescapedIdentifier {
                reasons.append("non-plain identifier \(token.name)")
            }
            tokenNames.insert(token.name)

            if occurrence.roles.contains("declaration") || occurrence.roles.contains("definition") {
                if Self.isLanguageRequiredDeclarationName(token.name) {
                    reasons.append("language-required declaration name \(token.name)")
                }
                if group.symbol.kind == "class", interfaceBuilderClassNames.contains(token.name) {
                    reasons.append("Interface Builder resource requires stable class name \(token.name)")
                }
                if indexedFacts.storedPropertyUSRs.contains(group.usr),
                   let ownerUSR = indexedFacts.nominalOwnerUSR(of: group.usr),
                   indexedFacts.serializationSensitiveOwnerUSRs.contains(ownerUSR),
                   !serializationKeyPreservedUSRs.contains(group.usr) {
                    reasons.append("serialized stored property requires explicit key preservation")
                }
                if !isSupportedLocalBindingParameter,
                   declarationHasUnindexedRuntimeOrLinkageAttribute(
                    source: source,
                    occurrence: occurrence,
                    token: token
                ) {
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
            || (IndexedSemanticFacts.isOverrideDispatchKind(symbolKind)
                && relation.roles.contains("baseOf"))
            || relation.roles.contains("specializationOf")
            || relation.roles.contains("ibTypeOf")
    }

    private func isSemanticOnlyCoordinatedOccurrence(
        _ occurrence: OccurrenceRecord,
        coordinatedRelatedUSRs: Set<String>
    ) -> Bool {
        guard occurrence.roles.contains("implicit"),
              !coordinatedRelatedUSRs.isEmpty else {
            return false
        }

        let lexicalRoles: Set<String> = [
            "declaration", "definition", "reference", "read", "write", "call", "dynamic", "addressOf"
        ]
        guard lexicalRoles.isDisjoint(with: occurrence.roles) else {
            return false
        }

        // IndexStore emits semantic witness occurrences at the conforming type's
        // token. They describe dispatch edges but are not spellings of the
        // requirement/witness identifier and therefore must never be patched.
        return occurrence.relations.contains { relation in
            (relation.roles.contains("overrideOf") || relation.roles.contains("baseOf"))
                && coordinatedRelatedUSRs.contains(relation.usr)
        }
    }

    static func isLanguageRequiredDeclarationName(_ name: String) -> Bool {
        let names: Set<String> = [
            "wrappedValue",
            "projectedValue",
            "subscript",
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

    static func isAccessorOccurrenceGroup(_ group: USROccurrenceGroup) -> Bool {
        group.occurrences.contains { occurrence in
            occurrence.roles.contains("accessorOf")
                || occurrence.relations.contains { $0.roles.contains("accessorOf") }
        }
    }

    static func isSemanticSelfTypeReference(
        occurrence: OccurrenceRecord,
        token: IdentifierToken,
        symbolKind: String
    ) -> Bool {
        let nominalKinds: Set<String> = ["class", "struct", "enum", "protocol"]
        return nominalKinds.contains(symbolKind)
            && token.name == "Self"
            && !occurrence.roles.contains("declaration")
            && !occurrence.roles.contains("definition")
    }

    private func isSyntheticAccessorName(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return lowercasedName.hasPrefix("getter:") || lowercasedName.hasPrefix("setter:")
    }

    private func declarationHasUnindexedRuntimeOrLinkageAttribute(
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
            guard isStandaloneAttributeLine(trimmedLine) else {
                break
            }
            declarationSegments.append(trimmedLine)
            precedingLine -= 1
        }

        // Most runtime contracts are represented semantically by c: USRs,
        // symbol properties and dispatch relations in IndexedSemanticFacts.
        // IndexStore does not consistently preserve every declaration attribute
        // (notably nested @objc names and some private @IB declarations), so the
        // attributes on this declaration remain a narrow lexical fallback.
        let sensitiveWords = [
            "objc",
            "objcMembers",
            "dynamic",
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

    private func isStandaloneAttributeLine(_ line: String) -> Bool {
        guard line.hasPrefix("@") else {
            return false
        }
        let declarationWords: Set<String> = [
            "class", "struct", "enum", "protocol", "extension", "typealias",
            "func", "var", "let", "subscript", "init", "deinit"
        ]
        return declarationWords.isDisjoint(with: swiftIdentifierPathTokens(in: line))
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
