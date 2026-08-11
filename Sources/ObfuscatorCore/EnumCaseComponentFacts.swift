import Foundation

public struct EnumCaseComponentMember: Codable, Equatable, Sendable {
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

public struct EnumCaseOwnerComponent: Codable, Equatable, Sendable {
    public let ownerUSR: String
    public let ownerName: String
    public let members: [EnumCaseComponentMember]
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

public struct UnresolvedEnumCaseComponentFact: Codable, Equatable, Sendable {
    public let caseUSR: String
    public let reason: String
}

public struct EnumCaseComponentFactsSummary: Codable, Equatable, Sendable {
    public let explicitEnumCases: Int
    public let resolvedEnumCases: Int
    public let unresolvedEnumCases: Int
    public let ownerComponents: Int
    public let rawTypeOwnerComponents: Int
    public let rawTypeCases: Int
    public let protocolConformanceOwnerComponents: Int
    public let protocolConformanceCases: Int
    public let protocolWitnessOwnerComponents: Int
    public let protocolWitnessCases: Int
    public let serializationSensitiveOwnerComponents: Int
    public let serializationSensitiveCases: Int
    public let runtimeSensitiveOwnerComponents: Int
    public let runtimeSensitiveCases: Int
    public let externallyOwnedOwnerComponents: Int
    public let externallyOwnedCases: Int
    public let ownerComponentsWithOccurrencesOutsideSelectedRoots: Int
    public let casesWithOccurrencesOutsideSelectedRoots: Int
    public let associatedValueCases: Int
    public let associatedValueParameters: Int
    public let casesWithoutRawSerializationOrRuntimeContracts: Int
    public let components: [EnumCaseOwnerComponent]
    public let unresolved: [UnresolvedEnumCaseComponentFact]

    public static let empty = EnumCaseComponentFactsSummary(
        explicitEnumCases: 0,
        resolvedEnumCases: 0,
        unresolvedEnumCases: 0,
        ownerComponents: 0,
        rawTypeOwnerComponents: 0,
        rawTypeCases: 0,
        protocolConformanceOwnerComponents: 0,
        protocolConformanceCases: 0,
        protocolWitnessOwnerComponents: 0,
        protocolWitnessCases: 0,
        serializationSensitiveOwnerComponents: 0,
        serializationSensitiveCases: 0,
        runtimeSensitiveOwnerComponents: 0,
        runtimeSensitiveCases: 0,
        externallyOwnedOwnerComponents: 0,
        externallyOwnedCases: 0,
        ownerComponentsWithOccurrencesOutsideSelectedRoots: 0,
        casesWithOccurrencesOutsideSelectedRoots: 0,
        associatedValueCases: 0,
        associatedValueParameters: 0,
        casesWithoutRawSerializationOrRuntimeContracts: 0,
        components: [],
        unresolved: []
    )
}

public struct EnumCaseComponentFacts: Sendable {
    public let components: [EnumCaseOwnerComponent]
    public let unresolved: [UnresolvedEnumCaseComponentFact]
    public let summary: EnumCaseComponentFactsSummary

    public init(
        snapshot: IndexSnapshot,
        indexedFacts: IndexedSemanticFacts,
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
            occurrence.symbol.kind == "enumConstant"
                && !occurrence.roles.contains("implicit")
                && (occurrence.roles.contains("declaration")
                    || occurrence.roles.contains("definition"))
                && Self.isPath(occurrence.path, underRootPaths: rootPaths)
        }
        let declarationsByUSR = Dictionary(grouping: declarationOccurrences, by: \.usr)
        let allOccurrencesByUSR = Dictionary(grouping: snapshot.occurrences, by: \.usr)

        var rawTypeUSRsByOwner: [String: Set<String>] = [:]
        var protocolUSRsByOwner: [String: Set<String>] = [:]
        for occurrence in snapshot.occurrences where occurrence.roles.contains("baseOf") {
            for relation in occurrence.relations where relation.roles.contains("baseOf") {
                guard symbolsByUSR[relation.usr]?.kind == "enum" else {
                    continue
                }
                if occurrence.symbol.kind == "protocol" {
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
            grouping: indexedFacts.parameterRenameComponents.filter {
                $0.ownerCategory == .enumCase
            },
            by: \.callableUSR
        ).mapValues { components in
            Array(Set(components.flatMap { $0.members.map(\.parameterUSR) })).sorted()
        }

        var membersByOwner: [String: [EnumCaseComponentMember]] = [:]
        var unresolved: [UnresolvedEnumCaseComponentFact] = []
        for caseUSR in declarationsByUSR.keys.sorted() {
            let declarations = declarationsByUSR[caseUSR] ?? []
            let ownerUSRs = Set(declarations.flatMap { occurrence in
                occurrence.relations.compactMap { relation in
                    relation.roles.contains("childOf") ? relation.usr : nil
                }
            })
            guard ownerUSRs.count == 1, let ownerUSR = ownerUSRs.first else {
                unresolved.append(UnresolvedEnumCaseComponentFact(
                    caseUSR: caseUSR,
                    reason: ownerUSRs.isEmpty
                        ? "indexed enum owner unavailable"
                        : "indexed enum owner is ambiguous"
                ))
                continue
            }
            guard symbolsByUSR[ownerUSR]?.kind == "enum" else {
                unresolved.append(UnresolvedEnumCaseComponentFact(
                    caseUSR: caseUSR,
                    reason: "indexed owner is not an enum"
                ))
                continue
            }
            guard let symbol = symbolsByUSR[caseUSR] else {
                unresolved.append(UnresolvedEnumCaseComponentFact(
                    caseUSR: caseUSR,
                    reason: "enum case symbol unavailable"
                ))
                continue
            }
            membersByOwner[ownerUSR, default: []].append(EnumCaseComponentMember(
                usr: caseUSR,
                name: symbol.name,
                associatedValueParameterUSRs: associatedParametersByCase[caseUSR] ?? [],
                protocolRequirementUSRs: Array(Set(
                    (allOccurrencesByUSR[caseUSR] ?? []).flatMap { occurrence in
                        occurrence.relations.compactMap { relation in
                            relation.roles.contains("overrideOf") ? relation.usr : nil
                        }
                    }
                )).sorted()
            ))
        }

        let components = membersByOwner.keys.sorted().map { ownerUSR in
            let members = (membersByOwner[ownerUSR] ?? []).sorted { $0.usr < $1.usr }
            let memberUSRs = Set(members.map(\.usr))
            let componentUSRs = memberUSRs.union([ownerUSR])
            let hasOccurrencesOutsideSelectedRoots = componentUSRs.contains { usr in
                (allOccurrencesByUSR[usr] ?? []).contains { occurrence in
                    !Self.isPath(occurrence.path, underRootPaths: rootPaths)
                }
            }
            return EnumCaseOwnerComponent(
                ownerUSR: ownerUSR,
                ownerName: symbolsByUSR[ownerUSR]?.name ?? ownerUSR,
                members: members,
                rawTypeUSRs: (rawTypeUSRsByOwner[ownerUSR] ?? []).sorted(),
                protocolConformanceUSRs: (protocolUSRsByOwner[ownerUSR] ?? []).sorted(),
                isExplicitCodingKeys:
                    indexedFacts.explicitCodingKeysEnumUSRs.contains(ownerUSR),
                isSerializationSensitive:
                    indexedFacts.serializationSensitiveOwnerUSRs.contains(ownerUSR),
                hasExplicitCodingKeys:
                    indexedFacts.explicitCodingKeysOwnerUSRs.contains(ownerUSR),
                hasCustomSerializationImplementation:
                    indexedFacts.customSerializationImplementationOwnerUSRs.contains(ownerUSR),
                isRuntimeSensitive: !componentUSRs.isDisjoint(
                    with: indexedFacts.runtimeSensitiveUSRs
                ),
                isExternallyOwned: !componentUSRs.isDisjoint(
                    with: indexedFacts.externallyOwnedUSRs
                ),
                hasOccurrencesOutsideSelectedRoots: hasOccurrencesOutsideSelectedRoots
            )
        }

        self.components = components
        self.unresolved = unresolved.sorted {
            ($0.caseUSR, $0.reason) < ($1.caseUSR, $1.reason)
        }
        self.summary = EnumCaseComponentFacts.makeSummary(
            explicitEnumCases: declarationsByUSR.count,
            components: components,
            unresolved: self.unresolved
        )
    }

    private static func makeSummary(
        explicitEnumCases: Int,
        components: [EnumCaseOwnerComponent],
        unresolved: [UnresolvedEnumCaseComponentFact]
    ) -> EnumCaseComponentFactsSummary {
        func caseCount(where predicate: (EnumCaseOwnerComponent) -> Bool) -> Int {
            components.filter(predicate).reduce(0) { $0 + $1.members.count }
        }

        let associatedValueCases = components.reduce(0) { total, component in
            total + component.members.count(where: \.hasAssociatedValues)
        }
        let associatedValueParameters = components.reduce(0) { total, component in
            total + component.associatedValueParameterUSRs.count
        }
        return EnumCaseComponentFactsSummary(
            explicitEnumCases: explicitEnumCases,
            resolvedEnumCases: components.reduce(0) { $0 + $1.members.count },
            unresolvedEnumCases: unresolved.count,
            ownerComponents: components.count,
            rawTypeOwnerComponents: components.count(where: \.hasRawType),
            rawTypeCases: caseCount(where: \.hasRawType),
            protocolConformanceOwnerComponents: components.count(
                where: \.hasProtocolConformance
            ),
            protocolConformanceCases: caseCount(where: \.hasProtocolConformance),
            protocolWitnessOwnerComponents: components.count(
                where: \.hasProtocolCaseWitness
            ),
            protocolWitnessCases: caseCount(where: \.hasProtocolCaseWitness),
            serializationSensitiveOwnerComponents: components.count {
                $0.isSerializationSensitive
            },
            serializationSensitiveCases: caseCount(where: \.isSerializationSensitive),
            runtimeSensitiveOwnerComponents: components.count(where: \.isRuntimeSensitive),
            runtimeSensitiveCases: caseCount(where: \.isRuntimeSensitive),
            externallyOwnedOwnerComponents: components.count(where: \.isExternallyOwned),
            externallyOwnedCases: caseCount(where: \.isExternallyOwned),
            ownerComponentsWithOccurrencesOutsideSelectedRoots: components.count {
                $0.hasOccurrencesOutsideSelectedRoots
            },
            casesWithOccurrencesOutsideSelectedRoots: caseCount(
                where: \.hasOccurrencesOutsideSelectedRoots
            ),
            associatedValueCases: associatedValueCases,
            associatedValueParameters: associatedValueParameters,
            casesWithoutRawSerializationOrRuntimeContracts: caseCount { component in
                !component.hasRawType
                    && !component.isSerializationSensitive
                    && !component.isRuntimeSensitive
            },
            components: components,
            unresolved: unresolved
        )
    }

    private static func isPath(_ path: String, underRootPaths roots: [String]) -> Bool {
        let canonicalPath = SourcePathNormalizer.canonicalPath(path)
        return roots.contains { root in
            canonicalPath == root || canonicalPath.hasPrefix(root + "/")
        }
    }
}
