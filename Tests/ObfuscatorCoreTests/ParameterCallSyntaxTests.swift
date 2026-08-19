import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Parameter calls and callable references

@Test func parameterCallSiteSyntaxFactsResolveCompilerAnchoredLabelsAndCallShapes() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Calls.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    func component(
        usr: String,
        labels: [String],
        ownerCategory: ParameterOwnerCategory = .callable,
        callLine: Int? = nil,
        callToken: String? = nil,
        hasNonCallReference: Bool = false
    ) -> ParameterRenameComponent {
        let callLocations: [IndexedSourceLocation]
        if let callLine, let callToken {
            callLocations = [
                IndexedSourceLocation(
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
                IndexedSourceLocation(
                    path: file.path,
                    line: 8,
                    utf8Column: utf8Column(of: "consume", in: lines[7])
                )
            ]
            : []
        return ParameterRenameComponent(
            callableUSR: usr,
            callableName: "call(\(labels.map { "\($0):" }.joined()))",
            callableKind: ownerCategory == .subscriptDeclaration
                ? "instanceProperty"
                : "instanceMethod",
            ownerCategory: ownerCategory,
            members: labels.enumerated().map { ordinal, label in
                ParameterRenameMember(
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

    let components = [
        component(usr: "usr-box-init", labels: ["first", "second"], callLine: 6, callToken: "Box"),
        component(usr: "usr-run", labels: ["value", "completion"], callLine: 7, callToken: "run"),
        component(usr: "usr-consume", labels: ["value"], callLine: 8, callToken: "consume"),
        component(
            usr: "usr-subscript",
            labels: ["index"],
            ownerCategory: .subscriptDeclaration,
            callLine: 9,
            callToken: "["
        ),
        component(
            usr: "usr-perform",
            labels: ["value", "completion", "failure"],
            callLine: 10,
            callToken: "perform"
        ),
        component(
            usr: "usr-wrapper-init",
            labels: ["value"],
            callLine: 11,
            callToken: "Wrapper"
        ),
        component(
            usr: "usr-unicode-label",
            labels: ["сallSettingsSource"],
            callLine: 12,
            callToken: "show"
        ),
        component(
            usr: "usr-bad-anchor",
            labels: ["value"],
            callLine: 7,
            callToken: "value"
        ),
        component(
            usr: "usr-reference-only",
            labels: ["input"],
            hasNonCallReference: true
        ),
    ]

    let facts = ParameterCallSiteSyntaxFacts(components: components, sourceCache: cache)
    let summary = facts.summary
    #expect(summary.componentsWithNamedExternalLabels == 9)
    #expect(summary.namedExternalLabelParameters == 13)
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
    #expect(summary.componentsWithAllIndexedCallsResolved == 7)
    #expect(summary.namedParametersInComponentsWithAllIndexedCallsResolved == 11)
    #expect(summary.componentsWithoutIndexedCalls == 1)
    #expect(summary.namedParametersInComponentsWithoutIndexedCalls == 1)
    #expect(summary.componentsWithNonCallReferences == 1)
    #expect(summary.namedParametersInComponentsWithNonCallReferences == 1)
    #expect(
        summary.unresolvedByReason == [
            "compiler call syntax unavailable at indexed call anchor": 1
        ])
    #expect(
        summary.unresolvedAnchors == [
            UnresolvedParameterCallSiteSyntaxFact(
                callableUSR: "usr-bad-anchor",
                callableName: "call(value:)",
                path: file.path,
                line: 7,
                utf8Column: utf8Column(of: "value", in: lines[6]),
                reason: "compiler call syntax unavailable at indexed call anchor"
            )
        ])

    let labelNames = Set(
        facts.rolesByAnchor.values.flatMap { roles in
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

@Test func parameterCallableReferenceSyntaxFactsClassifyBareFullNameAndSubscriptUses() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("CallableReferences.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    func location(line: Int, token: String) -> IndexedSourceLocation {
        IndexedSourceLocation(
            path: file.path,
            line: line,
            utf8Column: utf8Column(of: token, in: lines[line - 1])
        )
    }

    func component(
        usr: String,
        name: String,
        ownerCategory: ParameterOwnerCategory = .callable,
        references: [IndexedSourceLocation]
    ) -> ParameterRenameComponent {
        ParameterRenameComponent(
            callableUSR: usr,
            callableName: name,
            callableKind: ownerCategory == .subscriptDeclaration
                ? "instanceProperty"
                : "instanceMethod",
            ownerCategory: ownerCategory,
            members: [
                ParameterRenameMember(
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

    let convert = component(
        usr: "usr-convert",
        name: "convert(value:)",
        references: [
            location(line: 6, token: "convert"),
            location(line: 7, token: "convert"),
        ]
    )
    let subscriptComponent = component(
        usr: "usr-subscript-reference",
        name: "subscript(label:)",
        ownerCategory: .subscriptDeclaration,
        references: [location(line: 8, token: "[")]
    )
    let invalid = component(
        usr: "usr-invalid-reference",
        name: "invalid(value:)",
        references: [location(line: 2, token: "value")]
    )
    let mismatched = component(
        usr: "usr-mismatched-reference",
        name: "mismatched(value:)",
        references: [location(line: 9, token: "convert")]
    )

    let facts = ParameterCallableReferenceSyntaxFacts(
        components: [convert, subscriptComponent, mismatched, invalid],
        sourceCache: cache
    )
    let summary = facts.summary
    #expect(summary.componentsWithNamedExternalLabels == 4)
    #expect(summary.namedExternalLabelParameters == 4)
    #expect(summary.componentsWithIndexedReferences == 4)
    #expect(summary.namedParametersInComponentsWithIndexedReferences == 4)
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
    #expect(summary.componentsWithAllIndexedReferencesResolved == 3)
    #expect(summary.namedParametersInComponentsWithAllIndexedReferencesResolved == 3)
    #expect(
        summary.unresolvedByReason == [
            "compiler callable reference syntax unavailable at indexed anchor": 1
        ])
    #expect(
        summary.unresolvedAnchors == [
            UnresolvedParameterCallableReferenceSyntaxFact(
                callableUSR: invalid.callableUSR,
                callableName: invalid.callableName,
                path: file.path,
                line: 2,
                utf8Column: utf8Column(of: "value", in: lines[1]),
                reason: "compiler callable reference syntax unavailable at indexed anchor"
            )
        ])

    let bareAnchor = ParameterCallableReferenceAnchor(
        callableUSR: convert.callableUSR,
        location: location(line: 6, token: "convert")
    )
    let bareRoles = try #require(facts.rolesByAnchor[bareAnchor])
    #expect(bareRoles.kind == .bareReference)
    #expect(bareRoles.fullNameArgumentTokens.isEmpty)

    let fullNameAnchor = ParameterCallableReferenceAnchor(
        callableUSR: convert.callableUSR,
        location: location(line: 7, token: "convert")
    )
    let fullNameRoles = try #require(facts.rolesByAnchor[fullNameAnchor])
    #expect(fullNameRoles.kind == .fullNameReference)
    #expect(fullNameRoles.fullNameArgumentTokens.map(\.name) == ["value"])

    let subscriptAnchor = ParameterCallableReferenceAnchor(
        callableUSR: subscriptComponent.callableUSR,
        location: location(line: 8, token: "[")
    )
    let subscriptRoles = try #require(facts.rolesByAnchor[subscriptAnchor])
    #expect(subscriptRoles.kind == .subscriptCall)
    if case .parenthesized(label: let label)? = subscriptRoles.subscriptArguments.first {
        #expect(label?.name == "label")
    } else {
        Issue.record("Expected a named subscript argument")
    }

    let source = try #require(cache.file(for: file.path))
    func sourceToken(line: Int, token: String) throws -> SourceTokenRange {
        let column = utf8Column(of: token, in: lines[line - 1])
        let byteOffset = try #require(source.byteOffset(line: line, utf8Column: column))
        let identifier = try #require(source.identifierToken(atByteOffset: byteOffset))
        return SourceTokenRange(
            path: file.path,
            name: identifier.name,
            byteRange: identifier.byteRange,
            isBackticked: identifier.isBackticked
        )
    }

    func parameterRole(
        component: ParameterRenameComponent,
        kind: ParameterDeclarationSyntaxKind,
        externalLabel: SourceTokenRange,
        localBinding: SourceTokenRange
    ) -> ParameterDeclarationSyntaxRoles {
        ParameterDeclarationSyntaxRoles(
            parameterUSR: component.members[0].parameterUSR,
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
            indexedOwnerUSR: component.callableUSR,
            syntaxOwnerMatchesIndexedOwner: true
        )
    }

    let convertParameterToken = try sourceToken(line: 2, token: "value")
    let subscriptLabelToken = try sourceToken(line: 3, token: "label")
    let subscriptBindingToken = try sourceToken(line: 3, token: "value")
    let parameterRoles = [
        convert.members[0].parameterUSR: parameterRole(
            component: convert,
            kind: .function,
            externalLabel: convertParameterToken,
            localBinding: convertParameterToken
        ),
        subscriptComponent.members[0].parameterUSR: parameterRole(
            component: subscriptComponent,
            kind: .subscriptDeclaration,
            externalLabel: subscriptLabelToken,
            localBinding: subscriptBindingToken
        ),
        invalid.members[0].parameterUSR: parameterRole(
            component: invalid,
            kind: .function,
            externalLabel: convertParameterToken,
            localBinding: convertParameterToken
        ),
        mismatched.members[0].parameterUSR: parameterRole(
            component: mismatched,
            kind: .function,
            externalLabel: convertParameterToken,
            localBinding: convertParameterToken
        ),
    ]
    let bindingFacts = ParameterCallableReferenceBindingFacts(
        components: [convert, subscriptComponent, mismatched, invalid],
        parameterRolesByUSR: parameterRoles,
        syntaxFacts: facts
    )
    let bindingSummary = bindingFacts.summary
    #expect(bindingSummary.componentsWithNamedExternalLabels == 4)
    #expect(bindingSummary.namedExternalLabelParameters == 4)
    #expect(bindingSummary.componentsWithIndexedReferences == 4)
    #expect(bindingSummary.namedParametersInComponentsWithIndexedReferences == 4)
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
    #expect(bindingSummary.componentsWithAllIndexedReferencesBound == 2)
    #expect(bindingSummary.namedParametersInComponentsWithAllIndexedReferencesBound == 2)
    #expect(bindingSummary.fullNameSignatureMismatches == 1)
    #expect(bindingSummary.ambiguousSubscriptCalls == 0)
    #expect(bindingSummary.unmatchedSubscriptCalls == 0)
    #expect(
        bindingSummary.unresolvedByReason == [
            "callable reference syntax unresolved: compiler callable reference syntax unavailable at indexed anchor": 1,
            "full-name argument tokens do not match declaration parameter roles": 1,
        ])

    let bareBinding = try #require(bindingFacts.bindingsByAnchor[bareAnchor])
    #expect(bareBinding.kind == .bareReference)
    #expect(bareBinding.fullNameArguments.isEmpty)
    #expect(bareBinding.subscriptArguments.isEmpty)

    let fullNameBinding = try #require(bindingFacts.bindingsByAnchor[fullNameAnchor])
    #expect(fullNameBinding.kind == .fullNameReference)
    #expect(
        fullNameBinding.fullNameArguments.map(\.parameterUSR) == [
            convert.members[0].parameterUSR
        ])
    #expect(fullNameBinding.fullNameArguments.map(\.parameterOrdinal) == [0])
    #expect(fullNameBinding.fullNameArguments.map(\.token.name) == ["value"])

    let subscriptBinding = try #require(bindingFacts.bindingsByAnchor[subscriptAnchor])
    #expect(subscriptBinding.kind == .subscriptCall)
    #expect(
        subscriptBinding.subscriptArguments.map(\.parameterUSR) == [
            subscriptComponent.members[0].parameterUSR
        ])
    #expect(subscriptBinding.subscriptArguments.map(\.parameterOrdinal) == [0])
}

@Test func parameterExternalLabelComponentsRequireClosedRelationGraphs() throws {
    var nextOffset = 0

    func token(_ name: String) -> SourceTokenRange {
        defer { nextOffset += name.utf8.count + 1 }
        return SourceTokenRange(
            path: "/tmp/ParameterExternalLabelComponents.swift",
            name: name,
            byteRange: nextOffset..<(nextOffset + name.utf8.count)
        )
    }

    func component(
        usr: String,
        label: String,
        isProtocolRequirement: Bool = false,
        isOverrideRelated: Bool = false,
        isRuntimeSensitive: Bool = false
    ) -> ParameterRenameComponent {
        ParameterRenameComponent(
            callableUSR: usr,
            callableName: "call(\(label):)",
            callableKind: "instanceMethod",
            ownerCategory: .callable,
            members: [
                ParameterRenameMember(
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

    let standalone = component(usr: "usr-standalone", label: "value")
    let requirement = component(
        usr: "usr-requirement",
        label: "value",
        isProtocolRequirement: true,
        isOverrideRelated: true
    )
    let witness = component(
        usr: "usr-witness",
        label: "value",
        isOverrideRelated: true
    )
    let externalOverride = component(
        usr: "usr-external-override",
        label: "value",
        isOverrideRelated: true
    )
    let runtime = component(
        usr: "c:objc-runtime-method",
        label: "value",
        isRuntimeSensitive: true
    )
    let mismatchedBase = component(
        usr: "usr-mismatched-base",
        label: "value",
        isOverrideRelated: true
    )
    let mismatchedChild = component(
        usr: "usr-mismatched-child",
        label: "other",
        isOverrideRelated: true
    )
    let components = [
        standalone,
        requirement,
        witness,
        externalOverride,
        runtime,
        mismatchedBase,
        mismatchedChild,
    ]

    var parameterRoles: [String: ParameterDeclarationSyntaxRoles] = [:]
    for component in components {
        let label = try #require(component.members.first?.externalLabel)
        guard case .named(let name) = label else {
            Issue.record("Expected named test parameter")
            continue
        }
        let sourceToken = token(name)
        let parameterUSR = try #require(component.members.first?.parameterUSR)
        parameterRoles[parameterUSR] = ParameterDeclarationSyntaxRoles(
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
            indexedOwnerUSR: component.callableUSR,
            syntaxOwnerMatchesIndexedOwner: true
        )
    }

    let selectedUSRs = Set(components.map(\.callableUSR))
    let indexedFacts = IndexedSemanticFacts(
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
        parameterRenameComponents: components
    )
    let cache = try SourceFileCache(paths: [])
    let callSyntaxFacts = ParameterCallSiteSyntaxFacts(
        components: components,
        sourceCache: cache
    )
    let callBindingFacts = ParameterCallArgumentBindingFacts(
        components: components,
        parameterRolesByUSR: parameterRoles,
        callSiteSyntaxFacts: callSyntaxFacts
    )
    let referenceSyntaxFacts = ParameterCallableReferenceSyntaxFacts(
        components: components,
        sourceCache: cache
    )
    let referenceBindingFacts = ParameterCallableReferenceBindingFacts(
        components: components,
        parameterRolesByUSR: parameterRoles,
        syntaxFacts: referenceSyntaxFacts
    )
    let facts = ParameterExternalLabelComponentFacts(
        indexedFacts: indexedFacts,
        parameterRolesByUSR: parameterRoles,
        callBindingFacts: callBindingFacts,
        callableReferenceBindingFacts: referenceBindingFacts
    )

    let summary = facts.summary
    #expect(summary.atomicComponents == 5)
    #expect(summary.sourceCallableComponents == 7)
    #expect(summary.namedExternalLabelParameters == 7)
    #expect(summary.eligibleAtomicComponents == 2)
    #expect(summary.eligibleSourceCallableComponents == 3)
    #expect(summary.eligibleNamedExternalLabelParameters == 3)
    #expect(summary.deniedAtomicComponents == 3)
    #expect(summary.deniedSourceCallableComponents == 4)
    #expect(summary.deniedNamedExternalLabelParameters == 4)
    #expect(summary.standaloneAtomicComponents == 2)
    #expect(summary.eligibleStandaloneAtomicComponents == 1)
    #expect(summary.relatedAtomicComponents == 3)
    #expect(summary.eligibleRelatedAtomicComponents == 1)
    #expect(summary.protocolRelatedAtomicComponents == 1)
    #expect(summary.eligibleProtocolRelatedAtomicComponents == 1)
    #expect(summary.overrideRelatedAtomicComponents == 3)
    #expect(summary.eligibleOverrideRelatedAtomicComponents == 1)
    #expect(
        summary.blockerComponents == [
            "inconsistentRelatedSignature": 1,
            "objectiveCRuntimeDispatch": 1,
            "relationLeavesSelectedSourceRoots": 1,
        ])
    #expect(
        Set(summary.eligibleComponents.map(\.key)) == [
            standalone.callableUSR,
            requirement.callableUSR,
        ])

    let closedProtocol = try #require(
        facts.components.first { component in
            component.relatedCallableUSRs == [requirement.callableUSR, witness.callableUSR]
        })
    #expect(closedProtocol.isEligible)
    #expect(closedProtocol.ordinalComponents.count == 1)
    #expect(closedProtocol.ordinalComponents[0].originalLabel == "value")
    #expect(
        closedProtocol.ordinalComponents[0].parameterUSRs == [
            requirement.members[0].parameterUSR,
            witness.members[0].parameterUSR,
        ])

    let externalComponent = try #require(
        facts.components.first {
            $0.relatedCallableUSRs.contains("s:external-base")
        })
    #expect(!externalComponent.isEligible)
    #expect(externalComponent.blockers == [.relationLeavesSelectedSourceRoots])
}
