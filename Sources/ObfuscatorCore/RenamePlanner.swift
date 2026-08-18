import Foundation

public struct RenamePlanner {
    public var analyzer: SafetyAnalyzer
    public var generator: NameGenerator
    public var mappingStore: MappingStore

    public init(
        analyzer: SafetyAnalyzer,
        generator: NameGenerator = NameGenerator(),
        mappingStore: MappingStore = MappingStore()
    ) {
        self.analyzer = analyzer
        self.generator = generator
        self.mappingStore = mappingStore
    }

    // MARK: - Planning context

    private struct PlanningContext {
        let groups: [USROccurrenceGroup]
        let groupsByUSR: [String: USROccurrenceGroup]
        let indexedFacts: IndexedSemanticFacts
        let enumCaseComponentFacts: EnumCaseComponentFacts
        let compilerRawValueFacts: CompilerRawValueFacts
        let enumCaseSyntaxFacts: EnumCaseSyntaxFacts
        let enumCaseUSRs: Set<String>
        let enumCaseOwnerComponentByCaseUSR: [String: EnumCaseOwnerSyntaxComponent]
        let parameterSyntaxFacts: ParameterSyntaxFacts
        let genericParameterSyntaxFacts: GenericParameterSyntaxFacts
        let typealiasSyntaxFacts: TypealiasSyntaxFacts
        let parameterCallSiteSyntaxFacts: ParameterCallSiteSyntaxFacts
        let parameterCallArgumentBindingFacts: ParameterCallArgumentBindingFacts
        let parameterCallableReferenceSyntaxFacts: ParameterCallableReferenceSyntaxFacts
        let parameterCallableReferenceBindingFacts: ParameterCallableReferenceBindingFacts
        let parameterExternalLabelComponentFacts: ParameterExternalLabelComponentFacts
        let externalLabelParameterUSRs: Set<String>
        let namedLocalBindingParameterUSRs: Set<String>
        let externalLabelComponentByParameterUSR: [String: ParameterExternalLabelRenameComponent]
        let codingKeyComponents: [CodingKeyPreservationComponent]
        let propertyWrapperComponents: [PropertyWrapperRenameComponent]
        let propertyWrapperSupportedUSRs: Set<String>
        let coordinatedComponents: [CoordinatedRenameComponent]
        let coordinatedComponentByUSR: [String: CoordinatedRenameComponent]
        let explicitCodingKeyPlanning: ExplicitCodingKeyRenamePlanningResult
        let explicitCodingKeyPairByUSR: [String: ExplicitCodingKeyPairRenameTemplate]
        let serializationKeyPreservedUSRs: Set<String>

        init(
            snapshot: IndexSnapshot,
            sourceCache: SourceFileCache,
            analyzer: SafetyAnalyzer
        ) {
            groups = snapshot.groupsByUSR
            groupsByUSR = Dictionary(uniqueKeysWithValues: groups.map { ($0.usr, $0) })
            indexedFacts = IndexedSemanticFacts(
                snapshot: snapshot,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            enumCaseComponentFacts = EnumCaseComponentFacts(
                snapshot: snapshot,
                indexedFacts: indexedFacts,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            compilerRawValueFacts = CompilerRawValueFacts(
                snapshot: snapshot,
                semanticFacts: enumCaseComponentFacts,
                indexedFacts: indexedFacts,
                sourceCache: sourceCache
            )
            enumCaseSyntaxFacts = EnumCaseSyntaxFacts(
                snapshot: snapshot,
                semanticFacts: enumCaseComponentFacts,
                compilerRawValueFacts: compilerRawValueFacts,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            enumCaseUSRs = Set(
                enumCaseSyntaxFacts.components.flatMap { $0.members.map(\.caseUSR) }
            )
            enumCaseOwnerComponentByCaseUSR = Dictionary(
                uniqueKeysWithValues: enumCaseSyntaxFacts.components.flatMap { component in
                    component.members.map { ($0.caseUSR, component) }
                }
            )

            parameterSyntaxFacts = ParameterSyntaxFacts(
                snapshot: snapshot,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            genericParameterSyntaxFacts = GenericParameterSyntaxFacts(
                snapshot: snapshot,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            typealiasSyntaxFacts = TypealiasSyntaxFacts(
                snapshot: snapshot,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            parameterCallSiteSyntaxFacts = ParameterCallSiteSyntaxFacts(
                components: indexedFacts.parameterRenameComponents,
                sourceCache: sourceCache
            )
            parameterCallArgumentBindingFacts = ParameterCallArgumentBindingFacts(
                components: indexedFacts.parameterRenameComponents,
                parameterRolesByUSR: parameterSyntaxFacts.rolesByUSR,
                callSiteSyntaxFacts: parameterCallSiteSyntaxFacts
            )
            parameterCallableReferenceSyntaxFacts = ParameterCallableReferenceSyntaxFacts(
                components: indexedFacts.parameterRenameComponents,
                sourceCache: sourceCache
            )
            parameterCallableReferenceBindingFacts = ParameterCallableReferenceBindingFacts(
                components: indexedFacts.parameterRenameComponents,
                parameterRolesByUSR: parameterSyntaxFacts.rolesByUSR,
                syntaxFacts: parameterCallableReferenceSyntaxFacts
            )
            let eligibleEnumCaseUSRs = Set(
                enumCaseSyntaxFacts.components.flatMap {
                    $0.preliminaryEligibleMembers.map(\.caseUSR)
                }
            )
            parameterExternalLabelComponentFacts = ParameterExternalLabelComponentFacts(
                indexedFacts: indexedFacts,
                parameterRolesByUSR: parameterSyntaxFacts.rolesByUSR,
                callBindingFacts: parameterCallArgumentBindingFacts,
                callableReferenceBindingFacts: parameterCallableReferenceBindingFacts,
                eligibleEnumCaseUSRs: eligibleEnumCaseUSRs
            )
            externalLabelParameterUSRs = Set(
                parameterExternalLabelComponentFacts.components.flatMap(\.namedParameterUSRs)
            )
            let parameterFactsForLocalBindings = parameterSyntaxFacts
            namedLocalBindingParameterUSRs = Set(
                parameterFactsForLocalBindings.rolesByUSR.values.compactMap {
                    role -> String? in
                    guard
                        parameterFactsForLocalBindings
                            .localBindingOnlyCoverageCandidateUSRs
                            .contains(role.parameterUSR),
                        case .named = role.externalLabel
                    else {
                        return nil
                    }
                    return role.parameterUSR
                }
            )
            externalLabelComponentByParameterUSR = Dictionary(
                uniqueKeysWithValues: parameterExternalLabelComponentFacts.components.flatMap {
                    component in
                    component.namedParameterUSRs.map { ($0, component) }
                }
            )

            codingKeyComponents = RenamePlanner.codingKeyPreservationComponents(
                indexedFacts: indexedFacts,
                groupsByUSR: groupsByUSR,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            propertyWrapperComponents = RenamePlanner.propertyWrapperRenameComponents(
                indexedFacts: indexedFacts,
                groupsByUSR: groupsByUSR,
                sourceCache: sourceCache
            )
            propertyWrapperSupportedUSRs = Set(propertyWrapperComponents.map(\.propertyUSR))
            coordinatedComponents = RenamePlanner.coordinatedRenameComponents(
                indexedFacts: indexedFacts,
                groupsByUSR: groupsByUSR
            )
            let componentsForLookup = coordinatedComponents
            let occurrenceGroupsByUSR = groupsByUSR
            coordinatedComponentByUSR = Dictionary(
                uniqueKeysWithValues: componentsForLookup.flatMap { component in
                    component.memberUSRs.compactMap { usr in
                        occurrenceGroupsByUSR[usr] == nil ? nil : (usr, component)
                    }
                }
            )
            explicitCodingKeyPlanning = ExplicitCodingKeyRenamePlanning.makeResult(
                syntaxFacts: enumCaseSyntaxFacts,
                semanticFacts: enumCaseComponentFacts,
                indexedFacts: indexedFacts,
                groupsByUSR: groupsByUSR,
                analyzer: analyzer,
                sourceCache: sourceCache,
                excludedPropertyUSRs: Set(coordinatedComponentByUSR.keys)
            )
            explicitCodingKeyPairByUSR = Dictionary(
                explicitCodingKeyPlanning.pairTemplates.flatMap { pair in
                    [(pair.propertyUSR, pair), (pair.caseUSR, pair)]
                },
                uniquingKeysWith: { first, _ in first }
            )

            let factsForSerialization = indexedFacts
            let fullyManualSerializationOwnerUSRs = Set(
                factsForSerialization.serializationSensitiveOwnerUSRs.filter { ownerUSR in
                    (!factsForSerialization.decodingSensitiveOwnerUSRs.contains(ownerUSR)
                        || factsForSerialization.customDecodingImplementationOwnerUSRs
                            .contains(ownerUSR))
                        && (!factsForSerialization.encodingSensitiveOwnerUSRs.contains(ownerUSR)
                            || factsForSerialization.customEncodingImplementationOwnerUSRs
                                .contains(ownerUSR))
                }
            )
            let manualSerializationPropertyUSRs = Set(
                fullyManualSerializationOwnerUSRs.flatMap {
                    factsForSerialization.directStoredPropertyUSRs(of: $0)
                }
            )
            serializationKeyPreservedUSRs = Set(
                codingKeyComponents.flatMap(\.propertyUSRs)
            ).union(explicitCodingKeyPlanning.propertyUSRs)
                .union(manualSerializationPropertyUSRs)
        }
    }

    // MARK: - Planning

    public mutating func makePlan(snapshot: IndexSnapshot, sourceCache: SourceFileCache) -> RenamePlan {
        let context = PlanningContext(
            snapshot: snapshot,
            sourceCache: sourceCache,
            analyzer: analyzer
        )
        var denied: [SafetyDecision] = []
        var entries: [RenamePlanEntry] = []
        var reservedNames = Set(snapshot.symbols.map(\.name)).filter(isPlainSwiftIdentifier)
        reservedNames.formUnion(mappingStore.allEntries().map(\.obfuscatedName))

        planOrdinarySymbols(
            context: context,
            sourceCache: sourceCache,
            entries: &entries,
            denied: &denied,
            reservedNames: &reservedNames
        )

        planEnumCases(
            context: context,
            sourceCache: sourceCache,
            entries: &entries,
            denied: &denied,
            reservedNames: &reservedNames
        )

        planParameters(
            context: context,
            sourceCache: sourceCache,
            entries: &entries,
            denied: &denied,
            reservedNames: &reservedNames
        )

        let conflicts = Self.resolveReplacementConflicts(
            context: context,
            entries: &entries,
            denied: &denied
        )

        // A declaration can participate in more than one denied safety layer.
        // For example, an enum case that witnesses a protocol requirement is
        // denied both by the enum-owner component and by the coordinated
        // protocol graph. Reports and parameter outcome summaries require one
        // deterministic decision per USR, so preserve every reason while
        // coalescing the duplicate records before constructing those summaries.
        denied = Self.coalescedDenials(denied)

        let supportReplacements =
            Self.codingKeySupportReplacements(
                components: context.codingKeyComponents,
                entries: entries,
                indexedFacts: context.indexedFacts,
                sourceCache: sourceCache
            )
            + Self.propertyWrapperSupportReplacements(
                components: context.propertyWrapperComponents,
                entries: entries
            )
            + Self.implicitRawValueSupportReplacements(
                facts: context.enumCaseSyntaxFacts,
                entries: entries
            )

        return RenamePlan(
            entries: entries.sorted { ($0.oldName, $0.usr) < ($1.oldName, $1.usr) },
            denied: denied.sorted { ($0.symbolName, $0.usr) < ($1.symbolName, $1.usr) },
            conflicts: conflicts,
            supportReplacements: supportReplacements,
            parameterFacts: context.indexedFacts.parameterFactsSummary,
            parameterSyntaxFacts: context.parameterSyntaxFacts.summary,
            parameterCallSiteSyntaxFacts: context.parameterCallSiteSyntaxFacts.summary,
            parameterCallArgumentBindingFacts: context.parameterCallArgumentBindingFacts.summary,
            parameterCallableReferenceSyntaxFacts: context.parameterCallableReferenceSyntaxFacts.summary,
            parameterCallableReferenceBindingFacts:
                context.parameterCallableReferenceBindingFacts.summary,
            parameterExternalLabelComponentFacts: context.parameterExternalLabelComponentFacts.summary,
            parameterExternalLabelRenameOutcome: ParameterExternalLabelRenameOutcomeSummary(
                components: context.parameterExternalLabelComponentFacts.components,
                entries: entries,
                decisions: denied
            ),
            parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary(
                candidateUSRs: context.parameterSyntaxFacts.localBindingOnlyCoverageCandidateUSRs,
                entries: entries,
                decisions: denied,
                groupsByUSR: context.groupsByUSR
            ),
            enumCaseComponentFacts: context.enumCaseComponentFacts.summary,
            compilerRawValueFacts: context.compilerRawValueFacts.summary,
            enumCaseSyntaxFacts: context.enumCaseSyntaxFacts.summary,
            genericParameterSyntaxFacts: context.genericParameterSyntaxFacts.summary,
            typealiasSyntaxFacts: context.typealiasSyntaxFacts.summary
        )
    }

    private mutating func planOrdinarySymbols(
        context: PlanningContext,
        sourceCache: SourceFileCache,
        entries: inout [RenamePlanEntry],
        denied: inout [SafetyDecision],
        reservedNames: inout Set<String>
    ) {
        var processedComponentKeys: Set<String> = []

        for group in context.groups {
            guard !context.externalLabelParameterUSRs.contains(group.usr),
                !context.namedLocalBindingParameterUSRs.contains(group.usr),
                !context.enumCaseUSRs.contains(group.usr)
            else {
                continue
            }

            if let component = context.coordinatedComponentByUSR[group.usr] {
                guard processedComponentKeys.insert(component.key).inserted else {
                    continue
                }
                planCoordinatedComponent(
                    component,
                    context: context,
                    sourceCache: sourceCache,
                    entries: &entries,
                    denied: &denied,
                    reservedNames: &reservedNames
                )
            } else {
                planStandaloneSymbol(
                    group,
                    context: context,
                    sourceCache: sourceCache,
                    entries: &entries,
                    denied: &denied,
                    reservedNames: &reservedNames
                )
            }
        }
    }

    private mutating func planCoordinatedComponent(
        _ component: CoordinatedRenameComponent,
        context: PlanningContext,
        sourceCache: SourceFileCache,
        entries: inout [RenamePlanEntry],
        denied: inout [SafetyDecision],
        reservedNames: inout Set<String>
    ) {
        let componentGroups = component.memberUSRs.compactMap { context.groupsByUSR[$0] }.sorted {
            lhs, rhs in
            (lhs.symbol.name, lhs.usr) < (rhs.symbol.name, rhs.usr)
        }
        let coordinationEnabled = component.structuralReasons.isEmpty
        let decisions = componentGroups.map { group in
            analyzer.analyze(
                group: group,
                sourceCache: sourceCache,
                indexedFacts: context.indexedFacts,
                overrideRelatedUSRs: context.indexedFacts.overrideRelatedUSRs,
                tupleTypealiasRelatedUSRs: context.typealiasSyntaxFacts.unsafeTupleRelatedUSRs,
                coordinatedRelatedUSRs: coordinationEnabled ? component.memberUSRs : [],
                coordinatedProtocolRequirementUSRs: coordinationEnabled
                    ? component.protocolRequirementUSRs
                    : [],
                genericParameterUSRs: context.genericParameterSyntaxFacts.genericParameterUSRs,
                supportedGenericParameterUSRs:
                    context.genericParameterSyntaxFacts.supportedGenericParameterUSRs,
                serializationKeyPreservedUSRs: context.serializationKeyPreservedUSRs,
                propertyWrapperSupportedUSRs: context.propertyWrapperSupportedUSRs,
                localBindingOnlyParameterUSRs:
                    context.parameterSyntaxFacts.localBindingOnlyCoverageCandidateUSRs
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

        let caseConventions = Set(
            componentGroups.map {
                Self.nameWithConventionalInitialCase("Oa", for: $0.symbol.kind)
            })
        if caseConventions.count != 1 {
            failureSummaries.append("component symbol kinds require incompatible identifier casing")
        }

        let existingNames = Set(
            componentGroups.compactMap {
                mappingStore.entry(for: $0.usr)?.obfuscatedName
            })
        if existingNames.count > 1 {
            failureSummaries.append("component USRs already have inconsistent persisted mappings")
        }

        var replacementsByUSR: [String: Set<SourceReplacement>] = [:]
        if failureSummaries.isEmpty, let oldName = oldNames.first {
            for group in componentGroups {
                var replacements: Set<SourceReplacement> = []
                var localReasons: Set<String> = []
                for occurrence in group.occurrences {
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
                    guard
                        let token = source.identifierToken(
                            line: occurrence.line,
                            utf8Column: occurrence.utf8Column
                        )
                    else {
                        localReasons.insert(
                            "identifier token unavailable at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                        )
                        continue
                    }
                    if SafetyAnalyzer.isSemanticSelfTypeReference(
                        occurrence: occurrence,
                        token: token,
                        symbolKind: group.symbol.kind
                    ) {
                        continue
                    }
                    guard token.name == oldName else {
                        localReasons.insert(
                            "token mismatch at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                        )
                        continue
                    }
                    replacements.insert(
                        SourceReplacement(
                            path: source.path,
                            byteOffset: token.byteRange.lowerBound,
                            length: token.byteRange.count,
                            line: occurrence.line,
                            utf8Column: occurrence.utf8Column,
                            oldName: oldName,
                            newName: "",
                            usr: group.usr
                        ))
                }
                if !localReasons.isEmpty {
                    failureSummaries.append(
                        "\(group.usr): \(localReasons.sorted().joined(separator: "; "))"
                    )
                } else if replacements.isEmpty {
                    failureSummaries.append("\(group.usr): no source replacements")
                } else {
                    replacementsByUSR[group.usr] = replacements
                }
            }
        }

        guard failureSummaries.isEmpty, let oldName = oldNames.first else {
            let componentReason = component.denialReason(failureSummaries)
            denied.append(
                contentsOf: zip(componentGroups, decisions).map { group, decision in
                    var reasons = decision.allowed ? [] : decision.reasons
                    reasons.append(componentReason)
                    return SafetyDecision(
                        usr: group.usr,
                        symbolName: group.symbol.name,
                        kind: group.symbol.kind,
                        allowed: false,
                        oldName: decision.oldName,
                        reasons: Array(Set(reasons)).sorted()
                    )
                })
            return
        }

        let newName: String
        if let existingName = existingNames.first {
            newName = existingName
        } else {
            newName = nextName(for: componentGroups[0].symbol.kind, avoiding: reservedNames)
            reservedNames.insert(newName)
        }

        for group in componentGroups {
            if mappingStore.entry(for: group.usr) == nil {
                mappingStore.record(
                    usr: group.usr,
                    originalName: oldName,
                    obfuscatedName: newName,
                    kind: group.symbol.kind
                )
            }
            let replacements = (replacementsByUSR[group.usr] ?? []).map { replacement in
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
            entries.append(
                RenamePlanEntry(
                    usr: group.usr,
                    kind: group.symbol.kind,
                    oldName: oldName,
                    newName: newName,
                    replacements: replacements.sorted { lhs, rhs in
                        (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
                    }
                ))
        }
    }

    private mutating func planStandaloneSymbol(
        _ group: USROccurrenceGroup,
        context: PlanningContext,
        sourceCache: SourceFileCache,
        entries: inout [RenamePlanEntry],
        denied: inout [SafetyDecision],
        reservedNames: inout Set<String>
    ) {
        let decision = analyzer.analyze(
            group: group,
            sourceCache: sourceCache,
            indexedFacts: context.indexedFacts,
            overrideRelatedUSRs: context.indexedFacts.overrideRelatedUSRs,
            tupleTypealiasRelatedUSRs: context.typealiasSyntaxFacts.unsafeTupleRelatedUSRs,
            genericParameterUSRs: context.genericParameterSyntaxFacts.genericParameterUSRs,
            supportedGenericParameterUSRs:
                context.genericParameterSyntaxFacts.supportedGenericParameterUSRs,
            serializationKeyPreservedUSRs: context.serializationKeyPreservedUSRs,
            propertyWrapperSupportedUSRs: context.propertyWrapperSupportedUSRs,
            localBindingOnlyParameterUSRs:
                context.parameterSyntaxFacts.localBindingOnlyCoverageCandidateUSRs
        )
        guard decision.allowed, let oldName = decision.oldName else {
            denied.append(decision)
            return
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
            guard let token = source.identifierToken(line: occurrence.line, utf8Column: occurrence.utf8Column)
            else {
                localReasons.append(
                    "identifier token unavailable at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
                continue
            }
            if SafetyAnalyzer.isSemanticSelfTypeReference(
                occurrence: occurrence,
                token: token,
                symbolKind: group.symbol.kind
            ) {
                continue
            }
            guard token.name == oldName else {
                localReasons.append(
                    "token mismatch at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)")
                continue
            }
            replacements.insert(
                SourceReplacement(
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

        if group.symbol.isKind(.parameter),
            context.parameterSyntaxFacts.localBindingOnlyCoverageCandidateUSRs.contains(group.usr),
            let roles = context.parameterSyntaxFacts.rolesByUSR[group.usr]
        {
            for token in roles.localBindingTokens {
                guard let source = sourceCache.file(for: token.path) else {
                    localReasons.append("source file unavailable for \(token.path)")
                    continue
                }
                guard token.name == oldName,
                    source.text(in: token.byteRange) == oldName
                else {
                    localReasons.append(
                        "compiler syntax token mismatch at \(token.path):\(token.byteRange.lowerBound)"
                    )
                    continue
                }
                guard
                    let location = source.sourceLocation(
                        atByteOffset: token.byteRange.lowerBound
                    )
                else {
                    localReasons.append(
                        "compiler syntax source location unavailable at \(token.path):\(token.byteRange.lowerBound)"
                    )
                    continue
                }
                replacements.insert(
                    SourceReplacement(
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

        guard localReasons.isEmpty, !replacements.isEmpty else {
            denied.append(
                SafetyDecision(
                    usr: group.usr,
                    symbolName: group.symbol.name,
                    kind: group.symbol.kind,
                    allowed: false,
                    oldName: oldName,
                    reasons: localReasons.isEmpty
                        ? ["no source replacements"]
                        : Array(Set(localReasons)).sorted()
                ))
            return
        }

        entries.append(
            RenamePlanEntry(
                usr: group.usr,
                kind: group.symbol.kind,
                oldName: oldName,
                newName: newName,
                replacements: replacements.sorted { lhs, rhs in
                    (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
                }
            ))
    }

    private static func resolveReplacementConflicts(
        context: PlanningContext,
        entries: inout [RenamePlanEntry],
        denied: inout [SafetyDecision]
    ) -> [String] {
        func locationKey(_ replacement: SourceReplacement) -> String {
            "\(replacement.path):\(replacement.byteOffset)"
        }

        let conflictGroups = Dictionary(
            grouping: entries.flatMap(\.replacements),
            by: locationKey
        )
        let conflictKeys = Set(
            conflictGroups.compactMap { key, replacements -> String? in
                let uniqueTargets = Set(replacements.map { "\($0.oldName)->\($0.newName)" })
                return uniqueTargets.count > 1 ? key : nil
            })
        guard !conflictKeys.isEmpty else {
            return []
        }

        let entryHasConflict: (RenamePlanEntry) -> Bool = { entry in
            entry.replacements.contains { conflictKeys.contains(locationKey($0)) }
        }
        let conflictedCoordinatedComponents = Set(
            entries.compactMap { entry in
                entryHasConflict(entry) ? context.coordinatedComponentByUSR[entry.usr]?.key : nil
            })
        let conflictedExternalLabelComponents = Set(
            entries.compactMap { entry in
                entryHasConflict(entry)
                    ? context.externalLabelComponentByParameterUSR[entry.usr]?.key
                    : nil
            })
        let conflictedEnumCaseOwners = Set(
            entries.compactMap { entry in
                entryHasConflict(entry)
                    ? context.enumCaseOwnerComponentByCaseUSR[entry.usr]?.ownerUSR
                    : nil
            })
        let directlyConflictedExplicitCodingKeyPairs = Set(
            entries.compactMap { entry in
                entryHasConflict(entry) ? context.explicitCodingKeyPairByUSR[entry.usr]?.key : nil
            })
        let conflictedExplicitCodingKeyPairs = directlyConflictedExplicitCodingKeyPairs.union(
            context.explicitCodingKeyPlanning.pairTemplates.compactMap { pair in
                conflictedEnumCaseOwners.contains(pair.codingKeysEnumUSR) ? pair.key : nil
            }
        )

        entries.removeAll { entry in
            if let componentKey = context.coordinatedComponentByUSR[entry.usr]?.key,
                conflictedCoordinatedComponents.contains(componentKey)
            {
                return true
            }
            if let componentKey = context.externalLabelComponentByParameterUSR[entry.usr]?.key,
                conflictedExternalLabelComponents.contains(componentKey)
            {
                return true
            }
            if let ownerUSR = context.enumCaseOwnerComponentByCaseUSR[entry.usr]?.ownerUSR,
                conflictedEnumCaseOwners.contains(ownerUSR)
            {
                return true
            }
            if let pairKey = context.explicitCodingKeyPairByUSR[entry.usr]?.key,
                conflictedExplicitCodingKeyPairs.contains(pairKey)
            {
                return true
            }
            return entryHasConflict(entry)
        }

        let conflictReason = "component contains a replacement conflict and was removed atomically"
        for component in context.coordinatedComponents
        where conflictedCoordinatedComponents.contains(component.key) {
            let reason = component.denialReason([conflictReason])
            for group in context.groups where component.memberUSRs.contains(group.usr) {
                denied.append(
                    SafetyDecision(
                        usr: group.usr,
                        symbolName: group.symbol.name,
                        kind: group.symbol.kind,
                        allowed: false,
                        oldName: nil,
                        reasons: [reason]
                    ))
            }
        }
        for component in context.parameterExternalLabelComponentFacts.components
        where conflictedExternalLabelComponents.contains(component.key) {
            denied.append(
                contentsOf: ParameterExternalLabelRenamePlanning.denialDecisions(
                    component: component,
                    groupsByUSR: context.groupsByUSR,
                    reasons: [conflictReason]
                ))
        }
        for component in context.enumCaseSyntaxFacts.components
        where conflictedEnumCaseOwners.contains(component.ownerUSR) {
            denied.append(
                contentsOf: EnumCaseRenamePlanning.denialDecisions(
                    component: component,
                    groupsByUSR: context.groupsByUSR,
                    reasons: [conflictReason]
                ))
        }
        for pair in context.explicitCodingKeyPlanning.pairTemplates
        where conflictedExplicitCodingKeyPairs.contains(pair.key) {
            denied.append(
                contentsOf: ExplicitCodingKeyRenamePlanning.denialDecisions(
                    pair: pair,
                    groupsByUSR: context.groupsByUSR,
                    reasons: [conflictReason]
                ))
        }
        return conflictKeys.sorted()
    }

    private mutating func planParameters(
        context: PlanningContext,
        sourceCache: SourceFileCache,
        entries: inout [RenamePlanEntry],
        denied: inout [SafetyDecision],
        reservedNames: inout Set<String>
    ) {
        let parameterKind = IndexSymbolKind.parameter.rawValue
        let externalLabelPlanning = ParameterExternalLabelRenamePlanning.makeResult(
            facts: context.parameterExternalLabelComponentFacts,
            groupsByUSR: context.groupsByUSR,
            indexedFacts: context.indexedFacts,
            parameterRolesByUSR: context.parameterSyntaxFacts.rolesByUSR,
            callBindingFacts: context.parameterCallArgumentBindingFacts,
            callableReferenceBindingFacts: context.parameterCallableReferenceBindingFacts,
            analyzer: analyzer,
            sourceCache: sourceCache
        )
        let fullyPlannedExternalLabelParameterUSRs = Set(
            externalLabelPlanning.componentTemplates.flatMap(\.namedParameterUSRs)
        )
        let preservedLabelLocalBindingCandidateUSRs = context.namedLocalBindingParameterUSRs
            .subtracting(fullyPlannedExternalLabelParameterUSRs)
        let localBindingPlanning = ParameterLocalBindingRenamePlanning.makeResult(
            candidateUSRs: preservedLabelLocalBindingCandidateUSRs,
            groupsByUSR: context.groupsByUSR,
            indexedFacts: context.indexedFacts,
            parameterRolesByUSR: context.parameterSyntaxFacts.rolesByUSR,
            analyzer: analyzer,
            sourceCache: sourceCache
        )

        for componentTemplate in externalLabelPlanning.componentTemplates {
            guard
                let component = context.parameterExternalLabelComponentFacts.components.first(
                    where: { $0.key == componentTemplate.key }
                )
            else {
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
                        || existing.kind != parameterKind
                    {
                        mappingFailures.insert(
                            "persisted mapping metadata disagrees for \(parameter.usr)"
                        )
                    }
                }
            }
            guard mappingFailures.isEmpty else {
                denied.append(
                    contentsOf: ParameterExternalLabelRenamePlanning.denialDecisions(
                        component: component,
                        groupsByUSR: context.groupsByUSR,
                        reasons: mappingFailures.sorted()
                    ))
                continue
            }

            for ordinalTemplate in componentTemplate.ordinals {
                let newName: String
                if let existingName = existingNamesByOrdinal[ordinalTemplate.ordinal] {
                    newName = existingName
                } else {
                    newName = nextName(for: parameterKind, avoiding: reservedNames)
                    reservedNames.insert(newName)
                }
                for parameter in ordinalTemplate.parameters {
                    if mappingStore.entry(for: parameter.usr) == nil {
                        mappingStore.record(
                            usr: parameter.usr,
                            originalName: parameter.oldName,
                            obfuscatedName: newName,
                            kind: parameterKind
                        )
                    }
                    entries.append(
                        RenamePlanEntry(
                            usr: parameter.usr,
                            kind: parameterKind,
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

        var renamedLocalBindingUSRs: Set<String> = []
        for template in localBindingPlanning.templates {
            guard let group = context.groupsByUSR[template.usr] else {
                continue
            }
            let newName: String
            if let existing = mappingStore.entry(for: template.usr) {
                guard existing.originalName == template.oldName,
                    existing.kind == parameterKind
                else {
                    denied.append(
                        ParameterLocalBindingRenamePlanning.denialDecision(
                            group: group,
                            oldName: template.oldName,
                            reasons: ["persisted mapping metadata disagrees for \(template.usr)"]
                        ))
                    continue
                }
                newName = existing.obfuscatedName
            } else {
                newName = nextName(for: parameterKind, avoiding: reservedNames)
                reservedNames.insert(newName)
                mappingStore.record(
                    usr: template.usr,
                    originalName: template.oldName,
                    obfuscatedName: newName,
                    kind: parameterKind
                )
            }
            entries.append(
                RenamePlanEntry(
                    usr: template.usr,
                    kind: parameterKind,
                    oldName: template.oldName,
                    newName: newName,
                    replacements: template.replacements.map {
                        $0.replacement(newName: newName)
                    }.sorted { lhs, rhs in
                        (lhs.path, lhs.byteOffset, lhs.usr)
                            < (rhs.path, rhs.byteOffset, rhs.usr)
                    }
                ))
            renamedLocalBindingUSRs.insert(template.usr)
        }
        denied.append(
            contentsOf: externalLabelPlanning.denied.filter {
                !renamedLocalBindingUSRs.contains($0.usr)
            })
        denied.append(contentsOf: localBindingPlanning.denied)
    }

    private mutating func planEnumCases(
        context: PlanningContext,
        sourceCache: SourceFileCache,
        entries: inout [RenamePlanEntry],
        denied: inout [SafetyDecision],
        reservedNames: inout Set<String>
    ) {
        let enumCaseKind = IndexSymbolKind.enumConstant.rawValue
        let planning = EnumCaseRenamePlanning.makeResult(
            facts: context.enumCaseSyntaxFacts,
            groupsByUSR: context.groupsByUSR,
            indexedFacts: context.indexedFacts,
            analyzer: analyzer,
            sourceCache: sourceCache,
            handledCaseUSRs: context.explicitCodingKeyPlanning.caseUSRs
        )
        denied.append(contentsOf: planning.denied)

        for componentTemplate in planning.componentTemplates {
            guard
                let component = context.enumCaseSyntaxFacts.components.first(where: {
                    $0.ownerUSR == componentTemplate.ownerUSR
                })
            else {
                continue
            }

            var mappingFailures: Set<String> = []
            var existingNamesByUSR: [String: String] = [:]
            for member in componentTemplate.members {
                guard let existing = mappingStore.entry(for: member.usr) else {
                    continue
                }
                if existing.originalName != member.oldName || existing.kind != enumCaseKind {
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
                denied.append(
                    contentsOf: EnumCaseRenamePlanning.denialDecisions(
                        component: component,
                        groupsByUSR: context.groupsByUSR,
                        reasons: mappingFailures.sorted()
                    ))
                continue
            }

            for member in componentTemplate.members {
                let newName: String
                if let existingName = existingNamesByUSR[member.usr] {
                    newName = existingName
                } else {
                    newName = nextName(for: enumCaseKind, avoiding: reservedNames)
                    reservedNames.insert(newName)
                }
                if mappingStore.entry(for: member.usr) == nil {
                    mappingStore.record(
                        usr: member.usr,
                        originalName: member.oldName,
                        obfuscatedName: newName,
                        kind: enumCaseKind
                    )
                }
                entries.append(
                    RenamePlanEntry(
                        usr: member.usr,
                        kind: enumCaseKind,
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

        for pair in context.explicitCodingKeyPlanning.pairTemplates {
            guard
                let propertyEntry = entries.first(where: {
                    $0.usr == pair.propertyUSR
                })
            else {
                denied.append(
                    contentsOf: ExplicitCodingKeyRenamePlanning.denialDecisions(
                        pair: pair,
                        groupsByUSR: context.groupsByUSR,
                        reasons: ["paired stored property was not eligible for renaming"]
                    ))
                continue
            }

            var mappingFailures: Set<String> = []
            if propertyEntry.kind != IndexSymbolKind.instanceProperty.rawValue
                || propertyEntry.oldName != pair.caseTemplate.oldName
            {
                mappingFailures.insert(
                    "stored property and CodingKeys case do not resolve to one source spelling"
                )
            }
            if let existing = mappingStore.entry(for: pair.caseUSR) {
                if existing.originalName != pair.caseTemplate.oldName
                    || existing.kind != enumCaseKind
                {
                    mappingFailures.insert(
                        "persisted mapping metadata disagrees for \(pair.caseUSR)"
                    )
                } else if existing.obfuscatedName != propertyEntry.newName {
                    mappingFailures.insert(
                        "persisted property and CodingKeys case mappings are inconsistent"
                    )
                }
            }
            guard mappingFailures.isEmpty else {
                entries.removeAll { $0.usr == pair.propertyUSR }
                denied.append(
                    contentsOf: ExplicitCodingKeyRenamePlanning.denialDecisions(
                        pair: pair,
                        groupsByUSR: context.groupsByUSR,
                        reasons: mappingFailures.sorted()
                    ))
                continue
            }

            if mappingStore.entry(for: pair.caseUSR) == nil {
                mappingStore.record(
                    usr: pair.caseUSR,
                    originalName: pair.caseTemplate.oldName,
                    obfuscatedName: propertyEntry.newName,
                    kind: enumCaseKind
                )
            }
            entries.append(
                RenamePlanEntry(
                    usr: pair.caseUSR,
                    kind: enumCaseKind,
                    oldName: pair.caseTemplate.oldName,
                    newName: propertyEntry.newName,
                    replacements: pair.caseTemplate.replacements.map {
                        $0.replacement(newName: propertyEntry.newName)
                    }.sorted { lhs, rhs in
                        (lhs.path, lhs.byteOffset, lhs.usr)
                            < (rhs.path, rhs.byteOffset, rhs.usr)
                    }
                ))
        }
    }

    // MARK: - Support replacements

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
                    derivedGroup.symbol.name.hasSuffix(propertyName)
                else {
                    failed = true
                    break
                }
                let prefix = String(derivedGroup.symbol.name.dropLast(propertyName.count))
                guard !prefix.isEmpty,
                    prefix.allSatisfy({ $0 == "$" || $0 == "_" })
                else {
                    failed = true
                    break
                }

                for occurrence in derivedGroup.occurrences where !occurrence.hasRole(.implicit) {
                    guard let source = sourceCache.file(for: occurrence.path),
                        let byteOffset = source.byteOffset(
                            line: occurrence.line,
                            utf8Column: occurrence.utf8Column
                        )
                    else {
                        failed = true
                        break
                    }
                    let oldName = prefix + propertyName
                    let byteRange = byteOffset..<(byteOffset + oldName.utf8.count)
                    guard source.text(in: byteRange) == oldName else {
                        failed = true
                        break
                    }
                    templates.insert(
                        PropertyWrapperReplacementTemplate(
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
                components.append(
                    PropertyWrapperRenameComponent(
                        propertyUSR: propertyUSR,
                        replacements: templates
                    ))
            }
        }
        return components.sorted { $0.propertyUSR < $1.propertyUSR }
    }

    private static func implicitRawValueSupportReplacements(
        facts: EnumCaseSyntaxFacts,
        entries: [RenamePlanEntry]
    ) -> [SourceReplacement] {
        let entriesByUSR = Dictionary(uniqueKeysWithValues: entries.map { ($0.usr, $0) })
        return facts.components.flatMap { component in
            component.members.compactMap { member -> SourceReplacement? in
                guard entriesByUSR[member.caseUSR] != nil,
                    !member.hasExplicitRawValue,
                    let literal = member.implicitRawValueLiteral,
                    let token = member.declarationToken
                else {
                    return nil
                }
                return SourceReplacement(
                    path: token.path,
                    byteOffset: token.byteRange.upperBound,
                    length: 0,
                    line: 1,
                    utf8Column: 1,
                    oldName: "",
                    newName: " = \(literal)",
                    usr: "implicit-raw-value:\(member.caseUSR)"
                )
            }
        }.sorted { lhs, rhs in
            (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
        }
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
                replacements.insert(
                    SourceReplacement(
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
            guard indexedFacts.symbolsByUSR[ownerUSR]?.isKind(.struct) == true,
                !indexedFacts.explicitCodingKeysOwnerUSRs.contains(ownerUSR),
                !indexedFacts.customSerializationImplementationOwnerUSRs.contains(ownerUSR),
                let qualifiedOwnerUSRs = indexedFacts.qualifiedNominalOwnerUSRs(for: ownerUSR),
                qualifiedOwnerUSRs.allSatisfy({ usr in
                    indexedFacts.symbolsByUSR[usr].flatMap { escapedSwiftIdentifier($0.name) } != nil
                }),
                let ownerGroup = groupsByUSR[ownerUSR]
            else {
                continue
            }

            let propertyUSRs = indexedFacts.directStoredPropertyUSRs(of: ownerUSR).sorted()
            guard !propertyUSRs.isEmpty,
                propertyUSRs.allSatisfy({ usr in
                    groupsByUSR[usr] != nil
                        && indexedFacts.symbolsByUSR[usr].flatMap { escapedSwiftIdentifier($0.name) } != nil
                })
            else {
                continue
            }

            let ownerDeclarations = Dictionary(
                grouping: ownerGroup.occurrences.filter { occurrence in
                    (occurrence.hasRole(.declaration) || occurrence.hasRole(.definition))
                        && !occurrence.hasRole(.implicit)
                        && isPath(occurrence.path, under: obfuscationRoots)
                        && sourceCache.file(for: occurrence.path) != nil
                }
            ) { occurrence in
                "\(SourcePathNormalizer.canonicalPath(occurrence.path)):\(occurrence.line):\(occurrence.utf8Column)"
            }.values.compactMap(\.first)
            guard ownerDeclarations.count == 1,
                let ownerDeclaration = ownerDeclarations.first
            else {
                continue
            }

            components.append(
                CodingKeyPreservationComponent(
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
                    let caseName = escapedSwiftIdentifier(entriesByUSR[usr]?.newName ?? originalName)
                else {
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
                "}",
            ].joined(separator: "\n")
            chunksByPath[component.path, default: []].append(
                (
                    ownerUSR: component.ownerUSR,
                    line: component.declarationLine,
                    text: text
                ))
        }

        return chunksByPath.compactMap { path, chunks -> SourceReplacement? in
            guard let source = sourceCache.file(for: path),
                let first = chunks.sorted(by: {
                    ($0.line, $0.ownerUSR) < ($1.line, $1.ownerUSR)
                }).first
            else {
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
            !name.contains("\r")
        else {
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

    // MARK: - Coordinated components

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
                return
                    "protocol members require relation-aware witness renaming: coordinated component denied atomically (\(visible)\(suffix))"
            case .overrideChain:
                return
                    "override relations require coordinated renaming: coordinated override/base component denied atomically (\(visible)\(suffix))"
            }
        }
    }

    private static func coordinatedRenameComponents(
        indexedFacts: IndexedSemanticFacts,
        groupsByUSR: [String: USROccurrenceGroup]
    ) -> [CoordinatedRenameComponent] {
        let localRequirementUSRs = Set(
            indexedFacts.protocolRequirementUSRs.filter { usr in
                groupsByUSR[usr].map { !IndexSymbolName.isSyntheticAccessor($0.symbol.name) } == true
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
                pending.append(
                    contentsOf: (indexedFacts.overrideRelationNeighbors[usr] ?? []).filter {
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
                if IndexUSR.isObjectiveCCompatible(usr)
                    || memberGroup.symbol.language.lowercased().contains("objective")
                {
                    structuralReasons.append("Objective-C requirement or witness is part of the component: \(usr)")
                }
                if !indexedFacts.selectedDeclarationUSRs.contains(memberGroup.usr) {
                    structuralReasons.append("related USR has no declaration inside selected source roots: \(usr)")
                }
            }

            let protocolRequirementUSRs = members.intersection(localRequirementUSRs)
            components.append(
                CoordinatedRenameComponent(
                    key: members.sorted().first ?? seedUSR,
                    memberUSRs: members,
                    protocolRequirementUSRs: protocolRequirementUSRs,
                    structuralReasons: Array(Set(structuralReasons)).sorted(),
                    kind: protocolRequirementUSRs.isEmpty ? .overrideChain : .protocolWitness
                ))
        }

        return components.sorted { $0.key < $1.key }
    }

    private static func coalescedDenials(
        _ decisions: [SafetyDecision]
    ) -> [SafetyDecision] {
        Dictionary(grouping: decisions, by: \.usr).values.compactMap { duplicates in
            guard
                let first = duplicates.sorted(by: {
                    ($0.symbolName, $0.kind, $0.oldName ?? "")
                        < ($1.symbolName, $1.kind, $1.oldName ?? "")
                }).first
            else {
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
        guard occurrence.hasRole(.implicit) else {
            return false
        }
        guard IndexRole.lexicalRawValues.isDisjoint(with: occurrence.roles) else {
            return false
        }
        return occurrence.relations.contains { relation in
            (relation.hasRole(.overrideOf) || relation.hasRole(.baseOf))
                && componentUSRs.contains(relation.usr)
        }
    }

    // MARK: - Name generation

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
        let lowerCamelCaseKinds = IndexSymbolKind.rawValues(
            .function,
            .instanceMethod,
            .staticMethod,
            .classMethod,
            .instanceProperty,
            .staticProperty,
            .classProperty,
            .variable,
            .parameter,
            .enumConstant
        )
        guard lowerCamelCaseKinds.contains(symbolKind),
            let letterIndex = name.firstIndex(where: \.isLetter)
        else {
            return name
        }

        var result = name
        result.replaceSubrange(letterIndex...letterIndex, with: String(name[letterIndex]).lowercased())
        return result
    }

}
