import Foundation

public struct RenamePlanner {
    public var analyzer: RenameEligibilityAnalyzer
    public var generator: ObfuscatedNameGenerator
    public var mappingStore: RenameMappingStore

    public init(
        analyzer: RenameEligibilityAnalyzer,
        generator: ObfuscatedNameGenerator = ObfuscatedNameGenerator(),
        mappingStore: RenameMappingStore = RenameMappingStore()
    ) {
        self.analyzer = analyzer
        self.generator = generator
        self.mappingStore = mappingStore
    }

    // MARK: - Planner context

    private struct Context {
        let occurrenceGroups: [IndexSnapshot.OccurrenceGroup]
        let groupsByUSR: [String: IndexSnapshot.OccurrenceGroup]
        let semanticIndex: SemanticIndex
        let enumCaseSemantics: EnumCaseSemantics.Index
        let rawValues: EnumRawValue.Index
        let enumCaseSyntax: EnumCaseSyntax.Index
        let enumCaseUSRs: Set<String>
        let enumCaseOwnerByCaseUSR: [String: EnumCaseSyntax.Owner]
        let parameterSyntax: ParameterSyntax.Index
        let genericParameters: GenericParameterAnalysis.Index
        let typeAliasSyntax: TypeAliasSyntax.Index
        let callSiteSyntax: CallSiteSyntax.Index
        let callArgumentBindings: CallArgumentBinding.Index
        let callableReferenceSyntax: CallableReferenceSyntax.Index
        let callableReferenceBindings: CallableReferenceBinding.Index
        let externalLabels: ExternalLabel.Analysis
        let externalLabelParameterUSRs: Set<String>
        let namedLocalBindingParameterUSRs: Set<String>
        let externalLabelFamilyByParameterUSR: [String: ExternalLabel.Family]
        let codingKeyPreservations: [CodingKeyPreservation]
        let propertyWrapperRenames: [PropertyWrapperRename]
        let propertyWrapperSupportedUSRs: Set<String>
        let coordinatedFamilies: [CoordinatedRenameFamily]
        let coordinatedFamilyByUSR: [String: CoordinatedRenameFamily]
        let codingKeyPlan: CodingKeyRename.Plan
        let explicitCodingKeyPairByUSR: [String: CodingKeyRename.Pair]
        let serializationKeyPreservedUSRs: Set<String>

        init(
            snapshot: IndexSnapshot,
            sourceCache: SourceFileCache,
            analyzer: RenameEligibilityAnalyzer
        ) {
            occurrenceGroups = snapshot.occurrenceGroups
            groupsByUSR = Dictionary(
                uniqueKeysWithValues: occurrenceGroups.map { ($0.usr, $0) }
            )
            semanticIndex = SemanticIndex(
                snapshot: snapshot,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            enumCaseSemantics = EnumCaseSemantics.Index(
                snapshot: snapshot,
                semanticIndex: semanticIndex,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            rawValues = EnumRawValue.Index(
                snapshot: snapshot,
                semantics: enumCaseSemantics,
                semanticIndex: semanticIndex,
                sourceCache: sourceCache
            )
            enumCaseSyntax = EnumCaseSyntax.Index(
                snapshot: snapshot,
                semantics: enumCaseSemantics,
                rawValues: rawValues,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            enumCaseUSRs = Set(
                enumCaseSyntax.owners.flatMap { $0.members.map(\.caseUSR) }
            )
            enumCaseOwnerByCaseUSR = Dictionary(
                uniqueKeysWithValues: enumCaseSyntax.owners.flatMap { owner in
                    owner.members.map { ($0.caseUSR, owner) }
                }
            )

            parameterSyntax = ParameterSyntax.Index(
                snapshot: snapshot,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            genericParameters = GenericParameterAnalysis.Index(
                snapshot: snapshot,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            typeAliasSyntax = TypeAliasSyntax.Index(
                snapshot: snapshot,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            callSiteSyntax = CallSiteSyntax.Index(
                signatures: semanticIndex.callableSignatures,
                sourceCache: sourceCache
            )
            callArgumentBindings = CallArgumentBinding.Index(
                signatures: semanticIndex.callableSignatures,
                parametersByUSR: parameterSyntax.parametersByUSR,
                callSiteSyntax: callSiteSyntax
            )
            callableReferenceSyntax = CallableReferenceSyntax.Index(
                signatures: semanticIndex.callableSignatures,
                sourceCache: sourceCache
            )
            callableReferenceBindings = CallableReferenceBinding.Index(
                signatures: semanticIndex.callableSignatures,
                parametersByUSR: parameterSyntax.parametersByUSR,
                syntax: callableReferenceSyntax
            )
            let eligibleEnumCaseUSRs = Set(
                enumCaseSyntax.owners.flatMap {
                    $0.preliminaryEligibleMembers.map(\.caseUSR)
                }
            )
            externalLabels = ExternalLabel.Analysis(
                semanticIndex: semanticIndex,
                parametersByUSR: parameterSyntax.parametersByUSR,
                callBindings: callArgumentBindings,
                referenceBindings: callableReferenceBindings,
                eligibleEnumCaseUSRs: eligibleEnumCaseUSRs
            )
            externalLabelParameterUSRs = Set(
                externalLabels.families.flatMap(\.labeledParameterUSRs)
            )
            let parametersForLocalBindings = parameterSyntax
            namedLocalBindingParameterUSRs = Set(
                parametersForLocalBindings.parametersByUSR.values.compactMap {
                    role -> String? in
                    guard
                        parametersForLocalBindings
                            .localBindingCandidateUSRs
                            .contains(role.parameterUSR),
                        case .named = role.externalLabel
                    else {
                        return nil
                    }
                    return role.parameterUSR
                }
            )
            externalLabelFamilyByParameterUSR = Dictionary(
                uniqueKeysWithValues: externalLabels.families.flatMap {
                    family in
                    family.labeledParameterUSRs.map { ($0, family) }
                }
            )

            codingKeyPreservations = RenamePlanner.codingKeyPreservations(
                semanticIndex: semanticIndex,
                groupsByUSR: groupsByUSR,
                sourceCache: sourceCache,
                obfuscationRoots: analyzer.obfuscationRoots
            )
            propertyWrapperRenames = RenamePlanner.propertyWrapperRenames(
                semanticIndex: semanticIndex,
                groupsByUSR: groupsByUSR,
                sourceCache: sourceCache
            )
            propertyWrapperSupportedUSRs = Set(propertyWrapperRenames.map(\.propertyUSR))
            coordinatedFamilies = RenamePlanner.coordinatedRenameFamilies(
                semanticIndex: semanticIndex,
                groupsByUSR: groupsByUSR
            )
            let familiesForLookup = coordinatedFamilies
            let occurrenceGroupsByUSR = groupsByUSR
            coordinatedFamilyByUSR = Dictionary(
                uniqueKeysWithValues: familiesForLookup.flatMap { family in
                    family.memberUSRs.compactMap { usr in
                        occurrenceGroupsByUSR[usr] == nil ? nil : (usr, family)
                    }
                }
            )
            codingKeyPlan = CodingKeyRename.Planner.makePlan(
                syntax: enumCaseSyntax,
                semantics: enumCaseSemantics,
                semanticIndex: semanticIndex,
                groupsByUSR: groupsByUSR,
                analyzer: analyzer,
                sourceCache: sourceCache,
                excludedPropertyUSRs: Set(coordinatedFamilyByUSR.keys)
            )
            explicitCodingKeyPairByUSR = Dictionary(
                codingKeyPlan.pairs.flatMap { pair in
                    [(pair.propertyUSR, pair), (pair.caseUSR, pair)]
                },
                uniquingKeysWith: { first, _ in first }
            )

            let serializationSemantics = semanticIndex
            let fullyManualSerializationOwnerUSRs = Set(
                serializationSemantics.serializationSensitiveOwnerUSRs.filter { ownerUSR in
                    (!serializationSemantics.decodingSensitiveOwnerUSRs.contains(ownerUSR)
                        || serializationSemantics.customDecodingImplementationOwnerUSRs
                            .contains(ownerUSR))
                        && (!serializationSemantics.encodingSensitiveOwnerUSRs.contains(ownerUSR)
                            || serializationSemantics.customEncodingImplementationOwnerUSRs
                                .contains(ownerUSR))
                }
            )
            let manualSerializationPropertyUSRs = Set(
                fullyManualSerializationOwnerUSRs.flatMap {
                    serializationSemantics.directStoredPropertyUSRs(of: $0)
                }
            )
            serializationKeyPreservedUSRs = Set(
                codingKeyPreservations.flatMap(\.propertyUSRs)
            ).union(codingKeyPlan.propertyUSRs)
                .union(manualSerializationPropertyUSRs)
        }
    }

    // MARK: - Plan construction

    public mutating func makePlan(snapshot: IndexSnapshot, sourceCache: SourceFileCache)
        -> RenamePlan
    {
        let context = Context(
            snapshot: snapshot,
            sourceCache: sourceCache,
            analyzer: analyzer
        )
        var rejections: [RenameEligibility] = []
        var renames: [RenamePlan.Entry] = []
        var reservedNames = Set(snapshot.symbols.map(\.name)).filter(isPlainSwiftIdentifier)
        reservedNames.formUnion(mappingStore.allRenames().map(\.obfuscatedName))

        planOrdinarySymbols(
            context: context,
            sourceCache: sourceCache,
            renames: &renames,
            rejections: &rejections,
            reservedNames: &reservedNames
        )

        planEnumCases(
            context: context,
            sourceCache: sourceCache,
            renames: &renames,
            rejections: &rejections,
            reservedNames: &reservedNames
        )

        planParameters(
            context: context,
            sourceCache: sourceCache,
            renames: &renames,
            rejections: &rejections,
            reservedNames: &reservedNames
        )

        let editConflicts = Self.resolveEditConflicts(
            context: context,
            renames: &renames,
            rejections: &rejections
        )

        // A declaration can participate in more than one rejection layer.
        // For example, an enum case that witnesses a protocol requirement is
        // rejected both by its enum owner and by the coordinated
        // protocol graph. Reports and parameter outcome summaries require one
        // deterministic decision per USR, so preserve every reason while
        // coalescing the duplicate records before constructing those summaries.
        rejections = Self.coalescedRejections(rejections)

        let preservationEdits =
            Self.codingKeySupportEdits(
                preservations: context.codingKeyPreservations,
                renames: renames,
                semanticIndex: context.semanticIndex,
                sourceCache: sourceCache
            )
            + Self.propertyWrapperSupportEdits(
                propertyRenames: context.propertyWrapperRenames,
                renames: renames
            )
            + Self.implicitRawValueSupportEdits(
                syntax: context.enumCaseSyntax,
                renames: renames
            )

        return RenamePlan(
            renames: renames.sorted { ($0.oldName, $0.usr) < ($1.oldName, $1.usr) },
            rejections: rejections.sorted { ($0.symbolName, $0.usr) < ($1.symbolName, $1.usr) },
            editConflicts: editConflicts,
            preservationEdits: preservationEdits,
            callableReport: context.semanticIndex.callableReport,
            parameterSyntaxReport: context.parameterSyntax.report,
            callSiteSyntaxReport: context.callSiteSyntax.report,
            callArgumentBindingReport: context.callArgumentBindings.report,
            callableReferenceSyntaxReport: context.callableReferenceSyntax.report,
            callableReferenceBindingReport:
                context.callableReferenceBindings.report,
            externalLabelReport: context.externalLabels.report,
            externalLabelRenameReport: ExternalLabel.RenameReport(
                families: context.externalLabels.families,
                renames: renames,
                rejections: rejections
            ),
            localBindingRenameReport: LocalBindingRename.Report(
                candidateUSRs: context.parameterSyntax.localBindingCandidateUSRs,
                renames: renames,
                rejections: rejections,
                groupsByUSR: context.groupsByUSR
            ),
            enumCaseSemanticsReport: context.enumCaseSemantics.report,
            enumRawValueReport: context.rawValues.report,
            enumCaseSyntaxReport: context.enumCaseSyntax.report,
            genericParameterReport: context.genericParameters.report,
            typeAliasSyntaxReport: context.typeAliasSyntax.report
        )
    }

    private mutating func planOrdinarySymbols(
        context: Context,
        sourceCache: SourceFileCache,
        renames: inout [RenamePlan.Entry],
        rejections: inout [RenameEligibility],
        reservedNames: inout Set<String>
    ) {
        var processedFamilyKeys: Set<String> = []

        for group in context.occurrenceGroups {
            guard !context.externalLabelParameterUSRs.contains(group.usr),
                !context.namedLocalBindingParameterUSRs.contains(group.usr),
                !context.enumCaseUSRs.contains(group.usr)
            else {
                continue
            }

            if let family = context.coordinatedFamilyByUSR[group.usr] {
                guard processedFamilyKeys.insert(family.key).inserted else {
                    continue
                }
                planCoordinatedFamily(
                    family,
                    context: context,
                    sourceCache: sourceCache,
                    renames: &renames,
                    rejections: &rejections,
                    reservedNames: &reservedNames
                )
            } else {
                planStandaloneSymbol(
                    group,
                    context: context,
                    sourceCache: sourceCache,
                    renames: &renames,
                    rejections: &rejections,
                    reservedNames: &reservedNames
                )
            }
        }
    }

    private mutating func planCoordinatedFamily(
        _ family: CoordinatedRenameFamily,
        context: Context,
        sourceCache: SourceFileCache,
        renames: inout [RenamePlan.Entry],
        rejections: inout [RenameEligibility],
        reservedNames: inout Set<String>
    ) {
        let familyGroups = family.memberUSRs.compactMap { context.groupsByUSR[$0] }.sorted {
            lhs, rhs in
            (lhs.symbol.name, lhs.usr) < (rhs.symbol.name, rhs.usr)
        }
        let coordinationEnabled = family.structuralReasons.isEmpty
        let decisions = familyGroups.map { group in
            analyzer.analyze(
                group: group,
                sourceCache: sourceCache,
                semanticIndex: context.semanticIndex,
                overrideRelatedUSRs: context.semanticIndex.overrideRelatedUSRs,
                tupleTypeAliasRelatedUSRs: context.typeAliasSyntax.unsafeTupleRelatedUSRs,
                coordinatedRelatedUSRs: coordinationEnabled ? family.memberUSRs : [],
                coordinatedProtocolRequirementUSRs: coordinationEnabled
                    ? family.protocolRequirementUSRs
                    : [],
                genericParameterUSRs: context.genericParameters.genericParameterUSRs,
                supportedGenericParameterUSRs:
                    context.genericParameters.supportedGenericParameterUSRs,
                serializationKeyPreservedUSRs: context.serializationKeyPreservedUSRs,
                propertyWrapperSupportedUSRs: context.propertyWrapperSupportedUSRs,
                localBindingOnlyParameterUSRs:
                    context.parameterSyntax.localBindingCandidateUSRs
            )
        }

        var failureSummaries = family.structuralReasons
        for decision in decisions where !decision.isEligible {
            failureSummaries.append("\(decision.usr): \(decision.reasons.joined(separator: "; "))")
        }

        let oldNames = Set(decisions.compactMap(\.originalName))
        if decisions.allSatisfy(\.isEligible), oldNames.count != 1 {
            failureSummaries.append("component occurrences do not resolve to one source identifier")
        }

        let caseConventions = Set(
            familyGroups.map {
                Self.nameWithConventionalInitialCase("Oa", for: $0.symbol.kind)
            })
        if caseConventions.count != 1 {
            failureSummaries.append("component symbol kinds require incompatible identifier casing")
        }

        let existingNames = Set(
            familyGroups.compactMap {
                mappingStore.rename(for: $0.usr)?.obfuscatedName
            })
        if existingNames.count > 1 {
            failureSummaries.append("component USRs already have inconsistent persisted mappings")
        }

        var editsByUSR: [String: Set<SourcePatcher.Edit>] = [:]
        if failureSummaries.isEmpty, let oldName = oldNames.first {
            for group in familyGroups {
                var edits: Set<SourcePatcher.Edit> = []
                var localReasons: Set<String> = []
                for occurrence in group.occurrences {
                    if Self.isSemanticOnlyCoordinatedOccurrence(
                        occurrence,
                        familyUSRs: family.memberUSRs
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
                    if RenameEligibilityAnalyzer.isSemanticSelfTypeReference(
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
                    edits.insert(
                        SourcePatcher.Edit(
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
                } else if edits.isEmpty {
                    failureSummaries.append("\(group.usr): no source replacements")
                } else {
                    editsByUSR[group.usr] = edits
                }
            }
        }

        guard failureSummaries.isEmpty, let oldName = oldNames.first else {
            let familyReason = family.rejectionReason(failureSummaries)
            rejections.append(
                contentsOf: zip(familyGroups, decisions).map { group, decision in
                    var reasons = decision.isEligible ? [] : decision.reasons
                    reasons.append(familyReason)
                    return RenameEligibility(
                        usr: group.usr,
                        symbolName: group.symbol.name,
                        symbolKind: group.symbol.kind,
                        isEligible: false,
                        originalName: decision.originalName,
                        reasons: Array(Set(reasons)).sorted()
                    )
                })
            return
        }

        let newName: String
        if let existingName = existingNames.first {
            newName = existingName
        } else {
            newName = nextName(for: familyGroups[0].symbol.kind, avoiding: reservedNames)
            reservedNames.insert(newName)
        }

        for group in familyGroups {
            if mappingStore.rename(for: group.usr) == nil {
                mappingStore.record(
                    usr: group.usr,
                    originalName: oldName,
                    obfuscatedName: newName,
                    kind: group.symbol.kind
                )
            }
            let edits = (editsByUSR[group.usr] ?? []).map { edit in
                SourcePatcher.Edit(
                    path: edit.path,
                    byteOffset: edit.byteOffset,
                    length: edit.length,
                    line: edit.line,
                    utf8Column: edit.utf8Column,
                    oldName: edit.oldName,
                    newName: newName,
                    usr: edit.usr
                )
            }
            renames.append(
                RenamePlan.Entry(
                    usr: group.usr,
                    kind: group.symbol.kind,
                    oldName: oldName,
                    newName: newName,
                    edits: edits.sorted { lhs, rhs in
                        (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
                    }
                ))
        }
    }

    private mutating func planStandaloneSymbol(
        _ group: IndexSnapshot.OccurrenceGroup,
        context: Context,
        sourceCache: SourceFileCache,
        renames: inout [RenamePlan.Entry],
        rejections: inout [RenameEligibility],
        reservedNames: inout Set<String>
    ) {
        let decision = analyzer.analyze(
            group: group,
            sourceCache: sourceCache,
            semanticIndex: context.semanticIndex,
            overrideRelatedUSRs: context.semanticIndex.overrideRelatedUSRs,
            tupleTypeAliasRelatedUSRs: context.typeAliasSyntax.unsafeTupleRelatedUSRs,
            genericParameterUSRs: context.genericParameters.genericParameterUSRs,
            supportedGenericParameterUSRs:
                context.genericParameters.supportedGenericParameterUSRs,
            serializationKeyPreservedUSRs: context.serializationKeyPreservedUSRs,
            propertyWrapperSupportedUSRs: context.propertyWrapperSupportedUSRs,
            localBindingOnlyParameterUSRs:
                context.parameterSyntax.localBindingCandidateUSRs
        )
        guard decision.isEligible, let oldName = decision.originalName else {
            rejections.append(decision)
            return
        }

        let newName: String
        if let existing = mappingStore.rename(for: group.usr) {
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

        var edits: Set<SourcePatcher.Edit> = []
        var localReasons: [String] = []
        for occurrence in group.occurrences {
            guard let source = sourceCache.file(for: occurrence.path) else {
                localReasons.append("source file unavailable for \(occurrence.path)")
                continue
            }
            guard
                let token = source.identifierToken(
                    line: occurrence.line, utf8Column: occurrence.utf8Column)
            else {
                localReasons.append(
                    "identifier token unavailable at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
                continue
            }
            if RenameEligibilityAnalyzer.isSemanticSelfTypeReference(
                occurrence: occurrence,
                token: token,
                symbolKind: group.symbol.kind
            ) {
                continue
            }
            guard token.name == oldName else {
                localReasons.append(
                    "token mismatch at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
                continue
            }
            edits.insert(
                SourcePatcher.Edit(
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
            context.parameterSyntax.localBindingCandidateUSRs.contains(group.usr),
            let roles = context.parameterSyntax.parametersByUSR[group.usr]
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
                edits.insert(
                    SourcePatcher.Edit(
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

        guard localReasons.isEmpty, !edits.isEmpty else {
            rejections.append(
                RenameEligibility(
                    usr: group.usr,
                    symbolName: group.symbol.name,
                    symbolKind: group.symbol.kind,
                    isEligible: false,
                    originalName: oldName,
                    reasons: localReasons.isEmpty
                        ? ["no source replacements"]
                        : Array(Set(localReasons)).sorted()
                ))
            return
        }

        renames.append(
            RenamePlan.Entry(
                usr: group.usr,
                kind: group.symbol.kind,
                oldName: oldName,
                newName: newName,
                edits: edits.sorted { lhs, rhs in
                    (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
                }
            ))
    }

    private static func resolveEditConflicts(
        context: Context,
        renames: inout [RenamePlan.Entry],
        rejections: inout [RenameEligibility]
    ) -> [String] {
        func locationKey(_ edit: SourcePatcher.Edit) -> String {
            "\(edit.path):\(edit.byteOffset)"
        }

        let conflictGroups = Dictionary(
            grouping: renames.flatMap(\.edits),
            by: locationKey
        )
        let conflictKeys = Set(
            conflictGroups.compactMap { key, edits -> String? in
                let uniqueTargets = Set(edits.map { "\($0.oldName)->\($0.newName)" })
                return uniqueTargets.count > 1 ? key : nil
            })
        guard !conflictKeys.isEmpty else {
            return []
        }

        let entryHasConflict: (RenamePlan.Entry) -> Bool = { entry in
            entry.edits.contains { conflictKeys.contains(locationKey($0)) }
        }
        let conflictedCoordinatedFamilies = Set(
            renames.compactMap { entry in
                entryHasConflict(entry) ? context.coordinatedFamilyByUSR[entry.usr]?.key : nil
            })
        let conflictedExternalLabelFamilies = Set(
            renames.compactMap { entry in
                entryHasConflict(entry)
                    ? context.externalLabelFamilyByParameterUSR[entry.usr]?.key
                    : nil
            })
        let conflictedEnumCaseOwners = Set(
            renames.compactMap { entry in
                entryHasConflict(entry)
                    ? context.enumCaseOwnerByCaseUSR[entry.usr]?.ownerUSR
                    : nil
            })
        let directlyConflictedExplicitCodingKeyPairs = Set(
            renames.compactMap { entry in
                entryHasConflict(entry) ? context.explicitCodingKeyPairByUSR[entry.usr]?.key : nil
            })
        let conflictedExplicitCodingKeyPairs = directlyConflictedExplicitCodingKeyPairs.union(
            context.codingKeyPlan.pairs.compactMap { pair in
                conflictedEnumCaseOwners.contains(pair.codingKeysEnumUSR) ? pair.key : nil
            }
        )

        renames.removeAll { entry in
            if let familyKey = context.coordinatedFamilyByUSR[entry.usr]?.key,
                conflictedCoordinatedFamilies.contains(familyKey)
            {
                return true
            }
            if let familyKey = context.externalLabelFamilyByParameterUSR[entry.usr]?.key,
                conflictedExternalLabelFamilies.contains(familyKey)
            {
                return true
            }
            if let ownerUSR = context.enumCaseOwnerByCaseUSR[entry.usr]?.ownerUSR,
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
        for family in context.coordinatedFamilies
        where conflictedCoordinatedFamilies.contains(family.key) {
            let reason = family.rejectionReason([conflictReason])
            for group in context.occurrenceGroups where family.memberUSRs.contains(group.usr) {
                rejections.append(
                    RenameEligibility(
                        usr: group.usr,
                        symbolName: group.symbol.name,
                        symbolKind: group.symbol.kind,
                        isEligible: false,
                        originalName: nil,
                        reasons: [reason]
                    ))
            }
        }
        for family in context.externalLabels.families
        where conflictedExternalLabelFamilies.contains(family.key) {
            rejections.append(
                contentsOf: ExternalLabel.Planner.makeRejections(
                    family: family,
                    groupsByUSR: context.groupsByUSR,
                    reasons: [conflictReason]
                ))
        }
        for owner in context.enumCaseSyntax.owners
        where conflictedEnumCaseOwners.contains(owner.ownerUSR) {
            rejections.append(
                contentsOf: EnumCaseRename.Planner.makeRejections(
                    owner: owner,
                    groupsByUSR: context.groupsByUSR,
                    reasons: [conflictReason]
                ))
        }
        for pair in context.codingKeyPlan.pairs
        where conflictedExplicitCodingKeyPairs.contains(pair.key) {
            rejections.append(
                contentsOf: CodingKeyRename.Planner.makeRejections(
                    pair: pair,
                    groupsByUSR: context.groupsByUSR,
                    reasons: [conflictReason]
                ))
        }
        return conflictKeys.sorted()
    }

    private mutating func planParameters(
        context: Context,
        sourceCache: SourceFileCache,
        renames: inout [RenamePlan.Entry],
        rejections: inout [RenameEligibility],
        reservedNames: inout Set<String>
    ) {
        let parameterKind = IndexSymbolKind.parameter.rawValue
        let externalLabelPlan = ExternalLabel.Planner.makePlan(
            analysis: context.externalLabels,
            groupsByUSR: context.groupsByUSR,
            semanticIndex: context.semanticIndex,
            parametersByUSR: context.parameterSyntax.parametersByUSR,
            callBindings: context.callArgumentBindings,
            referenceBindings: context.callableReferenceBindings,
            analyzer: analyzer,
            sourceCache: sourceCache
        )
        let fullyPlannedExternalLabelParameterUSRs = Set(
            externalLabelPlan.families.flatMap(\.labeledParameterUSRs)
        )
        let preservedLabelLocalBindingCandidateUSRs = context.namedLocalBindingParameterUSRs
            .subtracting(fullyPlannedExternalLabelParameterUSRs)
        let localBindingPlan = LocalBindingRename.Planner.makePlan(
            candidateUSRs: preservedLabelLocalBindingCandidateUSRs,
            groupsByUSR: context.groupsByUSR,
            semanticIndex: context.semanticIndex,
            parametersByUSR: context.parameterSyntax.parametersByUSR,
            analyzer: analyzer,
            sourceCache: sourceCache
        )

        for familyRename in externalLabelPlan.families {
            guard
                let family = context.externalLabels.families.first(
                    where: { $0.key == familyRename.key }
                )
            else {
                continue
            }
            var mappingFailures: Set<String> = []
            var existingNamesByOrdinal: [Int: String] = [:]
            for slotRename in familyRename.slots {
                let existingEntries = slotRename.parameters.compactMap {
                    mappingStore.rename(for: $0.usr)
                }
                let existingNames = Set(existingEntries.map(\.obfuscatedName))
                if existingNames.count > 1 {
                    mappingFailures.insert(
                        "ordinal \(slotRename.ordinal) has inconsistent persisted mappings"
                    )
                } else if let existingName = existingNames.first {
                    existingNamesByOrdinal[slotRename.ordinal] = existingName
                }
                for parameter in slotRename.parameters {
                    guard let existing = mappingStore.rename(for: parameter.usr) else {
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
                rejections.append(
                    contentsOf: ExternalLabel.Planner.makeRejections(
                        family: family,
                        groupsByUSR: context.groupsByUSR,
                        reasons: mappingFailures.sorted()
                    ))
                continue
            }

            for slotRename in familyRename.slots {
                let newName: String
                if let existingName = existingNamesByOrdinal[slotRename.ordinal] {
                    newName = existingName
                } else {
                    newName = nextName(for: parameterKind, avoiding: reservedNames)
                    reservedNames.insert(newName)
                }
                for parameter in slotRename.parameters {
                    if mappingStore.rename(for: parameter.usr) == nil {
                        mappingStore.record(
                            usr: parameter.usr,
                            originalName: parameter.oldName,
                            obfuscatedName: newName,
                            kind: parameterKind
                        )
                    }
                    renames.append(
                        RenamePlan.Entry(
                            usr: parameter.usr,
                            kind: parameterKind,
                            oldName: parameter.oldName,
                            newName: newName,
                            edits: parameter.editTemplates.map {
                                $0.makeEdit(newName: newName)
                            }.sorted { lhs, rhs in
                                (lhs.path, lhs.byteOffset, lhs.usr)
                                    < (rhs.path, rhs.byteOffset, rhs.usr)
                            }
                        ))
                }
            }
        }

        var renamedLocalBindingUSRs: Set<String> = []
        for rename in localBindingPlan.renames {
            guard let group = context.groupsByUSR[rename.usr] else {
                continue
            }
            let newName: String
            if let existing = mappingStore.rename(for: rename.usr) {
                guard existing.originalName == rename.oldName,
                    existing.kind == parameterKind
                else {
                    rejections.append(
                        LocalBindingRename.Planner.makeRejection(
                            group: group,
                            oldName: rename.oldName,
                            reasons: ["persisted mapping metadata disagrees for \(rename.usr)"]
                        ))
                    continue
                }
                newName = existing.obfuscatedName
            } else {
                newName = nextName(for: parameterKind, avoiding: reservedNames)
                reservedNames.insert(newName)
                mappingStore.record(
                    usr: rename.usr,
                    originalName: rename.oldName,
                    obfuscatedName: newName,
                    kind: parameterKind
                )
            }
            renames.append(
                RenamePlan.Entry(
                    usr: rename.usr,
                    kind: parameterKind,
                    oldName: rename.oldName,
                    newName: newName,
                    edits: rename.editTemplates.map {
                        $0.makeEdit(newName: newName)
                    }.sorted { lhs, rhs in
                        (lhs.path, lhs.byteOffset, lhs.usr)
                            < (rhs.path, rhs.byteOffset, rhs.usr)
                    }
                ))
            renamedLocalBindingUSRs.insert(rename.usr)
        }
        rejections.append(
            contentsOf: externalLabelPlan.rejections.filter {
                !renamedLocalBindingUSRs.contains($0.usr)
            })
        rejections.append(contentsOf: localBindingPlan.rejections)
    }

    private mutating func planEnumCases(
        context: Context,
        sourceCache: SourceFileCache,
        renames: inout [RenamePlan.Entry],
        rejections: inout [RenameEligibility],
        reservedNames: inout Set<String>
    ) {
        let enumCaseKind = IndexSymbolKind.enumConstant.rawValue
        let plan = EnumCaseRename.Planner.makePlan(
            syntax: context.enumCaseSyntax,
            groupsByUSR: context.groupsByUSR,
            semanticIndex: context.semanticIndex,
            analyzer: analyzer,
            sourceCache: sourceCache,
            handledCaseUSRs: context.codingKeyPlan.caseUSRs
        )
        rejections.append(contentsOf: plan.rejections)

        for ownerRename in plan.owners {
            guard
                let owner = context.enumCaseSyntax.owners.first(where: {
                    $0.ownerUSR == ownerRename.ownerUSR
                })
            else {
                continue
            }

            var mappingFailures: Set<String> = []
            var existingNamesByUSR: [String: String] = [:]
            for member in ownerRename.members {
                guard let existing = mappingStore.rename(for: member.usr) else {
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
                rejections.append(
                    contentsOf: EnumCaseRename.Planner.makeRejections(
                        owner: owner,
                        groupsByUSR: context.groupsByUSR,
                        reasons: mappingFailures.sorted()
                    ))
                continue
            }

            for member in ownerRename.members {
                let newName: String
                if let existingName = existingNamesByUSR[member.usr] {
                    newName = existingName
                } else {
                    newName = nextName(for: enumCaseKind, avoiding: reservedNames)
                    reservedNames.insert(newName)
                }
                if mappingStore.rename(for: member.usr) == nil {
                    mappingStore.record(
                        usr: member.usr,
                        originalName: member.oldName,
                        obfuscatedName: newName,
                        kind: enumCaseKind
                    )
                }
                renames.append(
                    RenamePlan.Entry(
                        usr: member.usr,
                        kind: enumCaseKind,
                        oldName: member.oldName,
                        newName: newName,
                        edits: member.editTemplates.map {
                            $0.makeEdit(newName: newName)
                        }.sorted { lhs, rhs in
                            (lhs.path, lhs.byteOffset, lhs.usr)
                                < (rhs.path, rhs.byteOffset, rhs.usr)
                        }
                    ))
            }
        }

        for pair in context.codingKeyPlan.pairs {
            guard
                let propertyEntry = renames.first(where: {
                    $0.usr == pair.propertyUSR
                })
            else {
                rejections.append(
                    contentsOf: CodingKeyRename.Planner.makeRejections(
                        pair: pair,
                        groupsByUSR: context.groupsByUSR,
                        reasons: ["paired stored property was not eligible for renaming"]
                    ))
                continue
            }

            var mappingFailures: Set<String> = []
            if propertyEntry.kind != IndexSymbolKind.instanceProperty.rawValue
                || propertyEntry.oldName != pair.caseRename.oldName
            {
                mappingFailures.insert(
                    "stored property and CodingKeys case do not resolve to one source spelling"
                )
            }
            if let existing = mappingStore.rename(for: pair.caseUSR) {
                if existing.originalName != pair.caseRename.oldName
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
                renames.removeAll { $0.usr == pair.propertyUSR }
                rejections.append(
                    contentsOf: CodingKeyRename.Planner.makeRejections(
                        pair: pair,
                        groupsByUSR: context.groupsByUSR,
                        reasons: mappingFailures.sorted()
                    ))
                continue
            }

            if mappingStore.rename(for: pair.caseUSR) == nil {
                mappingStore.record(
                    usr: pair.caseUSR,
                    originalName: pair.caseRename.oldName,
                    obfuscatedName: propertyEntry.newName,
                    kind: enumCaseKind
                )
            }
            renames.append(
                RenamePlan.Entry(
                    usr: pair.caseUSR,
                    kind: enumCaseKind,
                    oldName: pair.caseRename.oldName,
                    newName: propertyEntry.newName,
                    edits: pair.caseRename.editTemplates.map {
                        $0.makeEdit(newName: propertyEntry.newName)
                    }.sorted { lhs, rhs in
                        (lhs.path, lhs.byteOffset, lhs.usr)
                            < (rhs.path, rhs.byteOffset, rhs.usr)
                    }
                ))
        }
    }

    // MARK: - Preservation edits

    private struct PropertyWrapperEditTemplate: Hashable {
        let path: String
        let byteOffset: Int
        let length: Int
        let line: Int
        let utf8Column: Int
        let oldName: String
        let derivedPrefix: String
        let derivedUSR: String
    }

    private struct PropertyWrapperRename {
        let propertyUSR: String
        let editTemplates: Set<PropertyWrapperEditTemplate>
    }

    private static func propertyWrapperRenames(
        semanticIndex: SemanticIndex,
        groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
        sourceCache: SourceFileCache
    ) -> [PropertyWrapperRename] {
        var propertyRenames: [PropertyWrapperRename] = []
        for propertyUSR in semanticIndex.propertyWrapperDerivedUSRsByPropertyUSR.keys.sorted() {
            guard let propertyGroup = groupsByUSR[propertyUSR] else {
                continue
            }
            let propertyName = propertyGroup.symbol.name
            let derivedUSRs =
                semanticIndex.propertyWrapperDerivedUSRsByPropertyUSR[propertyUSR] ?? []
            var editTemplates: Set<PropertyWrapperEditTemplate> = []
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
                    editTemplates.insert(
                        PropertyWrapperEditTemplate(
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
                propertyRenames.append(
                    PropertyWrapperRename(
                        propertyUSR: propertyUSR,
                        editTemplates: editTemplates
                    ))
            }
        }
        return propertyRenames.sorted { $0.propertyUSR < $1.propertyUSR }
    }

    private static func implicitRawValueSupportEdits(
        syntax: EnumCaseSyntax.Index,
        renames: [RenamePlan.Entry]
    ) -> [SourcePatcher.Edit] {
        let renamesByUSR = Dictionary(uniqueKeysWithValues: renames.map { ($0.usr, $0) })
        return syntax.owners.flatMap { owner in
            owner.members.compactMap { member -> SourcePatcher.Edit? in
                guard renamesByUSR[member.caseUSR] != nil,
                    !member.hasExplicitRawValue,
                    let literal = member.implicitRawValueLiteral,
                    let token = member.declarationToken
                else {
                    return nil
                }
                return SourcePatcher.Edit(
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

    private static func propertyWrapperSupportEdits(
        propertyRenames: [PropertyWrapperRename],
        renames: [RenamePlan.Entry]
    ) -> [SourcePatcher.Edit] {
        let renamesByUSR = Dictionary(uniqueKeysWithValues: renames.map { ($0.usr, $0) })
        var edits: Set<SourcePatcher.Edit> = []
        for propertyRename in propertyRenames {
            guard let rename = renamesByUSR[propertyRename.propertyUSR] else {
                continue
            }
            for template in propertyRename.editTemplates {
                edits.insert(
                    SourcePatcher.Edit(
                        path: template.path,
                        byteOffset: template.byteOffset,
                        length: template.length,
                        line: template.line,
                        utf8Column: template.utf8Column,
                        oldName: template.oldName,
                        newName: template.derivedPrefix + rename.newName,
                        usr: template.derivedUSR
                    ))
            }
        }
        return edits.sorted { lhs, rhs in
            (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
        }
    }

    private struct CodingKeyPreservation {
        let ownerUSR: String
        let propertyUSRs: [String]
        let qualifiedOwnerUSRs: [String]
        let path: String
        let declarationLine: Int
    }

    private static func codingKeyPreservations(
        semanticIndex: SemanticIndex,
        groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
        sourceCache: SourceFileCache,
        obfuscationRoots: [URL]
    ) -> [CodingKeyPreservation] {
        var preservations: [CodingKeyPreservation] = []
        for ownerUSR in semanticIndex.serializationSensitiveOwnerUSRs.sorted() {
            guard semanticIndex.symbolsByUSR[ownerUSR]?.isKind(.struct) == true,
                !semanticIndex.explicitCodingKeysOwnerUSRs.contains(ownerUSR),
                !semanticIndex.customSerializationImplementationOwnerUSRs.contains(ownerUSR),
                let qualifiedOwnerUSRs = semanticIndex.qualifiedNominalOwnerUSRs(for: ownerUSR),
                qualifiedOwnerUSRs.allSatisfy({ usr in
                    semanticIndex.symbolsByUSR[usr].flatMap { escapedSwiftIdentifier($0.name) }
                        != nil
                }),
                let ownerGroup = groupsByUSR[ownerUSR]
            else {
                continue
            }

            let propertyUSRs = semanticIndex.directStoredPropertyUSRs(of: ownerUSR).sorted()
            guard !propertyUSRs.isEmpty,
                propertyUSRs.allSatisfy({ usr in
                    groupsByUSR[usr] != nil
                        && semanticIndex.symbolsByUSR[usr].flatMap {
                            escapedSwiftIdentifier($0.name)
                        } != nil
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

            preservations.append(
                CodingKeyPreservation(
                    ownerUSR: ownerUSR,
                    propertyUSRs: propertyUSRs,
                    qualifiedOwnerUSRs: qualifiedOwnerUSRs,
                    path: SourcePathNormalizer.canonicalPath(ownerDeclaration.path),
                    declarationLine: ownerDeclaration.line
                ))
        }
        return preservations.sorted { lhs, rhs in
            (lhs.path, lhs.declarationLine, lhs.ownerUSR) < (
                rhs.path, rhs.declarationLine, rhs.ownerUSR
            )
        }
    }

    private static func codingKeySupportEdits(
        preservations: [CodingKeyPreservation],
        renames: [RenamePlan.Entry],
        semanticIndex: SemanticIndex,
        sourceCache: SourceFileCache
    ) -> [SourcePatcher.Edit] {
        let renamesByUSR = Dictionary(uniqueKeysWithValues: renames.map { ($0.usr, $0) })
        var chunksByPath: [String: [(ownerUSR: String, line: Int, text: String)]] = [:]

        for preservation in preservations {
            guard !preservation.propertyUSRs.allSatisfy({ renamesByUSR[$0] == nil }) else {
                continue
            }

            let qualifiedOwnerNames = preservation.qualifiedOwnerUSRs.compactMap { usr -> String? in
                guard let originalName = semanticIndex.symbolsByUSR[usr]?.name else {
                    return nil
                }
                return escapedSwiftIdentifier(renamesByUSR[usr]?.newName ?? originalName)
            }
            guard qualifiedOwnerNames.count == preservation.qualifiedOwnerUSRs.count else {
                continue
            }

            let cases = preservation.propertyUSRs.compactMap { usr -> (String, String)? in
                guard let originalName = semanticIndex.symbolsByUSR[usr]?.name,
                    let caseName = escapedSwiftIdentifier(
                        renamesByUSR[usr]?.newName ?? originalName)
                else {
                    return nil
                }
                return (originalName, "        case \(caseName) = \"\(originalName)\"")
            }.sorted { lhs, rhs in
                (lhs.0, lhs.1) < (rhs.0, rhs.1)
            }
            guard cases.count == preservation.propertyUSRs.count else {
                continue
            }

            let text = [
                "extension \(qualifiedOwnerNames.joined(separator: ".")) {",
                "    private enum CodingKeys: String, CodingKey {",
                cases.map(\.1).joined(separator: "\n"),
                "    }",
                "}",
            ].joined(separator: "\n")
            chunksByPath[preservation.path, default: []].append(
                (
                    ownerUSR: preservation.ownerUSR,
                    line: preservation.declarationLine,
                    text: text
                ))
        }

        return chunksByPath.compactMap { path, chunks -> SourcePatcher.Edit? in
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
            return SourcePatcher.Edit(
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

    private enum CoordinatedRenameKind {
        case protocolWitness
        case overrideChain
    }

    // MARK: - Coordinated families

    private struct CoordinatedRenameFamily {
        let key: String
        let memberUSRs: Set<String>
        let protocolRequirementUSRs: Set<String>
        let structuralReasons: [String]

        let kind: CoordinatedRenameKind

        func rejectionReason(_ summaries: [String]) -> String {
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

    private static func coordinatedRenameFamilies(
        semanticIndex: SemanticIndex,
        groupsByUSR: [String: IndexSnapshot.OccurrenceGroup]
    ) -> [CoordinatedRenameFamily] {
        let localRequirementUSRs = Set(
            semanticIndex.protocolRequirementUSRs.filter { usr in
                groupsByUSR[usr].map { !IndexSymbolName.isSyntheticAccessor($0.symbol.name) }
                    == true
            })
        let familySeeds = localRequirementUSRs.union(semanticIndex.overrideRelatedUSRs)

        var visited: Set<String> = []
        var families: [CoordinatedRenameFamily] = []
        for seedUSR in familySeeds.sorted() {
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
                    contentsOf: (semanticIndex.overrideRelationNeighbors[usr] ?? []).filter {
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
                    structuralReasons.append(
                        "Objective-C requirement or witness is part of the component: \(usr)")
                }
                if !semanticIndex.selectedDeclarationUSRs.contains(memberGroup.usr) {
                    structuralReasons.append(
                        "related USR has no declaration inside selected source roots: \(usr)")
                }
            }

            let protocolRequirementUSRs = members.intersection(localRequirementUSRs)
            families.append(
                CoordinatedRenameFamily(
                    key: members.sorted().first ?? seedUSR,
                    memberUSRs: members,
                    protocolRequirementUSRs: protocolRequirementUSRs,
                    structuralReasons: Array(Set(structuralReasons)).sorted(),
                    kind: protocolRequirementUSRs.isEmpty ? .overrideChain : .protocolWitness
                ))
        }

        return families.sorted { $0.key < $1.key }
    }

    private static func coalescedRejections(
        _ decisions: [RenameEligibility]
    ) -> [RenameEligibility] {
        Dictionary(grouping: decisions, by: \.usr).values.compactMap { duplicates in
            guard
                let first = duplicates.sorted(by: {
                    ($0.symbolName, $0.symbolKind, $0.originalName ?? "")
                        < ($1.symbolName, $1.symbolKind, $1.originalName ?? "")
                }).first
            else {
                return nil
            }
            return RenameEligibility(
                usr: first.usr,
                symbolName: first.symbolName,
                symbolKind: first.symbolKind,
                isEligible: false,
                originalName: first.originalName,
                reasons: Array(Set(duplicates.flatMap(\.reasons))).sorted()
            )
        }
    }

    private static func isSemanticOnlyCoordinatedOccurrence(
        _ occurrence: IndexSnapshot.Occurrence,
        familyUSRs: Set<String>
    ) -> Bool {
        guard occurrence.hasRole(.implicit) else {
            return false
        }
        guard IndexRole.lexicalRawValues.isDisjoint(with: occurrence.roles) else {
            return false
        }
        return occurrence.relations.contains { relation in
            (relation.hasRole(.overrideOf) || relation.hasRole(.baseOf))
                && familyUSRs.contains(relation.usr)
        }
    }

    // MARK: - Name generation

    private mutating func nextName(for symbolKind: String, avoiding reservedNames: Set<String>)
        -> String
    {
        while true {
            let generatedName = generator.nextName(avoiding: [])
            let candidate = Self.nameWithConventionalInitialCase(generatedName, for: symbolKind)
            if !reservedNames.contains(candidate), isPlainSwiftIdentifier(candidate) {
                return candidate
            }
        }
    }

    private static func nameWithConventionalInitialCase(_ name: String, for symbolKind: String)
        -> String
    {
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
        result.replaceSubrange(
            letterIndex...letterIndex, with: String(name[letterIndex]).lowercased())
        return result
    }

}
