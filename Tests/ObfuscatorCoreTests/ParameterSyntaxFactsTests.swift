import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Parameter syntax and local binding scopes

@Test func parameterSyntaxFactsResolveExactRolesWithoutDeclarationTextScanning() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Parameters.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let accessor = testSymbol("usr-accessor", "willSet:stored", .instanceMethod)
    let nextValue = testSymbol("usr-next-value", "nextValue", .parameter)
    let outer = testSymbol("usr-outer", "outer(external:)", .instanceMethod)
    let local = testSymbol("usr-local", "local", .parameter)
    let nestedValue = testSymbol("usr-nested-value", "nestedValue", .parameter)
    let inner = testSymbol("usr-inner", "inner", .parameter)
    let subscriptDeclaration = testSymbol("usr-subscript", "subscript(offset:)", .instanceProperty)
    let index = testSymbol("usr-index", "index", .parameter)
    let enumCase = testSymbol("usr-enum-case", "payload(label:_:_:)", .enumConstant)
    let value = testSymbol("usr-value", "value", .parameter)
    let omittedValue = testSymbol("usr-omitted-value", "_", .parameter)
    let sourceNameAbsent = testSymbol("usr-source-name-absent", "_", .parameter)
    let closureOwner = testSymbol("usr-closure-owner", "closure", .variable)
    let closureValue = testSymbol("usr-closure-value", "closureValue", .parameter)

    let occurrences = [
        testOccurrence(accessor, path: file.path, line: 2, token: "stored", roles: [.definition]),
        testOccurrence(
            nextValue,
            path: file.path,
            line: 3,
            token: "nextValue",
            roles: [.definition],
            relations: [childOf(accessor)]
        ),
        testOccurrence(outer, path: file.path, line: 5, token: "outer", roles: [.definition]),
        testOccurrence(
            local,
            path: file.path,
            line: 5,
            token: "local",
            roles: [.definition],
            relations: [childOf(outer)]
        ),
        testOccurrence(
            nestedValue,
            path: file.path,
            line: 6,
            token: "nestedValue",
            roles: [.definition],
            relations: [childOf(outer)]
        ),
        testOccurrence(
            inner,
            path: file.path,
            line: 6,
            token: "inner",
            roles: [.definition],
            relations: [childOf(outer)]
        ),
        testOccurrence(
            subscriptDeclaration,
            path: file.path,
            line: 10,
            token: "subscript",
            roles: [.definition]
        ),
        testOccurrence(
            index,
            path: file.path,
            line: 10,
            token: "index",
            roles: [.definition],
            relations: [childOf(subscriptDeclaration)]
        ),
        testOccurrence(enumCase, path: file.path, line: 12, token: "payload", roles: [.definition]),
        testOccurrence(
            value,
            path: file.path,
            line: 12,
            token: "value",
            roles: [.definition],
            relations: [childOf(enumCase)]
        ),
        testOccurrence(
            omittedValue,
            path: file.path,
            line: 12,
            token: "_",
            roles: [.definition],
            relations: [childOf(enumCase)]
        ),
        testOccurrence(
            sourceNameAbsent,
            path: file.path,
            line: 12,
            token: "Bool",
            roles: [.definition],
            relations: [childOf(enumCase)]
        ),
        testOccurrence(
            closureOwner,
            path: file.path,
            line: 13,
            token: "closure",
            roles: [.definition]
        ),
        testOccurrence(
            closureValue,
            path: file.path,
            line: 13,
            token: "closureValue",
            roles: [.definition],
            relations: [childOf(closureOwner)]
        ),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            accessor, nextValue, outer, local, nestedValue, inner,
            subscriptDeclaration, index, enumCase, value, omittedValue, sourceNameAbsent,
            closureOwner, closureValue,
        ],
        occurrences: occurrences
    )

    let facts = ParameterSyntaxFacts(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [file]
    )
    #expect(facts.unresolvedReasonsByUSR.isEmpty)
    #expect(facts.rolesByUSR.count == 9)
    #expect(
        facts.localBindingOnlyCoverageCandidateUSRs == [
            local.usr,
            nestedValue.usr,
            inner.usr,
            nextValue.usr,
            index.usr,
            closureValue.usr,
        ])

    let outerRoles = try #require(facts.rolesByUSR[local.usr])
    #expect(outerRoles.kind == .function)
    #expect(outerRoles.localBinding?.name == "local")
    #expect(outerRoles.syntaxOwnerToken?.name == "outer")
    #expect(outerRoles.syntaxOwnerMatchesIndexedOwner)
    if case .named(let label) = outerRoles.externalLabel {
        #expect(label.name == "external")
        #expect(label.byteRange != outerRoles.localBinding?.byteRange)
    } else {
        Issue.record("Expected a named external label")
    }

    let nestedRoles = try #require(facts.rolesByUSR[nestedValue.usr])
    #expect(nestedRoles.kind == .function)
    #expect(nestedRoles.localBinding?.name == "nestedValue")
    #expect(nestedRoles.syntaxOwnerToken?.name == "nested")
    #expect(nestedRoles.isNestedLocalFunctionParameter)
    if case .omitted(let label) = nestedRoles.externalLabel {
        #expect(label.name == "_")
    } else {
        Issue.record("Expected an omitted external label")
    }

    let innerRoles = try #require(facts.rolesByUSR[inner.usr])
    #expect(innerRoles.isNestedLocalFunctionParameter)
    #expect(innerRoles.localBinding?.name == "inner")
    if case .named(let label) = innerRoles.externalLabel {
        #expect(label.name == "wire")
    } else {
        Issue.record("Expected a named nested-function label")
    }
    #expect(innerRoles.hasDefaultValue)
    #expect(!innerRoles.isVariadic)

    let accessorRoles = try #require(facts.rolesByUSR[nextValue.usr])
    #expect(accessorRoles.kind == .accessor)
    #expect(accessorRoles.externalLabel == .none)
    #expect(accessorRoles.localBinding?.name == "nextValue")
    #expect(!accessorRoles.isNestedLocalFunctionParameter)

    let subscriptRoles = try #require(facts.rolesByUSR[index.usr])
    #expect(subscriptRoles.kind == .subscriptDeclaration)
    #expect(subscriptRoles.localBinding?.name == "index")

    let enumRoles = try #require(facts.rolesByUSR[value.usr])
    #expect(enumRoles.kind == .enumCase)
    #expect(enumRoles.localBinding?.name == "value")
    let omittedEnumRoles = try #require(facts.rolesByUSR[omittedValue.usr])
    #expect(omittedEnumRoles.kind == .enumCase)
    #expect(omittedEnumRoles.localBinding == nil)
    if case .omitted(let label) = omittedEnumRoles.externalLabel {
        #expect(label.name == "_")
    } else {
        Issue.record("Expected an omitted enum associated-value label")
    }
    let sourceNameAbsentRoles = try #require(facts.rolesByUSR[sourceNameAbsent.usr])
    #expect(sourceNameAbsentRoles.kind == .enumCase)
    #expect(sourceNameAbsentRoles.externalLabel == .none)
    #expect(sourceNameAbsentRoles.localBinding == nil)
    #expect(sourceNameAbsentRoles.indexedDeclarationAnchor.name == "Bool")

    let closureRoles = try #require(facts.rolesByUSR[closureValue.usr])
    #expect(closureRoles.kind == .closure)
    #expect(closureRoles.externalLabel == .none)
    #expect(closureRoles.localBinding?.name == "closureValue")

    let summary = facts.summary
    #expect(summary.explicitParameters == 9)
    #expect(summary.resolvedParameters == 9)
    #expect(summary.unresolvedParameters == 0)
    #expect(summary.functionParameters == 3)
    #expect(summary.initializerParameters == 0)
    #expect(summary.subscriptParameters == 1)
    #expect(summary.enumCaseParameters == 3)
    #expect(summary.accessorBindings == 1)
    #expect(summary.closureParameters == 1)
    #expect(summary.nestedLocalFunctionParameters == 2)
    #expect(summary.namedExternalLabels == 4)
    #expect(summary.omittedExternalLabels == 2)
    #expect(summary.parametersWithoutExternalLabels == 3)
    #expect(summary.localBindings == 7)
    #expect(summary.parametersWithoutLocalBindings == 2)
    #expect(summary.parametersWithoutSourceNames == 1)
    #expect(summary.parametersWithDefaultValues == 1)
    #expect(summary.variadicParameters == 0)
    #expect(summary.sharedLabelAndBindingTokens == 0)
    #expect(summary.distinctLabelAndBindingTokens == 5)
    #expect(summary.localBindingReferenceTokens == 6)
    #expect(summary.parametersWithShadowingBindingDeclarations == 0)
    #expect(summary.localBindingOnlyCoverageCandidates == 6)
    #expect(summary.parametersRequiringExternalLabelCoordination == 3)
    #expect(summary.nonEnumParametersWithoutLocalBindings == 0)
    #expect(summary.enumCaseParametersExcludedFromParameterStage == 3)
}

@Test func parameterSyntaxFactsRecordDefaultAndVariadicTraits() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ParameterTraits.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let owner = testSymbol("usr-configure", "configure(_:retries:completion:)", .function)
    let values = testSymbol("usr-values", "values", .parameter)
    let retries = testSymbol("usr-retries", "retries", .parameter)
    let completion = testSymbol("usr-traits-completion", "completion", .parameter)
    let int = testSymbol("usr-int", "Int", .struct)
    let childOfOwner = RelationRecord(
        usr: owner.usr,
        name: owner.name,
        rolesRaw: 0,
        roles: ["childOf"]
    )
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [owner, values, retries, completion, int],
        occurrences: [
            testOccurrence(
                owner,
                path: file.path,
                line: 1,
                token: "configure",
                roles: [.definition]
            ),
            testOccurrence(
                values,
                path: file.path,
                line: 2,
                token: "values",
                roles: [.definition],
                relations: [childOfOwner]
            ),
            testOccurrence(
                values,
                path: file.path,
                line: 6,
                token: "values",
                roles: [.reference]
            ),
            testOccurrence(int, path: file.path, line: 2, token: "Int", roles: [.reference]),
            testOccurrence(
                retries,
                path: file.path,
                line: 3,
                token: "retries",
                roles: [.definition],
                relations: [childOfOwner]
            ),
            testOccurrence(
                retries,
                path: file.path,
                line: 7,
                token: "retries",
                roles: [.reference]
            ),
            testOccurrence(int, path: file.path, line: 3, token: "Int", roles: [.reference]),
            testOccurrence(
                completion,
                path: file.path,
                line: 4,
                token: "completion",
                roles: [.definition],
                relations: [childOfOwner]
            ),
            testOccurrence(
                completion,
                path: file.path,
                line: 8,
                token: "completion",
                roles: [.reference]
            ),
        ]
    )

    let facts = ParameterSyntaxFacts(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [file]
    )
    let valuesRoles = try #require(facts.rolesByUSR[values.usr])
    #expect(!valuesRoles.hasDefaultValue)
    #expect(valuesRoles.isVariadic)
    #expect(valuesRoles.trailingClosureCompatibility == .definitelyNonCallable)
    if case .omitted(let label) = valuesRoles.externalLabel {
        #expect(label.name == "_")
    } else {
        Issue.record("Expected an explicitly omitted variadic label")
    }

    let retriesRoles = try #require(facts.rolesByUSR[retries.usr])
    #expect(retriesRoles.hasDefaultValue)
    #expect(!retriesRoles.isVariadic)
    #expect(retriesRoles.trailingClosureCompatibility == .definitelyNonCallable)
    if case .named(let label) = retriesRoles.externalLabel {
        #expect(label.name == "retries")
    } else {
        Issue.record("Expected a named defaulted label")
    }

    let completionRoles = try #require(facts.rolesByUSR[completion.usr])
    #expect(completionRoles.hasDefaultValue)
    #expect(completionRoles.trailingClosureCompatibility == .definitelyCallable)

    #expect(facts.summary.parametersWithDefaultValues == 2)
    #expect(facts.summary.variadicParameters == 1)
    #expect(facts.summary.definitelyCallableParameters == 1)
    #expect(facts.summary.definitelyNonCallableParameters == 2)
    #expect(facts.summary.parametersWithUnknownCallability == 0)
}

@Test func parameterSyntaxFactsUseSwiftOperatorAndSubscriptLabelSemantics() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ImplicitLabels.swift")
    try copyFixture(to: file)
    let cache = try SourceFileCache(paths: [file.path])

    let plus = testSymbol("usr-plus", "+(_:_:)", .staticMethod)
    let lhs = testSymbol("usr-lhs", "lhs", .parameter)
    let rhs = testSymbol("usr-rhs", "rhs", .parameter)
    let defaultSubscript = testSymbol("usr-default-subscript", "subscript(_:)", .instanceProperty)
    let index = testSymbol("usr-index", "index", .parameter)
    let labeledSubscript = testSymbol(
        "usr-labeled-subscript",
        "subscript(label:)",
        .instanceProperty
    )
    let localIndex = testSymbol("usr-local-index", "localIndex", .parameter)
    let occurrences = [
        testOccurrence(plus, path: file.path, line: 2, token: "+", roles: [.definition]),
        testOccurrence(
            lhs,
            path: file.path,
            line: 2,
            token: "lhs",
            roles: [.definition],
            relations: [childOf(plus)]
        ),
        testOccurrence(
            rhs,
            path: file.path,
            line: 2,
            token: "rhs",
            roles: [.definition],
            relations: [childOf(plus)]
        ),
        testOccurrence(lhs, path: file.path, line: 3, token: "lhs", roles: [.reference]),
        testOccurrence(rhs, path: file.path, line: 4, token: "rhs", roles: [.reference]),
        testOccurrence(
            defaultSubscript,
            path: file.path,
            line: 6,
            token: "subscript",
            roles: [.definition]
        ),
        testOccurrence(
            index,
            path: file.path,
            line: 6,
            token: "index",
            roles: [.definition],
            relations: [childOf(defaultSubscript)]
        ),
        testOccurrence(index, path: file.path, line: 7, token: "index", roles: [.reference]),
        testOccurrence(
            labeledSubscript,
            path: file.path,
            line: 9,
            token: "subscript",
            roles: [.definition]
        ),
        testOccurrence(
            localIndex,
            path: file.path,
            line: 9,
            token: "localIndex",
            roles: [.definition],
            relations: [childOf(labeledSubscript)]
        ),
        testOccurrence(
            localIndex,
            path: file.path,
            line: 10,
            token: "localIndex",
            roles: [.reference]
        ),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [plus, lhs, rhs, defaultSubscript, index, labeledSubscript, localIndex],
        occurrences: occurrences
    )

    let facts = ParameterSyntaxFacts(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [file]
    )
    #expect(facts.unresolvedReasonsByUSR.isEmpty)
    #expect(
        facts.localBindingOnlyCoverageCandidateUSRs == [
            lhs.usr, rhs.usr, index.usr, localIndex.usr,
        ])

    let lhsRoles = try #require(facts.rolesByUSR[lhs.usr])
    #expect(lhsRoles.externalLabel == .none)
    #expect(lhsRoles.localBinding?.name == "lhs")
    #expect(lhsRoles.syntaxOwnerToken?.name == "+")
    #expect(lhsRoles.syntaxOwnerMatchesIndexedOwner)
    #expect(!lhsRoles.isNestedLocalFunctionParameter)
    let rhsRoles = try #require(facts.rolesByUSR[rhs.usr])
    #expect(rhsRoles.externalLabel == .none)

    let indexRoles = try #require(facts.rolesByUSR[index.usr])
    #expect(indexRoles.externalLabel == .none)
    #expect(indexRoles.localBinding?.name == "index")
    #expect(indexRoles.syntaxOwnerMatchesIndexedOwner)

    let localIndexRoles = try #require(facts.rolesByUSR[localIndex.usr])
    if case .named(let label) = localIndexRoles.externalLabel {
        #expect(label.name == "label")
    } else {
        Issue.record("Expected the explicit subscript label to remain named")
    }
    #expect(localIndexRoles.localBinding?.name == "localIndex")

    let summary = facts.summary
    #expect(summary.explicitParameters == 4)
    #expect(summary.resolvedParameters == 4)
    #expect(summary.functionParameters == 2)
    #expect(summary.subscriptParameters == 2)
    #expect(summary.namedExternalLabels == 1)
    #expect(summary.omittedExternalLabels == 0)
    #expect(summary.parametersWithoutExternalLabels == 3)
    #expect(summary.localBindingOnlyCoverageCandidates == 4)
    #expect(summary.parametersRequiringExternalLabelCoordination == 1)

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let lhsEntry = try #require(plan.entries.first { $0.usr == lhs.usr })
    let rhsEntry = try #require(plan.entries.first { $0.usr == rhs.usr })
    let indexEntry = try #require(plan.entries.first { $0.usr == index.usr })
    let localIndexEntry = try #require(plan.entries.first { $0.usr == localIndex.usr })
    #expect(
        Set(plan.entries.map(\.usr)) == [
            lhs.usr, rhs.usr, index.usr, localIndex.usr,
        ])
    #expect(lhsEntry.replacements.count == 2)
    #expect(rhsEntry.replacements.count == 2)
    #expect(indexEntry.replacements.count == 2)
    #expect(plan.parameterLocalBindingOutcome.candidates == 4)
    #expect(plan.parameterLocalBindingOutcome.renamed == 4)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(
        patched.contains(
            "static func + (\(lhsEntry.newName): Sample, \(rhsEntry.newName): Sample)"
        ))
    #expect(patched.contains("subscript(\(indexEntry.newName): Int)"))
    #expect(
        patched.contains(
            "subscript(\(localIndexEntry.newName) \(localIndexEntry.newName): Int)"
        ))
}
