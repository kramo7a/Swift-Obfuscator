import Foundation

enum EnumCaseRename {
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

    struct Member: Sendable {
        let usr: String
        let oldName: String
        let editTemplates: Set<EnumCaseRename.EditTemplate>
    }

    struct Owner: Sendable {
        let ownerUSR: String
        let members: [EnumCaseRename.Member]
    }

    struct Plan: Sendable {
        let owners: [EnumCaseRename.Owner]
        let rejections: [RenameEligibility]
    }

    enum Planner {
        static func makePlan(
            syntax: EnumCaseSyntax.Index,
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
            semanticIndex: SemanticIndex,
            analyzer: RenameEligibilityAnalyzer,
            sourceCache: SourceFileCache,
            handledCaseUSRs: Set<String> = []
        ) -> EnumCaseRename.Plan {
            let eligibleCaseUSRs = Set(
                syntax.owners.flatMap { owner in
                    owner.preliminaryEligibleMembers.map(\.caseUSR)
                }
            ).subtracting(handledCaseUSRs)
            var owners: [EnumCaseRename.Owner] = []
            var rejections: [RenameEligibility] = []

            for owner in syntax.owners {
                let unhandledMembers = owner.members.filter {
                    !handledCaseUSRs.contains($0.caseUSR)
                }
                guard !unhandledMembers.isEmpty else {
                    continue
                }
                guard owner.blockers.isEmpty else {
                    rejections.append(
                        contentsOf: makeRejections(
                            owner: owner,
                            members: unhandledMembers,
                            groupsByUSR: groupsByUSR,
                            reasons: owner.blockers.map { "enum case blocker: \($0.rawValue)" }
                        ))
                    continue
                }

                let blockedMembers = unhandledMembers.filter {
                    !$0.isPreliminaryEligible
                }
                for member in blockedMembers {
                    rejections.append(
                        contentsOf: makeRejections(
                            owner: owner,
                            members: [member],
                            groupsByUSR: groupsByUSR,
                            reasons: member.blockers.map { "enum case blocker: \($0.rawValue)" }
                        ))
                }
                let candidateMembers = owner.preliminaryEligibleMembers.filter {
                    !handledCaseUSRs.contains($0.caseUSR)
                }
                guard !candidateMembers.isEmpty else {
                    continue
                }

                var failures: Set<String> = []
                var memberRenames: [EnumCaseRename.Member] = []
                for member in candidateMembers {
                    let result = makeMemberRename(
                        member: member,
                        groupsByUSR: groupsByUSR,
                        semanticIndex: semanticIndex,
                        analyzer: analyzer,
                        sourceCache: sourceCache,
                        coordinatedEnumCaseUSRs: eligibleCaseUSRs
                    )
                    failures.formUnion(result.failures)
                    if let rename = result.rename {
                        memberRenames.append(rename)
                    }
                }

                if memberRenames.count != candidateMembers.count {
                    failures.insert(
                        "enum owner candidate subset is missing one or more member templates")
                }
                guard failures.isEmpty else {
                    rejections.append(
                        contentsOf: makeRejections(
                            owner: owner,
                            members: candidateMembers,
                            groupsByUSR: groupsByUSR,
                            reasons: failures.sorted()
                        ))
                    continue
                }
                owners.append(
                    EnumCaseRename.Owner(
                        ownerUSR: owner.ownerUSR,
                        members: memberRenames.sorted { $0.usr < $1.usr }
                    ))
            }

            return EnumCaseRename.Plan(
                owners: owners.sorted { $0.ownerUSR < $1.ownerUSR },
                rejections: rejections
            )
        }

        static func makeMemberRename(
            member: EnumCaseSyntax.Member,
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
            semanticIndex: SemanticIndex,
            analyzer: RenameEligibilityAnalyzer,
            sourceCache: SourceFileCache,
            coordinatedEnumCaseUSRs: Set<String>
        ) -> (rename: EnumCaseRename.Member?, failures: Set<String>) {
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
                semanticIndex: semanticIndex,
                overrideRelatedUSRs: semanticIndex.overrideRelatedUSRs,
                coordinatedEnumCaseUSRs: coordinatedEnumCaseUSRs
            )
            guard decision.isEligible, decision.originalName == declarationToken.name else {
                let details = decision.reasons.joined(separator: "; ")
                failures.insert(
                    "\(member.caseUSR): enum case safety analysis disagrees with syntax: \(details)"
                )
                return (nil, failures)
            }

            var editTemplates: Set<EnumCaseRename.EditTemplate> = []
            add(
                token: declarationToken,
                expectedName: declarationToken.name,
                usr: member.caseUSR,
                sourceCache: sourceCache,
                editTemplates: &editTemplates,
                failures: &failures
            )
            for reference in member.references {
                add(
                    token: reference.token,
                    expectedName: declarationToken.name,
                    usr: member.caseUSR,
                    sourceCache: sourceCache,
                    editTemplates: &editTemplates,
                    failures: &failures
                )
            }

            let syntaxAnchors = Set(editTemplates.map { "\($0.path):\($0.byteOffset)" })
            for occurrence in group.occurrences where !occurrence.hasRole(.implicit) {
                guard let source = sourceCache.file(for: occurrence.path),
                    let token = source.identifierToken(
                        line: occurrence.line,
                        utf8Column: occurrence.utf8Column
                    )
                else {
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

            guard failures.isEmpty, !editTemplates.isEmpty else {
                if editTemplates.isEmpty {
                    failures.insert("enum case has no source replacements: \(member.caseUSR)")
                }
                return (nil, failures)
            }
            return (
                EnumCaseRename.Member(
                    usr: member.caseUSR,
                    oldName: declarationToken.name,
                    editTemplates: editTemplates
                ), []
            )
        }

        static func makeRejections(
            owner: EnumCaseSyntax.Owner,
            members selectedMembers: [EnumCaseSyntax.Member]? = nil,
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
            reasons: [String]
        ) -> [RenameEligibility] {
            let members = selectedMembers ?? owner.members
            let scope =
                members.count == owner.members.count
                ? "enum case owner component \(owner.ownerUSR) denied atomically"
                : "enum case candidate subset in owner \(owner.ownerUSR) denied atomically"
            let componentReason =
                scope + ": "
                + (reasons.isEmpty ? "unspecified safety failure" : reasons.joined(separator: "; "))
            return members.map { member in
                let group = groupsByUSR[member.caseUSR]
                return RenameEligibility(
                    usr: member.caseUSR,
                    symbolName: group?.symbol.name ?? member.declarationToken?.name
                        ?? member.caseUSR,
                    symbolKind: group?.symbol.kind ?? IndexSymbolKind.enumConstant.rawValue,
                    isEligible: false,
                    originalName: member.declarationToken?.name,
                    reasons: [componentReason]
                )
            }
        }

        static func add(
            token: SourceToken,
            expectedName: String,
            usr: String,
            sourceCache: SourceFileCache,
            editTemplates: inout Set<EnumCaseRename.EditTemplate>,
            failures: inout Set<String>
        ) {
            guard token.name == expectedName,
                isPlainSwiftArgumentLabel(token.name),
                let source = sourceCache.file(for: token.path),
                source.text(in: token.byteRange) == expectedName
            else {
                failures.insert(
                    "enum case syntax token mismatch at \(token.path):\(token.byteRange.lowerBound)"
                )
                return
            }
            guard let location = source.sourceLocation(atByteOffset: token.byteRange.lowerBound)
            else {
                failures.insert(
                    "enum case source location unavailable at \(token.path):\(token.byteRange.lowerBound)"
                )
                return
            }
            editTemplates.insert(
                EnumCaseRename.EditTemplate(
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

}
