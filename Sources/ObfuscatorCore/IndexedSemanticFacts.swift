import Foundation
import IndexStoreDB

/// Semantic declaration facts derived from the compiler index for one snapshot.
///
/// SafetyAnalyzer consumes this value instead of reconstructing Swift ownership
/// or declaration nesting from source braces. Source text remains responsible
/// only for lexical token/range validation and the few syntax facts that the
/// index does not encode.
public struct IndexedSemanticFacts: Sendable {
    public let selectedDeclarationUSRs: Set<String>
    public let protocolRequirementUSRs: Set<String>
    public let externallyOwnedUSRs: Set<String>
    public let runtimeSensitiveUSRs: Set<String>
    public let storedPropertyUSRs: Set<String>
    public let decodingSensitiveOwnerUSRs: Set<String>
    public let encodingSensitiveOwnerUSRs: Set<String>
    public let serializationSensitiveOwnerUSRs: Set<String>
    public let explicitCodingKeysEnumUSRs: Set<String>
    public let explicitCodingKeysOwnerUSRByEnumUSR: [String: String]
    public let explicitCodingKeysOwnerUSRs: Set<String>
    public let customDecodingImplementationOwnerUSRs: Set<String>
    public let customEncodingImplementationOwnerUSRs: Set<String>
    public let customSerializationImplementationOwnerUSRs: Set<String>
    public let propertyWrapperDerivedUSRsByPropertyUSR: [String: Set<String>]
    public let overrideRelationNeighbors: [String: Set<String>]
    public let overrideRelatedUSRs: Set<String>
    public let parameterRenameComponents: [ParameterRenameComponent]
    public let parameterFactsSummary: ParameterFactsSummary

    let symbolsByUSR: [String: SymbolRecord]
    let ownerUSRsByChild: [String: Set<String>]
    let childUSRsByOwner: [String: Set<String>]
    let extensionTargetUSRs: [String: Set<String>]
    let nominalSubtypeUSRsByBase: [String: Set<String>]

    public init(
        selectedDeclarationUSRs: Set<String> = [],
        protocolRequirementUSRs: Set<String> = [],
        externallyOwnedUSRs: Set<String> = [],
        runtimeSensitiveUSRs: Set<String> = [],
        storedPropertyUSRs: Set<String> = [],
        decodingSensitiveOwnerUSRs: Set<String> = [],
        encodingSensitiveOwnerUSRs: Set<String> = [],
        serializationSensitiveOwnerUSRs: Set<String> = [],
        explicitCodingKeysEnumUSRs: Set<String> = [],
        explicitCodingKeysOwnerUSRByEnumUSR: [String: String] = [:],
        explicitCodingKeysOwnerUSRs: Set<String> = [],
        customDecodingImplementationOwnerUSRs: Set<String> = [],
        customEncodingImplementationOwnerUSRs: Set<String> = [],
        customSerializationImplementationOwnerUSRs: Set<String> = [],
        propertyWrapperDerivedUSRsByPropertyUSR: [String: Set<String>] = [:],
        overrideRelationNeighbors: [String: Set<String>] = [:],
        parameterRenameComponents: [ParameterRenameComponent] = [],
        parameterFactsSummary: ParameterFactsSummary = .empty
    ) {
        self.selectedDeclarationUSRs = selectedDeclarationUSRs
        self.protocolRequirementUSRs = protocolRequirementUSRs
        self.externallyOwnedUSRs = externallyOwnedUSRs
        self.runtimeSensitiveUSRs = runtimeSensitiveUSRs
        self.storedPropertyUSRs = storedPropertyUSRs
        self.decodingSensitiveOwnerUSRs = decodingSensitiveOwnerUSRs
        self.encodingSensitiveOwnerUSRs = encodingSensitiveOwnerUSRs
        self.serializationSensitiveOwnerUSRs = serializationSensitiveOwnerUSRs
        self.explicitCodingKeysEnumUSRs = explicitCodingKeysEnumUSRs
        self.explicitCodingKeysOwnerUSRByEnumUSR = explicitCodingKeysOwnerUSRByEnumUSR
        self.explicitCodingKeysOwnerUSRs = explicitCodingKeysOwnerUSRs
        self.customDecodingImplementationOwnerUSRs = customDecodingImplementationOwnerUSRs
        self.customEncodingImplementationOwnerUSRs = customEncodingImplementationOwnerUSRs
        self.customSerializationImplementationOwnerUSRs = customSerializationImplementationOwnerUSRs
        self.propertyWrapperDerivedUSRsByPropertyUSR = propertyWrapperDerivedUSRsByPropertyUSR
        self.overrideRelationNeighbors = overrideRelationNeighbors
        self.overrideRelatedUSRs = Self.relatedUSRs(in: overrideRelationNeighbors)
        self.parameterRenameComponents = parameterRenameComponents
        self.parameterFactsSummary = parameterFactsSummary
        self.symbolsByUSR = [:]
        self.ownerUSRsByChild = [:]
        self.childUSRsByOwner = [:]
        self.extensionTargetUSRs = [:]
        self.nominalSubtypeUSRsByBase = [:]
    }

    public init(snapshot: IndexSnapshot, obfuscationRoots: [URL]) {
        let rootPaths = obfuscationRoots.map {
            $0.resolvingSymlinksInPath().standardizedFileURL.path
        }
        let symbolsByUSR = Dictionary(
            snapshot.symbols.map { ($0.usr, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var selectedDeclarationUSRs: Set<String> = []
        var explicitDeclarationUSRs: Set<String> = []
        var ownerUSRsByChild: [String: Set<String>] = [:]
        var childUSRsByOwner: [String: Set<String>] = [:]
        var extensionTargetUSRs: [String: Set<String>] = [:]
        var nominalSubtypeUSRsByBase: [String: Set<String>] = [:]
        var overrideRelationNeighbors: [String: Set<String>] = [:]
        var runtimeDispatchNeighbors: [String: Set<String>] = [:]
        var storedPropertyUSRs: Set<String> = []
        var decodingConformanceTargets: Set<String> = []
        var encodingConformanceTargets: Set<String> = []
        var serializationImplementationTargetsByCallableUSR: [String: Set<String>] = [:]
        var serializationImplementationNameByCallableUSR: [String: String] = [:]
        var knownDecodingWitnessUSRs: Set<String> = []
        var knownEncodingWitnessUSRs: Set<String> = []
        var parameterDeclarationSitesByCallableUSR: [String: Set<DeclarationLineSite>] = [:]
        var protocolUSRsByCallableAndSite:
            [String: [DeclarationLineSite: Set<String>]] = [:]
        var explicitPropertyUSRsBySite: [PropertyDeclarationSite: Set<String>] = [:]
        var implicitPropertyUSRsBySite: [PropertyDeclarationSite: Set<String>] = [:]
        var runtimeSeeds = Set(symbolsByUSR.values.compactMap { symbol -> String? in
            Self.isRuntimeSymbol(symbol) ? symbol.usr : nil
        })

        for occurrence in snapshot.occurrences {
            let isDeclaration = occurrence.hasRole(.declaration)
                || occurrence.hasRole(.definition)
            if isDeclaration, Self.isPath(occurrence.path, underRootPaths: rootPaths) {
                selectedDeclarationUSRs.insert(occurrence.usr)
                if !occurrence.hasRole(.implicit) {
                    explicitDeclarationUSRs.insert(occurrence.usr)
                }
                for relation in occurrence.relations where relation.hasRole(.childOf) {
                    ownerUSRsByChild[occurrence.usr, default: []].insert(relation.usr)
                    childUSRsByOwner[relation.usr, default: []].insert(occurrence.usr)
                }
            }

            if isDeclaration,
               occurrence.symbol.isKind(.parameter),
               !occurrence.hasRole(.implicit) {
                let site = DeclarationLineSite(
                    path: SourcePathNormalizer.canonicalPath(occurrence.path),
                    line: occurrence.line
                )
                for relation in occurrence.relations where relation.hasRole(.childOf) {
                    parameterDeclarationSitesByCallableUSR[relation.usr, default: []]
                        .insert(site)
                }
            }
            if occurrence.symbol.isKind(.protocol) {
                let site = DeclarationLineSite(
                    path: SourcePathNormalizer.canonicalPath(occurrence.path),
                    line: occurrence.line
                )
                for relation in occurrence.relations
                where relation.hasRole(.containedBy) {
                    protocolUSRsByCallableAndSite[relation.usr, default: [:]][
                        site,
                        default: []
                    ].insert(occurrence.usr)
                }
            }

            if occurrence.symbol.isKind(.instanceProperty),
               occurrence.hasRole(.definition),
               Self.isPath(occurrence.path, underRootPaths: rootPaths) {
                let owners = occurrence.relations.filter { $0.hasRole(.childOf) }
                if owners.count == 1, let ownerUSR = owners.first?.usr {
                    let site = PropertyDeclarationSite(
                        path: SourcePathNormalizer.canonicalPath(occurrence.path),
                        line: occurrence.line,
                        ownerUSR: ownerUSR
                    )
                    if occurrence.hasRole(.implicit) {
                        implicitPropertyUSRsBySite[site, default: []].insert(occurrence.usr)
                    } else {
                        explicitPropertyUSRsBySite[site, default: []].insert(occurrence.usr)
                    }
                }
            }

            if Self.hasRuntimeProperty(occurrence.symbol)
                || occurrence.relations.contains(where: { $0.hasRole(.ibTypeOf) }) {
                runtimeSeeds.insert(occurrence.usr)
            }

            if occurrence.hasRole(.definition),
               occurrence.hasRole(.implicit) {
                for relation in occurrence.relations where relation.hasRole(.accessorOf) {
                    guard symbolsByUSR[relation.usr]?.isKind(.instanceProperty) == true else {
                        continue
                    }
                    // A compiler-synthesized accessor definition is the semantic
                    // distinction IndexStore exposes between stored properties
                    // and source-authored computed accessors.
                    storedPropertyUSRs.insert(relation.usr)
                }
            }

            if occurrence.usr == Self.decodableProtocolUSR {
                for relation in occurrence.relations where relation.hasRole(.baseOf) {
                    decodingConformanceTargets.insert(relation.usr)
                }
            } else if occurrence.usr == Self.encodableProtocolUSR {
                for relation in occurrence.relations where relation.hasRole(.baseOf) {
                    encodingConformanceTargets.insert(relation.usr)
                }
            }

            if isDeclaration,
               !occurrence.hasRole(.implicit),
               Self.isSerializationImplementationSymbol(occurrence.symbol),
               Self.isPath(occurrence.path, underRootPaths: rootPaths) {
                for relation in occurrence.relations where relation.hasRole(.childOf) {
                    serializationImplementationTargetsByCallableUSR[
                        occurrence.usr,
                        default: []
                    ].insert(relation.usr)
                }
                serializationImplementationNameByCallableUSR[occurrence.usr] =
                    occurrence.symbol.name
                for relation in occurrence.relations where relation.hasRole(.overrideOf) {
                    if relation.name == Self.decodingRequirementName {
                        knownDecodingWitnessUSRs.insert(occurrence.usr)
                    } else if relation.name == Self.encodingRequirementName {
                        knownEncodingWitnessUSRs.insert(occurrence.usr)
                    }
                }
            }

            for relation in occurrence.relations where relation.hasRole(.extendedBy) {
                extensionTargetUSRs[relation.usr, default: []].insert(occurrence.usr)
            }
            if occurrence.symbol.isKind(.class),
               Self.isPath(occurrence.path, underRootPaths: rootPaths) {
                for relation in occurrence.relations
                where relation.hasRole(.baseOf)
                    && symbolsByUSR[relation.usr]?.isKind(.class) == true {
                    nominalSubtypeUSRsByBase[occurrence.usr, default: []]
                        .insert(relation.usr)
                }
            }
            for relation in occurrence.relations {
                let occurrenceIsSynthetic = IndexSymbolName.isSyntheticAccessor(occurrence.symbol.name)
                let targetIsSynthetic = IndexSymbolName.isSyntheticAccessor(
                    symbolsByUSR[relation.usr]?.name ?? relation.name
                )
                guard !occurrenceIsSynthetic, !targetIsSynthetic else {
                    continue
                }

                let isDispatchRelation = Self.isOverrideDispatchKind(occurrence.symbol.kind)
                    && Self.isOverrideRelation(relation)
                if relation.hasRole(.overrideOf) || isDispatchRelation {
                    overrideRelationNeighbors[occurrence.usr, default: []].insert(relation.usr)
                    overrideRelationNeighbors[relation.usr, default: []].insert(occurrence.usr)
                }
                if isDispatchRelation {
                    runtimeDispatchNeighbors[occurrence.usr, default: []].insert(relation.usr)
                    runtimeDispatchNeighbors[relation.usr, default: []].insert(occurrence.usr)
                    if Self.isRuntimeUSR(relation.usr, symbolsByUSR: symbolsByUSR) {
                        runtimeSeeds.insert(relation.usr)
                    }
                }
            }
        }

        let localNominalKinds = IndexSymbolKind.rawValues(.class, .struct, .enum, .protocol)
        let localNominalUSRs = Set(selectedDeclarationUSRs.compactMap { usr -> String? in
            guard let symbol = symbolsByUSR[usr],
                  localNominalKinds.contains(symbol.kind) else {
                return nil
            }
            return usr
        })
        let localProtocolUSRs = Set(localNominalUSRs.filter {
            symbolsByUSR[$0]?.isKind(.protocol) == true
        })

        let protocolRequirementUSRs = Set(selectedDeclarationUSRs.filter { usr in
            !(ownerUSRsByChild[usr] ?? []).isDisjoint(with: localProtocolUSRs)
        })

        let selectedExtensionUSRs = selectedDeclarationUSRs.filter {
            symbolsByUSR[$0]?.isKind(.extension) == true
        }
        let externalExtensionUSRs = Set(selectedExtensionUSRs.filter { extensionUSR in
            let targets = extensionTargetUSRs[extensionUSR] ?? []
            return targets.count != 1 || targets.isDisjoint(with: localNominalUSRs)
        })

        func nominalTargets(_ targets: Set<String>) -> Set<String> {
            Set(targets.compactMap {
                Self.nominalTarget(
                    for: $0,
                    symbolsByUSR: symbolsByUSR,
                    extensionTargetUSRs: extensionTargetUSRs
                )
            })
        }
        func signatureProtocolUSRs(for callableUSR: String) -> Set<String> {
            let parameterSites = parameterDeclarationSitesByCallableUSR[callableUSR] ?? []
            return parameterSites.reduce(into: Set<String>()) { result, site in
                result.formUnion(
                    protocolUSRsByCallableAndSite[callableUSR]?[site] ?? []
                )
            }
        }
        func commonSignatureProtocolUSRs(for callableUSRs: Set<String>) -> Set<String> {
            let signatures = callableUSRs.compactMap { callableUSR -> Set<String>? in
                let protocols = signatureProtocolUSRs(for: callableUSR)
                return protocols.isEmpty ? nil : protocols
            }
            guard var common = signatures.first else {
                return []
            }
            for protocols in signatures.dropFirst() {
                common.formIntersection(protocols)
            }
            return common
        }

        // A missing witness relation can be recovered only when the compiler
        // index gives us one unambiguous protocol identity shared by known
        // witnesses. Multiple common protocols are not guessed between.
        let commonDecodingParameterProtocolUSRs = commonSignatureProtocolUSRs(
            for: knownDecodingWitnessUSRs
        )
        let decodingParameterProtocolUSR = commonDecodingParameterProtocolUSRs.count == 1
            ? commonDecodingParameterProtocolUSRs.first
            : nil
        let commonEncodingParameterProtocolUSRs = commonSignatureProtocolUSRs(
            for: knownEncodingWitnessUSRs
        )
        let encodingParameterProtocolUSR = commonEncodingParameterProtocolUSRs.count == 1
            ? commonEncodingParameterProtocolUSRs.first
            : nil
        var customDecodingImplementationTargets: Set<String> = []
        var customEncodingImplementationTargets: Set<String> = []
        for (callableUSR, name) in serializationImplementationNameByCallableUSR {
            let signatureProtocols = signatureProtocolUSRs(for: callableUSR)
            if name == Self.decodingRequirementName,
               knownDecodingWitnessUSRs.contains(callableUSR)
                || decodingParameterProtocolUSR.map(signatureProtocols.contains) == true {
                customDecodingImplementationTargets.formUnion(
                    serializationImplementationTargetsByCallableUSR[callableUSR] ?? []
                )
            } else if name == Self.encodingRequirementName,
                      knownEncodingWitnessUSRs.contains(callableUSR)
                        || encodingParameterProtocolUSR.map(signatureProtocols.contains) == true {
                customEncodingImplementationTargets.formUnion(
                    serializationImplementationTargetsByCallableUSR[callableUSR] ?? []
                )
            }
        }

        let decodingSensitiveOwnerUSRs = nominalTargets(decodingConformanceTargets)
        let encodingSensitiveOwnerUSRs = nominalTargets(encodingConformanceTargets)
        let serializationSensitiveOwnerUSRs = decodingSensitiveOwnerUSRs
            .union(encodingSensitiveOwnerUSRs)
        let explicitCodingKeysEnumUSRs = Set(selectedDeclarationUSRs.filter { usr in
            symbolsByUSR[usr]?.isKind(.enum) == true && symbolsByUSR[usr]?.name == "CodingKeys"
        })
        let explicitCodingKeysOwnerUSRByEnumUSR = Dictionary(uniqueKeysWithValues:
            explicitCodingKeysEnumUSRs.compactMap { enumUSR -> (String, String)? in
            let owners = ownerUSRsByChild[enumUSR] ?? []
            guard owners.count == 1, let ownerUSR = owners.first else {
                return nil
            }
            guard let nominalOwnerUSR = Self.nominalTarget(
                for: ownerUSR,
                symbolsByUSR: symbolsByUSR,
                extensionTargetUSRs: extensionTargetUSRs
            ) else {
                return nil
            }
            return (enumUSR, nominalOwnerUSR)
        })
        let explicitCodingKeysOwnerUSRs = Set(explicitCodingKeysOwnerUSRByEnumUSR.values)
        let customDecodingImplementationOwnerUSRs = nominalTargets(
            customDecodingImplementationTargets
        ).intersection(decodingSensitiveOwnerUSRs)
        let customEncodingImplementationOwnerUSRs = nominalTargets(
            customEncodingImplementationTargets
        ).intersection(encodingSensitiveOwnerUSRs)
        let customSerializationImplementationOwnerUSRs =
            customDecodingImplementationOwnerUSRs
                .union(customEncodingImplementationOwnerUSRs)
        var propertyWrapperDerivedUSRsByPropertyUSR: [String: Set<String>] = [:]
        for (site, implicitUSRs) in implicitPropertyUSRsBySite {
            let explicitUSRs = explicitPropertyUSRsBySite[site] ?? []
            for implicitUSR in implicitUSRs {
                guard let derivedName = symbolsByUSR[implicitUSR]?.name else {
                    continue
                }
                let matchingParents = explicitUSRs.filter { explicitUSR in
                    guard let parentName = symbolsByUSR[explicitUSR]?.name else {
                        return false
                    }
                    return Self.isPropertyWrapperDerivedName(derivedName, from: parentName)
                }
                guard matchingParents.count == 1, let parentUSR = matchingParents.first else {
                    continue
                }
                propertyWrapperDerivedUSRsByPropertyUSR[parentUSR, default: []].insert(implicitUSR)
            }
        }

        let externallyOwnedUSRs = Self.descendants(
            of: externalExtensionUSRs,
            childUSRsByOwner: childUSRsByOwner
        )
        let runtimeSensitiveUSRs = Self.reachable(
            of: runtimeSeeds,
            neighbors: runtimeDispatchNeighbors
        )
        let overrideRelatedUSRs = Self.relatedUSRs(in: overrideRelationNeighbors)
        let parameterRenameComponents = ParameterRenameComponentBuilder.makeComponents(
            snapshot: snapshot,
            rootPaths: rootPaths,
            symbolsByUSR: symbolsByUSR,
            protocolRequirementUSRs: protocolRequirementUSRs,
            overrideRelatedUSRs: overrideRelatedUSRs,
            runtimeSensitiveUSRs: runtimeSensitiveUSRs,
            externallyOwnedUSRs: externallyOwnedUSRs
        )

        self.selectedDeclarationUSRs = selectedDeclarationUSRs
        self.protocolRequirementUSRs = protocolRequirementUSRs
        self.externallyOwnedUSRs = externallyOwnedUSRs
        self.runtimeSensitiveUSRs = runtimeSensitiveUSRs
        self.storedPropertyUSRs = storedPropertyUSRs.intersection(explicitDeclarationUSRs)
        self.decodingSensitiveOwnerUSRs = decodingSensitiveOwnerUSRs
        self.encodingSensitiveOwnerUSRs = encodingSensitiveOwnerUSRs
        self.serializationSensitiveOwnerUSRs = serializationSensitiveOwnerUSRs
        self.explicitCodingKeysEnumUSRs = explicitCodingKeysEnumUSRs
        self.explicitCodingKeysOwnerUSRByEnumUSR = explicitCodingKeysOwnerUSRByEnumUSR
        self.explicitCodingKeysOwnerUSRs = explicitCodingKeysOwnerUSRs
        self.customDecodingImplementationOwnerUSRs = customDecodingImplementationOwnerUSRs
        self.customEncodingImplementationOwnerUSRs = customEncodingImplementationOwnerUSRs
        self.customSerializationImplementationOwnerUSRs = customSerializationImplementationOwnerUSRs
        self.propertyWrapperDerivedUSRsByPropertyUSR = propertyWrapperDerivedUSRsByPropertyUSR
        self.overrideRelationNeighbors = overrideRelationNeighbors
        self.overrideRelatedUSRs = overrideRelatedUSRs
        self.parameterRenameComponents = parameterRenameComponents
        self.parameterFactsSummary = ParameterFactsSummary(
            explicitParameters: explicitDeclarationUSRs.count { usr in
                symbolsByUSR[usr]?.isKind(.parameter) == true
            },
            components: parameterRenameComponents
        )
        self.symbolsByUSR = symbolsByUSR
        self.ownerUSRsByChild = ownerUSRsByChild
        self.childUSRsByOwner = childUSRsByOwner
        self.extensionTargetUSRs = extensionTargetUSRs
        self.nominalSubtypeUSRsByBase = nominalSubtypeUSRsByBase
    }

    func nominalOwnerUSR(of childUSR: String) -> String? {
        let owners = ownerUSRsByChild[childUSR] ?? []
        guard owners.count == 1, let ownerUSR = owners.first else {
            return nil
        }
        return Self.nominalTarget(
            for: ownerUSR,
            symbolsByUSR: symbolsByUSR,
            extensionTargetUSRs: extensionTargetUSRs
        )
    }

    func directStoredPropertyUSRs(of ownerUSR: String) -> Set<String> {
        Set((childUSRsByOwner[ownerUSR] ?? []).filter(storedPropertyUSRs.contains))
    }

    func nominalDescendantUSRs(of baseUSR: String) -> Set<String> {
        Self.descendants(
            of: nominalSubtypeUSRsByBase[baseUSR] ?? [],
            childUSRsByOwner: nominalSubtypeUSRsByBase
        )
    }

    func qualifiedNominalOwnerUSRs(for ownerUSR: String) -> [String]? {
        let nominalKinds = IndexSymbolKind.rawValues(.class, .struct, .enum, .protocol)
        guard nominalKinds.contains(symbolsByUSR[ownerUSR]?.kind ?? "") else {
            return nil
        }

        var reversedChain = [ownerUSR]
        var currentUSR = ownerUSR
        var visited = Set(reversedChain)
        while true {
            let owners = ownerUSRsByChild[currentUSR] ?? []
            guard !owners.isEmpty else {
                break
            }
            guard owners.count == 1, let rawOwnerUSR = owners.first,
                  let nominalOwnerUSR = Self.nominalTarget(
                    for: rawOwnerUSR,
                    symbolsByUSR: symbolsByUSR,
                    extensionTargetUSRs: extensionTargetUSRs
                  ),
                  nominalKinds.contains(symbolsByUSR[nominalOwnerUSR]?.kind ?? ""),
                  visited.insert(nominalOwnerUSR).inserted else {
                return nil
            }
            reversedChain.append(nominalOwnerUSR)
            currentUSR = nominalOwnerUSR
        }
        return reversedChain.reversed()
    }

    private static func descendants(
        of seeds: Set<String>,
        childUSRsByOwner: [String: Set<String>]
    ) -> Set<String> {
        var result = seeds
        var pending = Array(seeds)
        while let ownerUSR = pending.popLast() {
            for childUSR in childUSRsByOwner[ownerUSR] ?? [] where result.insert(childUSR).inserted {
                pending.append(childUSR)
            }
        }
        return result
    }

    private static func reachable(
        of seeds: Set<String>,
        neighbors: [String: Set<String>]
    ) -> Set<String> {
        var result = seeds
        var pending = Array(seeds)
        while let usr = pending.popLast() {
            for neighbor in neighbors[usr] ?? [] where result.insert(neighbor).inserted {
                pending.append(neighbor)
            }
        }
        return result
    }

    private static func isPath(_ path: String, underRootPaths rootPaths: [String]) -> Bool {
        let canonicalPath = SourcePathNormalizer.canonicalPath(path)
        return rootPaths.contains { rootPath in
            canonicalPath == rootPath || canonicalPath.hasPrefix(rootPath + "/")
        }
    }

    private static func relatedUSRs(in neighbors: [String: Set<String>]) -> Set<String> {
        Set(neighbors.keys).union(neighbors.values.joined())
    }

    private static func nominalTarget(
        for usr: String,
        symbolsByUSR: [String: SymbolRecord],
        extensionTargetUSRs: [String: Set<String>]
    ) -> String? {
        guard symbolsByUSR[usr]?.isKind(.extension) == true else {
            return symbolsByUSR[usr] == nil ? nil : usr
        }
        let targets = extensionTargetUSRs[usr] ?? []
        return targets.count == 1 ? targets.first : nil
    }

    private static func isRuntimeUSR(
        _ usr: String,
        symbolsByUSR: [String: SymbolRecord]
    ) -> Bool {
        IndexUSR.isObjectiveCCompatible(usr) || symbolsByUSR[usr].map(isRuntimeSymbol) == true
    }

    private static func isRuntimeSymbol(_ symbol: SymbolRecord) -> Bool {
        let language = symbol.language.lowercased()
        return IndexUSR.isObjectiveCCompatible(symbol.usr)
            || language == "objc"
            || language == "objective-c"
            || language == "c"
            || hasRuntimeProperty(symbol)
    }

    private static func hasRuntimeProperty(_ symbol: SymbolRecord) -> Bool {
        let properties = SymbolProperty(rawValue: symbol.propertiesRaw)
        let runtimeProperties: SymbolProperty = [
            .ibAnnotated,
            .ibOutletCollection,
            .gkInspectable
        ]
        return !properties.intersection(runtimeProperties).isEmpty
    }

    static func isOverrideDispatchKind(_ kind: String) -> Bool {
        let dispatchKinds = IndexSymbolKind.rawValues(
            .constructor,
            .instanceMethod,
            .classMethod,
            .staticMethod,
            .instanceProperty,
            .classProperty,
            .staticProperty
        )
        return dispatchKinds.contains(kind)
    }

    private static func isOverrideRelation(_ relation: RelationRecord) -> Bool {
        relation.hasRole(.overrideOf) || relation.hasRole(.baseOf)
    }

    private static func isPropertyWrapperDerivedName(_ derivedName: String, from parentName: String) -> Bool {
        guard derivedName.hasSuffix(parentName), derivedName != parentName else {
            return false
        }
        let prefix = derivedName.dropLast(parentName.count)
        return !prefix.isEmpty && prefix.allSatisfy { $0 == "$" || $0 == "_" }
    }

    // These are the stable Swift standard-library semantic identities for the
    // two protocols whose synthesized implementations derive external keys
    // from stored-property spellings. The rule stays independent of any target
    // project's model names or framework types.
    private static let decodableProtocolUSR = "s:Se"
    private static let encodableProtocolUSR = "s:SE"

    // Explicit witnesses are distinguished from compiler-synthesized Codable
    // implementations by IndexStore roles and their protocol-requirement
    // relations. No declaration-body parsing is needed.
    private static let decodingRequirementName = "init(from:)"
    private static let encodingRequirementName = "encode(to:)"

    private static func isSerializationImplementationSymbol(_ symbol: SymbolRecord) -> Bool {
        (symbol.isKind(.constructor) && symbol.name == decodingRequirementName)
            || (symbol.isKind(.instanceMethod) && symbol.name == encodingRequirementName)
    }

    private struct DeclarationLineSite: Hashable {
        let path: String
        let line: Int
    }

    private struct PropertyDeclarationSite: Hashable {
        let path: String
        let line: Int
        let ownerUSR: String
    }
}
