import Foundation
import SwiftParser
import SwiftSyntax

public struct ParameterCallSiteAnchor: Hashable, Sendable {
    public let callableUSR: String
    public let location: IndexedSourceLocation

    public init(callableUSR: String, location: IndexedSourceLocation) {
        self.callableUSR = callableUSR
        self.location = location
    }
}

public enum ParameterCallSyntaxKind: String, Codable, Hashable, Sendable {
    case functionCall
    case subscriptCall
    case attributeCall
    case enumCasePattern
}

public enum ParameterCallArgumentSyntaxRole: Hashable, Sendable {
    case parenthesized(label: SourceTokenRange?)
    case firstTrailingClosure
    case additionalTrailingClosure(label: SourceTokenRange)
}

public struct ParameterCallSiteSyntaxRoles: Hashable, Sendable {
    public let anchor: ParameterCallSiteAnchor
    public let kind: ParameterCallSyntaxKind
    public let callByteRange: Range<Int>
    public let calleeByteRange: Range<Int>
    public let hasExplicitArgumentDelimiters: Bool
    public let allowsOmittedNamedLabels: Bool
    public let arguments: [ParameterCallArgumentSyntaxRole]
}

public struct UnresolvedParameterCallSiteSyntaxFact: Codable, Equatable, Sendable {
    public let callableUSR: String
    public let callableName: String
    public let path: String
    public let line: Int
    public let utf8Column: Int
    public let reason: String
}

public struct ParameterCallSiteSyntaxFactsSummary: Codable, Equatable, Sendable {
    public let componentsWithNamedExternalLabels: Int
    public let namedExternalLabelParameters: Int
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
    public let componentsWithAllIndexedCallsResolved: Int
    public let namedParametersInComponentsWithAllIndexedCallsResolved: Int
    public let componentsWithoutIndexedCalls: Int
    public let namedParametersInComponentsWithoutIndexedCalls: Int
    public let componentsWithNonCallReferences: Int
    public let namedParametersInComponentsWithNonCallReferences: Int
    public let unresolvedByReason: [String: Int]
    public let unresolvedAnchors: [UnresolvedParameterCallSiteSyntaxFact]

    public static let empty = ParameterCallSiteSyntaxFactsSummary(
        components: [],
        rolesByAnchor: [:],
        unresolvedReasonsByAnchor: [:]
    )

    init(
        components: [ParameterRenameComponent],
        rolesByAnchor: [ParameterCallSiteAnchor: ParameterCallSiteSyntaxRoles],
        unresolvedReasonsByAnchor: [ParameterCallSiteAnchor: String]
    ) {
        let namedParameterCount: (ParameterRenameComponent) -> Int = { component in
            component.members.count { member in
                if case .named = member.externalLabel {
                    return true
                }
                return false
            }
        }
        let roles = Array(rolesByAnchor.values)
        self.componentsWithNamedExternalLabels = components.count
        self.namedExternalLabelParameters = components.reduce(0) {
            $0 + namedParameterCount($1)
        }
        self.indexedCallAnchors = rolesByAnchor.count + unresolvedReasonsByAnchor.count
        self.resolvedCallAnchors = rolesByAnchor.count
        self.unresolvedCallAnchors = unresolvedReasonsByAnchor.count
        self.resolvedFunctionCalls = roles.count { $0.kind == .functionCall }
        self.resolvedSubscriptCalls = roles.count { $0.kind == .subscriptCall }
        self.resolvedAttributeCalls = roles.count { $0.kind == .attributeCall }
        self.resolvedEnumCasePatterns = roles.count { $0.kind == .enumCasePattern }
        self.parenthesizedArguments = roles.reduce(0) { count, role in
            count + role.arguments.count {
                if case .parenthesized = $0 { return true }
                return false
            }
        }
        self.namedParenthesizedArgumentTokens = roles.reduce(0) { count, role in
            count + role.arguments.count {
                if case .parenthesized(label: .some) = $0 { return true }
                return false
            }
        }
        self.unlabeledParenthesizedArguments = roles.reduce(0) { count, role in
            count + role.arguments.count {
                if case .parenthesized(label: .none) = $0 { return true }
                return false
            }
        }
        self.firstTrailingClosures = roles.reduce(0) { count, role in
            count + role.arguments.count {
                if case .firstTrailingClosure = $0 { return true }
                return false
            }
        }
        self.additionalTrailingClosureLabelTokens = roles.reduce(0) { count, role in
            count + role.arguments.count {
                if case .additionalTrailingClosure = $0 { return true }
                return false
            }
        }
        self.callsWithoutExplicitArgumentDelimiters = roles.count {
            !$0.hasExplicitArgumentDelimiters
        }

        let resolvedAnchors = Set(rolesByAnchor.keys)
        let componentsWithCalls = components.filter {
            !$0.externalLabelArgumentLocations.isEmpty
        }
        let fullyResolvedComponents = componentsWithCalls.filter { component in
            component.externalLabelArgumentLocations.allSatisfy { location in
                resolvedAnchors.contains(ParameterCallSiteAnchor(
                    callableUSR: component.callableUSR,
                    location: location
                ))
            }
        }
        self.componentsWithAllIndexedCallsResolved = fullyResolvedComponents.count
        self.namedParametersInComponentsWithAllIndexedCallsResolved = fullyResolvedComponents
            .reduce(0) { $0 + namedParameterCount($1) }

        let componentsWithoutCalls = components.filter {
            $0.externalLabelArgumentLocations.isEmpty
        }
        self.componentsWithoutIndexedCalls = componentsWithoutCalls.count
        self.namedParametersInComponentsWithoutIndexedCalls = componentsWithoutCalls
            .reduce(0) { $0 + namedParameterCount($1) }

        let componentsWithReferences = components.filter {
            !$0.nonCallReferenceLocations.isEmpty
        }
        self.componentsWithNonCallReferences = componentsWithReferences.count
        self.namedParametersInComponentsWithNonCallReferences = componentsWithReferences
            .reduce(0) { $0 + namedParameterCount($1) }
        self.unresolvedByReason = Dictionary(
            grouping: unresolvedReasonsByAnchor.values,
            by: { $0 }
        ).mapValues(\.count)
        let callableNamesByUSR = Dictionary(
            uniqueKeysWithValues: components.map { ($0.callableUSR, $0.callableName) }
        )
        self.unresolvedAnchors = unresolvedReasonsByAnchor.map { anchor, reason in
            UnresolvedParameterCallSiteSyntaxFact(
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

public struct ParameterCallSiteSyntaxFacts: Sendable {
    public let rolesByAnchor: [ParameterCallSiteAnchor: ParameterCallSiteSyntaxRoles]
    public let unresolvedReasonsByAnchor: [ParameterCallSiteAnchor: String]
    public let summary: ParameterCallSiteSyntaxFactsSummary

    public init(
        components: [ParameterRenameComponent],
        sourceCache: SourceFileCache
    ) {
        let targetComponents = components.filter { component in
            component.members.contains { member in
                if case .named = member.externalLabel {
                    return true
                }
                return false
            }
        }
        let anchors = Set(targetComponents.flatMap { component in
            component.externalLabelArgumentLocations.map {
                ParameterCallSiteAnchor(callableUSR: component.callableUSR, location: $0)
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

        var rolesByAnchor: [ParameterCallSiteAnchor: ParameterCallSiteSyntaxRoles] = [:]
        var unresolvedReasonsByAnchor: [ParameterCallSiteAnchor: String] = [:]
        for anchor in anchors.sorted(by: Self.anchorPrecedes) {
            guard let source = sourceCache.file(for: anchor.location.path) else {
                unresolvedReasonsByAnchor[anchor] = "indexed call source file unavailable"
                continue
            }
            guard let byteOffset = source.byteOffset(
                line: anchor.location.line,
                utf8Column: anchor.location.utf8Column
            ) else {
                unresolvedReasonsByAnchor[anchor] = "indexed call byte offset unavailable"
                continue
            }
            let matches = (candidatesByPath[source.path] ?? []).compactMap { candidate -> (
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
                unresolvedReasonsByAnchor[anchor] =
                    "compiler call syntax unavailable at indexed call anchor"
                continue
            }
            let closestMatches = matches.filter { $0.matchingSpan == shortestSpan }
            guard closestMatches.count == 1, let match = closestMatches.first else {
                unresolvedReasonsByAnchor[anchor] =
                    "multiple compiler calls match indexed call anchor"
                continue
            }
            guard match.candidate.structuralReasons.isEmpty else {
                unresolvedReasonsByAnchor[anchor] =
                    match.candidate.structuralReasons.sorted().joined(separator: "; ")
                continue
            }
            rolesByAnchor[anchor] = ParameterCallSiteSyntaxRoles(
                anchor: anchor,
                kind: match.candidate.kind,
                callByteRange: match.candidate.callByteRange,
                calleeByteRange: match.candidate.calleeByteRange,
                hasExplicitArgumentDelimiters:
                    match.candidate.hasExplicitArgumentDelimiters,
                allowsOmittedNamedLabels:
                    match.candidate.allowsOmittedNamedLabels,
                arguments: match.candidate.arguments
            )
        }

        self.rolesByAnchor = rolesByAnchor
        self.unresolvedReasonsByAnchor = unresolvedReasonsByAnchor
        self.summary = ParameterCallSiteSyntaxFactsSummary(
            components: targetComponents,
            rolesByAnchor: rolesByAnchor,
            unresolvedReasonsByAnchor: unresolvedReasonsByAnchor
        )
    }

    private static func anchorPrecedes(
        _ lhs: ParameterCallSiteAnchor,
        _ rhs: ParameterCallSiteAnchor
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

private struct CallSyntaxCandidate {
    let kind: ParameterCallSyntaxKind
    let callByteRange: Range<Int>
    let calleeByteRange: Range<Int>
    let anchorByteRanges: [Range<Int>]
    let hasExplicitArgumentDelimiters: Bool
    let allowsOmittedNamedLabels: Bool
    let arguments: [ParameterCallArgumentSyntaxRole]
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
        let omitsEntireEnumPayload = isExpressionPattern
            && node.leftParen == nil
            && node.rightParen == nil
            && arguments.roles.isEmpty
        candidates.append(CallSyntaxCandidate(
            kind: omitsEntireEnumPayload ? .enumCasePattern : .functionCall,
            callByteRange: syntaxRange(node),
            calleeByteRange: syntaxRange(node.calledExpression),
            anchorByteRanges: [syntaxRange(node.calledExpression)],
            hasExplicitArgumentDelimiters: node.leftParen != nil && node.rightParen != nil,
            allowsOmittedNamedLabels: isExpressionPattern,
            arguments: arguments.roles,
            structuralReasons: arguments.reasons
        ))
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.parent?.as(ExpressionPatternSyntax.self) != nil,
              node.declName.argumentNames == nil,
              let caseToken = sourceToken(node.declName.baseName) else {
            return .visitChildren
        }
        candidates.append(CallSyntaxCandidate(
            kind: .enumCasePattern,
            callByteRange: syntaxRange(node),
            calleeByteRange: syntaxRange(node),
            anchorByteRanges: [caseToken.byteRange],
            hasExplicitArgumentDelimiters: false,
            allowsOmittedNamedLabels: true,
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
        candidates.append(CallSyntaxCandidate(
            kind: .subscriptCall,
            callByteRange: syntaxRange(node),
            calleeByteRange: syntaxRange(node.calledExpression),
            anchorByteRanges: [
                syntaxRange(node.calledExpression),
                syntaxRange(node.leftSquare)
            ],
            hasExplicitArgumentDelimiters: true,
            allowsOmittedNamedLabels: false,
            arguments: arguments.roles,
            structuralReasons: arguments.reasons
        ))
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        guard let rawArguments = node.arguments,
              case .argumentList(let argumentList) = rawArguments else {
            return .visitChildren
        }
        let arguments = argumentRoles(
            parenthesized: argumentList,
            trailingClosure: nil,
            additionalTrailingClosures: []
        )
        candidates.append(CallSyntaxCandidate(
            kind: .attributeCall,
            callByteRange: syntaxRange(node),
            calleeByteRange: syntaxRange(node.attributeName),
            anchorByteRanges: [syntaxRange(node.attributeName)],
            hasExplicitArgumentDelimiters: node.leftParen != nil && node.rightParen != nil,
            allowsOmittedNamedLabels: false,
            arguments: arguments.roles,
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
        node.positionAfterSkippingLeadingTrivia.utf8Offset
            ..< node.endPositionBeforeTrailingTrivia.utf8Offset
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
