import Foundation

public enum ExternalLabel: Hashable, Sendable {
    case omitted
    case named(String)
    case unavailable
}

/// Compiler-index-backed model of one callable signature and its parameters.
///
/// The callable is the atomic unit because argument-label edits at declarations
/// and call sites must agree. Each member still keeps its local binding and
/// external label separate; sharing a source token does not merge those roles.
public struct CallableSignature: Hashable, Sendable {
    public enum OwnerKind: String, Codable, Hashable, Sendable {
        case callable
        case subscriptDeclaration
        case enumCase
    }

    public struct Parameter: Hashable, Sendable {
        public let parameterUSR: String
        public let ordinal: Int
        public let localBinding: String
        public let externalLabel: ExternalLabel
        public let declarationLocations: [IndexSnapshot.Location]
        public let referenceLocations: [IndexSnapshot.Location]
    }

    public let callableUSR: String
    public let callableName: String
    public let callableKind: String
    public let ownerCategory: OwnerKind
    public let parameters: [Parameter]
    public let declarationLocations: [IndexSnapshot.Location]
    public let callLocations: [IndexSnapshot.Location]
    public let nonCallReferenceLocations: [IndexSnapshot.Location]
    public let hasOccurrenceOutsideSelectedRoots: Bool
    public let isProtocolRequirement: Bool
    public let isOverrideRelated: Bool
    public let isRuntimeSensitive: Bool
    public let isExternallyOwned: Bool
    public let structuralReasons: [String]

    public var isStructurallyComplete: Bool {
        structuralReasons.isEmpty
            && parameters.allSatisfy { $0.externalLabel != .unavailable }
    }

    /// Enum associated-value labels occur both in constructor calls and in
    /// switch/catch patterns. IndexStore marks the latter as non-call
    /// references even though SwiftSyntax represents their argument list with
    /// the same `FunctionCallExprSyntax` shape. Ordinary callables keep their
    /// function-reference anchors in the separate callable-reference stage.
    var externalLabelArgumentLocations: [IndexSnapshot.Location] {
        let locations =
            ownerCategory == .enumCase
            ? callLocations + nonCallReferenceLocations
            : callLocations
        return Array(Set(locations)).sorted {
            ($0.path, $0.line, $0.utf8Column)
                < ($1.path, $1.line, $1.utf8Column)
        }
    }
}

extension CallableSignature {
    public struct Report: Codable, Equatable, Sendable {
        public let explicitParameters: Int
        public let modeledParameters: Int
        public let unmodeledParameters: Int
        public let signatures: Int
        public let structurallyCompleteSignatures: Int
        public let structurallyCompleteParameters: Int
        public let omittedExternalLabels: Int
        public let sharedLabelAndBindingParameters: Int
        public let distinctLabelAndBindingParameters: Int
        public let unavailableExternalLabels: Int
        public let callAnchors: Int
        public let functionReferenceAnchors: Int
        public let enumCaseReferenceAnchors: Int
        public let signaturesWithOccurrencesOutsideSelectedRoots: Int
        public let protocolRequirementSignatures: Int
        public let overrideRelatedSignatures: Int
        public let runtimeSensitiveSignatures: Int
        public let externallyOwnedSignatures: Int
        public let subscriptSignatures: Int
        public let subscriptParameters: Int
        public let enumCaseSignatures: Int
        public let enumCaseParameters: Int

        public static let empty = CallableSignature.Report(
            explicitParameters: 0,
            signatures: []
        )

        init(explicitParameters: Int, signatures: [CallableSignature]) {
            let modeledParameters = signatures.reduce(0) { $0 + $1.parameters.count }
            self.explicitParameters = explicitParameters
            self.modeledParameters = modeledParameters
            self.unmodeledParameters = max(0, explicitParameters - modeledParameters)
            self.signatures = signatures.count
            self.structurallyCompleteSignatures = signatures.count(where: \.isStructurallyComplete)
            self.structurallyCompleteParameters =
                signatures
                .filter(\.isStructurallyComplete)
                .reduce(0) { $0 + $1.parameters.count }
            self.omittedExternalLabels = signatures.flatMap(\.parameters).count {
                $0.externalLabel == .omitted
            }
            self.sharedLabelAndBindingParameters = signatures.flatMap(\.parameters).count {
                parameter in
                parameter.externalLabel == .named(parameter.localBinding)
            }
            self.distinctLabelAndBindingParameters = signatures.flatMap(\.parameters).count {
                parameter in
                guard case .named(let label) = parameter.externalLabel else {
                    return false
                }
                return label != parameter.localBinding
            }
            self.unavailableExternalLabels = signatures.flatMap(\.parameters).count {
                $0.externalLabel == .unavailable
            }
            self.callAnchors = signatures.reduce(0) { $0 + $1.callLocations.count }
            self.functionReferenceAnchors =
                signatures
                .filter { $0.ownerCategory != .enumCase }
                .reduce(0) {
                    $0 + $1.nonCallReferenceLocations.count
                }
            self.enumCaseReferenceAnchors =
                signatures
                .filter { $0.ownerCategory == .enumCase }
                .reduce(0) {
                    $0 + $1.nonCallReferenceLocations.count
                }
            self.signaturesWithOccurrencesOutsideSelectedRoots = signatures.count {
                $0.hasOccurrenceOutsideSelectedRoots
            }
            self.protocolRequirementSignatures = signatures.count(where: \.isProtocolRequirement)
            self.overrideRelatedSignatures = signatures.count(where: \.isOverrideRelated)
            self.runtimeSensitiveSignatures = signatures.count(where: \.isRuntimeSensitive)
            self.externallyOwnedSignatures = signatures.count(where: \.isExternallyOwned)
            self.subscriptSignatures = signatures.count {
                $0.ownerCategory == .subscriptDeclaration
            }
            self.subscriptParameters =
                signatures
                .filter { $0.ownerCategory == .subscriptDeclaration }
                .reduce(0) { $0 + $1.parameters.count }
            self.enumCaseSignatures = signatures.count { $0.ownerCategory == .enumCase }
            self.enumCaseParameters =
                signatures
                .filter { $0.ownerCategory == .enumCase }
                .reduce(0) { $0 + $1.parameters.count }
        }

        private enum CodingKeys: String, CodingKey {
            case explicitParameters
            case modeledParameters
            case unmodeledParameters
            case signatures = "components"
            case structurallyCompleteSignatures = "structurallyCompleteComponents"
            case structurallyCompleteParameters
            case omittedExternalLabels
            case sharedLabelAndBindingParameters
            case distinctLabelAndBindingParameters
            case unavailableExternalLabels
            case callAnchors
            case functionReferenceAnchors
            case enumCaseReferenceAnchors
            case signaturesWithOccurrencesOutsideSelectedRoots =
                "componentsWithOccurrencesOutsideSelectedRoots"
            case protocolRequirementSignatures = "protocolRequirementComponents"
            case overrideRelatedSignatures = "overrideRelatedComponents"
            case runtimeSensitiveSignatures = "runtimeSensitiveComponents"
            case externallyOwnedSignatures = "externallyOwnedComponents"
            case subscriptSignatures = "subscriptComponents"
            case subscriptParameters
            case enumCaseSignatures = "enumCaseComponents"
            case enumCaseParameters
        }
    }

}

extension CallableSignature {
    enum Builder {
        static func makeSignatures(
            snapshot: IndexSnapshot,
            rootPaths: [String],
            symbolsByUSR: [String: IndexSnapshot.Symbol],
            protocolRequirementUSRs: Set<String>,
            overrideRelatedUSRs: Set<String>,
            runtimeSensitiveUSRs: Set<String>,
            externallyOwnedUSRs: Set<String>
        ) -> [CallableSignature] {
            let occurrencesByUSR = Dictionary(grouping: snapshot.occurrences) { $0.usr }
            var parametersByCallableUSR: [String: Set<String>] = [:]

            for occurrence in snapshot.occurrences {
                guard occurrence.symbol.isKind(.parameter),
                    !occurrence.hasRole(.implicit),
                    occurrence.hasRole(.declaration) || occurrence.hasRole(.definition),
                    isPath(occurrence.path, underRootPaths: rootPaths)
                else {
                    continue
                }
                let callableOwners = Set(
                    occurrence.relations.compactMap { relation -> String? in
                        guard relation.hasRole(.childOf),
                            symbolsByUSR[relation.usr].flatMap(ownerCategory) != nil
                        else {
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
                    let ownerCategory = ownerCategory(for: callable)
                else {
                    return nil
                }
                let orderedParameters = parameterUSRs.compactMap {
                    parameterUSR -> (
                        symbol: IndexSnapshot.Symbol,
                        declarations: [IndexSnapshot.Occurrence],
                        references: [IndexSnapshot.Occurrence]
                    )? in
                    guard let parameter = symbolsByUSR[parameterUSR] else {
                        return nil
                    }
                    let occurrences = occurrencesByUSR[parameterUSR] ?? []
                    let declarations = occurrences.filter {
                        !$0.hasRole(.implicit)
                            && ($0.hasRole(.declaration) || $0.hasRole(.definition))
                            && isPath($0.path, underRootPaths: rootPaths)
                    }
                    guard !declarations.isEmpty else {
                        return nil
                    }
                    let references = occurrences.filter {
                        !$0.hasRole(.implicit)
                            && !$0.hasRole(.declaration)
                            && !$0.hasRole(.definition)
                            && isPath($0.path, underRootPaths: rootPaths)
                    }
                    return (parameter, declarations, references)
                }.sorted { lhs, rhs in
                    let lhsLocation = lhs.declarations.map(sourceLocation).sorted(
                        by: locationPrecedes
                    ).first
                    let rhsLocation = rhs.declarations.map(sourceLocation).sorted(
                        by: locationPrecedes
                    ).first
                    guard let lhsLocation, let rhsLocation else {
                        return lhs.symbol.usr < rhs.symbol.usr
                    }
                    return (
                        lhsLocation.path, lhsLocation.line, lhsLocation.utf8Column, lhs.symbol.usr
                    )
                        < (
                            rhsLocation.path, rhsLocation.line, rhsLocation.utf8Column,
                            rhs.symbol.usr
                        )
                }

                var structuralReasons: [String] = []
                if orderedParameters.count != parameterUSRs.count {
                    structuralReasons.append(
                        "one or more indexed parameters have no explicit declaration")
                }
                if orderedParameters.contains(where: { uniqueLocations($0.declarations).count != 1 }
                ) {
                    structuralReasons.append(
                        "one or more indexed parameters have ambiguous declaration locations")
                }
                let labels = externalParameterLabels(from: callable.name)
                if labels?.count != orderedParameters.count {
                    structuralReasons.append(
                        "callable index name does not expose exactly \(orderedParameters.count) external argument label(s)"
                    )
                }
                let resolvedLabels = labels?.count == orderedParameters.count ? labels : nil

                let parameters = orderedParameters.enumerated().map { ordinal, parameter in
                    CallableSignature.Parameter(
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
                    !$0.hasRole(.implicit) && isPath($0.path, underRootPaths: rootPaths)
                }
                let declarations = selectedCallableOccurrences.filter {
                    $0.hasRole(.declaration) || $0.hasRole(.definition)
                }
                let declarationLocations = uniqueLocations(declarations)
                if declarationLocations.count != 1 {
                    structuralReasons.append(
                        "callable does not have exactly one declaration location inside selected source roots"
                    )
                }
                let calls = selectedCallableOccurrences.filter { $0.hasRole(.call) }
                let functionReferences = selectedCallableOccurrences.filter {
                    $0.hasRole(.reference)
                        && !$0.hasRole(.call)
                        && !$0.hasRole(.declaration)
                        && !$0.hasRole(.definition)
                }

                return CallableSignature(
                    callableUSR: callableUSR,
                    callableName: callable.name,
                    callableKind: callable.kind,
                    ownerCategory: ownerCategory,
                    parameters: parameters,
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

        private static func externalParameterLabels(from callableName: String) -> [ExternalLabel]? {
            guard let openingParenthesis = callableName.firstIndex(of: "("),
                callableName.last == ")"
            else {
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
            guard
                rawLabels.allSatisfy({ label in
                    !label.isEmpty
                        && !label.contains(where: { $0.isWhitespace || $0 == "(" || $0 == ")" })
                })
            else {
                return nil
            }
            return rawLabels.map { label in
                label == "_" ? .omitted : .named(String(label))
            }
        }

        private static func ownerCategory(for symbol: IndexSnapshot.Symbol) -> CallableSignature
            .OwnerKind?
        {
            let callableKinds = IndexSymbolKind.rawValues(
                .function,
                .instanceMethod,
                .staticMethod,
                .classMethod,
                .constructor
            )
            if callableKinds.contains(symbol.kind) {
                return .callable
            }
            if symbol.isKind(.enumConstant) {
                return .enumCase
            }
            let propertyKinds = IndexSymbolKind.rawValues(
                .instanceProperty, .staticProperty, .classProperty)
            if propertyKinds.contains(symbol.kind), symbol.name.hasPrefix("subscript(") {
                return .subscriptDeclaration
            }
            return nil
        }

        private static func uniqueLocations(_ occurrences: [IndexSnapshot.Occurrence])
            -> [IndexSnapshot.Location]
        {
            Array(Set(occurrences.map(sourceLocation))).sorted(by: locationPrecedes)
        }

        private static func sourceLocation(_ occurrence: IndexSnapshot.Occurrence)
            -> IndexSnapshot.Location
        {
            IndexSnapshot.Location(
                path: occurrence.path,
                line: occurrence.line,
                utf8Column: occurrence.utf8Column
            )
        }

        private static func locationPrecedes(
            _ lhs: IndexSnapshot.Location,
            _ rhs: IndexSnapshot.Location
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

}
