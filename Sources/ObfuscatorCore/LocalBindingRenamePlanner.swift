import Foundation

extension LocalBindingRename {
    enum EditKind: Hashable, Sendable {
        case replaceIdentifier
        case insertBindingAfterExternalLabel
    }

    struct EditTemplate: Hashable, Sendable {
        let path: String
        let byteOffset: Int
        let length: Int
        let line: Int
        let utf8Column: Int
        let oldName: String
        let usr: String
        let kind: LocalBindingRename.EditKind

        func makeEdit(newName: String) -> SourcePatcher.Edit {
            SourcePatcher.Edit(
                path: path,
                byteOffset: byteOffset,
                length: length,
                line: line,
                utf8Column: utf8Column,
                oldName: oldName,
                newName: kind == .replaceIdentifier ? newName : " \(newName)",
                usr: usr
            )
        }
    }

    struct Rename: Sendable {
        let usr: String
        let oldName: String
        let editTemplates: Set<LocalBindingRename.EditTemplate>
    }

    struct Plan: Sendable {
        let renames: [LocalBindingRename.Rename]
        let rejections: [RenameEligibility]
    }

    /// Plans the local half of `external local:` parameters when the callable's
    /// external-label family must remain unchanged.
    ///
    /// IndexStoreDB decides which parameter USR and callable signature are in
    /// scope. SwiftSyntax contributes only compiler-anchored lexical binding
    /// ranges. No call-site label, callable full-name, or declaration label token
    /// is included in these planned renames.
    enum Planner {
        static func makePlan(
            candidateUSRs: Set<String>,
            groupsByUSR: [String: IndexSnapshot.OccurrenceGroup],
            semanticIndex: SemanticIndex,
            parametersByUSR: [String: ParameterSyntax.Parameter],
            analyzer: RenameEligibilityAnalyzer,
            sourceCache: SourceFileCache
        ) -> LocalBindingRename.Plan {
            var renames: [LocalBindingRename.Rename] = []
            var rejections: [RenameEligibility] = []

            for parameterUSR in candidateUSRs.sorted() {
                guard let group = groupsByUSR[parameterUSR] else {
                    continue
                }
                guard let roles = parametersByUSR[parameterUSR],
                    case .named(let externalLabel) = roles.externalLabel,
                    let localBinding = roles.localBinding
                else {
                    rejections.append(
                        makeRejection(
                            group: group,
                            oldName: group.symbol.name,
                            reasons: [
                                "parameter does not have a named external label and local binding"
                            ]
                        ))
                    continue
                }

                let decision = analyzer.analyze(
                    group: group,
                    sourceCache: sourceCache,
                    semanticIndex: semanticIndex,
                    overrideRelatedUSRs: semanticIndex.overrideRelatedUSRs,
                    localBindingOnlyParameterUSRs: candidateUSRs
                )
                guard decision.isEligible, decision.originalName == localBinding.name else {
                    rejections.append(
                        makeRejection(
                            group: group,
                            oldName: localBinding.name,
                            reasons: decision.isEligible
                                ? ["indexed parameter spelling disagrees with the local binding"]
                                : decision.reasons
                        ))
                    continue
                }

                var editTemplates: Set<LocalBindingRename.EditTemplate> = []
                var failures: Set<String> = []
                let sharedLabelAndBindingToken =
                    roles.hasSharedLabelAndBindingToken
                    ? externalLabel
                    : nil
                for occurrence in group.occurrences {
                    add(
                        occurrence: occurrence,
                        expectedName: localBinding.name,
                        parameterUSR: parameterUSR,
                        excluding: sharedLabelAndBindingToken,
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
                        excluding: sharedLabelAndBindingToken,
                        sourceCache: sourceCache,
                        editTemplates: &editTemplates,
                        failures: &failures
                    )
                }
                if let sharedLabelAndBindingToken {
                    addBindingInsertion(
                        after: sharedLabelAndBindingToken,
                        expectedName: localBinding.name,
                        parameterUSR: parameterUSR,
                        sourceCache: sourceCache,
                        editTemplates: &editTemplates,
                        failures: &failures
                    )
                }

                guard failures.isEmpty, !editTemplates.isEmpty else {
                    rejections.append(
                        makeRejection(
                            group: group,
                            oldName: localBinding.name,
                            reasons: failures.isEmpty
                                ? ["parameter local binding has no source replacements"]
                                : failures.sorted()
                        ))
                    continue
                }
                renames.append(
                    LocalBindingRename.Rename(
                        usr: parameterUSR,
                        oldName: localBinding.name,
                        editTemplates: editTemplates
                    ))
            }

            return LocalBindingRename.Plan(
                renames: renames.sorted { $0.usr < $1.usr },
                rejections: rejections.sorted { $0.usr < $1.usr }
            )
        }

        static func makeRejection(
            group: IndexSnapshot.OccurrenceGroup,
            oldName: String?,
            reasons: [String]
        ) -> RenameEligibility {
            RenameEligibility(
                usr: group.usr,
                symbolName: group.symbol.name,
                symbolKind: group.symbol.kind,
                isEligible: false,
                originalName: oldName,
                reasons: Array(Set(reasons)).sorted()
            )
        }

        private static func add(
            occurrence: IndexSnapshot.Occurrence,
            expectedName: String,
            parameterUSR: String,
            excluding excludedToken: SourceToken?,
            sourceCache: SourceFileCache,
            editTemplates: inout Set<LocalBindingRename.EditTemplate>,
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
                    "indexed parameter token mismatch at "
                        + "\(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
                )
                return
            }
            if let excludedToken,
                source.path == excludedToken.path,
                token.byteRange == excludedToken.byteRange
            {
                return
            }
            editTemplates.insert(
                LocalBindingRename.EditTemplate(
                    path: source.path,
                    byteOffset: token.byteRange.lowerBound,
                    length: token.byteRange.count,
                    line: occurrence.line,
                    utf8Column: occurrence.utf8Column,
                    oldName: expectedName,
                    usr: parameterUSR,
                    kind: .replaceIdentifier
                ))
        }

        private static func add(
            token: SourceToken,
            expectedName: String,
            parameterUSR: String,
            excluding excludedToken: SourceToken?,
            sourceCache: SourceFileCache,
            editTemplates: inout Set<LocalBindingRename.EditTemplate>,
            failures: inout Set<String>
        ) {
            guard isPlainSwiftIdentifier(expectedName),
                !token.isBackticked,
                token.name == expectedName,
                let source = sourceCache.file(for: token.path),
                source.text(in: token.byteRange) == expectedName,
                let location = source.sourceLocation(atByteOffset: token.byteRange.lowerBound)
            else {
                failures.insert(
                    "compiler syntax local-binding token mismatch at "
                        + "\(token.path):\(token.byteRange.lowerBound)"
                )
                return
            }
            if let excludedToken, isSameToken(token, excludedToken) {
                return
            }
            editTemplates.insert(
                LocalBindingRename.EditTemplate(
                    path: source.path,
                    byteOffset: token.byteRange.lowerBound,
                    length: token.byteRange.count,
                    line: location.line,
                    utf8Column: location.utf8Column,
                    oldName: expectedName,
                    usr: parameterUSR,
                    kind: .replaceIdentifier
                ))
        }

        private static func addBindingInsertion(
            after token: SourceToken,
            expectedName: String,
            parameterUSR: String,
            sourceCache: SourceFileCache,
            editTemplates: inout Set<LocalBindingRename.EditTemplate>,
            failures: inout Set<String>
        ) {
            guard isPlainSwiftIdentifier(expectedName),
                !token.isBackticked,
                token.name == expectedName,
                let source = sourceCache.file(for: token.path),
                source.text(in: token.byteRange) == expectedName,
                let location = source.sourceLocation(atByteOffset: token.byteRange.upperBound)
            else {
                failures.insert(
                    "compiler syntax shared-label token mismatch at "
                        + "\(token.path):\(token.byteRange.lowerBound)"
                )
                return
            }
            editTemplates.insert(
                LocalBindingRename.EditTemplate(
                    path: source.path,
                    byteOffset: token.byteRange.upperBound,
                    length: 0,
                    line: location.line,
                    utf8Column: location.utf8Column,
                    oldName: "",
                    usr: parameterUSR,
                    kind: .insertBindingAfterExternalLabel
                ))
        }

        private static func isSameToken(_ lhs: SourceToken, _ rhs: SourceToken) -> Bool {
            lhs.path == rhs.path && lhs.byteRange == rhs.byteRange
        }
    }

}
