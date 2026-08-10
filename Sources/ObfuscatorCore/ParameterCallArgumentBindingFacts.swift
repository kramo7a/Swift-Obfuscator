import Foundation

public struct ParameterCallArgumentBinding: Hashable, Sendable {
    public let argumentIndex: Int
    public let parameterUSR: String
    public let parameterOrdinal: Int
    public let syntaxRole: ParameterCallArgumentSyntaxRole
}

public struct ParameterCallArgumentBindings: Hashable, Sendable {
    public let anchor: ParameterCallSiteAnchor
    public let arguments: [ParameterCallArgumentBinding]
}

public struct UnresolvedParameterCallArgumentBindingFact: Codable, Equatable, Sendable {
    public let callableUSR: String
    public let callableName: String
    public let path: String
    public let line: Int
    public let utf8Column: Int
    public let reason: String
}

public struct ParameterCallArgumentBindingFactsSummary: Codable, Equatable, Sendable {
    public let componentsWithNamedExternalLabels: Int
    public let namedExternalLabelParameters: Int
    public let indexedCallAnchors: Int
    public let syntaxResolvedCallAnchors: Int
    public let bindingResolvedCallAnchors: Int
    public let bindingUnresolvedCallAnchors: Int
    public let boundArguments: Int
    public let boundNamedLabelTokens: Int
    public let ambiguousCallAnchors: Int
    public let unmatchedCallAnchors: Int
    public let componentsWithAllIndexedCallsBound: Int
    public let namedParametersInComponentsWithAllIndexedCallsBound: Int
    public let componentsWithoutIndexedCalls: Int
    public let namedParametersInComponentsWithoutIndexedCalls: Int
    public let unresolvedByReason: [String: Int]
    public let unresolvedAnchors: [UnresolvedParameterCallArgumentBindingFact]

    public static let empty = ParameterCallArgumentBindingFactsSummary(
        components: [],
        bindingsByAnchor: [:],
        callSiteRolesByAnchor: [:],
        unresolvedReasonsByAnchor: [:]
    )

    init(
        components: [ParameterRenameComponent],
        bindingsByAnchor: [ParameterCallSiteAnchor: ParameterCallArgumentBindings],
        callSiteRolesByAnchor: [ParameterCallSiteAnchor: ParameterCallSiteSyntaxRoles],
        unresolvedReasonsByAnchor: [ParameterCallSiteAnchor: String]
    ) {
        let namedParameterCount: (ParameterRenameComponent) -> Int = { component in
            component.members.count { member in
                if case .named = member.externalLabel {
                    return true
                }
                return false
            }
        }
        let allAnchors = Set(components.flatMap { component in
            component.callLocations.map {
                ParameterCallSiteAnchor(callableUSR: component.callableUSR, location: $0)
            }
        })
        let bindings = Array(bindingsByAnchor.values)
        self.componentsWithNamedExternalLabels = components.count
        self.namedExternalLabelParameters = components.reduce(0) {
            $0 + namedParameterCount($1)
        }
        self.indexedCallAnchors = allAnchors.count
        self.syntaxResolvedCallAnchors = allAnchors.intersection(
            callSiteRolesByAnchor.keys
        ).count
        self.bindingResolvedCallAnchors = bindingsByAnchor.count
        self.bindingUnresolvedCallAnchors = unresolvedReasonsByAnchor.count
        self.boundArguments = bindings.reduce(0) { $0 + $1.arguments.count }
        self.boundNamedLabelTokens = bindings.reduce(0) { count, binding in
            count + binding.arguments.count { $0.syntaxRole.labelToken != nil }
        }
        self.ambiguousCallAnchors = unresolvedReasonsByAnchor.values.count {
            $0 == ParameterCallArgumentBindingFacts.ambiguousReason
        }
        self.unmatchedCallAnchors = unresolvedReasonsByAnchor.values.count {
            $0 == ParameterCallArgumentBindingFacts.unmatchedReason
        }

        let resolvedAnchors = Set(bindingsByAnchor.keys)
        let componentsWithCalls = components.filter { !$0.callLocations.isEmpty }
        let fullyBoundComponents = componentsWithCalls.filter { component in
            component.callLocations.allSatisfy { location in
                resolvedAnchors.contains(ParameterCallSiteAnchor(
                    callableUSR: component.callableUSR,
                    location: location
                ))
            }
        }
        self.componentsWithAllIndexedCallsBound = fullyBoundComponents.count
        self.namedParametersInComponentsWithAllIndexedCallsBound = fullyBoundComponents
            .reduce(0) { $0 + namedParameterCount($1) }

        let componentsWithoutCalls = components.filter(\.callLocations.isEmpty)
        self.componentsWithoutIndexedCalls = componentsWithoutCalls.count
        self.namedParametersInComponentsWithoutIndexedCalls = componentsWithoutCalls
            .reduce(0) { $0 + namedParameterCount($1) }
        self.unresolvedByReason = Dictionary(
            grouping: unresolvedReasonsByAnchor.values,
            by: { $0 }
        ).mapValues(\.count)
        let callableNamesByUSR = Dictionary(
            uniqueKeysWithValues: components.map { ($0.callableUSR, $0.callableName) }
        )
        self.unresolvedAnchors = unresolvedReasonsByAnchor.map { anchor, reason in
            UnresolvedParameterCallArgumentBindingFact(
                callableUSR: anchor.callableUSR,
                callableName: callableNamesByUSR[anchor.callableUSR] ?? "<unavailable>",
                path: anchor.location.path,
                line: anchor.location.line,
                utf8Column: anchor.location.utf8Column,
                reason: reason
            )
        }.sorted {
            ($0.path, $0.line, $0.utf8Column, $0.callableUSR)
                < ($1.path, $1.line, $1.utf8Column, $1.callableUSR)
        }
    }
}

public struct ParameterCallArgumentBindingFacts: Sendable {
    static let ambiguousReason = "call argument-to-parameter ordinal mapping is ambiguous"
    static let unmatchedReason = "call arguments do not match declaration parameter roles"

    public let bindingsByAnchor: [ParameterCallSiteAnchor: ParameterCallArgumentBindings]
    public let unresolvedReasonsByAnchor: [ParameterCallSiteAnchor: String]
    public let summary: ParameterCallArgumentBindingFactsSummary

    public init(
        components: [ParameterRenameComponent],
        parameterRolesByUSR: [String: ParameterDeclarationSyntaxRoles],
        callSiteSyntaxFacts: ParameterCallSiteSyntaxFacts
    ) {
        let targetComponents = components.filter { component in
            component.ownerCategory != .enumCase
                && component.members.contains { member in
                    if case .named = member.externalLabel {
                        return true
                    }
                    return false
                }
        }
        var bindingsByAnchor: [ParameterCallSiteAnchor: ParameterCallArgumentBindings] = [:]
        var unresolvedReasonsByAnchor: [ParameterCallSiteAnchor: String] = [:]

        for component in targetComponents.sorted(by: { $0.callableUSR < $1.callableUSR }) {
            let parametersResult = Self.matchParameters(
                component: component,
                parameterRolesByUSR: parameterRolesByUSR
            )
            for location in component.callLocations {
                let anchor = ParameterCallSiteAnchor(
                    callableUSR: component.callableUSR,
                    location: location
                )
                guard case .success(let parameters) = parametersResult else {
                    if case .failure(let reason) = parametersResult {
                        unresolvedReasonsByAnchor[anchor] = reason
                    }
                    continue
                }
                guard let callRoles = callSiteSyntaxFacts.rolesByAnchor[anchor] else {
                    let syntaxReason = callSiteSyntaxFacts.unresolvedReasonsByAnchor[anchor]
                        ?? "compiler call syntax roles unavailable"
                    unresolvedReasonsByAnchor[anchor] = "call syntax unresolved: \(syntaxReason)"
                    continue
                }

                switch Self.assignment(
                    arguments: callRoles.arguments,
                    parameters: parameters
                ) {
                case .unique(let ordinals):
                    let bindings = zip(callRoles.arguments.indices, ordinals).map {
                        argumentIndex, ordinal in
                        ParameterCallArgumentBinding(
                            argumentIndex: argumentIndex,
                            parameterUSR: parameters[ordinal].parameterUSR,
                            parameterOrdinal: ordinal,
                            syntaxRole: callRoles.arguments[argumentIndex]
                        )
                    }
                    bindingsByAnchor[anchor] = ParameterCallArgumentBindings(
                        anchor: anchor,
                        arguments: bindings
                    )
                case .ambiguous:
                    unresolvedReasonsByAnchor[anchor] = Self.ambiguousReason
                case .unmatched:
                    unresolvedReasonsByAnchor[anchor] = Self.unmatchedReason
                }
            }
        }

        self.bindingsByAnchor = bindingsByAnchor
        self.unresolvedReasonsByAnchor = unresolvedReasonsByAnchor
        self.summary = ParameterCallArgumentBindingFactsSummary(
            components: targetComponents,
            bindingsByAnchor: bindingsByAnchor,
            callSiteRolesByAnchor: callSiteSyntaxFacts.rolesByAnchor,
            unresolvedReasonsByAnchor: unresolvedReasonsByAnchor
        )
    }

    private static func matchParameters(
        component: ParameterRenameComponent,
        parameterRolesByUSR: [String: ParameterDeclarationSyntaxRoles]
    ) -> MatchParametersOutcome {
        guard component.isStructurallyComplete else {
            return .failure(
                "parameter component is structurally incomplete: "
                    + component.structuralReasons.joined(separator: "; ")
            )
        }
        let members = component.members.sorted { $0.ordinal < $1.ordinal }
        guard members.map(\.ordinal) == Array(members.indices) else {
            return .failure("parameter ordinals are not contiguous")
        }
        var parameters: [MatchParameter] = []
        for member in members {
            guard let syntaxRole = parameterRolesByUSR[member.parameterUSR] else {
                return .failure(
                    "parameter declaration syntax roles unavailable for \(member.parameterUSR)"
                )
            }
            guard labelsAgree(indexed: member.externalLabel, syntax: syntaxRole.externalLabel) else {
                return .failure(
                    "indexed and compiler-syntax external labels disagree for "
                        + member.parameterUSR
                )
            }
            parameters.append(MatchParameter(
                parameterUSR: member.parameterUSR,
                externalLabel: member.externalLabel,
                hasDefaultValue: syntaxRole.hasDefaultValue,
                isVariadic: syntaxRole.isVariadic,
                trailingClosureCompatibility: syntaxRole.trailingClosureCompatibility
            ))
        }
        return .success(parameters)
    }

    private static func labelsAgree(
        indexed: ParameterExternalLabel,
        syntax: ParameterExternalLabelSyntaxRole
    ) -> Bool {
        switch (indexed, syntax) {
        case (.named(let indexedName), .named(let token)):
            return indexedName == token.name
        case (.omitted, .omitted), (.omitted, .none):
            return true
        default:
            return false
        }
    }

    private static func assignment(
        arguments: [ParameterCallArgumentSyntaxRole],
        parameters: [MatchParameter]
    ) -> AssignmentOutcome {
        var solutions: [[Int]] = []
        var current: [Int] = []

        func parametersCanBeOmitted(_ range: Range<Int>) -> Bool {
            range.allSatisfy {
                parameters[$0].hasDefaultValue || parameters[$0].isVariadic
            }
        }

        func search(argumentIndex: Int, previousOrdinal: Int?) {
            guard solutions.count < 2 else {
                return
            }
            guard argumentIndex < arguments.count else {
                let remainingStart = previousOrdinal.map { $0 + 1 } ?? 0
                guard parametersCanBeOmitted(remainingStart..<parameters.count) else {
                    return
                }
                solutions.append(current)
                return
            }

            let minimumOrdinal: Int
            if let previousOrdinal, parameters[previousOrdinal].isVariadic {
                minimumOrdinal = previousOrdinal
            } else {
                minimumOrdinal = previousOrdinal.map { $0 + 1 } ?? 0
            }
            guard minimumOrdinal < parameters.count else {
                return
            }

            for ordinal in minimumOrdinal..<parameters.count {
                let repeatsVariadic = previousOrdinal == ordinal
                if !repeatsVariadic {
                    let skippedStart = previousOrdinal.map { $0 + 1 } ?? 0
                    guard parametersCanBeOmitted(skippedStart..<ordinal) else {
                        break
                    }
                }
                guard argument(
                    arguments[argumentIndex],
                    matches: parameters[ordinal],
                    repeatsVariadic: repeatsVariadic
                ) else {
                    continue
                }
                current.append(ordinal)
                search(argumentIndex: argumentIndex + 1, previousOrdinal: ordinal)
                current.removeLast()
                if solutions.count >= 2 {
                    return
                }
            }
        }

        search(argumentIndex: 0, previousOrdinal: nil)
        switch solutions.count {
        case 0:
            return .unmatched
        case 1:
            return .unique(solutions[0])
        default:
            return .ambiguous
        }
    }

    private static func argument(
        _ argument: ParameterCallArgumentSyntaxRole,
        matches parameter: MatchParameter,
        repeatsVariadic: Bool
    ) -> Bool {
        if repeatsVariadic {
            guard parameter.isVariadic else {
                return false
            }
            switch argument {
            case .parenthesized(label: nil):
                return true
            case .firstTrailingClosure:
                return parameter.trailingClosureCompatibility != .definitelyNonCallable
            case .parenthesized(label: .some), .additionalTrailingClosure:
                return false
            }
        }

        switch argument {
        case .parenthesized(label: let label):
            switch parameter.externalLabel {
            case .omitted:
                return label == nil
            case .named(let name):
                return label?.name == name
            case .unavailable:
                return false
            }
        case .firstTrailingClosure:
            return parameter.trailingClosureCompatibility != .definitelyNonCallable
        case .additionalTrailingClosure(label: let label):
            if parameter.trailingClosureCompatibility != .definitelyNonCallable,
               case .named(let name) = parameter.externalLabel {
                return label.name == name
            }
            return false
        }
    }
}

private struct MatchParameter {
    let parameterUSR: String
    let externalLabel: ParameterExternalLabel
    let hasDefaultValue: Bool
    let isVariadic: Bool
    let trailingClosureCompatibility: ParameterTrailingClosureCompatibility
}

private enum AssignmentOutcome {
    case unique([Int])
    case ambiguous
    case unmatched
}

private enum MatchParametersOutcome {
    case success([MatchParameter])
    case failure(String)
}

private extension ParameterCallArgumentSyntaxRole {
    var labelToken: SourceTokenRange? {
        switch self {
        case .parenthesized(label: let label):
            return label
        case .firstTrailingClosure:
            return nil
        case .additionalTrailingClosure(label: let label):
            return label
        }
    }
}
