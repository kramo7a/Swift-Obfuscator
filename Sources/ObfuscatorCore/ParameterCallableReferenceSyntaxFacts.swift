import Foundation
import SwiftParser
import SwiftSyntax

public enum ParameterCallableReferenceSyntaxKind: String, Codable, Hashable, Sendable {
    case bareReference
    case fullNameReference
    case subscriptCall
}

public struct ParameterCallableReferenceAnchor: Hashable, Sendable {
    public let callableUSR: String
    public let location: IndexedSourceLocation

    public init(callableUSR: String, location: IndexedSourceLocation) {
        self.callableUSR = callableUSR
        self.location = location
    }
}

public struct ParameterCallableReferenceSyntaxRoles: Hashable, Sendable {
    public let anchor: ParameterCallableReferenceAnchor
    public let kind: ParameterCallableReferenceSyntaxKind
    public let referenceByteRange: Range<Int>
    public let fullNameArgumentTokens: [SourceTokenRange]
    public let subscriptArguments: [ParameterCallArgumentSyntaxRole]
}

public struct UnresolvedParameterCallableReferenceSyntaxFact: Codable, Equatable, Sendable {
    public let callableUSR: String
    public let callableName: String
    public let path: String
    public let line: Int
    public let utf8Column: Int
    public let reason: String
}

public struct ParameterCallableReferenceSyntaxFactsSummary: Codable, Equatable, Sendable {
    public let componentsWithNamedExternalLabels: Int
    public let namedExternalLabelParameters: Int
    public let componentsWithIndexedReferences: Int
    public let namedParametersInComponentsWithIndexedReferences: Int
    public let indexedReferenceAnchors: Int
    public let resolvedReferenceAnchors: Int
    public let unresolvedReferenceAnchors: Int
    public let resolvedBareReferences: Int
    public let resolvedFullNameReferences: Int
    public let fullNameArgumentTokens: Int
    public let namedFullNameArgumentTokens: Int
    public let resolvedSubscriptCalls: Int
    public let subscriptArguments: Int
    public let namedSubscriptArgumentLabelTokens: Int
    public let componentsWithAllIndexedReferencesResolved: Int
    public let namedParametersInComponentsWithAllIndexedReferencesResolved: Int
    public let unresolvedByReason: [String: Int]
    public let unresolvedAnchors: [UnresolvedParameterCallableReferenceSyntaxFact]

    public static let empty = ParameterCallableReferenceSyntaxFactsSummary(
        components: [],
        rolesByAnchor: [:],
        unresolvedReasonsByAnchor: [:]
    )

    init(
        components: [ParameterRenameComponent],
        rolesByAnchor: [ParameterCallableReferenceAnchor: ParameterCallableReferenceSyntaxRoles],
        unresolvedReasonsByAnchor: [ParameterCallableReferenceAnchor: String]
    ) {
        let namedParameterCount: (ParameterRenameComponent) -> Int = { component in
            component.members.count { member in
                if case .named = member.externalLabel {
                    return true
                }
                return false
            }
        }
        let componentsWithReferences = components.filter {
            !$0.nonCallReferenceLocations.isEmpty
        }
        let roles = Array(rolesByAnchor.values)

        self.componentsWithNamedExternalLabels = components.count
        self.namedExternalLabelParameters = components.reduce(0) {
            $0 + namedParameterCount($1)
        }
        self.componentsWithIndexedReferences = componentsWithReferences.count
        self.namedParametersInComponentsWithIndexedReferences = componentsWithReferences
            .reduce(0) { $0 + namedParameterCount($1) }
        self.indexedReferenceAnchors = rolesByAnchor.count + unresolvedReasonsByAnchor.count
        self.resolvedReferenceAnchors = rolesByAnchor.count
        self.unresolvedReferenceAnchors = unresolvedReasonsByAnchor.count
        self.resolvedBareReferences = roles.count { $0.kind == .bareReference }
        self.resolvedFullNameReferences = roles.count { $0.kind == .fullNameReference }
        self.fullNameArgumentTokens = roles.reduce(0) {
            $0 + $1.fullNameArgumentTokens.count
        }
        self.namedFullNameArgumentTokens = roles.reduce(0) { count, role in
            count + role.fullNameArgumentTokens.count { $0.name != "_" }
        }
        self.resolvedSubscriptCalls = roles.count { $0.kind == .subscriptCall }
        self.subscriptArguments = roles.reduce(0) {
            $0 + $1.subscriptArguments.count
        }
        self.namedSubscriptArgumentLabelTokens = roles.reduce(0) { count, role in
            count + role.subscriptArguments.count { argument in
                switch argument {
                case .parenthesized(label: .some), .additionalTrailingClosure:
                    return true
                case .parenthesized(label: .none), .firstTrailingClosure:
                    return false
                }
            }
        }

        let resolvedAnchors = Set(rolesByAnchor.keys)
        let fullyResolvedComponents = componentsWithReferences.filter { component in
            component.nonCallReferenceLocations.allSatisfy { location in
                resolvedAnchors.contains(ParameterCallableReferenceAnchor(
                    callableUSR: component.callableUSR,
                    location: location
                ))
            }
        }
        self.componentsWithAllIndexedReferencesResolved = fullyResolvedComponents.count
        self.namedParametersInComponentsWithAllIndexedReferencesResolved =
            fullyResolvedComponents.reduce(0) { $0 + namedParameterCount($1) }
        self.unresolvedByReason = Dictionary(
            grouping: unresolvedReasonsByAnchor.values,
            by: { $0 }
        ).mapValues(\.count)
        let callableNamesByUSR = Dictionary(
            uniqueKeysWithValues: components.map { ($0.callableUSR, $0.callableName) }
        )
        self.unresolvedAnchors = unresolvedReasonsByAnchor.map { anchor, reason in
            UnresolvedParameterCallableReferenceSyntaxFact(
                callableUSR: anchor.callableUSR,
                callableName: callableNamesByUSR[anchor.callableUSR] ?? "<unavailable>",
                path: anchor.location.path,
                line: anchor.location.line,
                utf8Column: anchor.location.utf8Column,
                reason: reason
            )
        }.sorted {
            ($0.path, $0.line, $0.utf8Column, $0.callableUSR)
                < ($1.path, $1.line, $1.utf8Column, $1.callableUSR)
        }
    }
}

public struct ParameterCallableReferenceSyntaxFacts: Sendable {
    public let rolesByAnchor: [ParameterCallableReferenceAnchor: ParameterCallableReferenceSyntaxRoles]
    public let unresolvedReasonsByAnchor: [ParameterCallableReferenceAnchor: String]
    public let summary: ParameterCallableReferenceSyntaxFactsSummary

    public init(
        components: [ParameterRenameComponent],
        sourceCache: SourceFileCache
    ) {
        let targetComponents = components.filter { component in
            component.ownerCategory != .enumCase
                && component.members.contains { member in
                    if case .named = member.externalLabel {
                        return true
                    }
                    return false
                }
        }
        let anchors = Set(targetComponents.flatMap { component in
            component.nonCallReferenceLocations.map {
                ParameterCallableReferenceAnchor(
                    callableUSR: component.callableUSR,
                    location: $0
                )
            }
        })
        let anchorPaths = Set(anchors.map { $0.location.path })
        var candidatesByPath: [String: [CallableReferenceSyntaxCandidate]] = [:]
        for path in anchorPaths.sorted() {
            guard let source = sourceCache.file(for: path) else {
                continue
            }
            let tree = Parser.parse(source: String(decoding: source.data, as: UTF8.self))
            let visitor = ParameterCallableReferenceSyntaxVisitor(source: source)
            visitor.walk(tree)
            candidatesByPath[path] = visitor.candidates
        }

        var rolesByAnchor: [
            ParameterCallableReferenceAnchor: ParameterCallableReferenceSyntaxRoles
        ] = [:]
        var unresolvedReasonsByAnchor: [ParameterCallableReferenceAnchor: String] = [:]
        for anchor in anchors.sorted(by: Self.anchorPrecedes) {
            guard let source = sourceCache.file(for: anchor.location.path) else {
                unresolvedReasonsByAnchor[anchor] = "indexed callable reference source file unavailable"
                continue
            }
            guard let byteOffset = source.byteOffset(
                line: anchor.location.line,
                utf8Column: anchor.location.utf8Column
            ) else {
                unresolvedReasonsByAnchor[anchor] = "indexed callable reference byte offset unavailable"
                continue
            }
            let matches = (candidatesByPath[source.path] ?? []).filter {
                $0.anchorByteRange.contains(byteOffset)
            }
            guard matches.count == 1, let match = matches.first else {
                unresolvedReasonsByAnchor[anchor] = matches.isEmpty
                    ? "compiler callable reference syntax unavailable at indexed anchor"
                    : "multiple compiler callable references match indexed anchor"
                continue
            }
            guard match.structuralReasons.isEmpty else {
                unresolvedReasonsByAnchor[anchor] = match.structuralReasons
                    .sorted()
                    .joined(separator: "; ")
                continue
            }
            rolesByAnchor[anchor] = ParameterCallableReferenceSyntaxRoles(
                anchor: anchor,
                kind: match.kind,
                referenceByteRange: match.referenceByteRange,
                fullNameArgumentTokens: match.fullNameArgumentTokens,
                subscriptArguments: match.subscriptArguments
            )
        }

        self.rolesByAnchor = rolesByAnchor
        self.unresolvedReasonsByAnchor = unresolvedReasonsByAnchor
        self.summary = ParameterCallableReferenceSyntaxFactsSummary(
            components: targetComponents,
            rolesByAnchor: rolesByAnchor,
            unresolvedReasonsByAnchor: unresolvedReasonsByAnchor
        )
    }

    private static func anchorPrecedes(
        _ lhs: ParameterCallableReferenceAnchor,
        _ rhs: ParameterCallableReferenceAnchor
    ) -> Bool {
        (
            lhs.location.path,
            lhs.location.line,
            lhs.location.utf8Column,
            lhs.callableUSR
        ) < (
            rhs.location.path,
            rhs.location.line,
            rhs.location.utf8Column,
            rhs.callableUSR
        )
    }
}

private struct CallableReferenceSyntaxCandidate {
    let kind: ParameterCallableReferenceSyntaxKind
    let referenceByteRange: Range<Int>
    let anchorByteRange: Range<Int>
    let fullNameArgumentTokens: [SourceTokenRange]
    let subscriptArguments: [ParameterCallArgumentSyntaxRole]
    let structuralReasons: [String]
}

private final class ParameterCallableReferenceSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var candidates: [CallableReferenceSyntaxCandidate] = []

    init(source: SourceFile) {
        self.source = source
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard let baseName = sourceToken(node.baseName) else {
            return .visitChildren
        }
        var argumentTokens: [SourceTokenRange] = []
        var structuralReasons: [String] = []
        if let argumentNames = node.argumentNames {
            for argument in argumentNames.arguments {
                if let token = sourceToken(argument.name) {
                    argumentTokens.append(token)
                } else {
                    structuralReasons.append(
                        "compiler full-name argument token unavailable"
                    )
                }
            }
        }
        candidates.append(CallableReferenceSyntaxCandidate(
            kind: node.argumentNames == nil ? .bareReference : .fullNameReference,
            referenceByteRange: syntaxRange(node),
            anchorByteRange: baseName.byteRange,
            fullNameArgumentTokens: argumentTokens,
            subscriptArguments: [],
            structuralReasons: Array(Set(structuralReasons)).sorted()
        ))
        return .visitChildren
    }

    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        let arguments = argumentRoles(
            parenthesized: node.arguments,
            trailingClosure: node.trailingClosure,
            additionalTrailingClosures: node.additionalTrailingClosures
        )
        candidates.append(CallableReferenceSyntaxCandidate(
            kind: .subscriptCall,
            referenceByteRange: syntaxRange(node),
            anchorByteRange: syntaxRange(node.leftSquare),
            fullNameArgumentTokens: [],
            subscriptArguments: arguments.roles,
            structuralReasons: arguments.reasons
        ))
        return .visitChildren
    }

    private func argumentRoles(
        parenthesized: LabeledExprListSyntax,
        trailingClosure: ClosureExprSyntax?,
        additionalTrailingClosures: MultipleTrailingClosureElementListSyntax
    ) -> (roles: [ParameterCallArgumentSyntaxRole], reasons: [String]) {
        var roles: [ParameterCallArgumentSyntaxRole] = []
        var reasons: [String] = []
        for argument in parenthesized {
            if let label = argument.label {
                if let token = sourceToken(label) {
                    roles.append(.parenthesized(label: token))
                } else {
                    reasons.append("compiler subscript argument label token unavailable")
                }
            } else {
                roles.append(.parenthesized(label: nil))
            }
        }
        if trailingClosure != nil {
            roles.append(.firstTrailingClosure)
        }
        for closure in additionalTrailingClosures {
            if let token = sourceToken(closure.label) {
                roles.append(.additionalTrailingClosure(label: token))
            } else {
                reasons.append("compiler subscript trailing-closure label token unavailable")
            }
        }
        return (roles, Array(Set(reasons)).sorted())
    }

    private func syntaxRange(_ node: some SyntaxProtocol) -> Range<Int> {
        node.positionAfterSkippingLeadingTrivia.utf8Offset
            ..< node.endPositionBeforeTrailingTrivia.utf8Offset
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
