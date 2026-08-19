import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Parameter argument binding

@Test func parameterCallArgumentBindingsResolveDefaultsVariadicsAndTrailingClosures() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ArgumentBindings.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    let send = testSymbol(
        "usr-send",
        "send(required:optional:values:completion:failure:)",
        .instanceMethod
    )
    let required = testSymbol("usr-required", "required", .parameter)
    let optional = testSymbol("usr-optional", "optional", .parameter)
    let values = testSymbol("usr-binding-values", "values", .parameter)
    let completion = testSymbol("usr-completion", "completion", .parameter)
    let failure = testSymbol("usr-failure", "failure", .parameter)
    let choose = testSymbol("usr-choose", "choose(first:second:)", .instanceMethod)
    let first = testSymbol("usr-first", "first", .parameter)
    let second = testSymbol("usr-second", "second", .parameter)
    let finish = testSymbol("usr-finish", "finish(animated:completion:)", .instanceMethod)
    let animated = testSymbol("usr-animated", "animated", .parameter)
    let finishCompletion = testSymbol(
        "usr-finish-completion",
        "completion",
        .parameter
    )
    let bool = testSymbol("usr-bool", "Bool", .struct)

    let occurrences = [
        testOccurrence(send, path: file.path, line: 2, token: "send", roles: [.definition]),
        testOccurrence(
            required,
            path: file.path,
            line: 2,
            token: "required",
            roles: [.definition],
            relations: [childOf(send)]
        ),
        testOccurrence(
            optional,
            path: file.path,
            line: 2,
            token: "optional",
            roles: [.definition],
            relations: [childOf(send)]
        ),
        testOccurrence(
            values,
            path: file.path,
            line: 2,
            token: "values",
            roles: [.definition],
            relations: [childOf(send)]
        ),
        testOccurrence(
            completion,
            path: file.path,
            line: 2,
            token: "completion",
            roles: [.definition],
            relations: [childOf(send)]
        ),
        testOccurrence(
            failure,
            path: file.path,
            line: 2,
            token: "failure",
            roles: [.definition],
            relations: [childOf(send)]
        ),
        testOccurrence(
            send,
            path: file.path,
            line: 7,
            token: "send",
            roles: [.reference, .call]
        ),
        testOccurrence(choose, path: file.path, line: 3, token: "choose", roles: [.definition]),
        testOccurrence(
            first,
            path: file.path,
            line: 3,
            token: "first",
            roles: [.definition],
            relations: [childOf(choose)]
        ),
        testOccurrence(
            second,
            path: file.path,
            line: 3,
            token: "second",
            roles: [.definition],
            relations: [childOf(choose)]
        ),
        testOccurrence(
            choose,
            path: file.path,
            line: 8,
            token: "choose",
            roles: [.reference, .call]
        ),
        testOccurrence(finish, path: file.path, line: 4, token: "finish", roles: [.definition]),
        testOccurrence(
            animated,
            path: file.path,
            line: 4,
            token: "animated",
            roles: [.definition],
            relations: [childOf(finish)]
        ),
        testOccurrence(bool, path: file.path, line: 4, token: "Bool", roles: [.reference]),
        testOccurrence(
            finishCompletion,
            path: file.path,
            line: 4,
            token: "completion",
            roles: [.definition],
            relations: [childOf(finish)]
        ),
        testOccurrence(
            finish,
            path: file.path,
            line: 9,
            token: "finish",
            roles: [.reference, .call]
        ),
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            send, required, optional, values, completion, failure,
            choose, first, second, finish, animated, finishCompletion, bool,
        ],
        occurrences: occurrences
    )
    let indexedFacts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [file])
    let parameterSyntaxFacts = ParameterSyntaxFacts(
        snapshot: snapshot,
        sourceCache: cache,
        obfuscationRoots: [file]
    )
    let callSiteSyntaxFacts = ParameterCallSiteSyntaxFacts(
        components: indexedFacts.parameterRenameComponents,
        sourceCache: cache
    )
    let bindingFacts = ParameterCallArgumentBindingFacts(
        components: indexedFacts.parameterRenameComponents,
        parameterRolesByUSR: parameterSyntaxFacts.rolesByUSR,
        callSiteSyntaxFacts: callSiteSyntaxFacts
    )

    let sendAnchor = ParameterCallSiteAnchor(
        callableUSR: send.usr,
        location: IndexedSourceLocation(
            path: file.path,
            line: 7,
            utf8Column: utf8Column(of: "send", in: lines[6])
        )
    )
    let sendBindings = try #require(bindingFacts.bindingsByAnchor[sendAnchor])
    #expect(
        sendBindings.arguments.map(\.parameterUSR) == [
            required.usr,
            values.usr,
            values.usr,
            completion.usr,
            failure.usr,
        ])
    #expect(sendBindings.arguments.map(\.parameterOrdinal) == [0, 2, 2, 3, 4])

    let finishAnchor = ParameterCallSiteAnchor(
        callableUSR: finish.usr,
        location: IndexedSourceLocation(
            path: file.path,
            line: 9,
            utf8Column: utf8Column(of: "finish", in: lines[8])
        )
    )
    let finishBindings = try #require(bindingFacts.bindingsByAnchor[finishAnchor])
    #expect(finishBindings.arguments.map(\.parameterUSR) == [finishCompletion.usr])
    #expect(finishBindings.arguments.map(\.parameterOrdinal) == [1])

    let summary = bindingFacts.summary
    #expect(summary.componentsWithNamedExternalLabels == 3)
    #expect(summary.namedExternalLabelParameters == 9)
    #expect(summary.indexedCallAnchors == 3)
    #expect(summary.syntaxResolvedCallAnchors == 3)
    #expect(summary.bindingResolvedCallAnchors == 2)
    #expect(summary.bindingUnresolvedCallAnchors == 1)
    #expect(summary.boundArguments == 6)
    #expect(summary.boundNamedLabelTokens == 3)
    #expect(summary.ambiguousCallAnchors == 1)
    #expect(summary.unmatchedCallAnchors == 0)
    #expect(summary.componentsWithAllIndexedCallsBound == 2)
    #expect(summary.namedParametersInComponentsWithAllIndexedCallsBound == 7)
    #expect(summary.componentsWithoutIndexedCalls == 0)
    #expect(summary.namedParametersInComponentsWithoutIndexedCalls == 0)
    #expect(
        summary.unresolvedByReason == [
            "call argument-to-parameter ordinal mapping is ambiguous": 1
        ])
    #expect(
        summary.unresolvedAnchors == [
            UnresolvedParameterCallArgumentBindingFact(
                callableUSR: choose.usr,
                callableName: choose.name,
                path: file.path,
                line: 8,
                utf8Column: utf8Column(of: "choose", in: lines[7]),
                reason: "call argument-to-parameter ordinal mapping is ambiguous"
            )
        ])
}
