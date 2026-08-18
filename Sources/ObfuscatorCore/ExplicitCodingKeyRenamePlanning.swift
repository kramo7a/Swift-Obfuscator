import Foundation

struct ExplicitCodingKeyPairRenameTemplate: Sendable {
    let codingKeysEnumUSR: String
    let nominalOwnerUSR: String
    let propertyUSR: String
    let caseTemplate: EnumCaseMemberRenameTemplate

    var caseUSR: String { caseTemplate.usr }
    var key: String { "\(propertyUSR)|\(caseUSR)" }
}

struct ExplicitCodingKeyRenamePlanningResult: Sendable {
    let pairTemplates: [ExplicitCodingKeyPairRenameTemplate]

    var propertyUSRs: Set<String> {
        Set(pairTemplates.map(\.propertyUSR))
    }

    var caseUSRs: Set<String> {
        Set(pairTemplates.map(\.caseUSR))
    }
}

/// Builds the source-closed half of an explicit CodingKeys rename component.
///
/// IndexStoreDB supplies both ownership edges: nominal owner -> stored property
/// and nominal owner -> CodingKeys enum -> enum case. SwiftSyntax supplies exact
/// declaration/reference ranges and identifies the raw-value literal belonging
/// to a case. A property/case pair is eligible only when both source spellings
/// agree and the old raw value is already explicit or compiler-derived.
enum ExplicitCodingKeyRenamePlanning {
    static func makeResult(
        syntaxFacts: EnumCaseSyntaxFacts,
        semanticFacts: EnumCaseComponentFacts,
        indexedFacts: IndexedSemanticFacts,
        groupsByUSR: [String: USROccurrenceGroup],
        analyzer: SafetyAnalyzer,
        sourceCache: SourceFileCache,
        excludedPropertyUSRs: Set<String>
    ) -> ExplicitCodingKeyRenamePlanningResult {
        let semanticByOwner = Dictionary(
            uniqueKeysWithValues: semanticFacts.components.map { ($0.ownerUSR, $0) }
        )
        var candidates: [ExplicitCodingKeyPairCandidate] = []

        for component in syntaxFacts.components {
            guard let semanticComponent = semanticByOwner[component.ownerUSR],
                  semanticComponent.isExplicitCodingKeys,
                  semanticComponent.hasRawType,
                  semanticComponent.protocolConformanceUSRs.contains(codingKeyProtocolUSR),
                  let nominalOwnerUSR = indexedFacts
                    .explicitCodingKeysOwnerUSRByEnumUSR[component.ownerUSR],
                  indexedFacts.serializationSensitiveOwnerUSRs.contains(nominalOwnerUSR) else {
                continue
            }

            var componentBlockers = Set(component.blockers)
            componentBlockers.remove(.codingKeyContract)
            guard componentBlockers.isEmpty else {
                continue
            }

            let propertyUSRsByName = Dictionary(grouping:
                indexedFacts.directStoredPropertyUSRs(of: nominalOwnerUSR).filter { propertyUSR in
                    !excludedPropertyUSRs.contains(propertyUSR)
                        && groupsByUSR[propertyUSR]?.symbol.isKind(.instanceProperty) == true
                }
            ) { propertyUSR in
                groupsByUSR[propertyUSR]?.symbol.name ?? ""
            }
            let semanticMembersByUSR = Dictionary(
                uniqueKeysWithValues: semanticComponent.members.map { ($0.usr, $0) }
            )

            for member in component.members {
                guard let declarationToken = member.declarationToken,
                      let semanticMember = semanticMembersByUSR[member.caseUSR],
                      !semanticMember.hasAssociatedValues,
                      member.hasExplicitRawValue || member.implicitRawValueLiteral != nil,
                      let propertyUSRs = propertyUSRsByName[declarationToken.name],
                      propertyUSRs.count == 1,
                      let propertyUSR = propertyUSRs.first,
                      groupsByUSR[propertyUSR]?.symbol.name == declarationToken.name else {
                    continue
                }

                // Swift.CodingKey's description/debugDescription are derived
                // from stringValue/intValue, not from the enum-case spelling.
                // This pair preserves an explicit raw value or materializes the
                // compiler-derived one, so equal string literals remain stable
                // storage/network data rather than a second identifier contract.
                // Direct interpolation and every other enum blocker stay active
                // at the owner/component layer.
                var memberBlockers = Set(member.blockers)
                memberBlockers.remove(.stringLiteralSpelling)
                guard memberBlockers.isEmpty else {
                    continue
                }

                candidates.append(ExplicitCodingKeyPairCandidate(
                    codingKeysEnumUSR: component.ownerUSR,
                    nominalOwnerUSR: nominalOwnerUSR,
                    propertyUSR: propertyUSR,
                    member: member
                ))
            }
        }

        let coordinatedCaseUSRs = Set(candidates.map { $0.member.caseUSR })
        let templates = candidates.compactMap { candidate
            -> ExplicitCodingKeyPairRenameTemplate? in
            let result = EnumCaseRenamePlanning.memberTemplate(
                member: candidate.member,
                groupsByUSR: groupsByUSR,
                indexedFacts: indexedFacts,
                analyzer: analyzer,
                sourceCache: sourceCache,
                coordinatedEnumCaseUSRs: coordinatedCaseUSRs
            )
            guard result.failures.isEmpty, let caseTemplate = result.template else {
                return nil
            }
            return ExplicitCodingKeyPairRenameTemplate(
                codingKeysEnumUSR: candidate.codingKeysEnumUSR,
                nominalOwnerUSR: candidate.nominalOwnerUSR,
                propertyUSR: candidate.propertyUSR,
                caseTemplate: caseTemplate
            )
        }.sorted { lhs, rhs in
            (lhs.codingKeysEnumUSR, lhs.propertyUSR, lhs.caseUSR)
                < (rhs.codingKeysEnumUSR, rhs.propertyUSR, rhs.caseUSR)
        }

        return ExplicitCodingKeyRenamePlanningResult(pairTemplates: templates)
    }

    static func denialDecisions(
        pair: ExplicitCodingKeyPairRenameTemplate,
        groupsByUSR: [String: USROccurrenceGroup],
        reasons: [String]
    ) -> [SafetyDecision] {
        [pair.propertyUSR, pair.caseUSR].map { usr in
            let group = groupsByUSR[usr]
            return SafetyDecision(
                usr: usr,
                symbolName: group?.symbol.name ?? pair.caseTemplate.oldName,
                kind: group?.symbol.kind ?? (usr == pair.caseUSR
                    ? IndexSymbolKind.enumConstant.rawValue
                    : IndexSymbolKind.instanceProperty.rawValue),
                allowed: false,
                oldName: pair.caseTemplate.oldName,
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
    // protocol identities used by IndexedSemanticFacts.
    private static let codingKeyProtocolUSR = "s:s9CodingKeyP"

}

private struct ExplicitCodingKeyPairCandidate {
    let codingKeysEnumUSR: String
    let nominalOwnerUSR: String
    let propertyUSR: String
    let member: EnumCaseMemberSyntaxFact
}
