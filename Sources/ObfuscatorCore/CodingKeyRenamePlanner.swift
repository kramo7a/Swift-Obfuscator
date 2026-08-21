import Foundation

enum CodingKeyRename {
    struct Pair: Sendable {
        let codingKeysEnumUSR: String
        let nominalOwnerUSR: String
        let propertyUSR: String
        let caseRename: EnumCaseRename.Member

        var caseUSR: String { caseRename.usr }
        var key: String { "\(propertyUSR)|\(caseUSR)" }
    }

    struct Plan: Sendable {
        let pairs: [CodingKeyRename.Pair]

        var propertyUSRs: Set<String> {
            Set(pairs.map(\.propertyUSR))
        }

        var caseUSRs: Set<String> {
            Set(pairs.map(\.caseUSR))
        }
    }

    /// Builds the source-closed half of an explicit CodingKeys rename pair.
    ///
    /// IndexStoreDB supplies both ownership edges: nominal owner -> stored property
    /// and nominal owner -> CodingKeys enum -> enum case. SwiftSyntax supplies exact
    /// declaration/reference ranges and identifies the raw-value literal belonging
    /// to a case. A property/case pair is eligible only when both source spellings
    /// agree and the old raw value is already explicit or compiler-derived.
    enum Planner {
        static func makePlan(
            syntax: EnumCaseSyntax.Index,
            semantics: EnumCaseSemantics.Index,
            semanticIndex: SemanticIndex,
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
            analyzer: RenameEligibilityAnalyzer,
            sourceCache: SourceFileCache,
            excludedPropertyUSRs: Set<String>
        ) -> CodingKeyRename.Plan {
            let semanticByOwner = Dictionary(
                uniqueKeysWithValues: semantics.owners.map { ($0.ownerUSR, $0) }
            )
            var candidates: [ExplicitCodingKeyPairCandidate] = []

            for owner in syntax.owners {
                guard let semanticOwner = semanticByOwner[owner.ownerUSR],
                    semanticOwner.isExplicitCodingKeys,
                    semanticOwner.hasRawType,
                    semanticOwner.protocolConformanceUSRs.contains(codingKeyProtocolUSR),
                    let nominalOwnerUSR =
                        semanticIndex
                        .explicitCodingKeysOwnerUSRByEnumUSR[owner.ownerUSR],
                    semanticIndex.serializationSensitiveOwnerUSRs.contains(nominalOwnerUSR)
                else {
                    continue
                }

                var ownerBlockers = Set(owner.blockers)
                ownerBlockers.remove(.codingKeyContract)
                guard ownerBlockers.isEmpty else {
                    continue
                }

                let propertyUSRsByName = Dictionary(
                    grouping:
                        semanticIndex.directStoredPropertyUSRs(of: nominalOwnerUSR).filter {
                            propertyUSR in
                            !excludedPropertyUSRs.contains(propertyUSR)
                                && groupsByUSR[propertyUSR]?.symbol.isKind(.instanceProperty)
                                    == true
                        }
                ) { propertyUSR in
                    groupsByUSR[propertyUSR]?.symbol.name ?? ""
                }
                let semanticMembersByUSR = Dictionary(
                    uniqueKeysWithValues: semanticOwner.members.map { ($0.usr, $0) }
                )

                for member in owner.members {
                    guard let declarationToken = member.declarationToken,
                        let semanticMember = semanticMembersByUSR[member.caseUSR],
                        !semanticMember.hasAssociatedValues,
                        member.hasExplicitRawValue || member.implicitRawValueLiteral != nil,
                        let propertyUSRs = propertyUSRsByName[declarationToken.name],
                        propertyUSRs.count == 1,
                        let propertyUSR = propertyUSRs.first,
                        groupsByUSR[propertyUSR]?.symbol.name == declarationToken.name
                    else {
                        continue
                    }

                    // Swift.CodingKey's description/debugDescription are derived
                    // from stringValue/intValue, not from the enum-case spelling.
                    // This pair preserves an explicit raw value or materializes the
                    // compiler-derived one, so equal string literals remain stable
                    // storage/network data rather than a second identifier contract.
                    // Direct interpolation and every other enum blocker stay active
                    // at the owner level.
                    var memberBlockers = Set(member.blockers)
                    memberBlockers.remove(.stringLiteralSpelling)
                    guard memberBlockers.isEmpty else {
                        continue
                    }

                    candidates.append(
                        ExplicitCodingKeyPairCandidate(
                            codingKeysEnumUSR: owner.ownerUSR,
                            nominalOwnerUSR: nominalOwnerUSR,
                            propertyUSR: propertyUSR,
                            member: member
                        ))
                }
            }

            let coordinatedCaseUSRs = Set(candidates.map { $0.member.caseUSR })
            let pairs = candidates.compactMap {
                candidate
                    -> CodingKeyRename.Pair? in
                let result = EnumCaseRename.Planner.makeMemberRename(
                    member: candidate.member,
                    groupsByUSR: groupsByUSR,
                    semanticIndex: semanticIndex,
                    analyzer: analyzer,
                    sourceCache: sourceCache,
                    coordinatedEnumCaseUSRs: coordinatedCaseUSRs
                )
                guard result.failures.isEmpty, let caseRename = result.rename else {
                    return nil
                }
                return CodingKeyRename.Pair(
                    codingKeysEnumUSR: candidate.codingKeysEnumUSR,
                    nominalOwnerUSR: candidate.nominalOwnerUSR,
                    propertyUSR: candidate.propertyUSR,
                    caseRename: caseRename
                )
            }.sorted { lhs, rhs in
                (lhs.codingKeysEnumUSR, lhs.propertyUSR, lhs.caseUSR)
                    < (rhs.codingKeysEnumUSR, rhs.propertyUSR, rhs.caseUSR)
            }

            return CodingKeyRename.Plan(pairs: pairs)
        }

        static func makeRejections(
            pair: CodingKeyRename.Pair,
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
            reasons: [String]
        ) -> [RenameEligibility] {
            [pair.propertyUSR, pair.caseUSR].map { usr in
                let group = groupsByUSR[usr]
                return RenameEligibility(
                    usr: usr,
                    symbolName: group?.symbol.name ?? pair.caseRename.oldName,
                    symbolKind: group?.symbol.kind
                        ?? (usr == pair.caseUSR
                            ? IndexSymbolKind.enumConstant.rawValue
                            : IndexSymbolKind.instanceProperty.rawValue),
                    isEligible: false,
                    originalName: pair.caseRename.oldName,
                    reasons: [
                        "explicit CodingKeys property/case pair \(pair.key) denied atomically: "
                            + (reasons.isEmpty
                                ? "unspecified safety failure"
                                : reasons.joined(separator: "; "))
                    ]
                )
            }
        }

        // Stable standard-library semantic identity, analogous to the Codable
        // protocol identities used by SemanticIndex.
        private static let codingKeyProtocolUSR = "s:s9CodingKeyP"

    }

}

private struct ExplicitCodingKeyPairCandidate {
    let codingKeysEnumUSR: String
    let nominalOwnerUSR: String
    let propertyUSR: String
    let member: EnumCaseSyntax.Member
}
