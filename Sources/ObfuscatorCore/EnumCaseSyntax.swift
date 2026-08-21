import Foundation
import SwiftParser
import SwiftSyntax

public enum EnumCaseSyntax {}

extension EnumCaseSyntax {
    public enum AccessLevel: String, Codable, Hashable, Sendable {
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

    public enum Blocker: String, Codable, Hashable, Sendable {
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

    public struct Reference: Codable, Hashable, Sendable {
        public let token: SourceToken
        public let isInsideStringInterpolation: Bool
    }

    public struct Member: Codable, Equatable, Sendable {
        public let caseUSR: String
        public let declarationToken: SourceToken?
        public let hasExplicitRawValue: Bool
        public let explicitRawValueStringLiteralToken: SourceToken?
        public let implicitRawValueLiteral: String?
        public let references: [EnumCaseSyntax.Reference]
        public let unresolvedReferenceTokens: [SourceToken]
        public let matchingStringLiteralTokens: [SourceToken]
        public let blockers: [EnumCaseSyntax.Blocker]

        public var isPreliminaryEligible: Bool {
            blockers.isEmpty
        }
    }

    public struct Owner: Codable, Equatable, Sendable {
        public let ownerUSR: String
        public let accessLevel: EnumCaseSyntax.AccessLevel
        public let declarationAttributes: [String]
        public let members: [EnumCaseSyntax.Member]
        public let blockers: [EnumCaseSyntax.Blocker]

        public var preliminaryEligibleMembers: [EnumCaseSyntax.Member] {
            guard blockers.isEmpty else {
                return []
            }
            return members.filter(\.isPreliminaryEligible)
        }

        public var isPreliminaryEligible: Bool {
            !preliminaryEligibleMembers.isEmpty
        }
    }

    public struct Issue: Codable, Equatable, Sendable {
        public let usr: String
        public let path: String?
        public let byteOffset: Int?
        public let reason: String
    }

    public struct Report: Codable, Equatable, Sendable {
        public let explicitEnumCases: Int
        public let resolvedEnumCases: Int
        public let unresolvedEnumCases: Int
        public let ownerCount: Int
        public let ownersByAccessLevel: [String: Int]
        public let casesByOwnerAccessLevel: [String: Int]
        public let ownersWithDeclarationAttributes: Int
        public let casesWithDeclarationAttributes: Int
        public let indexedReferenceOccurrences: Int
        public let resolvedReferenceOccurrences: Int
        public let unresolvedReferenceOccurrences: Int
        public let casesWithMatchingStringLiterals: Int
        public let matchingStringLiteralTokens: Int
        public let casesDirectlyInterpolated: Int
        public let directInterpolationReferences: Int
        public let preliminaryEligibleOwners: Int
        public let preliminaryEligibleCases: Int
        public let preliminaryEligibleSimpleCases: Int
        public let preliminaryEligibleAssociatedValueCases: Int
        public let preliminaryEligibleAssociatedValueParameters: Int
        public let ownersByBlocker: [String: Int]
        public let blockerCases: [String: Int]
        public let owners: [EnumCaseSyntax.Owner]
        public let issues: [EnumCaseSyntax.Issue]

        public static let empty = EnumCaseSyntax.Report(
            explicitEnumCases: 0,
            resolvedEnumCases: 0,
            unresolvedEnumCases: 0,
            ownerCount: 0,
            ownersByAccessLevel: [:],
            casesByOwnerAccessLevel: [:],
            ownersWithDeclarationAttributes: 0,
            casesWithDeclarationAttributes: 0,
            indexedReferenceOccurrences: 0,
            resolvedReferenceOccurrences: 0,
            unresolvedReferenceOccurrences: 0,
            casesWithMatchingStringLiterals: 0,
            matchingStringLiteralTokens: 0,
            casesDirectlyInterpolated: 0,
            directInterpolationReferences: 0,
            preliminaryEligibleOwners: 0,
            preliminaryEligibleCases: 0,
            preliminaryEligibleSimpleCases: 0,
            preliminaryEligibleAssociatedValueCases: 0,
            preliminaryEligibleAssociatedValueParameters: 0,
            ownersByBlocker: [:],
            blockerCases: [:],
            owners: [],
            issues: []
        )

        private enum CodingKeys: String, CodingKey {
            case explicitEnumCases
            case resolvedEnumCases
            case unresolvedEnumCases
            case ownerCount = "ownerComponents"
            case ownersByAccessLevel = "ownerComponentsByAccessLevel"
            case casesByOwnerAccessLevel
            case ownersWithDeclarationAttributes = "ownerComponentsWithDeclarationAttributes"
            case casesWithDeclarationAttributes
            case indexedReferenceOccurrences
            case resolvedReferenceOccurrences
            case unresolvedReferenceOccurrences
            case casesWithMatchingStringLiterals
            case matchingStringLiteralTokens
            case casesDirectlyInterpolated
            case directInterpolationReferences
            case preliminaryEligibleOwners = "preliminaryEligibleOwnerComponents"
            case preliminaryEligibleCases
            case preliminaryEligibleSimpleCases
            case preliminaryEligibleAssociatedValueCases
            case preliminaryEligibleAssociatedValueParameters
            case ownersByBlocker = "blockerOwnerComponents"
            case blockerCases
            case owners = "components"
            case issues = "unresolved"
        }
    }

    public struct Index: Sendable {
        public let owners: [EnumCaseSyntax.Owner]
        public let issues: [EnumCaseSyntax.Issue]
        public let report: EnumCaseSyntax.Report

        public init(
            snapshot: IndexSnapshot,
            semantics: EnumCaseSemantics.Index,
            rawValues: EnumRawValue.Index = .empty,
            sourceCache: SourceFileCache,
            obfuscationRoots: [URL]
        ) {
            let rootPaths = obfuscationRoots.map {
                $0.resolvingSymlinksInPath().standardizedFileURL.path
            }
            let groupsByUSR = Dictionary(
                uniqueKeysWithValues: snapshot.occurrenceGroups.map { ($0.usr, $0) }
            )
            let ownerUSRs = Set(semantics.owners.map(\.ownerUSR))
            let caseUSRs = Set(semantics.owners.flatMap(\.caseUSRs))
            var visitorsByPath: [String: EnumCaseSyntaxVisitor] = [:]
            var literalTokensBySpelling: [String: [SourceToken]] = [:]
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
            var issues: [EnumCaseSyntax.Issue] = []
            for owner in semantics.owners {
                let ownerCandidates = Self.syntaxCandidates(
                    at: ownerDeclarationAnchors[owner.ownerUSR] ?? [],
                    visitorsByPath: visitorsByPath,
                    keyPath: \.ownerCandidatesByOffset
                )
                guard ownerCandidates.count == 1, let ownerCandidate = ownerCandidates.first else {
                    issues.append(
                        EnumCaseSyntax.Issue(
                            usr: owner.ownerUSR,
                            path: ownerDeclarationAnchors[owner.ownerUSR]?.first?.path,
                            byteOffset: ownerDeclarationAnchors[owner.ownerUSR]?.first?
                                .byteOffset,
                            reason: ownerCandidates.isEmpty
                                ? "compiler syntax enum owner unavailable"
                                : "compiler syntax enum owner is ambiguous"
                        ))
                    continue
                }
                ownerCandidatesByUSR[owner.ownerUSR] = ownerCandidate

                for member in owner.members {
                    let caseCandidates = Self.syntaxCandidates(
                        at: caseDeclarationAnchors[member.usr] ?? [],
                        visitorsByPath: visitorsByPath,
                        keyPath: \.caseCandidatesByOffset
                    ).filter {
                        $0.ownerToken.path == ownerCandidate.token.path
                            && $0.ownerToken.byteRange == ownerCandidate.token.byteRange
                    }
                    guard caseCandidates.count == 1, let caseCandidate = caseCandidates.first else {
                        issues.append(
                            EnumCaseSyntax.Issue(
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

            var referencesByCaseUSR: [String: [EnumCaseSyntax.Reference]] = [:]
            var unresolvedReferenceTokensByCaseUSR: [String: [SourceToken]] = [:]
            var indexedReferenceOccurrences = 0
            for caseUSR in caseUSRs.sorted() {
                guard let group = groupsByUSR[caseUSR] else {
                    continue
                }
                for occurrence in group.occurrences {
                    guard !occurrence.hasRole(.implicit),
                        !occurrence.hasRole(.declaration),
                        !occurrence.hasRole(.definition),
                        Self.isPath(occurrence.path, underRootPaths: rootPaths),
                        let source = sourceCache.file(for: occurrence.path),
                        let byteOffset = source.byteOffset(
                            line: occurrence.line,
                            utf8Column: occurrence.utf8Column
                        ),
                        let indexedToken = source.identifierToken(atByteOffset: byteOffset).map({
                            SourceToken(
                                path: source.path,
                                name: $0.name,
                                byteRange: $0.byteRange,
                                isBackticked: $0.isBackticked
                            )
                        })
                    else {
                        continue
                    }
                    indexedReferenceOccurrences += 1
                    let candidates =
                        visitorsByPath[source.path]?
                        .referenceCandidatesByOffset[indexedToken.byteRange.lowerBound]?
                        .filter {
                            $0.token.byteRange == indexedToken.byteRange
                                && $0.token.name == indexedToken.name
                        } ?? []
                    if candidates.count == 1, let candidate = candidates.first {
                        referencesByCaseUSR[caseUSR, default: []].append(
                            EnumCaseSyntax.Reference(
                                token: candidate.token,
                                isInsideStringInterpolation: candidate.isInsideStringInterpolation
                            )
                        )
                    } else {
                        unresolvedReferenceTokensByCaseUSR[caseUSR, default: []]
                            .append(indexedToken)
                        issues.append(
                            EnumCaseSyntax.Issue(
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

            let owners = semantics.owners.map { semanticOwner in
                let ownerCandidate = ownerCandidatesByUSR[semanticOwner.ownerUSR]
                var members: [EnumCaseSyntax.Member] = []
                for semanticMember in semanticOwner.members {
                    let references = Array(
                        Set(
                            referencesByCaseUSR[semanticMember.usr] ?? []
                        )
                    ).sorted {
                        ($0.token.path, $0.token.byteRange.lowerBound)
                            < ($1.token.path, $1.token.byteRange.lowerBound)
                    }
                    let unresolvedReferenceTokens = Array(
                        Set(
                            unresolvedReferenceTokensByCaseUSR[semanticMember.usr] ?? []
                        )
                    ).sorted {
                        ($0.path, $0.byteRange.lowerBound)
                            < ($1.path, $1.byteRange.lowerBound)
                    }
                    let syntaxCandidate = caseCandidatesByUSR[semanticMember.usr]
                    let allMatchingStringLiteralTokens =
                        syntaxCandidate
                        .flatMap { literalTokensBySpelling[$0.token.name] } ?? []
                    let matchingStringLiteralTokens = allMatchingStringLiteralTokens.filter {
                        $0 != syntaxCandidate?.explicitRawValueStringLiteralToken
                    }
                    let hasExplicitRawValue =
                        syntaxCandidate?.hasExplicitRawValue ?? false
                    let implicitRawValueLiteral =
                        rawValues
                        .implicitValuesByCaseUSR[semanticMember.usr]?.literalSource
                    var memberBlockers: Set<EnumCaseSyntax.Blocker> = []
                    if semanticOwner.hasRawType
                        && !hasExplicitRawValue
                        && implicitRawValueLiteral == nil
                    {
                        memberBlockers.insert(.rawType)
                    }
                    if !matchingStringLiteralTokens.isEmpty {
                        memberBlockers.insert(.stringLiteralSpelling)
                    }
                    members.append(
                        EnumCaseSyntax.Member(
                            caseUSR: semanticMember.usr,
                            declarationToken: syntaxCandidate?.token,
                            hasExplicitRawValue: hasExplicitRawValue,
                            explicitRawValueStringLiteralToken:
                                syntaxCandidate?.explicitRawValueStringLiteralToken,
                            implicitRawValueLiteral: implicitRawValueLiteral,
                            references: references,
                            unresolvedReferenceTokens: unresolvedReferenceTokens,
                            matchingStringLiteralTokens: matchingStringLiteralTokens,
                            blockers: memberBlockers.sorted { $0.rawValue < $1.rawValue }
                        ))
                }
                members.sort { $0.caseUSR < $1.caseUSR }
                let blockers = Self.blockers(
                    semanticOwner: semanticOwner,
                    ownerCandidate: ownerCandidate,
                    members: members
                )
                return EnumCaseSyntax.Owner(
                    ownerUSR: semanticOwner.ownerUSR,
                    accessLevel: ownerCandidate?.accessLevel ?? .unknown,
                    declarationAttributes: ownerCandidate?.attributes ?? [],
                    members: members,
                    blockers: blockers.sorted { $0.rawValue < $1.rawValue }
                )
            }.sorted { $0.ownerUSR < $1.ownerUSR }

            self.owners = owners
            self.issues = issues.sorted {
                ($0.usr, $0.path ?? "", $0.byteOffset ?? -1, $0.reason)
                    < ($1.usr, $1.path ?? "", $1.byteOffset ?? -1, $1.reason)
            }
            self.report = Self.makeReport(
                explicitEnumCases: caseUSRs.count,
                indexedReferenceOccurrences: indexedReferenceOccurrences,
                semantics: semantics,
                owners: owners,
                issues: self.issues
            )
        }

        private static func blockers(
            semanticOwner: EnumCaseSemantics.Owner,
            ownerCandidate: EnumOwnerSyntaxCandidate?,
            members: [EnumCaseSyntax.Member]
        ) -> Set<EnumCaseSyntax.Blocker> {
            var blockers: Set<EnumCaseSyntax.Blocker> = []
            // A protocol conformance does not by itself make enum case spellings
            // requirements. IndexStoreDB marks the exceptional case-as-witness
            // declaration with an explicit overrideOf relation to the requirement.
            // Keep those enum owners denied until requirement and case names
            // are coordinated; ordinary owner-only conformances do not need a
            // source-text or protocol-name allowlist.
            if semanticOwner.hasProtocolCaseWitness {
                blockers.insert(.protocolConformance)
            }
            if semanticOwner.isExplicitCodingKeys {
                blockers.insert(.codingKeyContract)
            }
            if semanticOwner.isSerializationSensitive
                && !permitsMemberLocalRawValueRenaming(
                    semanticOwner: semanticOwner
                )
            {
                blockers.insert(.serializationContract)
            }
            if semanticOwner.isRuntimeSensitive {
                blockers.insert(.objectiveCRuntimeContract)
            }
            if semanticOwner.isExternallyOwned { blockers.insert(.externalOwner) }
            if semanticOwner.hasOccurrencesOutsideSelectedRoots {
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
            semanticOwner: EnumCaseSemantics.Owner
        ) -> Bool {
            semanticOwner.hasRawType
                && !semanticOwner.hasManualSerializationContract
        }

        private static func makeReport(
            explicitEnumCases: Int,
            indexedReferenceOccurrences: Int,
            semantics: EnumCaseSemantics.Index,
            owners: [EnumCaseSyntax.Owner],
            issues: [EnumCaseSyntax.Issue]
        ) -> EnumCaseSyntax.Report {
            let semanticByOwner = Dictionary(
                uniqueKeysWithValues: semantics.owners.map { ($0.ownerUSR, $0) }
            )
            let resolvedEnumCases = owners.reduce(0) { total, owner in
                total + owner.members.count { $0.declarationToken != nil }
            }
            let resolvedReferenceOccurrences = owners.reduce(0) { total, owner in
                total + owner.members.reduce(0) { $0 + $1.references.count }
            }
            var ownersByBlocker: [String: Int] = [:]
            var blockerCases: [String: Int] = [:]
            for owner in owners {
                for blocker in owner.blockers {
                    ownersByBlocker[blocker.rawValue, default: 0] += 1
                    blockerCases[blocker.rawValue, default: 0] += owner.members.count
                }
                let memberBlockers = Set(owner.members.flatMap(\.blockers))
                for blocker in memberBlockers {
                    ownersByBlocker[blocker.rawValue, default: 0] += 1
                    blockerCases[blocker.rawValue, default: 0] += owner.members.count {
                        $0.blockers.contains(blocker)
                    }
                }
            }
            let accessOwnerCounts = Dictionary(
                grouping: owners,
                by: { $0.accessLevel.rawValue }
            ).mapValues(\.count)
            let accessCaseCounts = Dictionary(
                grouping: owners,
                by: { $0.accessLevel.rawValue }
            ).mapValues { $0.reduce(0) { $0 + $1.members.count } }
            let casesWithMatchingStringLiterals = owners.reduce(0) { total, owner in
                total + owner.members.count { !$0.matchingStringLiteralTokens.isEmpty }
            }
            let matchingStringLiteralTokens = owners.reduce(0) { total, owner in
                total
                    + owner.members.reduce(0) {
                        $0 + $1.matchingStringLiteralTokens.count
                    }
            }
            let casesDirectlyInterpolated = owners.reduce(0) { total, owner in
                total
                    + owner.members.count {
                        $0.references.contains(where: \.isInsideStringInterpolation)
                    }
            }
            let directInterpolationReferences = owners.reduce(0) { total, owner in
                total
                    + owner.members.reduce(0) { memberTotal, member in
                        memberTotal + member.references.count(where: \.isInsideStringInterpolation)
                    }
            }
            var eligibleSimpleCases = 0
            var eligibleAssociatedCases = 0
            var eligibleAssociatedParameters = 0
            for owner in owners where owner.isPreliminaryEligible {
                guard let semantic = semanticByOwner[owner.ownerUSR] else {
                    continue
                }
                let eligibleCaseUSRs = Set(owner.preliminaryEligibleMembers.map(\.caseUSR))
                for member in semantic.members where eligibleCaseUSRs.contains(member.usr) {
                    if member.hasAssociatedValues {
                        eligibleAssociatedCases += 1
                        eligibleAssociatedParameters += member.associatedValueParameterUSRs.count
                    } else {
                        eligibleSimpleCases += 1
                    }
                }
            }
            return EnumCaseSyntax.Report(
                explicitEnumCases: explicitEnumCases,
                resolvedEnumCases: resolvedEnumCases,
                unresolvedEnumCases: max(0, explicitEnumCases - resolvedEnumCases),
                ownerCount: owners.count,
                ownersByAccessLevel: accessOwnerCounts,
                casesByOwnerAccessLevel: accessCaseCounts,
                ownersWithDeclarationAttributes: owners.count {
                    !$0.declarationAttributes.isEmpty
                },
                casesWithDeclarationAttributes: owners.filter {
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
                preliminaryEligibleOwners: owners.count(where: \.isPreliminaryEligible),
                preliminaryEligibleCases: owners.reduce(0) {
                    $0 + $1.preliminaryEligibleMembers.count
                },
                preliminaryEligibleSimpleCases: eligibleSimpleCases,
                preliminaryEligibleAssociatedValueCases: eligibleAssociatedCases,
                preliminaryEligibleAssociatedValueParameters: eligibleAssociatedParameters,
                ownersByBlocker: ownersByBlocker,
                blockerCases: blockerCases,
                owners: owners,
                issues: issues
            )
        }

        private static func declarationAnchors(
            for usrs: Set<String>,
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
            sourceCache: SourceFileCache,
            rootPaths: [String]
        ) -> [String: Set<IndexedEnumSyntaxAnchor>] {
            var result: [String: Set<IndexedEnumSyntaxAnchor>] = [:]
            for usr in usrs {
                guard let group = groupsByUSR[usr] else { continue }
                for occurrence in group.occurrences
                where !occurrence.hasRole(.implicit)
                    && (occurrence.hasRole(.declaration)
                        || occurrence.hasRole(.definition))
                    && isPath(occurrence.path, underRootPaths: rootPaths)
                {
                    guard let source = sourceCache.file(for: occurrence.path),
                        let byteOffset = source.byteOffset(
                            line: occurrence.line,
                            utf8Column: occurrence.utf8Column
                        ),
                        let token = source.identifierToken(atByteOffset: byteOffset)
                    else {
                        continue
                    }
                    result[usr, default: []].insert(
                        IndexedEnumSyntaxAnchor(
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

}

private struct IndexedEnumSyntaxAnchor: Hashable {
    let path: String
    let byteOffset: Int
}

private struct EnumOwnerSyntaxCandidate {
    let token: SourceToken
    let accessLevel: EnumCaseSyntax.AccessLevel
    let attributes: [String]
}

private struct EnumCaseSyntaxCandidate {
    let token: SourceToken
    let ownerToken: SourceToken
    let hasExplicitRawValue: Bool
    let explicitRawValueStringLiteralToken: SourceToken?
}

private struct EnumCaseReferenceSyntaxCandidate {
    let token: SourceToken
    let isInsideStringInterpolation: Bool
}

private final class EnumCaseSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var ownerCandidatesByOffset: [Int: [EnumOwnerSyntaxCandidate]] = [:]
    var caseCandidatesByOffset: [Int: [EnumCaseSyntaxCandidate]] = [:]
    var referenceCandidatesByOffset: [Int: [EnumCaseReferenceSyntaxCandidate]] = [:]
    var matchingStringLiteralTokens: [SourceToken] = []

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
            let ownerToken = enumOwnerToken(of: node)
        else {
            return .visitChildren
        }
        caseCandidatesByOffset[token.byteRange.lowerBound, default: []].append(
            EnumCaseSyntaxCandidate(
                token: token,
                ownerToken: ownerToken,
                hasExplicitRawValue: node.rawValue != nil,
                explicitRawValueStringLiteralToken: stringLiteralContentToken(
                    node.rawValue?.value
                )
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
            let token = rawToken(segment.content)
        else {
            return .visitChildren
        }
        matchingStringLiteralTokens.append(token)
        return .visitChildren
    }

    private func effectiveAccessLevel(_ node: EnumDeclSyntax) -> EnumCaseSyntax.AccessLevel {
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
    ) -> [EnumCaseSyntax.AccessLevel] {
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
                || current.is(ClosureExprSyntax.self)
            {
                return true
            }
            ancestor = current.parent
        }
        return false
    }

    private func enumOwnerToken(of node: EnumCaseElementSyntax) -> SourceToken? {
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

    private func identifierToken(_ token: TokenSyntax) -> SourceToken? {
        guard token.presence == .present else { return nil }
        let offset = token.positionAfterSkippingLeadingTrivia.utf8Offset
        guard let identifier = source.identifierToken(atByteOffset: offset) else {
            return nil
        }
        return SourceToken(
            path: source.path,
            name: identifier.name,
            byteRange: identifier.byteRange,
            isBackticked: identifier.isBackticked
        )
    }

    private func rawToken(_ token: TokenSyntax) -> SourceToken? {
        guard token.presence == .present else { return nil }
        let start = token.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = token.endPositionBeforeTrailingTrivia.utf8Offset
        guard start < end, end <= source.data.count else { return nil }
        return SourceToken(
            path: source.path,
            name: String(decoding: source.data[start..<end], as: UTF8.self),
            byteRange: start..<end
        )
    }

    private func stringLiteralContentToken(
        _ expression: ExprSyntax?
    ) -> SourceToken? {
        guard let literal = expression?.as(StringLiteralExprSyntax.self),
            literal.segments.count == 1,
            let segment = literal.segments.first?.as(StringSegmentSyntax.self)
        else {
            return nil
        }
        return rawToken(segment.content)
    }
}
