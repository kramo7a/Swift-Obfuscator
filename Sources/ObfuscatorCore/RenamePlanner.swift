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
    public let supportReplacements: [SourceReplacement]
    public let parameterFacts: ParameterFactsSummary
    public let parameterSyntaxFacts: ParameterSyntaxFactsSummary
    public let parameterCallSiteSyntaxFacts: ParameterCallSiteSyntaxFactsSummary
    public let parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary

    public init(
        entries: [RenamePlanEntry],
        denied: [SafetyDecision],
        conflicts: [String],
        supportReplacements: [SourceReplacement] = [],
        parameterFacts: ParameterFactsSummary = .empty,
        parameterSyntaxFacts: ParameterSyntaxFactsSummary = .empty,
        parameterCallSiteSyntaxFacts: ParameterCallSiteSyntaxFactsSummary = .empty,
        parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary = .empty
    ) {
        self.entries = entries
        self.denied = denied
        self.conflicts = conflicts
        self.supportReplacements = supportReplacements
        self.parameterFacts = parameterFacts
        self.parameterSyntaxFacts = parameterSyntaxFacts
        self.parameterCallSiteSyntaxFacts = parameterCallSiteSyntaxFacts
        self.parameterLocalBindingOutcome = parameterLocalBindingOutcome
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case denied
        case conflicts
        case supportReplacements
        case parameterFacts
        case parameterSyntaxFacts
        case parameterCallSiteSyntaxFacts
        case parameterLocalBindingOutcome
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([RenamePlanEntry].self, forKey: .entries)
        denied = try container.decode([SafetyDecision].self, forKey: .denied)
        conflicts = try container.decode([String].self, forKey: .conflicts)
        supportReplacements = try container.decodeIfPresent(
            [SourceReplacement].self,
            forKey: .supportReplacements
        ) ?? []
        parameterFacts = try container.decodeIfPresent(
            ParameterFactsSummary.self,
            forKey: .parameterFacts
        ) ?? .empty
        parameterSyntaxFacts = try container.decodeIfPresent(
            ParameterSyntaxFactsSummary.self,
            forKey: .parameterSyntaxFacts
        ) ?? .empty
        parameterCallSiteSyntaxFacts = try container.decodeIfPresent(
            ParameterCallSiteSyntaxFactsSummary.self,
            forKey: .parameterCallSiteSyntaxFacts
        ) ?? .empty
        parameterLocalBindingOutcome = try container.decodeIfPresent(
            ParameterLocalBindingOutcomeSummary.self,
            forKey: .parameterLocalBindingOutcome
        ) ?? .empty
    }

    public var replacements: [SourceReplacement] {
        var seen: Set<String> = []
        return (entries.flatMap(\.replacements) + supportReplacements)
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
        let indexedFacts = IndexedSemanticFacts(
            snapshot: snapshot,
            obfuscationRoots: analyzer.obfuscationRoots
        )
        let parameterSyntaxFacts = ParameterSyntaxFacts(
            snapshot: snapshot,
            sourceCache: sourceCache,
            obfuscationRoots: analyzer.obfuscationRoots
        )
        let parameterCallSiteSyntaxFacts = ParameterCallSiteSyntaxFacts(
            components: indexedFacts.parameterRenameComponents,
            sourceCache: sourceCache
        )
        let codingKeyComponents = Self.codingKeyPreservationComponents(
            indexedFacts: indexedFacts,
            groupsByUSR: groupsByUSR,
            sourceCache: sourceCache,
            obfuscationRoots: analyzer.obfuscationRoots
        )
        let serializationKeyPreservedUSRs = Set(
            codingKeyComponents.flatMap(\.propertyUSRs)
        )
        let propertyWrapperComponents = Self.propertyWrapperRenameComponents(
            indexedFacts: indexedFacts,
            groupsByUSR: groupsByUSR,
            sourceCache: sourceCache
        )
        let propertyWrapperSupportedUSRs = Set(propertyWrapperComponents.map(\.propertyUSR))
        let tupleTypealiasRelatedUSRs = Self.tupleTypealiasRelatedUSRs(
            snapshot: snapshot,
            sourceCache: sourceCache
        )
        let coordinatedComponents = Self.coordinatedRenameComponents(
            indexedFacts: indexedFacts,
            groupsByUSR: groupsByUSR
        )
        let coordinatedComponentByUSR = Dictionary(uniqueKeysWithValues: coordinatedComponents.flatMap { component in
            component.memberUSRs.compactMap { usr in
                groupsByUSR[usr] == nil ? nil : (usr, component)
            }
        })
        var processedCoordinatedComponents: Set<String> = []

        for group in groups {
            if let component = coordinatedComponentByUSR[group.usr] {
                guard processedCoordinatedComponents.insert(component.key).inserted else {
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
                        indexedFacts: indexedFacts,
                        overrideRelatedUSRs: indexedFacts.overrideRelatedUSRs,
                        tupleTypealiasRelatedUSRs: tupleTypealiasRelatedUSRs,
                        coordinatedRelatedUSRs: coordinationEnabled ? component.memberUSRs : [],
                        coordinatedProtocolRequirementUSRs: coordinationEnabled
                            ? component.protocolRequirementUSRs
                            : [],
                        serializationKeyPreservedUSRs: serializationKeyPreservedUSRs,
                        propertyWrapperSupportedUSRs: propertyWrapperSupportedUSRs,
                        localBindingOnlyParameterUSRs:
                            parameterSyntaxFacts.localBindingOnlyCoverageCandidateUSRs
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
                    let componentReason = component.denialReason(failureSummaries)
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
                indexedFacts: indexedFacts,
                overrideRelatedUSRs: indexedFacts.overrideRelatedUSRs,
                tupleTypealiasRelatedUSRs: tupleTypealiasRelatedUSRs,
                serializationKeyPreservedUSRs: serializationKeyPreservedUSRs,
                propertyWrapperSupportedUSRs: propertyWrapperSupportedUSRs,
                localBindingOnlyParameterUSRs:
                    parameterSyntaxFacts.localBindingOnlyCoverageCandidateUSRs
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

            if group.symbol.kind == "parameter",
               parameterSyntaxFacts.localBindingOnlyCoverageCandidateUSRs.contains(group.usr),
               let roles = parameterSyntaxFacts.rolesByUSR[group.usr] {
                for token in roles.localBindingTokens {
                    guard let source = sourceCache.file(for: token.path) else {
                        localReasons.append("source file unavailable for \(token.path)")
                        continue
                    }
                    guard token.name == oldName,
                          source.text(in: token.byteRange) == oldName else {
                        localReasons.append(
                            "compiler syntax token mismatch at \(token.path):\(token.byteRange.lowerBound)"
                        )
                        continue
                    }
                    guard let location = source.sourceLocation(
                        atByteOffset: token.byteRange.lowerBound
                    ) else {
                        localReasons.append(
                            "compiler syntax source location unavailable at \(token.path):\(token.byteRange.lowerBound)"
                        )
                        continue
                    }
                    replacements.insert(SourceReplacement(
                        path: source.path,
                        byteOffset: token.byteRange.lowerBound,
                        length: token.byteRange.count,
                        line: location.line,
                        utf8Column: location.utf8Column,
                        oldName: oldName,
                        newName: newName,
                        usr: group.usr
                    ))
                }
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
            let conflictedCoordinatedComponents = Set(entries.compactMap { entry -> String? in
                guard entry.replacements.contains(where: {
                    conflictKeys.contains("\($0.path):\($0.byteOffset)")
                }) else {
                    return nil
                }
                return coordinatedComponentByUSR[entry.usr]?.key
            })
            entries = entries.compactMap { entry in
                if let componentKey = coordinatedComponentByUSR[entry.usr]?.key,
                   conflictedCoordinatedComponents.contains(componentKey) {
                    return nil
                }
                return entry.replacements.contains {
                    conflictKeys.contains("\($0.path):\($0.byteOffset)")
                } ? nil : entry
            }
            for component in coordinatedComponents where conflictedCoordinatedComponents.contains(component.key) {
                let reason = component.denialReason([
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

        let supportReplacements = Self.codingKeySupportReplacements(
            components: codingKeyComponents,
            entries: entries,
            indexedFacts: indexedFacts,
            sourceCache: sourceCache
        ) + Self.propertyWrapperSupportReplacements(
            components: propertyWrapperComponents,
            entries: entries
        )

        return RenamePlan(
            entries: entries.sorted { ($0.oldName, $0.usr) < ($1.oldName, $1.usr) },
            denied: denied.sorted { ($0.symbolName, $0.usr) < ($1.symbolName, $1.usr) },
            conflicts: conflicts,
            supportReplacements: supportReplacements,
            parameterFacts: indexedFacts.parameterFactsSummary,
            parameterSyntaxFacts: parameterSyntaxFacts.summary,
            parameterCallSiteSyntaxFacts: parameterCallSiteSyntaxFacts.summary,
            parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary(
                candidateUSRs: parameterSyntaxFacts.localBindingOnlyCoverageCandidateUSRs,
                entries: entries,
                decisions: denied,
                groupsByUSR: groupsByUSR
            )
        )
    }

    private struct PropertyWrapperReplacementTemplate: Hashable {
        let path: String
        let byteOffset: Int
        let length: Int
        let line: Int
        let utf8Column: Int
        let oldName: String
        let derivedPrefix: String
        let derivedUSR: String
    }

    private struct PropertyWrapperRenameComponent {
        let propertyUSR: String
        let replacements: Set<PropertyWrapperReplacementTemplate>
    }

    private static func propertyWrapperRenameComponents(
        indexedFacts: IndexedSemanticFacts,
        groupsByUSR: [String: USROccurrenceGroup],
        sourceCache: SourceFileCache
    ) -> [PropertyWrapperRenameComponent] {
        var components: [PropertyWrapperRenameComponent] = []
        for propertyUSR in indexedFacts.propertyWrapperDerivedUSRsByPropertyUSR.keys.sorted() {
            guard let propertyGroup = groupsByUSR[propertyUSR] else {
                continue
            }
            let propertyName = propertyGroup.symbol.name
            let derivedUSRs = indexedFacts.propertyWrapperDerivedUSRsByPropertyUSR[propertyUSR] ?? []
            var templates: Set<PropertyWrapperReplacementTemplate> = []
            var failed = false

            for derivedUSR in derivedUSRs.sorted() {
                guard let derivedGroup = groupsByUSR[derivedUSR],
                      derivedGroup.symbol.name.hasSuffix(propertyName) else {
                    failed = true
                    break
                }
                let prefix = String(derivedGroup.symbol.name.dropLast(propertyName.count))
                guard !prefix.isEmpty,
                      prefix.allSatisfy({ $0 == "$" || $0 == "_" }) else {
                    failed = true
                    break
                }

                for occurrence in derivedGroup.occurrences where !occurrence.roles.contains("implicit") {
                    guard let source = sourceCache.file(for: occurrence.path),
                          let byteOffset = source.byteOffset(
                            line: occurrence.line,
                            utf8Column: occurrence.utf8Column
                          ) else {
                        failed = true
                        break
                    }
                    let oldName = prefix + propertyName
                    let byteRange = byteOffset..<(byteOffset + oldName.utf8.count)
                    guard source.text(in: byteRange) == oldName else {
                        failed = true
                        break
                    }
                    templates.insert(PropertyWrapperReplacementTemplate(
                        path: source.path,
                        byteOffset: byteOffset,
                        length: oldName.utf8.count,
                        line: occurrence.line,
                        utf8Column: occurrence.utf8Column,
                        oldName: oldName,
                        derivedPrefix: prefix,
                        derivedUSR: derivedUSR
                    ))
                }
                if failed {
                    break
                }
            }

            if !failed {
                components.append(PropertyWrapperRenameComponent(
                    propertyUSR: propertyUSR,
                    replacements: templates
                ))
            }
        }
        return components.sorted { $0.propertyUSR < $1.propertyUSR }
    }

    private static func propertyWrapperSupportReplacements(
        components: [PropertyWrapperRenameComponent],
        entries: [RenamePlanEntry]
    ) -> [SourceReplacement] {
        let entriesByUSR = Dictionary(uniqueKeysWithValues: entries.map { ($0.usr, $0) })
        var replacements: Set<SourceReplacement> = []
        for component in components {
            guard let entry = entriesByUSR[component.propertyUSR] else {
                continue
            }
            for template in component.replacements {
                replacements.insert(SourceReplacement(
                    path: template.path,
                    byteOffset: template.byteOffset,
                    length: template.length,
                    line: template.line,
                    utf8Column: template.utf8Column,
                    oldName: template.oldName,
                    newName: template.derivedPrefix + entry.newName,
                    usr: template.derivedUSR
                ))
            }
        }
        return replacements.sorted { lhs, rhs in
            (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
        }
    }

    private struct CodingKeyPreservationComponent {
        let ownerUSR: String
        let propertyUSRs: [String]
        let qualifiedOwnerUSRs: [String]
        let path: String
        let declarationLine: Int
    }

    private static func codingKeyPreservationComponents(
        indexedFacts: IndexedSemanticFacts,
        groupsByUSR: [String: USROccurrenceGroup],
        sourceCache: SourceFileCache,
        obfuscationRoots: [URL]
    ) -> [CodingKeyPreservationComponent] {
        var components: [CodingKeyPreservationComponent] = []
        for ownerUSR in indexedFacts.serializationSensitiveOwnerUSRs.sorted() {
            guard indexedFacts.symbolsByUSR[ownerUSR]?.kind == "struct",
                  !indexedFacts.explicitCodingKeysOwnerUSRs.contains(ownerUSR),
                  !indexedFacts.customSerializationImplementationOwnerUSRs.contains(ownerUSR),
                  let qualifiedOwnerUSRs = indexedFacts.qualifiedNominalOwnerUSRs(for: ownerUSR),
                  qualifiedOwnerUSRs.allSatisfy({ usr in
                    indexedFacts.symbolsByUSR[usr].flatMap { escapedSwiftIdentifier($0.name) } != nil
                  }),
                  let ownerGroup = groupsByUSR[ownerUSR] else {
                continue
            }

            let propertyUSRs = indexedFacts.directStoredPropertyUSRs(of: ownerUSR).sorted()
            guard !propertyUSRs.isEmpty,
                  propertyUSRs.allSatisfy({ usr in
                    groupsByUSR[usr] != nil
                        && indexedFacts.symbolsByUSR[usr].flatMap { escapedSwiftIdentifier($0.name) } != nil
                  }) else {
                continue
            }

            let ownerDeclarations = Dictionary(grouping: ownerGroup.occurrences.filter { occurrence in
                (occurrence.roles.contains("declaration") || occurrence.roles.contains("definition"))
                    && !occurrence.roles.contains("implicit")
                    && isPath(occurrence.path, under: obfuscationRoots)
                    && sourceCache.file(for: occurrence.path) != nil
            }) { occurrence in
                "\(SourcePathNormalizer.canonicalPath(occurrence.path)):\(occurrence.line):\(occurrence.utf8Column)"
            }.values.compactMap(\.first)
            guard ownerDeclarations.count == 1,
                  let ownerDeclaration = ownerDeclarations.first else {
                continue
            }

            components.append(CodingKeyPreservationComponent(
                ownerUSR: ownerUSR,
                propertyUSRs: propertyUSRs,
                qualifiedOwnerUSRs: qualifiedOwnerUSRs,
                path: SourcePathNormalizer.canonicalPath(ownerDeclaration.path),
                declarationLine: ownerDeclaration.line
            ))
        }
        return components.sorted { lhs, rhs in
            (lhs.path, lhs.declarationLine, lhs.ownerUSR) < (rhs.path, rhs.declarationLine, rhs.ownerUSR)
        }
    }

    private static func codingKeySupportReplacements(
        components: [CodingKeyPreservationComponent],
        entries: [RenamePlanEntry],
        indexedFacts: IndexedSemanticFacts,
        sourceCache: SourceFileCache
    ) -> [SourceReplacement] {
        let entriesByUSR = Dictionary(uniqueKeysWithValues: entries.map { ($0.usr, $0) })
        var chunksByPath: [String: [(ownerUSR: String, line: Int, text: String)]] = [:]

        for component in components {
            guard !component.propertyUSRs.allSatisfy({ entriesByUSR[$0] == nil }) else {
                continue
            }

            let qualifiedOwnerNames = component.qualifiedOwnerUSRs.compactMap { usr -> String? in
                guard let originalName = indexedFacts.symbolsByUSR[usr]?.name else {
                    return nil
                }
                return escapedSwiftIdentifier(entriesByUSR[usr]?.newName ?? originalName)
            }
            guard qualifiedOwnerNames.count == component.qualifiedOwnerUSRs.count else {
                continue
            }

            let cases = component.propertyUSRs.compactMap { usr -> (String, String)? in
                guard let originalName = indexedFacts.symbolsByUSR[usr]?.name,
                      let caseName = escapedSwiftIdentifier(entriesByUSR[usr]?.newName ?? originalName) else {
                    return nil
                }
                return (originalName, "        case \(caseName) = \"\(originalName)\"")
            }.sorted { lhs, rhs in
                (lhs.0, lhs.1) < (rhs.0, rhs.1)
            }
            guard cases.count == component.propertyUSRs.count else {
                continue
            }

            let text = [
                "extension \(qualifiedOwnerNames.joined(separator: ".")) {",
                "    private enum CodingKeys: String, CodingKey {",
                cases.map(\.1).joined(separator: "\n"),
                "    }",
                "}"
            ].joined(separator: "\n")
            chunksByPath[component.path, default: []].append((
                ownerUSR: component.ownerUSR,
                line: component.declarationLine,
                text: text
            ))
        }

        return chunksByPath.compactMap { path, chunks -> SourceReplacement? in
            guard let source = sourceCache.file(for: path),
                  let first = chunks.sorted(by: {
                    ($0.line, $0.ownerUSR) < ($1.line, $1.ownerUSR)
                  }).first else {
                return nil
            }
            let sortedChunks = chunks.sorted {
                ($0.line, $0.ownerUSR) < ($1.line, $1.ownerUSR)
            }
            let separator = source.data.last == UInt8(ascii: "\n") ? "\n" : "\n\n"
            let insertion = separator + sortedChunks.map(\.text).joined(separator: "\n\n") + "\n"
            return SourceReplacement(
                path: path,
                byteOffset: source.data.count,
                length: 0,
                line: first.line,
                utf8Column: 1,
                oldName: "",
                newName: insertion,
                usr: "coding-keys:\(first.ownerUSR)"
            )
        }.sorted { lhs, rhs in
            (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
        }
    }

    private static func escapedSwiftIdentifier(_ name: String) -> String? {
        guard !name.isEmpty,
              !name.contains("`"),
              !name.contains("\n"),
              !name.contains("\r") else {
            return nil
        }
        return isPlainSwiftIdentifier(name) ? name : "`\(name)`"
    }

    private static func isPath(_ path: String, under roots: [URL]) -> Bool {
        let canonicalPath = SourcePathNormalizer.canonicalPath(path)
        return roots.contains { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            return canonicalPath == rootPath || canonicalPath.hasPrefix(rootPath + "/")
        }
    }

    private enum CoordinatedRenameComponentKind {
        case protocolWitness
        case overrideChain
    }

    private struct CoordinatedRenameComponent {
        let key: String
        let memberUSRs: Set<String>
        let protocolRequirementUSRs: Set<String>
        let structuralReasons: [String]

        let kind: CoordinatedRenameComponentKind

        func denialReason(_ summaries: [String]) -> String {
            let uniqueSummaries = Array(Set(summaries)).sorted()
            let visible = uniqueSummaries.prefix(5).joined(separator: " | ")
            let remainder = uniqueSummaries.count - min(uniqueSummaries.count, 5)
            let suffix = remainder > 0 ? " | plus \(remainder) more blocker(s)" : ""
            switch kind {
            case .protocolWitness:
                return "protocol members require relation-aware witness renaming: coordinated component denied atomically (\(visible)\(suffix))"
            case .overrideChain:
                return "override relations require coordinated renaming: coordinated override/base component denied atomically (\(visible)\(suffix))"
            }
        }
    }

    private static func coordinatedRenameComponents(
        indexedFacts: IndexedSemanticFacts,
        groupsByUSR: [String: USROccurrenceGroup]
    ) -> [CoordinatedRenameComponent] {
        let localRequirementUSRs = Set(indexedFacts.protocolRequirementUSRs.filter { usr in
            groupsByUSR[usr].map { !isSyntheticAccessorName($0.symbol.name) } == true
        })
        let componentSeeds = localRequirementUSRs.union(indexedFacts.overrideRelatedUSRs)

        var visited: Set<String> = []
        var components: [CoordinatedRenameComponent] = []
        for seedUSR in componentSeeds.sorted() {
            guard !visited.contains(seedUSR) else {
                continue
            }

            var members: Set<String> = []
            var pending = [seedUSR]
            while let usr = pending.popLast() {
                guard members.insert(usr).inserted else {
                    continue
                }
                pending.append(contentsOf: (indexedFacts.overrideRelationNeighbors[usr] ?? []).filter {
                    !members.contains($0)
                })
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
                if !indexedFacts.selectedDeclarationUSRs.contains(memberGroup.usr) {
                    structuralReasons.append("related USR has no declaration inside selected source roots: \(usr)")
                }
            }

            let protocolRequirementUSRs = members.intersection(localRequirementUSRs)
            components.append(CoordinatedRenameComponent(
                key: members.sorted().first ?? seedUSR,
                memberUSRs: members,
                protocolRequirementUSRs: protocolRequirementUSRs,
                structuralReasons: Array(Set(structuralReasons)).sorted(),
                kind: protocolRequirementUSRs.isEmpty ? .overrideChain : .protocolWitness
            ))
        }

        return components.sorted { $0.key < $1.key }
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
            (relation.roles.contains("overrideOf") || relation.roles.contains("baseOf"))
                && componentUSRs.contains(relation.usr)
        }
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
            "variable",
            "parameter"
        ]
        guard lowerCamelCaseKinds.contains(symbolKind),
              let letterIndex = name.firstIndex(where: \.isLetter) else {
            return name
        }

        var result = name
        result.replaceSubrange(letterIndex...letterIndex, with: String(name[letterIndex]).lowercased())
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
