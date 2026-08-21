import Foundation
import SwiftParser
import SwiftSyntax

public enum CallableReferenceSyntax {}

extension CallableReferenceSyntax {
    public enum Kind: String, Codable, Hashable, Sendable {
        case bareReference
        case fullNameReference
        case subscriptCall
    }

    public struct Anchor: Hashable, Sendable {
        public let callableUSR: String
        public let location: IndexSnapshot.Location

        public init(callableUSR: String, location: IndexSnapshot.Location) {
            self.callableUSR = callableUSR
            self.location = location
        }
    }

    public struct Reference: Hashable, Sendable {
        public let anchor: CallableReferenceSyntax.Anchor
        public let kind: CallableReferenceSyntax.Kind
        public let referenceByteRange: Range<Int>
        public let fullNameArgumentTokens: [SourceToken]
        public let subscriptArguments: [CallSiteSyntax.Argument]
    }

    public struct Issue: Codable, Equatable, Sendable {
        public let callableUSR: String
        public let callableName: String
        public let path: String
        public let line: Int
        public let utf8Column: Int
        public let reason: String
    }

    public struct Report: Codable, Equatable, Sendable {
        public let signatureCountWithNamedExternalLabels: Int
        public let labeledParameterCount: Int
        public let signatureCountWithIndexedReferences: Int
        public let namedParameterCountInSignaturesWithIndexedReferences: Int
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
        public let signatureCountWithAllIndexedReferencesResolved: Int
        public let namedParameterCountInSignaturesWithAllIndexedReferencesResolved: Int
        public let unresolvedByReason: [String: Int]
        public let unresolvedAnchors: [CallableReferenceSyntax.Issue]

        public static let empty = CallableReferenceSyntax.Report(
            signatures: [],
            referencesByAnchor: [:],
            issueReasonsByAnchor: [:]
        )

        init(
            signatures: [CallableSignature],
            referencesByAnchor: [CallableReferenceSyntax.Anchor: CallableReferenceSyntax.Reference],
            issueReasonsByAnchor: [CallableReferenceSyntax.Anchor: String]
        ) {
            let namedParameterCount: (CallableSignature) -> Int = { signature in
                signature.parameters.count { member in
                    if case .named = member.externalLabel {
                        return true
                    }
                    return false
                }
            }
            let signaturesWithReferences = signatures.filter {
                !$0.nonCallReferenceLocations.isEmpty
            }
            let roles = Array(referencesByAnchor.values)

            self.signatureCountWithNamedExternalLabels = signatures.count
            self.labeledParameterCount = signatures.reduce(0) {
                $0 + namedParameterCount($1)
            }
            self.signatureCountWithIndexedReferences = signaturesWithReferences.count
            self.namedParameterCountInSignaturesWithIndexedReferences =
                signaturesWithReferences
                .reduce(0) { $0 + namedParameterCount($1) }
            self.indexedReferenceAnchors = referencesByAnchor.count + issueReasonsByAnchor.count
            self.resolvedReferenceAnchors = referencesByAnchor.count
            self.unresolvedReferenceAnchors = issueReasonsByAnchor.count
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
                count
                    + role.subscriptArguments.count { argument in
                        switch argument {
                        case .parenthesized(label: .some), .additionalTrailingClosure:
                            return true
                        case .parenthesized(label: .none), .firstTrailingClosure:
                            return false
                        }
                    }
            }

            let resolvedAnchors = Set(referencesByAnchor.keys)
            let fullyResolvedSignatures = signaturesWithReferences.filter { signature in
                signature.nonCallReferenceLocations.allSatisfy { location in
                    resolvedAnchors.contains(
                        CallableReferenceSyntax.Anchor(
                            callableUSR: signature.callableUSR,
                            location: location
                        ))
                }
            }
            self.signatureCountWithAllIndexedReferencesResolved = fullyResolvedSignatures.count
            self.namedParameterCountInSignaturesWithAllIndexedReferencesResolved =
                fullyResolvedSignatures.reduce(0) { $0 + namedParameterCount($1) }
            self.unresolvedByReason = Dictionary(
                grouping: issueReasonsByAnchor.values,
                by: { $0 }
            ).mapValues(\.count)
            let callableNamesByUSR = Dictionary(
                uniqueKeysWithValues: signatures.map { ($0.callableUSR, $0.callableName) }
            )
            self.unresolvedAnchors = issueReasonsByAnchor.map { anchor, reason in
                CallableReferenceSyntax.Issue(
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

        private enum CodingKeys: String, CodingKey {
            case signatureCountWithNamedExternalLabels = "componentsWithNamedExternalLabels"
            case labeledParameterCount = "namedExternalLabelParameters"
            case signatureCountWithIndexedReferences = "componentsWithIndexedReferences"
            case namedParameterCountInSignaturesWithIndexedReferences =
                "namedParametersInComponentsWithIndexedReferences"
            case indexedReferenceAnchors
            case resolvedReferenceAnchors
            case unresolvedReferenceAnchors
            case resolvedBareReferences
            case resolvedFullNameReferences
            case fullNameArgumentTokens
            case namedFullNameArgumentTokens
            case resolvedSubscriptCalls
            case subscriptArguments
            case namedSubscriptArgumentLabelTokens
            case signatureCountWithAllIndexedReferencesResolved =
                "componentsWithAllIndexedReferencesResolved"
            case namedParameterCountInSignaturesWithAllIndexedReferencesResolved =
                "namedParametersInComponentsWithAllIndexedReferencesResolved"
            case unresolvedByReason
            case unresolvedAnchors
        }
    }

    public struct Index: Sendable {
        public let referencesByAnchor:
            [CallableReferenceSyntax.Anchor: CallableReferenceSyntax.Reference]
        public let issueReasonsByAnchor: [CallableReferenceSyntax.Anchor: String]
        public let report: CallableReferenceSyntax.Report

        public init(
            signatures: [CallableSignature],
            sourceCache: SourceFileCache
        ) {
            let targetSignatures = signatures.filter { signature in
                signature.ownerCategory != .enumCase
                    && signature.parameters.contains { member in
                        if case .named = member.externalLabel {
                            return true
                        }
                        return false
                    }
            }
            let anchors = Set(
                targetSignatures.flatMap { signature in
                    signature.nonCallReferenceLocations.map {
                        CallableReferenceSyntax.Anchor(
                            callableUSR: signature.callableUSR,
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

            var referencesByAnchor:
                [CallableReferenceSyntax.Anchor: CallableReferenceSyntax.Reference] = [:]
            var issueReasonsByAnchor: [CallableReferenceSyntax.Anchor: String] = [:]
            for anchor in anchors.sorted(by: Self.anchorPrecedes) {
                guard let source = sourceCache.file(for: anchor.location.path) else {
                    issueReasonsByAnchor[anchor] =
                        "indexed callable reference source file unavailable"
                    continue
                }
                guard
                    let byteOffset = source.byteOffset(
                        line: anchor.location.line,
                        utf8Column: anchor.location.utf8Column
                    )
                else {
                    issueReasonsByAnchor[anchor] =
                        "indexed callable reference byte offset unavailable"
                    continue
                }
                let matches = (candidatesByPath[source.path] ?? []).filter {
                    $0.anchorByteRange.contains(byteOffset)
                }
                guard matches.count == 1, let match = matches.first else {
                    issueReasonsByAnchor[anchor] =
                        matches.isEmpty
                        ? "compiler callable reference syntax unavailable at indexed anchor"
                        : "multiple compiler callable references match indexed anchor"
                    continue
                }
                guard match.structuralReasons.isEmpty else {
                    issueReasonsByAnchor[anchor] = match.structuralReasons
                        .sorted()
                        .joined(separator: "; ")
                    continue
                }
                referencesByAnchor[anchor] = CallableReferenceSyntax.Reference(
                    anchor: anchor,
                    kind: match.kind,
                    referenceByteRange: match.referenceByteRange,
                    fullNameArgumentTokens: match.fullNameArgumentTokens,
                    subscriptArguments: match.subscriptArguments
                )
            }

            self.referencesByAnchor = referencesByAnchor
            self.issueReasonsByAnchor = issueReasonsByAnchor
            self.report = CallableReferenceSyntax.Report(
                signatures: targetSignatures,
                referencesByAnchor: referencesByAnchor,
                issueReasonsByAnchor: issueReasonsByAnchor
            )
        }

        private static func anchorPrecedes(
            _ lhs: CallableReferenceSyntax.Anchor,
            _ rhs: CallableReferenceSyntax.Anchor
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

}

private struct CallableReferenceSyntaxCandidate {
    let kind: CallableReferenceSyntax.Kind
    let referenceByteRange: Range<Int>
    let anchorByteRange: Range<Int>
    let fullNameArgumentTokens: [SourceToken]
    let subscriptArguments: [CallSiteSyntax.Argument]
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
        var argumentTokens: [SourceToken] = []
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
        candidates.append(
            CallableReferenceSyntaxCandidate(
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
        candidates.append(
            CallableReferenceSyntaxCandidate(
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
    ) -> (roles: [CallSiteSyntax.Argument], reasons: [String]) {
        var roles: [CallSiteSyntax.Argument] = []
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
        node.positionAfterSkippingLeadingTrivia
            .utf8Offset..<node.endPositionBeforeTrailingTrivia.utf8Offset
    }

    private func sourceToken(_ token: TokenSyntax) -> SourceToken? {
        guard token.presence == .present else {
            return nil
        }
        let rawStart = token.positionAfterSkippingLeadingTrivia.utf8Offset
        if let identifier = source.identifierToken(atByteOffset: rawStart) {
            return SourceToken(
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
        return SourceToken(
            path: source.path,
            name: String(decoding: source.data[rawStart..<rawEnd], as: UTF8.self),
            byteRange: rawStart..<rawEnd
        )
    }
}
