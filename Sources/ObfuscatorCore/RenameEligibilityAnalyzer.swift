import Foundation

public struct RenameEligibility: Codable, Sendable {
    public let usr: String
    public let symbolName: String
    public let symbolKind: String
    public let isEligible: Bool
    public let originalName: String?
    public let reasons: [String]

    public init(
        usr: String,
        symbolName: String,
        symbolKind: String,
        isEligible: Bool,
        originalName: String?,
        reasons: [String]
    ) {
        self.usr = usr
        self.symbolName = symbolName
        self.symbolKind = symbolKind
        self.isEligible = isEligible
        self.originalName = originalName
        self.reasons = reasons
    }

    private enum CodingKeys: String, CodingKey {
        case usr
        case symbolName
        case symbolKind = "kind"
        case isEligible = "allowed"
        case originalName = "oldName"
        case reasons
    }
}

public struct RenameEligibilityAnalyzer: Sendable {
    public static let defaultAllowedKinds = IndexSymbolKind.rawValues(
        .class,
        .struct,
        .enum,
        .protocol,
        .typealias,
        .function,
        .instanceMethod,
        .staticMethod,
        .classMethod,
        .instanceProperty,
        .staticProperty,
        .classProperty,
        .variable
    )

    public let sourceRoot: URL
    public let obfuscationRoots: [URL]
    public let allowedKinds: Set<String>
    private let interfaceBuilderClassNames: Set<String>

    public init(
        sourceRoot: URL,
        obfuscationRoots: [URL] = [],
        allowedKinds: Set<String> = RenameEligibilityAnalyzer.defaultAllowedKinds
    ) {
        let canonicalSourceRoot = sourceRoot.resolvingSymlinksInPath().standardizedFileURL
        self.sourceRoot = canonicalSourceRoot
        self.obfuscationRoots =
            obfuscationRoots.isEmpty
            ? [canonicalSourceRoot]
            : obfuscationRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.allowedKinds = allowedKinds
        self.interfaceBuilderClassNames = Self.discoverInterfaceBuilderClassNames(
            under: canonicalSourceRoot)
    }

    public func analyze(
        group: IndexSnapshot.OccurrenceGroup,
        sourceCache: SourceFileCache,
        semanticIndex: SemanticIndex = SemanticIndex(),
        overrideRelatedUSRs: Set<String> = [],
        tupleTypeAliasRelatedUSRs: Set<String> = [],
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
    ) -> RenameEligibility {
        var reasons: [String] = []
        var tokenNames: Set<String> = []
        var hasDeclarationOrDefinition = false
        var hasSelectedDeclarationOrDefinition = false

        if group.usr.isEmpty {
            reasons.append("empty USR")
        }
        if IndexUSR.isObjectiveCCompatible(group.usr) {
            reasons.append("Objective-C-compatible USR requires a stable runtime name")
        }
        if IndexSymbolName.isSyntheticAccessor(group.symbol.name) {
            reasons.append("synthetic accessor is derived from its parent declaration")
        }
        if Self.isAccessorOccurrenceGroup(group) {
            reasons.append("synthetic accessor is derived from its parent declaration")
        }
        if semanticIndex.explicitCodingKeysEnumUSRs.contains(group.usr) {
            reasons.append("explicit CodingKeys type name is required for Codable semantics")
        }
        let isSupportedLocalBindingParameter =
            group.symbol.isKind(.parameter)
            && localBindingOnlyParameterUSRs.contains(group.usr)
        let isSupportedExternalLabelParameter =
            group.symbol.isKind(.parameter)
            && coordinatedExternalLabelParameterUSRs.contains(group.usr)
        let isSupportedParameter =
            isSupportedLocalBindingParameter
            || isSupportedExternalLabelParameter
        let isSupportedEnumCase =
            group.symbol.isKind(.enumConstant)
            && coordinatedEnumCaseUSRs.contains(group.usr)
        if !allowedKinds.contains(group.symbol.kind)
            && !isSupportedParameter
            && !isSupportedEnumCase
        {
            reasons.append("unsupported symbol kind \(group.symbol.kind)")
        }
        if group.occurrences.isEmpty {
            reasons.append("no occurrences")
        }
        if semanticIndex.protocolRequirementUSRs.contains(group.usr),
            !coordinatedProtocolRequirementUSRs.contains(group.usr)
        {
            reasons.append("protocol members require relation-aware witness renaming")
        }
        // External nominal ownership is structural. A descendant with its own
        // explicit selected declaration is source-authored and can use the
        // same occurrence-closure and runtime checks as any other local symbol.
        let isSourceAuthoredExternalExtensionDeclaration =
            semanticIndex.externallyOwnedUSRs.contains(group.usr)
            && semanticIndex.selectedDeclarationUSRs.contains(group.usr)
        if semanticIndex.externallyOwnedUSRs.contains(group.usr),
            !isSourceAuthoredExternalExtensionDeclaration,
            !isSupportedLocalBindingParameter
        {
            reasons.append(
                "extensions on external Swift or Objective-C owners are not self-contained")
        }
        if !IndexUSR.isObjectiveCCompatible(group.usr),
            semanticIndex.runtimeSensitiveUSRs.contains(group.usr),
            !isSupportedLocalBindingParameter
        {
            reasons.append(
                "runtime-reflected or externally linked declaration according to IndexStore semantics"
            )
        }
        if overrideRelatedUSRs.contains(group.usr), !coordinatedRelatedUSRs.contains(group.usr) {
            reasons.append("override relations require coordinated renaming")
        }
        if tupleTypeAliasRelatedUSRs.contains(group.usr) {
            reasons.append("tuple typealias constructor occurrences are incomplete")
        }
        if genericParameterUSRs.contains(group.usr),
            !supportedGenericParameterUSRs.contains(group.usr)
        {
            reasons.append("generic type parameter occurrences are incomplete")
        }
        if semanticIndex.propertyWrapperDerivedUSRsByPropertyUSR[group.usr] != nil,
            !propertyWrapperSupportedUSRs.contains(group.usr)
        {
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
                reasons.append(
                    "occurrence outside source root at \(occurrence.path):\(occurrence.line)")
            }
            if occurrence.hasRole(.declaration) || occurrence.hasRole(.definition) {
                hasDeclarationOrDefinition = true
                if isUnderObfuscationRoots(occurrence.path) {
                    hasSelectedDeclarationOrDefinition = true
                }
            }
            if occurrence.relations.contains(where: {
                hasUnsafeRelation($0, symbolKind: group.symbol.kind)
                    && !coordinatedRelatedUSRs.contains($0.usr)
            }) {
                reasons.append(
                    "unsafe relation at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
            }

            guard let source = sourceCache.file(for: occurrence.path) else {
                reasons.append("source file unavailable for \(occurrence.path)")
                continue
            }
            guard
                let token = source.identifierToken(
                    line: occurrence.line, utf8Column: occurrence.utf8Column)
            else {
                reasons.append(
                    "identifier token unavailable at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
                continue
            }
            if Self.isSemanticSelfTypeReference(
                occurrence: occurrence,
                token: token,
                symbolKind: group.symbol.kind
            ) {
                continue
            }
            if occurrence.hasRole(.implicit) {
                reasons.append(
                    "implicit occurrence at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
            }
            let isExternalLabelOnlyUnderscore =
                isSupportedExternalLabelParameter
                && externalLabelOnlyParameterUSRs.contains(group.usr)
                && token.name == "_"
            let isCompilerValidatedParameterToken =
                isSupportedParameter
                && isPlainSwiftArgumentLabel(token.name)
            let isCompilerValidatedEnumCaseToken =
                isSupportedEnumCase
                && isPlainSwiftArgumentLabel(token.name)
            // The indexed project has already proved that an ASCII identifier
            // token is legal in every recorded declaration/reference context.
            // This includes contextual spellings and explicitly escaped Swift
            // keywords. Replacing only the identifier bytes keeps existing
            // backtick delimiters valid while generated names never require
            // escaping. Language entities are denied independently by semantic
            // accessor relations or by the declaration-name check below.
            let isCompilerAcceptedSourceIdentifier = isPlainSwiftArgumentLabel(token.name)
            if token.isBackticked
                && !isCompilerValidatedEnumCaseToken
                && !isCompilerAcceptedSourceIdentifier
            {
                reasons.append("backticked identifier \(token.name)")
            }
            if !isExternalLabelOnlyUnderscore
                && !isCompilerValidatedParameterToken
                && !isCompilerValidatedEnumCaseToken
                && !isCompilerAcceptedSourceIdentifier
            {
                reasons.append("non-plain identifier \(token.name)")
            }
            tokenNames.insert(token.name)

            if occurrence.hasRole(.declaration) || occurrence.hasRole(.definition) {
                if Self.isLanguageRequiredDeclarationName(token.name) {
                    reasons.append("language-required declaration name \(token.name)")
                }
                if group.symbol.isKind(.class), interfaceBuilderClassNames.contains(token.name) {
                    reasons.append(
                        "Interface Builder resource requires stable class name \(token.name)")
                }
                if semanticIndex.storedPropertyUSRs.contains(group.usr),
                    let ownerUSR = semanticIndex.nominalOwnerUSR(of: group.usr),
                    semanticIndex.serializationSensitiveOwnerUSRs.contains(ownerUSR),
                    !serializationKeyPreservedUSRs.contains(group.usr)
                {
                    reasons.append("serialized stored property requires explicit key preservation")
                }
                if !isSupportedLocalBindingParameter,
                    declarationHasUnindexedRuntimeOrLinkageAttribute(
                        source: source,
                        occurrence: occurrence,
                        token: token
                    )
                {
                    reasons.append(
                        "runtime-reflected or externally linked declaration at \(occurrence.path):\(occurrence.line)"
                    )
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
            reasons.append(
                "occurrences resolve to multiple source tokens: \(tokenNames.sorted().joined(separator: ", "))"
            )
        }

        let oldName = tokenNames.count == 1 ? tokenNames.first : nil
        return RenameEligibility(
            usr: group.usr,
            symbolName: group.symbol.name,
            symbolKind: group.symbol.kind,
            isEligible: reasons.isEmpty && oldName != nil,
            originalName: oldName,
            reasons: reasons.isEmpty
                ? ["allowed by local deny-by-default checks"] : Array(Set(reasons)).sorted()
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

    private func hasUnsafeRelation(_ relation: IndexSnapshot.Relation, symbolKind: String) -> Bool {
        relation.hasRole(.overrideOf)
            || (SemanticIndex.isOverrideDispatchKind(symbolKind)
                && relation.hasRole(.baseOf))
            || relation.hasRole(.specializationOf)
            || relation.hasRole(.ibTypeOf)
    }

    private func isSemanticOnlyCoordinatedOccurrence(
        _ occurrence: IndexSnapshot.Occurrence,
        coordinatedRelatedUSRs: Set<String>
    ) -> Bool {
        guard occurrence.hasRole(.implicit),
            !coordinatedRelatedUSRs.isEmpty
        else {
            return false
        }

        guard IndexRole.lexicalRawValues.isDisjoint(with: occurrence.roles) else {
            return false
        }

        // IndexStore emits semantic witness occurrences at the conforming type's
        // token. They describe dispatch edges but are not spellings of the
        // requirement/witness identifier and therefore must never be patched.
        return occurrence.relations.contains { relation in
            (relation.hasRole(.overrideOf) || relation.hasRole(.baseOf))
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
            "buildFinalResult",
        ]
        return names.contains(name)
    }

    static func isAccessorOccurrenceGroup(_ group: IndexSnapshot.OccurrenceGroup) -> Bool {
        group.occurrences.contains { occurrence in
            occurrence.hasRole(.accessorOf)
                || occurrence.relations.contains { $0.hasRole(.accessorOf) }
        }
    }

    static func isSemanticSelfTypeReference(
        occurrence: IndexSnapshot.Occurrence,
        token: SourceFile.IdentifierToken,
        symbolKind: String
    ) -> Bool {
        let nominalKinds = IndexSymbolKind.rawValues(.class, .struct, .enum, .protocol)
        return nominalKinds.contains(symbolKind)
            && token.name == "Self"
            && !occurrence.hasRole(.declaration)
            && !occurrence.hasRole(.definition)
    }

    private func declarationHasUnindexedRuntimeOrLinkageAttribute(
        source: SourceFile,
        occurrence: IndexSnapshot.Occurrence,
        token: SourceFile.IdentifierToken
    ) -> Bool {
        guard let line = source.lineText(line: occurrence.line),
            let tokenRange = line.range(of: token.name)
        else {
            return true
        }

        let beforeName = line[..<tokenRange.lowerBound]
        let declarationSegment =
            beforeName.split(
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
        // symbol properties and dispatch relations in SemanticIndex.
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
            "_silgen_name",
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
            "func", "var", "let", "subscript", "init", "deinit",
        ]
        return declarationWords.isDisjoint(with: swiftIdentifierPathTokens(in: line))
    }

    private static func discoverInterfaceBuilderClassNames(under sourceRoot: URL) -> Set<String> {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
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
                let contents = try? String(contentsOf: resourceURL, encoding: .utf8)
            else {
                continue
            }
            let fullRange = NSRange(contents.startIndex..<contents.endIndex, in: contents)
            for match in customClassPattern.matches(in: contents, range: fullRange) {
                guard match.numberOfRanges > 1,
                    let range = Range(match.range(at: 1), in: contents)
                else {
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
