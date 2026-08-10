import CryptoKit
import Foundation

public enum CoverageDenialCategory: String, Codable, CaseIterable, Sendable {
    case syntheticAccessor
    case parameter
    case enumCase
    case unsupportedSymbolKind
    case objectiveCRuntimeContract
    case noLocalDeclaration
    case externalLanguageContract
    case storedProperty
    case protocolRequirementWitness
    case overrideBaseComponent
    case nonPlainIdentifier
    case genericParameter
    case tupleTypealias
    case identifierTokenUnavailable
    case ambiguousSourceTokens
    case sourceValidation
    case missingFromIndex
    case unclassified
    case other
}

public enum CoverageCohortBaselineStatus: String, Codable, Sendable {
    case renamed
    case engineeringCandidate
}

public struct CoverageCohortMember: Codable, Equatable, Sendable {
    public let usr: String
    public let originalName: String
    public let kind: String
    public let baselineStatus: CoverageCohortBaselineStatus
    public let baselineDenialCategories: [CoverageDenialCategory]
}

public struct CoverageCohort: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let identifier: String
    public let denominator: Int
    public let membersSHA256: String
    public let baselineIndexedSymbols: Int
    public let baselineIndexedOccurrences: Int
    public let baselineRenamedSymbols: Int
    public let members: [CoverageCohortMember]

    public static func load(from url: URL) throws -> CoverageCohort {
        let cohort = try JSONDecoder().decode(CoverageCohort.self, from: Data(contentsOf: url))
        try cohort.validate()
        return cohort
    }

    public func save(to url: URL, fileManager: FileManager = .default) throws {
        guard !fileManager.fileExists(atPath: url.path) else {
            throw CoverageReportError.cohortAlreadyExists(url.path)
        }
        try validate()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw CoverageReportError.unsupportedCohortFormat(formatVersion)
        }
        guard denominator == members.count else {
            throw CoverageReportError.invalidCohortCount(expected: denominator, actual: members.count)
        }
        let uniqueUSRs = Set(members.map(\.usr))
        guard uniqueUSRs.count == members.count else {
            throw CoverageReportError.duplicateCohortUSRs
        }
        let sortedMembers = members.sorted { $0.usr < $1.usr }
        guard sortedMembers == members else {
            throw CoverageReportError.unsortedCohortUSRs
        }
        let actualDigest = Self.digest(of: members)
        guard actualDigest == membersSHA256 else {
            throw CoverageReportError.invalidCohortDigest(expected: membersSHA256, actual: actualDigest)
        }
    }

    fileprivate static func digest(of members: [CoverageCohortMember]) -> String {
        let canonicalUSRs = members.map(\.usr).joined(separator: "\n") + "\n"
        return SHA256.hash(data: Data(canonicalUSRs.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum CoverageMemberStatus: String, Codable, Sendable {
    case renamed
    case denied
    case missingFromIndex
    case unclassified
}

public struct CoverageMemberResult: Codable, Equatable, Sendable {
    public let usr: String
    public let originalName: String
    public let kind: String
    public let status: CoverageMemberStatus
    public let newName: String?
    public let denialCategories: [CoverageDenialCategory]
    public let denialReasons: [String]
}

public struct CoverageKindSummary: Codable, Equatable, Sendable {
    public let kind: String
    public let denominator: Int
    public let renamed: Int
    public let denied: Int
    public let missingOrUnclassified: Int
    public let coveragePercent: Double
}

public struct CoverageDenialSummary: Codable, Equatable, Sendable {
    public let category: CoverageDenialCategory
    public let members: Int
}

public struct SyntheticAccessorSummary: Codable, Equatable, Sendable {
    public let total: Int
    public let getters: Int
    public let setters: Int
    public let other: Int
    public let derivedRenamed: Int
    public let derivedUnchanged: Int
    public let unresolvedParent: Int
    public let unexpectedlyPlanned: Int
}

public struct CoverageReport: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let cohortIdentifier: String
    public let cohortMembersSHA256: String
    public let denominator: Int
    public let renamed: Int
    public let denied: Int
    public let missingFromIndex: Int
    public let unclassified: Int
    public let coveragePercent: Double
    public let indexedSymbols: Int
    public let indexedOccurrences: Int
    public let plannedSymbols: Int
    public let plannedReplacements: Int
    public let conflicts: Int
    public let bySymbolKind: [CoverageKindSummary]
    public let primaryDenialReasons: [CoverageDenialSummary]
    public let allDenialReasons: [CoverageDenialSummary]
    public let syntheticAccessors: SyntheticAccessorSummary
    public let members: [CoverageMemberResult]

    public func save(to url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

public enum CoverageReportError: LocalizedError {
    case cohortAlreadyExists(String)
    case unsupportedCohortFormat(Int)
    case invalidCohortCount(expected: Int, actual: Int)
    case duplicateCohortUSRs
    case unsortedCohortUSRs
    case invalidCohortDigest(expected: String, actual: String)
    case generatedCohortCountMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .cohortAlreadyExists(let path):
            return "Coverage cohort already exists and is immutable: \(path)"
        case .unsupportedCohortFormat(let version):
            return "Unsupported coverage cohort format version: \(version)"
        case .invalidCohortCount(let expected, let actual):
            return "Coverage cohort declares \(expected) members but contains \(actual)"
        case .duplicateCohortUSRs:
            return "Coverage cohort contains duplicate USRs"
        case .unsortedCohortUSRs:
            return "Coverage cohort USRs must be sorted for deterministic hashing"
        case .invalidCohortDigest(let expected, let actual):
            return "Coverage cohort digest mismatch: expected \(expected), got \(actual)"
        case .generatedCohortCountMismatch(let expected, let actual):
            return "Generated coverage cohort has \(actual) USRs, expected \(expected)"
        }
    }
}

public enum CoverageAnalyzer {
    public static func makeBaselineCohort(
        identifier: String,
        expectedCount: Int? = nil,
        snapshot: IndexSnapshot,
        plan: RenamePlan,
        allowedKinds: Set<String> = SafetyAnalyzer.defaultAllowedKinds
    ) throws -> CoverageCohort {
        let plannedByUSR = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.usr, $0) })
        let deniedByUSR = Dictionary(uniqueKeysWithValues: plan.denied.map { ($0.usr, $0) })
        var members: [CoverageCohortMember] = []

        for group in snapshot.groupsByUSR {
            if isSyntheticAccessor(group) {
                continue
            }

            if let entry = plannedByUSR[group.usr] {
                members.append(CoverageCohortMember(
                    usr: group.usr,
                    originalName: entry.oldName,
                    kind: entry.kind,
                    baselineStatus: .renamed,
                    baselineDenialCategories: []
                ))
                continue
            }

            guard allowedKinds.contains(group.symbol.kind),
                  let decision = deniedByUSR[group.usr] else {
                continue
            }
            let categories = denialCategories(for: decision, group: group)
            guard !decision.hasReason(startingWith: "no declaration or definition occurrence"),
                  !isBaselineHardContract(decision) else {
                continue
            }

            members.append(CoverageCohortMember(
                usr: group.usr,
                originalName: decision.oldName ?? group.symbol.name,
                kind: group.symbol.kind,
                baselineStatus: .engineeringCandidate,
                baselineDenialCategories: sortedCategories(categories)
            ))
        }

        members.sort { $0.usr < $1.usr }
        if let expectedCount, members.count != expectedCount {
            throw CoverageReportError.generatedCohortCountMismatch(expected: expectedCount, actual: members.count)
        }

        return CoverageCohort(
            formatVersion: CoverageCohort.currentFormatVersion,
            identifier: identifier,
            denominator: members.count,
            membersSHA256: CoverageCohort.digest(of: members),
            baselineIndexedSymbols: snapshot.symbols.count,
            baselineIndexedOccurrences: snapshot.occurrences.count,
            baselineRenamedSymbols: plan.entries.count,
            members: members
        )
    }

    public static func makeReport(
        cohort: CoverageCohort,
        snapshot: IndexSnapshot,
        plan: RenamePlan
    ) throws -> CoverageReport {
        try cohort.validate()
        let plannedByUSR = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.usr, $0) })
        let deniedByUSR = Dictionary(uniqueKeysWithValues: plan.denied.map { ($0.usr, $0) })
        let groups = snapshot.groupsByUSR
        let groupsByUSR = Dictionary(uniqueKeysWithValues: groups.map { ($0.usr, $0) })
        var results: [CoverageMemberResult] = []

        for member in cohort.members {
            if let entry = plannedByUSR[member.usr] {
                results.append(CoverageMemberResult(
                    usr: member.usr,
                    originalName: member.originalName,
                    kind: member.kind,
                    status: .renamed,
                    newName: entry.newName,
                    denialCategories: [],
                    denialReasons: []
                ))
            } else if let decision = deniedByUSR[member.usr] {
                let categories = denialCategories(for: decision, group: groupsByUSR[member.usr])
                results.append(CoverageMemberResult(
                    usr: member.usr,
                    originalName: member.originalName,
                    kind: member.kind,
                    status: .denied,
                    newName: nil,
                    denialCategories: sortedCategories(categories),
                    denialReasons: decision.reasons
                ))
            } else if groupsByUSR[member.usr] == nil {
                results.append(CoverageMemberResult(
                    usr: member.usr,
                    originalName: member.originalName,
                    kind: member.kind,
                    status: .missingFromIndex,
                    newName: nil,
                    denialCategories: [.missingFromIndex],
                    denialReasons: ["cohort USR missing from current index"]
                ))
            } else {
                results.append(CoverageMemberResult(
                    usr: member.usr,
                    originalName: member.originalName,
                    kind: member.kind,
                    status: .unclassified,
                    newName: nil,
                    denialCategories: [.unclassified],
                    denialReasons: ["cohort USR is neither planned nor represented in denied decisions"]
                ))
            }
        }

        let renamed = results.count { $0.status == .renamed }
        let denied = results.count { $0.status == .denied }
        let missing = results.count { $0.status == .missingFromIndex }
        let unclassified = results.count { $0.status == .unclassified }
        let byKind = Dictionary(grouping: results, by: \.kind).map { kind, members in
            let kindRenamed = members.count { $0.status == .renamed }
            let kindDenied = members.count { $0.status == .denied }
            let kindMissing = members.count - kindRenamed - kindDenied
            return CoverageKindSummary(
                kind: kind,
                denominator: members.count,
                renamed: kindRenamed,
                denied: kindDenied,
                missingOrUnclassified: kindMissing,
                coveragePercent: percent(kindRenamed, of: members.count)
            )
        }.sorted { $0.kind < $1.kind }

        var allCategoryCounts: [CoverageDenialCategory: Int] = [:]
        var primaryCategoryCounts: [CoverageDenialCategory: Int] = [:]
        for result in results where result.status != .renamed {
            let categories = result.denialCategories.isEmpty ? [.other] : result.denialCategories
            for category in categories {
                allCategoryCounts[category, default: 0] += 1
            }
            primaryCategoryCounts[primaryCategory(in: categories), default: 0] += 1
        }

        return CoverageReport(
            formatVersion: CoverageReport.currentFormatVersion,
            cohortIdentifier: cohort.identifier,
            cohortMembersSHA256: cohort.membersSHA256,
            denominator: cohort.denominator,
            renamed: renamed,
            denied: denied,
            missingFromIndex: missing,
            unclassified: unclassified,
            coveragePercent: percent(renamed, of: cohort.denominator),
            indexedSymbols: snapshot.symbols.count,
            indexedOccurrences: snapshot.occurrences.count,
            plannedSymbols: plan.entries.count,
            plannedReplacements: plan.replacements.count,
            conflicts: plan.conflicts.count,
            bySymbolKind: byKind,
            primaryDenialReasons: summaries(from: primaryCategoryCounts),
            allDenialReasons: summaries(from: allCategoryCounts),
            syntheticAccessors: syntheticAccessorSummary(groups: groups, plan: plan),
            members: results
        )
    }

    public static func accessorParentUSRs(for group: USROccurrenceGroup) -> Set<String> {
        Set(group.occurrences.flatMap(\.relations).compactMap { relation in
            relation.roles.contains("accessorOf") ? relation.usr : nil
        })
    }

    public static func isSyntheticAccessor(_ group: USROccurrenceGroup) -> Bool {
        let name = group.symbol.name.lowercased()
        return name.hasPrefix("getter:") || name.hasPrefix("setter:")
    }

    public static func denialCategories(
        for decision: SafetyDecision,
        group: USROccurrenceGroup? = nil
    ) -> Set<CoverageDenialCategory> {
        if let group, isSyntheticAccessor(group) {
            return [.syntheticAccessor]
        }

        var categories: Set<CoverageDenialCategory> = []
        if decision.kind == "parameter" {
            categories.insert(.parameter)
        }
        if decision.kind == "enumConstant" {
            categories.insert(.enumCase)
        }

        for reason in decision.reasons {
            if reason.contains("unsupported symbol kind") {
                categories.insert(decision.kind == "enumConstant" ? .enumCase : .unsupportedSymbolKind)
            }
            if reason.contains("Objective-C-compatible USR")
                || reason.contains("runtime-reflected or externally linked declaration")
                || reason.contains("Interface Builder resource requires stable class name") {
                categories.insert(.objectiveCRuntimeContract)
            }
            if reason.contains("no declaration or definition occurrence") {
                categories.insert(.noLocalDeclaration)
            }
            if reason.contains("system occurrence")
                || reason.contains("occurrence outside source root")
                || reason.contains("implicit occurrence")
                || reason.contains("extensions on external Swift or Objective-C owners")
                || reason.contains("language-required declaration name")
                || reason == "empty USR"
                || reason == "no occurrences" {
                categories.insert(.externalLanguageContract)
            }
            if reason.contains("stored property declarations require memberwise initializer label support") {
                categories.insert(.storedProperty)
            }
            if reason.contains("protocol members require relation-aware witness renaming") {
                categories.insert(.protocolRequirementWitness)
            }
            if reason.contains("override relations require coordinated renaming") {
                categories.insert(.overrideBaseComponent)
            }
            if reason.contains("unsafe relation") {
                if groupHasOverrideOrBaseRelation(group) {
                    categories.insert(.overrideBaseComponent)
                } else {
                    categories.insert(.externalLanguageContract)
                }
            }
            if reason.contains("backticked identifier") || reason.contains("non-plain identifier") {
                categories.insert(.nonPlainIdentifier)
            }
            if reason.contains("generic type parameter occurrences are incomplete") {
                categories.insert(.genericParameter)
            }
            if reason.contains("tuple typealias constructor occurrences are incomplete") {
                categories.insert(.tupleTypealias)
            }
            if reason.contains("identifier token unavailable") {
                categories.insert(.identifierTokenUnavailable)
            }
            if reason.contains("occurrences resolve to multiple source tokens") || reason.contains("token mismatch") {
                categories.insert(.ambiguousSourceTokens)
            }
            if reason.contains("source file unavailable") || reason == "no source replacements" {
                categories.insert(.sourceValidation)
            }
        }
        if categories.isEmpty {
            categories.insert(.other)
        }
        return categories
    }

    private static func groupHasOverrideOrBaseRelation(_ group: USROccurrenceGroup?) -> Bool {
        guard let group else {
            return false
        }
        return group.occurrences.flatMap(\.relations).contains { relation in
            relation.roles.contains("overrideOf") || relation.roles.contains("baseOf")
        }
    }

    private static func isBaselineHardContract(_ decision: SafetyDecision) -> Bool {
        decision.hasReason(startingWith: "Objective-C-compatible USR")
            || decision.hasReason(startingWith: "runtime-reflected or externally linked")
            || decision.hasReason(startingWith: "Interface Builder resource requires stable class name")
            || decision.hasReason(startingWith: "language-required declaration name")
            || decision.hasReason(startingWith: "extensions on external Swift or Objective-C owners")
    }

    private static func syntheticAccessorSummary(groups: [USROccurrenceGroup], plan: RenamePlan) -> SyntheticAccessorSummary {
        let plannedUSRs = Set(plan.entries.map(\.usr))
        let indexedUSRs = Set(groups.map(\.usr))
        var total = 0
        var getters = 0
        var setters = 0
        var other = 0
        var derivedRenamed = 0
        var derivedUnchanged = 0
        var unresolvedParent = 0
        var unexpectedlyPlanned = 0

        for group in groups {
            guard isSyntheticAccessor(group) else {
                continue
            }
            let parents = accessorParentUSRs(for: group)
            total += 1
            let lowercasedName = group.symbol.name.lowercased()
            if lowercasedName.hasPrefix("getter:") {
                getters += 1
            } else if lowercasedName.hasPrefix("setter:") {
                setters += 1
            } else {
                other += 1
            }
            if plannedUSRs.contains(group.usr) {
                unexpectedlyPlanned += 1
            }
            if !parents.isDisjoint(with: plannedUSRs) {
                derivedRenamed += 1
            } else if !parents.isDisjoint(with: indexedUSRs) {
                derivedUnchanged += 1
            } else {
                unresolvedParent += 1
            }
        }

        return SyntheticAccessorSummary(
            total: total,
            getters: getters,
            setters: setters,
            other: other,
            derivedRenamed: derivedRenamed,
            derivedUnchanged: derivedUnchanged,
            unresolvedParent: unresolvedParent,
            unexpectedlyPlanned: unexpectedlyPlanned
        )
    }

    private static func primaryCategory(in categories: [CoverageDenialCategory]) -> CoverageDenialCategory {
        let priority: [CoverageDenialCategory] = [
            .missingFromIndex,
            .unclassified,
            .syntheticAccessor,
            .parameter,
            .storedProperty,
            .protocolRequirementWitness,
            .overrideBaseComponent,
            .ambiguousSourceTokens,
            .nonPlainIdentifier,
            .identifierTokenUnavailable,
            .genericParameter,
            .tupleTypealias,
            .enumCase,
            .unsupportedSymbolKind,
            .objectiveCRuntimeContract,
            .noLocalDeclaration,
            .externalLanguageContract,
            .sourceValidation,
            .other
        ]
        return priority.first(where: { categories.contains($0) }) ?? .other
    }

    private static func sortedCategories(_ categories: Set<CoverageDenialCategory>) -> [CoverageDenialCategory] {
        categories.sorted { $0.rawValue < $1.rawValue }
    }

    private static func summaries(
        from counts: [CoverageDenialCategory: Int]
    ) -> [CoverageDenialSummary] {
        counts.map { CoverageDenialSummary(category: $0.key, members: $0.value) }
            .sorted { lhs, rhs in
                lhs.members == rhs.members
                    ? lhs.category.rawValue < rhs.category.rawValue
                    : lhs.members > rhs.members
            }
    }

    private static func percent(_ numerator: Int, of denominator: Int) -> Double {
        guard denominator > 0 else {
            return 0
        }
        return Double(numerator) * 100 / Double(denominator)
    }
}

private extension SafetyDecision {
    func hasReason(startingWith prefix: String) -> Bool {
        reasons.contains { $0.hasPrefix(prefix) }
    }
}
