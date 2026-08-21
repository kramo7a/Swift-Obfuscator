import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Coverage

@Test func coverageCohortUsesExplicitSourceSurfaceIndependentOfRenameEligibility() throws {
    let path = "/tmp/CoverageSample.swift"
    let outsidePath = "/tmp/OutsideSelection.swift"
    let renamedProperty = IndexSnapshot.Symbol(
        usr: "usr-renamed-property",
        name: "renamedValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let deniedProperty = IndexSnapshot.Symbol(
        usr: "usr-denied-property",
        name: "storedValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let getter = IndexSnapshot.Symbol(
        usr: "usr-getter",
        name: "getter:renamedValue",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let setter = IndexSnapshot.Symbol(
        usr: "usr-setter",
        name: "setter:storedValue",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let parameter = IndexSnapshot.Symbol(
        usr: "usr-parameter",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let enumCase = IndexSnapshot.Symbol(
        usr: "usr-enum-case",
        name: "ready",
        kind: "enumConstant",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let runtimeProperty = IndexSnapshot.Symbol(
        usr: "c:objc-runtime-property",
        name: "runtimeValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let constructor = IndexSnapshot.Symbol(
        usr: "usr-constructor",
        name: "init(value:)",
        kind: "constructor",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let compilerDerivedProperty = IndexSnapshot.Symbol(
        usr: "usr-compiler-derived-property",
        name: "$value",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let outsideProperty = IndexSnapshot.Symbol(
        usr: "usr-outside-property",
        name: "outsideValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )

    func occurrence(
        _ symbol: IndexSnapshot.Symbol,
        path occurrencePath: String? = nil,
        roles: [String] = ["declaration"],
        relation: IndexSnapshot.Relation? = nil
    ) -> IndexSnapshot.Occurrence {
        IndexSnapshot.Occurrence(
            symbol: symbol,
            path: occurrencePath ?? path,
            line: 1,
            utf8Column: 1,
            moduleName: "CoverageSample",
            isSystem: false,
            rolesRaw: 1,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relation.map { [$0] } ?? []
        )
    }

    let snapshot = IndexSnapshot(
        sourceFiles: [path, outsidePath],
        symbols: [
            renamedProperty,
            deniedProperty,
            getter,
            setter,
            parameter,
            enumCase,
            runtimeProperty,
            constructor,
            compilerDerivedProperty,
            outsideProperty,
        ],
        occurrences: [
            occurrence(renamedProperty),
            occurrence(deniedProperty),
            occurrence(
                getter,
                relation: IndexSnapshot.Relation(
                    usr: renamedProperty.usr,
                    name: renamedProperty.name,
                    rolesRaw: 1,
                    roles: ["accessorOf"]
                )),
            occurrence(setter),
            occurrence(parameter),
            occurrence(enumCase),
            occurrence(runtimeProperty),
            occurrence(constructor),
            occurrence(compilerDerivedProperty, roles: ["definition", "implicit"]),
            occurrence(outsideProperty, path: outsidePath),
        ]
    )
    let plan = RenamePlan(
        renames: [
            RenamePlan.Entry(
                usr: renamedProperty.usr,
                kind: renamedProperty.kind,
                oldName: renamedProperty.name,
                newName: "oa",
                edits: []
            )
        ],
        rejections: [
            RenameEligibility(
                usr: deniedProperty.usr,
                symbolName: deniedProperty.name,
                symbolKind: deniedProperty.kind,
                isEligible: false,
                originalName: deniedProperty.name,
                reasons: [
                    "stored property declarations require memberwise initializer label support",
                    "implicit occurrence at \(path):1:1",
                ]
            ),
            RenameEligibility(
                usr: getter.usr,
                symbolName: getter.name,
                symbolKind: getter.kind,
                isEligible: false,
                originalName: nil,
                reasons: ["implicit occurrence at \(path):1:1"]
            ),
            RenameEligibility(
                usr: setter.usr,
                symbolName: setter.name,
                symbolKind: setter.kind,
                isEligible: false,
                originalName: nil,
                reasons: ["implicit occurrence at \(path):1:1"]
            ),
            RenameEligibility(
                usr: parameter.usr,
                symbolName: parameter.name,
                symbolKind: parameter.kind,
                isEligible: false,
                originalName: parameter.name,
                reasons: ["unsupported symbol kind parameter"]
            ),
            RenameEligibility(
                usr: enumCase.usr,
                symbolName: enumCase.name,
                symbolKind: enumCase.kind,
                isEligible: false,
                originalName: enumCase.name,
                reasons: ["unsupported symbol kind enumConstant"]
            ),
            RenameEligibility(
                usr: runtimeProperty.usr,
                symbolName: runtimeProperty.name,
                symbolKind: runtimeProperty.kind,
                isEligible: false,
                originalName: runtimeProperty.name,
                reasons: ["Objective-C-compatible USR requires a stable runtime name"]
            ),
            RenameEligibility(
                usr: constructor.usr,
                symbolName: constructor.name,
                symbolKind: constructor.kind,
                isEligible: false,
                originalName: "init",
                reasons: ["unsupported symbol kind constructor"]
            ),
            RenameEligibility(
                usr: compilerDerivedProperty.usr,
                symbolName: compilerDerivedProperty.name,
                symbolKind: compilerDerivedProperty.kind,
                isEligible: false,
                originalName: compilerDerivedProperty.name,
                reasons: ["implicit occurrence at \(path):1:1"]
            ),
            RenameEligibility(
                usr: outsideProperty.usr,
                symbolName: outsideProperty.name,
                symbolKind: outsideProperty.kind,
                isEligible: false,
                originalName: outsideProperty.name,
                reasons: ["no declaration or definition occurrence inside selected source roots"]
            ),
        ],
        editConflicts: []
    )

    let cohort = try CoverageAnalyzer.makeBaselineCohort(
        identifier: "fixture@1",
        expectedCount: 5,
        snapshot: snapshot,
        plan: plan,
        selectedSourceFiles: [path]
    )
    let report = try CoverageAnalyzer.makeReport(cohort: cohort, snapshot: snapshot, plan: plan)

    #expect(cohort.population == .explicitSourceSurface)
    #expect(
        cohort.members.map(\.usr)
            == [
                deniedProperty.usr,
                enumCase.usr,
                parameter.usr,
                renamedProperty.usr,
                runtimeProperty.usr,
            ].sorted())
    #expect(cohort.denominator == 5)
    #expect(report.renamed == 1)
    #expect(report.rejected == 4)
    #expect(report.bySymbolKind.first { $0.kind == "parameter" }?.denominator == 1)
    #expect(report.bySymbolKind.first { $0.kind == "parameter" }?.renamed == 0)
    #expect(report.bySymbolKind.first { $0.kind == "enumConstant" }?.denominator == 1)
    #expect(report.syntheticAccessors.total == 2)
    #expect(report.syntheticAccessors.getters == 1)
    #expect(report.syntheticAccessors.setters == 1)
    #expect(report.syntheticAccessors.derivedRenamed == 1)
    #expect(report.syntheticAccessors.derivedUnchanged == 0)
    #expect(report.syntheticAccessors.unresolvedParent == 1)
    #expect(report.syntheticAccessors.unexpectedlyPlanned == 0)

    do {
        _ = try CoverageAnalyzer.makeBaselineCohort(
            identifier: "fixture@1",
            expectedCount: 6,
            snapshot: snapshot,
            plan: plan,
            selectedSourceFiles: [path]
        )
        Issue.record("Expected fixed denominator validation to fail")
    } catch let error as CoverageReportError {
        #expect(error.localizedDescription.contains("expected 6"))
    }
}
