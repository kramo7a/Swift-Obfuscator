import Foundation

public enum EnumCaseSemantics {
    public struct Member: Codable, Equatable, Sendable {
        public let usr: String
        public let name: String
        public let associatedValueParameterUSRs: [String]
        public let protocolRequirementUSRs: [String]

        public var hasAssociatedValues: Bool {
            !associatedValueParameterUSRs.isEmpty
        }

        public var isProtocolRequirementWitness: Bool {
            !protocolRequirementUSRs.isEmpty
        }
    }

    public struct Owner: Codable, Equatable, Sendable {
        public let ownerUSR: String
        public let ownerName: String
        public let members: [EnumCaseSemantics.Member]
        public let rawTypeUSRs: [String]
        public let protocolConformanceUSRs: [String]
        public let isExplicitCodingKeys: Bool
        public let isSerializationSensitive: Bool
        public let hasExplicitCodingKeys: Bool
        public let hasCustomSerializationImplementation: Bool
        public let isRuntimeSensitive: Bool
        public let isExternallyOwned: Bool
        public let hasOccurrencesOutsideSelectedRoots: Bool

        public var caseUSRs: [String] {
            members.map(\.usr)
        }

        public var associatedValueParameterUSRs: [String] {
            members.flatMap(\.associatedValueParameterUSRs)
        }

        public var hasRawType: Bool {
            !rawTypeUSRs.isEmpty
        }

        public var hasProtocolConformance: Bool {
            !protocolConformanceUSRs.isEmpty
        }

        public var hasProtocolCaseWitness: Bool {
            members.contains(where: \.isProtocolRequirementWitness)
        }

        public var hasManualSerializationContract: Bool {
            hasExplicitCodingKeys || hasCustomSerializationImplementation
        }
    }

    public struct Issue: Codable, Equatable, Sendable {
        public let caseUSR: String
        public let reason: String
    }

    public struct Report: Codable, Equatable, Sendable {
        public let explicitEnumCases: Int
        public let resolvedEnumCases: Int
        public let unresolvedEnumCases: Int
        public let ownerCount: Int
        public let rawTypeOwnerCount: Int
        public let rawTypeCases: Int
        public let protocolConformanceOwnerCount: Int
        public let protocolConformanceCases: Int
        public let protocolWitnessOwnerCount: Int
        public let protocolWitnessCases: Int
        public let serializationSensitiveOwnerCount: Int
        public let serializationSensitiveCases: Int
        public let runtimeSensitiveOwnerCount: Int
        public let runtimeSensitiveCases: Int
        public let externallyOwnedOwnerCount: Int
        public let externallyOwnedCases: Int
        public let ownersWithOccurrencesOutsideSelectedRoots: Int
        public let casesWithOccurrencesOutsideSelectedRoots: Int
        public let associatedValueCases: Int
        public let associatedValueParameters: Int
        public let casesWithoutRawSerializationOrRuntimeContracts: Int
        public let owners: [EnumCaseSemantics.Owner]
        public let issues: [EnumCaseSemantics.Issue]

        public static let empty = EnumCaseSemantics.Report(
            explicitEnumCases: 0,
            resolvedEnumCases: 0,
            unresolvedEnumCases: 0,
            ownerCount: 0,
            rawTypeOwnerCount: 0,
            rawTypeCases: 0,
            protocolConformanceOwnerCount: 0,
            protocolConformanceCases: 0,
            protocolWitnessOwnerCount: 0,
            protocolWitnessCases: 0,
            serializationSensitiveOwnerCount: 0,
            serializationSensitiveCases: 0,
            runtimeSensitiveOwnerCount: 0,
            runtimeSensitiveCases: 0,
            externallyOwnedOwnerCount: 0,
            externallyOwnedCases: 0,
            ownersWithOccurrencesOutsideSelectedRoots: 0,
            casesWithOccurrencesOutsideSelectedRoots: 0,
            associatedValueCases: 0,
            associatedValueParameters: 0,
            casesWithoutRawSerializationOrRuntimeContracts: 0,
            owners: [],
            issues: []
        )

        private enum CodingKeys: String, CodingKey {
            case explicitEnumCases
            case resolvedEnumCases
            case unresolvedEnumCases
            case ownerCount = "ownerComponents"
            case rawTypeOwnerCount = "rawTypeOwnerComponents"
            case rawTypeCases
            case protocolConformanceOwnerCount = "protocolConformanceOwnerComponents"
            case protocolConformanceCases
            case protocolWitnessOwnerCount = "protocolWitnessOwnerComponents"
            case protocolWitnessCases
            case serializationSensitiveOwnerCount = "serializationSensitiveOwnerComponents"
            case serializationSensitiveCases
            case runtimeSensitiveOwnerCount = "runtimeSensitiveOwnerComponents"
            case runtimeSensitiveCases
            case externallyOwnedOwnerCount = "externallyOwnedOwnerComponents"
            case externallyOwnedCases
            case ownersWithOccurrencesOutsideSelectedRoots =
                "ownerComponentsWithOccurrencesOutsideSelectedRoots"
            case casesWithOccurrencesOutsideSelectedRoots
            case associatedValueCases
            case associatedValueParameters
            case casesWithoutRawSerializationOrRuntimeContracts
            case owners = "components"
            case issues = "unresolved"
        }
    }

    public struct Index: Sendable {
        public let owners: [EnumCaseSemantics.Owner]
        public let issues: [EnumCaseSemantics.Issue]
        public let report: EnumCaseSemantics.Report

        public init(
            snapshot: IndexSnapshot,
            semanticIndex: SemanticIndex,
            obfuscationRoots: [URL]
        ) {
            let rootPaths = obfuscationRoots.map {
                $0.resolvingSymlinksInPath().standardizedFileURL.path
            }
            let symbolsByUSR = Dictionary(
                snapshot.symbols.map { ($0.usr, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let declarationOccurrences = snapshot.occurrences.filter { occurrence in
                occurrence.symbol.isKind(.enumConstant)
                    && !occurrence.hasRole(.implicit)
                    && (occurrence.hasRole(.declaration)
                        || occurrence.hasRole(.definition))
                    && Self.isPath(occurrence.path, underRootPaths: rootPaths)
            }
            let declarationsByUSR = Dictionary(grouping: declarationOccurrences, by: \.usr)
            let allOccurrencesByUSR = Dictionary(grouping: snapshot.occurrences, by: \.usr)

            var rawTypeUSRsByOwner: [String: Set<String>] = [:]
            var protocolUSRsByOwner: [String: Set<String>] = [:]
            for occurrence in snapshot.occurrences where occurrence.hasRole(.baseOf) {
                for relation in occurrence.relations where relation.hasRole(.baseOf) {
                    guard symbolsByUSR[relation.usr]?.isKind(.enum) == true else {
                        continue
                    }
                    if occurrence.symbol.isKind(.protocol) {
                        protocolUSRsByOwner[relation.usr, default: []].insert(occurrence.usr)
                    } else {
                        // On an enum declaration, a semantic non-protocol `baseOf`
                        // edge is the raw type. This avoids hardcoding String/Int or
                        // any target-project type spelling.
                        rawTypeUSRsByOwner[relation.usr, default: []].insert(occurrence.usr)
                    }
                }
            }

            let associatedParametersByCase = Dictionary(
                grouping: semanticIndex.callableSignatures.filter {
                    $0.ownerCategory == .enumCase
                },
                by: \.callableUSR
            ).mapValues { signatures in
                Array(Set(signatures.flatMap { $0.parameters.map(\.parameterUSR) })).sorted()
            }

            var membersByOwner: [String: [EnumCaseSemantics.Member]] = [:]
            var issues: [EnumCaseSemantics.Issue] = []
            for caseUSR in declarationsByUSR.keys.sorted() {
                let declarations = declarationsByUSR[caseUSR] ?? []
                let ownerUSRs = Set(
                    declarations.flatMap { occurrence in
                        occurrence.relations.compactMap { relation in
                            relation.hasRole(.childOf) ? relation.usr : nil
                        }
                    })
                guard ownerUSRs.count == 1, let ownerUSR = ownerUSRs.first else {
                    issues.append(
                        EnumCaseSemantics.Issue(
                            caseUSR: caseUSR,
                            reason: ownerUSRs.isEmpty
                                ? "indexed enum owner unavailable"
                                : "indexed enum owner is ambiguous"
                        ))
                    continue
                }
                guard symbolsByUSR[ownerUSR]?.isKind(.enum) == true else {
                    issues.append(
                        EnumCaseSemantics.Issue(
                            caseUSR: caseUSR,
                            reason: "indexed owner is not an enum"
                        ))
                    continue
                }
                guard let symbol = symbolsByUSR[caseUSR] else {
                    issues.append(
                        EnumCaseSemantics.Issue(
                            caseUSR: caseUSR,
                            reason: "enum case symbol unavailable"
                        ))
                    continue
                }
                membersByOwner[ownerUSR, default: []].append(
                    EnumCaseSemantics.Member(
                        usr: caseUSR,
                        name: symbol.name,
                        associatedValueParameterUSRs: associatedParametersByCase[caseUSR] ?? [],
                        protocolRequirementUSRs: Array(
                            Set(
                                (allOccurrencesByUSR[caseUSR] ?? []).flatMap { occurrence in
                                    occurrence.relations.compactMap { relation in
                                        relation.hasRole(.overrideOf) ? relation.usr : nil
                                    }
                                }
                            )
                        ).sorted()
                    ))
            }

            let owners = membersByOwner.keys.sorted().map { ownerUSR in
                let members = (membersByOwner[ownerUSR] ?? []).sorted { $0.usr < $1.usr }
                let memberUSRs = Set(members.map(\.usr))
                let ownerAndMemberUSRs = memberUSRs.union([ownerUSR])
                let hasOccurrencesOutsideSelectedRoots = ownerAndMemberUSRs.contains { usr in
                    (allOccurrencesByUSR[usr] ?? []).contains { occurrence in
                        !Self.isPath(occurrence.path, underRootPaths: rootPaths)
                    }
                }
                return EnumCaseSemantics.Owner(
                    ownerUSR: ownerUSR,
                    ownerName: symbolsByUSR[ownerUSR]?.name ?? ownerUSR,
                    members: members,
                    rawTypeUSRs: (rawTypeUSRsByOwner[ownerUSR] ?? []).sorted(),
                    protocolConformanceUSRs: (protocolUSRsByOwner[ownerUSR] ?? []).sorted(),
                    isExplicitCodingKeys:
                        semanticIndex.explicitCodingKeysEnumUSRs.contains(ownerUSR),
                    isSerializationSensitive:
                        semanticIndex.serializationSensitiveOwnerUSRs.contains(ownerUSR),
                    hasExplicitCodingKeys:
                        semanticIndex.explicitCodingKeysOwnerUSRs.contains(ownerUSR),
                    hasCustomSerializationImplementation:
                        semanticIndex.customSerializationImplementationOwnerUSRs.contains(ownerUSR),
                    isRuntimeSensitive: !ownerAndMemberUSRs.isDisjoint(
                        with: semanticIndex.runtimeSensitiveUSRs
                    ),
                    isExternallyOwned: !ownerAndMemberUSRs.isDisjoint(
                        with: semanticIndex.externallyOwnedUSRs
                    ),
                    hasOccurrencesOutsideSelectedRoots: hasOccurrencesOutsideSelectedRoots
                )
            }

            self.owners = owners
            self.issues = issues.sorted {
                ($0.caseUSR, $0.reason) < ($1.caseUSR, $1.reason)
            }
            self.report = EnumCaseSemantics.Index.makeReport(
                explicitEnumCases: declarationsByUSR.count,
                owners: owners,
                issues: self.issues
            )
        }

        private static func makeReport(
            explicitEnumCases: Int,
            owners: [EnumCaseSemantics.Owner],
            issues: [EnumCaseSemantics.Issue]
        ) -> EnumCaseSemantics.Report {
            func caseCount(where predicate: (EnumCaseSemantics.Owner) -> Bool) -> Int {
                owners.filter(predicate).reduce(0) { $0 + $1.members.count }
            }

            let associatedValueCases = owners.reduce(0) { total, owner in
                total + owner.members.count(where: \.hasAssociatedValues)
            }
            let associatedValueParameters = owners.reduce(0) { total, owner in
                total + owner.associatedValueParameterUSRs.count
            }
            return EnumCaseSemantics.Report(
                explicitEnumCases: explicitEnumCases,
                resolvedEnumCases: owners.reduce(0) { $0 + $1.members.count },
                unresolvedEnumCases: issues.count,
                ownerCount: owners.count,
                rawTypeOwnerCount: owners.count(where: \.hasRawType),
                rawTypeCases: caseCount(where: \.hasRawType),
                protocolConformanceOwnerCount: owners.count(
                    where: \.hasProtocolConformance
                ),
                protocolConformanceCases: caseCount(where: \.hasProtocolConformance),
                protocolWitnessOwnerCount: owners.count(
                    where: \.hasProtocolCaseWitness
                ),
                protocolWitnessCases: caseCount(where: \.hasProtocolCaseWitness),
                serializationSensitiveOwnerCount: owners.count {
                    $0.isSerializationSensitive
                },
                serializationSensitiveCases: caseCount(where: \.isSerializationSensitive),
                runtimeSensitiveOwnerCount: owners.count(where: \.isRuntimeSensitive),
                runtimeSensitiveCases: caseCount(where: \.isRuntimeSensitive),
                externallyOwnedOwnerCount: owners.count(where: \.isExternallyOwned),
                externallyOwnedCases: caseCount(where: \.isExternallyOwned),
                ownersWithOccurrencesOutsideSelectedRoots: owners.count {
                    $0.hasOccurrencesOutsideSelectedRoots
                },
                casesWithOccurrencesOutsideSelectedRoots: caseCount(
                    where: \.hasOccurrencesOutsideSelectedRoots
                ),
                associatedValueCases: associatedValueCases,
                associatedValueParameters: associatedValueParameters,
                casesWithoutRawSerializationOrRuntimeContracts: caseCount { owner in
                    !owner.hasRawType
                        && !owner.isSerializationSensitive
                        && !owner.isRuntimeSensitive
                },
                owners: owners,
                issues: issues
            )
        }

        private static func isPath(_ path: String, underRootPaths roots: [String]) -> Bool {
            let canonicalPath = SourcePathNormalizer.canonicalPath(path)
            return roots.contains { root in
                canonicalPath == root || canonicalPath.hasPrefix(root + "/")
            }
        }
    }

}
