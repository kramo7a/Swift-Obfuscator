import Foundation

struct ParameterExternalLabelReplacementTemplate: Hashable, Sendable {
    let path: String
    let byteOffset: Int
    let length: Int
    let line: Int
    let utf8Column: Int
    let oldName: String
    let usr: String

    func replacement(newName: String) -> SourceReplacement {
        SourceReplacement(
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

struct ParameterExternalLabelParameterRenameTemplate: Sendable {
    let usr: String
    let oldName: String
    let replacements: Set<ParameterExternalLabelReplacementTemplate>
}

struct ParameterExternalLabelOrdinalRenameTemplate: Sendable {
    let ordinal: Int
    let parameters: [ParameterExternalLabelParameterRenameTemplate]
}

struct ParameterExternalLabelComponentRenameTemplate: Sendable {
    let key: String
    let namedParameterUSRs: Set<String>
    let ordinals: [ParameterExternalLabelOrdinalRenameTemplate]
}

struct ParameterExternalLabelRenamePlanningResult: Sendable {
    let componentTemplates: [ParameterExternalLabelComponentRenameTemplate]
    let denied: [SafetyDecision]
}

enum ParameterExternalLabelRenamePlanning {
    static func makeResult(
        facts: ParameterExternalLabelComponentFacts,
        groupsByUSR: [String: USROccurrenceGroup],
        indexedFacts: IndexedSemanticFacts,
        parameterRolesByUSR: [String: ParameterDeclarationSyntaxRoles],
        callBindingFacts: ParameterCallArgumentBindingFacts,
        callableReferenceBindingFacts: ParameterCallableReferenceBindingFacts,
        analyzer: SafetyAnalyzer,
        sourceCache: SourceFileCache
    ) -> ParameterExternalLabelRenamePlanningResult {
        let eligibleParameterUSRs = Set(
            facts.components.filter(\.isEligible).flatMap(\.namedParameterUSRs)
        )
        let externalLabelOnlyParameterUSRs = Set(eligibleParameterUSRs.filter {
            parameterRolesByUSR[$0]?.localBinding == nil
        })
        var templates: [ParameterExternalLabelComponentRenameTemplate] = []
        var denied: [SafetyDecision] = []

        for component in facts.components {
            guard component.isEligible else {
                denied.append(contentsOf: denialDecisions(
                    component: component,
                    groupsByUSR: groupsByUSR,
                    reasons: component.blockerDetails.isEmpty
                        ? component.blockers.map(\.rawValue)
                        : component.blockerDetails
                ))
                continue
            }

            var failures: Set<String> = []
            var ordinalTemplates: [ParameterExternalLabelOrdinalRenameTemplate] = []
            for ordinalComponent in component.ordinalComponents.sorted(by: {
                $0.ordinal < $1.ordinal
            }) {
                var parameterTemplates: [ParameterExternalLabelParameterRenameTemplate] = []
                for parameterUSR in ordinalComponent.parameterUSRs.sorted() {
                    guard let group = groupsByUSR[parameterUSR] else {
                        failures.insert("parameter occurrence group unavailable: \(parameterUSR)")
                        continue
                    }
                    guard group.symbol.kind == "parameter" else {
                        failures.insert("component member is not a parameter: \(parameterUSR)")
                        continue
                    }
                    let matchingMembers = component.sourceCallableComponents.flatMap(\.members)
                        .filter { $0.parameterUSR == parameterUSR }
                    guard matchingMembers.count == 1, let member = matchingMembers.first else {
                        failures.insert("parameter member is missing or duplicated: \(parameterUSR)")
                        continue
                    }
                    guard member.ordinal == ordinalComponent.ordinal else {
                        failures.insert("parameter ordinal disagrees with component: \(parameterUSR)")
                        continue
                    }
                    guard let roles = parameterRolesByUSR[parameterUSR] else {
                        failures.insert("parameter syntax roles unavailable: \(parameterUSR)")
                        continue
                    }
                    guard case .named(let labelToken) = roles.externalLabel,
                          labelToken.name == ordinalComponent.originalLabel else {
                        failures.insert("external label syntax disagrees: \(parameterUSR)")
                        continue
                    }
                    if let localBinding = roles.localBinding {
                        guard localBinding.name == member.localBinding else {
                            failures.insert("indexed local binding disagrees with syntax: \(parameterUSR)")
                            continue
                        }
                    } else if member.localBinding != "_" {
                        failures.insert("missing local binding is not an indexed underscore: \(parameterUSR)")
                        continue
                    }

                    let decision = analyzer.analyze(
                        group: group,
                        sourceCache: sourceCache,
                        indexedFacts: indexedFacts,
                        overrideRelatedUSRs: indexedFacts.overrideRelatedUSRs,
                        coordinatedExternalLabelParameterUSRs: eligibleParameterUSRs,
                        externalLabelOnlyParameterUSRs: externalLabelOnlyParameterUSRs
                    )
                    guard decision.allowed else {
                        failures.insert(
                            "\(parameterUSR): \(decision.reasons.joined(separator: "; "))"
                        )
                        continue
                    }

                    let entryOldName = roles.localBinding?.name
                        ?? ordinalComponent.originalLabel
                    var replacements: Set<ParameterExternalLabelReplacementTemplate> = []
                    add(
                        token: labelToken,
                        expectedName: ordinalComponent.originalLabel,
                        parameterUSR: parameterUSR,
                        sourceCache: sourceCache,
                        replacements: &replacements,
                        failures: &failures
                    )

                    if let localBinding = roles.localBinding {
                        guard decision.oldName == localBinding.name else {
                            failures.insert("parameter occurrence spelling disagrees: \(parameterUSR)")
                            continue
                        }
                        for occurrence in group.occurrences {
                            add(
                                occurrence: occurrence,
                                expectedName: localBinding.name,
                                parameterUSR: parameterUSR,
                                sourceCache: sourceCache,
                                replacements: &replacements,
                                failures: &failures
                            )
                        }
                        for token in roles.localBindingTokens {
                            add(
                                token: token,
                                expectedName: localBinding.name,
                                parameterUSR: parameterUSR,
                                sourceCache: sourceCache,
                                replacements: &replacements,
                                failures: &failures
                            )
                        }
                    } else if decision.oldName != "_" {
                        failures.insert("external-label-only parameter anchor is not underscore: \(parameterUSR)")
                        continue
                    }

                    addCallSiteLabels(
                        component: component,
                        parameterUSR: parameterUSR,
                        ordinal: ordinalComponent.ordinal,
                        expectedName: ordinalComponent.originalLabel,
                        callBindingFacts: callBindingFacts,
                        sourceCache: sourceCache,
                        replacements: &replacements,
                        failures: &failures
                    )
                    addCallableReferenceLabels(
                        component: component,
                        parameterUSR: parameterUSR,
                        ordinal: ordinalComponent.ordinal,
                        expectedName: ordinalComponent.originalLabel,
                        bindingFacts: callableReferenceBindingFacts,
                        sourceCache: sourceCache,
                        replacements: &replacements,
                        failures: &failures
                    )
                    guard !replacements.isEmpty else {
                        failures.insert("parameter has no external-label replacements: \(parameterUSR)")
                        continue
                    }
                    parameterTemplates.append(ParameterExternalLabelParameterRenameTemplate(
                        usr: parameterUSR,
                        oldName: entryOldName,
                        replacements: replacements
                    ))
                }
                if parameterTemplates.count != ordinalComponent.parameterUSRs.count {
                    failures.insert(
                        "ordinal \(ordinalComponent.ordinal) is missing one or more parameter templates"
                    )
                }
                ordinalTemplates.append(ParameterExternalLabelOrdinalRenameTemplate(
                    ordinal: ordinalComponent.ordinal,
                    parameters: parameterTemplates.sorted { $0.usr < $1.usr }
                ))
            }

            guard failures.isEmpty else {
                denied.append(contentsOf: denialDecisions(
                    component: component,
                    groupsByUSR: groupsByUSR,
                    reasons: failures.sorted()
                ))
                continue
            }
            templates.append(ParameterExternalLabelComponentRenameTemplate(
                key: component.key,
                namedParameterUSRs: component.namedParameterUSRs,
                ordinals: ordinalTemplates
            ))
        }

        return ParameterExternalLabelRenamePlanningResult(
            componentTemplates: templates.sorted { $0.key < $1.key },
            denied: denied
        )
    }

    private static func addCallSiteLabels(
        component: ParameterExternalLabelRenameComponent,
        parameterUSR: String,
        ordinal: Int,
        expectedName: String,
        callBindingFacts: ParameterCallArgumentBindingFacts,
        sourceCache: SourceFileCache,
        replacements: inout Set<ParameterExternalLabelReplacementTemplate>,
        failures: inout Set<String>
    ) {
        for callable in component.sourceCallableComponents {
            for location in callable.callLocations {
                let anchor = ParameterCallSiteAnchor(
                    callableUSR: callable.callableUSR,
                    location: location
                )
                guard let bindings = callBindingFacts.bindingsByAnchor[anchor] else {
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
                            replacements: &replacements,
                            failures: &failures
                        )
                    }
                }
            }
        }
    }

    private static func addCallableReferenceLabels(
        component: ParameterExternalLabelRenameComponent,
        parameterUSR: String,
        ordinal: Int,
        expectedName: String,
        bindingFacts: ParameterCallableReferenceBindingFacts,
        sourceCache: SourceFileCache,
        replacements: inout Set<ParameterExternalLabelReplacementTemplate>,
        failures: inout Set<String>
    ) {
        for callable in component.sourceCallableComponents {
            for location in callable.nonCallReferenceLocations {
                let anchor = ParameterCallableReferenceAnchor(
                    callableUSR: callable.callableUSR,
                    location: location
                )
                guard let bindings = bindingFacts.bindingsByAnchor[anchor] else {
                    failures.insert("callable-reference binding unavailable: \(callable.callableUSR)")
                    continue
                }
                for binding in bindings.fullNameArguments
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
                        replacements: &replacements,
                        failures: &failures
                    )
                }
                for binding in bindings.subscriptArguments
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
                            replacements: &replacements,
                            failures: &failures
                        )
                    }
                }
            }
        }
    }

    private static func add(
        occurrence: OccurrenceRecord,
        expectedName: String,
        parameterUSR: String,
        sourceCache: SourceFileCache,
        replacements: inout Set<ParameterExternalLabelReplacementTemplate>,
        failures: inout Set<String>
    ) {
        guard let source = sourceCache.file(for: occurrence.path),
              let token = source.identifierToken(
                line: occurrence.line,
                utf8Column: occurrence.utf8Column
              ),
              token.name == expectedName else {
            failures.insert(
                "indexed parameter token mismatch at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
            )
            return
        }
        replacements.insert(ParameterExternalLabelReplacementTemplate(
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
        token: SourceTokenRange,
        expectedName: String,
        parameterUSR: String,
        sourceCache: SourceFileCache,
        replacements: inout Set<ParameterExternalLabelReplacementTemplate>,
        failures: inout Set<String>
    ) {
        guard isPlainSwiftArgumentLabel(expectedName),
              !token.isBackticked,
              token.name == expectedName,
              let source = sourceCache.file(for: token.path),
              source.text(in: token.byteRange) == expectedName,
              let location = source.sourceLocation(atByteOffset: token.byteRange.lowerBound) else {
            failures.insert(
                "compiler syntax token mismatch at \(token.path):\(token.byteRange.lowerBound)"
            )
            return
        }
        replacements.insert(ParameterExternalLabelReplacementTemplate(
            path: source.path,
            byteOffset: token.byteRange.lowerBound,
            length: token.byteRange.count,
            line: location.line,
            utf8Column: location.utf8Column,
            oldName: expectedName,
            usr: parameterUSR
        ))
    }

    static func denialDecisions(
        component: ParameterExternalLabelRenameComponent,
        groupsByUSR: [String: USROccurrenceGroup],
        reasons: [String]
    ) -> [SafetyDecision] {
        let uniqueReasons = Array(Set(reasons)).sorted()
        let visible = uniqueReasons.prefix(5).joined(separator: " | ")
        let remainder = uniqueReasons.count - min(uniqueReasons.count, 5)
        let suffix = remainder > 0 ? " | plus \(remainder) more blocker(s)" : ""
        let reason = "external argument-label component denied atomically (\(visible)\(suffix))"
        return component.namedParameterUSRs.sorted().compactMap { usr in
            guard let group = groupsByUSR[usr] else {
                return nil
            }
            return SafetyDecision(
                usr: usr,
                symbolName: group.symbol.name,
                kind: group.symbol.kind,
                allowed: false,
                oldName: group.symbol.name,
                reasons: [reason]
            )
        }
    }
}
