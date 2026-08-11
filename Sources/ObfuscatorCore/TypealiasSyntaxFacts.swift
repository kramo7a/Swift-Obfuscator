import Foundation
import SwiftParser
import SwiftSyntax

public enum TypealiasUnderlyingSyntaxKind: String, Codable, Hashable, Sendable {
    case tuple
    case function
    case other
}

public struct TypealiasSyntaxFactsSummary: Codable, Equatable, Sendable {
    public let syntaxTypealiasDeclarations: Int
    public let indexedTypealiasDeclarations: Int
    public let resolvedTypealiasDeclarations: Int
    public let unresolvedTypealiasDeclarations: Int
    public let syntaxDeclarationsWithoutIndexedUSR: Int
    public let directTupleTypealiases: Int
    public let functionTypealiases: Int
    public let otherTypealiases: Int
    public let tupleRelatedOwnerUSRs: Int
    public let unresolvedByReason: [String: Int]

    public static let empty = TypealiasSyntaxFactsSummary(
        syntaxTypealiasDeclarations: 0,
        indexedTypealiasDeclarations: 0,
        resolvedTypealiasDeclarations: 0,
        unresolvedTypealiasDeclarations: 0,
        syntaxDeclarationsWithoutIndexedUSR: 0,
        directTupleTypealiases: 0,
        functionTypealiases: 0,
        otherTypealiases: 0,
        tupleRelatedOwnerUSRs: 0,
        unresolvedByReason: [:]
    )
}

/// Compiler-anchored lexical classification for indexed typealias declarations.
///
/// IndexStoreDB supplies declaration USRs and owner relations. SwiftSyntax is
/// used only to classify the exact indexed declaration token's initializer.
/// This prevents function types such as `(Input) -> Output` from being confused
/// with direct tuple aliases merely because both spellings begin with `(`.
public struct TypealiasSyntaxFacts: Sendable {
    public let underlyingKindByUSR: [String: TypealiasUnderlyingSyntaxKind]
    public let directTupleTypealiasUSRs: Set<String>
    public let tupleRelatedOwnerUSRs: Set<String>
    public let unresolvedRelatedOwnerUSRs: Set<String>
    public let unsafeTupleRelatedUSRs: Set<String>
    public let unresolvedReasonsByUSR: [String: String]
    public let summary: TypealiasSyntaxFactsSummary

    public init(
        snapshot: IndexSnapshot,
        sourceCache: SourceFileCache,
        obfuscationRoots: [URL]
    ) {
        let rootPaths = obfuscationRoots.map {
            $0.resolvingSymlinksInPath().standardizedFileURL.path
        }
        let declarations = snapshot.occurrences.filter { occurrence in
            occurrence.symbol.kind == "typealias"
                && !occurrence.roles.contains("implicit")
                && (occurrence.roles.contains("declaration")
                    || occurrence.roles.contains("definition"))
                && Self.isPath(occurrence.path, underRootPaths: rootPaths)
        }
        let declarationsByUSR = Dictionary(grouping: declarations, by: \.usr)
        let declarationPaths = Set(declarations.map {
            SourcePathNormalizer.canonicalPath($0.path)
        })

        var candidatesByPathAndOffset: [String: [Int: [TypealiasSyntaxCandidate]]] = [:]
        var syntaxCandidateAnchors: Set<TypealiasAnchor> = []
        for path in declarationPaths.sorted() {
            guard let source = sourceCache.file(for: path) else {
                continue
            }
            let tree = Parser.parse(source: String(decoding: source.data, as: UTF8.self))
            let visitor = TypealiasSyntaxVisitor(source: source)
            visitor.walk(tree)
            candidatesByPathAndOffset[source.path] = Dictionary(
                grouping: visitor.candidates,
                by: { $0.token.byteRange.lowerBound }
            )
            syntaxCandidateAnchors.formUnion(visitor.candidates.map {
                TypealiasAnchor(path: $0.token.path, byteOffset: $0.token.byteRange.lowerBound)
            })
        }

        var underlyingKindByUSR: [String: TypealiasUnderlyingSyntaxKind] = [:]
        var directTupleTypealiasUSRs: Set<String> = []
        var tupleRelatedOwnerUSRs: Set<String> = []
        var unresolvedRelatedOwnerUSRs: Set<String> = []
        var unresolvedReasonsByUSR: [String: String] = [:]
        var matchedSyntaxAnchors: Set<TypealiasAnchor> = []

        for usr in declarationsByUSR.keys.sorted() {
            let indexedAnchors = Set((declarationsByUSR[usr] ?? []).compactMap {
                occurrence -> IndexedTypealiasAnchor? in
                guard let source = sourceCache.file(for: occurrence.path),
                      let byteOffset = source.byteOffset(
                        line: occurrence.line,
                        utf8Column: occurrence.utf8Column
                      ),
                      let token = source.identifierToken(atByteOffset: byteOffset) else {
                    return nil
                }
                return IndexedTypealiasAnchor(
                    path: source.path,
                    byteOffset: byteOffset,
                    token: SourceTokenRange(
                        path: source.path,
                        name: token.name,
                        byteRange: token.byteRange,
                        isBackticked: token.isBackticked
                    )
                )
            })
            let matchingCandidates = Set(indexedAnchors.flatMap { anchor in
                (candidatesByPathAndOffset[anchor.path]?[anchor.byteOffset] ?? []).filter {
                    $0.token.byteRange == anchor.token.byteRange
                }
            })
            guard !matchingCandidates.isEmpty else {
                // IndexStoreDB also represents generic parameters as typealias
                // symbols. They are intentionally handled by their own facts.
                continue
            }

            matchedSyntaxAnchors.formUnion(matchingCandidates.map {
                TypealiasAnchor(path: $0.token.path, byteOffset: $0.token.byteRange.lowerBound)
            })
            var indexedOwnerUSRs: Set<String> = []
            for occurrence in declarationsByUSR[usr] ?? [] {
                for relation in occurrence.relations
                where relation.roles.contains("childOf")
                    || relation.roles.contains("containedBy") {
                    indexedOwnerUSRs.insert(relation.usr)
                }
            }
            guard indexedAnchors.count == 1 else {
                unresolvedReasonsByUSR[usr] = indexedAnchors.isEmpty
                    ? "indexed typealias declaration anchor unavailable"
                    : "indexed typealias declaration anchor is ambiguous"
                unresolvedRelatedOwnerUSRs.formUnion(indexedOwnerUSRs)
                continue
            }
            guard matchingCandidates.count == 1, let candidate = matchingCandidates.first else {
                unresolvedReasonsByUSR[usr] =
                    "multiple compiler syntax typealiases match indexed declaration token"
                unresolvedRelatedOwnerUSRs.formUnion(indexedOwnerUSRs)
                continue
            }
            guard candidate.token.name == declarationsByUSR[usr]?.first?.symbol.name else {
                unresolvedReasonsByUSR[usr] =
                    "compiler syntax typealias spelling differs from indexed symbol"
                unresolvedRelatedOwnerUSRs.formUnion(indexedOwnerUSRs)
                continue
            }

            underlyingKindByUSR[usr] = candidate.underlyingKind
            guard candidate.underlyingKind == .tuple else {
                continue
            }
            directTupleTypealiasUSRs.insert(usr)
            tupleRelatedOwnerUSRs.formUnion(indexedOwnerUSRs)
        }

        var unresolvedByReason: [String: Int] = [:]
        for reason in unresolvedReasonsByUSR.values {
            unresolvedByReason[reason, default: 0] += 1
        }
        let kinds = Array(underlyingKindByUSR.values)

        self.underlyingKindByUSR = underlyingKindByUSR
        self.directTupleTypealiasUSRs = directTupleTypealiasUSRs
        self.tupleRelatedOwnerUSRs = tupleRelatedOwnerUSRs
        self.unresolvedRelatedOwnerUSRs = unresolvedRelatedOwnerUSRs
        self.unsafeTupleRelatedUSRs = directTupleTypealiasUSRs
            .union(tupleRelatedOwnerUSRs)
            .union(unresolvedReasonsByUSR.keys)
            .union(unresolvedRelatedOwnerUSRs)
        self.unresolvedReasonsByUSR = unresolvedReasonsByUSR
        self.summary = TypealiasSyntaxFactsSummary(
            syntaxTypealiasDeclarations: syntaxCandidateAnchors.count,
            indexedTypealiasDeclarations: underlyingKindByUSR.count
                + unresolvedReasonsByUSR.count,
            resolvedTypealiasDeclarations: underlyingKindByUSR.count,
            unresolvedTypealiasDeclarations: unresolvedReasonsByUSR.count,
            syntaxDeclarationsWithoutIndexedUSR:
                syntaxCandidateAnchors.subtracting(matchedSyntaxAnchors).count,
            directTupleTypealiases: kinds.count { $0 == .tuple },
            functionTypealiases: kinds.count { $0 == .function },
            otherTypealiases: kinds.count { $0 == .other },
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

private struct TypealiasAnchor: Hashable {
    let path: String
    let byteOffset: Int
}

private struct IndexedTypealiasAnchor: Hashable {
    let path: String
    let byteOffset: Int
    let token: SourceTokenRange
}

private struct TypealiasSyntaxCandidate: Hashable {
    let token: SourceTokenRange
    let underlyingKind: TypealiasUnderlyingSyntaxKind
}

private final class TypealiasSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var candidates: [TypealiasSyntaxCandidate] = []

    init(source: SourceFile) {
        self.source = source
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let token = sourceToken(node.name) else {
            return .visitChildren
        }
        let value = node.initializer.value
        let underlyingKind: TypealiasUnderlyingSyntaxKind
        if value.is(TupleTypeSyntax.self) {
            underlyingKind = .tuple
        } else if value.is(FunctionTypeSyntax.self) {
            underlyingKind = .function
        } else {
            underlyingKind = .other
        }
        candidates.append(TypealiasSyntaxCandidate(
            token: token,
            underlyingKind: underlyingKind
        ))
        return .visitChildren
    }

    private func sourceToken(_ token: TokenSyntax) -> SourceTokenRange? {
        guard token.presence == .present else {
            return nil
        }
        let offset = token.positionAfterSkippingLeadingTrivia.utf8Offset
        guard let identifier = source.identifierToken(atByteOffset: offset) else {
            return nil
        }
        return SourceTokenRange(
            path: source.path,
            name: identifier.name,
            byteRange: identifier.byteRange,
            isBackticked: identifier.isBackticked
        )
    }
}
