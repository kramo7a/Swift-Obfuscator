import Foundation
import SwiftParser
import SwiftSyntax

public struct SourceTokenRange: Hashable, Sendable {
    public let path: String
    public let name: String
    public let byteRange: Range<Int>

    public init(path: String, name: String, byteRange: Range<Int>) {
        self.path = SourcePathNormalizer.canonicalPath(path)
        self.name = name
        self.byteRange = byteRange
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
    public let sharedLabelAndBindingTokens: Int
    public let distinctLabelAndBindingTokens: Int
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
        self.sharedLabelAndBindingTokens = roles.count(where: \.sharesLabelAndBindingToken)
        self.distinctLabelAndBindingTokens = roles.count {
            $0.externalLabel.token != nil
                && $0.localBinding != nil
                && !$0.sharesLabelAndBindingToken
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
                        byteRange: $0.byteRange
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
            let indexedOwnerTokens = Set(indexedOwnerUSR.flatMap { ownerUSR in
                occurrencesByUSR[ownerUSR]?.compactMap { occurrence -> SourceTokenRange? in
                    guard !occurrence.roles.contains("implicit"),
                          occurrence.roles.contains("declaration")
                            || occurrence.roles.contains("definition"),
                          Self.isPath(occurrence.path, underRootPaths: rootPaths),
                          let source = sourceCache.file(for: occurrence.path),
                          let token = source.identifierToken(
                            line: occurrence.line,
                            utf8Column: occurrence.utf8Column
                          ) else {
                        return nil
                    }
                    return SourceTokenRange(
                        path: source.path,
                        name: token.name,
                        byteRange: token.byteRange
                    )
                }
            } ?? [])
            let syntaxOwnerMatchesIndexedOwner = candidate.ownerToken.map {
                indexedOwnerTokens.contains($0)
            } ?? false

            rolesByUSR[usr] = ParameterDeclarationSyntaxRoles(
                parameterUSR: usr,
                kind: candidate.kind,
                indexedDeclarationAnchor: declarationAnchor.token ?? candidate.indexedAnchor,
                externalLabel: candidate.externalLabel,
                localBinding: candidate.localBinding,
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
        guard role.kind != .enumCase, role.localBinding != nil else {
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
    let ownerToken: SourceTokenRange?
}

private final class ParameterSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var candidates: [ParameterSyntaxCandidate] = []

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
        candidates.append(ParameterSyntaxCandidate(
            kind: owner.kind,
            indexedAnchor: indexedAnchor,
            externalLabel: externalLabel(firstName),
            localBinding: localBinding,
            ownerToken: owner.token
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
                ownerToken: ownerToken(of: node, as: EnumCaseElementSyntax.self, token: \.name)
            ))
            return .visitChildren
        }
        guard let firstName = sourceToken(firstNameSyntax),
              let indexedAnchor = sourceToken(node.secondName ?? firstNameSyntax) else {
            return .visitChildren
        }
        candidates.append(ParameterSyntaxCandidate(
            kind: .enumCase,
            indexedAnchor: indexedAnchor,
            externalLabel: externalLabel(firstName),
            localBinding: indexedAnchor.name == "_" ? nil : indexedAnchor,
            ownerToken: ownerToken(of: node, as: EnumCaseElementSyntax.self, token: \.name)
        ))
        return .visitChildren
    }

    override func visit(_ node: AccessorParametersSyntax) -> SyntaxVisitorContinueKind {
        guard let indexedAnchor = sourceToken(node.name) else {
            return .visitChildren
        }
        candidates.append(ParameterSyntaxCandidate(
            kind: .accessor,
            indexedAnchor: indexedAnchor,
            externalLabel: .none,
            localBinding: indexedAnchor,
            ownerToken: ownerToken(of: node, as: AccessorDeclSyntax.self, token: \.accessorSpecifier)
        ))
        return .visitChildren
    }

    override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
        guard let indexedAnchor = sourceToken(node.secondName ?? node.firstName) else {
            return .visitChildren
        }
        candidates.append(ParameterSyntaxCandidate(
            kind: .closure,
            indexedAnchor: indexedAnchor,
            externalLabel: .none,
            localBinding: indexedAnchor.name == "_" ? nil : indexedAnchor,
            ownerToken: ownerToken(of: node, as: ClosureExprSyntax.self, token: \.leftBrace)
        ))
        return .visitChildren
    }

    private func functionOwner(
        of node: FunctionParameterSyntax
    ) -> (kind: ParameterDeclarationSyntaxKind, token: SourceTokenRange)? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let function = current.as(FunctionDeclSyntax.self),
               let token = sourceToken(function.name) {
                return (.function, token)
            }
            if let initializer = current.as(InitializerDeclSyntax.self),
               let token = sourceToken(initializer.initKeyword) {
                return (.initializer, token)
            }
            if let subscriptDeclaration = current.as(SubscriptDeclSyntax.self),
               let token = sourceToken(subscriptDeclaration.subscriptKeyword) {
                return (.subscriptDeclaration, token)
            }
            ancestor = current.parent
        }
        return nil
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

    private func sourceToken(_ token: TokenSyntax) -> SourceTokenRange? {
        guard token.presence == .present else {
            return nil
        }
        let rawStart = token.positionAfterSkippingLeadingTrivia.utf8Offset
        if let identifier = source.identifierToken(atByteOffset: rawStart) {
            return SourceTokenRange(
                path: source.path,
                name: identifier.name,
                byteRange: identifier.byteRange
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
