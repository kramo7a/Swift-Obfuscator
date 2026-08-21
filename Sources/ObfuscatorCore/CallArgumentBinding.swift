import Foundation

public enum CallArgumentBinding {
    public struct Argument: Hashable, Sendable {
        public let argumentIndex: Int
        public let parameterUSR: String
        public let parameterOrdinal: Int
        public let syntaxRole: CallSiteSyntax.Argument
    }

    public struct Call: Hashable, Sendable {
        public let anchor: CallSiteSyntax.Anchor
        public let arguments: [CallArgumentBinding.Argument]
    }

    public struct Issue: Codable, Equatable, Sendable {
        public let callableUSR: String
        public let callableName: String
        public let path: String
        public let line: Int
        public let utf8Column: Int
        public let reason: String
    }

    public struct Report: Codable, Equatable, Sendable {
        public let signatureCountWithNamedExternalLabels: Int
        public let labeledParameterCount: Int
        public let indexedCallAnchors: Int
        public let syntaxResolvedCallAnchors: Int
        public let bindingResolvedCallAnchors: Int
        public let bindingUnresolvedCallAnchors: Int
        public let boundArguments: Int
        public let boundNamedLabelTokens: Int
        public let ambiguousCallAnchors: Int
        public let unmatchedCallAnchors: Int
        public let signatureCountWithAllIndexedCallsBound: Int
        public let namedParameterCountInSignaturesWithAllIndexedCallsBound: Int
        public let signatureCountWithoutIndexedCalls: Int
        public let namedParameterCountInSignaturesWithoutIndexedCalls: Int
        public let unresolvedByReason: [String: Int]
        public let unresolvedAnchors: [CallArgumentBinding.Issue]

        public static let empty = CallArgumentBinding.Report(
            signatures: [],
            callsByAnchor: [:],
            callSiteRolesByAnchor: [:],
            issueReasonsByAnchor: [:]
        )

        init(
            signatures: [CallableSignature],
            callsByAnchor: [CallSiteSyntax.Anchor: CallArgumentBinding.Call],
            callSiteRolesByAnchor: [CallSiteSyntax.Anchor: CallSiteSyntax.Call],
            issueReasonsByAnchor: [CallSiteSyntax.Anchor: String]
        ) {
            let namedParameterCount: (CallableSignature) -> Int = { signature in
                signature.parameters.count { member in
                    if case .named = member.externalLabel {
                        return true
                    }
                    return false
                }
            }
            let allAnchors = Set(
                signatures.flatMap { signature in
                    signature.externalLabelArgumentLocations.map {
                        CallSiteSyntax.Anchor(callableUSR: signature.callableUSR, location: $0)
                    }
                })
            let bindings = Array(callsByAnchor.values)
            self.signatureCountWithNamedExternalLabels = signatures.count
            self.labeledParameterCount = signatures.reduce(0) {
                $0 + namedParameterCount($1)
            }
            self.indexedCallAnchors = allAnchors.count
            self.syntaxResolvedCallAnchors =
                allAnchors.intersection(
                    callSiteRolesByAnchor.keys
                ).count
            self.bindingResolvedCallAnchors = callsByAnchor.count
            self.bindingUnresolvedCallAnchors = issueReasonsByAnchor.count
            self.boundArguments = bindings.reduce(0) { $0 + $1.arguments.count }
            self.boundNamedLabelTokens = bindings.reduce(0) { count, binding in
                count + binding.arguments.count { $0.syntaxRole.labelToken != nil }
            }
            self.ambiguousCallAnchors = issueReasonsByAnchor.values.count {
                $0 == CallArgumentBinding.Index.ambiguousReason
            }
            self.unmatchedCallAnchors = issueReasonsByAnchor.values.count {
                $0 == CallArgumentBinding.Index.unmatchedReason
            }

            let resolvedAnchors = Set(callsByAnchor.keys)
            let signaturesWithCalls = signatures.filter {
                !$0.externalLabelArgumentLocations.isEmpty
            }
            let fullyBoundSignatures = signaturesWithCalls.filter { signature in
                signature.externalLabelArgumentLocations.allSatisfy { location in
                    resolvedAnchors.contains(
                        CallSiteSyntax.Anchor(
                            callableUSR: signature.callableUSR,
                            location: location
                        ))
                }
            }
            self.signatureCountWithAllIndexedCallsBound = fullyBoundSignatures.count
            self.namedParameterCountInSignaturesWithAllIndexedCallsBound =
                fullyBoundSignatures
                .reduce(0) { $0 + namedParameterCount($1) }

            let signaturesWithoutCalls = signatures.filter {
                $0.externalLabelArgumentLocations.isEmpty
            }
            self.signatureCountWithoutIndexedCalls = signaturesWithoutCalls.count
            self.namedParameterCountInSignaturesWithoutIndexedCalls =
                signaturesWithoutCalls
                .reduce(0) { $0 + namedParameterCount($1) }
            self.unresolvedByReason = Dictionary(
                grouping: issueReasonsByAnchor.values,
                by: { $0 }
            ).mapValues(\.count)
            let callableNamesByUSR = Dictionary(
                uniqueKeysWithValues: signatures.map { ($0.callableUSR, $0.callableName) }
            )
            self.unresolvedAnchors = issueReasonsByAnchor.map { anchor, reason in
                CallArgumentBinding.Issue(
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

        private enum CodingKeys: String, CodingKey {
            case signatureCountWithNamedExternalLabels = "componentsWithNamedExternalLabels"
            case labeledParameterCount = "namedExternalLabelParameters"
            case indexedCallAnchors
            case syntaxResolvedCallAnchors
            case bindingResolvedCallAnchors
            case bindingUnresolvedCallAnchors
            case boundArguments
            case boundNamedLabelTokens
            case ambiguousCallAnchors
            case unmatchedCallAnchors
            case signatureCountWithAllIndexedCallsBound = "componentsWithAllIndexedCallsBound"
            case namedParameterCountInSignaturesWithAllIndexedCallsBound =
                "namedParametersInComponentsWithAllIndexedCallsBound"
            case signatureCountWithoutIndexedCalls = "componentsWithoutIndexedCalls"
            case namedParameterCountInSignaturesWithoutIndexedCalls =
                "namedParametersInComponentsWithoutIndexedCalls"
            case unresolvedByReason
            case unresolvedAnchors
        }
    }

    public struct Index: Sendable {
        static let ambiguousReason = "call argument-to-parameter ordinal mapping is ambiguous"
        static let unmatchedReason = "call arguments do not match declaration parameter roles"

        public let callsByAnchor: [CallSiteSyntax.Anchor: CallArgumentBinding.Call]
        public let issueReasonsByAnchor: [CallSiteSyntax.Anchor: String]
        public let report: CallArgumentBinding.Report

        public init(
            signatures: [CallableSignature],
            parametersByUSR: [String: ParameterSyntax.Parameter],
            callSiteSyntax: CallSiteSyntax.Index
        ) {
            let targetSignatures = signatures.filter { signature in
                signature.parameters.contains { member in
                    if case .named = member.externalLabel {
                        return true
                    }
                    return false
                }
            }
            var callsByAnchor: [CallSiteSyntax.Anchor: CallArgumentBinding.Call] = [:]
            var issueReasonsByAnchor: [CallSiteSyntax.Anchor: String] = [:]

            for signature in targetSignatures.sorted(by: { $0.callableUSR < $1.callableUSR }) {
                let parametersResult = ParameterArgumentOrdinalMatcher.parameters(
                    signature: signature,
                    parametersByUSR: parametersByUSR
                )
                for location in signature.externalLabelArgumentLocations {
                    let anchor = CallSiteSyntax.Anchor(
                        callableUSR: signature.callableUSR,
                        location: location
                    )
                    guard case .success(let parameters) = parametersResult else {
                        if case .failure(let reason) = parametersResult {
                            issueReasonsByAnchor[anchor] = reason
                        }
                        continue
                    }
                    guard let callRoles = callSiteSyntax.callsByAnchor[anchor] else {
                        let syntaxReason =
                            callSiteSyntax.issueReasonsByAnchor[anchor]
                            ?? "compiler call syntax roles unavailable"
                        issueReasonsByAnchor[anchor] = "call syntax unresolved: \(syntaxReason)"
                        continue
                    }

                    if callRoles.kind == .enumCasePattern {
                        guard callRoles.arguments.isEmpty else {
                            issueReasonsByAnchor[anchor] = Self.unmatchedReason
                            continue
                        }
                        callsByAnchor[anchor] = CallArgumentBinding.Call(
                            anchor: anchor,
                            arguments: []
                        )
                        continue
                    }

                    switch ParameterArgumentOrdinalMatcher.assignment(
                        arguments: callRoles.arguments,
                        parameters: parameters,
                        canOmitNamedLabels: callRoles.canOmitNamedLabels
                    ) {
                    case .unique(let ordinals):
                        let bindings = zip(callRoles.arguments.indices, ordinals).map {
                            argumentIndex, ordinal in
                            CallArgumentBinding.Argument(
                                argumentIndex: argumentIndex,
                                parameterUSR: parameters[ordinal].parameterUSR,
                                parameterOrdinal: ordinal,
                                syntaxRole: callRoles.arguments[argumentIndex]
                            )
                        }
                        callsByAnchor[anchor] = CallArgumentBinding.Call(
                            anchor: anchor,
                            arguments: bindings
                        )
                    case .ambiguous:
                        issueReasonsByAnchor[anchor] = Self.ambiguousReason
                    case .unmatched:
                        issueReasonsByAnchor[anchor] = Self.unmatchedReason
                    }
                }
            }

            self.callsByAnchor = callsByAnchor
            self.issueReasonsByAnchor = issueReasonsByAnchor
            self.report = CallArgumentBinding.Report(
                signatures: targetSignatures,
                callsByAnchor: callsByAnchor,
                callSiteRolesByAnchor: callSiteSyntax.callsByAnchor,
                issueReasonsByAnchor: issueReasonsByAnchor
            )
        }
    }

}
