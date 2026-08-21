import Foundation

extension ExternalLabel {
    struct EditTemplate: Hashable, Sendable {
        let path: String
        let byteOffset: Int
        let length: Int
        let line: Int
        let utf8Column: Int
        let oldName: String
        let usr: String

        func makeEdit(newName: String) -> SourcePatcher.Edit {
            SourcePatcher.Edit(
                path: path,
                byteOffset: byteOffset,
                length: length,
                line: line,
                utf8Column: utf8Column,
                oldName: oldName,
                newName: newName,
                usr: usr
            )
        }
    }

    struct ParameterRename: Sendable {
        let usr: String
        let oldName: String
        let editTemplates: Set<ExternalLabel.EditTemplate>
    }

    struct SlotRename: Sendable {
        let ordinal: Int
        let parameters: [ExternalLabel.ParameterRename]
    }

    struct FamilyRename: Sendable {
        let key: String
        let labeledParameterUSRs: Set<String>
        let slots: [ExternalLabel.SlotRename]
    }

    struct Plan: Sendable {
        let families: [ExternalLabel.FamilyRename]
        let rejections: [RenameEligibility]
    }

    enum Planner {
        static func makePlan(
            analysis: ExternalLabel.Analysis,
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
            semanticIndex: SemanticIndex,
            parametersByUSR: [String: ParameterSyntax.Parameter],
            callBindings: CallArgumentBinding.Index,
            referenceBindings: CallableReferenceBinding.Index,
            analyzer: RenameEligibilityAnalyzer,
            sourceCache: SourceFileCache
        ) -> ExternalLabel.Plan {
            let eligibleParameterUSRs = Set(
                analysis.families.filter(\.isEligible).flatMap(\.labeledParameterUSRs)
            )
            let externalLabelOnlyParameterUSRs = Set(
                eligibleParameterUSRs.filter {
                    parametersByUSR[$0]?.localBinding == nil
                })
            var familyRenames: [ExternalLabel.FamilyRename] = []
            var rejections: [RenameEligibility] = []

            for family in analysis.families {
                guard family.isEligible else {
                    rejections.append(
                        contentsOf: makeRejections(
                            family: family,
                            groupsByUSR: groupsByUSR,
                            reasons: family.blockerDetails.isEmpty
                                ? family.blockers.map(\.rawValue)
                                : family.blockerDetails
                        ))
                    continue
                }

                var failures: Set<String> = []
                var slotRenames: [ExternalLabel.SlotRename] = []
                for slot in family.slots.sorted(by: {
                    $0.ordinal < $1.ordinal
                }) {
                    var parameterRenames: [ExternalLabel.ParameterRename] = []
                    for parameterUSR in slot.parameterUSRs.sorted() {
                        guard let group = groupsByUSR[parameterUSR] else {
                            failures.insert(
                                "parameter occurrence group unavailable: \(parameterUSR)")
                            continue
                        }
                        guard group.symbol.isKind(.parameter) else {
                            failures.insert("component member is not a parameter: \(parameterUSR)")
                            continue
                        }
                        let matchingMembers = family.signatures.flatMap(\.parameters)
                            .filter { $0.parameterUSR == parameterUSR }
                        guard matchingMembers.count == 1, let member = matchingMembers.first else {
                            failures.insert(
                                "parameter member is missing or duplicated: \(parameterUSR)")
                            continue
                        }
                        guard member.ordinal == slot.ordinal else {
                            failures.insert(
                                "parameter ordinal disagrees with component: \(parameterUSR)")
                            continue
                        }
                        guard let roles = parametersByUSR[parameterUSR] else {
                            failures.insert("parameter syntax roles unavailable: \(parameterUSR)")
                            continue
                        }
                        guard case .named(let labelToken) = roles.externalLabel,
                            labelToken.name == slot.originalLabel
                        else {
                            failures.insert("external label syntax disagrees: \(parameterUSR)")
                            continue
                        }
                        if let localBinding = roles.localBinding {
                            guard localBinding.name == member.localBinding else {
                                failures.insert(
                                    "indexed local binding disagrees with syntax: \(parameterUSR)")
                                continue
                            }
                        } else if member.localBinding != "_" {
                            failures.insert(
                                "missing local binding is not an indexed underscore: \(parameterUSR)"
                            )
                            continue
                        }

                        let decision = analyzer.analyze(
                            group: group,
                            sourceCache: sourceCache,
                            semanticIndex: semanticIndex,
                            overrideRelatedUSRs: semanticIndex.overrideRelatedUSRs,
                            coordinatedExternalLabelParameterUSRs: eligibleParameterUSRs,
                            externalLabelOnlyParameterUSRs: externalLabelOnlyParameterUSRs
                        )
                        guard decision.isEligible else {
                            failures.insert(
                                "\(parameterUSR): \(decision.reasons.joined(separator: "; "))"
                            )
                            continue
                        }

                        let entryOldName =
                            roles.localBinding?.name
                            ?? slot.originalLabel
                        var editTemplates: Set<ExternalLabel.EditTemplate> = []
                        add(
                            token: labelToken,
                            expectedName: slot.originalLabel,
                            parameterUSR: parameterUSR,
                            sourceCache: sourceCache,
                            editTemplates: &editTemplates,
                            failures: &failures
                        )

                        if let localBinding = roles.localBinding {
                            guard decision.originalName == localBinding.name else {
                                failures.insert(
                                    "parameter occurrence spelling disagrees: \(parameterUSR)")
                                continue
                            }
                            for occurrence in group.occurrences {
                                add(
                                    occurrence: occurrence,
                                    expectedName: localBinding.name,
                                    parameterUSR: parameterUSR,
                                    sourceCache: sourceCache,
                                    editTemplates: &editTemplates,
                                    failures: &failures
                                )
                            }
                            for token in roles.localBindingTokens {
                                add(
                                    token: token,
                                    expectedName: localBinding.name,
                                    parameterUSR: parameterUSR,
                                    sourceCache: sourceCache,
                                    editTemplates: &editTemplates,
                                    failures: &failures
                                )
                            }
                        } else if decision.originalName != "_" {
                            failures.insert(
                                "external-label-only parameter anchor is not underscore: \(parameterUSR)"
                            )
                            continue
                        }

                        addCallSiteLabels(
                            family: family,
                            parameterUSR: parameterUSR,
                            ordinal: slot.ordinal,
                            expectedName: slot.originalLabel,
                            callBindings: callBindings,
                            sourceCache: sourceCache,
                            editTemplates: &editTemplates,
                            failures: &failures
                        )
                        addCallableReferenceLabels(
                            family: family,
                            parameterUSR: parameterUSR,
                            ordinal: slot.ordinal,
                            expectedName: slot.originalLabel,
                            referenceBindings: referenceBindings,
                            sourceCache: sourceCache,
                            editTemplates: &editTemplates,
                            failures: &failures
                        )
                        guard !editTemplates.isEmpty else {
                            failures.insert(
                                "parameter has no external-label replacements: \(parameterUSR)")
                            continue
                        }
                        parameterRenames.append(
                            ExternalLabel.ParameterRename(
                                usr: parameterUSR,
                                oldName: entryOldName,
                                editTemplates: editTemplates
                            ))
                    }
                    if parameterRenames.count != slot.parameterUSRs.count {
                        failures.insert(
                            "ordinal \(slot.ordinal) is missing one or more parameter templates"
                        )
                    }
                    slotRenames.append(
                        ExternalLabel.SlotRename(
                            ordinal: slot.ordinal,
                            parameters: parameterRenames.sorted { $0.usr < $1.usr }
                        ))
                }

                guard failures.isEmpty else {
                    rejections.append(
                        contentsOf: makeRejections(
                            family: family,
                            groupsByUSR: groupsByUSR,
                            reasons: failures.sorted()
                        ))
                    continue
                }
                familyRenames.append(
                    ExternalLabel.FamilyRename(
                        key: family.key,
                        labeledParameterUSRs: family.labeledParameterUSRs,
                        slots: slotRenames
                    ))
            }

            return ExternalLabel.Plan(
                families: familyRenames.sorted { $0.key < $1.key },
                rejections: rejections
            )
        }

        private static func addCallSiteLabels(
            family: ExternalLabel.Family,
            parameterUSR: String,
            ordinal: Int,
            expectedName: String,
            callBindings: CallArgumentBinding.Index,
            sourceCache: SourceFileCache,
            editTemplates: inout Set<ExternalLabel.EditTemplate>,
            failures: inout Set<String>
        ) {
            for callable in family.signatures {
                for location in callable.externalLabelArgumentLocations {
                    let anchor = CallSiteSyntax.Anchor(
                        callableUSR: callable.callableUSR,
                        location: location
                    )
                    guard let bindings = callBindings.callsByAnchor[anchor] else {
                        failures.insert("call binding unavailable: \(callable.callableUSR)")
                        continue
                    }
                    for binding in bindings.arguments where binding.parameterUSR == parameterUSR {
                        guard binding.parameterOrdinal == ordinal else {
                            failures.insert("call binding ordinal disagrees: \(parameterUSR)")
                            continue
                        }
                        if let token = binding.syntaxRole.labelToken {
                            add(
                                token: token,
                                expectedName: expectedName,
                                parameterUSR: parameterUSR,
                                sourceCache: sourceCache,
                                editTemplates: &editTemplates,
                                failures: &failures
                            )
                        }
                    }
                }
            }
        }

        private static func addCallableReferenceLabels(
            family: ExternalLabel.Family,
            parameterUSR: String,
            ordinal: Int,
            expectedName: String,
            referenceBindings: CallableReferenceBinding.Index,
            sourceCache: SourceFileCache,
            editTemplates: inout Set<ExternalLabel.EditTemplate>,
            failures: inout Set<String>
        ) {
            for callable in family.signatures {
                guard callable.ownerCategory != .enumCase else {
                    continue
                }
                for location in callable.nonCallReferenceLocations {
                    let anchor = CallableReferenceSyntax.Anchor(
                        callableUSR: callable.callableUSR,
                        location: location
                    )
                    guard let boundReference = referenceBindings.referencesByAnchor[anchor] else {
                        failures.insert(
                            "callable-reference binding unavailable: \(callable.callableUSR)")
                        continue
                    }
                    for binding in boundReference.fullNameArguments
                    where binding.parameterUSR == parameterUSR {
                        guard binding.parameterOrdinal == ordinal else {
                            failures.insert("full-name binding ordinal disagrees: \(parameterUSR)")
                            continue
                        }
                        add(
                            token: binding.token,
                            expectedName: expectedName,
                            parameterUSR: parameterUSR,
                            sourceCache: sourceCache,
                            editTemplates: &editTemplates,
                            failures: &failures
                        )
                    }
                    for binding in boundReference.subscriptArguments
                    where binding.parameterUSR == parameterUSR {
                        guard binding.parameterOrdinal == ordinal else {
                            failures.insert("subscript binding ordinal disagrees: \(parameterUSR)")
                            continue
                        }
                        if let token = binding.syntaxRole.labelToken {
                            add(
                                token: token,
                                expectedName: expectedName,
                                parameterUSR: parameterUSR,
                                sourceCache: sourceCache,
                                editTemplates: &editTemplates,
                                failures: &failures
                            )
                        }
                    }
                }
            }
        }

        private static func add(
            occurrence: IndexSnapshot.Occurrence,
            expectedName: String,
            parameterUSR: String,
            sourceCache: SourceFileCache,
            editTemplates: inout Set<ExternalLabel.EditTemplate>,
            failures: inout Set<String>
        ) {
            guard let source = sourceCache.file(for: occurrence.path),
                let token = source.identifierToken(
                    line: occurrence.line,
                    utf8Column: occurrence.utf8Column
                ),
                token.name == expectedName
            else {
                failures.insert(
                    "indexed parameter token mismatch at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
                return
            }
            editTemplates.insert(
                ExternalLabel.EditTemplate(
                    path: source.path,
                    byteOffset: token.byteRange.lowerBound,
                    length: token.byteRange.count,
                    line: occurrence.line,
                    utf8Column: occurrence.utf8Column,
                    oldName: expectedName,
                    usr: parameterUSR
                ))
        }

        private static func add(
            token: SourceToken,
            expectedName: String,
            parameterUSR: String,
            sourceCache: SourceFileCache,
            editTemplates: inout Set<ExternalLabel.EditTemplate>,
            failures: inout Set<String>
        ) {
            guard isPlainSwiftArgumentLabel(expectedName),
                !token.isBackticked,
                token.name == expectedName,
                let source = sourceCache.file(for: token.path),
                source.text(in: token.byteRange) == expectedName,
                let location = source.sourceLocation(atByteOffset: token.byteRange.lowerBound)
            else {
                failures.insert(
                    "compiler syntax token mismatch at \(token.path):\(token.byteRange.lowerBound)"
                )
                return
            }
            editTemplates.insert(
                ExternalLabel.EditTemplate(
                    path: source.path,
                    byteOffset: token.byteRange.lowerBound,
                    length: token.byteRange.count,
                    line: location.line,
                    utf8Column: location.utf8Column,
                    oldName: expectedName,
                    usr: parameterUSR
                ))
        }

        static func makeRejections(
            family: ExternalLabel.Family,
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
            reasons: [String]
        ) -> [RenameEligibility] {
            let uniqueReasons = Array(Set(reasons)).sorted()
            let visible = uniqueReasons.prefix(5).joined(separator: " | ")
            let remainder = uniqueReasons.count - min(uniqueReasons.count, 5)
            let suffix = remainder > 0 ? " | plus \(remainder) more blocker(s)" : ""
            let reason = "external argument-label component denied atomically (\(visible)\(suffix))"
            return family.labeledParameterUSRs.sorted().compactMap { usr in
                guard let group = groupsByUSR[usr] else {
                    return nil
                }
                return RenameEligibility(
                    usr: usr,
                    symbolName: group.symbol.name,
                    symbolKind: group.symbol.kind,
                    isEligible: false,
                    originalName: group.symbol.name,
                    reasons: [reason]
                )
            }
        }
    }

}
