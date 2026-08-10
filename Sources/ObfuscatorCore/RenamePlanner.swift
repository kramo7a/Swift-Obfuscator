import Foundation

public struct RenamePlanEntry: Codable, Sendable {
    public let usr: String
    public let kind: String
    public let oldName: String
    public let newName: String
    public let replacements: [SourceReplacement]
}

public struct RenamePlan: Codable, Sendable {
    public let entries: [RenamePlanEntry]
    public let denied: [SafetyDecision]
    public let conflicts: [String]

    public var replacements: [SourceReplacement] {
        var seen: Set<String> = []
        return entries.flatMap(\.replacements)
            .sorted { lhs, rhs in
                (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
            }
            .filter { replacement in
                // One source token can carry more than one semantic USR (for
                // example a witness satisfying two protocol requirements).
                // Applying the identical byte edit twice would fail validation,
                // so keep one physical edit while retaining every semantic plan
                // entry and mapping.
                let key = "\(replacement.path):\(replacement.byteOffset):\(replacement.length):\(replacement.oldName)->\(replacement.newName)"
                return seen.insert(key).inserted
            }
    }
}

public struct RenamePlanner {
    public var analyzer: SafetyAnalyzer
    public var generator: NameGenerator
    public var mappingStore: MappingStore

    public init(analyzer: SafetyAnalyzer, generator: NameGenerator = NameGenerator(), mappingStore: MappingStore = MappingStore()) {
        self.analyzer = analyzer
        self.generator = generator
        self.mappingStore = mappingStore
    }

    public mutating func makePlan(snapshot: IndexSnapshot, sourceCache: SourceFileCache) -> RenamePlan {
        var denied: [SafetyDecision] = []
        var entries: [RenamePlanEntry] = []
        var conflicts: [String] = []
        let groups = snapshot.groupsByUSR
        let groupsByUSR = Dictionary(uniqueKeysWithValues: groups.map { ($0.usr, $0) })
        var reservedNames = Set(snapshot.symbols.map(\.name)).filter(isPlainSwiftIdentifier)
        reservedNames.formUnion(mappingStore.allEntries().map(\.obfuscatedName))
        let localNominalTypeNames = Self.localNominalTypeNames(snapshot: snapshot)
        let overrideRelatedUSRs = Self.overrideRelatedUSRs(snapshot: snapshot)
        let tupleTypealiasRelatedUSRs = Self.tupleTypealiasRelatedUSRs(
            snapshot: snapshot,
            sourceCache: sourceCache
        )
        let protocolComponents = Self.protocolRenameComponents(
            snapshot: snapshot,
            analyzer: analyzer
        )
        let protocolComponentByUSR = Dictionary(uniqueKeysWithValues: protocolComponents.flatMap { component in
            component.memberUSRs.compactMap { usr in
                groupsByUSR[usr] == nil ? nil : (usr, component)
            }
        })
        var processedProtocolComponents: Set<String> = []

        for group in groups {
            if let component = protocolComponentByUSR[group.usr] {
                guard processedProtocolComponents.insert(component.key).inserted else {
                    continue
                }

                let componentGroups = component.memberUSRs.compactMap { groupsByUSR[$0] }.sorted { lhs, rhs in
                    (lhs.symbol.name, lhs.usr) < (rhs.symbol.name, rhs.usr)
                }
                let coordinationEnabled = component.structuralReasons.isEmpty
                let decisions = componentGroups.map { componentGroup in
                    analyzer.analyze(
                        group: componentGroup,
                        sourceCache: sourceCache,
                        localNominalTypeNames: localNominalTypeNames,
                        overrideRelatedUSRs: overrideRelatedUSRs,
                        tupleTypealiasRelatedUSRs: tupleTypealiasRelatedUSRs,
                        coordinatedRelatedUSRs: coordinationEnabled ? component.memberUSRs : [],
                        coordinatedProtocolRequirementUSRs: coordinationEnabled
                            ? component.protocolRequirementUSRs
                            : []
                    )
                }

                var failureSummaries = component.structuralReasons
                for decision in decisions where !decision.allowed {
                    failureSummaries.append("\(decision.usr): \(decision.reasons.joined(separator: "; "))")
                }

                let oldNames = Set(decisions.compactMap(\.oldName))
                if decisions.allSatisfy(\.allowed), oldNames.count != 1 {
                    failureSummaries.append("component occurrences do not resolve to one source identifier")
                }

                let caseConventions = Set(componentGroups.map {
                    Self.nameWithConventionalInitialCase("Oa", for: $0.symbol.kind)
                })
                if caseConventions.count != 1 {
                    failureSummaries.append("component symbol kinds require incompatible identifier casing")
                }

                let existingNames = Set(componentGroups.compactMap {
                    mappingStore.entry(for: $0.usr)?.obfuscatedName
                })
                if existingNames.count > 1 {
                    failureSummaries.append("component USRs already have inconsistent persisted mappings")
                }

                var replacementsByUSR: [String: Set<SourceReplacement>] = [:]
                if failureSummaries.isEmpty, let oldName = oldNames.first {
                    for componentGroup in componentGroups {
                        var replacements: Set<SourceReplacement> = []
                        var localReasons: Set<String> = []
                        for occurrence in componentGroup.occurrences {
                            if Self.isSemanticOnlyCoordinatedOccurrence(
                                occurrence,
                                componentUSRs: component.memberUSRs
                            ) {
                                continue
                            }
                            guard let source = sourceCache.file(for: occurrence.path) else {
                                localReasons.insert("source file unavailable for \(occurrence.path)")
                                continue
                            }
                            guard let token = source.identifierToken(
                                line: occurrence.line,
                                utf8Column: occurrence.utf8Column
                            ) else {
                                localReasons.insert(
                                    "identifier token unavailable at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                                )
                                continue
                            }
                            guard token.name == oldName else {
                                localReasons.insert(
                                    "token mismatch at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                                )
                                continue
                            }
                            replacements.insert(SourceReplacement(
                                path: source.path,
                                byteOffset: token.byteRange.lowerBound,
                                length: token.byteRange.count,
                                line: occurrence.line,
                                utf8Column: occurrence.utf8Column,
                                oldName: oldName,
                                newName: "",
                                usr: componentGroup.usr
                            ))
                        }
                        if !localReasons.isEmpty {
                            failureSummaries.append(
                                "\(componentGroup.usr): \(localReasons.sorted().joined(separator: "; "))"
                            )
                        } else if replacements.isEmpty {
                            failureSummaries.append("\(componentGroup.usr): no source replacements")
                        } else {
                            replacementsByUSR[componentGroup.usr] = replacements
                        }
                    }
                }

                guard failureSummaries.isEmpty, let oldName = oldNames.first else {
                    let componentReason = Self.protocolComponentDenialReason(failureSummaries)
                    denied.append(contentsOf: zip(componentGroups, decisions).map { componentGroup, decision in
                        var reasons = decision.allowed ? [] : decision.reasons
                        reasons.append(componentReason)
                        return SafetyDecision(
                            usr: componentGroup.usr,
                            symbolName: componentGroup.symbol.name,
                            kind: componentGroup.symbol.kind,
                            allowed: false,
                            oldName: decision.oldName,
                            reasons: Array(Set(reasons)).sorted()
                        )
                    })
                    continue
                }

                let newName: String
                if let existingName = existingNames.first {
                    newName = existingName
                } else {
                    newName = nextName(for: componentGroups[0].symbol.kind, avoiding: reservedNames)
                    reservedNames.insert(newName)
                }

                for componentGroup in componentGroups {
                    if mappingStore.entry(for: componentGroup.usr) == nil {
                        mappingStore.record(
                            usr: componentGroup.usr,
                            originalName: oldName,
                            obfuscatedName: newName,
                            kind: componentGroup.symbol.kind
                        )
                    }
                    let replacements = (replacementsByUSR[componentGroup.usr] ?? []).map { replacement in
                        SourceReplacement(
                            path: replacement.path,
                            byteOffset: replacement.byteOffset,
                            length: replacement.length,
                            line: replacement.line,
                            utf8Column: replacement.utf8Column,
                            oldName: replacement.oldName,
                            newName: newName,
                            usr: replacement.usr
                        )
                    }
                    entries.append(RenamePlanEntry(
                        usr: componentGroup.usr,
                        kind: componentGroup.symbol.kind,
                        oldName: oldName,
                        newName: newName,
                        replacements: replacements.sorted { lhs, rhs in
                            (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
                        }
                    ))
                }
                continue
            }

            let decision = analyzer.analyze(
                group: group,
                sourceCache: sourceCache,
                localNominalTypeNames: localNominalTypeNames,
                overrideRelatedUSRs: overrideRelatedUSRs,
                tupleTypealiasRelatedUSRs: tupleTypealiasRelatedUSRs
            )
            guard decision.allowed, let oldName = decision.oldName else {
                denied.append(decision)
                continue
            }

            let newName: String
            if let existing = mappingStore.entry(for: group.usr) {
                newName = existing.obfuscatedName
            } else {
                newName = nextName(for: group.symbol.kind, avoiding: reservedNames)
                reservedNames.insert(newName)
                mappingStore.record(
                    usr: group.usr,
                    originalName: oldName,
                    obfuscatedName: newName,
                    kind: group.symbol.kind
                )
            }

            var replacements: Set<SourceReplacement> = []
            var localReasons: [String] = []
            for occurrence in group.occurrences {
                guard let source = sourceCache.file(for: occurrence.path) else {
                    localReasons.append("source file unavailable for \(occurrence.path)")
                    continue
                }
                guard let token = source.identifierToken(line: occurrence.line, utf8Column: occurrence.utf8Column) else {
                    localReasons.append("identifier token unavailable at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)")
                    continue
                }
                guard token.name == oldName else {
                    localReasons.append("token mismatch at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)")
                    continue
                }
                replacements.insert(SourceReplacement(
                    path: source.path,
                    byteOffset: token.byteRange.lowerBound,
                    length: token.byteRange.count,
                    line: occurrence.line,
                    utf8Column: occurrence.utf8Column,
                    oldName: oldName,
                    newName: newName,
                    usr: group.usr
                ))
            }

            if !localReasons.isEmpty || replacements.isEmpty {
                denied.append(SafetyDecision(
                    usr: group.usr,
                    symbolName: group.symbol.name,
                    kind: group.symbol.kind,
                    allowed: false,
                    oldName: oldName,
                    reasons: localReasons.isEmpty ? ["no source replacements"] : Array(Set(localReasons)).sorted()
                ))
                continue
            }

            entries.append(RenamePlanEntry(
                usr: group.usr,
                kind: group.symbol.kind,
                oldName: oldName,
                newName: newName,
                replacements: replacements.sorted { lhs, rhs in
                    (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
                }
            ))
        }

        let conflictGroups = Dictionary(grouping: entries.flatMap(\.replacements)) { replacement in
            "\(replacement.path):\(replacement.byteOffset)"
        }
        let conflictKeys = Set(conflictGroups.compactMap { key, replacements -> String? in
            let uniqueTargets = Set(replacements.map { "\($0.oldName)->\($0.newName)" })
            return uniqueTargets.count > 1 ? key : nil
        })
        if !conflictKeys.isEmpty {
            conflicts = conflictKeys.sorted()
            let conflictedProtocolComponents = Set(entries.compactMap { entry -> String? in
                guard entry.replacements.contains(where: {
                    conflictKeys.contains("\($0.path):\($0.byteOffset)")
                }) else {
                    return nil
                }
                return protocolComponentByUSR[entry.usr]?.key
            })
            entries = entries.compactMap { entry in
                if let componentKey = protocolComponentByUSR[entry.usr]?.key,
                   conflictedProtocolComponents.contains(componentKey) {
                    return nil
                }
                return entry.replacements.contains {
                    conflictKeys.contains("\($0.path):\($0.byteOffset)")
                } ? nil : entry
            }
            for component in protocolComponents where conflictedProtocolComponents.contains(component.key) {
                let reason = Self.protocolComponentDenialReason([
                    "component contains a replacement conflict and was removed atomically"
                ])
                for componentGroup in groups where component.memberUSRs.contains(componentGroup.usr) {
                    denied.append(SafetyDecision(
                        usr: componentGroup.usr,
                        symbolName: componentGroup.symbol.name,
                        kind: componentGroup.symbol.kind,
                        allowed: false,
                        oldName: nil,
                        reasons: [reason]
                    ))
                }
            }
        }

        return RenamePlan(
            entries: entries.sorted { ($0.oldName, $0.usr) < ($1.oldName, $1.usr) },
            denied: denied.sorted { ($0.symbolName, $0.usr) < ($1.symbolName, $1.usr) },
            conflicts: conflicts
        )
    }

    private struct ProtocolRenameComponent {
        let key: String
        let memberUSRs: Set<String>
        let protocolRequirementUSRs: Set<String>
        let structuralReasons: [String]
    }

    private static func protocolRenameComponents(
        snapshot: IndexSnapshot,
        analyzer: SafetyAnalyzer
    ) -> [ProtocolRenameComponent] {
        let groups = snapshot.groupsByUSR
        let groupsByUSR = Dictionary(uniqueKeysWithValues: groups.map { ($0.usr, $0) })
        let symbolsByUSR = Dictionary(
            snapshot.symbols.map { ($0.usr, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let obfuscationRootPaths = analyzer.obfuscationRoots.map {
            $0.resolvingSymlinksInPath().standardizedFileURL.path
        }
        let selectedDeclarationUSRs = Set(snapshot.occurrences.compactMap { occurrence -> String? in
            guard occurrence.roles.contains("declaration") || occurrence.roles.contains("definition"),
                  isPath(occurrence.path, underRootPaths: obfuscationRootPaths) else {
                return nil
            }
            return occurrence.usr
        })

        let localProtocolUSRs = Set(groups.compactMap { group -> String? in
            guard group.symbol.kind == "protocol",
                  !group.usr.hasPrefix("c:"),
                  selectedDeclarationUSRs.contains(group.usr) else {
                return nil
            }
            return group.usr
        })

        let localRequirementUSRs = Set(groups.compactMap { group -> String? in
            guard !isSyntheticAccessorName(group.symbol.name),
                  selectedDeclarationUSRs.contains(group.usr),
                  group.occurrences.contains(where: { occurrence in
                      (occurrence.roles.contains("declaration") || occurrence.roles.contains("definition"))
                          && occurrence.relations.contains(where: { relation in
                              relation.roles.contains("childOf")
                                  && localProtocolUSRs.contains(relation.usr)
                          })
                  }) else {
                return nil
            }
            return group.usr
        })

        var adjacency: [String: Set<String>] = [:]
        for occurrence in snapshot.occurrences {
            guard !isSyntheticAccessorName(occurrence.symbol.name) else {
                continue
            }
            for relation in occurrence.relations where relation.roles.contains("overrideOf") {
                let targetName = symbolsByUSR[relation.usr]?.name ?? relation.name
                guard !isSyntheticAccessorName(targetName) else {
                    continue
                }
                adjacency[occurrence.usr, default: []].insert(relation.usr)
                adjacency[relation.usr, default: []].insert(occurrence.usr)
            }
        }

        var visited: Set<String> = []
        var components: [ProtocolRenameComponent] = []
        for requirementUSR in localRequirementUSRs.sorted() {
            guard !visited.contains(requirementUSR) else {
                continue
            }

            var members: Set<String> = []
            var pending = [requirementUSR]
            while let usr = pending.popLast() {
                guard members.insert(usr).inserted else {
                    continue
                }
                pending.append(contentsOf: (adjacency[usr] ?? []).filter { !members.contains($0) })
            }
            visited.formUnion(members)

            var structuralReasons: [String] = []
            for usr in members.sorted() {
                guard let memberGroup = groupsByUSR[usr] else {
                    structuralReasons.append("related USR has no indexed occurrence group: \(usr)")
                    continue
                }
                if usr.hasPrefix("c:") || memberGroup.symbol.language.lowercased().contains("objective") {
                    structuralReasons.append("Objective-C requirement or witness is part of the component: \(usr)")
                }
                if !selectedDeclarationUSRs.contains(memberGroup.usr) {
                    structuralReasons.append("related USR has no declaration inside selected source roots: \(usr)")
                }
            }

            components.append(ProtocolRenameComponent(
                key: members.sorted().first ?? requirementUSR,
                memberUSRs: members,
                protocolRequirementUSRs: members.intersection(localRequirementUSRs),
                structuralReasons: Array(Set(structuralReasons)).sorted()
            ))
        }

        return components.sorted { $0.key < $1.key }
    }

    private static func isPath(_ path: String, underRootPaths rootPaths: [String]) -> Bool {
        let canonicalPath = SourcePathNormalizer.canonicalPath(path)
        return rootPaths.contains { rootPath in
            return canonicalPath == rootPath || canonicalPath.hasPrefix(rootPath + "/")
        }
    }

    private static func isSyntheticAccessorName(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return lowercasedName.hasPrefix("getter:") || lowercasedName.hasPrefix("setter:")
    }

    private static func isSemanticOnlyCoordinatedOccurrence(
        _ occurrence: OccurrenceRecord,
        componentUSRs: Set<String>
    ) -> Bool {
        guard occurrence.roles.contains("implicit") else {
            return false
        }
        let lexicalRoles: Set<String> = [
            "declaration", "definition", "reference", "read", "write", "call", "dynamic", "addressOf"
        ]
        guard lexicalRoles.isDisjoint(with: occurrence.roles) else {
            return false
        }
        return occurrence.relations.contains { relation in
            relation.roles.contains("overrideOf") && componentUSRs.contains(relation.usr)
        }
    }

    private static func protocolComponentDenialReason(_ summaries: [String]) -> String {
        let uniqueSummaries = Array(Set(summaries)).sorted()
        let visible = uniqueSummaries.prefix(5).joined(separator: " | ")
        let remainder = uniqueSummaries.count - min(uniqueSummaries.count, 5)
        let suffix = remainder > 0 ? " | plus \(remainder) more blocker(s)" : ""
        return "protocol members require relation-aware witness renaming: coordinated component denied atomically (\(visible)\(suffix))"
    }

    private mutating func nextName(for symbolKind: String, avoiding reservedNames: Set<String>) -> String {
        while true {
            let generatedName = generator.nextName(avoiding: [])
            let candidate = Self.nameWithConventionalInitialCase(generatedName, for: symbolKind)
            if !reservedNames.contains(candidate), isPlainSwiftIdentifier(candidate) {
                return candidate
            }
        }
    }

    private static func nameWithConventionalInitialCase(_ name: String, for symbolKind: String) -> String {
        let lowerCamelCaseKinds: Set<String> = [
            "function",
            "instanceMethod",
            "staticMethod",
            "classMethod",
            "instanceProperty",
            "staticProperty",
            "classProperty",
            "variable"
        ]
        guard lowerCamelCaseKinds.contains(symbolKind),
              let letterIndex = name.firstIndex(where: \.isLetter) else {
            return name
        }

        var result = name
        result.replaceSubrange(letterIndex...letterIndex, with: String(name[letterIndex]).lowercased())
        return result
    }

    private static func localNominalTypeNames(snapshot: IndexSnapshot) -> Set<String> {
        let nominalKinds: Set<String> = ["class", "struct", "enum", "protocol"]
        return Set(snapshot.occurrences.compactMap { occurrence in
            guard nominalKinds.contains(occurrence.symbol.kind),
                  !occurrence.isSystem,
                  occurrence.roles.contains(where: { $0 == "declaration" || $0 == "definition" }),
                  isPlainSwiftIdentifier(occurrence.symbol.name) else {
                return nil
            }
            return occurrence.symbol.name
        })
    }

    private static func overrideRelatedUSRs(snapshot: IndexSnapshot) -> Set<String> {
        var result: Set<String> = []
        for occurrence in snapshot.occurrences {
            for relation in occurrence.relations where relation.roles.contains("overrideOf") {
                result.insert(occurrence.usr)
                result.insert(relation.usr)
            }
        }
        return result
    }

    private static func tupleTypealiasRelatedUSRs(
        snapshot: IndexSnapshot,
        sourceCache: SourceFileCache
    ) -> Set<String> {
        var result: Set<String> = []
        for occurrence in snapshot.occurrences where occurrence.symbol.kind == "typealias" {
            guard occurrence.roles.contains("declaration") || occurrence.roles.contains("definition"),
                  let source = sourceCache.file(for: occurrence.path),
                  let token = source.identifierToken(line: occurrence.line, utf8Column: occurrence.utf8Column),
                  declarationLooksLikeTupleTypealias(source: source, occurrence: occurrence, token: token) else {
                continue
            }

            result.insert(occurrence.usr)
            for relation in occurrence.relations
            where relation.roles.contains("childOf") || relation.roles.contains("containedBy") {
                result.insert(relation.usr)
            }
        }
        return result
    }

    private static func declarationLooksLikeTupleTypealias(
        source: SourceFile,
        occurrence: OccurrenceRecord,
        token: IdentifierToken
    ) -> Bool {
        guard let line = source.lineText(line: occurrence.line),
              let tokenRange = line.range(of: token.name) else {
            return true
        }
        let afterName = line[tokenRange.upperBound...]
        guard let equalsIndex = afterName.firstIndex(of: "=") else {
            return false
        }
        let rhsStart = afterName.index(after: equalsIndex)
        let rhs = afterName[rhsStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return rhs.isEmpty || rhs.first == "("
    }
}
