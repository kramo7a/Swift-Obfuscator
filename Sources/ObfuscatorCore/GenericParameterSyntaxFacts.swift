import Foundation
import SwiftParser
import SwiftSyntax

public struct GenericParameterSyntaxFactsSummary: Codable, Equatable, Sendable {
    public let syntaxGenericParameters: Int
    public let indexedGenericParameters: Int
    public let supportedGenericParameters: Int
    public let unresolvedGenericParameters: Int
    public let syntaxParametersWithoutIndexedDeclaration: Int
    public let indexedOccurrences: Int
    public let unresolvedByReason: [String: Int]

    public static let empty = GenericParameterSyntaxFactsSummary(
        syntaxGenericParameters: 0,
        indexedGenericParameters: 0,
        supportedGenericParameters: 0,
        unresolvedGenericParameters: 0,
        syntaxParametersWithoutIndexedDeclaration: 0,
        indexedOccurrences: 0,
        unresolvedByReason: [:]
    )
}

/// Compiler-anchored lexical facts for Swift generic parameters.
///
/// IndexStoreDB represents a generic parameter as a `typealias` symbol and is
/// authoritative for its USR and semantic references. SwiftSyntax is used only
/// to prove that the indexed declaration token is a generic-parameter token;
/// declaration ownership is never reconstructed from source text.
public struct GenericParameterSyntaxFacts: Sendable {
    public let genericParameterUSRs: Set<String>
    public let supportedGenericParameterUSRs: Set<String>
    public let unresolvedReasonsByUSR: [String: String]
    public let summary: GenericParameterSyntaxFactsSummary

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
        let declarationPaths = Set(declarations.map {
            SourcePathNormalizer.canonicalPath($0.path)
        })

        var candidatesByPathAndOffset: [String: [Int: [SourceTokenRange]]] = [:]
        var syntaxCandidateAnchors: Set<GenericParameterAnchor> = []
        for path in declarationPaths.sorted() {
            guard let source = sourceCache.file(for: path) else {
                continue
            }
            let tree = Parser.parse(source: String(decoding: source.data, as: UTF8.self))
            let visitor = GenericParameterSyntaxVisitor(source: source)
            visitor.walk(tree)
            candidatesByPathAndOffset[source.path] = Dictionary(
                grouping: visitor.tokens,
                by: { $0.byteRange.lowerBound }
            )
            syntaxCandidateAnchors.formUnion(visitor.tokens.map {
                GenericParameterAnchor(path: $0.path, byteOffset: $0.byteRange.lowerBound)
            })
        }

        var identifiedUSRs: Set<String> = []
        var supportedUSRs: Set<String> = []
        var unresolvedReasonsByUSR: [String: String] = [:]
        var matchedSyntaxAnchors: Set<GenericParameterAnchor> = []

        for usr in declarationsByUSR.keys.sorted() {
            let indexedAnchors = Set((declarationsByUSR[usr] ?? []).compactMap {
                occurrence -> IndexedGenericParameterAnchor? in
                guard let source = sourceCache.file(for: occurrence.path),
                      let byteOffset = source.byteOffset(
                        line: occurrence.line,
                        utf8Column: occurrence.utf8Column
                      ),
                      let token = source.identifierToken(atByteOffset: byteOffset) else {
                    return nil
                }
                return IndexedGenericParameterAnchor(
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
                    $0.byteRange == anchor.token.byteRange
                }
            })
            guard !matchingCandidates.isEmpty else {
                // This is an ordinary typealias rather than a generic parameter.
                continue
            }

            identifiedUSRs.insert(usr)
            matchedSyntaxAnchors.formUnion(matchingCandidates.map {
                GenericParameterAnchor(path: $0.path, byteOffset: $0.byteRange.lowerBound)
            })

            guard indexedAnchors.count == 1 else {
                unresolvedReasonsByUSR[usr] = indexedAnchors.isEmpty
                    ? "indexed generic-parameter declaration anchor unavailable"
                    : "indexed generic-parameter declaration anchor is ambiguous"
                continue
            }
            guard matchingCandidates.count == 1, let candidate = matchingCandidates.first else {
                unresolvedReasonsByUSR[usr] =
                    "multiple compiler syntax generic parameters match indexed declaration token"
                continue
            }
            guard candidate.name == declarationsByUSR[usr]?.first?.symbol.name else {
                unresolvedReasonsByUSR[usr] =
                    "compiler syntax generic-parameter spelling differs from indexed symbol"
                continue
            }
            supportedUSRs.insert(usr)
        }

        var unresolvedByReason: [String: Int] = [:]
        for reason in unresolvedReasonsByUSR.values {
            unresolvedByReason[reason, default: 0] += 1
        }
        let occurrencesByUSR = Dictionary(grouping: snapshot.occurrences, by: \.usr)

        self.genericParameterUSRs = identifiedUSRs
        self.supportedGenericParameterUSRs = supportedUSRs
        self.unresolvedReasonsByUSR = unresolvedReasonsByUSR
        self.summary = GenericParameterSyntaxFactsSummary(
            syntaxGenericParameters: syntaxCandidateAnchors.count,
            indexedGenericParameters: identifiedUSRs.count,
            supportedGenericParameters: supportedUSRs.count,
            unresolvedGenericParameters: unresolvedReasonsByUSR.count,
            syntaxParametersWithoutIndexedDeclaration:
                syntaxCandidateAnchors.subtracting(matchedSyntaxAnchors).count,
            indexedOccurrences: supportedUSRs.reduce(0) {
                $0 + (occurrencesByUSR[$1]?.count ?? 0)
            },
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

private struct GenericParameterAnchor: Hashable {
    let path: String
    let byteOffset: Int
}

private struct IndexedGenericParameterAnchor: Hashable {
    let path: String
    let byteOffset: Int
    let token: SourceTokenRange
}

private final class GenericParameterSyntaxVisitor: SyntaxVisitor {
    let source: SourceFile
    var tokens: [SourceTokenRange] = []

    init(source: SourceFile) {
        self.source = source
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: GenericParameterSyntax) -> SyntaxVisitorContinueKind {
        if let token = sourceToken(node.name) {
            tokens.append(token)
        }
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
