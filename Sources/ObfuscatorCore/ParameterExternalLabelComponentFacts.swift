import Foundation

public enum ParameterExternalLabelComponentBlocker: String, Codable, Hashable, Sendable {
    case incompleteParameterStructure
    case relationLeavesSelectedSourceRoots
    case objectiveCRuntimeDispatch
    case externallyOwned
    case occurrenceOutsideSelectedSourceRoots
    case incompleteParameterSyntax
    case unsafeLocalBindingScope
    case backtickedIdentifier
    case languageRequiredExternalLabel
    case incompleteInheritedConstructorCoverage
    case incompleteCallBindings
    case incompleteCallableReferenceBindings
    case inconsistentRelatedSignature
    case enumCaseOwnerComponentDenied
}

public struct ParameterExternalLabelOrdinalComponent: Sendable {
    public let ordinal: Int
    public let originalLabel: String
    public let parameterUSRs: Set<String>
}

public struct ParameterExternalLabelRenameComponent: Sendable {
    public let key: String
    public let relatedCallableUSRs: Set<String>
    public let sourceCallableComponents: [ParameterRenameComponent]
    public let ordinalComponents: [ParameterExternalLabelOrdinalComponent]
    public let namedParameterUSRs: Set<String>
    public let isProtocolRelated: Bool
    public let isOverrideRelated: Bool
    public let blockers: Set<ParameterExternalLabelComponentBlocker>
    public let blockerDetails: [String]

    public var isEligible: Bool {
        blockers.isEmpty
    }
}

public struct DeniedParameterExternalLabelComponent: Codable, Equatable, Sendable {
    public let key: String
    public let relatedCallableUSRs: [String]
    public let sourceCallableUSRs: [String]
    public let namedParameterUSRs: [String]
    public let blockers: [ParameterExternalLabelComponentBlocker]
    public let blockerDetails: [String]
}

public struct EligibleParameterExternalLabelOrdinalComponent: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let originalLabel: String
    public let parameterUSRs: [String]
}

public struct EligibleParameterExternalLabelComponent: Codable, Equatable, Sendable {
    public let key: String
    public let relatedCallableUSRs: [String]
    public let sourceCallableUSRs: [String]
    public let ordinalComponents: [EligibleParameterExternalLabelOrdinalComponent]
}

public struct ParameterExternalLabelComponentFactsSummary: Codable, Equatable, Sendable {
    public let atomicComponents: Int
    public let sourceCallableComponents: Int
    public let namedExternalLabelParameters: Int
    public let eligibleAtomicComponents: Int
    public let eligibleSourceCallableComponents: Int
    public let eligibleNamedExternalLabelParameters: Int
    public let deniedAtomicComponents: Int
    public let deniedSourceCallableComponents: Int
    public let deniedNamedExternalLabelParameters: Int
    public let standaloneAtomicComponents: Int
    public let eligibleStandaloneAtomicComponents: Int
    public let relatedAtomicComponents: Int
    public let eligibleRelatedAtomicComponents: Int
    public let protocolRelatedAtomicComponents: Int
    public let eligibleProtocolRelatedAtomicComponents: Int
    public let overrideRelatedAtomicComponents: Int
    public let eligibleOverrideRelatedAtomicComponents: Int
    public let blockerComponents: [String: Int]
    public let blockerNamedParameters: [String: Int]
    public let eligibleComponents: [EligibleParameterExternalLabelComponent]
    public let deniedComponents: [DeniedParameterExternalLabelComponent]

    public static let empty = ParameterExternalLabelComponentFactsSummary(components: [])

    init(components: [ParameterExternalLabelRenameComponent]) {
        let eligible = components.filter(\.isEligible)
        let denied = components.filter { !$0.isEligible }
        let standalone = components.filter { !$0.isOverrideRelated && !$0.isProtocolRelated }
        let related = components.filter { $0.isOverrideRelated || $0.isProtocolRelated }
        let protocolRelated = components.filter(\.isProtocolRelated)
        let overrideRelated = components.filter(\.isOverrideRelated)

        self.atomicComponents = components.count
        self.sourceCallableComponents = components.reduce(0) {
            $0 + $1.sourceCallableComponents.count
        }
        self.namedExternalLabelParameters = Set(
            components.flatMap(\.namedParameterUSRs)
        ).count
        self.eligibleAtomicComponents = eligible.count
        self.eligibleSourceCallableComponents = eligible.reduce(0) {
            $0 + $1.sourceCallableComponents.count
        }
        self.eligibleNamedExternalLabelParameters = Set(
            eligible.flatMap(\.namedParameterUSRs)
        ).count
        self.deniedAtomicComponents = denied.count
        self.deniedSourceCallableComponents = denied.reduce(0) {
            $0 + $1.sourceCallableComponents.count
        }
        self.deniedNamedExternalLabelParameters = Set(
            denied.flatMap(\.namedParameterUSRs)
        ).count
        self.standaloneAtomicComponents = standalone.count
        self.eligibleStandaloneAtomicComponents = standalone.count(where: \.isEligible)
        self.relatedAtomicComponents = related.count
        self.eligibleRelatedAtomicComponents = related.count(where: \.isEligible)
        self.protocolRelatedAtomicComponents = protocolRelated.count
        self.eligibleProtocolRelatedAtomicComponents = protocolRelated.count(where: \.isEligible)
        self.overrideRelatedAtomicComponents = overrideRelated.count
        self.eligibleOverrideRelatedAtomicComponents = overrideRelated.count(where: \.isEligible)

        var blockerComponents: [ParameterExternalLabelComponentBlocker: Int] = [:]
        var blockerNamedParameters: [ParameterExternalLabelComponentBlocker: Set<String>] = [:]
        for component in denied {
            for blocker in component.blockers {
                blockerComponents[blocker, default: 0] += 1
                blockerNamedParameters[blocker, default: []].formUnion(
                    component.namedParameterUSRs
                )
            }
        }
        self.blockerComponents = Dictionary(uniqueKeysWithValues: blockerComponents.map {
            ($0.key.rawValue, $0.value)
        })
        self.blockerNamedParameters = Dictionary(uniqueKeysWithValues: blockerNamedParameters.map {
            ($0.key.rawValue, $0.value.count)
        })
        self.eligibleComponents = eligible.map { component in
            EligibleParameterExternalLabelComponent(
                key: component.key,
                relatedCallableUSRs: component.relatedCallableUSRs.sorted(),
                sourceCallableUSRs: component.sourceCallableComponents
                    .map(\.callableUSR)
                    .sorted(),
                ordinalComponents: component.ordinalComponents.map { ordinal in
                    EligibleParameterExternalLabelOrdinalComponent(
                        ordinal: ordinal.ordinal,
                        originalLabel: ordinal.originalLabel,
                        parameterUSRs: ordinal.parameterUSRs.sorted()
                    )
                }.sorted { $0.ordinal < $1.ordinal }
            )
        }.sorted { $0.key < $1.key }
        self.deniedComponents = denied.map { component in
            DeniedParameterExternalLabelComponent(
                key: component.key,
                relatedCallableUSRs: component.relatedCallableUSRs.sorted(),
                sourceCallableUSRs: component.sourceCallableComponents
                    .map(\.callableUSR)
                    .sorted(),
                namedParameterUSRs: component.namedParameterUSRs.sorted(),
                blockers: component.blockers.sorted { $0.rawValue < $1.rawValue },
                blockerDetails: component.blockerDetails
            )
        }.sorted { $0.key < $1.key }
    }
}

public struct DeniedParameterExternalLabelRenameOutcome: Codable, Equatable, Sendable {
    public let key: String
    public let parameterUSRs: [String]
    public let reasons: [String]
}

public struct ParameterExternalLabelRenameOutcomeSummary: Codable, Equatable, Sendable {
    public let candidateAtomicComponents: Int
    public let candidateParameterUSRs: Int
    public let renamedAtomicComponents: Int
    public let renamedParameterUSRs: Int
    public let deniedAtomicComponents: Int
    public let deniedParameterUSRs: Int
    public let unclassifiedAtomicComponents: Int
    public let unclassifiedParameterUSRs: Int
    public let deniedComponents: [DeniedParameterExternalLabelRenameOutcome]

    public static let empty = ParameterExternalLabelRenameOutcomeSummary(
        components: [],
        entries: [],
        decisions: []
    )

    init(
        components: [ParameterExternalLabelRenameComponent],
        entries: [RenamePlanEntry],
        decisions: [SafetyDecision]
    ) {
        let candidates = components.filter(\.isEligible)
        let renamedUSRs = Set(entries.map(\.usr))
        let decisionsByUSR = Dictionary(
            decisions.map { ($0.usr, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let candidateUSRs = Set(candidates.flatMap(\.namedParameterUSRs))
        let renamedCandidateUSRs = candidateUSRs.intersection(renamedUSRs)
        let deniedCandidateUSRs = candidateUSRs.intersection(decisionsByUSR.keys)
        let unclassifiedUSRs = candidateUSRs
            .subtracting(renamedCandidateUSRs)
            .subtracting(deniedCandidateUSRs)
        let renamedComponents = candidates.filter {
            $0.namedParameterUSRs.isSubset(of: renamedCandidateUSRs)
        }
        let deniedComponents = candidates.filter {
            !$0.namedParameterUSRs.isDisjoint(with: deniedCandidateUSRs)
        }
        let unclassifiedComponents = candidates.filter {
            !$0.namedParameterUSRs.isDisjoint(with: unclassifiedUSRs)
        }

        self.candidateAtomicComponents = candidates.count
        self.candidateParameterUSRs = candidateUSRs.count
        self.renamedAtomicComponents = renamedComponents.count
        self.renamedParameterUSRs = renamedCandidateUSRs.count
        self.deniedAtomicComponents = deniedComponents.count
        self.deniedParameterUSRs = deniedCandidateUSRs.count
        self.unclassifiedAtomicComponents = unclassifiedComponents.count
        self.unclassifiedParameterUSRs = unclassifiedUSRs.count
        self.deniedComponents = deniedComponents.map { component in
            let parameterUSRs = component.namedParameterUSRs
                .intersection(deniedCandidateUSRs)
                .sorted()
            let reasons = Array(Set(parameterUSRs.flatMap {
                decisionsByUSR[$0]?.reasons ?? []
            })).sorted()
            return DeniedParameterExternalLabelRenameOutcome(
                key: component.key,
                parameterUSRs: parameterUSRs,
                reasons: reasons
            )
        }.sorted { $0.key < $1.key }
    }
}

public struct ParameterExternalLabelComponentFacts: Sendable {
    public let components: [ParameterExternalLabelRenameComponent]
    public let summary: ParameterExternalLabelComponentFactsSummary

    public init(
        indexedFacts: IndexedSemanticFacts,
        parameterRolesByUSR: [String: ParameterDeclarationSyntaxRoles],
        callBindingFacts: ParameterCallArgumentBindingFacts,
        callableReferenceBindingFacts: ParameterCallableReferenceBindingFacts,
        eligibleEnumCaseUSRs: Set<String> = []
    ) {
        let callableComponents = indexedFacts.parameterRenameComponents
        let componentsByCallableUSR = Dictionary(
            uniqueKeysWithValues: callableComponents.map { ($0.callableUSR, $0) }
        )
        let targetCallableUSRs = Set(callableComponents.compactMap { component -> String? in
            component.members.contains { member in
                if case .named = member.externalLabel {
                    return parameterRolesByUSR[member.parameterUSR]?.kind != .accessor
                }
                return false
            } ? component.callableUSR : nil
        })

        var visitedTargetUSRs: Set<String> = []
        var components: [ParameterExternalLabelRenameComponent] = []
        for seedUSR in targetCallableUSRs.sorted() where !visitedTargetUSRs.contains(seedUSR) {
            let relatedCallableUSRs = Self.relatedCallableUSRs(
                seedUSR: seedUSR,
                neighbors: indexedFacts.overrideRelationNeighbors
            )
            visitedTargetUSRs.formUnion(relatedCallableUSRs.intersection(targetCallableUSRs))
            let sourceComponents = relatedCallableUSRs.compactMap {
                componentsByCallableUSR[$0]
            }.sorted { $0.callableUSR < $1.callableUSR }
            components.append(Self.makeComponent(
                relatedCallableUSRs: relatedCallableUSRs,
                sourceComponents: sourceComponents,
                indexedFacts: indexedFacts,
                parameterRolesByUSR: parameterRolesByUSR,
                callBindingFacts: callBindingFacts,
                callableReferenceBindingFacts: callableReferenceBindingFacts,
                eligibleEnumCaseUSRs: eligibleEnumCaseUSRs
            ))
        }

        self.components = components.sorted { $0.key < $1.key }
        self.summary = ParameterExternalLabelComponentFactsSummary(
            components: self.components
        )
    }

    private static func relatedCallableUSRs(
        seedUSR: String,
        neighbors: [String: Set<String>]
    ) -> Set<String> {
        guard neighbors[seedUSR] != nil else {
            return [seedUSR]
        }
        var result: Set<String> = []
        var pending = [seedUSR]
        while let usr = pending.popLast() {
            guard result.insert(usr).inserted else {
                continue
            }
            pending.append(contentsOf: (neighbors[usr] ?? []).filter {
                !result.contains($0)
            })
        }
        return result
    }

    private static func makeComponent(
        relatedCallableUSRs: Set<String>,
        sourceComponents: [ParameterRenameComponent],
        indexedFacts: IndexedSemanticFacts,
        parameterRolesByUSR: [String: ParameterDeclarationSyntaxRoles],
        callBindingFacts: ParameterCallArgumentBindingFacts,
        callableReferenceBindingFacts: ParameterCallableReferenceBindingFacts,
        eligibleEnumCaseUSRs: Set<String>
    ) -> ParameterExternalLabelRenameComponent {
        var blockers: Set<ParameterExternalLabelComponentBlocker> = []
        var details: Set<String> = []

        let missingComponents = relatedCallableUSRs.subtracting(
            sourceComponents.map(\.callableUSR)
        )
        if !missingComponents.isEmpty {
            blockers.insert(.relationLeavesSelectedSourceRoots)
            for usr in missingComponents.sorted() {
                details.insert("related callable has no explicit parameter component: \(usr)")
            }
        }
        for usr in relatedCallableUSRs.sorted() {
            if !indexedFacts.selectedDeclarationUSRs.contains(usr) {
                blockers.insert(.relationLeavesSelectedSourceRoots)
                details.insert("related callable has no declaration in selected roots: \(usr)")
            }
            if IndexUSR.isObjectiveCCompatible(usr) || indexedFacts.runtimeSensitiveUSRs.contains(usr) {
                blockers.insert(.objectiveCRuntimeDispatch)
                details.insert("runtime-sensitive related callable: \(usr)")
            }
            if indexedFacts.externallyOwnedUSRs.contains(usr) {
                blockers.insert(.externallyOwned)
                details.insert("externally owned related callable: \(usr)")
            }
        }

        for component in sourceComponents {
            if component.ownerCategory == .enumCase,
               !eligibleEnumCaseUSRs.contains(component.callableUSR) {
                blockers.insert(.enumCaseOwnerComponentDenied)
                details.insert(
                    "enum case owner component is not eligible for coordinated renaming: "
                        + component.callableUSR
                )
            }
            if !component.isStructurallyComplete {
                blockers.insert(.incompleteParameterStructure)
                for reason in component.structuralReasons {
                    details.insert("\(component.callableUSR): \(reason)")
                }
            }
            if component.hasOccurrenceOutsideSelectedRoots {
                blockers.insert(.occurrenceOutsideSelectedSourceRoots)
                details.insert("callable has an occurrence outside selected roots: \(component.callableUSR)")
            }
            if component.isRuntimeSensitive {
                blockers.insert(.objectiveCRuntimeDispatch)
                details.insert("runtime-sensitive source callable: \(component.callableUSR)")
            }
            if component.isExternallyOwned {
                blockers.insert(.externallyOwned)
                details.insert("externally owned source callable: \(component.callableUSR)")
            }
            if !component.externalLabelArgumentLocations.allSatisfy({ location in
                callBindingFacts.bindingsByAnchor[ParameterCallSiteAnchor(
                    callableUSR: component.callableUSR,
                    location: location
                )] != nil
            }) {
                blockers.insert(.incompleteCallBindings)
                details.insert("one or more call anchors are not ordinal-bound: \(component.callableUSR)")
            }
            if component.ownerCategory != .enumCase,
               !component.nonCallReferenceLocations.allSatisfy({ location in
                callableReferenceBindingFacts.bindingsByAnchor[
                    ParameterCallableReferenceAnchor(
                        callableUSR: component.callableUSR,
                        location: location
                    )
                ] != nil
            }) {
                blockers.insert(.incompleteCallableReferenceBindings)
                details.insert(
                    "one or more callable-reference anchors are not ordinal-bound: "
                        + component.callableUSR
                )
            }
            for member in component.members {
                guard let role = parameterRolesByUSR[member.parameterUSR],
                      externalLabelsAgree(indexed: member.externalLabel, syntax: role.externalLabel) else {
                    blockers.insert(.incompleteParameterSyntax)
                    details.insert(
                        "parameter declaration syntax is unavailable or disagrees: "
                            + member.parameterUSR
                    )
                    continue
                }
                if role.localBinding != nil,
                   !role.shadowingBindingDeclarations.isEmpty
                    || !role.implicitShadowingBindingNames.isEmpty {
                    blockers.insert(.unsafeLocalBindingScope)
                    details.insert("parameter local binding is shadowed: \(member.parameterUSR)")
                }
                let tokens = [role.externalLabel.token, role.localBinding]
                    .compactMap { $0 } + role.localBindingReferences
                if tokens.contains(where: \.isBackticked) {
                    blockers.insert(.backtickedIdentifier)
                    details.insert("parameter uses a backticked identifier token: \(member.parameterUSR)")
                }
            }
        }

        let constructorComponents = sourceComponents.filter {
            $0.callableKind == IndexSymbolKind.constructor.rawValue
        }
        if !constructorComponents.isEmpty {
            let coveredOwnerUSRs = Set(sourceComponents.compactMap {
                indexedFacts.nominalOwnerUSR(of: $0.callableUSR)
            })
            for component in constructorComponents {
                guard let ownerUSR = indexedFacts.nominalOwnerUSR(
                    of: component.callableUSR
                ) else {
                    continue
                }
                let uncoveredDescendants = indexedFacts
                    .nominalDescendantUSRs(of: ownerUSR)
                    .subtracting(coveredOwnerUSRs)
                if !uncoveredDescendants.isEmpty {
                    blockers.insert(.incompleteInheritedConstructorCoverage)
                    for descendantUSR in uncoveredDescendants.sorted() {
                        details.insert(
                            "constructor label may be inherited by an uncovered subtype: "
                                + descendantUSR
                        )
                    }
                }
            }
        }

        var ordinalComponents: [ParameterExternalLabelOrdinalComponent] = []
        if let first = sourceComponents.first {
            let parameterCounts = Set(sourceComponents.map { $0.members.count })
            if parameterCounts.count != 1 {
                blockers.insert(.inconsistentRelatedSignature)
                details.insert("related callables expose different parameter counts")
            } else {
                let sortedMembers = sourceComponents.map { component in
                    component.members.sorted { $0.ordinal < $1.ordinal }
                }
                for ordinal in first.members.indices {
                    let members = sortedMembers.map { $0[ordinal] }
                    guard members.allSatisfy({ $0.ordinal == ordinal }) else {
                        blockers.insert(.inconsistentRelatedSignature)
                        details.insert("related callable parameter ordinals are not aligned")
                        continue
                    }
                    let labels = Set(members.map(\.externalLabel))
                    guard labels.count == 1, let label = labels.first else {
                        blockers.insert(.inconsistentRelatedSignature)
                        details.insert("related callable external labels disagree at ordinal \(ordinal)")
                        continue
                    }
                    switch label {
                    case .named(let name):
                        if first.ownerCategory == .subscriptDeclaration,
                           name == "dynamicMember" {
                            blockers.insert(.languageRequiredExternalLabel)
                            details.insert(
                                "Swift dynamic-member lookup requires "
                                    + "subscript(dynamicMember:) at ordinal \(ordinal)"
                            )
                        }
                        if first.callableKind == IndexSymbolKind.constructor.rawValue,
                           name == "wrappedValue" {
                            blockers.insert(.languageRequiredExternalLabel)
                            details.insert(
                                "Swift property-wrapper initialization requires "
                                    + "init(wrappedValue:) at ordinal \(ordinal)"
                            )
                        }
                        ordinalComponents.append(ParameterExternalLabelOrdinalComponent(
                            ordinal: ordinal,
                            originalLabel: name,
                            parameterUSRs: Set(members.map(\.parameterUSR))
                        ))
                    case .omitted:
                        break
                    case .unavailable:
                        blockers.insert(.incompleteParameterStructure)
                        details.insert("external label is unavailable at ordinal \(ordinal)")
                    }
                }
            }
        } else {
            blockers.insert(.relationLeavesSelectedSourceRoots)
            details.insert("component contains no callable declared in selected roots")
        }

        let namedParameterUSRs = Set(sourceComponents.flatMap { component in
            component.members.compactMap { member -> String? in
                if case .named = member.externalLabel {
                    return member.parameterUSR
                }
                return nil
            }
        })
        let isProtocolRelated = sourceComponents.contains(where: \.isProtocolRequirement)
            || !relatedCallableUSRs.isDisjoint(with: indexedFacts.protocolRequirementUSRs)
        let isOverrideRelated = relatedCallableUSRs.count > 1
            || sourceComponents.contains(where: \.isOverrideRelated)

        return ParameterExternalLabelRenameComponent(
            key: relatedCallableUSRs.sorted().first
                ?? sourceComponents.first?.callableUSR
                ?? "<empty-parameter-component>",
            relatedCallableUSRs: relatedCallableUSRs,
            sourceCallableComponents: sourceComponents,
            ordinalComponents: ordinalComponents,
            namedParameterUSRs: namedParameterUSRs,
            isProtocolRelated: isProtocolRelated,
            isOverrideRelated: isOverrideRelated,
            blockers: blockers,
            blockerDetails: details.sorted()
        )
    }

    private static func externalLabelsAgree(
        indexed: ParameterExternalLabel,
        syntax: ParameterExternalLabelSyntaxRole
    ) -> Bool {
        switch (indexed, syntax) {
        case (.named(let indexedName), .named(let token)):
            return indexedName == token.name
        case (.omitted, .omitted), (.omitted, .none):
            return true
        default:
            return false
        }
    }
}
