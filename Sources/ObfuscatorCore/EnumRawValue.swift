import Foundation

public enum EnumRawValue {}

extension EnumRawValue {
    public enum LiteralKind: String, Codable, Hashable, Sendable {
        case string
        case integer
        case floatingPoint
    }

    public struct ImplicitValue: Codable, Hashable, Sendable {
        public let caseUSR: String
        public let declarationToken: SourceToken
        public let literalKind: EnumRawValue.LiteralKind
        public let literalSource: String
    }

    public struct Report: Codable, Equatable, Sendable {
        public let requestedSourceFiles: Int
        public let decodedSourceFiles: Int
        public let failedSourceFiles: Int
        public let candidateCaseUSRs: Int
        public let resolvedImplicitRawValues: Int
        public let resolvedByLiteralKind: [String: Int]

        public static let empty = EnumRawValue.Report(
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
    public struct Index: Sendable {
        public let implicitValuesByCaseUSR: [String: EnumRawValue.ImplicitValue]
        public let report: EnumRawValue.Report

        public static let empty = EnumRawValue.Index(
            implicitValuesByCaseUSR: [:],
            report: .empty
        )

        public init(
            snapshot: IndexSnapshot,
            semantics: EnumCaseSemantics.Index,
            semanticIndex: SemanticIndex,
            sourceCache: SourceFileCache,
            runner: CommandRunner = CommandRunner()
        ) {
            let groupsByUSR = Dictionary(
                uniqueKeysWithValues: snapshot.occurrenceGroups.map { ($0.usr, $0) }
            )
            let candidateCaseUSRs = Set(
                semantics.owners
                    .filter(\.hasRawType)
                    .flatMap(\.caseUSRs))

            var anchorsByPath: [String: [Int: [EnumRawValueAnchor]]] = [:]
            for caseUSR in candidateCaseUSRs.sorted() {
                guard let group = groupsByUSR[caseUSR] else {
                    continue
                }
                let anchors = Set(
                    group.occurrences.compactMap {
                        occurrence
                            -> EnumRawValueAnchor? in
                        guard !occurrence.hasRole(.implicit),
                            occurrence.hasRole(.declaration)
                                || occurrence.hasRole(.definition),
                            let source = sourceCache.file(for: occurrence.path),
                            let byteOffset = source.byteOffset(
                                line: occurrence.line,
                                utf8Column: occurrence.utf8Column
                            ),
                            let token = source.identifierToken(atByteOffset: byteOffset)
                        else {
                            return nil
                        }
                        return EnumRawValueAnchor(
                            caseUSR: caseUSR,
                            token: SourceToken(
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

            var implicitValuesByCaseUSR: [String: EnumRawValue.ImplicitValue] = [:]
            var decodedSourceFiles = 0
            var failedSourceFiles = 0
            for path in anchorsByPath.keys.sorted() {
                guard
                    let result = try? runner.run(
                        executable: "/usr/bin/xcrun",
                        arguments: [
                            "swiftc",
                            "-dump-ast",
                            "-dump-ast-format", "json",
                            "-parse-as-library",
                            path,
                        ],
                        allowNonZeroExit: true
                    ),
                    let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
                else {
                    failedSourceFiles += 1
                    continue
                }
                decodedSourceFiles += 1

                var candidates: Set<EnumRawValueCandidate> = []
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
                    implicitValuesByCaseUSR[anchor.caseUSR] = EnumRawValue.ImplicitValue(
                        caseUSR: anchor.caseUSR,
                        declarationToken: anchor.token,
                        literalKind: match.literalKind,
                        literalSource: match.literalSource
                    )
                }
            }

            var resolvedByLiteralKind: [String: Int] = [:]
            for fact in implicitValuesByCaseUSR.values {
                resolvedByLiteralKind[fact.literalKind.rawValue, default: 0] += 1
            }
            self.implicitValuesByCaseUSR = implicitValuesByCaseUSR
            self.report = EnumRawValue.Report(
                requestedSourceFiles: anchorsByPath.count,
                decodedSourceFiles: decodedSourceFiles,
                failedSourceFiles: failedSourceFiles,
                candidateCaseUSRs: candidateCaseUSRs.count,
                resolvedImplicitRawValues: implicitValuesByCaseUSR.count,
                resolvedByLiteralKind: resolvedByLiteralKind
            )
        }

        private init(
            implicitValuesByCaseUSR: [String: EnumRawValue.ImplicitValue],
            report: EnumRawValue.Report
        ) {
            self.implicitValuesByCaseUSR = implicitValuesByCaseUSR
            self.report = report
        }

        private static func collectCandidates(
            from value: Any,
            path: String,
            into result: inout Set<EnumRawValueCandidate>
        ) {
            if let dictionary = value as? [String: Any] {
                if dictionary["_kind"] as? String == "enum_element_decl",
                    let rawValue = dictionary["raw_value_expr"] as? [String: Any],
                    rawValue["implicit"] as? Bool == true,
                    let range = dictionary["range"] as? [String: Any],
                    let offset = (range["start"] as? NSNumber)?.intValue,
                    let name =
                        (((dictionary["name"] as? [String: Any])?["base_name"]
                            as? [String: Any])?["name"] as? String),
                    let literal = literal(from: rawValue)
                {
                    result.insert(
                        EnumRawValueCandidate(
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
        ) -> (kind: EnumRawValue.LiteralKind, source: String)? {
            guard let kind = expression["_kind"] as? String,
                let value = expression["value"] as? String
            else {
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
                guard
                    value.range(
                        of: #"^-?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
                        options: .regularExpression
                    ) != nil
                else {
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

}

private struct EnumRawValueAnchor: Hashable {
    let caseUSR: String
    let token: SourceToken
}

private struct EnumRawValueCandidate: Hashable {
    let path: String
    let declarationByteOffset: Int
    let name: String
    let literalKind: EnumRawValue.LiteralKind
    let literalSource: String
}
