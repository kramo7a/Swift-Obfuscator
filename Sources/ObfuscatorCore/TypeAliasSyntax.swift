import Foundation
import SwiftParser
import SwiftSyntax

public enum TypeAliasSyntax {}

extension TypeAliasSyntax {
    public enum UnderlyingKind: String, Codable, Hashable, Sendable {
        case tuple
        case function
        case other
    }

    public struct Report: Codable, Equatable, Sendable {
        public let syntaxTypeAliasDeclarations: Int
        public let indexedTypeAliasDeclarations: Int
        public let resolvedTypeAliasDeclarations: Int
        public let unresolvedTypeAliasDeclarations: Int
        public let syntaxDeclarationsWithoutIndexedUSR: Int
        public let directTupleTypeAliases: Int
        public let functionTypeAliases: Int
        public let otherTypeAliases: Int
        public let tupleRelatedOwnerUSRs: Int
        public let unresolvedByReason: [String: Int]

        public static let empty = TypeAliasSyntax.Report(
            syntaxTypeAliasDeclarations: 0,
            indexedTypeAliasDeclarations: 0,
            resolvedTypeAliasDeclarations: 0,
            unresolvedTypeAliasDeclarations: 0,
            syntaxDeclarationsWithoutIndexedUSR: 0,
            directTupleTypeAliases: 0,
            functionTypeAliases: 0,
            otherTypeAliases: 0,
            tupleRelatedOwnerUSRs: 0,
            unresolvedByReason: [:]
        )

        private enum CodingKeys: String, CodingKey {
            case syntaxTypeAliasDeclarations = "syntaxTypealiasDeclarations"
            case indexedTypeAliasDeclarations = "indexedTypealiasDeclarations"
            case resolvedTypeAliasDeclarations = "resolvedTypealiasDeclarations"
            case unresolvedTypeAliasDeclarations = "unresolvedTypealiasDeclarations"
            case syntaxDeclarationsWithoutIndexedUSR
            case directTupleTypeAliases = "directTupleTypealiases"
            case functionTypeAliases = "functionTypealiases"
            case otherTypeAliases = "otherTypealiases"
            case tupleRelatedOwnerUSRs
            case unresolvedByReason
        }
    }

    /// Compiler-anchored lexical classification for indexed typealias declarations.
    ///
    /// IndexStoreDB supplies declaration USRs and owner relations. SwiftSyntax is
    /// used only to classify the exact indexed declaration token's initializer.
    /// This prevents function types such as `(Input) -> Output` from being confused
    /// with direct tuple aliases merely because both spellings begin with `(`.
    public struct Index: Sendable {
        public let underlyingKindByUSR: [String: TypeAliasSyntax.UnderlyingKind]
        public let directTupleTypeAliasUSRs: Set<String>
        public let tupleRelatedOwnerUSRs: Set<String>
        public let unresolvedRelatedOwnerUSRs: Set<String>
        public let unsafeTupleRelatedUSRs: Set<String>
        public let issueReasonsByUSR: [String: String]
        public let report: TypeAliasSyntax.Report

        public init(
            snapshot: IndexSnapshot,
            sourceCache: SourceFileCache,
            obfuscationRoots: [URL]
        ) {
            let rootPaths = obfuscationRoots.map {
                $0.resolvingSymlinksInPath().standardizedFileURL.path
            }
            let declarations = snapshot.occurrences.filter { occurrence in
                occurrence.symbol.isKind(.typealias)
                    && !occurrence.hasRole(.implicit)
                    && (occurrence.hasRole(.declaration)
                        || occurrence.hasRole(.definition))
                    && Self.isPath(occurrence.path, underRootPaths: rootPaths)
            }
            let declarationsByUSR = Dictionary(grouping: declarations, by: \.usr)
            let declarationPaths = Set(
                declarations.map {
                    SourcePathNormalizer.canonicalPath($0.path)
                })

            var candidatesByPathAndOffset: [String: [Int: [TypeAliasSyntaxCandidate]]] = [:]
            var syntaxCandidateAnchors: Set<TypeAliasAnchor> = []
            for path in declarationPaths.sorted() {
                guard let source = sourceCache.file(for: path) else {
                    continue
                }
                let tree = Parser.parse(source: String(decoding: source.data, as: UTF8.self))
                let visitor = TypeAliasSyntaxVisitor(source: source)
                visitor.walk(tree)
                candidatesByPathAndOffset[source.path] = Dictionary(
                    grouping: visitor.candidates,
                    by: { $0.token.byteRange.lowerBound }
                )
                syntaxCandidateAnchors.formUnion(
                    visitor.candidates.map {
                        TypeAliasAnchor(
                            path: $0.token.path, byteOffset: $0.token.byteRange.lowerBound)
                    })
            }

            var underlyingKindByUSR: [String: TypeAliasSyntax.UnderlyingKind] = [:]
            var directTupleTypeAliasUSRs: Set<String> = []
            var tupleRelatedOwnerUSRs: Set<String> = []
            var unresolvedRelatedOwnerUSRs: Set<String> = []
            var issueReasonsByUSR: [String: String] = [:]
            var matchedSyntaxAnchors: Set<TypeAliasAnchor> = []

            for usr in declarationsByUSR.keys.sorted() {
                let indexedAnchors = Set(
                    (declarationsByUSR[usr] ?? []).compactMap {
                        occurrence -> IndexedTypeAliasAnchor? in
                        guard let source = sourceCache.file(for: occurrence.path),
                            let byteOffset = source.byteOffset(
                                line: occurrence.line,
                                utf8Column: occurrence.utf8Column
                            ),
                            let token = source.identifierToken(atByteOffset: byteOffset)
                        else {
                            return nil
                        }
                        return IndexedTypeAliasAnchor(
                            path: source.path,
                            byteOffset: byteOffset,
                            token: SourceToken(
                                path: source.path,
                                name: token.name,
                                byteRange: token.byteRange,
                                isBackticked: token.isBackticked
                            )
                        )
                    })
                let matchingCandidates = Set(
                    indexedAnchors.flatMap { anchor in
                        (candidatesByPathAndOffset[anchor.path]?[anchor.byteOffset] ?? []).filter {
                            $0.token.byteRange == anchor.token.byteRange
                        }
                    })
                guard !matchingCandidates.isEmpty else {
                    // IndexStoreDB also represents generic parameters as typealias
                    // symbols. They are intentionally handled by their own analysis.
                    continue
                }

                matchedSyntaxAnchors.formUnion(
                    matchingCandidates.map {
                        TypeAliasAnchor(
                            path: $0.token.path, byteOffset: $0.token.byteRange.lowerBound)
                    })
                var indexedOwnerUSRs: Set<String> = []
                for occurrence in declarationsByUSR[usr] ?? [] {
                    for relation in occurrence.relations
                    where relation.hasRole(.childOf)
                        || relation.hasRole(.containedBy)
                    {
                        indexedOwnerUSRs.insert(relation.usr)
                    }
                }
                guard indexedAnchors.count == 1 else {
                    issueReasonsByUSR[usr] =
                        indexedAnchors.isEmpty
                        ? "indexed typealias declaration anchor unavailable"
                        : "indexed typealias declaration anchor is ambiguous"
                    unresolvedRelatedOwnerUSRs.formUnion(indexedOwnerUSRs)
                    continue
                }
                guard matchingCandidates.count == 1, let candidate = matchingCandidates.first else {
                    issueReasonsByUSR[usr] =
                        "multiple compiler syntax typealiases match indexed declaration token"
                    unresolvedRelatedOwnerUSRs.formUnion(indexedOwnerUSRs)
                    continue
                }
                guard candidate.token.name == declarationsByUSR[usr]?.first?.symbol.name else {
                    issueReasonsByUSR[usr] =
                        "compiler syntax typealias spelling differs from indexed symbol"
                    unresolvedRelatedOwnerUSRs.formUnion(indexedOwnerUSRs)
                    continue
                }

                underlyingKindByUSR[usr] = candidate.underlyingKind
                guard candidate.underlyingKind == .tuple else {
                    continue
                }
                directTupleTypeAliasUSRs.insert(usr)
                tupleRelatedOwnerUSRs.formUnion(indexedOwnerUSRs)
            }

            var unresolvedByReason: [String: Int] = [:]
            for reason in issueReasonsByUSR.values {
                unresolvedByReason[reason, default: 0] += 1
            }
            let kinds = Array(underlyingKindByUSR.values)

            self.underlyingKindByUSR = underlyingKindByUSR
            self.directTupleTypeAliasUSRs = directTupleTypeAliasUSRs
            self.tupleRelatedOwnerUSRs = tupleRelatedOwnerUSRs
            self.unresolvedRelatedOwnerUSRs = unresolvedRelatedOwnerUSRs
            self.unsafeTupleRelatedUSRs =
                directTupleTypeAliasUSRs
                .union(tupleRelatedOwnerUSRs)
                .union(issueReasonsByUSR.keys)
                .union(unresolvedRelatedOwnerUSRs)
            self.issueReasonsByUSR = issueReasonsByUSR
            self.report = TypeAliasSyntax.Report(
                syntaxTypeAliasDeclarations: syntaxCandidateAnchors.count,
                indexedTypeAliasDeclarations: underlyingKindByUSR.count
                    + issueReasonsByUSR.count,
                resolvedTypeAliasDeclarations: underlyingKindByUSR.count,
                unresolvedTypeAliasDeclarations: issueReasonsByUSR.count,
                syntaxDeclarationsWithoutIndexedUSR:
                    syntaxCandidateAnchors.subtracting(matchedSyntaxAnchors).count,
                directTupleTypeAliases: kinds.count { $0 == .tuple },
                functionTypeAliases: kinds.count { $0 == .function },
                otherTypeAliases: kinds.count { $0 == .other },
                tupleRelatedOwnerUSRs: tupleRelatedOwnerUSRs.count,
                unresolvedByReason: unresolvedByReason
            )
        }

        private static func isPath(_ path: String, underRootPaths rootPaths: [String]) -> Bool {
            let canonicalPath = SourcePathNormalizer.canonicalPath(path)
            return rootPaths.contains { rootPath in
                canonicalPath == rootPath || canonicalPath.hasPrefix(rootPath + "/")
            }
        }
    }

}

private struct TypeAliasAnchor: Hashable {
    let path: String
    let byteOffset: Int
}

private struct IndexedTypeAliasAnchor: Hashable {
    let path: String
    let byteOffset: Int
    let token: SourceToken
}

private struct TypeAliasSyntaxCandidate: Hashable {
    let token: SourceToken
    let underlyingKind: TypeAliasSyntax.UnderlyingKind
}

private final class TypeAliasSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var candidates: [TypeAliasSyntaxCandidate] = []

    init(source: SourceFile) {
        self.source = source
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let token = sourceToken(node.name) else {
            return .visitChildren
        }
        let value = node.initializer.value
        let underlyingKind: TypeAliasSyntax.UnderlyingKind
        if value.is(TupleTypeSyntax.self) {
            underlyingKind = .tuple
        } else if value.is(FunctionTypeSyntax.self) {
            underlyingKind = .function
        } else {
            underlyingKind = .other
        }
        candidates.append(
            TypeAliasSyntaxCandidate(
                token: token,
                underlyingKind: underlyingKind
            ))
        return .visitChildren
    }

    private func sourceToken(_ token: TokenSyntax) -> SourceToken? {
        guard token.presence == .present else {
            return nil
        }
        let offset = token.positionAfterSkippingLeadingTrivia.utf8Offset
        guard let identifier = source.identifierToken(atByteOffset: offset) else {
            return nil
        }
        return SourceToken(
            path: source.path,
            name: identifier.name,
            byteRange: identifier.byteRange,
            isBackticked: identifier.isBackticked
        )
    }
}
