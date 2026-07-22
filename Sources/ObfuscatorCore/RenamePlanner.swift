import Foundation

public struct RenamePlanEntry: Sendable {
    public let usr: String
    public let kind: String
    public let oldName: String
    public let newName: String
    public let replacements: [SourceReplacement]
}

public struct RenamePlan: Sendable {
    public let entries: [RenamePlanEntry]
    public let denied: [SafetyDecision]
    public let conflicts: [String]

    public var replacements: [SourceReplacement] {
        entries.flatMap(\.replacements)
    }
}

public struct RenamePlanner {
    public var analyzer: SafetyAnalyzer
    public var generator: NameGenerator
    public var mappingStore: MappingStore

    public init(analyzer: SafetyAnalyzer, generator: NameGenerator = NameGenerator(), mappingStore: MappingStore = MappingStore()) {
        self.analyzer = analyzer
        self.generator = generator
        self.mappingStore = mappingStore
    }

    public mutating func makePlan(snapshot: IndexSnapshot, sourceCache: SourceFileCache) -> RenamePlan {
        var denied: [SafetyDecision] = []
        var entries: [RenamePlanEntry] = []
        var conflicts: [String] = []
        var reservedNames = Set(snapshot.symbols.map(\.name)).filter(isPlainSwiftIdentifier)
        reservedNames.formUnion(mappingStore.allEntries().map(\.obfuscatedName))
        let localNominalTypeNames = Self.localNominalTypeNames(snapshot: snapshot)

        for group in snapshot.groupsByUSR {
            let decision = analyzer.analyze(
                group: group,
                sourceCache: sourceCache,
                localNominalTypeNames: localNominalTypeNames
            )
            guard decision.allowed, let oldName = decision.oldName else {
                denied.append(decision)
                continue
            }

            let newName: String
            if let existing = mappingStore.entry(for: group.usr) {
                newName = existing.obfuscatedName
            } else {
                newName = generator.nextName(avoiding: reservedNames)
                reservedNames.insert(newName)
                mappingStore.record(
                    usr: group.usr,
                    originalName: oldName,
                    obfuscatedName: newName,
                    kind: group.symbol.kind
                )
            }

            var replacements: Set<SourceReplacement> = []
            var localReasons: [String] = []
            for occurrence in group.occurrences {
                guard let source = sourceCache.file(for: occurrence.path) else {
                    localReasons.append("source file unavailable for \(occurrence.path)")
                    continue
                }
                guard let token = source.identifierToken(line: occurrence.line, utf8Column: occurrence.utf8Column) else {
                    localReasons.append("identifier token unavailable at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)")
                    continue
                }
                guard token.name == oldName else {
                    localReasons.append("token mismatch at \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column)")
                    continue
                }
                replacements.insert(SourceReplacement(
                    path: source.path,
                    byteOffset: token.byteRange.lowerBound,
                    length: token.byteRange.count,
                    line: occurrence.line,
                    utf8Column: occurrence.utf8Column,
                    oldName: oldName,
                    newName: newName,
                    usr: group.usr
                ))
            }

            if !localReasons.isEmpty || replacements.isEmpty {
                denied.append(SafetyDecision(
                    usr: group.usr,
                    symbolName: group.symbol.name,
                    kind: group.symbol.kind,
                    allowed: false,
                    oldName: oldName,
                    reasons: localReasons.isEmpty ? ["no source replacements"] : Array(Set(localReasons)).sorted()
                ))
                continue
            }

            entries.append(RenamePlanEntry(
                usr: group.usr,
                kind: group.symbol.kind,
                oldName: oldName,
                newName: newName,
                replacements: replacements.sorted { lhs, rhs in
                    (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
                }
            ))
        }

        let conflictGroups = Dictionary(grouping: entries.flatMap(\.replacements)) { replacement in
            "\(replacement.path):\(replacement.byteOffset)"
        }
        let conflictKeys = Set(conflictGroups.compactMap { key, replacements -> String? in
            let uniqueTargets = Set(replacements.map { "\($0.oldName)->\($0.newName):\($0.usr)" })
            return uniqueTargets.count > 1 ? key : nil
        })
        if !conflictKeys.isEmpty {
            conflicts = conflictKeys.sorted()
            entries = entries.compactMap { entry in
                entry.replacements.contains { conflictKeys.contains("\($0.path):\($0.byteOffset)") } ? nil : entry
            }
        }

        return RenamePlan(
            entries: entries.sorted { ($0.oldName, $0.usr) < ($1.oldName, $1.usr) },
            denied: denied.sorted { ($0.symbolName, $0.usr) < ($1.symbolName, $1.usr) },
            conflicts: conflicts
        )
    }

    private static func localNominalTypeNames(snapshot: IndexSnapshot) -> Set<String> {
        let nominalKinds: Set<String> = ["class", "struct", "enum", "protocol"]
        return Set(snapshot.occurrences.compactMap { occurrence in
            guard nominalKinds.contains(occurrence.symbol.kind),
                  !occurrence.isSystem,
                  occurrence.roles.contains(where: { $0 == "declaration" || $0 == "definition" }),
                  isPlainSwiftIdentifier(occurrence.symbol.name) else {
                return nil
            }
            return occurrence.symbol.name
        })
    }
}
