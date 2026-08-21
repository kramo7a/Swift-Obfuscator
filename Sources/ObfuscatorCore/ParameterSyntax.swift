import Foundation
import SwiftParser
import SwiftSyntax

public struct SourceToken: Codable, Hashable, Sendable {
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

public enum ParameterSyntax {}
public enum LocalBindingRename {}

extension ParameterSyntax {
    public enum DeclarationKind: String, Codable, Hashable, Sendable {
        case function
        case initializer
        case subscriptDeclaration
        case enumCase
        case accessor
        case closure
    }

    public enum LabelRole: Hashable, Sendable {
        case none
        case omitted(SourceToken)
        case named(SourceToken)

        public var token: SourceToken? {
            switch self {
            case .none:
                return nil
            case .omitted(let token), .named(let token):
                return token
            }
        }
    }

    public enum TrailingClosureSupport: String, Codable, Hashable, Sendable {
        case definitelyCallable
        case definitelyNonCallable
        case unknown
    }

    public struct Parameter: Hashable, Sendable {
        public let parameterUSR: String
        public let kind: ParameterSyntax.DeclarationKind
        public let indexedDeclarationAnchor: SourceToken
        public let externalLabel: ParameterSyntax.LabelRole
        public let localBinding: SourceToken?
        public let hasDefaultValue: Bool
        public let isVariadic: Bool
        public let trailingClosureCompatibility: ParameterSyntax.TrailingClosureSupport
        public let localBindingReferences: [SourceToken]
        public let coordinatedShorthandBindingDeclarations: [SourceToken]
        public let coordinatedShorthandBindingReferences: [SourceToken]
        public let shadowingBindingDeclarations: [SourceToken]
        public let implicitShadowingBindingNames: Set<String>
        public let syntaxOwnerToken: SourceToken?
        public let indexedOwnerUSR: String?
        public let hasMatchingIndexedOwner: Bool

        public var hasSharedLabelAndBindingToken: Bool {
            guard let label = externalLabel.token, let localBinding else {
                return false
            }
            return label.byteRange == localBinding.byteRange
                && label.path == localBinding.path
        }

        public var isNestedLocalFunctionParameter: Bool {
            kind == .function && !hasMatchingIndexedOwner
        }

        public var localBindingTokens: [SourceToken] {
            let declaration = localBinding.map { [$0] } ?? []
            return Array(
                Set(
                    declaration
                        + localBindingReferences
                        + coordinatedShorthandBindingDeclarations
                        + coordinatedShorthandBindingReferences
                )
            ).sorted {
                ($0.path, $0.byteRange.lowerBound) < ($1.path, $1.byteRange.lowerBound)
            }
        }
    }

    public struct Report: Codable, Equatable, Sendable {
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
        public let definitelyCallableParameters: Int
        public let definitelyNonCallableParameters: Int
        public let parametersWithUnknownCallability: Int
        public let sharedLabelAndBindingTokens: Int
        public let distinctLabelAndBindingTokens: Int
        public let localBindingReferenceTokens: Int
        public let parametersWithCoordinatedShorthandBindings: Int
        public let coordinatedShorthandBindingDeclarations: Int
        public let coordinatedShorthandBindingReferenceTokens: Int
        public let parametersWithShadowingBindingDeclarations: Int
        public let unresolvedShadowingBindingKinds: [String: Int]
        public let localBindingOnlyCoverageCandidates: Int
        public let parametersRequiringExternalLabelCoordination: Int
        public let nonEnumParametersWithoutLocalBindings: Int
        public let enumCaseParametersExcludedFromParameterStage: Int
        public let unresolvedByReason: [String: Int]

        public static let empty = ParameterSyntax.Report(
            explicitParameters: 0,
            parametersByUSR: [:],
            issueReasonsByUSR: [:]
        )

        init(
            explicitParameters: Int,
            parametersByUSR: [String: ParameterSyntax.Parameter],
            shadowingBindingKindsByUSR: [String: [String]] = [:],
            issueReasonsByUSR: [String: String]
        ) {
            let roles = Array(parametersByUSR.values)
            self.explicitParameters = explicitParameters
            self.resolvedParameters = roles.count
            self.unresolvedParameters = max(0, explicitParameters - roles.count)
            self.functionParameters = roles.count { $0.kind == .function }
            self.initializerParameters = roles.count { $0.kind == .initializer }
            self.subscriptParameters = roles.count { $0.kind == .subscriptDeclaration }
            self.enumCaseParameters = roles.count { $0.kind == .enumCase }
            self.accessorBindings = roles.count { $0.kind == .accessor }
            self.closureParameters = roles.count { $0.kind == .closure }
            self.nestedLocalFunctionParameters = roles.count(
                where: \.isNestedLocalFunctionParameter)
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
            self.definitelyCallableParameters = roles.count {
                $0.trailingClosureCompatibility == .definitelyCallable
            }
            self.definitelyNonCallableParameters = roles.count {
                $0.trailingClosureCompatibility == .definitelyNonCallable
            }
            self.parametersWithUnknownCallability = roles.count {
                $0.trailingClosureCompatibility == .unknown
            }
            self.sharedLabelAndBindingTokens = roles.count(where: \.hasSharedLabelAndBindingToken)
            self.distinctLabelAndBindingTokens = roles.count {
                $0.externalLabel.token != nil
                    && $0.localBinding != nil
                    && !$0.hasSharedLabelAndBindingToken
            }
            self.localBindingReferenceTokens = roles.reduce(0) {
                $0 + $1.localBindingReferences.count
            }
            self.parametersWithCoordinatedShorthandBindings = roles.count {
                !$0.coordinatedShorthandBindingDeclarations.isEmpty
            }
            self.coordinatedShorthandBindingDeclarations = roles.reduce(0) {
                $0 + $1.coordinatedShorthandBindingDeclarations.count
            }
            self.coordinatedShorthandBindingReferenceTokens = roles.reduce(0) {
                $0 + $1.coordinatedShorthandBindingReferences.count
            }
            self.parametersWithShadowingBindingDeclarations = roles.count {
                !$0.shadowingBindingDeclarations.isEmpty
                    || !$0.implicitShadowingBindingNames.isEmpty
            }
            var unresolvedShadowingBindingKinds: [String: Int] = [:]
            for kinds in shadowingBindingKindsByUSR.values {
                for kind in Set(kinds) {
                    unresolvedShadowingBindingKinds[kind, default: 0] += 1
                }
            }
            self.unresolvedShadowingBindingKinds = unresolvedShadowingBindingKinds
            self.localBindingOnlyCoverageCandidates = roles.count {
                ParameterSyntax.Index.isLocalBindingOnlyCoverageCandidate($0)
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
                grouping: issueReasonsByUSR.values,
                by: { $0 }
            ).mapValues(\.count)
        }
    }

}

extension LocalBindingRename {
    public struct Report: Codable, Equatable, Sendable {
        public let candidateCount: Int
        public let renamedCount: Int
        public let rejectedCount: Int
        public let unclassifiedCount: Int
        public let rejectionCategories: [CoverageRejectionSummary]
        public let rejectedCandidateUSRs: [String]

        public static let empty = LocalBindingRename.Report(
            candidateCount: 0,
            renamedCount: 0,
            rejectedCount: 0,
            unclassifiedCount: 0,
            rejectionCategories: [],
            rejectedCandidateUSRs: []
        )

        private init(
            candidateCount: Int,
            renamedCount: Int,
            rejectedCount: Int,
            unclassifiedCount: Int,
            rejectionCategories: [CoverageRejectionSummary],
            rejectedCandidateUSRs: [String]
        ) {
            self.candidateCount = candidateCount
            self.renamedCount = renamedCount
            self.rejectedCount = rejectedCount
            self.unclassifiedCount = unclassifiedCount
            self.rejectionCategories = rejectionCategories
            self.rejectedCandidateUSRs = rejectedCandidateUSRs
        }

        init(
            candidateUSRs: Set<String>,
            renames: [RenamePlan.Entry],
            rejections: [RenameEligibility],
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup]
        ) {
            let renamedUSRs = Set(renames.map(\.usr)).intersection(candidateUSRs)
            let decisionsByUSR = Dictionary(uniqueKeysWithValues: rejections.map { ($0.usr, $0) })
            let rejectedUSRs = candidateUSRs.intersection(decisionsByUSR.keys)
            var categoryCounts: [CoverageRejectionCategory: Int] = [:]
            for usr in rejectedUSRs {
                guard let decision = decisionsByUSR[usr] else {
                    continue
                }
                let categories = CoverageAnalyzer.rejectionCategories(
                    for: decision,
                    group: groupsByUSR[usr]
                ).subtracting([.parameter])
                for category in categories.isEmpty ? [.other] : categories {
                    categoryCounts[category, default: 0] += 1
                }
            }

            self.candidateCount = candidateUSRs.count
            self.renamedCount = renamedUSRs.count
            self.rejectedCount = rejectedUSRs.count
            self.unclassifiedCount =
                candidateUSRs.subtracting(renamedUSRs).subtracting(rejectedUSRs).count
            self.rejectionCategories = categoryCounts.map {
                CoverageRejectionSummary(category: $0.key, members: $0.value)
            }.sorted {
                $0.members == $1.members
                    ? $0.category.rawValue < $1.category.rawValue
                    : $0.members > $1.members
            }
            self.rejectedCandidateUSRs = rejectedUSRs.sorted()
        }

        private enum CodingKeys: String, CodingKey {
            case candidateCount = "candidates"
            case renamedCount = "renamed"
            case rejectedCount = "denied"
            case unclassifiedCount = "unclassified"
            case rejectionCategories = "denialCategories"
            case rejectedCandidateUSRs = "deniedCandidateUSRs"
        }
    }

}

extension ParameterSyntax {
    public struct Index: Sendable {
        public let parametersByUSR: [String: ParameterSyntax.Parameter]
        public let localBindingCandidateUSRs: Set<String>
        public let shadowingBindingKindsByUSR: [String: [String]]
        public let issueReasonsByUSR: [String: String]
        public let report: ParameterSyntax.Report

        public init(
            snapshot: IndexSnapshot,
            sourceCache: SourceFileCache,
            obfuscationRoots: [URL]
        ) {
            let rootPaths = obfuscationRoots.map {
                $0.resolvingSymlinksInPath().standardizedFileURL.path
            }
            let parameterDeclarations = snapshot.occurrences.filter { occurrence in
                occurrence.symbol.isKind(.parameter)
                    && !occurrence.hasRole(.implicit)
                    && (occurrence.hasRole(.declaration)
                        || occurrence.hasRole(.definition))
                    && Self.isPath(occurrence.path, underRootPaths: rootPaths)
            }
            let declarationsByUSR = Dictionary(grouping: parameterDeclarations, by: \.usr)
            let occurrencesByUSR = Dictionary(grouping: snapshot.occurrences, by: \.usr)
            let declarationPaths = Set(
                parameterDeclarations.map {
                    SourcePathNormalizer.canonicalPath($0.path)
                })

            var candidatesByPathAndOffset: [String: [Int: [ParameterSyntaxCandidate]]] = [:]
            var nominalTypeAnchors: Set<IndexedByteAnchor> = []
            for path in declarationPaths.sorted() {
                guard let source = sourceCache.file(for: path) else {
                    continue
                }
                let tree = Parser.parse(source: String(decoding: source.data, as: UTF8.self))
                let visitor = ParameterSyntaxVisitor(source: source)
                visitor.walk(tree)
                visitor.resolveLocalBindingReferences()
                nominalTypeAnchors.formUnion(
                    visitor.candidates.compactMap { candidate in
                        candidate.nominalTypeAnchor.map {
                            IndexedByteAnchor(path: $0.path, byteOffset: $0.byteRange.lowerBound)
                        }
                    })
                candidatesByPathAndOffset[path] = Dictionary(
                    grouping: visitor.candidates,
                    by: { $0.indexedAnchor.byteRange.lowerBound }
                )
            }

            var symbolKindsByNominalTypeAnchor: [IndexedByteAnchor: Set<String>] = [:]
            for occurrence in snapshot.occurrences where occurrence.hasRole(.reference) {
                guard let source = sourceCache.file(for: occurrence.path),
                    let byteOffset = source.byteOffset(
                        line: occurrence.line,
                        utf8Column: occurrence.utf8Column
                    )
                else {
                    continue
                }
                let anchor = IndexedByteAnchor(path: source.path, byteOffset: byteOffset)
                guard nominalTypeAnchors.contains(anchor) else {
                    continue
                }
                symbolKindsByNominalTypeAnchor[anchor, default: []].insert(
                    occurrence.symbol.kind
                )
            }

            var parametersByUSR: [String: ParameterSyntax.Parameter] = [:]
            var shadowingBindingKindsByUSR: [String: [String]] = [:]
            var issueReasonsByUSR: [String: String] = [:]
            for usr in declarationsByUSR.keys.sorted() {
                let declarations = declarationsByUSR[usr] ?? []
                let declarationAnchors = Set(
                    declarations.compactMap { occurrence -> IndexedParameterAnchor? in
                        guard let source = sourceCache.file(for: occurrence.path),
                            let byteOffset = source.byteOffset(
                                line: occurrence.line,
                                utf8Column: occurrence.utf8Column
                            )
                        else {
                            return nil
                        }
                        let token = source.identifierToken(atByteOffset: byteOffset).map {
                            SourceToken(
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
                guard declarationAnchors.count == 1,
                    let declarationAnchor = declarationAnchors.first
                else {
                    issueReasonsByUSR[usr] =
                        declarationAnchors.isEmpty
                        ? "indexed declaration anchor unavailable"
                        : "indexed declaration anchor is ambiguous"
                    continue
                }
                let candidatesAtOffset =
                    candidatesByPathAndOffset[declarationAnchor.path]
                    .flatMap { $0[declarationAnchor.byteOffset] } ?? []
                let candidates = candidatesAtOffset.filter {
                    declarationAnchor.token == nil
                        || $0.indexedAnchor.byteRange == declarationAnchor.token?.byteRange
                }
                guard candidates.count == 1, let candidate = candidates.first else {
                    issueReasonsByUSR[usr] =
                        candidates.isEmpty
                        ? "compiler syntax parameter unavailable at indexed declaration token"
                        : "multiple compiler syntax parameters match indexed declaration token"
                    continue
                }

                let ownerUSRs = Set(
                    declarations.flatMap { occurrence in
                        occurrence.relations.compactMap { relation in
                            relation.hasRole(.childOf) ? relation.usr : nil
                        }
                    })
                let indexedOwnerUSR = ownerUSRs.count == 1 ? ownerUSRs.first : nil
                let indexedOwnerAnchors = Set(
                    indexedOwnerUSR.flatMap { ownerUSR in
                        occurrencesByUSR[ownerUSR]?.compactMap { occurrence -> IndexedByteAnchor? in
                            guard !occurrence.hasRole(.implicit),
                                occurrence.hasRole(.declaration)
                                    || occurrence.hasRole(.definition),
                                Self.isPath(occurrence.path, underRootPaths: rootPaths),
                                let source = sourceCache.file(for: occurrence.path),
                                let byteOffset = source.byteOffset(
                                    line: occurrence.line,
                                    utf8Column: occurrence.utf8Column
                                )
                            else {
                                return nil
                            }
                            return IndexedByteAnchor(
                                path: source.path,
                                byteOffset: byteOffset
                            )
                        }
                    } ?? [])
                let hasMatchingIndexedOwner =
                    candidate.ownerToken.map { token in
                        indexedOwnerAnchors.contains { anchor in
                            guard anchor.path == token.path else {
                                return false
                            }
                            return token.byteRange.contains(anchor.byteOffset)
                                || (token.isBackticked
                                    && anchor.byteOffset + 1 == token.byteRange.lowerBound)
                        }
                    } ?? false

                parametersByUSR[usr] = ParameterSyntax.Parameter(
                    parameterUSR: usr,
                    kind: candidate.kind,
                    indexedDeclarationAnchor: declarationAnchor.token ?? candidate.indexedAnchor,
                    externalLabel: candidate.externalLabel,
                    localBinding: candidate.localBinding,
                    hasDefaultValue: candidate.hasDefaultValue,
                    isVariadic: candidate.isVariadic,
                    trailingClosureCompatibility: Self.trailingClosureCompatibility(
                        candidate: candidate,
                        symbolKindsByNominalTypeAnchor: symbolKindsByNominalTypeAnchor
                    ),
                    localBindingReferences: candidate.localBindingReferences,
                    coordinatedShorthandBindingDeclarations:
                        candidate.coordinatedShorthandBindingDeclarations,
                    coordinatedShorthandBindingReferences:
                        candidate.coordinatedShorthandBindingReferences,
                    shadowingBindingDeclarations: candidate.shadowingBindingDeclarations,
                    implicitShadowingBindingNames: candidate.implicitShadowingBindingNames,
                    syntaxOwnerToken: candidate.ownerToken,
                    indexedOwnerUSR: indexedOwnerUSR,
                    hasMatchingIndexedOwner: hasMatchingIndexedOwner
                )
                if !candidate.shadowingBindingKinds.isEmpty {
                    shadowingBindingKindsByUSR[usr] = candidate.shadowingBindingKinds
                }
            }

            self.parametersByUSR = parametersByUSR
            self.localBindingCandidateUSRs = Set(
                parametersByUSR.compactMap { usr, role in
                    Self.isLocalBindingOnlyCoverageCandidate(role) ? usr : nil
                }
            )
            self.shadowingBindingKindsByUSR = shadowingBindingKindsByUSR
            self.issueReasonsByUSR = issueReasonsByUSR
            self.report = ParameterSyntax.Report(
                explicitParameters: declarationsByUSR.count,
                parametersByUSR: parametersByUSR,
                shadowingBindingKindsByUSR: shadowingBindingKindsByUSR,
                issueReasonsByUSR: issueReasonsByUSR
            )
        }

        private static func isPath(_ path: String, underRootPaths rootPaths: [String]) -> Bool {
            let canonicalPath = SourcePathNormalizer.canonicalPath(path)
            return rootPaths.contains { rootPath in
                canonicalPath == rootPath || canonicalPath.hasPrefix(rootPath + "/")
            }
        }

        private static func trailingClosureCompatibility(
            candidate: ParameterSyntaxCandidate,
            symbolKindsByNominalTypeAnchor: [IndexedByteAnchor: Set<String>]
        ) -> ParameterSyntax.TrailingClosureSupport {
            guard candidate.trailingClosureCompatibility != .definitelyCallable,
                let token = candidate.nominalTypeAnchor
            else {
                return candidate.trailingClosureCompatibility
            }
            let anchor = IndexedByteAnchor(
                path: token.path,
                byteOffset: token.byteRange.lowerBound
            )
            let kinds = symbolKindsByNominalTypeAnchor[anchor] ?? []
            let nominalKinds = IndexSymbolKind.rawValues(.actor, .class, .enum, .struct)
            guard !kinds.isEmpty, kinds.isSubset(of: nominalKinds) else {
                return .unknown
            }
            return .definitelyNonCallable
        }

        static func isLocalBindingOnlyCoverageCandidate(
            _ role: ParameterSyntax.Parameter
        ) -> Bool {
            guard role.kind != .enumCase,
                role.localBinding != nil,
                role.shadowingBindingDeclarations.isEmpty,
                role.implicitShadowingBindingNames.isEmpty,
                role.localBindingTokens.allSatisfy({
                    !$0.isBackticked && isPlainSwiftIdentifier($0.name)
                })
            else {
                return false
            }
            switch role.externalLabel {
            case .none, .omitted:
                return true
            case .named:
                // `external local:` already has two independent source tokens.
                // For shorthand `name:`, the planner may preserve `name` as the
                // external label and insert a distinct local binding, producing
                // `name obfuscated:`. Both forms keep overload identity,
                // Objective-C selectors, protocol requirements, and inherited
                // initializer signatures unchanged.
                return true
            }
        }
    }

}

private struct ParameterSyntaxCandidate {
    let kind: ParameterSyntax.DeclarationKind
    let indexedAnchor: SourceToken
    let externalLabel: ParameterSyntax.LabelRole
    let localBinding: SourceToken?
    let hasDefaultValue: Bool
    let isVariadic: Bool
    let trailingClosureCompatibility: ParameterSyntax.TrailingClosureSupport
    let nominalTypeAnchor: SourceToken?
    let ownerToken: SourceToken?
    let bodyRange: Range<Int>?
    var localBindingReferences: [SourceToken] = []
    var coordinatedShorthandBindingDeclarations: [SourceToken] = []
    var coordinatedShorthandBindingReferences: [SourceToken] = []
    var shadowingBindingDeclarations: [SourceToken] = []
    var shadowingBindingKinds: [String] = []
    var implicitShadowingBindingNames: Set<String> = []
}

private struct ImplicitBindingScope {
    let name: String
    let bodyRange: Range<Int>
}

private struct BindingDeclaration {
    let token: SourceToken
    let kind: BindingDeclarationKind
    /// Exact lexical ranges in which this declaration shadows an outer binding.
    /// `nil` means the scope has not been modeled and must remain fail-closed.
    let shadowScopes: [Range<Int>]?
    /// The declaration uses shorthand optional-binding syntax, so its source token
    /// also reads the visible binding with the same name.
    let isShorthandOptionalBinding: Bool

    init(
        token: SourceToken,
        kind: BindingDeclarationKind,
        shadowScope: Range<Int>?,
        isShorthandOptionalBinding: Bool = false
    ) {
        self.token = token
        self.kind = kind
        self.shadowScopes = shadowScope.map { [$0] }
        self.isShorthandOptionalBinding = isShorthandOptionalBinding
    }

    init(
        token: SourceToken,
        kind: BindingDeclarationKind,
        shadowScopes: [Range<Int>]?,
        isShorthandOptionalBinding: Bool = false
    ) {
        self.token = token
        self.kind = kind
        self.shadowScopes = shadowScopes
        self.isShorthandOptionalBinding = isShorthandOptionalBinding
    }
}

private enum BindingDeclarationKind: String {
    case functionParameter
    case enumCaseParameter
    case accessorParameter
    case closureParameter
    case closureShorthandParameter
    case closureCaptureAlias
    case simpleLocalVariable
    case multiBindingVariable
    case destructuredVariablePattern
    case accessorBackedVariable
    case ifOptionalBindingCondition
    case guardOptionalBindingCondition
    case whileOptionalBindingCondition
    case unmodeledOptionalBindingCondition
    case matchingPatternCondition
    case forStatementPattern
    case switchCasePattern
    case catchItemPattern
    case memberOrSourceVariable
    case unmodeledIdentifierPattern
}

private final class ParameterSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var candidates: [ParameterSyntaxCandidate] = []
    var declarationReferences: [SourceToken] = []
    var bindingDeclarations: [BindingDeclaration] = []
    var implicitBindingScopes: [ImplicitBindingScope] = []

    init(source: SourceFile) {
        self.source = source
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        guard let firstName = sourceToken(node.firstName),
            let indexedAnchor = sourceToken(node.secondName ?? node.firstName),
            let owner = functionOwner(of: node)
        else {
            return .visitChildren
        }
        let localBinding = indexedAnchor.name == "_" ? nil : indexedAnchor
        if let localBinding {
            bindingDeclarations.append(
                BindingDeclaration(
                    token: localBinding,
                    kind: .functionParameter,
                    shadowScope: owner.bodyRange
                ))
        }
        let trailingClosureType = trailingClosureType(of: node.type)
        candidates.append(
            ParameterSyntaxCandidate(
                kind: owner.kind,
                indexedAnchor: indexedAnchor,
                externalLabel: owner.isOperatorFunction
                    || (owner.kind == .subscriptDeclaration && node.secondName == nil)
                    ? .none
                    : externalLabel(firstName),
                localBinding: localBinding,
                hasDefaultValue: node.defaultValue != nil,
                isVariadic: node.ellipsis != nil,
                trailingClosureCompatibility: trailingClosureType.compatibility,
                nominalTypeAnchor: trailingClosureType.nominalTypeAnchor,
                ownerToken: owner.token,
                bodyRange: owner.bodyRange
            ))
        return .visitChildren
    }

    override func visit(_ node: EnumCaseParameterSyntax) -> SyntaxVisitorContinueKind {
        guard let firstNameSyntax = node.firstName else {
            guard let typeToken = node.type.firstToken(viewMode: .sourceAccurate),
                let indexedAnchor = sourceToken(typeToken)
            else {
                return .visitChildren
            }
            let trailingClosureType = trailingClosureType(of: node.type)
            candidates.append(
                ParameterSyntaxCandidate(
                    kind: .enumCase,
                    indexedAnchor: indexedAnchor,
                    externalLabel: .none,
                    localBinding: nil,
                    hasDefaultValue: node.defaultValue != nil,
                    isVariadic: false,
                    trailingClosureCompatibility: trailingClosureType.compatibility,
                    nominalTypeAnchor: trailingClosureType.nominalTypeAnchor,
                    ownerToken: ownerToken(of: node, as: EnumCaseElementSyntax.self, token: \.name),
                    bodyRange: nil
                ))
            return .visitChildren
        }
        guard let firstName = sourceToken(firstNameSyntax),
            let indexedAnchor = sourceToken(node.secondName ?? firstNameSyntax)
        else {
            return .visitChildren
        }
        let localBinding = indexedAnchor.name == "_" ? nil : indexedAnchor
        if let localBinding {
            bindingDeclarations.append(
                BindingDeclaration(
                    token: localBinding,
                    kind: .enumCaseParameter,
                    shadowScope: nil
                ))
        }
        let trailingClosureType = trailingClosureType(of: node.type)
        candidates.append(
            ParameterSyntaxCandidate(
                kind: .enumCase,
                indexedAnchor: indexedAnchor,
                externalLabel: externalLabel(firstName),
                localBinding: localBinding,
                hasDefaultValue: node.defaultValue != nil,
                isVariadic: false,
                trailingClosureCompatibility: trailingClosureType.compatibility,
                nominalTypeAnchor: trailingClosureType.nominalTypeAnchor,
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
        bindingDeclarations.append(
            BindingDeclaration(
                token: indexedAnchor,
                kind: .accessorParameter,
                shadowScope: owner?.bodyRange
            ))
        candidates.append(
            ParameterSyntaxCandidate(
                kind: .accessor,
                indexedAnchor: indexedAnchor,
                externalLabel: .none,
                localBinding: indexedAnchor,
                hasDefaultValue: false,
                isVariadic: false,
                trailingClosureCompatibility: .unknown,
                nominalTypeAnchor: nil,
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
        let owner = closureOwner(of: node)
        if let localBinding {
            bindingDeclarations.append(
                BindingDeclaration(
                    token: localBinding,
                    kind: .closureParameter,
                    shadowScope: owner?.bodyRange
                ))
        }
        let trailingClosureType = trailingClosureType(of: node.type)
        candidates.append(
            ParameterSyntaxCandidate(
                kind: .closure,
                indexedAnchor: indexedAnchor,
                externalLabel: .none,
                localBinding: localBinding,
                hasDefaultValue: false,
                isVariadic: node.ellipsis != nil,
                trailingClosureCompatibility: trailingClosureType.compatibility,
                nominalTypeAnchor: trailingClosureType.nominalTypeAnchor,
                ownerToken: owner?.token,
                bodyRange: owner?.bodyRange
            ))
        return .visitChildren
    }

    override func visit(
        _ node: ClosureShorthandParameterSyntax
    ) -> SyntaxVisitorContinueKind {
        guard let localBinding = sourceToken(node.name),
            localBinding.name != "_"
        else {
            return .visitChildren
        }
        bindingDeclarations.append(
            BindingDeclaration(
                token: localBinding,
                kind: .closureShorthandParameter,
                shadowScope: enclosingClosureBodyRange(of: node)
            ))
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if !isQualifiedReferenceName(node), let token = sourceToken(node.baseName) {
            declarationReferences.append(token)
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        if let token = sourceToken(node.identifier) {
            let binding = identifierPatternBinding(of: node)
            bindingDeclarations.append(
                BindingDeclaration(
                    token: token,
                    kind: binding.kind,
                    shadowScopes: binding.shadowScopes,
                    isShorthandOptionalBinding: binding.isShorthandOptionalBinding
                ))
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
            bindingDeclarations.append(
                BindingDeclaration(
                    token: token,
                    kind: .closureCaptureAlias,
                    shadowScope: enclosingClosureBodyRange(of: node)
                ))
        }
        return .visitChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        if let bodyRange = syntaxRange(node.body) {
            implicitBindingScopes.append(
                ImplicitBindingScope(
                    name: "error",
                    bodyRange: bodyRange
                ))
        }
        return .visitChildren
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.parameters == nil,
            let bodyRange = syntaxRange(node.body)
        else {
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
            implicitBindingScopes.append(
                ImplicitBindingScope(
                    name: implicitBindingName,
                    bodyRange: bodyRange
                ))
        }
        return .visitChildren
    }

    func resolveLocalBindingReferences() {
        for index in candidates.indices {
            guard let localBinding = candidates[index].localBinding,
                let bodyRange = candidates[index].bodyRange
            else {
                continue
            }
            let matchingBindings = bindingDeclarations.filter {
                $0.token.name == localBinding.name
                    && bodyRange.contains($0.token.byteRange.lowerBound)
            }
            let scopedBindings = matchingBindings.filter { binding in
                guard let scopes = binding.shadowScopes, !scopes.isEmpty else {
                    return false
                }
                return scopes.allSatisfy { scope in
                    bodyRange.lowerBound <= scope.lowerBound
                        && scope.upperBound <= bodyRange.upperBound
                }
            }
            let safelyCoordinatedShorthandBindings = scopedBindings.filter { binding in
                guard binding.isShorthandOptionalBinding,
                    let scopes = binding.shadowScopes
                else {
                    return false
                }
                let isAlreadyShadowed = scopedBindings.contains { other in
                    other.token != binding.token
                        && (other.shadowScopes ?? []).contains(where: {
                            $0.contains(binding.token.byteRange.lowerBound)
                        })
                }
                guard !isAlreadyShadowed else {
                    return false
                }
                let hasNestedBinding = matchingBindings.contains { other in
                    other.token != binding.token
                        && scopes.contains(where: {
                            $0.contains(other.token.byteRange.lowerBound)
                        })
                }
                let hasNestedImplicitBinding = implicitBindingScopes.contains { implicit in
                    implicit.name == localBinding.name
                        && scopes.contains(where: {
                            $0.contains(implicit.bodyRange.lowerBound)
                        })
                }
                return !hasNestedBinding && !hasNestedImplicitBinding
            }
            let safeCoordinatedTokens = Set(
                safelyCoordinatedShorthandBindings.map(\.token)
            )
            let unsafeDirectShorthandTokens = Set<SourceToken>(
                scopedBindings.compactMap { binding -> SourceToken? in
                    guard binding.isShorthandOptionalBinding,
                        !safeCoordinatedTokens.contains(binding.token)
                    else {
                        return nil
                    }
                    let isAlreadyShadowed = scopedBindings.contains { other in
                        other.token != binding.token
                            && (other.shadowScopes ?? []).contains(where: {
                                $0.contains(binding.token.byteRange.lowerBound)
                            })
                    }
                    return isAlreadyShadowed ? nil : binding.token
                }
            )
            let shadowScopes = scopedBindings.flatMap { $0.shadowScopes ?? [] }
            candidates[index].localBindingReferences = Array(
                Set(
                    declarationReferences.filter { reference in
                        reference.name == localBinding.name
                            && bodyRange.contains(reference.byteRange.lowerBound)
                            && !shadowScopes.contains(where: {
                                $0.contains(reference.byteRange.lowerBound)
                            })
                    }
                )
            ).sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
            candidates[index].coordinatedShorthandBindingDeclarations =
                safelyCoordinatedShorthandBindings.map(\.token).sorted {
                    $0.byteRange.lowerBound < $1.byteRange.lowerBound
                }
            candidates[index].coordinatedShorthandBindingReferences = Array(
                Set(
                    safelyCoordinatedShorthandBindings.flatMap { binding in
                        let scopes = binding.shadowScopes ?? []
                        return declarationReferences.filter { reference in
                            reference.name == localBinding.name
                                && scopes.contains(where: {
                                    $0.contains(reference.byteRange.lowerBound)
                                })
                        }
                    }
                )
            ).sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
            let scopedTokens = Set(scopedBindings.map(\.token))
                .subtracting(unsafeDirectShorthandTokens)
            let unresolvedBindings = matchingBindings.filter {
                !scopedTokens.contains($0.token)
            }
            candidates[index].shadowingBindingDeclarations = Array(
                Set(
                    unresolvedBindings.map(\.token)
                )
            ).sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
            candidates[index].shadowingBindingKinds = Array(
                Set(
                    unresolvedBindings.map { $0.kind.rawValue }
                )
            ).sorted()
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
        kind: ParameterSyntax.DeclarationKind,
        token: SourceToken,
        bodyRange: Range<Int>?,
        isOperatorFunction: Bool
    )? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let function = current.as(FunctionDeclSyntax.self),
                let token = sourceToken(function.name)
            {
                return (
                    .function,
                    token,
                    syntaxRange(function.body),
                    isOperatorToken(function.name.tokenKind)
                )
            }
            if let initializer = current.as(InitializerDeclSyntax.self),
                let token = sourceToken(initializer.initKeyword)
            {
                return (.initializer, token, syntaxRange(initializer.body), false)
            }
            if let subscriptDeclaration = current.as(SubscriptDeclSyntax.self),
                let token = sourceToken(subscriptDeclaration.subscriptKeyword)
            {
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

    private func trailingClosureType(
        of type: TypeSyntax?
    ) -> (
        compatibility: ParameterSyntax.TrailingClosureSupport,
        nominalTypeAnchor: SourceToken?
    ) {
        guard let type else {
            return (.unknown, nil)
        }
        if type.is(FunctionTypeSyntax.self) {
            return (.definitelyCallable, nil)
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return trailingClosureType(of: optional.wrappedType)
        }
        if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return trailingClosureType(of: implicitlyUnwrapped.wrappedType)
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return trailingClosureType(of: attributed.baseType)
        }
        if let tuple = type.as(TupleTypeSyntax.self),
            tuple.elements.count == 1,
            let element = tuple.elements.first,
            element.firstName == nil,
            element.secondName == nil
        {
            return trailingClosureType(of: element.type)
        }
        if let identifier = type.as(IdentifierTypeSyntax.self),
            identifier.genericArgumentClause == nil
        {
            return (.unknown, sourceToken(identifier.name))
        }
        if let member = type.as(MemberTypeSyntax.self),
            member.genericArgumentClause == nil
        {
            return (.unknown, sourceToken(member.name))
        }
        return (.unknown, nil)
    }

    private func accessorOwner(
        of node: AccessorParametersSyntax
    ) -> (token: SourceToken, bodyRange: Range<Int>?)? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let accessor = current.as(AccessorDeclSyntax.self),
                let token = sourceToken(accessor.accessorSpecifier)
            {
                return (token, syntaxRange(accessor.body))
            }
            ancestor = current.parent
        }
        return nil
    }

    private func closureOwner(
        of node: ClosureParameterSyntax
    ) -> (token: SourceToken, bodyRange: Range<Int>?)? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let closure = current.as(ClosureExprSyntax.self),
                let token = sourceToken(closure.leftBrace)
            {
                return (token, syntaxRange(closure.statements))
            }
            ancestor = current.parent
        }
        return nil
    }

    private func enclosingClosureBodyRange(
        of node: some SyntaxProtocol
    ) -> Range<Int>? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let closure = current.as(ClosureExprSyntax.self) {
                return syntaxRange(closure.statements)
            }
            ancestor = current.parent
        }
        return nil
    }

    private func identifierPatternBinding(
        of node: IdentifierPatternSyntax
    ) -> (
        shadowScopes: [Range<Int>]?,
        kind: BindingDeclarationKind,
        isShorthandOptionalBinding: Bool
    ) {
        var ancestor = Syntax(node).parent
        var patternBinding: PatternBindingSyntax?
        while let current = ancestor {
            if let optionalBinding = current.as(OptionalBindingConditionSyntax.self) {
                let kind = optionalBindingKind(of: optionalBinding)
                let shadowScopes: [Range<Int>]?
                switch kind {
                case .ifOptionalBindingCondition:
                    shadowScopes = ifOptionalBindingShadowScope(optionalBinding).map { [$0] }
                case .guardOptionalBindingCondition:
                    shadowScopes = guardOptionalBindingShadowScopes(optionalBinding)
                default:
                    shadowScopes = nil
                }
                return (
                    shadowScopes,
                    kind,
                    optionalBinding.initializer == nil
                        && (kind == .ifOptionalBindingCondition
                            || kind == .guardOptionalBindingCondition)
                        && shadowScopes != nil
                )
            }
            if current.is(MatchingPatternConditionSyntax.self) {
                return (nil, .matchingPatternCondition, false)
            }
            if current.is(ForStmtSyntax.self) {
                return (nil, .forStatementPattern, false)
            }
            if current.is(SwitchCaseItemSyntax.self) {
                return (
                    switchCasePatternShadowScope(of: node).map { [$0] },
                    .switchCasePattern,
                    false
                )
            }
            if current.is(CatchItemSyntax.self) {
                return (nil, .catchItemPattern, false)
            }
            if let binding = current.as(PatternBindingSyntax.self) {
                patternBinding = binding
                break
            }
            if current.is(CodeBlockItemSyntax.self) {
                return (nil, .unmodeledIdentifierPattern, false)
            }
            ancestor = current.parent
        }
        guard let patternBinding else {
            return (nil, .unmodeledIdentifierPattern, false)
        }
        guard patternBinding.pattern.is(IdentifierPatternSyntax.self) else {
            return (nil, .destructuredVariablePattern, false)
        }
        guard patternBinding.accessorBlock == nil else {
            return (nil, .accessorBackedVariable, false)
        }

        ancestor = Syntax(patternBinding).parent
        var variableDeclaration: VariableDeclSyntax?
        while let current = ancestor {
            if let declaration = current.as(VariableDeclSyntax.self) {
                variableDeclaration = declaration
                break
            }
            if current.is(CodeBlockItemSyntax.self) {
                return (nil, .unmodeledIdentifierPattern, false)
            }
            ancestor = current.parent
        }
        guard let variableDeclaration else {
            return (nil, .unmodeledIdentifierPattern, false)
        }
        guard variableDeclaration.bindings.count == 1 else {
            return (nil, .multiBindingVariable, false)
        }

        ancestor = Syntax(variableDeclaration).parent
        while let current = ancestor {
            if let closure = current.as(ClosureExprSyntax.self) {
                let start = variableDeclaration.endPositionBeforeTrailingTrivia.utf8Offset
                let end = closure.rightBrace.positionAfterSkippingLeadingTrivia.utf8Offset
                return (start <= end ? [start..<end] : nil, .simpleLocalVariable, false)
            }
            if let codeBlock = current.as(CodeBlockSyntax.self) {
                let start = variableDeclaration.endPositionBeforeTrailingTrivia.utf8Offset
                let end = codeBlock.rightBrace.positionAfterSkippingLeadingTrivia.utf8Offset
                return (start <= end ? [start..<end] : nil, .simpleLocalVariable, false)
            }
            if current.is(MemberBlockSyntax.self) || current.is(SourceFileSyntax.self) {
                return (nil, .memberOrSourceVariable, false)
            }
            ancestor = current.parent
        }
        return (nil, .unmodeledIdentifierPattern, false)
    }

    private func optionalBindingKind(
        of node: OptionalBindingConditionSyntax
    ) -> BindingDeclarationKind {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if current.is(IfExprSyntax.self) {
                return .ifOptionalBindingCondition
            }
            if current.is(GuardStmtSyntax.self) {
                return .guardOptionalBindingCondition
            }
            if current.is(WhileStmtSyntax.self) {
                return .whileOptionalBindingCondition
            }
            if current.is(CodeBlockItemSyntax.self) {
                break
            }
            ancestor = current.parent
        }
        return .unmodeledOptionalBindingCondition
    }

    private func ifOptionalBindingShadowScope(
        _ binding: OptionalBindingConditionSyntax
    ) -> Range<Int>? {
        guard binding.pattern.is(IdentifierPatternSyntax.self) else {
            return nil
        }
        var ancestor = Syntax(binding).parent
        while let current = ancestor {
            if let ifExpression = current.as(IfExprSyntax.self) {
                let start = binding.endPositionBeforeTrailingTrivia.utf8Offset
                let end = ifExpression.body.rightBrace.positionAfterSkippingLeadingTrivia.utf8Offset
                return start <= end ? start..<end : nil
            }
            if current.is(CodeBlockItemSyntax.self) {
                return nil
            }
            ancestor = current.parent
        }
        return nil
    }

    private func guardOptionalBindingShadowScopes(
        _ binding: OptionalBindingConditionSyntax
    ) -> [Range<Int>]? {
        guard binding.pattern.is(IdentifierPatternSyntax.self) else {
            return nil
        }
        var ancestor = Syntax(binding).parent
        while let current = ancestor {
            if let guardStatement = current.as(GuardStmtSyntax.self) {
                guard let end = enclosingSequentialScopeEnd(of: guardStatement) else {
                    return nil
                }
                let conditionStart = binding.endPositionBeforeTrailingTrivia.utf8Offset
                let conditionEnd = guardStatement.body.leftBrace
                    .positionAfterSkippingLeadingTrivia.utf8Offset
                let sequentialStart = guardStatement.endPositionBeforeTrailingTrivia.utf8Offset
                guard conditionStart <= conditionEnd, sequentialStart <= end else {
                    return nil
                }
                return [conditionStart..<conditionEnd, sequentialStart..<end]
            }
            if current.is(CodeBlockItemSyntax.self) {
                return nil
            }
            ancestor = current.parent
        }
        return nil
    }

    private func enclosingSequentialScopeEnd(
        of node: some SyntaxProtocol
    ) -> Int? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let closure = current.as(ClosureExprSyntax.self) {
                return closure.rightBrace.positionAfterSkippingLeadingTrivia.utf8Offset
            }
            if let codeBlock = current.as(CodeBlockSyntax.self) {
                return codeBlock.rightBrace.positionAfterSkippingLeadingTrivia.utf8Offset
            }
            if current.is(MemberBlockSyntax.self) || current.is(SourceFileSyntax.self) {
                return nil
            }
            ancestor = current.parent
        }
        return nil
    }

    private func switchCasePatternShadowScope(
        of node: IdentifierPatternSyntax
    ) -> Range<Int>? {
        var ancestor = Syntax(node).parent
        var caseItem: SwitchCaseItemSyntax?
        while let current = ancestor {
            if caseItem == nil, let item = current.as(SwitchCaseItemSyntax.self) {
                caseItem = item
            }
            if let switchCase = current.as(SwitchCaseSyntax.self) {
                guard caseItem != nil,
                    let label = switchCase.label.as(SwitchCaseLabelSyntax.self),
                    label.caseItems.count == 1
                else {
                    return nil
                }
                let start = node.endPositionBeforeTrailingTrivia.utf8Offset
                let end = switchCase.endPositionBeforeTrailingTrivia.utf8Offset
                return start <= end ? start..<end : nil
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
    ) -> SourceToken? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let owner = current.as(ownerType) {
                return sourceToken(owner[keyPath: token])
            }
            ancestor = current.parent
        }
        return nil
    }

    private func externalLabel(_ firstName: SourceToken) -> ParameterSyntax.LabelRole {
        firstName.name == "_" ? .omitted(firstName) : .named(firstName)
    }

    private func isQualifiedReferenceName(_ node: DeclReferenceExprSyntax) -> Bool {
        if let memberAccess = node.parent?.as(MemberAccessExprSyntax.self) {
            return node.baseName.positionAfterSkippingLeadingTrivia
                == memberAccess.declName.baseName.positionAfterSkippingLeadingTrivia
        }
        if let keyPathComponent = node.parent?.as(KeyPathPropertyComponentSyntax.self) {
            return node.baseName.positionAfterSkippingLeadingTrivia
                == keyPathComponent.declName.baseName.positionAfterSkippingLeadingTrivia
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

private struct IndexedParameterAnchor: Hashable {
    let path: String
    let byteOffset: Int
    let token: SourceToken?
}

private struct IndexedByteAnchor: Hashable {
    let path: String
    let byteOffset: Int
}
