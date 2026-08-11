import Foundation

public enum CompilerRawLiteralKind: String, Codable, Hashable, Sendable {
    case string
    case integer
    case floatingPoint
}

public struct CompilerImplicitRawValueFact: Codable, Hashable, Sendable {
    public let caseUSR: String
    public let declarationToken: SourceTokenRange
    public let literalKind: CompilerRawLiteralKind
    public let literalSource: String
}

public struct CompilerRawValueFactsSummary: Codable, Equatable, Sendable {
    public let requestedSourceFiles: Int
    public let decodedSourceFiles: Int
    public let failedSourceFiles: Int
    public let candidateCaseUSRs: Int
    public let resolvedImplicitRawValues: Int
    public let resolvedByLiteralKind: [String: Int]

    public static let empty = CompilerRawValueFactsSummary(
        requestedSourceFiles: 0,
        decodedSourceFiles: 0,
        failedSourceFiles: 0,
        candidateCaseUSRs: 0,
        resolvedImplicitRawValues: 0,
        resolvedByLiteralKind: [:]
    )
}

/// Compiler-derived values for source-authored enum cases with implicit raw values.
///
/// IndexStoreDB supplies the enum/case ownership graph and exact declaration USRs.
/// SwiftSyntax still owns the source ranges used for patching. The compiler JSON AST
/// is consulted only for the semantic value that source syntax intentionally omits:
/// the literal selected for an implicit raw-value case. Matching is by the exact
/// compiler-indexed declaration byte anchor and spelling; unmatched or ambiguous
/// records fail closed.
public struct CompilerRawValueFacts: Sendable {
    public let factsByCaseUSR: [String: CompilerImplicitRawValueFact]
    public let summary: CompilerRawValueFactsSummary

    public static let empty = CompilerRawValueFacts(
        factsByCaseUSR: [:],
        summary: .empty
    )

    public init(
        snapshot: IndexSnapshot,
        semanticFacts: EnumCaseComponentFacts,
        indexedFacts: IndexedSemanticFacts,
        sourceCache: SourceFileCache,
        runner: CommandRunner = CommandRunner()
    ) {
        let groupsByUSR = Dictionary(
            uniqueKeysWithValues: snapshot.groupsByUSR.map { ($0.usr, $0) }
        )
        let candidateCaseUSRs = Set(semanticFacts.components
            .filter { component in
                component.hasRawType
                    && !indexedFacts.explicitCodingKeysEnumUSRs.contains(component.ownerUSR)
            }
            .flatMap(\.caseUSRs))

        var anchorsByPath: [String: [Int: [CompilerRawValueAnchor]]] = [:]
        for caseUSR in candidateCaseUSRs.sorted() {
            guard let group = groupsByUSR[caseUSR] else {
                continue
            }
            let anchors = Set(group.occurrences.compactMap { occurrence
                -> CompilerRawValueAnchor? in
                guard !occurrence.roles.contains("implicit"),
                      occurrence.roles.contains("declaration")
                        || occurrence.roles.contains("definition"),
                      let source = sourceCache.file(for: occurrence.path),
                      let byteOffset = source.byteOffset(
                        line: occurrence.line,
                        utf8Column: occurrence.utf8Column
                      ),
                      let token = source.identifierToken(atByteOffset: byteOffset) else {
                    return nil
                }
                return CompilerRawValueAnchor(
                    caseUSR: caseUSR,
                    token: SourceTokenRange(
                        path: source.path,
                        name: token.name,
                        byteRange: token.byteRange,
                        isBackticked: token.isBackticked
                    )
                )
            })
            guard anchors.count == 1, let anchor = anchors.first else {
                continue
            }
            anchorsByPath[anchor.token.path, default: [:]][
                anchor.token.byteRange.lowerBound,
                default: []
            ].append(anchor)
        }

        var factsByCaseUSR: [String: CompilerImplicitRawValueFact] = [:]
        var decodedSourceFiles = 0
        var failedSourceFiles = 0
        for path in anchorsByPath.keys.sorted() {
            guard let result = try? runner.run(
                executable: "/usr/bin/xcrun",
                arguments: [
                    "swiftc",
                    "-dump-ast",
                    "-dump-ast-format", "json",
                    "-parse-as-library",
                    path
                ],
                allowNonZeroExit: true
            ),
            let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) else {
                failedSourceFiles += 1
                continue
            }
            decodedSourceFiles += 1

            var candidates: Set<CompilerRawValueCandidate> = []
            Self.collectCandidates(from: root, path: path, into: &candidates)
            let candidatesByOffset = Dictionary(grouping: candidates) {
                $0.declarationByteOffset
            }
            for (offset, anchors) in anchorsByPath[path] ?? [:] {
                guard anchors.count == 1, let anchor = anchors.first else {
                    continue
                }
                let matches = (candidatesByOffset[offset] ?? []).filter {
                    $0.name == anchor.token.name
                }
                guard matches.count == 1, let match = matches.first else {
                    continue
                }
                factsByCaseUSR[anchor.caseUSR] = CompilerImplicitRawValueFact(
                    caseUSR: anchor.caseUSR,
                    declarationToken: anchor.token,
                    literalKind: match.literalKind,
                    literalSource: match.literalSource
                )
            }
        }

        var resolvedByLiteralKind: [String: Int] = [:]
        for fact in factsByCaseUSR.values {
            resolvedByLiteralKind[fact.literalKind.rawValue, default: 0] += 1
        }
        self.factsByCaseUSR = factsByCaseUSR
        self.summary = CompilerRawValueFactsSummary(
            requestedSourceFiles: anchorsByPath.count,
            decodedSourceFiles: decodedSourceFiles,
            failedSourceFiles: failedSourceFiles,
            candidateCaseUSRs: candidateCaseUSRs.count,
            resolvedImplicitRawValues: factsByCaseUSR.count,
            resolvedByLiteralKind: resolvedByLiteralKind
        )
    }

    private init(
        factsByCaseUSR: [String: CompilerImplicitRawValueFact],
        summary: CompilerRawValueFactsSummary
    ) {
        self.factsByCaseUSR = factsByCaseUSR
        self.summary = summary
    }

    private static func collectCandidates(
        from value: Any,
        path: String,
        into result: inout Set<CompilerRawValueCandidate>
    ) {
        if let dictionary = value as? [String: Any] {
            if dictionary["_kind"] as? String == "enum_element_decl",
               let rawValue = dictionary["raw_value_expr"] as? [String: Any],
               rawValue["implicit"] as? Bool == true,
               let range = dictionary["range"] as? [String: Any],
               let offset = (range["start"] as? NSNumber)?.intValue,
               let name = (((dictionary["name"] as? [String: Any])?["base_name"]
                    as? [String: Any])?["name"] as? String),
               let literal = literal(from: rawValue) {
                result.insert(CompilerRawValueCandidate(
                    path: path,
                    declarationByteOffset: offset,
                    name: name,
                    literalKind: literal.kind,
                    literalSource: literal.source
                ))
            }
            for child in dictionary.values {
                collectCandidates(from: child, path: path, into: &result)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectCandidates(from: child, path: path, into: &result)
            }
        }
    }

    private static func literal(
        from expression: [String: Any]
    ) -> (kind: CompilerRawLiteralKind, source: String)? {
        guard let kind = expression["_kind"] as? String,
              let value = expression["value"] as? String else {
            return nil
        }
        switch kind {
        case "string_literal_expr":
            return (.string, swiftStringLiteral(value))
        case "integer_literal_expr":
            guard value.range(of: #"^-?[0-9]+$"#, options: .regularExpression) != nil else {
                return nil
            }
            return (.integer, value)
        case "float_literal_expr":
            guard value.range(
                of: #"^-?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
                options: .regularExpression
            ) != nil else {
                return nil
            }
            return (.floatingPoint, value)
        default:
            return nil
        }
    }

    private static func swiftStringLiteral(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0: result += "\\0"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 13: result += "\\r"
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 0..<32, 127:
                result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }
}

private struct CompilerRawValueAnchor: Hashable {
    let caseUSR: String
    let token: SourceTokenRange
}

private struct CompilerRawValueCandidate: Hashable {
    let path: String
    let declarationByteOffset: Int
    let name: String
    let literalKind: CompilerRawLiteralKind
    let literalSource: String
}
