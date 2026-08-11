import Foundation

struct ParameterLocalBindingReplacementTemplate: Hashable, Sendable {
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

struct ParameterLocalBindingRenameTemplate: Sendable {
    let usr: String
    let oldName: String
    let replacements: Set<ParameterLocalBindingReplacementTemplate>
}

struct ParameterLocalBindingRenamePlanningResult: Sendable {
    let templates: [ParameterLocalBindingRenameTemplate]
    let denied: [SafetyDecision]
}

/// Plans the local half of `external local:` parameters when the callable's
/// external-label component must remain unchanged.
///
/// IndexStoreDB decides which parameter USR and callable component are in
/// scope. SwiftSyntax contributes only compiler-anchored lexical binding
/// ranges. No call-site label, callable full-name, or declaration label token
/// is included in these templates.
enum ParameterLocalBindingRenamePlanning {
    static func makeResult(
        candidateUSRs: Set<String>,
        groupsByUSR: [String: USROccurrenceGroup],
        indexedFacts: IndexedSemanticFacts,
        parameterRolesByUSR: [String: ParameterDeclarationSyntaxRoles],
        analyzer: SafetyAnalyzer,
        sourceCache: SourceFileCache
    ) -> ParameterLocalBindingRenamePlanningResult {
        var templates: [ParameterLocalBindingRenameTemplate] = []
        var denied: [SafetyDecision] = []

        for parameterUSR in candidateUSRs.sorted() {
            guard let group = groupsByUSR[parameterUSR] else {
                continue
            }
            guard let roles = parameterRolesByUSR[parameterUSR],
                  case .named = roles.externalLabel,
                  let localBinding = roles.localBinding,
                  !roles.sharesLabelAndBindingToken else {
                denied.append(denialDecision(
                    group: group,
                    oldName: group.symbol.name,
                    reasons: ["parameter does not have independent external-label and local-binding tokens"]
                ))
                continue
            }

            let decision = analyzer.analyze(
                group: group,
                sourceCache: sourceCache,
                indexedFacts: indexedFacts,
                overrideRelatedUSRs: indexedFacts.overrideRelatedUSRs,
                localBindingOnlyParameterUSRs: candidateUSRs
            )
            guard decision.allowed, decision.oldName == localBinding.name else {
                denied.append(denialDecision(
                    group: group,
                    oldName: localBinding.name,
                    reasons: decision.allowed
                        ? ["indexed parameter spelling disagrees with the local binding"]
                        : decision.reasons
                ))
                continue
            }

            var replacements: Set<ParameterLocalBindingReplacementTemplate> = []
            var failures: Set<String> = []
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

            guard failures.isEmpty, !replacements.isEmpty else {
                denied.append(denialDecision(
                    group: group,
                    oldName: localBinding.name,
                    reasons: failures.isEmpty
                        ? ["parameter local binding has no source replacements"]
                        : failures.sorted()
                ))
                continue
            }
            templates.append(ParameterLocalBindingRenameTemplate(
                usr: parameterUSR,
                oldName: localBinding.name,
                replacements: replacements
            ))
        }

        return ParameterLocalBindingRenamePlanningResult(
            templates: templates.sorted { $0.usr < $1.usr },
            denied: denied.sorted { $0.usr < $1.usr }
        )
    }

    static func denialDecision(
        group: USROccurrenceGroup,
        oldName: String?,
        reasons: [String]
    ) -> SafetyDecision {
        SafetyDecision(
            usr: group.usr,
            symbolName: group.symbol.name,
            kind: group.symbol.kind,
            allowed: false,
            oldName: oldName,
            reasons: Array(Set(reasons)).sorted()
        )
    }

    private static func add(
        occurrence: OccurrenceRecord,
        expectedName: String,
        parameterUSR: String,
        sourceCache: SourceFileCache,
        replacements: inout Set<ParameterLocalBindingReplacementTemplate>,
        failures: inout Set<String>
    ) {
        guard let source = sourceCache.file(for: occurrence.path),
              let token = source.identifierToken(
                  line: occurrence.line,
                  utf8Column: occurrence.utf8Column
              ),
              token.name == expectedName else {
            failures.insert(
                "indexed parameter token mismatch at "
                    + "\(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)"
            )
            return
        }
        replacements.insert(ParameterLocalBindingReplacementTemplate(
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
        replacements: inout Set<ParameterLocalBindingReplacementTemplate>,
        failures: inout Set<String>
    ) {
        guard isPlainSwiftIdentifier(expectedName),
              !token.isBackticked,
              token.name == expectedName,
              let source = sourceCache.file(for: token.path),
              source.text(in: token.byteRange) == expectedName,
              let location = source.sourceLocation(atByteOffset: token.byteRange.lowerBound) else {
            failures.insert(
                "compiler syntax local-binding token mismatch at "
                    + "\(token.path):\(token.byteRange.lowerBound)"
            )
            return
        }
        replacements.insert(ParameterLocalBindingReplacementTemplate(
            path: source.path,
            byteOffset: token.byteRange.lowerBound,
            length: token.byteRange.count,
            line: location.line,
            utf8Column: location.utf8Column,
            oldName: expectedName,
            usr: parameterUSR
        ))
    }
}
