import Foundation
import SwiftParser
import SwiftSyntax

public enum EnumOwnerSyntaxAccessLevel: String, Codable, Hashable, Sendable {
    case local
    case `private`
    case `fileprivate`
    case `internal`
    case package
    case `public`
    case unknown

    var isFileScoped: Bool {
        self == .local || self == .private || self == .fileprivate
    }
}

public enum EnumCaseSyntaxBlocker: String, Codable, Hashable, Sendable {
    case rawType
    case protocolConformance
    case codingKeyContract
    case serializationContract
    case objectiveCRuntimeContract
    case externalOwner
    case occurrenceLeavesSelectedRoots
    case nonFileScopedAccess
    case declarationAttribute
    case stringLiteralSpelling
    case directStringInterpolation
    case unresolvedDeclarationSyntax
    case unresolvedReferenceSyntax
    case nonPlainIdentifier
    case backtickedIdentifier
}

public struct EnumCaseReferenceSyntaxFact: Codable, Hashable, Sendable {
    public let token: SourceTokenRange
    public let isInsideStringInterpolation: Bool
}

public struct EnumCaseMemberSyntaxFact: Codable, Equatable, Sendable {
    public let caseUSR: String
    public let declarationToken: SourceTokenRange?
    public let hasExplicitRawValue: Bool
    public let implicitRawValueLiteral: String?
    public let references: [EnumCaseReferenceSyntaxFact]
    public let unresolvedReferenceTokens: [SourceTokenRange]
    public let matchingStringLiteralTokens: [SourceTokenRange]
    public let blockers: [EnumCaseSyntaxBlocker]

    public var isPreliminaryEligible: Bool {
        blockers.isEmpty
    }
}

public struct EnumCaseOwnerSyntaxComponent: Codable, Equatable, Sendable {
    public let ownerUSR: String
    public let accessLevel: EnumOwnerSyntaxAccessLevel
    public let declarationAttributes: [String]
    public let members: [EnumCaseMemberSyntaxFact]
    public let blockers: [EnumCaseSyntaxBlocker]

    public var preliminaryEligibleMembers: [EnumCaseMemberSyntaxFact] {
        guard blockers.isEmpty else {
            return []
        }
        return members.filter(\.isPreliminaryEligible)
    }

    public var isPreliminaryEligible: Bool {
        !preliminaryEligibleMembers.isEmpty
    }
}

public struct UnresolvedEnumCaseSyntaxFact: Codable, Equatable, Sendable {
    public let usr: String
    public let path: String?
    public let byteOffset: Int?
    public let reason: String
}

public struct EnumCaseSyntaxFactsSummary: Codable, Equatable, Sendable {
    public let explicitEnumCases: Int
    public let resolvedEnumCases: Int
    public let unresolvedEnumCases: Int
    public let ownerComponents: Int
    public let ownerComponentsByAccessLevel: [String: Int]
    public let casesByOwnerAccessLevel: [String: Int]
    public let ownerComponentsWithDeclarationAttributes: Int
    public let casesWithDeclarationAttributes: Int
    public let indexedReferenceOccurrences: Int
    public let resolvedReferenceOccurrences: Int
    public let unresolvedReferenceOccurrences: Int
    public let casesWithMatchingStringLiterals: Int
    public let matchingStringLiteralTokens: Int
    public let casesDirectlyInterpolated: Int
    public let directInterpolationReferences: Int
    public let preliminaryEligibleOwnerComponents: Int
    public let preliminaryEligibleCases: Int
    public let preliminaryEligibleSimpleCases: Int
    public let preliminaryEligibleAssociatedValueCases: Int
    public let preliminaryEligibleAssociatedValueParameters: Int
    public let blockerOwnerComponents: [String: Int]
    public let blockerCases: [String: Int]
    public let components: [EnumCaseOwnerSyntaxComponent]
    public let unresolved: [UnresolvedEnumCaseSyntaxFact]

    public static let empty = EnumCaseSyntaxFactsSummary(
        explicitEnumCases: 0,
        resolvedEnumCases: 0,
        unresolvedEnumCases: 0,
        ownerComponents: 0,
        ownerComponentsByAccessLevel: [:],
        casesByOwnerAccessLevel: [:],
        ownerComponentsWithDeclarationAttributes: 0,
        casesWithDeclarationAttributes: 0,
        indexedReferenceOccurrences: 0,
        resolvedReferenceOccurrences: 0,
        unresolvedReferenceOccurrences: 0,
        casesWithMatchingStringLiterals: 0,
        matchingStringLiteralTokens: 0,
        casesDirectlyInterpolated: 0,
        directInterpolationReferences: 0,
        preliminaryEligibleOwnerComponents: 0,
        preliminaryEligibleCases: 0,
        preliminaryEligibleSimpleCases: 0,
        preliminaryEligibleAssociatedValueCases: 0,
        preliminaryEligibleAssociatedValueParameters: 0,
        blockerOwnerComponents: [:],
        blockerCases: [:],
        components: [],
        unresolved: []
    )
}

public struct EnumCaseSyntaxFacts: Sendable {
    public let components: [EnumCaseOwnerSyntaxComponent]
    public let unresolved: [UnresolvedEnumCaseSyntaxFact]
    public let summary: EnumCaseSyntaxFactsSummary

    public init(
        snapshot: IndexSnapshot,
        semanticFacts: EnumCaseComponentFacts,
        compilerRawValueFacts: CompilerRawValueFacts = .empty,
        sourceCache: SourceFileCache,
        obfuscationRoots: [URL]
    ) {
        let rootPaths = obfuscationRoots.map {
            $0.resolvingSymlinksInPath().standardizedFileURL.path
        }
        let groupsByUSR = Dictionary(
            uniqueKeysWithValues: snapshot.groupsByUSR.map { ($0.usr, $0) }
        )
        let ownerUSRs = Set(semanticFacts.components.map(\.ownerUSR))
        let caseUSRs = Set(semanticFacts.components.flatMap(\.caseUSRs))
        var visitorsByPath: [String: EnumCaseSyntaxVisitor] = [:]
        var literalTokensBySpelling: [String: [SourceTokenRange]] = [:]
        for path in sourceCache.allPaths {
            guard let source = sourceCache.file(for: path) else {
                continue
            }
            let tree = Parser.parse(source: String(decoding: source.data, as: UTF8.self))
            let visitor = EnumCaseSyntaxVisitor(source: source)
            visitor.walk(tree)
            visitorsByPath[source.path] = visitor
            for token in visitor.matchingStringLiteralTokens {
                literalTokensBySpelling[token.name, default: []].append(token)
            }
        }
        literalTokensBySpelling = literalTokensBySpelling.mapValues { tokens in
            Array(Set(tokens)).sorted {
                ($0.path, $0.byteRange.lowerBound) < ($1.path, $1.byteRange.lowerBound)
            }
        }

        let ownerDeclarationAnchors = Self.declarationAnchors(
            for: ownerUSRs,
            groupsByUSR: groupsByUSR,
            sourceCache: sourceCache,
            rootPaths: rootPaths
        )
        let caseDeclarationAnchors = Self.declarationAnchors(
            for: caseUSRs,
            groupsByUSR: groupsByUSR,
            sourceCache: sourceCache,
            rootPaths: rootPaths
        )

        var ownerCandidatesByUSR: [String: EnumOwnerSyntaxCandidate] = [:]
        var caseCandidatesByUSR: [String: EnumCaseSyntaxCandidate] = [:]
        var unresolved: [UnresolvedEnumCaseSyntaxFact] = []
        for component in semanticFacts.components {
            let ownerCandidates = Self.syntaxCandidates(
                at: ownerDeclarationAnchors[component.ownerUSR] ?? [],
                visitorsByPath: visitorsByPath,
                keyPath: \.ownerCandidatesByOffset
            )
            guard ownerCandidates.count == 1, let ownerCandidate = ownerCandidates.first else {
                unresolved.append(UnresolvedEnumCaseSyntaxFact(
                    usr: component.ownerUSR,
                    path: ownerDeclarationAnchors[component.ownerUSR]?.first?.path,
                    byteOffset: ownerDeclarationAnchors[component.ownerUSR]?.first?.byteOffset,
                    reason: ownerCandidates.isEmpty
                        ? "compiler syntax enum owner unavailable"
                        : "compiler syntax enum owner is ambiguous"
                ))
                continue
            }
            ownerCandidatesByUSR[component.ownerUSR] = ownerCandidate

            for member in component.members {
                let caseCandidates = Self.syntaxCandidates(
                    at: caseDeclarationAnchors[member.usr] ?? [],
                    visitorsByPath: visitorsByPath,
                    keyPath: \.caseCandidatesByOffset
                ).filter {
                    $0.ownerToken.path == ownerCandidate.token.path
                        && $0.ownerToken.byteRange == ownerCandidate.token.byteRange
                }
                guard caseCandidates.count == 1, let caseCandidate = caseCandidates.first else {
                    unresolved.append(UnresolvedEnumCaseSyntaxFact(
                        usr: member.usr,
                        path: caseDeclarationAnchors[member.usr]?.first?.path,
                        byteOffset: caseDeclarationAnchors[member.usr]?.first?.byteOffset,
                        reason: caseCandidates.isEmpty
                            ? "compiler syntax enum case unavailable"
                            : "compiler syntax enum case is ambiguous"
                    ))
                    continue
                }
                caseCandidatesByUSR[member.usr] = caseCandidate
            }
        }

        var referencesByCaseUSR: [String: [EnumCaseReferenceSyntaxFact]] = [:]
        var unresolvedReferenceTokensByCaseUSR: [String: [SourceTokenRange]] = [:]
        var indexedReferenceOccurrences = 0
        for caseUSR in caseUSRs.sorted() {
            guard let group = groupsByUSR[caseUSR] else {
                continue
            }
            for occurrence in group.occurrences {
                guard !occurrence.roles.contains("implicit"),
                      !occurrence.roles.contains("declaration"),
                      !occurrence.roles.contains("definition"),
                      Self.isPath(occurrence.path, underRootPaths: rootPaths),
                      let source = sourceCache.file(for: occurrence.path),
                      let byteOffset = source.byteOffset(
                        line: occurrence.line,
                        utf8Column: occurrence.utf8Column
                      ),
                      let indexedToken = source.identifierToken(atByteOffset: byteOffset).map({
                        SourceTokenRange(
                            path: source.path,
                            name: $0.name,
                            byteRange: $0.byteRange,
                            isBackticked: $0.isBackticked
                        )
                      }) else {
                    continue
                }
                indexedReferenceOccurrences += 1
                let candidates = visitorsByPath[source.path]?
                    .referenceCandidatesByOffset[indexedToken.byteRange.lowerBound]?
                    .filter {
                        $0.token.byteRange == indexedToken.byteRange
                            && $0.token.name == indexedToken.name
                    } ?? []
                if candidates.count == 1, let candidate = candidates.first {
                    referencesByCaseUSR[caseUSR, default: []].append(
                        EnumCaseReferenceSyntaxFact(
                            token: candidate.token,
                            isInsideStringInterpolation: candidate.isInsideStringInterpolation
                        )
                    )
                } else {
                    unresolvedReferenceTokensByCaseUSR[caseUSR, default: []]
                        .append(indexedToken)
                    unresolved.append(UnresolvedEnumCaseSyntaxFact(
                        usr: caseUSR,
                        path: indexedToken.path,
                        byteOffset: indexedToken.byteRange.lowerBound,
                        reason: candidates.isEmpty
                            ? "compiler syntax enum case reference unavailable"
                            : "compiler syntax enum case reference is ambiguous"
                    ))
                }
            }
        }

        let components = semanticFacts.components.map { semanticComponent in
            let ownerCandidate = ownerCandidatesByUSR[semanticComponent.ownerUSR]
            var members: [EnumCaseMemberSyntaxFact] = []
            for semanticMember in semanticComponent.members {
                let references = Array(Set(
                    referencesByCaseUSR[semanticMember.usr] ?? []
                )).sorted {
                    ($0.token.path, $0.token.byteRange.lowerBound)
                        < ($1.token.path, $1.token.byteRange.lowerBound)
                }
                let unresolvedReferenceTokens = Array(Set(
                    unresolvedReferenceTokensByCaseUSR[semanticMember.usr] ?? []
                )).sorted {
                    ($0.path, $0.byteRange.lowerBound)
                        < ($1.path, $1.byteRange.lowerBound)
                }
                let matchingStringLiteralTokens = caseCandidatesByUSR[semanticMember.usr]
                    .flatMap { literalTokensBySpelling[$0.token.name] } ?? []
                let hasExplicitRawValue =
                    caseCandidatesByUSR[semanticMember.usr]?.hasExplicitRawValue ?? false
                let implicitRawValueLiteral = compilerRawValueFacts
                    .factsByCaseUSR[semanticMember.usr]?.literalSource
                var memberBlockers: Set<EnumCaseSyntaxBlocker> = []
                if semanticComponent.hasRawType
                    && !hasExplicitRawValue
                    && implicitRawValueLiteral == nil {
                    memberBlockers.insert(.rawType)
                }
                if !matchingStringLiteralTokens.isEmpty {
                    memberBlockers.insert(.stringLiteralSpelling)
                }
                members.append(EnumCaseMemberSyntaxFact(
                    caseUSR: semanticMember.usr,
                    declarationToken: caseCandidatesByUSR[semanticMember.usr]?.token,
                    hasExplicitRawValue: hasExplicitRawValue,
                    implicitRawValueLiteral: implicitRawValueLiteral,
                    references: references,
                    unresolvedReferenceTokens: unresolvedReferenceTokens,
                    matchingStringLiteralTokens: matchingStringLiteralTokens,
                    blockers: memberBlockers.sorted { $0.rawValue < $1.rawValue }
                ))
            }
            members.sort { $0.caseUSR < $1.caseUSR }
            let blockers = Self.blockers(
                semanticComponent: semanticComponent,
                ownerCandidate: ownerCandidate,
                members: members
            )
            return EnumCaseOwnerSyntaxComponent(
                ownerUSR: semanticComponent.ownerUSR,
                accessLevel: ownerCandidate?.accessLevel ?? .unknown,
                declarationAttributes: ownerCandidate?.attributes ?? [],
                members: members,
                blockers: blockers.sorted { $0.rawValue < $1.rawValue }
            )
        }.sorted { $0.ownerUSR < $1.ownerUSR }

        self.components = components
        self.unresolved = unresolved.sorted {
            ($0.usr, $0.path ?? "", $0.byteOffset ?? -1, $0.reason)
                < ($1.usr, $1.path ?? "", $1.byteOffset ?? -1, $1.reason)
        }
        self.summary = Self.makeSummary(
            explicitEnumCases: caseUSRs.count,
            indexedReferenceOccurrences: indexedReferenceOccurrences,
            semanticFacts: semanticFacts,
            components: components,
            unresolved: self.unresolved
        )
    }

    private static func blockers(
        semanticComponent: EnumCaseOwnerComponent,
        ownerCandidate: EnumOwnerSyntaxCandidate?,
        members: [EnumCaseMemberSyntaxFact]
    ) -> Set<EnumCaseSyntaxBlocker> {
        var blockers: Set<EnumCaseSyntaxBlocker> = []
        // A protocol conformance does not by itself make enum case spellings
        // requirements. IndexStoreDB marks the exceptional case-as-witness
        // declaration with an explicit overrideOf relation to the requirement.
        // Keep those owner components denied until requirement and case names
        // are coordinated; ordinary owner-only conformances do not need a
        // source-text or protocol-name allowlist.
        if semanticComponent.hasProtocolCaseWitness {
            blockers.insert(.protocolConformance)
        }
        if semanticComponent.isExplicitCodingKeys {
            blockers.insert(.codingKeyContract)
        }
        if semanticComponent.isSerializationSensitive
            && !permitsMemberLocalRawValueRenaming(
                semanticComponent: semanticComponent
            ) {
            blockers.insert(.serializationContract)
        }
        if semanticComponent.isRuntimeSensitive {
            blockers.insert(.objectiveCRuntimeContract)
        }
        if semanticComponent.isExternallyOwned { blockers.insert(.externalOwner) }
        if semanticComponent.hasOccurrencesOutsideSelectedRoots {
            blockers.insert(.occurrenceLeavesSelectedRoots)
        }
        guard let ownerCandidate else {
            blockers.insert(.unresolvedDeclarationSyntax)
            return blockers
        }
        // Visibility alone is not an external contract. Public and package
        // declarations follow the same selected-root closure model as the
        // rest of the planner; actual out-of-root occurrences, runtime,
        // serialization, raw-value, protocol, and reflection contracts are
        // represented by independent semantic blockers above.
        if ownerCandidate.accessLevel == .unknown {
            blockers.insert(.nonFileScopedAccess)
        }
        if !ownerCandidate.attributes.isEmpty { blockers.insert(.declarationAttribute) }
        for member in members {
            guard let declarationToken = member.declarationToken else {
                blockers.insert(.unresolvedDeclarationSyntax)
                continue
            }
            if !isPlainSwiftArgumentLabel(declarationToken.name) {
                blockers.insert(.nonPlainIdentifier)
            }
            if !member.unresolvedReferenceTokens.isEmpty {
                blockers.insert(.unresolvedReferenceSyntax)
            }
            if member.references.contains(where: \.isInsideStringInterpolation) {
                blockers.insert(.directStringInterpolation)
            }
        }
        return blockers
    }

    /// Synthesized Codable for a raw-representable enum encodes the raw value,
    /// not the case identifier. Explicit-raw members may therefore be renamed
    /// independently while implicit-raw siblings keep their member-level
    /// `rawType` blocker. Explicit CodingKeys and custom Codable witnesses keep
    /// the entire owner denied because they can introduce another spelling
    /// contract that is not represented by the raw expression alone.
    private static func permitsMemberLocalRawValueRenaming(
        semanticComponent: EnumCaseOwnerComponent
    ) -> Bool {
        semanticComponent.hasRawType
            && !semanticComponent.hasManualSerializationContract
    }

    private static func makeSummary(
        explicitEnumCases: Int,
        indexedReferenceOccurrences: Int,
        semanticFacts: EnumCaseComponentFacts,
        components: [EnumCaseOwnerSyntaxComponent],
        unresolved: [UnresolvedEnumCaseSyntaxFact]
    ) -> EnumCaseSyntaxFactsSummary {
        let semanticByOwner = Dictionary(
            uniqueKeysWithValues: semanticFacts.components.map { ($0.ownerUSR, $0) }
        )
        let resolvedEnumCases = components.reduce(0) { total, component in
            total + component.members.count { $0.declarationToken != nil }
        }
        let resolvedReferenceOccurrences = components.reduce(0) { total, component in
            total + component.members.reduce(0) { $0 + $1.references.count }
        }
        var blockerOwnerComponents: [String: Int] = [:]
        var blockerCases: [String: Int] = [:]
        for component in components {
            for blocker in component.blockers {
                blockerOwnerComponents[blocker.rawValue, default: 0] += 1
                blockerCases[blocker.rawValue, default: 0] += component.members.count
            }
            let memberBlockers = Set(component.members.flatMap(\.blockers))
            for blocker in memberBlockers {
                blockerOwnerComponents[blocker.rawValue, default: 0] += 1
                blockerCases[blocker.rawValue, default: 0] += component.members.count {
                    $0.blockers.contains(blocker)
                }
            }
        }
        let accessOwnerCounts = Dictionary(
            grouping: components,
            by: { $0.accessLevel.rawValue }
        ).mapValues(\.count)
        let accessCaseCounts = Dictionary(
            grouping: components,
            by: { $0.accessLevel.rawValue }
        ).mapValues { $0.reduce(0) { $0 + $1.members.count } }
        let casesWithMatchingStringLiterals = components.reduce(0) { total, component in
            total + component.members.count { !$0.matchingStringLiteralTokens.isEmpty }
        }
        let matchingStringLiteralTokens = components.reduce(0) { total, component in
            total + component.members.reduce(0) {
                $0 + $1.matchingStringLiteralTokens.count
            }
        }
        let casesDirectlyInterpolated = components.reduce(0) { total, component in
            total + component.members.count {
                $0.references.contains(where: \.isInsideStringInterpolation)
            }
        }
        let directInterpolationReferences = components.reduce(0) { total, component in
            total + component.members.reduce(0) { memberTotal, member in
                memberTotal + member.references.count(where: \.isInsideStringInterpolation)
            }
        }
        var eligibleSimpleCases = 0
        var eligibleAssociatedCases = 0
        var eligibleAssociatedParameters = 0
        for component in components where component.isPreliminaryEligible {
            guard let semantic = semanticByOwner[component.ownerUSR] else {
                continue
            }
            let eligibleCaseUSRs = Set(component.preliminaryEligibleMembers.map(\.caseUSR))
            for member in semantic.members where eligibleCaseUSRs.contains(member.usr) {
                if member.hasAssociatedValues {
                    eligibleAssociatedCases += 1
                    eligibleAssociatedParameters += member.associatedValueParameterUSRs.count
                } else {
                    eligibleSimpleCases += 1
                }
            }
        }
        return EnumCaseSyntaxFactsSummary(
            explicitEnumCases: explicitEnumCases,
            resolvedEnumCases: resolvedEnumCases,
            unresolvedEnumCases: max(0, explicitEnumCases - resolvedEnumCases),
            ownerComponents: components.count,
            ownerComponentsByAccessLevel: accessOwnerCounts,
            casesByOwnerAccessLevel: accessCaseCounts,
            ownerComponentsWithDeclarationAttributes: components.count {
                !$0.declarationAttributes.isEmpty
            },
            casesWithDeclarationAttributes: components.filter {
                !$0.declarationAttributes.isEmpty
            }.reduce(0) { $0 + $1.members.count },
            indexedReferenceOccurrences: indexedReferenceOccurrences,
            resolvedReferenceOccurrences: resolvedReferenceOccurrences,
            unresolvedReferenceOccurrences:
                max(0, indexedReferenceOccurrences - resolvedReferenceOccurrences),
            casesWithMatchingStringLiterals: casesWithMatchingStringLiterals,
            matchingStringLiteralTokens: matchingStringLiteralTokens,
            casesDirectlyInterpolated: casesDirectlyInterpolated,
            directInterpolationReferences: directInterpolationReferences,
            preliminaryEligibleOwnerComponents: components.count(where: \.isPreliminaryEligible),
            preliminaryEligibleCases: components.reduce(0) {
                $0 + $1.preliminaryEligibleMembers.count
            },
            preliminaryEligibleSimpleCases: eligibleSimpleCases,
            preliminaryEligibleAssociatedValueCases: eligibleAssociatedCases,
            preliminaryEligibleAssociatedValueParameters: eligibleAssociatedParameters,
            blockerOwnerComponents: blockerOwnerComponents,
            blockerCases: blockerCases,
            components: components,
            unresolved: unresolved
        )
    }

    private static func declarationAnchors(
        for usrs: Set<String>,
        groupsByUSR: [String: USROccurrenceGroup],
        sourceCache: SourceFileCache,
        rootPaths: [String]
    ) -> [String: Set<IndexedEnumSyntaxAnchor>] {
        var result: [String: Set<IndexedEnumSyntaxAnchor>] = [:]
        for usr in usrs {
            guard let group = groupsByUSR[usr] else { continue }
            for occurrence in group.occurrences
            where !occurrence.roles.contains("implicit")
                && (occurrence.roles.contains("declaration")
                    || occurrence.roles.contains("definition"))
                && isPath(occurrence.path, underRootPaths: rootPaths) {
                guard let source = sourceCache.file(for: occurrence.path),
                      let byteOffset = source.byteOffset(
                        line: occurrence.line,
                        utf8Column: occurrence.utf8Column
                      ),
                      let token = source.identifierToken(atByteOffset: byteOffset) else {
                    continue
                }
                result[usr, default: []].insert(IndexedEnumSyntaxAnchor(
                    path: source.path,
                    byteOffset: token.byteRange.lowerBound
                ))
            }
        }
        return result
    }

    private static func syntaxCandidates<Candidate>(
        at anchors: Set<IndexedEnumSyntaxAnchor>,
        visitorsByPath: [String: EnumCaseSyntaxVisitor],
        keyPath: KeyPath<EnumCaseSyntaxVisitor, [Int: [Candidate]]>
    ) -> [Candidate] {
        anchors.flatMap { anchor in
            visitorsByPath[anchor.path]?[keyPath: keyPath][anchor.byteOffset] ?? []
        }
    }

    private static func isPath(_ path: String, underRootPaths roots: [String]) -> Bool {
        let canonicalPath = SourcePathNormalizer.canonicalPath(path)
        return roots.contains { root in
            canonicalPath == root || canonicalPath.hasPrefix(root + "/")
        }
    }
}

private struct IndexedEnumSyntaxAnchor: Hashable {
    let path: String
    let byteOffset: Int
}

private struct EnumOwnerSyntaxCandidate {
    let token: SourceTokenRange
    let accessLevel: EnumOwnerSyntaxAccessLevel
    let attributes: [String]
}

private struct EnumCaseSyntaxCandidate {
    let token: SourceTokenRange
    let ownerToken: SourceTokenRange
    let hasExplicitRawValue: Bool
}

private struct EnumCaseReferenceSyntaxCandidate {
    let token: SourceTokenRange
    let isInsideStringInterpolation: Bool
}

private final class EnumCaseSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var ownerCandidatesByOffset: [Int: [EnumOwnerSyntaxCandidate]] = [:]
    var caseCandidatesByOffset: [Int: [EnumCaseSyntaxCandidate]] = [:]
    var referenceCandidatesByOffset: [Int: [EnumCaseReferenceSyntaxCandidate]] = [:]
    var matchingStringLiteralTokens: [SourceTokenRange] = []

    init(source: SourceFile) {
        self.source = source
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let token = identifierToken(node.name) else {
            return .visitChildren
        }
        ownerCandidatesByOffset[token.byteRange.lowerBound, default: []].append(
            EnumOwnerSyntaxCandidate(
                token: token,
                accessLevel: effectiveAccessLevel(node),
                attributes: node.attributes.map { $0.trimmedDescription }.sorted()
            )
        )
        return .visitChildren
    }

    override func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
        guard let token = identifierToken(node.name),
              let ownerToken = enumOwnerToken(of: node) else {
            return .visitChildren
        }
        caseCandidatesByOffset[token.byteRange.lowerBound, default: []].append(
            EnumCaseSyntaxCandidate(
                token: token,
                ownerToken: ownerToken,
                hasExplicitRawValue: node.rawValue != nil
            )
        )
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard let token = identifierToken(node.baseName) else {
            return .visitChildren
        }
        referenceCandidatesByOffset[token.byteRange.lowerBound, default: []].append(
            EnumCaseReferenceSyntaxCandidate(
                token: token,
                isInsideStringInterpolation: hasAncestor(
                    node,
                    ofType: ExpressionSegmentSyntax.self
                )
            )
        )
        return .visitChildren
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.segments.count == 1,
              let segment = node.segments.first?.as(StringSegmentSyntax.self),
              let token = rawToken(segment.content) else {
            return .visitChildren
        }
        matchingStringLiteralTokens.append(token)
        return .visitChildren
    }

    private func effectiveAccessLevel(_ node: EnumDeclSyntax) -> EnumOwnerSyntaxAccessLevel {
        if hasLocalDeclarationAncestor(node) {
            return .local
        }
        var levels = accessLevels(in: node.modifiers)
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let declaration = current.as(EnumDeclSyntax.self) {
                levels.append(contentsOf: accessLevels(in: declaration.modifiers))
            } else if let declaration = current.as(StructDeclSyntax.self) {
                levels.append(contentsOf: accessLevels(in: declaration.modifiers))
            } else if let declaration = current.as(ClassDeclSyntax.self) {
                levels.append(contentsOf: accessLevels(in: declaration.modifiers))
            } else if let declaration = current.as(ActorDeclSyntax.self) {
                levels.append(contentsOf: accessLevels(in: declaration.modifiers))
            } else if let declaration = current.as(ProtocolDeclSyntax.self) {
                levels.append(contentsOf: accessLevels(in: declaration.modifiers))
            } else if let declaration = current.as(ExtensionDeclSyntax.self) {
                levels.append(contentsOf: accessLevels(in: declaration.modifiers))
            }
            ancestor = current.parent
        }
        if levels.contains(.private) { return .private }
        if levels.contains(.fileprivate) { return .fileprivate }
        if levels.contains(.internal) { return .internal }
        if levels.contains(.package) { return .package }
        if levels.contains(.public) { return .public }
        return .internal
    }

    private func accessLevels(
        in modifiers: DeclModifierListSyntax
    ) -> [EnumOwnerSyntaxAccessLevel] {
        modifiers.compactMap { modifier in
            switch modifier.name.text {
            case "private": .private
            case "fileprivate": .fileprivate
            case "internal": .internal
            case "package": .package
            case "public", "open": .public
            default: nil
            }
        }
    }

    private func hasLocalDeclarationAncestor(_ node: EnumDeclSyntax) -> Bool {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if current.is(FunctionDeclSyntax.self)
                || current.is(InitializerDeclSyntax.self)
                || current.is(DeinitializerDeclSyntax.self)
                || current.is(AccessorDeclSyntax.self)
                || current.is(ClosureExprSyntax.self) {
                return true
            }
            ancestor = current.parent
        }
        return false
    }

    private func enumOwnerToken(of node: EnumCaseElementSyntax) -> SourceTokenRange? {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if let owner = current.as(EnumDeclSyntax.self) {
                return identifierToken(owner.name)
            }
            ancestor = current.parent
        }
        return nil
    }

    private func hasAncestor<Node: SyntaxProtocol>(
        _ node: some SyntaxProtocol,
        ofType type: Node.Type
    ) -> Bool {
        var ancestor = Syntax(node).parent
        while let current = ancestor {
            if current.is(type) { return true }
            ancestor = current.parent
        }
        return false
    }

    private func identifierToken(_ token: TokenSyntax) -> SourceTokenRange? {
        guard token.presence == .present else { return nil }
        let offset = token.positionAfterSkippingLeadingTrivia.utf8Offset
        guard let identifier = source.identifierToken(atByteOffset: offset) else {
            return nil
        }
        return SourceTokenRange(
            path: source.path,
            name: identifier.name,
            byteRange: identifier.byteRange,
            isBackticked: identifier.isBackticked
        )
    }

    private func rawToken(_ token: TokenSyntax) -> SourceTokenRange? {
        guard token.presence == .present else { return nil }
        let start = token.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = token.endPositionBeforeTrailingTrivia.utf8Offset
        guard start < end, end <= source.data.count else { return nil }
        return SourceTokenRange(
            path: source.path,
            name: String(decoding: source.data[start..<end], as: UTF8.self),
            byteRange: start..<end
        )
    }
}
