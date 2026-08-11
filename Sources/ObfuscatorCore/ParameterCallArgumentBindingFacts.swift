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
            component.externalLabelArgumentLocations.map {
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
        let componentsWithCalls = components.filter {
            !$0.externalLabelArgumentLocations.isEmpty
        }
        let fullyBoundComponents = componentsWithCalls.filter { component in
            component.externalLabelArgumentLocations.allSatisfy { location in
                resolvedAnchors.contains(ParameterCallSiteAnchor(
                    callableUSR: component.callableUSR,
                    location: location
                ))
            }
        }
        self.componentsWithAllIndexedCallsBound = fullyBoundComponents.count
        self.namedParametersInComponentsWithAllIndexedCallsBound = fullyBoundComponents
            .reduce(0) { $0 + namedParameterCount($1) }

        let componentsWithoutCalls = components.filter {
            $0.externalLabelArgumentLocations.isEmpty
        }
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
            component.members.contains { member in
                if case .named = member.externalLabel {
                    return true
                }
                return false
            }
        }
        var bindingsByAnchor: [ParameterCallSiteAnchor: ParameterCallArgumentBindings] = [:]
        var unresolvedReasonsByAnchor: [ParameterCallSiteAnchor: String] = [:]

        for component in targetComponents.sorted(by: { $0.callableUSR < $1.callableUSR }) {
            let parametersResult = ParameterArgumentOrdinalMatcher.parameters(
                component: component,
                parameterRolesByUSR: parameterRolesByUSR
            )
            for location in component.externalLabelArgumentLocations {
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

                if callRoles.kind == .enumCasePattern {
                    guard callRoles.arguments.isEmpty else {
                        unresolvedReasonsByAnchor[anchor] = Self.unmatchedReason
                        continue
                    }
                    bindingsByAnchor[anchor] = ParameterCallArgumentBindings(
                        anchor: anchor,
                        arguments: []
                    )
                    continue
                }

                switch ParameterArgumentOrdinalMatcher.assignment(
                    arguments: callRoles.arguments,
                    parameters: parameters,
                    allowsOmittedNamedLabels: callRoles.allowsOmittedNamedLabels
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
}
