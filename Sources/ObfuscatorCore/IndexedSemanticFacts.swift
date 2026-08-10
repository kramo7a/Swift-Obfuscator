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

    public init(
        selectedDeclarationUSRs: Set<String> = [],
        protocolRequirementUSRs: Set<String> = [],
        externallyOwnedUSRs: Set<String> = [],
        runtimeSensitiveUSRs: Set<String> = []
    ) {
        self.selectedDeclarationUSRs = selectedDeclarationUSRs
        self.protocolRequirementUSRs = protocolRequirementUSRs
        self.externallyOwnedUSRs = externallyOwnedUSRs
        self.runtimeSensitiveUSRs = runtimeSensitiveUSRs
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
        var ownerUSRsByChild: [String: Set<String>] = [:]
        var childUSRsByOwner: [String: Set<String>] = [:]
        var extensionTargetUSRs: [String: Set<String>] = [:]
        var runtimeDispatchNeighbors: [String: Set<String>] = [:]
        var runtimeSeeds = Set(symbolsByUSR.values.compactMap { symbol -> String? in
            Self.isRuntimeSymbol(symbol) ? symbol.usr : nil
        })

        for occurrence in snapshot.occurrences {
            let isDeclaration = occurrence.roles.contains("declaration")
                || occurrence.roles.contains("definition")
            if isDeclaration, Self.isPath(occurrence.path, underRootPaths: rootPaths) {
                selectedDeclarationUSRs.insert(occurrence.usr)
                for relation in occurrence.relations where relation.roles.contains("childOf") {
                    ownerUSRsByChild[occurrence.usr, default: []].insert(relation.usr)
                    childUSRsByOwner[relation.usr, default: []].insert(occurrence.usr)
                }
            }

            if Self.hasRuntimeProperty(occurrence.symbol)
                || occurrence.relations.contains(where: { $0.roles.contains("ibTypeOf") }) {
                runtimeSeeds.insert(occurrence.usr)
            }

            for relation in occurrence.relations where relation.roles.contains("extendedBy") {
                extensionTargetUSRs[relation.usr, default: []].insert(occurrence.usr)
            }
            for relation in occurrence.relations where
                Self.isRuntimeDispatchKind(occurrence.symbol.kind)
                    && (relation.roles.contains("overrideOf") || relation.roles.contains("baseOf")) {
                runtimeDispatchNeighbors[occurrence.usr, default: []].insert(relation.usr)
                runtimeDispatchNeighbors[relation.usr, default: []].insert(occurrence.usr)
                if Self.isRuntimeUSR(relation.usr, symbolsByUSR: symbolsByUSR) {
                    runtimeSeeds.insert(relation.usr)
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

    private static func isRuntimeDispatchKind(_ kind: String) -> Bool {
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
}
