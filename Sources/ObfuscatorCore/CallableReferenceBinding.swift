import Foundation

public enum CallableReferenceBinding {
    public struct Label: Hashable, Sendable {
        public let parameterUSR: String
        public let parameterOrdinal: Int
        public let token: SourceToken
    }

    public struct Reference: Hashable, Sendable {
        public let anchor: CallableReferenceSyntax.Anchor
        public let kind: CallableReferenceSyntax.Kind
        public let fullNameArguments: [CallableReferenceBinding.Label]
        public let subscriptArguments: [CallArgumentBinding.Argument]
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
        public let signatureCountWithIndexedReferences: Int
        public let namedParameterCountInSignaturesWithIndexedReferences: Int
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
        public let signatureCountWithAllIndexedReferencesBound: Int
        public let namedParameterCountInSignaturesWithAllIndexedReferencesBound: Int
        public let fullNameSignatureMismatches: Int
        public let ambiguousSubscriptCalls: Int
        public let unmatchedSubscriptCalls: Int
        public let unresolvedByReason: [String: Int]
        public let unresolvedAnchors: [CallableReferenceBinding.Issue]

        public static let empty = CallableReferenceBinding.Report(
            signatures: [],
            referencesByAnchor: [:],
            syntaxRolesByAnchor: [:],
            issueReasonsByAnchor: [:]
        )

        init(
            signatures: [CallableSignature],
            referencesByAnchor: [CallableReferenceSyntax.Anchor: CallableReferenceBinding
                .Reference],
            syntaxRolesByAnchor: [CallableReferenceSyntax.Anchor: CallableReferenceSyntax
                .Reference],
            issueReasonsByAnchor: [CallableReferenceSyntax.Anchor: String]
        ) {
            let namedParameterCount: (CallableSignature) -> Int = { signature in
                signature.parameters.count { member in
                    if case .named = member.externalLabel {
                        return true
                    }
                    return false
                }
            }
            let signaturesWithReferences = signatures.filter {
                !$0.nonCallReferenceLocations.isEmpty
            }
            let allAnchors = Set(
                signaturesWithReferences.flatMap { signature in
                    signature.nonCallReferenceLocations.map {
                        CallableReferenceSyntax.Anchor(
                            callableUSR: signature.callableUSR,
                            location: $0
                        )
                    }
                })
            let bindings = Array(referencesByAnchor.values)

            self.signatureCountWithNamedExternalLabels = signatures.count
            self.labeledParameterCount = signatures.reduce(0) {
                $0 + namedParameterCount($1)
            }
            self.signatureCountWithIndexedReferences = signaturesWithReferences.count
            self.namedParameterCountInSignaturesWithIndexedReferences =
                signaturesWithReferences
                .reduce(0) { $0 + namedParameterCount($1) }
            self.indexedReferenceAnchors = allAnchors.count
            self.syntaxResolvedReferenceAnchors =
                allAnchors.intersection(
                    syntaxRolesByAnchor.keys
                ).count
            self.bindingResolvedReferenceAnchors = referencesByAnchor.count
            self.bindingUnresolvedReferenceAnchors = issueReasonsByAnchor.count
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

            let resolvedAnchors = Set(referencesByAnchor.keys)
            let fullyBoundSignatures = signaturesWithReferences.filter { signature in
                signature.nonCallReferenceLocations.allSatisfy { location in
                    resolvedAnchors.contains(
                        CallableReferenceSyntax.Anchor(
                            callableUSR: signature.callableUSR,
                            location: location
                        ))
                }
            }
            self.signatureCountWithAllIndexedReferencesBound = fullyBoundSignatures.count
            self.namedParameterCountInSignaturesWithAllIndexedReferencesBound =
                fullyBoundSignatures.reduce(0) { $0 + namedParameterCount($1) }
            self.fullNameSignatureMismatches = issueReasonsByAnchor.values.count {
                $0 == CallableReferenceBinding.Index.fullNameMismatchReason
            }
            self.ambiguousSubscriptCalls = issueReasonsByAnchor.values.count {
                $0 == CallableReferenceBinding.Index.ambiguousSubscriptReason
            }
            self.unmatchedSubscriptCalls = issueReasonsByAnchor.values.count {
                $0 == CallableReferenceBinding.Index.unmatchedSubscriptReason
            }
            self.unresolvedByReason = Dictionary(
                grouping: issueReasonsByAnchor.values,
                by: { $0 }
            ).mapValues(\.count)
            let callableNamesByUSR = Dictionary(
                uniqueKeysWithValues: signatures.map { ($0.callableUSR, $0.callableName) }
            )
            self.unresolvedAnchors = issueReasonsByAnchor.map { anchor, reason in
                CallableReferenceBinding.Issue(
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
            case signatureCountWithIndexedReferences = "componentsWithIndexedReferences"
            case namedParameterCountInSignaturesWithIndexedReferences =
                "namedParametersInComponentsWithIndexedReferences"
            case indexedReferenceAnchors
            case syntaxResolvedReferenceAnchors
            case bindingResolvedReferenceAnchors
            case bindingUnresolvedReferenceAnchors
            case boundBareReferences
            case boundFullNameReferences
            case boundFullNameArgumentTokens
            case boundNamedFullNameLabelTokens
            case boundSubscriptCalls
            case boundSubscriptArguments
            case boundNamedSubscriptLabelTokens
            case signatureCountWithAllIndexedReferencesBound =
                "componentsWithAllIndexedReferencesBound"
            case namedParameterCountInSignaturesWithAllIndexedReferencesBound =
                "namedParametersInComponentsWithAllIndexedReferencesBound"
            case fullNameSignatureMismatches
            case ambiguousSubscriptCalls
            case unmatchedSubscriptCalls
            case unresolvedByReason
            case unresolvedAnchors
        }
    }

    public struct Index: Sendable {
        static let fullNameMismatchReason =
            "full-name argument tokens do not match declaration parameter roles"
        static let ambiguousSubscriptReason =
            "subscript argument-to-parameter ordinal mapping is ambiguous"
        static let unmatchedSubscriptReason =
            "subscript arguments do not match declaration parameter roles"

        public let referencesByAnchor:
            [CallableReferenceSyntax.Anchor: CallableReferenceBinding.Reference]
        public let issueReasonsByAnchor: [CallableReferenceSyntax.Anchor: String]
        public let report: CallableReferenceBinding.Report

        public init(
            signatures: [CallableSignature],
            parametersByUSR: [String: ParameterSyntax.Parameter],
            syntax: CallableReferenceSyntax.Index
        ) {
            let targetSignatures = signatures.filter { signature in
                signature.ownerCategory != .enumCase
                    && signature.parameters.contains { member in
                        if case .named = member.externalLabel {
                            return true
                        }
                        return false
                    }
            }
            var referencesByAnchor:
                [CallableReferenceSyntax.Anchor: CallableReferenceBinding.Reference] = [:]
            var issueReasonsByAnchor: [CallableReferenceSyntax.Anchor: String] = [:]

            for signature in targetSignatures.sorted(by: { $0.callableUSR < $1.callableUSR }) {
                let parametersResult = ParameterArgumentOrdinalMatcher.parameters(
                    signature: signature,
                    parametersByUSR: parametersByUSR
                )
                for location in signature.nonCallReferenceLocations {
                    let anchor = CallableReferenceSyntax.Anchor(
                        callableUSR: signature.callableUSR,
                        location: location
                    )
                    guard case .success(let parameters) = parametersResult else {
                        if case .failure(let reason) = parametersResult {
                            issueReasonsByAnchor[anchor] = reason
                        }
                        continue
                    }
                    guard let syntaxRoles = syntax.referencesByAnchor[anchor] else {
                        let syntaxReason =
                            syntax.issueReasonsByAnchor[anchor]
                            ?? "compiler callable reference syntax roles unavailable"
                        issueReasonsByAnchor[anchor] =
                            "callable reference syntax unresolved: \(syntaxReason)"
                        continue
                    }

                    switch syntaxRoles.kind {
                    case .bareReference:
                        referencesByAnchor[anchor] = CallableReferenceBinding.Reference(
                            anchor: anchor,
                            kind: .bareReference,
                            fullNameArguments: [],
                            subscriptArguments: []
                        )
                    case .fullNameReference:
                        guard
                            let ordinals = ParameterArgumentOrdinalMatcher.fullNameOrdinals(
                                argumentTokens: syntaxRoles.fullNameArgumentTokens,
                                parameters: parameters
                            )
                        else {
                            issueReasonsByAnchor[anchor] = Self.fullNameMismatchReason
                            continue
                        }
                        let bindings = zip(syntaxRoles.fullNameArgumentTokens, ordinals).map {
                            token, ordinal in
                            CallableReferenceBinding.Label(
                                parameterUSR: parameters[ordinal].parameterUSR,
                                parameterOrdinal: ordinal,
                                token: token
                            )
                        }
                        referencesByAnchor[anchor] = CallableReferenceBinding.Reference(
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
                                CallArgumentBinding.Argument(
                                    argumentIndex: argumentIndex,
                                    parameterUSR: parameters[ordinal].parameterUSR,
                                    parameterOrdinal: ordinal,
                                    syntaxRole: syntaxRoles.subscriptArguments[argumentIndex]
                                )
                            }
                            referencesByAnchor[anchor] = CallableReferenceBinding.Reference(
                                anchor: anchor,
                                kind: .subscriptCall,
                                fullNameArguments: [],
                                subscriptArguments: bindings
                            )
                        case .ambiguous:
                            issueReasonsByAnchor[anchor] = Self.ambiguousSubscriptReason
                        case .unmatched:
                            issueReasonsByAnchor[anchor] = Self.unmatchedSubscriptReason
                        }
                    }
                }
            }

            self.referencesByAnchor = referencesByAnchor
            self.issueReasonsByAnchor = issueReasonsByAnchor
            self.report = CallableReferenceBinding.Report(
                signatures: targetSignatures,
                referencesByAnchor: referencesByAnchor,
                syntaxRolesByAnchor: syntax.referencesByAnchor,
                issueReasonsByAnchor: issueReasonsByAnchor
            )
        }
    }

}
