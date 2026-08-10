import Foundation
import SwiftParser
import SwiftSyntax

public struct SourceTokenRange: Hashable, Sendable {
    public let path: String
    public let name: String
    public let byteRange: Range<Int>
    public let isBackticked: Bool

    public init(
        path: String,
        name: String,
        byteRange: Range<Int>,
        isBackticked: Bool = false
    ) {
        self.path = SourcePathNormalizer.canonicalPath(path)
        self.name = name
        self.byteRange = byteRange
        self.isBackticked = isBackticked
    }
}

public enum ParameterDeclarationSyntaxKind: String, Codable, Hashable, Sendable {
    case function
    case initializer
    case subscriptDeclaration
    case enumCase
    case accessor
    case closure
}

public enum ParameterExternalLabelSyntaxRole: Hashable, Sendable {
    case none
    case omitted(SourceTokenRange)
    case named(SourceTokenRange)

    public var token: SourceTokenRange? {
        switch self {
        case .none:
            return nil
        case .omitted(let token), .named(let token):
            return token
        }
    }
}

public struct ParameterDeclarationSyntaxRoles: Hashable, Sendable {
    public let parameterUSR: String
    public let kind: ParameterDeclarationSyntaxKind
    public let indexedDeclarationAnchor: SourceTokenRange
    public let externalLabel: ParameterExternalLabelSyntaxRole
    public let localBinding: SourceTokenRange?
    public let hasDefaultValue: Bool
    public let isVariadic: Bool
    public let localBindingReferences: [SourceTokenRange]
    public let shadowingBindingDeclarations: [SourceTokenRange]
    public let implicitShadowingBindingNames: Set<String>
    public let syntaxOwnerToken: SourceTokenRange?
    public let indexedOwnerUSR: String?
    public let syntaxOwnerMatchesIndexedOwner: Bool

    public var sharesLabelAndBindingToken: Bool {
        guard let label = externalLabel.token, let localBinding else {
            return false
        }
        return label.byteRange == localBinding.byteRange
            && label.path == localBinding.path
    }

    public var isNestedLocalFunctionParameter: Bool {
        kind == .function && !syntaxOwnerMatchesIndexedOwner
    }

    public var localBindingTokens: [SourceTokenRange] {
        let declaration = localBinding.map { [$0] } ?? []
        return Array(Set(declaration + localBindingReferences)).sorted {
            ($0.path, $0.byteRange.lowerBound) < ($1.path, $1.byteRange.lowerBound)
        }
    }
}

public struct ParameterSyntaxFactsSummary: Codable, Equatable, Sendable {
    public let explicitParameters: Int
    public let resolvedParameters: Int
    public let unresolvedParameters: Int
    public let functionParameters: Int
    public let initializerParameters: Int
    public let subscriptParameters: Int
    public let enumCaseParameters: Int
    public let accessorBindings: Int
    public let closureParameters: Int
    public let nestedLocalFunctionParameters: Int
    public let namedExternalLabels: Int
    public let omittedExternalLabels: Int
    public let parametersWithoutExternalLabels: Int
    public let localBindings: Int
    public let parametersWithoutLocalBindings: Int
    public let parametersWithoutSourceNames: Int
    public let parametersWithDefaultValues: Int
    public let variadicParameters: Int
    public let sharedLabelAndBindingTokens: Int
    public let distinctLabelAndBindingTokens: Int
    public let localBindingReferenceTokens: Int
    public let parametersWithShadowingBindingDeclarations: Int
    public let localBindingOnlyCoverageCandidates: Int
    public let parametersRequiringExternalLabelCoordination: Int
    public let nonEnumParametersWithoutLocalBindings: Int
    public let enumCaseParametersExcludedFromParameterStage: Int
    public let unresolvedByReason: [String: Int]

    public static let empty = ParameterSyntaxFactsSummary(
        explicitParameters: 0,
        rolesByUSR: [:],
        unresolvedReasonsByUSR: [:]
    )

    init(
        explicitParameters: Int,
        rolesByUSR: [String: ParameterDeclarationSyntaxRoles],
        unresolvedReasonsByUSR: [String: String]
    ) {
        let roles = Array(rolesByUSR.values)
        self.explicitParameters = explicitParameters
        self.resolvedParameters = roles.count
        self.unresolvedParameters = max(0, explicitParameters - roles.count)
        self.functionParameters = roles.count { $0.kind == .function }
        self.initializerParameters = roles.count { $0.kind == .initializer }
        self.subscriptParameters = roles.count { $0.kind == .subscriptDeclaration }
        self.enumCaseParameters = roles.count { $0.kind == .enumCase }
        self.accessorBindings = roles.count { $0.kind == .accessor }
        self.closureParameters = roles.count { $0.kind == .closure }
        self.nestedLocalFunctionParameters = roles.count(where: \.isNestedLocalFunctionParameter)
        self.namedExternalLabels = roles.count {
            if case .named = $0.externalLabel { return true }
            return false
        }
        self.omittedExternalLabels = roles.count {
            if case .omitted = $0.externalLabel { return true }
            return false
        }
        self.parametersWithoutExternalLabels = roles.count { $0.externalLabel == .none }
        self.localBindings = roles.count { $0.localBinding != nil }
        self.parametersWithoutLocalBindings = roles.count { $0.localBinding == nil }
        self.parametersWithoutSourceNames = roles.count {
            $0.externalLabel == .none && $0.localBinding == nil
        }
        self.parametersWithDefaultValues = roles.count(where: \.hasDefaultValue)
        self.variadicParameters = roles.count(where: \.isVariadic)
        self.sharedLabelAndBindingTokens = roles.count(where: \.sharesLabelAndBindingToken)
        self.distinctLabelAndBindingTokens = roles.count {
            $0.externalLabel.token != nil
                && $0.localBinding != nil
                && !$0.sharesLabelAndBindingToken
        }
        self.localBindingReferenceTokens = roles.reduce(0) {
            $0 + $1.localBindingReferences.count
        }
        self.parametersWithShadowingBindingDeclarations = roles.count {
            !$0.shadowingBindingDeclarations.isEmpty
                || !$0.implicitShadowingBindingNames.isEmpty
        }
        self.localBindingOnlyCoverageCandidates = roles.count {
            ParameterSyntaxFacts.isLocalBindingOnlyCoverageCandidate($0)
        }
        self.parametersRequiringExternalLabelCoordination = roles.count { role in
            guard role.kind != .enumCase, role.localBinding != nil else {
                return false
            }
            if case .named = role.externalLabel {
                return true
            }
            return false
        }
        self.nonEnumParametersWithoutLocalBindings = roles.count {
            $0.kind != .enumCase && $0.localBinding == nil
        }
        self.enumCaseParametersExcludedFromParameterStage = roles.count {
            $0.kind == .enumCase
        }
        self.unresolvedByReason = Dictionary(
            grouping: unresolvedReasonsByUSR.values,
            by: { $0 }
        ).mapValues(\.count)
    }
}

public struct ParameterLocalBindingOutcomeSummary: Codable, Equatable, Sendable {
    public let candidates: Int
    public let renamed: Int
    public let denied: Int
    public let unclassified: Int
    public let denialCategories: [CoverageDenialSummary]
    public let deniedCandidateUSRs: [String]

    public static let empty = ParameterLocalBindingOutcomeSummary(
        candidates: 0,
        renamed: 0,
        denied: 0,
        unclassified: 0,
        denialCategories: [],
        deniedCandidateUSRs: []
    )

    private init(
        candidates: Int,
        renamed: Int,
        denied: Int,
        unclassified: Int,
        denialCategories: [CoverageDenialSummary],
        deniedCandidateUSRs: [String]
    ) {
        self.candidates = candidates
        self.renamed = renamed
        self.denied = denied
        self.unclassified = unclassified
        self.denialCategories = denialCategories
        self.deniedCandidateUSRs = deniedCandidateUSRs
    }

    init(
        candidateUSRs: Set<String>,
        entries: [RenamePlanEntry],
        decisions: [SafetyDecision],
        groupsByUSR: [String: USROccurrenceGroup]
    ) {
        let renamedUSRs = Set(entries.map(\.usr)).intersection(candidateUSRs)
        let decisionsByUSR = Dictionary(uniqueKeysWithValues: decisions.map { ($0.usr, $0) })
        let deniedUSRs = candidateUSRs.intersection(decisionsByUSR.keys)
        var categoryCounts: [CoverageDenialCategory: Int] = [:]
        for usr in deniedUSRs {
            guard let decision = decisionsByUSR[usr] else {
                continue
            }
            let categories = CoverageAnalyzer.denialCategories(
                for: decision,
                group: groupsByUSR[usr]
            ).subtracting([.parameter])
            for category in categories.isEmpty ? [.other] : categories {
                categoryCounts[category, default: 0] += 1
            }
        }

        self.candidates = candidateUSRs.count
        self.renamed = renamedUSRs.count
        self.denied = deniedUSRs.count
        self.unclassified = candidateUSRs.subtracting(renamedUSRs).subtracting(deniedUSRs).count
        self.denialCategories = categoryCounts.map {
            CoverageDenialSummary(category: $0.key, members: $0.value)
        }.sorted {
            $0.members == $1.members
                ? $0.category.rawValue < $1.category.rawValue
                : $0.members > $1.members
        }
        self.deniedCandidateUSRs = deniedUSRs.sorted()
    }
}

public struct ParameterSyntaxFacts: Sendable {
    public let rolesByUSR: [String: ParameterDeclarationSyntaxRoles]
    public let localBindingOnlyCoverageCandidateUSRs: Set<String>
    public let unresolvedReasonsByUSR: [String: String]
    public let summary: ParameterSyntaxFactsSummary

    public init(
        snapshot: IndexSnapshot,
        sourceCache: SourceFileCache,
        obfuscationRoots: [URL]
    ) {
        let rootPaths = obfuscationRoots.map {
            $0.resolvingSymlinksInPath().standardizedFileURL.path
        }
        let parameterDeclarations = snapshot.occurrences.filter { occurrence in
            occurrence.symbol.kind == "parameter"
                && !occurrence.roles.contains("implicit")
                && (occurrence.roles.contains("declaration")
                    || occurrence.roles.contains("definition"))
                && Self.isPath(occurrence.path, underRootPaths: rootPaths)
        }
        let declarationsByUSR = Dictionary(grouping: parameterDeclarations, by: \.usr)
        let occurrencesByUSR = Dictionary(grouping: snapshot.occurrences, by: \.usr)
        let declarationPaths = Set(parameterDeclarations.map {
            SourcePathNormalizer.canonicalPath($0.path)
        })

        var candidatesByPathAndOffset: [String: [Int: [ParameterSyntaxCandidate]]] = [:]
        for path in declarationPaths.sorted() {
            guard let source = sourceCache.file(for: path) else {
                continue
            }
            let tree = Parser.parse(source: String(decoding: source.data, as: UTF8.self))
            let visitor = ParameterSyntaxVisitor(source: source)
            visitor.walk(tree)
            visitor.resolveLocalBindingReferences()
            candidatesByPathAndOffset[path] = Dictionary(
                grouping: visitor.candidates,
                by: { $0.indexedAnchor.byteRange.lowerBound }
            )
        }

        var rolesByUSR: [String: ParameterDeclarationSyntaxRoles] = [:]
        var unresolvedReasonsByUSR: [String: String] = [:]
        for usr in declarationsByUSR.keys.sorted() {
            let declarations = declarationsByUSR[usr] ?? []
            let declarationAnchors = Set(declarations.compactMap { occurrence -> IndexedParameterAnchor? in
                guard let source = sourceCache.file(for: occurrence.path),
                      let byteOffset = source.byteOffset(
                        line: occurrence.line,
                        utf8Column: occurrence.utf8Column
                      ) else {
                    return nil
                }
                let token = source.identifierToken(atByteOffset: byteOffset).map {
                    SourceTokenRange(
                        path: source.path,
                        name: $0.name,
                        byteRange: $0.byteRange,
                        isBackticked: $0.isBackticked
                    )
                }
                return IndexedParameterAnchor(
                    path: source.path,
                    byteOffset: byteOffset,
                    token: token
                )
            })
            guard declarationAnchors.count == 1, let declarationAnchor = declarationAnchors.first else {
                unresolvedReasonsByUSR[usr] = declarationAnchors.isEmpty
                    ? "indexed declaration anchor unavailable"
                    : "indexed declaration anchor is ambiguous"
                continue
            }
            let candidatesAtOffset = candidatesByPathAndOffset[declarationAnchor.path]
                .flatMap { $0[declarationAnchor.byteOffset] } ?? []
            let candidates = candidatesAtOffset.filter {
                declarationAnchor.token == nil
                    || $0.indexedAnchor.byteRange == declarationAnchor.token?.byteRange
            }
            guard candidates.count == 1, let candidate = candidates.first else {
                unresolvedReasonsByUSR[usr] = candidates.isEmpty
                    ? "compiler syntax parameter unavailable at indexed declaration token"
                    : "multiple compiler syntax parameters match indexed declaration token"
                continue
            }

            let ownerUSRs = Set(declarations.flatMap { occurrence in
                occurrence.relations.compactMap { relation in
                    relation.roles.contains("childOf") ? relation.usr : nil
                }
            })
            let indexedOwnerUSR = ownerUSRs.count == 1 ? ownerUSRs.first : nil
            let indexedOwnerAnchors = Set(indexedOwnerUSR.flatMap { ownerUSR in
                occurrencesByUSR[ownerUSR]?.compactMap { occurrence -> IndexedByteAnchor? in
                    guard !occurrence.roles.contains("implicit"),
                          occurrence.roles.contains("declaration")
                            || occurrence.roles.contains("definition"),
                          Self.isPath(occurrence.path, underRootPaths: rootPaths),
                          let source = sourceCache.file(for: occurrence.path),
                          let byteOffset = source.byteOffset(
                            line: occurrence.line,
                            utf8Column: occurrence.utf8Column
                          ) else {
                        return nil
                    }
                    return IndexedByteAnchor(
                        path: source.path,
                        byteOffset: byteOffset
                    )
                }
            } ?? [])
            let syntaxOwnerMatchesIndexedOwner = candidate.ownerToken.map { token in
                indexedOwnerAnchors.contains { anchor in
                    guard anchor.path == token.path else {
                        return false
                    }
                    return token.byteRange.contains(anchor.byteOffset)
                        || (token.isBackticked
                            && anchor.byteOffset + 1 == token.byteRange.lowerBound)
                }
            } ?? false

            rolesByUSR[usr] = ParameterDeclarationSyntaxRoles(
                parameterUSR: usr,
                kind: candidate.kind,
                indexedDeclarationAnchor: declarationAnchor.token ?? candidate.indexedAnchor,
                externalLabel: candidate.externalLabel,
                localBinding: candidate.localBinding,
                hasDefaultValue: candidate.hasDefaultValue,
                isVariadic: candidate.isVariadic,
                localBindingReferences: candidate.localBindingReferences,
                shadowingBindingDeclarations: candidate.shadowingBindingDeclarations,
                implicitShadowingBindingNames: candidate.implicitShadowingBindingNames,
                syntaxOwnerToken: candidate.ownerToken,
                indexedOwnerUSR: indexedOwnerUSR,
                syntaxOwnerMatchesIndexedOwner: syntaxOwnerMatchesIndexedOwner
            )
        }

        self.rolesByUSR = rolesByUSR
        self.localBindingOnlyCoverageCandidateUSRs = Set(
            rolesByUSR.compactMap { usr, role in
                Self.isLocalBindingOnlyCoverageCandidate(role) ? usr : nil
            }
        )
        self.unresolvedReasonsByUSR = unresolvedReasonsByUSR
        self.summary = ParameterSyntaxFactsSummary(
            explicitParameters: declarationsByUSR.count,
            rolesByUSR: rolesByUSR,
            unresolvedReasonsByUSR: unresolvedReasonsByUSR
        )
    }

    private static func isPath(_ path: String, underRootPaths rootPaths: [String]) -> Bool {
        let canonicalPath = SourcePathNormalizer.canonicalPath(path)
        return rootPaths.contains { rootPath in
            canonicalPath == rootPath || canonicalPath.hasPrefix(rootPath + "/")
        }
    }

    static func isLocalBindingOnlyCoverageCandidate(
        _ role: ParameterDeclarationSyntaxRoles
    ) -> Bool {
        guard role.kind != .enumCase,
              role.localBinding != nil,
              role.shadowingBindingDeclarations.isEmpty,
              role.implicitShadowingBindingNames.isEmpty,
              role.localBindingTokens.allSatisfy({
                  !$0.isBackticked && isPlainSwiftIdentifier($0.name)
              }) else {
            return false
        }
        switch role.externalLabel {
        case .none, .omitted:
            return true
        case .named:
            return false
        }
    }
}

private struct ParameterSyntaxCandidate {
    let kind: ParameterDeclarationSyntaxKind
    let indexedAnchor: SourceTokenRange
    let externalLabel: ParameterExternalLabelSyntaxRole
    let localBinding: SourceTokenRange?
    let hasDefaultValue: Bool
    let isVariadic: Bool
    let ownerToken: SourceTokenRange?
    let bodyRange: Range<Int>?
    var localBindingReferences: [SourceTokenRange] = []
    var shadowingBindingDeclarations: [SourceTokenRange] = []
    var implicitShadowingBindingNames: Set<String> = []
}

private struct ImplicitBindingScope {
    let name: String
    let bodyRange: Range<Int>
}

private final class ParameterSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var candidates: [ParameterSyntaxCandidate] = []
    var declarationReferences: [SourceTokenRange] = []
    var bindingDeclarations: [SourceTokenRange] = []
    var implicitBindingScopes: [ImplicitBindingScope] = []

    init(source: SourceFile) {
        self.source = source
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        guard let firstName = sourceToken(node.firstName),
              let indexedAnchor = sourceToken(node.secondName ?? node.firstName),
              let owner = functionOwner(of: node) else {
            return .visitChildren
        }
        let localBinding = indexedAnchor.name == "_" ? nil : indexedAnchor
        if let localBinding {
            bindingDeclarations.append(localBinding)
        }
        candidates.append(ParameterSyntaxCandidate(
            kind: owner.kind,
            indexedAnchor: indexedAnchor,
            externalLabel: owner.isOperatorFunction
                || (owner.kind == .subscriptDeclaration && node.secondName == nil)
                ? .none
                : externalLabel(firstName),
            localBinding: localBinding,
            hasDefaultValue: node.defaultValue != nil,
            isVariadic: node.ellipsis != nil,
            ownerToken: owner.token,
            bodyRange: owner.bodyRange
        ))
        return .visitChildren
    }

    override func visit(_ node: EnumCaseParameterSyntax) -> SyntaxVisitorContinueKind {
        guard let firstNameSyntax = node.firstName else {
            guard let typeToken = node.type.firstToken(viewMode: .sourceAccurate),
                  let indexedAnchor = sourceToken(typeToken) else {
                return .visitChildren
            }
            candidates.append(ParameterSyntaxCandidate(
                kind: .enumCase,
                indexedAnchor: indexedAnchor,
                externalLabel: .none,
                localBinding: nil,
                hasDefaultValue: node.defaultValue != nil,
                isVariadic: false,
                ownerToken: ownerToken(of: node, as: EnumCaseElementSyntax.self, token: \.name),
                bodyRange: nil
            ))
            return .visitChildren
        }
        guard let firstName = sourceToken(firstNameSyntax),
              let indexedAnchor = sourceToken(node.secondName ?? firstNameSyntax) else {
            return .visitChildren
        }
        let localBinding = indexedAnchor.name == "_" ? nil : indexedAnchor
        if let localBinding {
            bindingDeclarations.append(localBinding)
        }
        candidates.append(ParameterSyntaxCandidate(
            kind: .enumCase,
            indexedAnchor: indexedAnchor,
            externalLabel: externalLabel(firstName),
            localBinding: localBinding,
            hasDefaultValue: node.defaultValue != nil,
            isVariadic: false,
            ownerToken: ownerToken(of: node, as: EnumCaseElementSyntax.self, token: \.name),
            bodyRange: nil
        ))
        return .visitChildren
    }

    override func visit(_ node: AccessorParametersSyntax) -> SyntaxVisitorContinueKind {
        guard let indexedAnchor = sourceToken(node.name) else {
            return .visitChildren
        }
        let owner = accessorOwner(of: node)
        bindingDeclarations.append(indexedAnchor)
        candidates.append(ParameterSyntaxCandidate(
            kind: .accessor,
            indexedAnchor: indexedAnchor,
            externalLabel: .none,
            localBinding: indexedAnchor,
            hasDefaultValue: false,
            isVariadic: false,
            ownerToken: owner?.token,
            bodyRange: owner?.bodyRange
        ))
        return .visitChildren
    }

    override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
        guard let indexedAnchor = sourceToken(node.secondName ?? node.firstName) else {
            return .visitChildren
        }
        let localBinding = indexedAnchor.name == "_" ? nil : indexedAnchor
        if let localBinding {
            bindingDeclarations.append(localBinding)
        }
        let owner = closureOwner(of: node)
        candidates.append(ParameterSyntaxCandidate(
            kind: .closure,
            indexedAnchor: indexedAnchor,
            externalLabel: .none,
            localBinding: localBinding,
            hasDefaultValue: false,
            isVariadic: node.ellipsis != nil,
            ownerToken: owner?.token,
            bodyRange: owner?.bodyRange
        ))
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if !isMemberAccessName(node), let token = sourceToken(node.baseName) {
            declarationReferences.append(token)
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        if let token = sourceToken(node.identifier) {
            bindingDeclarations.append(token)
        }
        return .visitChildren
    }

    override func visit(_ node: ClosureCaptureSyntax) -> SyntaxVisitorContinueKind {
        guard let token = sourceToken(node.name) else {
            return .visitChildren
        }
        if node.initializer == nil {
            declarationReferences.append(token)
        } else {
            bindingDeclarations.append(token)
        }
        return .visitChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        if let bodyRange = syntaxRange(node.body) {
            implicitBindingScopes.append(ImplicitBindingScope(
                name: "error",
                bodyRange: bodyRange
            ))
        }
        return .visitChildren
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.parameters == nil,
              let bodyRange = syntaxRange(node.body) else {
            return .visitChildren
        }
        let implicitBindingName: String?
        switch node.accessorSpecifier.text {
        case "set", "willSet":
            implicitBindingName = "newValue"
        case "didSet":
            implicitBindingName = "oldValue"
        default:
            implicitBindingName = nil
        }
        if let implicitBindingName {
            implicitBindingScopes.append(ImplicitBindingScope(
                name: implicitBindingName,
                bodyRange: bodyRange
            ))
        }
        return .visitChildren
    }

    func resolveLocalBindingReferences() {
        for index in candidates.indices {
            guard let localBinding = candidates[index].localBinding,
                  let bodyRange = candidates[index].bodyRange else {
                continue
            }
            candidates[index].localBindingReferences = Array(Set(
                declarationReferences.filter {
                    $0.name == localBinding.name
                        && bodyRange.contains($0.byteRange.lowerBound)
                }
            )).sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
            candidates[index].shadowingBindingDeclarations = Array(Set(
                bindingDeclarations.filter {
                    $0.name == localBinding.name
                        && bodyRange.contains($0.byteRange.lowerBound)
                }
            )).sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
            candidates[index].implicitShadowingBindingNames = Set(
                implicitBindingScopes.compactMap { scope in
                    scope.name == localBinding.name
                        && bodyRange.contains(scope.bodyRange.lowerBound)
                        ? scope.name
                        : nil
                }
            )
        }
    }

    private func functionOwner(
        of node: FunctionParameterSyntax
    ) -> (
        kind: ParameterDeclarationSyntaxKind,
        token: SourceTokenRange,
        bodyRange: Range<Int>?,
        isOperatorFunction: Bool
    )? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let function = current.as(FunctionDeclSyntax.self),
               let token = sourceToken(function.name) {
                return (
                    .function,
                    token,
                    syntaxRange(function.body),
                    isOperatorToken(function.name.tokenKind)
                )
            }
            if let initializer = current.as(InitializerDeclSyntax.self),
               let token = sourceToken(initializer.initKeyword) {
                return (.initializer, token, syntaxRange(initializer.body), false)
            }
            if let subscriptDeclaration = current.as(SubscriptDeclSyntax.self),
               let token = sourceToken(subscriptDeclaration.subscriptKeyword) {
                return (
                    .subscriptDeclaration,
                    token,
                    syntaxRange(subscriptDeclaration.accessorBlock),
                    false
                )
            }
            ancestor = current.parent
        }
        return nil
    }

    private func isOperatorToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .binaryOperator, .prefixOperator, .postfixOperator:
            return true
        default:
            return false
        }
    }

    private func accessorOwner(
        of node: AccessorParametersSyntax
    ) -> (token: SourceTokenRange, bodyRange: Range<Int>?)? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let accessor = current.as(AccessorDeclSyntax.self),
               let token = sourceToken(accessor.accessorSpecifier) {
                return (token, syntaxRange(accessor.body))
            }
            ancestor = current.parent
        }
        return nil
    }

    private func closureOwner(
        of node: ClosureParameterSyntax
    ) -> (token: SourceTokenRange, bodyRange: Range<Int>?)? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let closure = current.as(ClosureExprSyntax.self),
               let token = sourceToken(closure.leftBrace) {
                return (token, syntaxRange(closure.statements))
            }
            ancestor = current.parent
        }
        return nil
    }

    private func syntaxRange<Node: SyntaxProtocol>(_ node: Node?) -> Range<Int>? {
        guard let node else {
            return nil
        }
        let start = node.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = node.endPositionBeforeTrailingTrivia.utf8Offset
        return start < end ? start..<end : nil
    }

    private func ownerToken<Node: SyntaxProtocol>(
        of node: some SyntaxProtocol,
        as ownerType: Node.Type,
        token: KeyPath<Node, TokenSyntax>
    ) -> SourceTokenRange? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let owner = current.as(ownerType) {
                return sourceToken(owner[keyPath: token])
            }
            ancestor = current.parent
        }
        return nil
    }

    private func externalLabel(_ firstName: SourceTokenRange) -> ParameterExternalLabelSyntaxRole {
        firstName.name == "_" ? .omitted(firstName) : .named(firstName)
    }

    private func isMemberAccessName(_ node: DeclReferenceExprSyntax) -> Bool {
        guard let memberAccess = node.parent?.as(MemberAccessExprSyntax.self) else {
            return false
        }
        return node.baseName.positionAfterSkippingLeadingTrivia
            == memberAccess.declName.baseName.positionAfterSkippingLeadingTrivia
    }

    private func sourceToken(_ token: TokenSyntax) -> SourceTokenRange? {
        guard token.presence == .present else {
            return nil
        }
        let rawStart = token.positionAfterSkippingLeadingTrivia.utf8Offset
        if let identifier = source.identifierToken(atByteOffset: rawStart) {
            return SourceTokenRange(
                path: source.path,
                name: identifier.name,
                byteRange: identifier.byteRange,
                isBackticked: identifier.isBackticked
            )
        }
        let rawEnd = token.endPositionBeforeTrailingTrivia.utf8Offset
        guard rawStart < rawEnd, rawEnd <= source.data.count else {
            return nil
        }
        return SourceTokenRange(
            path: source.path,
            name: String(decoding: source.data[rawStart..<rawEnd], as: UTF8.self),
            byteRange: rawStart..<rawEnd
        )
    }
}

private struct IndexedParameterAnchor: Hashable {
    let path: String
    let byteOffset: Int
    let token: SourceTokenRange?
}

private struct IndexedByteAnchor: Hashable {
    let path: String
    let byteOffset: Int
}
