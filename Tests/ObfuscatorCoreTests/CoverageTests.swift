import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Coverage

@Test func coverageCohortUsesExplicitSourceSurfaceIndependentOfRenameEligibility() throws {
    let path = "/tmp/CoverageSample.swift"
    let outsidePath = "/tmp/OutsideSelection.swift"
    let renamedProperty = SymbolRecord(
        usr: "usr-renamed-property",
        name: "renamedValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let deniedProperty = SymbolRecord(
        usr: "usr-denied-property",
        name: "storedValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let getter = SymbolRecord(
        usr: "usr-getter",
        name: "getter:renamedValue",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let setter = SymbolRecord(
        usr: "usr-setter",
        name: "setter:storedValue",
        kind: "instanceMethod",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let parameter = SymbolRecord(
        usr: "usr-parameter",
        name: "value",
        kind: "parameter",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let enumCase = SymbolRecord(
        usr: "usr-enum-case",
        name: "ready",
        kind: "enumConstant",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let runtimeProperty = SymbolRecord(
        usr: "c:objc-runtime-property",
        name: "runtimeValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let constructor = SymbolRecord(
        usr: "usr-constructor",
        name: "init(value:)",
        kind: "constructor",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let compilerDerivedProperty = SymbolRecord(
        usr: "usr-compiler-derived-property",
        name: "$value",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let outsideProperty = SymbolRecord(
        usr: "usr-outside-property",
        name: "outsideValue",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )

    func occurrence(
        _ symbol: SymbolRecord,
        path occurrencePath: String? = nil,
        roles: [String] = ["declaration"],
        relation: RelationRecord? = nil
    ) -> OccurrenceRecord {
        OccurrenceRecord(
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
                relation: RelationRecord(
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
        entries: [
            RenamePlanEntry(
                usr: renamedProperty.usr,
                kind: renamedProperty.kind,
                oldName: renamedProperty.name,
                newName: "oa",
                replacements: []
            )
        ],
        denied: [
            SafetyDecision(
                usr: deniedProperty.usr,
                symbolName: deniedProperty.name,
                kind: deniedProperty.kind,
                allowed: false,
                oldName: deniedProperty.name,
                reasons: [
                    "stored property declarations require memberwise initializer label support",
                    "implicit occurrence at \(path):1:1",
                ]
            ),
            SafetyDecision(
                usr: getter.usr,
                symbolName: getter.name,
                kind: getter.kind,
                allowed: false,
                oldName: nil,
                reasons: ["implicit occurrence at \(path):1:1"]
            ),
            SafetyDecision(
                usr: setter.usr,
                symbolName: setter.name,
                kind: setter.kind,
                allowed: false,
                oldName: nil,
                reasons: ["implicit occurrence at \(path):1:1"]
            ),
            SafetyDecision(
                usr: parameter.usr,
                symbolName: parameter.name,
                kind: parameter.kind,
                allowed: false,
                oldName: parameter.name,
                reasons: ["unsupported symbol kind parameter"]
            ),
            SafetyDecision(
                usr: enumCase.usr,
                symbolName: enumCase.name,
                kind: enumCase.kind,
                allowed: false,
                oldName: enumCase.name,
                reasons: ["unsupported symbol kind enumConstant"]
            ),
            SafetyDecision(
                usr: runtimeProperty.usr,
                symbolName: runtimeProperty.name,
                kind: runtimeProperty.kind,
                allowed: false,
                oldName: runtimeProperty.name,
                reasons: ["Objective-C-compatible USR requires a stable runtime name"]
            ),
            SafetyDecision(
                usr: constructor.usr,
                symbolName: constructor.name,
                kind: constructor.kind,
                allowed: false,
                oldName: "init",
                reasons: ["unsupported symbol kind constructor"]
            ),
            SafetyDecision(
                usr: compilerDerivedProperty.usr,
                symbolName: compilerDerivedProperty.name,
                kind: compilerDerivedProperty.kind,
                allowed: false,
                oldName: compilerDerivedProperty.name,
                reasons: ["implicit occurrence at \(path):1:1"]
            ),
            SafetyDecision(
                usr: outsideProperty.usr,
                symbolName: outsideProperty.name,
                kind: outsideProperty.kind,
                allowed: false,
                oldName: outsideProperty.name,
                reasons: ["no declaration or definition occurrence inside selected source roots"]
            ),
        ],
        conflicts: []
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
    #expect(report.denied == 4)
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
