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
    public let serializationSensitiveOwnerUSRs: Set<String>
    public let explicitCodingKeysOwnerUSRs: Set<String>
    public let customSerializationImplementationOwnerUSRs: Set<String>
    public let propertyWrapperDerivedUSRsByPropertyUSR: [String: Set<String>]
    public let overrideRelationNeighbors: [String: Set<String>]
    public let overrideRelatedUSRs: Set<String>

    let symbolsByUSR: [String: SymbolRecord]
    let ownerUSRsByChild: [String: Set<String>]
    let childUSRsByOwner: [String: Set<String>]
    let extensionTargetUSRs: [String: Set<String>]

    public init(
        selectedDeclarationUSRs: Set<String> = [],
        protocolRequirementUSRs: Set<String> = [],
        externallyOwnedUSRs: Set<String> = [],
        runtimeSensitiveUSRs: Set<String> = [],
        storedPropertyUSRs: Set<String> = [],
        serializationSensitiveOwnerUSRs: Set<String> = [],
        explicitCodingKeysOwnerUSRs: Set<String> = [],
        customSerializationImplementationOwnerUSRs: Set<String> = [],
        propertyWrapperDerivedUSRsByPropertyUSR: [String: Set<String>] = [:],
        overrideRelationNeighbors: [String: Set<String>] = [:]
    ) {
        self.selectedDeclarationUSRs = selectedDeclarationUSRs
        self.protocolRequirementUSRs = protocolRequirementUSRs
        self.externallyOwnedUSRs = externallyOwnedUSRs
        self.runtimeSensitiveUSRs = runtimeSensitiveUSRs
        self.storedPropertyUSRs = storedPropertyUSRs
        self.serializationSensitiveOwnerUSRs = serializationSensitiveOwnerUSRs
        self.explicitCodingKeysOwnerUSRs = explicitCodingKeysOwnerUSRs
        self.customSerializationImplementationOwnerUSRs = customSerializationImplementationOwnerUSRs
        self.propertyWrapperDerivedUSRsByPropertyUSR = propertyWrapperDerivedUSRsByPropertyUSR
        self.overrideRelationNeighbors = overrideRelationNeighbors
        self.overrideRelatedUSRs = Self.relatedUSRs(in: overrideRelationNeighbors)
        self.symbolsByUSR = [:]
        self.ownerUSRsByChild = [:]
        self.childUSRsByOwner = [:]
        self.extensionTargetUSRs = [:]
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
        var overrideRelationNeighbors: [String: Set<String>] = [:]
        var runtimeDispatchNeighbors: [String: Set<String>] = [:]
        var storedPropertyUSRs: Set<String> = []
        var serializationConformanceTargets: Set<String> = []
        var customSerializationImplementationTargets: Set<String> = []
        var explicitPropertyUSRsBySite: [PropertyDeclarationSite: Set<String>] = [:]
        var implicitPropertyUSRsBySite: [PropertyDeclarationSite: Set<String>] = [:]
        var runtimeSeeds = Set(symbolsByUSR.values.compactMap { symbol -> String? in
            Self.isRuntimeSymbol(symbol) ? symbol.usr : nil
        })

        for occurrence in snapshot.occurrences {
            let isDeclaration = occurrence.roles.contains("declaration")
                || occurrence.roles.contains("definition")
            if isDeclaration, Self.isPath(occurrence.path, underRootPaths: rootPaths) {
                selectedDeclarationUSRs.insert(occurrence.usr)
                if !occurrence.roles.contains("implicit") {
                    explicitDeclarationUSRs.insert(occurrence.usr)
                }
                for relation in occurrence.relations where relation.roles.contains("childOf") {
                    ownerUSRsByChild[occurrence.usr, default: []].insert(relation.usr)
                    childUSRsByOwner[relation.usr, default: []].insert(occurrence.usr)
                }
            }

            if occurrence.symbol.kind == "instanceProperty",
               occurrence.roles.contains("definition"),
               Self.isPath(occurrence.path, underRootPaths: rootPaths) {
                let owners = occurrence.relations.filter { $0.roles.contains("childOf") }
                if owners.count == 1, let ownerUSR = owners.first?.usr {
                    let site = PropertyDeclarationSite(
                        path: SourcePathNormalizer.canonicalPath(occurrence.path),
                        line: occurrence.line,
                        ownerUSR: ownerUSR
                    )
                    if occurrence.roles.contains("implicit") {
                        implicitPropertyUSRsBySite[site, default: []].insert(occurrence.usr)
                    } else {
                        explicitPropertyUSRsBySite[site, default: []].insert(occurrence.usr)
                    }
                }
            }

            if Self.hasRuntimeProperty(occurrence.symbol)
                || occurrence.relations.contains(where: { $0.roles.contains("ibTypeOf") }) {
                runtimeSeeds.insert(occurrence.usr)
            }

            if occurrence.roles.contains("definition"),
               occurrence.roles.contains("implicit") {
                for relation in occurrence.relations where relation.roles.contains("accessorOf") {
                    guard symbolsByUSR[relation.usr]?.kind == "instanceProperty" else {
                        continue
                    }
                    // A compiler-synthesized accessor definition is the semantic
                    // distinction IndexStore exposes between stored properties
                    // and source-authored computed accessors.
                    storedPropertyUSRs.insert(relation.usr)
                }
            }

            if Self.synthesizedCodingKeyProtocolUSRs.contains(occurrence.usr) {
                for relation in occurrence.relations where relation.roles.contains("baseOf") {
                    serializationConformanceTargets.insert(relation.usr)
                }
            }

            if isDeclaration,
               !occurrence.roles.contains("implicit"),
               occurrence.relations.contains(where: {
                   $0.roles.contains("overrideOf")
                       && Self.serializationRequirementNames.contains($0.name)
               }) {
                for relation in occurrence.relations where relation.roles.contains("childOf") {
                    customSerializationImplementationTargets.insert(relation.usr)
                }
            }

            for relation in occurrence.relations where relation.roles.contains("extendedBy") {
                extensionTargetUSRs[relation.usr, default: []].insert(occurrence.usr)
            }
            for relation in occurrence.relations {
                let occurrenceIsSynthetic = Self.isSyntheticAccessorName(occurrence.symbol.name)
                let targetIsSynthetic = Self.isSyntheticAccessorName(
                    symbolsByUSR[relation.usr]?.name ?? relation.name
                )
                guard !occurrenceIsSynthetic, !targetIsSynthetic else {
                    continue
                }

                let isDispatchRelation = Self.isOverrideDispatchKind(occurrence.symbol.kind)
                    && Self.isOverrideRelation(relation)
                if relation.roles.contains("overrideOf") || isDispatchRelation {
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

        let localNominalKinds: Set<String> = ["class", "struct", "enum", "protocol"]
        let localNominalUSRs = Set(selectedDeclarationUSRs.compactMap { usr -> String? in
            guard let symbol = symbolsByUSR[usr],
                  localNominalKinds.contains(symbol.kind) else {
                return nil
            }
            return usr
        })
        let localProtocolUSRs = Set(localNominalUSRs.filter {
            symbolsByUSR[$0]?.kind == "protocol"
        })

        let protocolRequirementUSRs = Set(selectedDeclarationUSRs.filter { usr in
            !(ownerUSRsByChild[usr] ?? []).isDisjoint(with: localProtocolUSRs)
        })

        let selectedExtensionUSRs = selectedDeclarationUSRs.filter {
            symbolsByUSR[$0]?.kind == "extension"
        }
        let externalExtensionUSRs = Set(selectedExtensionUSRs.filter { extensionUSR in
            let targets = extensionTargetUSRs[extensionUSR] ?? []
            return targets.count != 1 || targets.isDisjoint(with: localNominalUSRs)
        })

        let serializationSensitiveOwnerUSRs = Set(serializationConformanceTargets.compactMap {
            Self.nominalTarget(
                for: $0,
                symbolsByUSR: symbolsByUSR,
                extensionTargetUSRs: extensionTargetUSRs
            )
        })
        let explicitCodingKeysOwnerUSRs = Set(selectedDeclarationUSRs.compactMap { usr -> String? in
            guard symbolsByUSR[usr]?.name == "CodingKeys" else {
                return nil
            }
            let owners = ownerUSRsByChild[usr] ?? []
            guard owners.count == 1, let ownerUSR = owners.first else {
                return nil
            }
            return Self.nominalTarget(
                for: ownerUSR,
                symbolsByUSR: symbolsByUSR,
                extensionTargetUSRs: extensionTargetUSRs
            )
        })
        let customSerializationImplementationOwnerUSRs = Set(
            customSerializationImplementationTargets.compactMap {
                Self.nominalTarget(
                    for: $0,
                    symbolsByUSR: symbolsByUSR,
                    extensionTargetUSRs: extensionTargetUSRs
                )
            }
        ).intersection(serializationSensitiveOwnerUSRs)
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

        self.selectedDeclarationUSRs = selectedDeclarationUSRs
        self.protocolRequirementUSRs = protocolRequirementUSRs
        self.externallyOwnedUSRs = Self.descendants(
            of: externalExtensionUSRs,
            childUSRsByOwner: childUSRsByOwner
        )
        self.runtimeSensitiveUSRs = Self.reachable(
            of: runtimeSeeds,
            neighbors: runtimeDispatchNeighbors
        )
        self.storedPropertyUSRs = storedPropertyUSRs.intersection(explicitDeclarationUSRs)
        self.serializationSensitiveOwnerUSRs = serializationSensitiveOwnerUSRs
        self.explicitCodingKeysOwnerUSRs = explicitCodingKeysOwnerUSRs
        self.customSerializationImplementationOwnerUSRs = customSerializationImplementationOwnerUSRs
        self.propertyWrapperDerivedUSRsByPropertyUSR = propertyWrapperDerivedUSRsByPropertyUSR
        self.overrideRelationNeighbors = overrideRelationNeighbors
        self.overrideRelatedUSRs = Self.relatedUSRs(in: overrideRelationNeighbors)
        self.symbolsByUSR = symbolsByUSR
        self.ownerUSRsByChild = ownerUSRsByChild
        self.childUSRsByOwner = childUSRsByOwner
        self.extensionTargetUSRs = extensionTargetUSRs
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

    func qualifiedNominalOwnerUSRs(for ownerUSR: String) -> [String]? {
        let nominalKinds: Set<String> = ["class", "struct", "enum", "protocol"]
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
        guard symbolsByUSR[usr]?.kind == "extension" else {
            return symbolsByUSR[usr] == nil ? nil : usr
        }
        let targets = extensionTargetUSRs[usr] ?? []
        return targets.count == 1 ? targets.first : nil
    }

    private static func isRuntimeUSR(
        _ usr: String,
        symbolsByUSR: [String: SymbolRecord]
    ) -> Bool {
        usr.hasPrefix("c:") || symbolsByUSR[usr].map(isRuntimeSymbol) == true
    }

    private static func isRuntimeSymbol(_ symbol: SymbolRecord) -> Bool {
        let language = symbol.language.lowercased()
        return symbol.usr.hasPrefix("c:")
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
        let dispatchKinds: Set<String> = [
            "constructor",
            "instanceMethod",
            "classMethod",
            "staticMethod",
            "instanceProperty",
            "classProperty",
            "staticProperty"
        ]
        return dispatchKinds.contains(kind)
    }

    private static func isOverrideRelation(_ relation: RelationRecord) -> Bool {
        relation.roles.contains("overrideOf") || relation.roles.contains("baseOf")
    }

    private static func isSyntheticAccessorName(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return lowercasedName.hasPrefix("getter:") || lowercasedName.hasPrefix("setter:")
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
    private static let synthesizedCodingKeyProtocolUSRs: Set<String> = ["s:Se", "s:SE"]

    // Explicit witnesses are distinguished from compiler-synthesized Codable
    // implementations by IndexStore roles and their protocol-requirement
    // relations. No declaration-body parsing is needed.
    private static let serializationRequirementNames: Set<String> = ["init(from:)", "encode(to:)"]

    private struct PropertyDeclarationSite: Hashable {
        let path: String
        let line: Int
        let ownerUSR: String
    }
}
