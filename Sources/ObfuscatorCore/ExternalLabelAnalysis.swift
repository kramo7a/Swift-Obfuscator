import Foundation

extension ExternalLabel {
    public enum Blocker: String, Codable, Hashable, Sendable {
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
        case enumCaseOwnerBlocked = "enumCaseOwnerComponentDenied"
    }

    public struct Slot: Sendable {
        public let ordinal: Int
        public let originalLabel: String
        public let parameterUSRs: Set<String>
    }

    public struct Family: Sendable {
        public let key: String
        public let relatedCallableUSRs: Set<String>
        public let signatures: [CallableSignature]
        public let slots: [ExternalLabel.Slot]
        public let labeledParameterUSRs: Set<String>
        public let isProtocolRelated: Bool
        public let isOverrideRelated: Bool
        public let blockers: Set<ExternalLabel.Blocker>
        public let blockerDetails: [String]

        public var isEligible: Bool {
            blockers.isEmpty
        }
    }

    public struct BlockedFamily: Codable, Equatable, Sendable {
        public let key: String
        public let relatedCallableUSRs: [String]
        public let sourceCallableUSRs: [String]
        public let labeledParameterUSRs: [String]
        public let blockers: [ExternalLabel.Blocker]
        public let blockerDetails: [String]

        private enum CodingKeys: String, CodingKey {
            case key
            case relatedCallableUSRs
            case sourceCallableUSRs
            case labeledParameterUSRs = "namedParameterUSRs"
            case blockers
            case blockerDetails
        }
    }

    public struct EligibleSlot: Codable, Equatable, Sendable {
        public let ordinal: Int
        public let originalLabel: String
        public let parameterUSRs: [String]
    }

    public struct EligibleFamily: Codable, Equatable, Sendable {
        public let key: String
        public let relatedCallableUSRs: [String]
        public let sourceCallableUSRs: [String]
        public let slots: [ExternalLabel.EligibleSlot]

        private enum CodingKeys: String, CodingKey {
            case key
            case relatedCallableUSRs
            case sourceCallableUSRs
            case slots = "ordinalComponents"
        }
    }

    public struct Report: Codable, Equatable, Sendable {
        public let familyCount: Int
        public let signatureCount: Int
        public let labeledParameterCount: Int
        public let eligibleFamilyCount: Int
        public let eligibleSignatureCount: Int
        public let eligibleLabeledParameterCount: Int
        public let blockedFamilyCount: Int
        public let blockedSignatureCount: Int
        public let blockedLabeledParameterCount: Int
        public let standaloneFamilyCount: Int
        public let eligibleStandaloneFamilyCount: Int
        public let relatedFamilyCount: Int
        public let eligibleRelatedFamilyCount: Int
        public let protocolRelatedFamilyCount: Int
        public let eligibleProtocolRelatedFamilyCount: Int
        public let overrideRelatedFamilyCount: Int
        public let eligibleOverrideRelatedFamilyCount: Int
        public let familyCountsByBlocker: [String: Int]
        public let parameterCountsByBlocker: [String: Int]
        public let eligibleFamilies: [ExternalLabel.EligibleFamily]
        public let blockedFamilies: [ExternalLabel.BlockedFamily]

        public static let empty = ExternalLabel.Report(families: [])

        init(families: [ExternalLabel.Family]) {
            let eligible = families.filter(\.isEligible)
            let blocked = families.filter { !$0.isEligible }
            let standalone = families.filter { !$0.isOverrideRelated && !$0.isProtocolRelated }
            let related = families.filter { $0.isOverrideRelated || $0.isProtocolRelated }
            let protocolRelated = families.filter(\.isProtocolRelated)
            let overrideRelated = families.filter(\.isOverrideRelated)

            self.familyCount = families.count
            self.signatureCount = families.reduce(0) {
                $0 + $1.signatures.count
            }
            self.labeledParameterCount =
                Set(
                    families.flatMap(\.labeledParameterUSRs)
                ).count
            self.eligibleFamilyCount = eligible.count
            self.eligibleSignatureCount = eligible.reduce(0) {
                $0 + $1.signatures.count
            }
            self.eligibleLabeledParameterCount =
                Set(
                    eligible.flatMap(\.labeledParameterUSRs)
                ).count
            self.blockedFamilyCount = blocked.count
            self.blockedSignatureCount = blocked.reduce(0) {
                $0 + $1.signatures.count
            }
            self.blockedLabeledParameterCount =
                Set(
                    blocked.flatMap(\.labeledParameterUSRs)
                ).count
            self.standaloneFamilyCount = standalone.count
            self.eligibleStandaloneFamilyCount = standalone.count(where: \.isEligible)
            self.relatedFamilyCount = related.count
            self.eligibleRelatedFamilyCount = related.count(where: \.isEligible)
            self.protocolRelatedFamilyCount = protocolRelated.count
            self.eligibleProtocolRelatedFamilyCount = protocolRelated.count(where: \.isEligible)
            self.overrideRelatedFamilyCount = overrideRelated.count
            self.eligibleOverrideRelatedFamilyCount = overrideRelated.count(where: \.isEligible)

            var familyCountsByBlocker: [ExternalLabel.Blocker: Int] = [:]
            var parameterUSRsByBlocker: [ExternalLabel.Blocker: Set<String>] = [:]
            for family in blocked {
                for blocker in family.blockers {
                    familyCountsByBlocker[blocker, default: 0] += 1
                    parameterUSRsByBlocker[blocker, default: []].formUnion(
                        family.labeledParameterUSRs
                    )
                }
            }
            self.familyCountsByBlocker = Dictionary(
                uniqueKeysWithValues: familyCountsByBlocker.map {
                    ($0.key.rawValue, $0.value)
                })
            self.parameterCountsByBlocker = Dictionary(
                uniqueKeysWithValues: parameterUSRsByBlocker.map {
                    ($0.key.rawValue, $0.value.count)
                })
            self.eligibleFamilies = eligible.map { family in
                ExternalLabel.EligibleFamily(
                    key: family.key,
                    relatedCallableUSRs: family.relatedCallableUSRs.sorted(),
                    sourceCallableUSRs: family.signatures
                        .map(\.callableUSR)
                        .sorted(),
                    slots: family.slots.map { slot in
                        ExternalLabel.EligibleSlot(
                            ordinal: slot.ordinal,
                            originalLabel: slot.originalLabel,
                            parameterUSRs: slot.parameterUSRs.sorted()
                        )
                    }.sorted { $0.ordinal < $1.ordinal }
                )
            }.sorted { $0.key < $1.key }
            self.blockedFamilies = blocked.map { family in
                ExternalLabel.BlockedFamily(
                    key: family.key,
                    relatedCallableUSRs: family.relatedCallableUSRs.sorted(),
                    sourceCallableUSRs: family.signatures
                        .map(\.callableUSR)
                        .sorted(),
                    labeledParameterUSRs: family.labeledParameterUSRs.sorted(),
                    blockers: family.blockers.sorted { $0.rawValue < $1.rawValue },
                    blockerDetails: family.blockerDetails
                )
            }.sorted { $0.key < $1.key }
        }

        private enum CodingKeys: String, CodingKey {
            case familyCount = "atomicComponents"
            case signatureCount = "sourceCallableComponents"
            case labeledParameterCount = "namedExternalLabelParameters"
            case eligibleFamilyCount = "eligibleAtomicComponents"
            case eligibleSignatureCount = "eligibleSourceCallableComponents"
            case eligibleLabeledParameterCount = "eligibleNamedExternalLabelParameters"
            case blockedFamilyCount = "deniedAtomicComponents"
            case blockedSignatureCount = "deniedSourceCallableComponents"
            case blockedLabeledParameterCount = "deniedNamedExternalLabelParameters"
            case standaloneFamilyCount = "standaloneAtomicComponents"
            case eligibleStandaloneFamilyCount = "eligibleStandaloneAtomicComponents"
            case relatedFamilyCount = "relatedAtomicComponents"
            case eligibleRelatedFamilyCount = "eligibleRelatedAtomicComponents"
            case protocolRelatedFamilyCount = "protocolRelatedAtomicComponents"
            case eligibleProtocolRelatedFamilyCount = "eligibleProtocolRelatedAtomicComponents"
            case overrideRelatedFamilyCount = "overrideRelatedAtomicComponents"
            case eligibleOverrideRelatedFamilyCount = "eligibleOverrideRelatedAtomicComponents"
            case familyCountsByBlocker = "blockerComponents"
            case parameterCountsByBlocker = "blockerNamedParameters"
            case eligibleFamilies = "eligibleComponents"
            case blockedFamilies = "deniedComponents"
        }
    }

    public struct RenameRejection: Codable, Equatable, Sendable {
        public let key: String
        public let parameterUSRs: [String]
        public let reasons: [String]
    }

    public struct RenameReport: Codable, Equatable, Sendable {
        public let candidateFamilyCount: Int
        public let candidateParameterCount: Int
        public let renamedFamilyCount: Int
        public let renamedParameterCount: Int
        public let rejectedFamilyCount: Int
        public let rejectedParameterCount: Int
        public let unclassifiedFamilyCount: Int
        public let unclassifiedParameterCount: Int
        public let rejections: [ExternalLabel.RenameRejection]

        public static let empty = ExternalLabel.RenameReport(
            families: [],
            renames: [],
            rejections: []
        )

        init(
            families: [ExternalLabel.Family],
            renames: [RenamePlan.Entry],
            rejections: [RenameEligibility]
        ) {
            let candidates = families.filter(\.isEligible)
            let renamedUSRs = Set(renames.map(\.usr))
            let decisionsByUSR = Dictionary(
                rejections.map { ($0.usr, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let candidateUSRs = Set(candidates.flatMap(\.labeledParameterUSRs))
            let renamedCandidateUSRs = candidateUSRs.intersection(renamedUSRs)
            let rejectedCandidateUSRs = candidateUSRs.intersection(decisionsByUSR.keys)
            let unclassifiedUSRs =
                candidateUSRs
                .subtracting(renamedCandidateUSRs)
                .subtracting(rejectedCandidateUSRs)
            let renamedFamilies = candidates.filter {
                $0.labeledParameterUSRs.isSubset(of: renamedCandidateUSRs)
            }
            let rejectedFamilies = candidates.filter {
                !$0.labeledParameterUSRs.isDisjoint(with: rejectedCandidateUSRs)
            }
            let unclassifiedFamilies = candidates.filter {
                !$0.labeledParameterUSRs.isDisjoint(with: unclassifiedUSRs)
            }

            self.candidateFamilyCount = candidates.count
            self.candidateParameterCount = candidateUSRs.count
            self.renamedFamilyCount = renamedFamilies.count
            self.renamedParameterCount = renamedCandidateUSRs.count
            self.rejectedFamilyCount = rejectedFamilies.count
            self.rejectedParameterCount = rejectedCandidateUSRs.count
            self.unclassifiedFamilyCount = unclassifiedFamilies.count
            self.unclassifiedParameterCount = unclassifiedUSRs.count
            self.rejections = rejectedFamilies.map { family in
                let parameterUSRs = family.labeledParameterUSRs
                    .intersection(rejectedCandidateUSRs)
                    .sorted()
                let reasons = Array(
                    Set(
                        parameterUSRs.flatMap {
                            decisionsByUSR[$0]?.reasons ?? []
                        })
                ).sorted()
                return ExternalLabel.RenameRejection(
                    key: family.key,
                    parameterUSRs: parameterUSRs,
                    reasons: reasons
                )
            }.sorted { $0.key < $1.key }
        }

        private enum CodingKeys: String, CodingKey {
            case candidateFamilyCount = "candidateAtomicComponents"
            case candidateParameterCount = "candidateParameterUSRs"
            case renamedFamilyCount = "renamedAtomicComponents"
            case renamedParameterCount = "renamedParameterUSRs"
            case rejectedFamilyCount = "deniedAtomicComponents"
            case rejectedParameterCount = "deniedParameterUSRs"
            case unclassifiedFamilyCount = "unclassifiedAtomicComponents"
            case unclassifiedParameterCount = "unclassifiedParameterUSRs"
            case rejections = "deniedComponents"
        }
    }

    public struct Analysis: Sendable {
        public let families: [ExternalLabel.Family]
        public let report: ExternalLabel.Report

        public init(
            semanticIndex: SemanticIndex,
            parametersByUSR: [String: ParameterSyntax.Parameter],
            callBindings: CallArgumentBinding.Index,
            referenceBindings: CallableReferenceBinding.Index,
            eligibleEnumCaseUSRs: Set<String> = []
        ) {
            let signatures = semanticIndex.callableSignatures
            let signaturesByCallableUSR = Dictionary(
                uniqueKeysWithValues: signatures.map { ($0.callableUSR, $0) }
            )
            let targetCallableUSRs = Set(
                signatures.compactMap { signature -> String? in
                    signature.parameters.contains { parameter in
                        if case .named = parameter.externalLabel {
                            return parametersByUSR[parameter.parameterUSR]?.kind != .accessor
                        }
                        return false
                    } ? signature.callableUSR : nil
                })

            var visitedTargetUSRs: Set<String> = []
            var families: [ExternalLabel.Family] = []
            for seedUSR in targetCallableUSRs.sorted() where !visitedTargetUSRs.contains(seedUSR) {
                let relatedCallableUSRs = Self.relatedCallableUSRs(
                    seedUSR: seedUSR,
                    neighbors: semanticIndex.overrideRelationNeighbors
                )
                visitedTargetUSRs.formUnion(relatedCallableUSRs.intersection(targetCallableUSRs))
                let signatures = relatedCallableUSRs.compactMap {
                    signaturesByCallableUSR[$0]
                }.sorted { $0.callableUSR < $1.callableUSR }
                families.append(
                    Self.makeFamily(
                        relatedCallableUSRs: relatedCallableUSRs,
                        signatures: signatures,
                        semanticIndex: semanticIndex,
                        parametersByUSR: parametersByUSR,
                        callBindings: callBindings,
                        referenceBindings: referenceBindings,
                        eligibleEnumCaseUSRs: eligibleEnumCaseUSRs
                    ))
            }

            self.families = families.sorted { $0.key < $1.key }
            self.report = ExternalLabel.Report(
                families: self.families
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
                pending.append(
                    contentsOf: (neighbors[usr] ?? []).filter {
                        !result.contains($0)
                    })
            }
            return result
        }

        private static func makeFamily(
            relatedCallableUSRs: Set<String>,
            signatures: [CallableSignature],
            semanticIndex: SemanticIndex,
            parametersByUSR: [String: ParameterSyntax.Parameter],
            callBindings: CallArgumentBinding.Index,
            referenceBindings: CallableReferenceBinding.Index,
            eligibleEnumCaseUSRs: Set<String>
        ) -> ExternalLabel.Family {
            var blockers: Set<ExternalLabel.Blocker> = []
            var details: Set<String> = []

            let missingSignatures = relatedCallableUSRs.subtracting(
                signatures.map(\.callableUSR)
            )
            if !missingSignatures.isEmpty {
                blockers.insert(.relationLeavesSelectedSourceRoots)
                for usr in missingSignatures.sorted() {
                    details.insert("related callable has no explicit parameter component: \(usr)")
                }
            }
            for usr in relatedCallableUSRs.sorted() {
                if !semanticIndex.selectedDeclarationUSRs.contains(usr) {
                    blockers.insert(.relationLeavesSelectedSourceRoots)
                    details.insert("related callable has no declaration in selected roots: \(usr)")
                }
                if IndexUSR.isObjectiveCCompatible(usr)
                    || semanticIndex.runtimeSensitiveUSRs.contains(usr)
                {
                    blockers.insert(.objectiveCRuntimeDispatch)
                    details.insert("runtime-sensitive related callable: \(usr)")
                }
                if semanticIndex.externallyOwnedUSRs.contains(usr) {
                    blockers.insert(.externallyOwned)
                    details.insert("externally owned related callable: \(usr)")
                }
            }

            for signature in signatures {
                if signature.ownerCategory == .enumCase,
                    !eligibleEnumCaseUSRs.contains(signature.callableUSR)
                {
                    blockers.insert(.enumCaseOwnerBlocked)
                    details.insert(
                        "enum case owner component is not eligible for coordinated renaming: "
                            + signature.callableUSR
                    )
                }
                if !signature.isStructurallyComplete {
                    blockers.insert(.incompleteParameterStructure)
                    for reason in signature.structuralReasons {
                        details.insert("\(signature.callableUSR): \(reason)")
                    }
                }
                if signature.hasOccurrenceOutsideSelectedRoots {
                    blockers.insert(.occurrenceOutsideSelectedSourceRoots)
                    details.insert(
                        "callable has an occurrence outside selected roots: \(signature.callableUSR)"
                    )
                }
                if signature.isRuntimeSensitive {
                    blockers.insert(.objectiveCRuntimeDispatch)
                    details.insert("runtime-sensitive source callable: \(signature.callableUSR)")
                }
                if signature.isExternallyOwned {
                    blockers.insert(.externallyOwned)
                    details.insert("externally owned source callable: \(signature.callableUSR)")
                }
                if !signature.externalLabelArgumentLocations.allSatisfy({ location in
                    callBindings.callsByAnchor[
                        CallSiteSyntax.Anchor(
                            callableUSR: signature.callableUSR,
                            location: location
                        )] != nil
                }) {
                    blockers.insert(.incompleteCallBindings)
                    details.insert(
                        "one or more call anchors are not ordinal-bound: \(signature.callableUSR)")
                }
                if signature.ownerCategory != .enumCase,
                    !signature.nonCallReferenceLocations.allSatisfy({ location in
                        referenceBindings.referencesByAnchor[
                            CallableReferenceSyntax.Anchor(
                                callableUSR: signature.callableUSR,
                                location: location
                            )
                        ] != nil
                    })
                {
                    blockers.insert(.incompleteCallableReferenceBindings)
                    details.insert(
                        "one or more callable-reference anchors are not ordinal-bound: "
                            + signature.callableUSR
                    )
                }
                for parameter in signature.parameters {
                    guard let role = parametersByUSR[parameter.parameterUSR],
                        externalLabelsAgree(
                            indexed: parameter.externalLabel, syntax: role.externalLabel)
                    else {
                        blockers.insert(.incompleteParameterSyntax)
                        details.insert(
                            "parameter declaration syntax is unavailable or disagrees: "
                                + parameter.parameterUSR
                        )
                        continue
                    }
                    if role.localBinding != nil,
                        !role.shadowingBindingDeclarations.isEmpty
                            || !role.implicitShadowingBindingNames.isEmpty
                    {
                        blockers.insert(.unsafeLocalBindingScope)
                        details.insert(
                            "parameter local binding is shadowed: \(parameter.parameterUSR)")
                    }
                    let tokens =
                        [role.externalLabel.token, role.localBinding]
                        .compactMap { $0 } + role.localBindingReferences
                    if tokens.contains(where: \.isBackticked) {
                        blockers.insert(.backtickedIdentifier)
                        details.insert(
                            "parameter uses a backticked identifier token: \(parameter.parameterUSR)"
                        )
                    }
                }
            }

            let constructorSignatures = signatures.filter {
                $0.callableKind == IndexSymbolKind.constructor.rawValue
            }
            if !constructorSignatures.isEmpty {
                let coveredOwnerUSRs = Set(
                    signatures.compactMap {
                        semanticIndex.nominalOwnerUSR(of: $0.callableUSR)
                    })
                for signature in constructorSignatures {
                    guard
                        let ownerUSR = semanticIndex.nominalOwnerUSR(
                            of: signature.callableUSR
                        )
                    else {
                        continue
                    }
                    let uncoveredDescendants =
                        semanticIndex
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

            var slots: [ExternalLabel.Slot] = []
            if let first = signatures.first {
                let parameterCounts = Set(signatures.map { $0.parameters.count })
                if parameterCounts.count != 1 {
                    blockers.insert(.inconsistentRelatedSignature)
                    details.insert("related callables expose different parameter counts")
                } else {
                    let orderedParametersBySignature = signatures.map { signature in
                        signature.parameters.sorted { $0.ordinal < $1.ordinal }
                    }
                    for ordinal in first.parameters.indices {
                        let parametersAtOrdinal = orderedParametersBySignature.map { $0[ordinal] }
                        guard parametersAtOrdinal.allSatisfy({ $0.ordinal == ordinal }) else {
                            blockers.insert(.inconsistentRelatedSignature)
                            details.insert("related callable parameter ordinals are not aligned")
                            continue
                        }
                        let labels = Set(parametersAtOrdinal.map(\.externalLabel))
                        guard labels.count == 1, let label = labels.first else {
                            blockers.insert(.inconsistentRelatedSignature)
                            details.insert(
                                "related callable external labels disagree at ordinal \(ordinal)")
                            continue
                        }
                        switch label {
                        case .named(let name):
                            if first.ownerCategory == .subscriptDeclaration,
                                name == "dynamicMember"
                            {
                                blockers.insert(.languageRequiredExternalLabel)
                                details.insert(
                                    "Swift dynamic-member lookup requires "
                                        + "subscript(dynamicMember:) at ordinal \(ordinal)"
                                )
                            }
                            if first.callableKind == IndexSymbolKind.constructor.rawValue,
                                name == "wrappedValue"
                            {
                                blockers.insert(.languageRequiredExternalLabel)
                                details.insert(
                                    "Swift property-wrapper initialization requires "
                                        + "init(wrappedValue:) at ordinal \(ordinal)"
                                )
                            }
                            slots.append(
                                ExternalLabel.Slot(
                                    ordinal: ordinal,
                                    originalLabel: name,
                                    parameterUSRs: Set(parametersAtOrdinal.map(\.parameterUSR))
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

            let labeledParameterUSRs = Set(
                signatures.flatMap { signature in
                    signature.parameters.compactMap { parameter -> String? in
                        if case .named = parameter.externalLabel {
                            return parameter.parameterUSR
                        }
                        return nil
                    }
                })
            let isProtocolRelated =
                signatures.contains(where: \.isProtocolRequirement)
                || !relatedCallableUSRs.isDisjoint(with: semanticIndex.protocolRequirementUSRs)
            let isOverrideRelated =
                relatedCallableUSRs.count > 1
                || signatures.contains(where: \.isOverrideRelated)

            return ExternalLabel.Family(
                key: relatedCallableUSRs.sorted().first
                    ?? signatures.first?.callableUSR
                    ?? "<empty-parameter-component>",
                relatedCallableUSRs: relatedCallableUSRs,
                signatures: signatures,
                slots: slots,
                labeledParameterUSRs: labeledParameterUSRs,
                isProtocolRelated: isProtocolRelated,
                isOverrideRelated: isOverrideRelated,
                blockers: blockers,
                blockerDetails: details.sorted()
            )
        }

        private static func externalLabelsAgree(
            indexed: ExternalLabel,
            syntax: ParameterSyntax.LabelRole
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

}
