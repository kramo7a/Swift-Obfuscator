import Foundation
import SwiftParser
import SwiftSyntax

public enum CallSiteSyntax {}

extension CallSiteSyntax {
    public struct Anchor: Hashable, Sendable {
        public let callableUSR: String
        public let location: IndexSnapshot.Location

        public init(callableUSR: String, location: IndexSnapshot.Location) {
            self.callableUSR = callableUSR
            self.location = location
        }
    }

    public enum Kind: String, Codable, Hashable, Sendable {
        case functionCall
        case subscriptCall
        case attributeCall
        case enumCasePattern
    }

    public enum Argument: Hashable, Sendable {
        case parenthesized(label: SourceToken?)
        case firstTrailingClosure
        case additionalTrailingClosure(label: SourceToken)
    }

    public struct Call: Hashable, Sendable {
        public let anchor: CallSiteSyntax.Anchor
        public let kind: CallSiteSyntax.Kind
        public let callByteRange: Range<Int>
        public let calleeByteRange: Range<Int>
        public let hasExplicitArgumentDelimiters: Bool
        public let canOmitNamedLabels: Bool
        public let arguments: [CallSiteSyntax.Argument]
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
        public let indexedCallAnchors: Int
        public let resolvedCallAnchors: Int
        public let unresolvedCallAnchors: Int
        public let resolvedFunctionCalls: Int
        public let resolvedSubscriptCalls: Int
        public let resolvedAttributeCalls: Int
        public let resolvedEnumCasePatterns: Int
        public let parenthesizedArguments: Int
        public let namedParenthesizedArgumentTokens: Int
        public let unlabeledParenthesizedArguments: Int
        public let firstTrailingClosures: Int
        public let additionalTrailingClosureLabelTokens: Int
        public let callsWithoutExplicitArgumentDelimiters: Int
        public let signatureCountWithAllIndexedCallsResolved: Int
        public let namedParameterCountInSignaturesWithAllIndexedCallsResolved: Int
        public let signatureCountWithoutIndexedCalls: Int
        public let namedParameterCountInSignaturesWithoutIndexedCalls: Int
        public let signatureCountWithNonCallReferences: Int
        public let namedParameterCountInSignaturesWithNonCallReferences: Int
        public let unresolvedByReason: [String: Int]
        public let unresolvedAnchors: [CallSiteSyntax.Issue]

        public static let empty = CallSiteSyntax.Report(
            signatures: [],
            callsByAnchor: [:],
            issueReasonsByAnchor: [:]
        )

        init(
            signatures: [CallableSignature],
            callsByAnchor: [CallSiteSyntax.Anchor: CallSiteSyntax.Call],
            issueReasonsByAnchor: [CallSiteSyntax.Anchor: String]
        ) {
            let namedParameterCount: (CallableSignature) -> Int = { signature in
                signature.parameters.count { member in
                    if case .named = member.externalLabel {
                        return true
                    }
                    return false
                }
            }
            let roles = Array(callsByAnchor.values)
            self.signatureCountWithNamedExternalLabels = signatures.count
            self.labeledParameterCount = signatures.reduce(0) {
                $0 + namedParameterCount($1)
            }
            self.indexedCallAnchors = callsByAnchor.count + issueReasonsByAnchor.count
            self.resolvedCallAnchors = callsByAnchor.count
            self.unresolvedCallAnchors = issueReasonsByAnchor.count
            self.resolvedFunctionCalls = roles.count { $0.kind == .functionCall }
            self.resolvedSubscriptCalls = roles.count { $0.kind == .subscriptCall }
            self.resolvedAttributeCalls = roles.count { $0.kind == .attributeCall }
            self.resolvedEnumCasePatterns = roles.count { $0.kind == .enumCasePattern }
            self.parenthesizedArguments = roles.reduce(0) { count, role in
                count
                    + role.arguments.count {
                        if case .parenthesized = $0 { return true }
                        return false
                    }
            }
            self.namedParenthesizedArgumentTokens = roles.reduce(0) { count, role in
                count
                    + role.arguments.count {
                        if case .parenthesized(label: .some) = $0 { return true }
                        return false
                    }
            }
            self.unlabeledParenthesizedArguments = roles.reduce(0) { count, role in
                count
                    + role.arguments.count {
                        if case .parenthesized(label: .none) = $0 { return true }
                        return false
                    }
            }
            self.firstTrailingClosures = roles.reduce(0) { count, role in
                count
                    + role.arguments.count {
                        if case .firstTrailingClosure = $0 { return true }
                        return false
                    }
            }
            self.additionalTrailingClosureLabelTokens = roles.reduce(0) { count, role in
                count
                    + role.arguments.count {
                        if case .additionalTrailingClosure = $0 { return true }
                        return false
                    }
            }
            self.callsWithoutExplicitArgumentDelimiters = roles.count {
                !$0.hasExplicitArgumentDelimiters
            }

            let resolvedAnchors = Set(callsByAnchor.keys)
            let signaturesWithCalls = signatures.filter {
                !$0.externalLabelArgumentLocations.isEmpty
            }
            let fullyResolvedSignatures = signaturesWithCalls.filter { signature in
                signature.externalLabelArgumentLocations.allSatisfy { location in
                    resolvedAnchors.contains(
                        CallSiteSyntax.Anchor(
                            callableUSR: signature.callableUSR,
                            location: location
                        ))
                }
            }
            self.signatureCountWithAllIndexedCallsResolved = fullyResolvedSignatures.count
            self.namedParameterCountInSignaturesWithAllIndexedCallsResolved =
                fullyResolvedSignatures
                .reduce(0) { $0 + namedParameterCount($1) }

            let signaturesWithoutCalls = signatures.filter {
                $0.externalLabelArgumentLocations.isEmpty
            }
            self.signatureCountWithoutIndexedCalls = signaturesWithoutCalls.count
            self.namedParameterCountInSignaturesWithoutIndexedCalls =
                signaturesWithoutCalls
                .reduce(0) { $0 + namedParameterCount($1) }

            let signaturesWithReferences = signatures.filter {
                !$0.nonCallReferenceLocations.isEmpty
            }
            self.signatureCountWithNonCallReferences = signaturesWithReferences.count
            self.namedParameterCountInSignaturesWithNonCallReferences =
                signaturesWithReferences
                .reduce(0) { $0 + namedParameterCount($1) }
            self.unresolvedByReason = Dictionary(
                grouping: issueReasonsByAnchor.values,
                by: { $0 }
            ).mapValues(\.count)
            let callableNamesByUSR = Dictionary(
                uniqueKeysWithValues: signatures.map { ($0.callableUSR, $0.callableName) }
            )
            self.unresolvedAnchors = issueReasonsByAnchor.map { anchor, reason in
                CallSiteSyntax.Issue(
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
            case indexedCallAnchors
            case resolvedCallAnchors
            case unresolvedCallAnchors
            case resolvedFunctionCalls
            case resolvedSubscriptCalls
            case resolvedAttributeCalls
            case resolvedEnumCasePatterns
            case parenthesizedArguments
            case namedParenthesizedArgumentTokens
            case unlabeledParenthesizedArguments
            case firstTrailingClosures
            case additionalTrailingClosureLabelTokens
            case callsWithoutExplicitArgumentDelimiters
            case signatureCountWithAllIndexedCallsResolved =
                "componentsWithAllIndexedCallsResolved"
            case namedParameterCountInSignaturesWithAllIndexedCallsResolved =
                "namedParametersInComponentsWithAllIndexedCallsResolved"
            case signatureCountWithoutIndexedCalls = "componentsWithoutIndexedCalls"
            case namedParameterCountInSignaturesWithoutIndexedCalls =
                "namedParametersInComponentsWithoutIndexedCalls"
            case signatureCountWithNonCallReferences = "componentsWithNonCallReferences"
            case namedParameterCountInSignaturesWithNonCallReferences =
                "namedParametersInComponentsWithNonCallReferences"
            case unresolvedByReason
            case unresolvedAnchors
        }
    }

    public struct Index: Sendable {
        public let callsByAnchor: [CallSiteSyntax.Anchor: CallSiteSyntax.Call]
        public let issueReasonsByAnchor: [CallSiteSyntax.Anchor: String]
        public let report: CallSiteSyntax.Report

        public init(
            signatures: [CallableSignature],
            sourceCache: SourceFileCache
        ) {
            let targetSignatures = signatures.filter { signature in
                signature.parameters.contains { member in
                    if case .named = member.externalLabel {
                        return true
                    }
                    return false
                }
            }
            let anchors = Set(
                targetSignatures.flatMap { signature in
                    signature.externalLabelArgumentLocations.map {
                        CallSiteSyntax.Anchor(callableUSR: signature.callableUSR, location: $0)
                    }
                })
            let anchorPaths = Set(anchors.map { $0.location.path })
            var candidatesByPath: [String: [CallSyntaxCandidate]] = [:]
            for path in anchorPaths.sorted() {
                guard let source = sourceCache.file(for: path) else {
                    continue
                }
                let tree = Parser.parse(source: String(decoding: source.data, as: UTF8.self))
                let visitor = ParameterCallSyntaxVisitor(source: source)
                visitor.walk(tree)
                candidatesByPath[path] = visitor.candidates
            }

            var callsByAnchor: [CallSiteSyntax.Anchor: CallSiteSyntax.Call] = [:]
            var issueReasonsByAnchor: [CallSiteSyntax.Anchor: String] = [:]
            for anchor in anchors.sorted(by: Self.anchorPrecedes) {
                guard let source = sourceCache.file(for: anchor.location.path) else {
                    issueReasonsByAnchor[anchor] = "indexed call source file unavailable"
                    continue
                }
                guard
                    let byteOffset = source.byteOffset(
                        line: anchor.location.line,
                        utf8Column: anchor.location.utf8Column
                    )
                else {
                    issueReasonsByAnchor[anchor] = "indexed call byte offset unavailable"
                    continue
                }
                let matches = (candidatesByPath[source.path] ?? []).compactMap {
                    candidate -> (
                        candidate: CallSyntaxCandidate,
                        matchingSpan: Int
                    )? in
                    let spans = candidate.anchorByteRanges.compactMap { range in
                        range.contains(byteOffset) ? range.count : nil
                    }
                    guard let matchingSpan = spans.min() else {
                        return nil
                    }
                    return (candidate, matchingSpan)
                }
                guard let shortestSpan = matches.map(\.matchingSpan).min() else {
                    issueReasonsByAnchor[anchor] =
                        "compiler call syntax unavailable at indexed call anchor"
                    continue
                }
                let closestMatches = matches.filter { $0.matchingSpan == shortestSpan }
                guard closestMatches.count == 1, let match = closestMatches.first else {
                    issueReasonsByAnchor[anchor] =
                        "multiple compiler calls match indexed call anchor"
                    continue
                }
                guard match.candidate.structuralReasons.isEmpty else {
                    issueReasonsByAnchor[anchor] =
                        match.candidate.structuralReasons.sorted().joined(separator: "; ")
                    continue
                }
                callsByAnchor[anchor] = CallSiteSyntax.Call(
                    anchor: anchor,
                    kind: match.candidate.kind,
                    callByteRange: match.candidate.callByteRange,
                    calleeByteRange: match.candidate.calleeByteRange,
                    hasExplicitArgumentDelimiters:
                        match.candidate.hasExplicitArgumentDelimiters,
                    canOmitNamedLabels:
                        match.candidate.canOmitNamedLabels,
                    arguments: match.candidate.arguments
                )
            }

            self.callsByAnchor = callsByAnchor
            self.issueReasonsByAnchor = issueReasonsByAnchor
            self.report = CallSiteSyntax.Report(
                signatures: targetSignatures,
                callsByAnchor: callsByAnchor,
                issueReasonsByAnchor: issueReasonsByAnchor
            )
        }

        private static func anchorPrecedes(
            _ lhs: CallSiteSyntax.Anchor,
            _ rhs: CallSiteSyntax.Anchor
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

private struct CallSyntaxCandidate {
    let kind: CallSiteSyntax.Kind
    let callByteRange: Range<Int>
    let calleeByteRange: Range<Int>
    let anchorByteRanges: [Range<Int>]
    let hasExplicitArgumentDelimiters: Bool
    let canOmitNamedLabels: Bool
    let arguments: [CallSiteSyntax.Argument]
    let structuralReasons: [String]
}

private final class ParameterCallSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var candidates: [CallSyntaxCandidate] = []

    init(source: SourceFile) {
        self.source = source
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let arguments = argumentRoles(
            parenthesized: node.arguments,
            trailingClosure: node.trailingClosure,
            additionalTrailingClosures: node.additionalTrailingClosures
        )
        let isExpressionPattern = isInsideExpressionPattern(node)
        let omitsEntireEnumPayload =
            isExpressionPattern
            && node.leftParen == nil
            && node.rightParen == nil
            && arguments.roles.isEmpty
        candidates.append(
            CallSyntaxCandidate(
                kind: omitsEntireEnumPayload ? .enumCasePattern : .functionCall,
                callByteRange: syntaxRange(node),
                calleeByteRange: syntaxRange(node.calledExpression),
                anchorByteRanges: [syntaxRange(node.calledExpression)],
                hasExplicitArgumentDelimiters: node.leftParen != nil && node.rightParen != nil,
                canOmitNamedLabels: isExpressionPattern,
                arguments: arguments.roles,
                structuralReasons: arguments.reasons
            ))
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.parent?.as(ExpressionPatternSyntax.self) != nil,
            node.declName.argumentNames == nil,
            let caseToken = sourceToken(node.declName.baseName)
        else {
            return .visitChildren
        }
        candidates.append(
            CallSyntaxCandidate(
                kind: .enumCasePattern,
                callByteRange: syntaxRange(node),
                calleeByteRange: syntaxRange(node),
                anchorByteRanges: [caseToken.byteRange],
                hasExplicitArgumentDelimiters: false,
                canOmitNamedLabels: true,
                arguments: [],
                structuralReasons: []
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
            CallSyntaxCandidate(
                kind: .subscriptCall,
                callByteRange: syntaxRange(node),
                calleeByteRange: syntaxRange(node.calledExpression),
                anchorByteRanges: [
                    syntaxRange(node.calledExpression),
                    syntaxRange(node.leftSquare),
                ],
                hasExplicitArgumentDelimiters: true,
                canOmitNamedLabels: false,
                arguments: arguments.roles,
                structuralReasons: arguments.reasons
            ))
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        guard let rawArguments = node.arguments,
            case .argumentList(let argumentList) = rawArguments
        else {
            return .visitChildren
        }
        let arguments = argumentRoles(
            parenthesized: argumentList,
            trailingClosure: nil,
            additionalTrailingClosures: []
        )
        candidates.append(
            CallSyntaxCandidate(
                kind: .attributeCall,
                callByteRange: syntaxRange(node),
                calleeByteRange: syntaxRange(node.attributeName),
                anchorByteRanges: [syntaxRange(node.attributeName)],
                hasExplicitArgumentDelimiters: node.leftParen != nil && node.rightParen != nil,
                canOmitNamedLabels: false,
                arguments: arguments.roles,
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
                    reasons.append("compiler call argument label token unavailable")
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
                reasons.append("compiler trailing-closure label token unavailable")
            }
        }
        return (roles, Array(Set(reasons)).sorted())
    }

    private func syntaxRange(_ node: some SyntaxProtocol) -> Range<Int> {
        node.positionAfterSkippingLeadingTrivia
            .utf8Offset..<node.endPositionBeforeTrailingTrivia.utf8Offset
    }

    private func isInsideExpressionPattern(_ node: some SyntaxProtocol) -> Bool {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if current.as(ExpressionPatternSyntax.self) != nil {
                return true
            }
            ancestor = current.parent
        }
        return false
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
