import Foundation

public struct ParameterCallableReferenceLabelBinding: Hashable, Sendable {
    public let parameterUSR: String
    public let parameterOrdinal: Int
    public let token: SourceTokenRange
}

public struct ParameterCallableReferenceBindings: Hashable, Sendable {
    public let anchor: ParameterCallableReferenceAnchor
    public let kind: ParameterCallableReferenceSyntaxKind
    public let fullNameArguments: [ParameterCallableReferenceLabelBinding]
    public let subscriptArguments: [ParameterCallArgumentBinding]
}

public struct UnresolvedParameterCallableReferenceBindingFact: Codable, Equatable, Sendable {
    public let callableUSR: String
    public let callableName: String
    public let path: String
    public let line: Int
    public let utf8Column: Int
    public let reason: String
}

public struct ParameterCallableReferenceBindingFactsSummary: Codable, Equatable, Sendable {
    public let componentsWithNamedExternalLabels: Int
    public let namedExternalLabelParameters: Int
    public let componentsWithIndexedReferences: Int
    public let namedParametersInComponentsWithIndexedReferences: Int
    public let indexedReferenceAnchors: Int
    public let syntaxResolvedReferenceAnchors: Int
    public let bindingResolvedReferenceAnchors: Int
    public let bindingUnresolvedReferenceAnchors: Int
    public let boundBareReferences: Int
    public let boundFullNameReferences: Int
    public let boundFullNameArgumentTokens: Int
    public let boundNamedFullNameLabelTokens: Int
    public let boundSubscriptCalls: Int
    public let boundSubscriptArguments: Int
    public let boundNamedSubscriptLabelTokens: Int
    public let componentsWithAllIndexedReferencesBound: Int
    public let namedParametersInComponentsWithAllIndexedReferencesBound: Int
    public let fullNameSignatureMismatches: Int
    public let ambiguousSubscriptCalls: Int
    public let unmatchedSubscriptCalls: Int
    public let unresolvedByReason: [String: Int]
    public let unresolvedAnchors: [UnresolvedParameterCallableReferenceBindingFact]

    public static let empty = ParameterCallableReferenceBindingFactsSummary(
        components: [],
        bindingsByAnchor: [:],
        syntaxRolesByAnchor: [:],
        unresolvedReasonsByAnchor: [:]
    )

    init(
        components: [ParameterRenameComponent],
        bindingsByAnchor: [ParameterCallableReferenceAnchor: ParameterCallableReferenceBindings],
        syntaxRolesByAnchor: [
            ParameterCallableReferenceAnchor: ParameterCallableReferenceSyntaxRoles
        ],
        unresolvedReasonsByAnchor: [ParameterCallableReferenceAnchor: String]
    ) {
        let namedParameterCount: (ParameterRenameComponent) -> Int = { component in
            component.members.count { member in
                if case .named = member.externalLabel {
                    return true
                }
                return false
            }
        }
        let componentsWithReferences = components.filter {
            !$0.nonCallReferenceLocations.isEmpty
        }
        let allAnchors = Set(componentsWithReferences.flatMap { component in
            component.nonCallReferenceLocations.map {
                ParameterCallableReferenceAnchor(
                    callableUSR: component.callableUSR,
                    location: $0
                )
            }
        })
        let bindings = Array(bindingsByAnchor.values)

        self.componentsWithNamedExternalLabels = components.count
        self.namedExternalLabelParameters = components.reduce(0) {
            $0 + namedParameterCount($1)
        }
        self.componentsWithIndexedReferences = componentsWithReferences.count
        self.namedParametersInComponentsWithIndexedReferences = componentsWithReferences
            .reduce(0) { $0 + namedParameterCount($1) }
        self.indexedReferenceAnchors = allAnchors.count
        self.syntaxResolvedReferenceAnchors = allAnchors.intersection(
            syntaxRolesByAnchor.keys
        ).count
        self.bindingResolvedReferenceAnchors = bindingsByAnchor.count
        self.bindingUnresolvedReferenceAnchors = unresolvedReasonsByAnchor.count
        self.boundBareReferences = bindings.count { $0.kind == .bareReference }
        self.boundFullNameReferences = bindings.count { $0.kind == .fullNameReference }
        self.boundFullNameArgumentTokens = bindings.reduce(0) {
            $0 + $1.fullNameArguments.count
        }
        self.boundNamedFullNameLabelTokens = bindings.reduce(0) { count, binding in
            count + binding.fullNameArguments.count { $0.token.name != "_" }
        }
        self.boundSubscriptCalls = bindings.count { $0.kind == .subscriptCall }
        self.boundSubscriptArguments = bindings.reduce(0) {
            $0 + $1.subscriptArguments.count
        }
        self.boundNamedSubscriptLabelTokens = bindings.reduce(0) { count, binding in
            count + binding.subscriptArguments.count { $0.syntaxRole.labelToken != nil }
        }

        let resolvedAnchors = Set(bindingsByAnchor.keys)
        let fullyBoundComponents = componentsWithReferences.filter { component in
            component.nonCallReferenceLocations.allSatisfy { location in
                resolvedAnchors.contains(ParameterCallableReferenceAnchor(
                    callableUSR: component.callableUSR,
                    location: location
                ))
            }
        }
        self.componentsWithAllIndexedReferencesBound = fullyBoundComponents.count
        self.namedParametersInComponentsWithAllIndexedReferencesBound =
            fullyBoundComponents.reduce(0) { $0 + namedParameterCount($1) }
        self.fullNameSignatureMismatches = unresolvedReasonsByAnchor.values.count {
            $0 == ParameterCallableReferenceBindingFacts.fullNameMismatchReason
        }
        self.ambiguousSubscriptCalls = unresolvedReasonsByAnchor.values.count {
            $0 == ParameterCallableReferenceBindingFacts.ambiguousSubscriptReason
        }
        self.unmatchedSubscriptCalls = unresolvedReasonsByAnchor.values.count {
            $0 == ParameterCallableReferenceBindingFacts.unmatchedSubscriptReason
        }
        self.unresolvedByReason = Dictionary(
            grouping: unresolvedReasonsByAnchor.values,
            by: { $0 }
        ).mapValues(\.count)
        let callableNamesByUSR = Dictionary(
            uniqueKeysWithValues: components.map { ($0.callableUSR, $0.callableName) }
        )
        self.unresolvedAnchors = unresolvedReasonsByAnchor.map { anchor, reason in
            UnresolvedParameterCallableReferenceBindingFact(
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

public struct ParameterCallableReferenceBindingFacts: Sendable {
    static let fullNameMismatchReason =
        "full-name argument tokens do not match declaration parameter roles"
    static let ambiguousSubscriptReason =
        "subscript argument-to-parameter ordinal mapping is ambiguous"
    static let unmatchedSubscriptReason =
        "subscript arguments do not match declaration parameter roles"

    public let bindingsByAnchor: [
        ParameterCallableReferenceAnchor: ParameterCallableReferenceBindings
    ]
    public let unresolvedReasonsByAnchor: [ParameterCallableReferenceAnchor: String]
    public let summary: ParameterCallableReferenceBindingFactsSummary

    public init(
        components: [ParameterRenameComponent],
        parameterRolesByUSR: [String: ParameterDeclarationSyntaxRoles],
        syntaxFacts: ParameterCallableReferenceSyntaxFacts
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
        var bindingsByAnchor: [
            ParameterCallableReferenceAnchor: ParameterCallableReferenceBindings
        ] = [:]
        var unresolvedReasonsByAnchor: [ParameterCallableReferenceAnchor: String] = [:]

        for component in targetComponents.sorted(by: { $0.callableUSR < $1.callableUSR }) {
            let parametersResult = ParameterArgumentOrdinalMatcher.parameters(
                component: component,
                parameterRolesByUSR: parameterRolesByUSR
            )
            for location in component.nonCallReferenceLocations {
                let anchor = ParameterCallableReferenceAnchor(
                    callableUSR: component.callableUSR,
                    location: location
                )
                guard case .success(let parameters) = parametersResult else {
                    if case .failure(let reason) = parametersResult {
                        unresolvedReasonsByAnchor[anchor] = reason
                    }
                    continue
                }
                guard let syntaxRoles = syntaxFacts.rolesByAnchor[anchor] else {
                    let syntaxReason = syntaxFacts.unresolvedReasonsByAnchor[anchor]
                        ?? "compiler callable reference syntax roles unavailable"
                    unresolvedReasonsByAnchor[anchor] =
                        "callable reference syntax unresolved: \(syntaxReason)"
                    continue
                }

                switch syntaxRoles.kind {
                case .bareReference:
                    bindingsByAnchor[anchor] = ParameterCallableReferenceBindings(
                        anchor: anchor,
                        kind: .bareReference,
                        fullNameArguments: [],
                        subscriptArguments: []
                    )
                case .fullNameReference:
                    guard let ordinals = ParameterArgumentOrdinalMatcher.fullNameOrdinals(
                        argumentTokens: syntaxRoles.fullNameArgumentTokens,
                        parameters: parameters
                    ) else {
                        unresolvedReasonsByAnchor[anchor] = Self.fullNameMismatchReason
                        continue
                    }
                    let bindings = zip(syntaxRoles.fullNameArgumentTokens, ordinals).map {
                        token, ordinal in
                        ParameterCallableReferenceLabelBinding(
                            parameterUSR: parameters[ordinal].parameterUSR,
                            parameterOrdinal: ordinal,
                            token: token
                        )
                    }
                    bindingsByAnchor[anchor] = ParameterCallableReferenceBindings(
                        anchor: anchor,
                        kind: .fullNameReference,
                        fullNameArguments: bindings,
                        subscriptArguments: []
                    )
                case .subscriptCall:
                    switch ParameterArgumentOrdinalMatcher.assignment(
                        arguments: syntaxRoles.subscriptArguments,
                        parameters: parameters
                    ) {
                    case .unique(let ordinals):
                        let bindings = zip(
                            syntaxRoles.subscriptArguments.indices,
                            ordinals
                        ).map { argumentIndex, ordinal in
                            ParameterCallArgumentBinding(
                                argumentIndex: argumentIndex,
                                parameterUSR: parameters[ordinal].parameterUSR,
                                parameterOrdinal: ordinal,
                                syntaxRole: syntaxRoles.subscriptArguments[argumentIndex]
                            )
                        }
                        bindingsByAnchor[anchor] = ParameterCallableReferenceBindings(
                            anchor: anchor,
                            kind: .subscriptCall,
                            fullNameArguments: [],
                            subscriptArguments: bindings
                        )
                    case .ambiguous:
                        unresolvedReasonsByAnchor[anchor] = Self.ambiguousSubscriptReason
                    case .unmatched:
                        unresolvedReasonsByAnchor[anchor] = Self.unmatchedSubscriptReason
                    }
                }
            }
        }

        self.bindingsByAnchor = bindingsByAnchor
        self.unresolvedReasonsByAnchor = unresolvedReasonsByAnchor
        self.summary = ParameterCallableReferenceBindingFactsSummary(
            components: targetComponents,
            bindingsByAnchor: bindingsByAnchor,
            syntaxRolesByAnchor: syntaxFacts.rolesByAnchor,
            unresolvedReasonsByAnchor: unresolvedReasonsByAnchor
        )
    }
}
