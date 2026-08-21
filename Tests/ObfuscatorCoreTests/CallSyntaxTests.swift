import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Parameter calls and callable references

@Test func callSiteSyntaxResolvesCompilerAnchoredLabelsAndCallShapes() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Calls.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    func signature(
        usr: String,
        labels: [String],
        ownerCategory: CallableSignature.OwnerKind = .callable,
        callLine: Int? = nil,
        callToken: String? = nil,
        hasNonCallReference: Bool = false
    ) -> CallableSignature {
        let callLocations: [IndexSnapshot.Location]
        if let callLine, let callToken {
            callLocations = [
                IndexSnapshot.Location(
                    path: file.path,
                    line: callLine,
                    utf8Column: utf8Column(of: callToken, in: lines[callLine - 1])
                )
            ]
        } else {
            callLocations = []
        }
        let nonCallReferenceLocations =
            hasNonCallReference
            ? [
                IndexSnapshot.Location(
                    path: file.path,
                    line: 8,
                    utf8Column: utf8Column(of: "consume", in: lines[7])
                )
            ]
            : []
        return CallableSignature(
            callableUSR: usr,
            callableName: "call(\(labels.map { "\($0):" }.joined()))",
            callableKind: ownerCategory == .subscriptDeclaration
                ? "instanceProperty"
                : "instanceMethod",
            ownerCategory: ownerCategory,
            parameters: labels.enumerated().map { ordinal, label in
                CallableSignature.Parameter(
                    parameterUSR: "\(usr)-parameter-\(ordinal)",
                    ordinal: ordinal,
                    localBinding: label,
                    externalLabel: .named(label),
                    declarationLocations: [],
                    referenceLocations: []
                )
            },
            declarationLocations: [],
            callLocations: callLocations,
            nonCallReferenceLocations: nonCallReferenceLocations,
            hasOccurrenceOutsideSelectedRoots: false,
            isProtocolRequirement: false,
            isOverrideRelated: false,
            isRuntimeSensitive: false,
            isExternallyOwned: false,
            structuralReasons: []
        )
    }

    let signatures = [
        signature(usr: "usr-box-init", labels: ["first", "second"], callLine: 6, callToken: "Box"),
        signature(usr: "usr-run", labels: ["value", "completion"], callLine: 7, callToken: "run"),
        signature(usr: "usr-consume", labels: ["value"], callLine: 8, callToken: "consume"),
        signature(
            usr: "usr-subscript",
            labels: ["index"],
            ownerCategory: .subscriptDeclaration,
            callLine: 9,
            callToken: "["
        ),
        signature(
            usr: "usr-perform",
            labels: ["value", "completion", "failure"],
            callLine: 10,
            callToken: "perform"
        ),
        signature(
            usr: "usr-wrapper-init",
            labels: ["value"],
            callLine: 11,
            callToken: "Wrapper"
        ),
        signature(
            usr: "usr-unicode-label",
            labels: ["сallSettingsSource"],
            callLine: 12,
            callToken: "show"
        ),
        signature(
            usr: "usr-bad-anchor",
            labels: ["value"],
            callLine: 7,
            callToken: "value"
        ),
        signature(
            usr: "usr-reference-only",
            labels: ["input"],
            hasNonCallReference: true
        ),
    ]

    let syntaxIndex = CallSiteSyntax.Index(signatures: signatures, sourceCache: cache)
    let summary = syntaxIndex.report
    #expect(summary.signatureCountWithNamedExternalLabels == 9)
    #expect(summary.labeledParameterCount == 13)
    #expect(summary.indexedCallAnchors == 8)
    #expect(summary.resolvedCallAnchors == 7)
    #expect(summary.unresolvedCallAnchors == 1)
    #expect(summary.resolvedFunctionCalls == 5)
    #expect(summary.resolvedSubscriptCalls == 1)
    #expect(summary.resolvedAttributeCalls == 1)
    #expect(summary.resolvedEnumCasePatterns == 0)
    #expect(summary.parenthesizedArguments == 7)
    #expect(summary.namedParenthesizedArgumentTokens == 7)
    #expect(summary.unlabeledParenthesizedArguments == 0)
    #expect(summary.firstTrailingClosures == 2)
    #expect(summary.additionalTrailingClosureLabelTokens == 1)
    #expect(summary.callsWithoutExplicitArgumentDelimiters == 0)
    #expect(summary.signatureCountWithAllIndexedCallsResolved == 7)
    #expect(summary.namedParameterCountInSignaturesWithAllIndexedCallsResolved == 11)
    #expect(summary.signatureCountWithoutIndexedCalls == 1)
    #expect(summary.namedParameterCountInSignaturesWithoutIndexedCalls == 1)
    #expect(summary.signatureCountWithNonCallReferences == 1)
    #expect(summary.namedParameterCountInSignaturesWithNonCallReferences == 1)
    #expect(
        summary.unresolvedByReason == [
            "compiler call syntax unavailable at indexed call anchor": 1
        ])
    #expect(
        summary.unresolvedAnchors == [
            CallSiteSyntax.Issue(
                callableUSR: "usr-bad-anchor",
                callableName: "call(value:)",
                path: file.path,
                line: 7,
                utf8Column: utf8Column(of: "value", in: lines[6]),
                reason: "compiler call syntax unavailable at indexed call anchor"
            )
        ])

    let labelNames = Set(
        syntaxIndex.callsByAnchor.values.flatMap { roles in
            roles.arguments.compactMap { argument -> String? in
                switch argument {
                case .parenthesized(let label):
                    return label?.name
                case .firstTrailingClosure:
                    return nil
                case .additionalTrailingClosure(let label):
                    return label.name
                }
            }
        })
    #expect(labelNames == ["failure", "first", "index", "value", "сallSettingsSource"])
}

@Test func callableReferenceSyntaxClassifiesBareFullNameAndSubscriptUses() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("CallableReferences.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    func location(line: Int, token: String) -> IndexSnapshot.Location {
        IndexSnapshot.Location(
            path: file.path,
            line: line,
            utf8Column: utf8Column(of: token, in: lines[line - 1])
        )
    }

    func signature(
        usr: String,
        name: String,
        ownerCategory: CallableSignature.OwnerKind = .callable,
        references: [IndexSnapshot.Location]
    ) -> CallableSignature {
        CallableSignature(
            callableUSR: usr,
            callableName: name,
            callableKind: ownerCategory == .subscriptDeclaration
                ? "instanceProperty"
                : "instanceMethod",
            ownerCategory: ownerCategory,
            parameters: [
                CallableSignature.Parameter(
                    parameterUSR: "\(usr)-parameter",
                    ordinal: 0,
                    localBinding: "value",
                    externalLabel: .named(
                        ownerCategory == .subscriptDeclaration ? "label" : "value"
                    ),
                    declarationLocations: [],
                    referenceLocations: []
                )
            ],
            declarationLocations: [],
            callLocations: [],
            nonCallReferenceLocations: references,
            hasOccurrenceOutsideSelectedRoots: false,
            isProtocolRequirement: false,
            isOverrideRelated: false,
            isRuntimeSensitive: false,
            isExternallyOwned: false,
            structuralReasons: []
        )
    }

    let convert = signature(
        usr: "usr-convert",
        name: "convert(value:)",
        references: [
            location(line: 6, token: "convert"),
            location(line: 7, token: "convert"),
        ]
    )
    let subscriptSignature = signature(
        usr: "usr-subscript-reference",
        name: "subscript(label:)",
        ownerCategory: .subscriptDeclaration,
        references: [location(line: 8, token: "[")]
    )
    let invalid = signature(
        usr: "usr-invalid-reference",
        name: "invalid(value:)",
        references: [location(line: 2, token: "value")]
    )
    let mismatched = signature(
        usr: "usr-mismatched-reference",
        name: "mismatched(value:)",
        references: [location(line: 9, token: "convert")]
    )

    let syntaxIndex = CallableReferenceSyntax.Index(
        signatures: [convert, subscriptSignature, mismatched, invalid],
        sourceCache: cache
    )
    let summary = syntaxIndex.report
    #expect(summary.signatureCountWithNamedExternalLabels == 4)
    #expect(summary.labeledParameterCount == 4)
    #expect(summary.signatureCountWithIndexedReferences == 4)
    #expect(summary.namedParameterCountInSignaturesWithIndexedReferences == 4)
    #expect(summary.indexedReferenceAnchors == 5)
    #expect(summary.resolvedReferenceAnchors == 4)
    #expect(summary.unresolvedReferenceAnchors == 1)
    #expect(summary.resolvedBareReferences == 1)
    #expect(summary.resolvedFullNameReferences == 2)
    #expect(summary.fullNameArgumentTokens == 2)
    #expect(summary.namedFullNameArgumentTokens == 2)
    #expect(summary.resolvedSubscriptCalls == 1)
    #expect(summary.subscriptArguments == 1)
    #expect(summary.namedSubscriptArgumentLabelTokens == 1)
    #expect(summary.signatureCountWithAllIndexedReferencesResolved == 3)
    #expect(summary.namedParameterCountInSignaturesWithAllIndexedReferencesResolved == 3)
    #expect(
        summary.unresolvedByReason == [
            "compiler callable reference syntax unavailable at indexed anchor": 1
        ])
    #expect(
        summary.unresolvedAnchors == [
            CallableReferenceSyntax.Issue(
                callableUSR: invalid.callableUSR,
                callableName: invalid.callableName,
                path: file.path,
                line: 2,
                utf8Column: utf8Column(of: "value", in: lines[1]),
                reason: "compiler callable reference syntax unavailable at indexed anchor"
            )
        ])

    let bareAnchor = CallableReferenceSyntax.Anchor(
        callableUSR: convert.callableUSR,
        location: location(line: 6, token: "convert")
    )
    let bareRoles = try #require(syntaxIndex.referencesByAnchor[bareAnchor])
    #expect(bareRoles.kind == .bareReference)
    #expect(bareRoles.fullNameArgumentTokens.isEmpty)

    let fullNameAnchor = CallableReferenceSyntax.Anchor(
        callableUSR: convert.callableUSR,
        location: location(line: 7, token: "convert")
    )
    let fullNameRoles = try #require(syntaxIndex.referencesByAnchor[fullNameAnchor])
    #expect(fullNameRoles.kind == .fullNameReference)
    #expect(fullNameRoles.fullNameArgumentTokens.map(\.name) == ["value"])

    let subscriptAnchor = CallableReferenceSyntax.Anchor(
        callableUSR: subscriptSignature.callableUSR,
        location: location(line: 8, token: "[")
    )
    let subscriptRoles = try #require(syntaxIndex.referencesByAnchor[subscriptAnchor])
    #expect(subscriptRoles.kind == .subscriptCall)
    if case .parenthesized(label: let label)? = subscriptRoles.subscriptArguments.first {
        #expect(label?.name == "label")
    } else {
        Issue.record("Expected a named subscript argument")
    }

    let source = try #require(cache.file(for: file.path))
    func sourceToken(line: Int, token: String) throws -> SourceToken {
        let column = utf8Column(of: token, in: lines[line - 1])
        let byteOffset = try #require(source.byteOffset(line: line, utf8Column: column))
        let identifier = try #require(source.identifierToken(atByteOffset: byteOffset))
        return SourceToken(
            path: file.path,
            name: identifier.name,
            byteRange: identifier.byteRange,
            isBackticked: identifier.isBackticked
        )
    }

    func parameterRole(
        signature: CallableSignature,
        kind: ParameterSyntax.DeclarationKind,
        externalLabel: SourceToken,
        localBinding: SourceToken
    ) -> ParameterSyntax.Parameter {
        ParameterSyntax.Parameter(
            parameterUSR: signature.parameters[0].parameterUSR,
            kind: kind,
            indexedDeclarationAnchor: localBinding,
            externalLabel: .named(externalLabel),
            localBinding: localBinding,
            hasDefaultValue: false,
            isVariadic: false,
            trailingClosureCompatibility: .definitelyNonCallable,
            localBindingReferences: [],
            coordinatedShorthandBindingDeclarations: [],
            coordinatedShorthandBindingReferences: [],
            shadowingBindingDeclarations: [],
            implicitShadowingBindingNames: [],
            syntaxOwnerToken: nil,
            indexedOwnerUSR: signature.callableUSR,
            hasMatchingIndexedOwner: true
        )
    }

    let convertParameterToken = try sourceToken(line: 2, token: "value")
    let subscriptLabelToken = try sourceToken(line: 3, token: "label")
    let subscriptBindingToken = try sourceToken(line: 3, token: "value")
    let parameterRoles = [
        convert.parameters[0].parameterUSR: parameterRole(
            signature: convert,
            kind: .function,
            externalLabel: convertParameterToken,
            localBinding: convertParameterToken
        ),
        subscriptSignature.parameters[0].parameterUSR: parameterRole(
            signature: subscriptSignature,
            kind: .subscriptDeclaration,
            externalLabel: subscriptLabelToken,
            localBinding: subscriptBindingToken
        ),
        invalid.parameters[0].parameterUSR: parameterRole(
            signature: invalid,
            kind: .function,
            externalLabel: convertParameterToken,
            localBinding: convertParameterToken
        ),
        mismatched.parameters[0].parameterUSR: parameterRole(
            signature: mismatched,
            kind: .function,
            externalLabel: convertParameterToken,
            localBinding: convertParameterToken
        ),
    ]
    let bindingIndex = CallableReferenceBinding.Index(
        signatures: [convert, subscriptSignature, mismatched, invalid],
        parametersByUSR: parameterRoles,
        syntax: syntaxIndex
    )
    let bindingSummary = bindingIndex.report
    #expect(bindingSummary.signatureCountWithNamedExternalLabels == 4)
    #expect(bindingSummary.labeledParameterCount == 4)
    #expect(bindingSummary.signatureCountWithIndexedReferences == 4)
    #expect(bindingSummary.namedParameterCountInSignaturesWithIndexedReferences == 4)
    #expect(bindingSummary.indexedReferenceAnchors == 5)
    #expect(bindingSummary.syntaxResolvedReferenceAnchors == 4)
    #expect(bindingSummary.bindingResolvedReferenceAnchors == 3)
    #expect(bindingSummary.bindingUnresolvedReferenceAnchors == 2)
    #expect(bindingSummary.boundBareReferences == 1)
    #expect(bindingSummary.boundFullNameReferences == 1)
    #expect(bindingSummary.boundFullNameArgumentTokens == 1)
    #expect(bindingSummary.boundNamedFullNameLabelTokens == 1)
    #expect(bindingSummary.boundSubscriptCalls == 1)
    #expect(bindingSummary.boundSubscriptArguments == 1)
    #expect(bindingSummary.boundNamedSubscriptLabelTokens == 1)
    #expect(bindingSummary.signatureCountWithAllIndexedReferencesBound == 2)
    #expect(bindingSummary.namedParameterCountInSignaturesWithAllIndexedReferencesBound == 2)
    #expect(bindingSummary.fullNameSignatureMismatches == 1)
    #expect(bindingSummary.ambiguousSubscriptCalls == 0)
    #expect(bindingSummary.unmatchedSubscriptCalls == 0)
    #expect(
        bindingSummary.unresolvedByReason == [
            "callable reference syntax unresolved: compiler callable reference syntax unavailable at indexed anchor": 1,
            "full-name argument tokens do not match declaration parameter roles": 1,
        ])

    let bareBinding = try #require(bindingIndex.referencesByAnchor[bareAnchor])
    #expect(bareBinding.kind == .bareReference)
    #expect(bareBinding.fullNameArguments.isEmpty)
    #expect(bareBinding.subscriptArguments.isEmpty)

    let fullNameBinding = try #require(bindingIndex.referencesByAnchor[fullNameAnchor])
    #expect(fullNameBinding.kind == .fullNameReference)
    #expect(
        fullNameBinding.fullNameArguments.map(\.parameterUSR) == [
            convert.parameters[0].parameterUSR
        ])
    #expect(fullNameBinding.fullNameArguments.map(\.parameterOrdinal) == [0])
    #expect(fullNameBinding.fullNameArguments.map(\.token.name) == ["value"])

    let subscriptBinding = try #require(bindingIndex.referencesByAnchor[subscriptAnchor])
    #expect(subscriptBinding.kind == .subscriptCall)
    #expect(
        subscriptBinding.subscriptArguments.map(\.parameterUSR) == [
            subscriptSignature.parameters[0].parameterUSR
        ])
    #expect(subscriptBinding.subscriptArguments.map(\.parameterOrdinal) == [0])
}

@Test func externalLabelFamiliesRequireClosedRelationGraphs() throws {
    var nextOffset = 0

    func token(_ name: String) -> SourceToken {
        defer { nextOffset += name.utf8.count + 1 }
        return SourceToken(
            path: "/tmp/ExternalLabelFamilies.swift",
            name: name,
            byteRange: nextOffset..<(nextOffset + name.utf8.count)
        )
    }

    func signature(
        usr: String,
        label: String,
        isProtocolRequirement: Bool = false,
        isOverrideRelated: Bool = false,
        isRuntimeSensitive: Bool = false
    ) -> CallableSignature {
        CallableSignature(
            callableUSR: usr,
            callableName: "call(\(label):)",
            callableKind: "instanceMethod",
            ownerCategory: .callable,
            parameters: [
                CallableSignature.Parameter(
                    parameterUSR: "\(usr)-parameter",
                    ordinal: 0,
                    localBinding: label,
                    externalLabel: .named(label),
                    declarationLocations: [],
                    referenceLocations: []
                )
            ],
            declarationLocations: [],
            callLocations: [],
            nonCallReferenceLocations: [],
            hasOccurrenceOutsideSelectedRoots: false,
            isProtocolRequirement: isProtocolRequirement,
            isOverrideRelated: isOverrideRelated,
            isRuntimeSensitive: isRuntimeSensitive,
            isExternallyOwned: false,
            structuralReasons: []
        )
    }

    let standalone = signature(usr: "usr-standalone", label: "value")
    let requirement = signature(
        usr: "usr-requirement",
        label: "value",
        isProtocolRequirement: true,
        isOverrideRelated: true
    )
    let witness = signature(
        usr: "usr-witness",
        label: "value",
        isOverrideRelated: true
    )
    let externalOverride = signature(
        usr: "usr-external-override",
        label: "value",
        isOverrideRelated: true
    )
    let runtime = signature(
        usr: "c:objc-runtime-method",
        label: "value",
        isRuntimeSensitive: true
    )
    let mismatchedBase = signature(
        usr: "usr-mismatched-base",
        label: "value",
        isOverrideRelated: true
    )
    let mismatchedChild = signature(
        usr: "usr-mismatched-child",
        label: "other",
        isOverrideRelated: true
    )
    let signatures = [
        standalone,
        requirement,
        witness,
        externalOverride,
        runtime,
        mismatchedBase,
        mismatchedChild,
    ]

    var parameterRoles: [String: ParameterSyntax.Parameter] = [:]
    for signature in signatures {
        let label = try #require(signature.parameters.first?.externalLabel)
        guard case .named(let name) = label else {
            Issue.record("Expected named test parameter")
            continue
        }
        let sourceToken = token(name)
        let parameterUSR = try #require(signature.parameters.first?.parameterUSR)
        parameterRoles[parameterUSR] = ParameterSyntax.Parameter(
            parameterUSR: parameterUSR,
            kind: .function,
            indexedDeclarationAnchor: sourceToken,
            externalLabel: .named(sourceToken),
            localBinding: sourceToken,
            hasDefaultValue: false,
            isVariadic: false,
            trailingClosureCompatibility: .definitelyNonCallable,
            localBindingReferences: [],
            coordinatedShorthandBindingDeclarations: [],
            coordinatedShorthandBindingReferences: [],
            shadowingBindingDeclarations: [],
            implicitShadowingBindingNames: [],
            syntaxOwnerToken: nil,
            indexedOwnerUSR: signature.callableUSR,
            hasMatchingIndexedOwner: true
        )
    }

    let selectedUSRs = Set(signatures.map(\.callableUSR))
    let semanticIndex = SemanticIndex(
        selectedDeclarationUSRs: selectedUSRs,
        protocolRequirementUSRs: [requirement.callableUSR],
        runtimeSensitiveUSRs: [runtime.callableUSR],
        overrideRelationNeighbors: [
            requirement.callableUSR: [witness.callableUSR],
            witness.callableUSR: [requirement.callableUSR],
            externalOverride.callableUSR: ["s:external-base"],
            "s:external-base": [externalOverride.callableUSR],
            mismatchedBase.callableUSR: [mismatchedChild.callableUSR],
            mismatchedChild.callableUSR: [mismatchedBase.callableUSR],
        ],
        callableSignatures: signatures
    )
    let cache = try SourceFileCache(paths: [])
    let callSyntax = CallSiteSyntax.Index(
        signatures: signatures,
        sourceCache: cache
    )
    let callBindings = CallArgumentBinding.Index(
        signatures: signatures,
        parametersByUSR: parameterRoles,
        callSiteSyntax: callSyntax
    )
    let referenceSyntax = CallableReferenceSyntax.Index(
        signatures: signatures,
        sourceCache: cache
    )
    let referenceBindings = CallableReferenceBinding.Index(
        signatures: signatures,
        parametersByUSR: parameterRoles,
        syntax: referenceSyntax
    )
    let externalLabelAnalysis = ExternalLabel.Analysis(
        semanticIndex: semanticIndex,
        parametersByUSR: parameterRoles,
        callBindings: callBindings,
        referenceBindings: referenceBindings
    )

    let summary = externalLabelAnalysis.report
    #expect(summary.familyCount == 5)
    #expect(summary.signatureCount == 7)
    #expect(summary.labeledParameterCount == 7)
    #expect(summary.eligibleFamilyCount == 2)
    #expect(summary.eligibleSignatureCount == 3)
    #expect(summary.eligibleLabeledParameterCount == 3)
    #expect(summary.blockedFamilyCount == 3)
    #expect(summary.blockedSignatureCount == 4)
    #expect(summary.blockedLabeledParameterCount == 4)
    #expect(summary.standaloneFamilyCount == 2)
    #expect(summary.eligibleStandaloneFamilyCount == 1)
    #expect(summary.relatedFamilyCount == 3)
    #expect(summary.eligibleRelatedFamilyCount == 1)
    #expect(summary.protocolRelatedFamilyCount == 1)
    #expect(summary.eligibleProtocolRelatedFamilyCount == 1)
    #expect(summary.overrideRelatedFamilyCount == 3)
    #expect(summary.eligibleOverrideRelatedFamilyCount == 1)
    #expect(
        summary.familyCountsByBlocker == [
            "inconsistentRelatedSignature": 1,
            "objectiveCRuntimeDispatch": 1,
            "relationLeavesSelectedSourceRoots": 1,
        ])
    #expect(
        Set(summary.eligibleFamilies.map(\.key)) == [
            standalone.callableUSR,
            requirement.callableUSR,
        ])

    let closedProtocol = try #require(
        externalLabelAnalysis.families.first { signature in
            signature.relatedCallableUSRs == [requirement.callableUSR, witness.callableUSR]
        })
    #expect(closedProtocol.isEligible)
    #expect(closedProtocol.slots.count == 1)
    #expect(closedProtocol.slots[0].originalLabel == "value")
    #expect(
        closedProtocol.slots[0].parameterUSRs == [
            requirement.parameters[0].parameterUSR,
            witness.parameters[0].parameterUSR,
        ])

    let externalFamily = try #require(
        externalLabelAnalysis.families.first {
            $0.relatedCallableUSRs.contains("s:external-base")
        })
    #expect(!externalFamily.isEligible)
    #expect(externalFamily.blockers == [.relationLeavesSelectedSourceRoots])
}
