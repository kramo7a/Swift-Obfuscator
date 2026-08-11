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
    public let parameterCallArgumentBindingFacts: ParameterCallArgumentBindingFactsSummary
    public let parameterCallableReferenceSyntaxFacts: ParameterCallableReferenceSyntaxFactsSummary
    public let parameterCallableReferenceBindingFacts: ParameterCallableReferenceBindingFactsSummary
    public let parameterExternalLabelComponentFacts: ParameterExternalLabelComponentFactsSummary
    public let parameterExternalLabelRenameOutcome: ParameterExternalLabelRenameOutcomeSummary
    public let parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary
    public let enumCaseComponentFacts: EnumCaseComponentFactsSummary
    public let enumCaseSyntaxFacts: EnumCaseSyntaxFactsSummary
    public let genericParameterSyntaxFacts: GenericParameterSyntaxFactsSummary
    public let typealiasSyntaxFacts: TypealiasSyntaxFactsSummary

    public init(
        entries: [RenamePlanEntry],
        denied: [SafetyDecision],
        conflicts: [String],
        supportReplacements: [SourceReplacement] = [],
        parameterFacts: ParameterFactsSummary = .empty,
        parameterSyntaxFacts: ParameterSyntaxFactsSummary = .empty,
        parameterCallSiteSyntaxFacts: ParameterCallSiteSyntaxFactsSummary = .empty,
        parameterCallArgumentBindingFacts: ParameterCallArgumentBindingFactsSummary = .empty,
        parameterCallableReferenceSyntaxFacts: ParameterCallableReferenceSyntaxFactsSummary = .empty,
        parameterCallableReferenceBindingFacts: ParameterCallableReferenceBindingFactsSummary = .empty,
        parameterExternalLabelComponentFacts: ParameterExternalLabelComponentFactsSummary = .empty,
        parameterExternalLabelRenameOutcome: ParameterExternalLabelRenameOutcomeSummary = .empty,
        parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary = .empty,
        enumCaseComponentFacts: EnumCaseComponentFactsSummary = .empty,
        enumCaseSyntaxFacts: EnumCaseSyntaxFactsSummary = .empty,
        genericParameterSyntaxFacts: GenericParameterSyntaxFactsSummary = .empty,
        typealiasSyntaxFacts: TypealiasSyntaxFactsSummary = .empty
    ) {
        self.entries = entries
        self.denied = denied
        self.conflicts = conflicts
        self.supportReplacements = supportReplacements
        self.parameterFacts = parameterFacts
        self.parameterSyntaxFacts = parameterSyntaxFacts
        self.parameterCallSiteSyntaxFacts = parameterCallSiteSyntaxFacts
        self.parameterCallArgumentBindingFacts = parameterCallArgumentBindingFacts
        self.parameterCallableReferenceSyntaxFacts = parameterCallableReferenceSyntaxFacts
        self.parameterCallableReferenceBindingFacts = parameterCallableReferenceBindingFacts
        self.parameterExternalLabelComponentFacts = parameterExternalLabelComponentFacts
        self.parameterExternalLabelRenameOutcome = parameterExternalLabelRenameOutcome
        self.parameterLocalBindingOutcome = parameterLocalBindingOutcome
        self.enumCaseComponentFacts = enumCaseComponentFacts
        self.enumCaseSyntaxFacts = enumCaseSyntaxFacts
        self.genericParameterSyntaxFacts = genericParameterSyntaxFacts
        self.typealiasSyntaxFacts = typealiasSyntaxFacts
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case denied
        case conflicts
        case supportReplacements
        case parameterFacts
        case parameterSyntaxFacts
        case parameterCallSiteSyntaxFacts
        case parameterCallArgumentBindingFacts
        case parameterCallableReferenceSyntaxFacts
        case parameterCallableReferenceBindingFacts
        case parameterExternalLabelComponentFacts
        case parameterExternalLabelRenameOutcome
        case parameterLocalBindingOutcome
        case enumCaseComponentFacts
        case enumCaseSyntaxFacts
        case genericParameterSyntaxFacts
        case typealiasSyntaxFacts
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
        parameterCallArgumentBindingFacts = try container.decodeIfPresent(
            ParameterCallArgumentBindingFactsSummary.self,
            forKey: .parameterCallArgumentBindingFacts
        ) ?? .empty
        parameterCallableReferenceSyntaxFacts = try container.decodeIfPresent(
            ParameterCallableReferenceSyntaxFactsSummary.self,
            forKey: .parameterCallableReferenceSyntaxFacts
        ) ?? .empty
        parameterCallableReferenceBindingFacts = try container.decodeIfPresent(
            ParameterCallableReferenceBindingFactsSummary.self,
            forKey: .parameterCallableReferenceBindingFacts
        ) ?? .empty
        parameterExternalLabelComponentFacts = try container.decodeIfPresent(
            ParameterExternalLabelComponentFactsSummary.self,
            forKey: .parameterExternalLabelComponentFacts
        ) ?? .empty
        parameterExternalLabelRenameOutcome = try container.decodeIfPresent(
            ParameterExternalLabelRenameOutcomeSummary.self,
            forKey: .parameterExternalLabelRenameOutcome
        ) ?? .empty
        parameterLocalBindingOutcome = try container.decodeIfPresent(
            ParameterLocalBindingOutcomeSummary.self,
            forKey: .parameterLocalBindingOutcome
        ) ?? .empty
        enumCaseComponentFacts = try container.decodeIfPresent(
            EnumCaseComponentFactsSummary.self,
            forKey: .enumCaseComponentFacts
        ) ?? .empty
        enumCaseSyntaxFacts = try container.decodeIfPresent(
            EnumCaseSyntaxFactsSummary.self,
            forKey: .enumCaseSyntaxFacts
        ) ?? .empty
        genericParameterSyntaxFacts = try container.decodeIfPresent(
            GenericParameterSyntaxFactsSummary.self,
            forKey: .genericParameterSyntaxFacts
        ) ?? .empty
        typealiasSyntaxFacts = try container.decodeIfPresent(
            TypealiasSyntaxFactsSummary.self,
            forKey: .typealiasSyntaxFacts
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
        let enumCaseComponentFacts = EnumCaseComponentFacts(
            snapshot: snapshot,
            indexedFacts: indexedFacts,
            obfuscationRoots: analyzer.obfuscationRoots
        )
        let enumCaseSyntaxFacts = EnumCaseSyntaxFacts(
            snapshot: snapshot,
            semanticFacts: enumCaseComponentFacts,
            sourceCache: sourceCache,
            obfuscationRoots: analyzer.obfuscationRoots
        )
        let enumCaseUSRs = Set(
            enumCaseSyntaxFacts.components.flatMap { $0.members.map(\.caseUSR) }
        )
        let eligibleEnumCaseUSRs = Set(
            enumCaseSyntaxFacts.components.filter(\.isPreliminaryEligible).flatMap {
                $0.members.map(\.caseUSR)
            }
        )
        let enumCaseOwnerComponentByCaseUSR = Dictionary(
            uniqueKeysWithValues: enumCaseSyntaxFacts.components.flatMap { component in
                component.members.map { ($0.caseUSR, component) }
            }
        )
        let parameterSyntaxFacts = ParameterSyntaxFacts(
            snapshot: snapshot,
            sourceCache: sourceCache,
            obfuscationRoots: analyzer.obfuscationRoots
        )
        let genericParameterSyntaxFacts = GenericParameterSyntaxFacts(
            snapshot: snapshot,
            sourceCache: sourceCache,
            obfuscationRoots: analyzer.obfuscationRoots
        )
        let typealiasSyntaxFacts = TypealiasSyntaxFacts(
            snapshot: snapshot,
            sourceCache: sourceCache,
            obfuscationRoots: analyzer.obfuscationRoots
        )
        let parameterCallSiteSyntaxFacts = ParameterCallSiteSyntaxFacts(
            components: indexedFacts.parameterRenameComponents,
            sourceCache: sourceCache
        )
        let parameterCallArgumentBindingFacts = ParameterCallArgumentBindingFacts(
            components: indexedFacts.parameterRenameComponents,
            parameterRolesByUSR: parameterSyntaxFacts.rolesByUSR,
            callSiteSyntaxFacts: parameterCallSiteSyntaxFacts
        )
        let parameterCallableReferenceSyntaxFacts = ParameterCallableReferenceSyntaxFacts(
            components: indexedFacts.parameterRenameComponents,
            sourceCache: sourceCache
        )
        let parameterCallableReferenceBindingFacts = ParameterCallableReferenceBindingFacts(
            components: indexedFacts.parameterRenameComponents,
            parameterRolesByUSR: parameterSyntaxFacts.rolesByUSR,
            syntaxFacts: parameterCallableReferenceSyntaxFacts
        )
        let parameterExternalLabelComponentFacts = ParameterExternalLabelComponentFacts(
            indexedFacts: indexedFacts,
            parameterRolesByUSR: parameterSyntaxFacts.rolesByUSR,
            callBindingFacts: parameterCallArgumentBindingFacts,
            callableReferenceBindingFacts: parameterCallableReferenceBindingFacts,
            eligibleEnumCaseUSRs: eligibleEnumCaseUSRs
        )
        let externalLabelParameterUSRs = Set(
            parameterExternalLabelComponentFacts.components.flatMap(\.namedParameterUSRs)
        )
        let externalLabelComponentByParameterUSR = Dictionary(
            uniqueKeysWithValues: parameterExternalLabelComponentFacts.components.flatMap {
                component in
                component.namedParameterUSRs.map { ($0, component) }
            }
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
            if externalLabelParameterUSRs.contains(group.usr) {
                continue
            }
            if enumCaseUSRs.contains(group.usr) {
                continue
            }
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
                        tupleTypealiasRelatedUSRs:
                            typealiasSyntaxFacts.unsafeTupleRelatedUSRs,
                        coordinatedRelatedUSRs: coordinationEnabled ? component.memberUSRs : [],
                        coordinatedProtocolRequirementUSRs: coordinationEnabled
                            ? component.protocolRequirementUSRs
                            : [],
                        genericParameterUSRs:
                            genericParameterSyntaxFacts.genericParameterUSRs,
                        supportedGenericParameterUSRs:
                            genericParameterSyntaxFacts.supportedGenericParameterUSRs,
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
                tupleTypealiasRelatedUSRs: typealiasSyntaxFacts.unsafeTupleRelatedUSRs,
                genericParameterUSRs: genericParameterSyntaxFacts.genericParameterUSRs,
                supportedGenericParameterUSRs:
                    genericParameterSyntaxFacts.supportedGenericParameterUSRs,
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

        let enumCasePlanning = EnumCaseRenamePlanning.makeResult(
            facts: enumCaseSyntaxFacts,
            groupsByUSR: groupsByUSR,
            indexedFacts: indexedFacts,
            analyzer: analyzer,
            sourceCache: sourceCache
        )
        denied.append(contentsOf: enumCasePlanning.denied)
        for componentTemplate in enumCasePlanning.componentTemplates {
            guard let component = enumCaseSyntaxFacts.components.first(where: {
                $0.ownerUSR == componentTemplate.ownerUSR
            }) else {
                continue
            }

            var mappingFailures: Set<String> = []
            var existingNamesByUSR: [String: String] = [:]
            for member in componentTemplate.members {
                guard let existing = mappingStore.entry(for: member.usr) else {
                    continue
                }
                if existing.originalName != member.oldName || existing.kind != "enumConstant" {
                    mappingFailures.insert(
                        "persisted mapping metadata disagrees for \(member.usr)"
                    )
                } else {
                    existingNamesByUSR[member.usr] = existing.obfuscatedName
                }
            }
            let existingTargets = Array(existingNamesByUSR.values)
            if Set(existingTargets).count != existingTargets.count {
                mappingFailures.insert("enum owner members have duplicate persisted mappings")
            }
            guard mappingFailures.isEmpty else {
                denied.append(contentsOf: EnumCaseRenamePlanning.denialDecisions(
                    component: component,
                    groupsByUSR: groupsByUSR,
                    reasons: mappingFailures.sorted()
                ))
                continue
            }

            for member in componentTemplate.members {
                let newName: String
                if let existingName = existingNamesByUSR[member.usr] {
                    newName = existingName
                } else {
                    newName = nextName(for: "enumConstant", avoiding: reservedNames)
                    reservedNames.insert(newName)
                }
                if mappingStore.entry(for: member.usr) == nil {
                    mappingStore.record(
                        usr: member.usr,
                        originalName: member.oldName,
                        obfuscatedName: newName,
                        kind: "enumConstant"
                    )
                }
                entries.append(RenamePlanEntry(
                    usr: member.usr,
                    kind: "enumConstant",
                    oldName: member.oldName,
                    newName: newName,
                    replacements: member.replacements.map {
                        $0.replacement(newName: newName)
                    }.sorted { lhs, rhs in
                        (lhs.path, lhs.byteOffset, lhs.usr)
                            < (rhs.path, rhs.byteOffset, rhs.usr)
                    }
                ))
            }
        }

        let externalLabelPlanning = ParameterExternalLabelRenamePlanning.makeResult(
            facts: parameterExternalLabelComponentFacts,
            groupsByUSR: groupsByUSR,
            indexedFacts: indexedFacts,
            parameterRolesByUSR: parameterSyntaxFacts.rolesByUSR,
            callBindingFacts: parameterCallArgumentBindingFacts,
            callableReferenceBindingFacts: parameterCallableReferenceBindingFacts,
            analyzer: analyzer,
            sourceCache: sourceCache
        )
        denied.append(contentsOf: externalLabelPlanning.denied)
        for componentTemplate in externalLabelPlanning.componentTemplates {
            guard let component = parameterExternalLabelComponentFacts.components.first(where: {
                $0.key == componentTemplate.key
            }) else {
                continue
            }
            var mappingFailures: Set<String> = []
            var existingNamesByOrdinal: [Int: String] = [:]
            for ordinalTemplate in componentTemplate.ordinals {
                let existingEntries = ordinalTemplate.parameters.compactMap {
                    mappingStore.entry(for: $0.usr)
                }
                let existingNames = Set(existingEntries.map(\.obfuscatedName))
                if existingNames.count > 1 {
                    mappingFailures.insert(
                        "ordinal \(ordinalTemplate.ordinal) has inconsistent persisted mappings"
                    )
                } else if let existingName = existingNames.first {
                    existingNamesByOrdinal[ordinalTemplate.ordinal] = existingName
                }
                for parameter in ordinalTemplate.parameters {
                    guard let existing = mappingStore.entry(for: parameter.usr) else {
                        continue
                    }
                    if existing.originalName != parameter.oldName
                        || existing.kind != "parameter" {
                        mappingFailures.insert(
                            "persisted mapping metadata disagrees for \(parameter.usr)"
                        )
                    }
                }
            }
            guard mappingFailures.isEmpty else {
                denied.append(contentsOf: ParameterExternalLabelRenamePlanning.denialDecisions(
                    component: component,
                    groupsByUSR: groupsByUSR,
                    reasons: mappingFailures.sorted()
                ))
                continue
            }

            for ordinalTemplate in componentTemplate.ordinals {
                let newName: String
                if let existingName = existingNamesByOrdinal[ordinalTemplate.ordinal] {
                    newName = existingName
                } else {
                    newName = nextName(for: "parameter", avoiding: reservedNames)
                    reservedNames.insert(newName)
                }
                for parameter in ordinalTemplate.parameters {
                    if mappingStore.entry(for: parameter.usr) == nil {
                        mappingStore.record(
                            usr: parameter.usr,
                            originalName: parameter.oldName,
                            obfuscatedName: newName,
                            kind: "parameter"
                        )
                    }
                    entries.append(RenamePlanEntry(
                        usr: parameter.usr,
                        kind: "parameter",
                        oldName: parameter.oldName,
                        newName: newName,
                        replacements: parameter.replacements.map {
                            $0.replacement(newName: newName)
                        }.sorted { lhs, rhs in
                            (lhs.path, lhs.byteOffset, lhs.usr)
                                < (rhs.path, rhs.byteOffset, rhs.usr)
                        }
                    ))
                }
            }
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
            let conflictedExternalLabelComponents = Set(entries.compactMap {
                entry -> String? in
                guard entry.replacements.contains(where: {
                    conflictKeys.contains("\($0.path):\($0.byteOffset)")
                }) else {
                    return nil
                }
                return externalLabelComponentByParameterUSR[entry.usr]?.key
            })
            let conflictedEnumCaseOwners = Set(entries.compactMap { entry -> String? in
                guard entry.replacements.contains(where: {
                    conflictKeys.contains("\($0.path):\($0.byteOffset)")
                }) else {
                    return nil
                }
                return enumCaseOwnerComponentByCaseUSR[entry.usr]?.ownerUSR
            })
            entries = entries.compactMap { entry in
                if let componentKey = coordinatedComponentByUSR[entry.usr]?.key,
                   conflictedCoordinatedComponents.contains(componentKey) {
                    return nil
                }
                if let componentKey = externalLabelComponentByParameterUSR[entry.usr]?.key,
                   conflictedExternalLabelComponents.contains(componentKey) {
                    return nil
                }
                if let ownerUSR = enumCaseOwnerComponentByCaseUSR[entry.usr]?.ownerUSR,
                   conflictedEnumCaseOwners.contains(ownerUSR) {
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
            for component in parameterExternalLabelComponentFacts.components
            where conflictedExternalLabelComponents.contains(component.key) {
                denied.append(contentsOf: ParameterExternalLabelRenamePlanning.denialDecisions(
                    component: component,
                    groupsByUSR: groupsByUSR,
                    reasons: [
                        "component contains a replacement conflict and was removed atomically"
                    ]
                ))
            }
            for component in enumCaseSyntaxFacts.components
            where conflictedEnumCaseOwners.contains(component.ownerUSR) {
                denied.append(contentsOf: EnumCaseRenamePlanning.denialDecisions(
                    component: component,
                    groupsByUSR: groupsByUSR,
                    reasons: [
                        "component contains a replacement conflict and was removed atomically"
                    ]
                ))
            }
        }

        // A declaration can participate in more than one denied safety layer.
        // For example, an enum case that witnesses a protocol requirement is
        // denied both by the enum-owner component and by the coordinated
        // protocol graph. Reports and parameter outcome summaries require one
        // deterministic decision per USR, so preserve every reason while
        // coalescing the duplicate records before constructing those summaries.
        denied = Self.coalescedDenials(denied)

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
            parameterCallArgumentBindingFacts: parameterCallArgumentBindingFacts.summary,
            parameterCallableReferenceSyntaxFacts: parameterCallableReferenceSyntaxFacts.summary,
            parameterCallableReferenceBindingFacts:
                parameterCallableReferenceBindingFacts.summary,
            parameterExternalLabelComponentFacts: parameterExternalLabelComponentFacts.summary,
            parameterExternalLabelRenameOutcome: ParameterExternalLabelRenameOutcomeSummary(
                components: parameterExternalLabelComponentFacts.components,
                entries: entries,
                decisions: denied
            ),
            parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary(
                candidateUSRs: parameterSyntaxFacts.localBindingOnlyCoverageCandidateUSRs,
                entries: entries,
                decisions: denied,
                groupsByUSR: groupsByUSR
            ),
            enumCaseComponentFacts: enumCaseComponentFacts.summary,
            enumCaseSyntaxFacts: enumCaseSyntaxFacts.summary,
            genericParameterSyntaxFacts: genericParameterSyntaxFacts.summary,
            typealiasSyntaxFacts: typealiasSyntaxFacts.summary
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

    private static func coalescedDenials(
        _ decisions: [SafetyDecision]
    ) -> [SafetyDecision] {
        Dictionary(grouping: decisions, by: \.usr).values.compactMap { duplicates in
            guard let first = duplicates.sorted(by: {
                ($0.symbolName, $0.kind, $0.oldName ?? "")
                    < ($1.symbolName, $1.kind, $1.oldName ?? "")
            }).first else {
                return nil
            }
            return SafetyDecision(
                usr: first.usr,
                symbolName: first.symbolName,
                kind: first.kind,
                allowed: false,
                oldName: first.oldName,
                reasons: Array(Set(duplicates.flatMap(\.reasons))).sorted()
            )
        }
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
            "parameter",
            "enumConstant"
        ]
        guard lowerCamelCaseKinds.contains(symbolKind),
              let letterIndex = name.firstIndex(where: \.isLetter) else {
            return name
        }

        var result = name
        result.replaceSubrange(letterIndex...letterIndex, with: String(name[letterIndex]).lowercased())
        return result
    }

}
