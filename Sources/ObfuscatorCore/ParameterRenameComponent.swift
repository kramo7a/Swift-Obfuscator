import Foundation

public struct IndexedSourceLocation: Hashable, Sendable {
    public let path: String
    public let line: Int
    public let utf8Column: Int

    public init(path: String, line: Int, utf8Column: Int) {
        self.path = SourcePathNormalizer.canonicalPath(path)
        self.line = line
        self.utf8Column = utf8Column
    }
}

public enum ParameterExternalLabel: Hashable, Sendable {
    case omitted
    case named(String)
    case unavailable
}

public enum ParameterOwnerCategory: String, Codable, Hashable, Sendable {
    case callable
    case subscriptDeclaration
    case enumCase
}

public struct ParameterRenameMember: Hashable, Sendable {
    public let parameterUSR: String
    public let ordinal: Int
    public let localBinding: String
    public let externalLabel: ParameterExternalLabel
    public let declarationLocations: [IndexedSourceLocation]
    public let referenceLocations: [IndexedSourceLocation]
}

/// Compiler-index-backed facts for the parameters of one callable signature.
///
/// The callable is the atomic unit because argument-label edits at declarations
/// and call sites must agree. Each member still keeps its local binding and
/// external label separate; sharing a source token does not merge those roles.
public struct ParameterRenameComponent: Hashable, Sendable {
    public let callableUSR: String
    public let callableName: String
    public let callableKind: String
    public let ownerCategory: ParameterOwnerCategory
    public let members: [ParameterRenameMember]
    public let declarationLocations: [IndexedSourceLocation]
    public let callLocations: [IndexedSourceLocation]
    public let nonCallReferenceLocations: [IndexedSourceLocation]
    public let hasOccurrenceOutsideSelectedRoots: Bool
    public let isProtocolRequirement: Bool
    public let isOverrideRelated: Bool
    public let isRuntimeSensitive: Bool
    public let isExternallyOwned: Bool
    public let structuralReasons: [String]

    public var isStructurallyComplete: Bool {
        structuralReasons.isEmpty
            && members.allSatisfy { $0.externalLabel != .unavailable }
    }
}

public struct ParameterFactsSummary: Codable, Equatable, Sendable {
    public let explicitParameters: Int
    public let modeledParameters: Int
    public let unmodeledParameters: Int
    public let components: Int
    public let structurallyCompleteComponents: Int
    public let structurallyCompleteParameters: Int
    public let omittedExternalLabels: Int
    public let sharedLabelAndBindingParameters: Int
    public let distinctLabelAndBindingParameters: Int
    public let unavailableExternalLabels: Int
    public let callAnchors: Int
    public let functionReferenceAnchors: Int
    public let enumCaseReferenceAnchors: Int
    public let componentsWithOccurrencesOutsideSelectedRoots: Int
    public let protocolRequirementComponents: Int
    public let overrideRelatedComponents: Int
    public let runtimeSensitiveComponents: Int
    public let externallyOwnedComponents: Int
    public let subscriptComponents: Int
    public let subscriptParameters: Int
    public let enumCaseComponents: Int
    public let enumCaseParameters: Int

    public static let empty = ParameterFactsSummary(
        explicitParameters: 0,
        components: []
    )

    init(explicitParameters: Int, components: [ParameterRenameComponent]) {
        let modeledParameters = components.reduce(0) { $0 + $1.members.count }
        self.explicitParameters = explicitParameters
        self.modeledParameters = modeledParameters
        self.unmodeledParameters = max(0, explicitParameters - modeledParameters)
        self.components = components.count
        self.structurallyCompleteComponents = components.count(where: \.isStructurallyComplete)
        self.structurallyCompleteParameters = components
            .filter(\.isStructurallyComplete)
            .reduce(0) { $0 + $1.members.count }
        self.omittedExternalLabels = components.flatMap(\.members).count {
            $0.externalLabel == .omitted
        }
        self.sharedLabelAndBindingParameters = components.flatMap(\.members).count { member in
            member.externalLabel == .named(member.localBinding)
        }
        self.distinctLabelAndBindingParameters = components.flatMap(\.members).count { member in
            guard case .named(let label) = member.externalLabel else {
                return false
            }
            return label != member.localBinding
        }
        self.unavailableExternalLabels = components.flatMap(\.members).count {
            $0.externalLabel == .unavailable
        }
        self.callAnchors = components.reduce(0) { $0 + $1.callLocations.count }
        self.functionReferenceAnchors = components
            .filter { $0.ownerCategory != .enumCase }
            .reduce(0) {
                $0 + $1.nonCallReferenceLocations.count
            }
        self.enumCaseReferenceAnchors = components
            .filter { $0.ownerCategory == .enumCase }
            .reduce(0) {
                $0 + $1.nonCallReferenceLocations.count
            }
        self.componentsWithOccurrencesOutsideSelectedRoots = components.count {
            $0.hasOccurrenceOutsideSelectedRoots
        }
        self.protocolRequirementComponents = components.count(where: \.isProtocolRequirement)
        self.overrideRelatedComponents = components.count(where: \.isOverrideRelated)
        self.runtimeSensitiveComponents = components.count(where: \.isRuntimeSensitive)
        self.externallyOwnedComponents = components.count(where: \.isExternallyOwned)
        self.subscriptComponents = components.count {
            $0.ownerCategory == .subscriptDeclaration
        }
        self.subscriptParameters = components
            .filter { $0.ownerCategory == .subscriptDeclaration }
            .reduce(0) { $0 + $1.members.count }
        self.enumCaseComponents = components.count { $0.ownerCategory == .enumCase }
        self.enumCaseParameters = components
            .filter { $0.ownerCategory == .enumCase }
            .reduce(0) { $0 + $1.members.count }
    }
}

enum ParameterRenameComponentBuilder {
    static func makeComponents(
        snapshot: IndexSnapshot,
        rootPaths: [String],
        symbolsByUSR: [String: SymbolRecord],
        protocolRequirementUSRs: Set<String>,
        overrideRelatedUSRs: Set<String>,
        runtimeSensitiveUSRs: Set<String>,
        externallyOwnedUSRs: Set<String>
    ) -> [ParameterRenameComponent] {
        let occurrencesByUSR = Dictionary(grouping: snapshot.occurrences) { $0.usr }
        var parametersByCallableUSR: [String: Set<String>] = [:]

        for occurrence in snapshot.occurrences {
            guard occurrence.symbol.kind == "parameter",
                  !occurrence.roles.contains("implicit"),
                  occurrence.roles.contains("declaration") || occurrence.roles.contains("definition"),
                  isPath(occurrence.path, underRootPaths: rootPaths) else {
                continue
            }
            let callableOwners = Set(occurrence.relations.compactMap { relation -> String? in
                guard relation.roles.contains("childOf"),
                      symbolsByUSR[relation.usr].flatMap(ownerCategory) != nil else {
                    return nil
                }
                return relation.usr
            })
            guard callableOwners.count == 1, let callableUSR = callableOwners.first else {
                continue
            }
            parametersByCallableUSR[callableUSR, default: []].insert(occurrence.usr)
        }

        return parametersByCallableUSR.compactMap { callableUSR, parameterUSRs in
            guard let callable = symbolsByUSR[callableUSR],
                  let ownerCategory = ownerCategory(for: callable) else {
                return nil
            }
            let orderedParameters = parameterUSRs.compactMap { parameterUSR -> (
                symbol: SymbolRecord,
                declarations: [OccurrenceRecord],
                references: [OccurrenceRecord]
            )? in
                guard let parameter = symbolsByUSR[parameterUSR] else {
                    return nil
                }
                let occurrences = occurrencesByUSR[parameterUSR] ?? []
                let declarations = occurrences.filter {
                    !$0.roles.contains("implicit")
                        && ($0.roles.contains("declaration") || $0.roles.contains("definition"))
                        && isPath($0.path, underRootPaths: rootPaths)
                }
                guard !declarations.isEmpty else {
                    return nil
                }
                let references = occurrences.filter {
                    !$0.roles.contains("implicit")
                        && !$0.roles.contains("declaration")
                        && !$0.roles.contains("definition")
                        && isPath($0.path, underRootPaths: rootPaths)
                }
                return (parameter, declarations, references)
            }.sorted { lhs, rhs in
                let lhsLocation = lhs.declarations.map(sourceLocation).sorted(by: locationPrecedes).first
                let rhsLocation = rhs.declarations.map(sourceLocation).sorted(by: locationPrecedes).first
                guard let lhsLocation, let rhsLocation else {
                    return lhs.symbol.usr < rhs.symbol.usr
                }
                return (lhsLocation.path, lhsLocation.line, lhsLocation.utf8Column, lhs.symbol.usr)
                    < (rhsLocation.path, rhsLocation.line, rhsLocation.utf8Column, rhs.symbol.usr)
            }

            var structuralReasons: [String] = []
            if orderedParameters.count != parameterUSRs.count {
                structuralReasons.append("one or more indexed parameters have no explicit declaration")
            }
            if orderedParameters.contains(where: { uniqueLocations($0.declarations).count != 1 }) {
                structuralReasons.append("one or more indexed parameters have ambiguous declaration locations")
            }
            let labels = externalParameterLabels(from: callable.name)
            if labels?.count != orderedParameters.count {
                structuralReasons.append(
                    "callable index name does not expose exactly \(orderedParameters.count) external argument label(s)"
                )
            }
            let resolvedLabels = labels?.count == orderedParameters.count ? labels : nil

            let members = orderedParameters.enumerated().map { ordinal, parameter in
                ParameterRenameMember(
                    parameterUSR: parameter.symbol.usr,
                    ordinal: ordinal,
                    localBinding: parameter.symbol.name,
                    externalLabel: resolvedLabels?[ordinal] ?? .unavailable,
                    declarationLocations: uniqueLocations(parameter.declarations),
                    referenceLocations: uniqueLocations(parameter.references)
                )
            }

            let callableOccurrences = occurrencesByUSR[callableUSR] ?? []
            let selectedCallableOccurrences = callableOccurrences.filter {
                !$0.roles.contains("implicit") && isPath($0.path, underRootPaths: rootPaths)
            }
            let declarations = selectedCallableOccurrences.filter {
                $0.roles.contains("declaration") || $0.roles.contains("definition")
            }
            let declarationLocations = uniqueLocations(declarations)
            if declarationLocations.count != 1 {
                structuralReasons.append(
                    "callable does not have exactly one declaration location inside selected source roots"
                )
            }
            let calls = selectedCallableOccurrences.filter { $0.roles.contains("call") }
            let functionReferences = selectedCallableOccurrences.filter {
                $0.roles.contains("reference")
                    && !$0.roles.contains("call")
                    && !$0.roles.contains("declaration")
                    && !$0.roles.contains("definition")
            }

            return ParameterRenameComponent(
                callableUSR: callableUSR,
                callableName: callable.name,
                callableKind: callable.kind,
                ownerCategory: ownerCategory,
                members: members,
                declarationLocations: declarationLocations,
                callLocations: uniqueLocations(calls),
                nonCallReferenceLocations: uniqueLocations(functionReferences),
                hasOccurrenceOutsideSelectedRoots: callableOccurrences.contains {
                    !isPath($0.path, underRootPaths: rootPaths)
                },
                isProtocolRequirement: protocolRequirementUSRs.contains(callableUSR),
                isOverrideRelated: overrideRelatedUSRs.contains(callableUSR),
                isRuntimeSensitive: runtimeSensitiveUSRs.contains(callableUSR),
                isExternallyOwned: externallyOwnedUSRs.contains(callableUSR),
                structuralReasons: Array(Set(structuralReasons)).sorted()
            )
        }.sorted { $0.callableUSR < $1.callableUSR }
    }

    private static func externalParameterLabels(from callableName: String) -> [ParameterExternalLabel]? {
        guard let openingParenthesis = callableName.firstIndex(of: "("),
              callableName.last == ")" else {
            return nil
        }
        let bodyStart = callableName.index(after: openingParenthesis)
        let bodyEnd = callableName.index(before: callableName.endIndex)
        let body = callableName[bodyStart..<bodyEnd]
        guard !body.isEmpty else {
            return []
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.last?.isEmpty == true else {
            return nil
        }
        let rawLabels = parts.dropLast()
        guard rawLabels.allSatisfy({ label in
            !label.isEmpty
                && !label.contains(where: { $0.isWhitespace || $0 == "(" || $0 == ")" })
        }) else {
            return nil
        }
        return rawLabels.map { label in
            label == "_" ? .omitted : .named(String(label))
        }
    }

    private static func ownerCategory(for symbol: SymbolRecord) -> ParameterOwnerCategory? {
        let callableKinds: Set<String> = [
            "function", "instanceMethod", "staticMethod", "classMethod", "constructor"
        ]
        if callableKinds.contains(symbol.kind) {
            return .callable
        }
        if symbol.kind == "enumConstant" {
            return .enumCase
        }
        let propertyKinds: Set<String> = ["instanceProperty", "staticProperty", "classProperty"]
        if propertyKinds.contains(symbol.kind), symbol.name.hasPrefix("subscript(") {
            return .subscriptDeclaration
        }
        return nil
    }

    private static func uniqueLocations(_ occurrences: [OccurrenceRecord]) -> [IndexedSourceLocation] {
        Array(Set(occurrences.map(sourceLocation))).sorted(by: locationPrecedes)
    }

    private static func sourceLocation(_ occurrence: OccurrenceRecord) -> IndexedSourceLocation {
        IndexedSourceLocation(
            path: occurrence.path,
            line: occurrence.line,
            utf8Column: occurrence.utf8Column
        )
    }

    private static func locationPrecedes(
        _ lhs: IndexedSourceLocation,
        _ rhs: IndexedSourceLocation
    ) -> Bool {
        (lhs.path, lhs.line, lhs.utf8Column) < (rhs.path, rhs.line, rhs.utf8Column)
    }

    private static func isPath(_ path: String, underRootPaths rootPaths: [String]) -> Bool {
        let canonicalPath = SourcePathNormalizer.canonicalPath(path)
        return rootPaths.contains { rootPath in
            canonicalPath == rootPath || canonicalPath.hasPrefix(rootPath + "/")
        }
    }
}
