import Foundation

struct EnumCaseReplacementTemplate: Hashable, Sendable {
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

struct EnumCaseMemberRenameTemplate: Sendable {
    let usr: String
    let oldName: String
    let replacements: Set<EnumCaseReplacementTemplate>
}

struct EnumCaseOwnerRenameTemplate: Sendable {
    let ownerUSR: String
    let members: [EnumCaseMemberRenameTemplate]
}

struct EnumCaseRenamePlanningResult: Sendable {
    let componentTemplates: [EnumCaseOwnerRenameTemplate]
    let denied: [SafetyDecision]
}

enum EnumCaseRenamePlanning {
    static func makeResult(
        facts: EnumCaseSyntaxFacts,
        groupsByUSR: [String: USROccurrenceGroup],
        indexedFacts: IndexedSemanticFacts,
        analyzer: SafetyAnalyzer,
        sourceCache: SourceFileCache,
        handledCaseUSRs: Set<String> = []
    ) -> EnumCaseRenamePlanningResult {
        let eligibleCaseUSRs = Set(
            facts.components.flatMap { component in
                component.preliminaryEligibleMembers.map(\.caseUSR)
            }
        ).subtracting(handledCaseUSRs)
        var componentTemplates: [EnumCaseOwnerRenameTemplate] = []
        var denied: [SafetyDecision] = []

        for component in facts.components {
            let unhandledMembers = component.members.filter {
                !handledCaseUSRs.contains($0.caseUSR)
            }
            guard !unhandledMembers.isEmpty else {
                continue
            }
            guard component.blockers.isEmpty else {
                denied.append(contentsOf: denialDecisions(
                    component: component,
                    members: unhandledMembers,
                    groupsByUSR: groupsByUSR,
                    reasons: component.blockers.map { "enum case blocker: \($0.rawValue)" }
                ))
                continue
            }

            let blockedMembers = unhandledMembers.filter {
                !$0.isPreliminaryEligible
            }
            for member in blockedMembers {
                denied.append(contentsOf: denialDecisions(
                    component: component,
                    members: [member],
                    groupsByUSR: groupsByUSR,
                    reasons: member.blockers.map { "enum case blocker: \($0.rawValue)" }
                ))
            }
            let candidateMembers = component.preliminaryEligibleMembers.filter {
                !handledCaseUSRs.contains($0.caseUSR)
            }
            guard !candidateMembers.isEmpty else {
                continue
            }

            var failures: Set<String> = []
            var memberTemplates: [EnumCaseMemberRenameTemplate] = []
            for member in candidateMembers {
                let result = memberTemplate(
                    member: member,
                    groupsByUSR: groupsByUSR,
                    indexedFacts: indexedFacts,
                    analyzer: analyzer,
                    sourceCache: sourceCache,
                    coordinatedEnumCaseUSRs: eligibleCaseUSRs
                )
                failures.formUnion(result.failures)
                if let template = result.template {
                    memberTemplates.append(template)
                }
            }

            if memberTemplates.count != candidateMembers.count {
                failures.insert("enum owner candidate subset is missing one or more member templates")
            }
            guard failures.isEmpty else {
                denied.append(contentsOf: denialDecisions(
                    component: component,
                    members: candidateMembers,
                    groupsByUSR: groupsByUSR,
                    reasons: failures.sorted()
                ))
                continue
            }
            componentTemplates.append(EnumCaseOwnerRenameTemplate(
                ownerUSR: component.ownerUSR,
                members: memberTemplates.sorted { $0.usr < $1.usr }
            ))
        }

        return EnumCaseRenamePlanningResult(
            componentTemplates: componentTemplates.sorted { $0.ownerUSR < $1.ownerUSR },
            denied: denied
        )
    }

    static func memberTemplate(
        member: EnumCaseMemberSyntaxFact,
        groupsByUSR: [String: USROccurrenceGroup],
        indexedFacts: IndexedSemanticFacts,
        analyzer: SafetyAnalyzer,
        sourceCache: SourceFileCache,
        coordinatedEnumCaseUSRs: Set<String>
    ) -> (template: EnumCaseMemberRenameTemplate?, failures: Set<String>) {
        var failures: Set<String> = []
        guard let group = groupsByUSR[member.caseUSR] else {
            failures.insert("enum case occurrence group unavailable: \(member.caseUSR)")
            return (nil, failures)
        }
        guard group.symbol.isKind(.enumConstant) else {
            failures.insert("component member is not an enum case: \(member.caseUSR)")
            return (nil, failures)
        }
        guard let declarationToken = member.declarationToken else {
            failures.insert("enum case declaration syntax unavailable: \(member.caseUSR)")
            return (nil, failures)
        }

        let decision = analyzer.analyze(
            group: group,
            sourceCache: sourceCache,
            indexedFacts: indexedFacts,
            overrideRelatedUSRs: indexedFacts.overrideRelatedUSRs,
            coordinatedEnumCaseUSRs: coordinatedEnumCaseUSRs
        )
        guard decision.allowed, decision.oldName == declarationToken.name else {
            let details = decision.reasons.joined(separator: "; ")
            failures.insert(
                "\(member.caseUSR): enum case safety analysis disagrees with syntax: \(details)"
            )
            return (nil, failures)
        }

        var replacements: Set<EnumCaseReplacementTemplate> = []
        add(
            token: declarationToken,
            expectedName: declarationToken.name,
            usr: member.caseUSR,
            sourceCache: sourceCache,
            replacements: &replacements,
            failures: &failures
        )
        for reference in member.references {
            add(
                token: reference.token,
                expectedName: declarationToken.name,
                usr: member.caseUSR,
                sourceCache: sourceCache,
                replacements: &replacements,
                failures: &failures
            )
        }

        let syntaxAnchors = Set(replacements.map { "\($0.path):\($0.byteOffset)" })
        for occurrence in group.occurrences where !occurrence.hasRole(.implicit) {
            guard let source = sourceCache.file(for: occurrence.path),
                  let token = source.identifierToken(
                    line: occurrence.line,
                    utf8Column: occurrence.utf8Column
                  ) else {
                failures.insert(
                    "indexed enum case token unavailable at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
                continue
            }
            let anchor = "\(source.path):\(token.byteRange.lowerBound)"
            if token.name != declarationToken.name || !syntaxAnchors.contains(anchor) {
                failures.insert(
                    "indexed enum case occurrence lacks an exact syntax anchor at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
            }
        }

        guard failures.isEmpty, !replacements.isEmpty else {
            if replacements.isEmpty {
                failures.insert("enum case has no source replacements: \(member.caseUSR)")
            }
            return (nil, failures)
        }
        return (EnumCaseMemberRenameTemplate(
            usr: member.caseUSR,
            oldName: declarationToken.name,
            replacements: replacements
        ), [])
    }

    static func denialDecisions(
        component: EnumCaseOwnerSyntaxComponent,
        members selectedMembers: [EnumCaseMemberSyntaxFact]? = nil,
        groupsByUSR: [String: USROccurrenceGroup],
        reasons: [String]
    ) -> [SafetyDecision] {
        let members = selectedMembers ?? component.members
        let scope = members.count == component.members.count
            ? "enum case owner component \(component.ownerUSR) denied atomically"
            : "enum case candidate subset in owner \(component.ownerUSR) denied atomically"
        let componentReason = scope + ": "
            + (reasons.isEmpty ? "unspecified safety failure" : reasons.joined(separator: "; "))
        return members.map { member in
            let group = groupsByUSR[member.caseUSR]
            return SafetyDecision(
                usr: member.caseUSR,
                symbolName: group?.symbol.name ?? member.declarationToken?.name ?? member.caseUSR,
                kind: group?.symbol.kind ?? IndexSymbolKind.enumConstant.rawValue,
                allowed: false,
                oldName: member.declarationToken?.name,
                reasons: [componentReason]
            )
        }
    }

    static func add(
        token: SourceTokenRange,
        expectedName: String,
        usr: String,
        sourceCache: SourceFileCache,
        replacements: inout Set<EnumCaseReplacementTemplate>,
        failures: inout Set<String>
    ) {
        guard token.name == expectedName,
              isPlainSwiftArgumentLabel(token.name),
              let source = sourceCache.file(for: token.path),
              source.text(in: token.byteRange) == expectedName else {
            failures.insert(
                "enum case syntax token mismatch at \(token.path):\(token.byteRange.lowerBound)"
            )
            return
        }
        guard let location = source.sourceLocation(atByteOffset: token.byteRange.lowerBound) else {
            failures.insert(
                "enum case source location unavailable at \(token.path):\(token.byteRange.lowerBound)"
            )
            return
        }
        replacements.insert(EnumCaseReplacementTemplate(
            path: source.path,
            byteOffset: token.byteRange.lowerBound,
            length: token.byteRange.count,
            line: location.line,
            utf8Column: location.utf8Column,
            oldName: expectedName,
            usr: usr
        ))
    }
}
