import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Serialization and generated names

@Test func safetyAnalyzerAllowsStoredPropertiesBecauseMemberwiseLabelsAreIndexedByPropertyUSR() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("Sample.swift")
    let line = "struct Sample { let count: Int }"
    try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    let cache = try SourceFileCache(paths: [file.path])

    let symbol = SymbolRecord(
        usr: "usr-count",
        name: "count",
        kind: "instanceProperty",
        language: "swift",
        propertiesRaw: 0,
        properties: "[]"
    )
    let occurrence = OccurrenceRecord(
        symbol: symbol,
        path: file.path,
        line: 1,
        utf8Column: utf8Column(of: "count", in: line),
        moduleName: "Sample",
        isSystem: false,
        rolesRaw: 1,
        roles: ["declaration"],
        rolesDescription: "decl",
        symbolProvider: "swift",
        relations: []
    )

    let decision = SafetyAnalyzer(sourceRoot: directory).analyze(
        group: USROccurrenceGroup(usr: symbol.usr, symbol: symbol, occurrences: [occurrence]),
        sourceCache: cache
    )

    #expect(decision.allowed)
    #expect(!decision.reasons.contains { $0.contains("memberwise initializer") })
}

@Test func renamePlannerPreservesMemberwiseLabelsExplicitInitializerLabelsAndCodableKeys() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixture =
        repositoryRoot
        .appendingPathComponent("Fixtures/StoredPropertySafety/main.swift")
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("main.swift")
    try FileManager.default.copyItem(at: fixture, to: sourceURL)
    let sourceText = try String(contentsOf: sourceURL, encoding: .utf8)
    let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let cache = try SourceFileCache(paths: [sourceURL.path])

    func occurrence(
        _ symbol: SymbolRecord,
        line: Int,
        token: String,
        roles: [String],
        relations: [RelationRecord] = []
    ) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: sourceURL.path,
            line: line,
            utf8Column: utf8Column(of: token, in: lines[line - 1]),
            moduleName: "StoredPropertySafety",
            isSystem: false,
            rolesRaw: 0,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relations
        )
    }

    let envelope = testSymbol("s:fixture-envelope", "Envelope", .struct)
    let payload = testSymbol("s:fixture-payload", "MemberwisePayload", .struct)
    let explicitPayload = testSymbol("s:fixture-explicit", "ExplicitPayload", .struct)
    let serverName = testSymbol("s:fixture-server-name", "serverName", .instanceProperty)
    let retryCount = testSymbol("s:fixture-retry-count", "retryCount", .instanceProperty)
    let diagnosticText = testSymbol("s:fixture-diagnostic-text", "diagnosticText", .instanceProperty)
    let storedValue = testSymbol("s:fixture-stored-value", "storedValue", .instanceProperty)
    let localValue = testSymbol("s:fixture-local-value", "localValue", .parameter)
    let serverNameGetter = testSymbol("s:fixture-server-name-getter", "getter:serverName", .instanceMethod)
    let retryCountGetter = testSymbol("s:fixture-retry-count-getter", "getter:retryCount", .instanceMethod)
    let diagnosticTextGetter = testSymbol("s:fixture-diagnostic-text-getter", "getter:diagnosticText", .instanceMethod)
    let storedValueGetter = testSymbol("s:fixture-stored-value-getter", "getter:storedValue", .instanceMethod)
    let wrapperOwner = testSymbol("s:fixture-wrapper-owner", "WrapperOwner", .struct)
    let wrappedNumber = testSymbol("s:fixture-wrapped-number", "wrappedNumber", .instanceProperty)
    let wrappedNumberGetter = testSymbol("s:fixture-wrapped-number-getter", "getter:wrappedNumber", .instanceMethod)
    let projectedWrappedNumber = testSymbol(
        "s:fixture-projected-wrapped-number",
        "$wrappedNumber",
        .instanceProperty
    )
    let decodable = testSymbol("s:Se", "Decodable", .protocol)
    let encodable = testSymbol("s:SE", "Encodable", .protocol)

    var occurrences: [OccurrenceRecord] = [
        occurrence(envelope, line: 3, token: "Envelope", roles: ["definition", "canonical"]),
        occurrence(
            payload,
            line: 4,
            token: "MemberwisePayload",
            roles: ["definition", "childOf", "canonical"],
            relations: [testRelation(envelope, [.childOf])]
        ),
        occurrence(explicitPayload, line: 14, token: "ExplicitPayload", roles: ["definition", "canonical"]),
        occurrence(
            serverName,
            line: 5,
            token: "serverName",
            roles: ["definition", "childOf", "canonical"],
            relations: [testRelation(payload, [.childOf])]
        ),
        occurrence(
            retryCount,
            line: 6,
            token: "retryCount",
            roles: ["definition", "childOf", "canonical"],
            relations: [testRelation(payload, [.childOf])]
        ),
        occurrence(
            diagnosticText,
            line: 8,
            token: "diagnosticText",
            roles: ["definition", "childOf", "canonical"],
            relations: [testRelation(payload, [.childOf])]
        ),
        occurrence(
            storedValue,
            line: 15,
            token: "storedValue",
            roles: ["definition", "childOf", "canonical"],
            relations: [testRelation(explicitPayload, [.childOf])]
        ),
        occurrence(
            serverNameGetter,
            line: 5,
            token: "serverName",
            roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
            relations: [testRelation(serverName, [.childOf, .accessorOf])]
        ),
        occurrence(
            retryCountGetter,
            line: 6,
            token: "retryCount",
            roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
            relations: [testRelation(retryCount, [.childOf, .accessorOf])]
        ),
        occurrence(
            diagnosticTextGetter,
            line: 8,
            token: "diagnosticText",
            roles: ["definition", "childOf", "accessorOf", "canonical"],
            relations: [testRelation(diagnosticText, [.childOf, .accessorOf])]
        ),
        occurrence(
            storedValueGetter,
            line: 15,
            token: "storedValue",
            roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
            relations: [testRelation(storedValue, [.childOf, .accessorOf])]
        ),
        occurrence(
            decodable,
            line: 4,
            token: "Codable",
            roles: ["reference", "implicit", "baseOf"],
            relations: [testRelation(payload, [.baseOf])]
        ),
        occurrence(
            encodable,
            line: 4,
            token: "Codable",
            roles: ["reference", "implicit", "baseOf"],
            relations: [testRelation(payload, [.baseOf])]
        ),
        occurrence(wrapperOwner, line: 41, token: "WrapperOwner", roles: ["definition", "canonical"]),
        occurrence(
            wrappedNumber,
            line: 42,
            token: "wrappedNumber",
            roles: ["definition", "childOf", "canonical"],
            relations: [testRelation(wrapperOwner, [.childOf])]
        ),
        occurrence(
            wrappedNumberGetter,
            line: 42,
            token: "wrappedNumber",
            roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
            relations: [testRelation(wrappedNumber, [.childOf, .accessorOf])]
        ),
        occurrence(
            projectedWrappedNumber,
            line: 42,
            token: "FixtureBox",
            roles: ["definition", "implicit", "childOf", "canonical"],
            relations: [testRelation(wrapperOwner, [.childOf])]
        ),
    ]

    occurrences.append(contentsOf: [
        occurrence(envelope, line: 22, token: "Envelope", roles: ["reference"]),
        occurrence(envelope, line: 27, token: "Envelope", roles: ["reference"]),
        occurrence(payload, line: 22, token: "MemberwisePayload", roles: ["reference", "call"]),
        occurrence(payload, line: 27, token: "MemberwisePayload", roles: ["reference"]),
        occurrence(explicitPayload, line: 32, token: "ExplicitPayload", roles: ["reference", "call"]),
        occurrence(serverName, line: 9, token: "serverName", roles: ["reference", "read"]),
        occurrence(serverName, line: 22, token: "serverName", roles: ["reference"]),
        occurrence(serverName, line: 28, token: "serverName", roles: ["reference", "read"]),
        occurrence(retryCount, line: 9, token: "retryCount", roles: ["reference", "read"]),
        occurrence(retryCount, line: 22, token: "retryCount", roles: ["reference"]),
        occurrence(retryCount, line: 29, token: "retryCount", roles: ["reference", "read"]),
        occurrence(diagnosticText, line: 30, token: "diagnosticText", roles: ["reference", "read"]),
        occurrence(storedValue, line: 18, token: "storedValue", roles: ["reference", "write"]),
        occurrence(storedValue, line: 33, token: "storedValue", roles: ["reference", "read"]),
        occurrence(localValue, line: 17, token: "localValue", roles: ["definition", "childOf"]),
        occurrence(localValue, line: 18, token: "localValue", roles: ["reference", "read"]),
        occurrence(localValue, line: 32, token: "externalLabel", roles: ["reference"]),
        occurrence(wrapperOwner, line: 46, token: "WrapperOwner", roles: ["reference", "call"]),
        occurrence(wrappedNumber, line: 47, token: "wrappedNumber", roles: ["reference", "read"]),
        occurrence(
            projectedWrappedNumber,
            line: 43,
            token: "$wrappedNumber",
            roles: ["reference", "read"]
        ),
    ])

    let symbols = [
        envelope, payload, explicitPayload, serverName, retryCount, diagnosticText, storedValue,
        localValue, serverNameGetter, retryCountGetter, diagnosticTextGetter, storedValueGetter,
        wrapperOwner, wrappedNumber, wrappedNumberGetter, projectedWrappedNumber, decodable, encodable,
    ]
    let snapshot = IndexSnapshot(
        sourceFiles: [sourceURL.path],
        symbols: symbols,
        occurrences: occurrences
    )
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])
    #expect(
        facts.storedPropertyUSRs == [
            serverName.usr, retryCount.usr, storedValue.usr, wrappedNumber.usr,
        ])
    #expect(!facts.storedPropertyUSRs.contains(diagnosticText.usr))
    #expect(facts.serializationSensitiveOwnerUSRs == [payload.usr])

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.conflicts.isEmpty)
    #expect(plan.supportReplacements.count == 2)
    #expect(plan.entries.contains { $0.usr == serverName.usr })
    #expect(plan.entries.contains { $0.usr == retryCount.usr })
    #expect(plan.entries.contains { $0.usr == diagnosticText.usr })
    #expect(plan.entries.contains { $0.usr == storedValue.usr })
    #expect(plan.entries.contains { $0.usr == wrappedNumber.usr })
    #expect(!plan.entries.contains { $0.usr == localValue.usr })

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: sourceURL, encoding: .utf8)
    let serverNameEntry = try #require(plan.entries.first { $0.usr == serverName.usr })
    let retryCountEntry = try #require(plan.entries.first { $0.usr == retryCount.usr })
    #expect(patched.contains("case \(serverNameEntry.newName) = \"serverName\""))
    #expect(patched.contains("case \(retryCountEntry.newName) = \"retryCount\""))
    #expect(!patched.contains("case diagnosticText"))
    #expect(patched.contains("externalLabel: 4"))
    #expect(patched.contains("externalLabel localValue"))
    let wrappedNumberEntry = try #require(plan.entries.first { $0.usr == wrappedNumber.usr })
    #expect(patched.contains("$\(wrappedNumberEntry.newName)"))
    #expect(!patched.contains("$wrappedNumber"))

    let executable = directory.appendingPathComponent("StoredPropertySafety")
    let runner = CommandRunner(logDirectory: directory.appendingPathComponent("logs", isDirectory: true))
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", sourceURL.path, "-o", executable.path]
    )
    _ = try runner.run(executable: executable.path, arguments: [])
}

@Test func renamePlannerDeniesSerializedPropertiesWithExistingCustomCodingKeys() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("CustomCodingKeys.swift")
    try copyFixture(to: file)
    let lines = fixtureLines(at: file)
    let cache = try SourceFileCache(paths: [file.path])

    func occurrence(
        _ symbol: SymbolRecord,
        line: Int,
        token: String,
        roles: [String],
        relations: [RelationRecord] = []
    ) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: file.path,
            line: line,
            utf8Column: utf8Column(of: token, in: lines[line - 1]),
            moduleName: "CustomCodingKeys",
            isSystem: false,
            rolesRaw: 0,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relations
        )
    }

    let owner = testSymbol("s:custom-schema", "Schema", .struct)
    let property = testSymbol("s:custom-schema-value", "value", .instanceProperty)
    let getter = testSymbol("s:custom-schema-value-getter", "getter:value", .instanceMethod)
    let codingKeys = testSymbol("s:custom-schema-coding-keys", "CodingKeys", .enum)
    let decodable = testSymbol("s:Se", "Decodable", .protocol)
    let encodable = testSymbol("s:SE", "Encodable", .protocol)
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [owner, property, getter, codingKeys, decodable, encodable],
        occurrences: [
            occurrence(owner, line: 1, token: "Schema", roles: ["definition", "canonical"]),
            occurrence(
                property,
                line: 2,
                token: "value",
                roles: ["definition", "childOf", "canonical"],
                relations: [childOf(owner)]
            ),
            occurrence(
                getter,
                line: 2,
                token: "value",
                roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
                relations: [
                    RelationRecord(
                        usr: property.usr,
                        name: property.name,
                        rolesRaw: 0,
                        roles: ["childOf", "accessorOf"]
                    )
                ]
            ),
            occurrence(
                codingKeys,
                line: 3,
                token: "CodingKeys",
                roles: ["definition", "childOf", "canonical"],
                relations: [childOf(owner)]
            ),
            occurrence(
                decodable,
                line: 1,
                token: "Codable",
                roles: ["reference", "implicit", "baseOf"],
                relations: [baseOf(owner)]
            ),
            occurrence(
                encodable,
                line: 1,
                token: "Codable",
                roles: ["reference", "implicit", "baseOf"],
                relations: [baseOf(owner)]
            ),
        ]
    )
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])
    #expect(facts.explicitCodingKeysOwnerUSRs == [owner.usr])

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.supportReplacements.isEmpty)
    #expect(!plan.entries.contains { $0.usr == property.usr })
    #expect(
        plan.denied.contains { decision in
            decision.usr == property.usr
                && decision.reasons.contains("serialized stored property requires explicit key preservation")
        })
}

@Test func explicitCodingKeysPropertiesAndCasesRenameTogetherWhileWireKeysStayStable() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ExplicitCodingKeys.swift")
    try copyFixture(to: file)

    let store = directory.appendingPathComponent("IndexStore", isDirectory: true)
    let database = directory.appendingPathComponent("IndexDatabase", isDirectory: true)
    let beforeExecutable = directory.appendingPathComponent("Before")
    let runner = CommandRunner(
        logDirectory: directory.appendingPathComponent("logs", isDirectory: true)
    )
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: [
            "swiftc",
            "-module-name", "ExplicitCodingKeysFixture",
            "-index-store-path", store.path,
            file.path,
            "-o", beforeExecutable.path,
        ]
    )
    _ = try runner.run(executable: beforeExecutable.path, arguments: [])

    let snapshot = try IndexReader().read(
        storePath: store,
        databasePath: database,
        sourceRoot: directory
    )
    let codingKeysUSR = try #require(
        snapshot.groupsByUSR.first { group in
            group.symbol.kind == "enum" && group.symbol.name == "CodingKeys"
        }
    ).usr
    let payloadUSR = try #require(
        snapshot.groupsByUSR.first { group in
            group.symbol.kind == "struct" && group.symbol.name == "Payload"
        }
    ).usr
    let sourceNames = ["value", "other", "equal"]
    let caseUSRsByName = Dictionary(
        uniqueKeysWithValues: try sourceNames.map { name in
            let usr = try #require(
                snapshot.groupsByUSR.first { group in
                    group.symbol.kind == "enumConstant"
                        && group.symbol.name == name
                        && group.occurrences.contains { occurrence in
                            occurrence.relations.contains { relation in
                                relation.roles.contains("childOf") && relation.usr == codingKeysUSR
                            }
                        }
                }
            ).usr
            return (name, usr)
        })
    let propertyUSRsByName = Dictionary(
        uniqueKeysWithValues: try sourceNames.map { name in
            let usr = try #require(
                snapshot.groupsByUSR.first { group in
                    group.symbol.kind == "instanceProperty"
                        && group.symbol.name == name
                        && group.occurrences.contains { occurrence in
                            !occurrence.roles.contains("implicit")
                                && occurrence.roles.contains("definition")
                                && occurrence.relations.contains { relation in
                                    relation.roles.contains("childOf") && relation.usr == payloadUSR
                                }
                        }
                }
            ).usr
            return (name, usr)
        })

    let cache = try SourceFileCache(paths: [file.path])
    var planner = RenamePlanner(
        analyzer: SafetyAnalyzer(sourceRoot: directory),
        generator: NameGenerator(prefix: "Key")
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(!plan.entries.contains { $0.usr == codingKeysUSR })
    for name in sourceNames {
        let caseEntry = try #require(
            plan.entries.first {
                $0.usr == caseUSRsByName[name]
            })
        let propertyEntry = try #require(
            plan.entries.first {
                $0.usr == propertyUSRsByName[name]
            })
        #expect(caseEntry.oldName == name)
        #expect(propertyEntry.oldName == name)
        #expect(caseEntry.newName == propertyEntry.newName)
    }
    #expect(
        plan.denied.first { $0.usr == codingKeysUSR }?.reasons.contains {
            $0.contains("explicit CodingKeys type name is required")
        } == true)
    let codingCaseComponent = try #require(
        plan.enumCaseSyntaxFacts.components.first {
            $0.ownerUSR == codingKeysUSR
        })
    #expect(codingCaseComponent.blockers.contains(.codingKeyContract))
    let otherCaseUSR = try #require(caseUSRsByName["other"])
    #expect(
        plan.supportReplacements.contains {
            $0.usr == "implicit-raw-value:\(otherCaseUSR)" && $0.newName == " = \"other\""
        })
    #expect(plan.conflicts.isEmpty)

    try SourcePatcher().apply(plan.replacements)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("enum CodingKeys: String, CodingKey"))
    let valueCaseEntry = try #require(
        plan.entries.first {
            $0.usr == caseUSRsByName["value"]
        })
    let otherCaseEntry = try #require(
        plan.entries.first {
            $0.usr == caseUSRsByName["other"]
        })
    let equalCaseEntry = try #require(
        plan.entries.first {
            $0.usr == caseUSRsByName["equal"]
        })
    #expect(patched.contains("case \(valueCaseEntry.newName) = \"wire_value\""))
    #expect(patched.contains("case \(otherCaseEntry.newName) = \"other\""))
    #expect(patched.contains("case \(equalCaseEntry.newName) = \"equal\""))

    let afterExecutable = directory.appendingPathComponent("After")
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", afterExecutable.path]
    )
    _ = try runner.run(executable: afterExecutable.path, arguments: [])
}

@Test func renamePlannerDeniesSerializedPropertiesWithCustomCodableImplementation() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixture =
        repositoryRoot
        .appendingPathComponent("Fixtures/ManualCodableSafety/main.swift")
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("main.swift")
    try FileManager.default.copyItem(at: fixture, to: sourceURL)
    let sourceText = try String(contentsOf: sourceURL, encoding: .utf8)
    let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let cache = try SourceFileCache(paths: [sourceURL.path])

    func occurrence(
        _ symbol: SymbolRecord,
        line: Int,
        token: String,
        roles: [String],
        relations: [RelationRecord] = []
    ) -> OccurrenceRecord {
        OccurrenceRecord(
            symbol: symbol,
            path: sourceURL.path,
            line: line,
            utf8Column: utf8Column(of: token, in: lines[line - 1]),
            moduleName: "ManualCodableSafety",
            isSystem: false,
            rolesRaw: 0,
            roles: roles,
            rolesDescription: roles.joined(separator: ","),
            symbolProvider: "swift",
            relations: relations
        )
    }

    let owner = testSymbol("s:manual-payload", "ManualPayload", .struct)
    let property = testSymbol("s:manual-payload-value", "value", .instanceProperty)
    let getter = testSymbol("s:manual-payload-value-getter", "getter:value", .instanceMethod)
    let customDecoder = testSymbol("s:manual-payload-decoder", "init(from:)", .constructor)
    let decodingRequirement = testSymbol("s:Se4fromxs7Decoder_p_tKcfc", "init(from:)", .constructor)
    let decodable = testSymbol("s:Se", "Decodable", .protocol)
    let encodable = testSymbol("s:SE", "Encodable", .protocol)
    let snapshot = IndexSnapshot(
        sourceFiles: [sourceURL.path],
        symbols: [owner, property, getter, customDecoder, decodingRequirement, decodable, encodable],
        occurrences: [
            occurrence(owner, line: 3, token: "ManualPayload", roles: ["definition", "canonical"]),
            occurrence(owner, line: 12, token: "ManualPayload", roles: ["reference"]),
            occurrence(
                property,
                line: 4,
                token: "value",
                roles: ["definition", "childOf", "canonical"],
                relations: [testRelation(owner, [.childOf])]
            ),
            occurrence(
                property,
                line: 8,
                token: "value",
                roles: ["reference", "write"]
            ),
            occurrence(
                property,
                line: 13,
                token: "value",
                roles: ["reference", "read"]
            ),
            occurrence(
                getter,
                line: 4,
                token: "value",
                roles: ["definition", "implicit", "childOf", "accessorOf", "canonical"],
                relations: [testRelation(property, [.childOf, .accessorOf])]
            ),
            occurrence(
                customDecoder,
                line: 6,
                token: "init",
                roles: ["definition", "childOf", "overrideOf", "canonical"],
                relations: [
                    testRelation(decodingRequirement, [.overrideOf]),
                    testRelation(owner, [.childOf]),
                ]
            ),
            occurrence(
                decodable,
                line: 3,
                token: "Codable",
                roles: ["reference", "implicit", "baseOf"],
                relations: [testRelation(owner, [.baseOf])]
            ),
            occurrence(
                encodable,
                line: 3,
                token: "Codable",
                roles: ["reference", "implicit", "baseOf"],
                relations: [testRelation(owner, [.baseOf])]
            ),
        ]
    )
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])
    #expect(facts.customSerializationImplementationOwnerUSRs == [owner.usr])

    var planner = RenamePlanner(analyzer: SafetyAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    #expect(plan.supportReplacements.isEmpty)
    #expect(!plan.entries.contains { $0.usr == property.usr })
    #expect(
        plan.denied.contains { decision in
            decision.usr == property.usr
                && decision.reasons.contains("serialized stored property requires explicit key preservation")
        })

    try SourcePatcher().apply(plan.replacements)
    let executable = directory.appendingPathComponent("ManualCodableSafety")
    let runner = CommandRunner(logDirectory: directory.appendingPathComponent("logs", isDirectory: true))
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", sourceURL.path, "-o", executable.path]
    )
    _ = try runner.run(executable: executable.path, arguments: [])
}

@Test func indexedSemanticFactsRecoverMissingCodableWitnessRelationsFromCompilerSignatureFacts() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("DirectionAwareCodable.swift")
    try copyFixture(to: file)

    let linked = testSymbol("s:direction-linked", "Linked", .struct)
    let unlinked = testSymbol("s:direction-unlinked", "Unlinked", .struct)
    let partial = testSymbol("s:direction-partial", "Partial", .struct)
    let linkedDecoder = testSymbol("s:direction-linked-decoder", "init(from:)", .constructor)
    let unlinkedDecoder = testSymbol("s:direction-unlinked-decoder", "init(from:)", .constructor)
    let partialDecoder = testSymbol("s:direction-partial-decoder", "init(from:)", .constructor)
    let linkedParameter = testSymbol("s:direction-linked-parameter", "decoder", .parameter)
    let unlinkedParameter = testSymbol("s:direction-unlinked-parameter", "decoder", .parameter)
    let partialParameter = testSymbol("s:direction-partial-parameter", "decoder", .parameter)
    let decodingRequirement = testSymbol(
        "s:Se4fromxs7Decoder_p_tKcfc",
        "init(from:)",
        .constructor
    )
    let decodable = testSymbol("s:Se", "Decodable", .protocol)
    let encodable = testSymbol("s:SE", "Encodable", .protocol)
    let decoder = testSymbol("s:s7DecoderP", "Decoder", .protocol)

    let callableFacts: [(SymbolRecord, SymbolRecord, SymbolRecord, Int, Bool)] = [
        (linkedDecoder, linkedParameter, linked, 2, true),
        (unlinkedDecoder, unlinkedParameter, unlinked, 5, false),
        (partialDecoder, partialParameter, partial, 8, false),
    ]
    var occurrences = [
        testOccurrence(linked, path: file.path, line: 1, token: "Linked", roles: [.definition]),
        testOccurrence(unlinked, path: file.path, line: 4, token: "Unlinked", roles: [.definition]),
        testOccurrence(partial, path: file.path, line: 7, token: "Partial", roles: [.definition]),
        testOccurrence(
            decodable,
            path: file.path,
            line: 1,
            token: "Decodable",
            roles: [.reference, .baseOf],
            relations: [testRelation(linked, [.baseOf])]
        ),
        testOccurrence(
            decodable,
            path: file.path,
            line: 4,
            token: "Decodable",
            roles: [.reference, .baseOf],
            relations: [testRelation(unlinked, [.baseOf])]
        ),
        testOccurrence(
            decodable,
            path: file.path,
            line: 7,
            token: "Codable",
            roles: [.reference, .implicit, .baseOf],
            relations: [testRelation(partial, [.baseOf])]
        ),
        testOccurrence(
            encodable,
            path: file.path,
            line: 7,
            token: "Codable",
            roles: [.reference, .implicit, .baseOf],
            relations: [testRelation(partial, [.baseOf])]
        ),
    ]
    for (callable, parameter, owner, line, hasWitnessRelation) in callableFacts {
        var callableRelations = [testRelation(owner, [.childOf])]
        var callableRoles: [IndexRole] = [.definition, .childOf]
        if hasWitnessRelation {
            callableRelations.append(testRelation(decodingRequirement, [.overrideOf]))
            callableRoles.append(.overrideOf)
        }
        occurrences.append(
            testOccurrence(
                callable,
                path: file.path,
                line: line,
                token: "init",
                roles: callableRoles,
                relations: callableRelations
            ))
        occurrences.append(
            testOccurrence(
                parameter,
                path: file.path,
                line: line,
                token: "decoder",
                roles: [.definition, .childOf],
                relations: [testRelation(callable, [.childOf])]
            ))
        occurrences.append(
            testOccurrence(
                decoder,
                path: file.path,
                line: line,
                token: "Decoder",
                roles: [.reference, .containedBy],
                relations: [testRelation(callable, [.containedBy])]
            ))
    }

    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [
            linked, unlinked, partial,
            linkedDecoder, unlinkedDecoder, partialDecoder,
            linkedParameter, unlinkedParameter, partialParameter,
            decodingRequirement, decodable, encodable, decoder,
        ],
        occurrences: occurrences
    )
    let facts = IndexedSemanticFacts(snapshot: snapshot, obfuscationRoots: [directory])

    #expect(facts.decodingSensitiveOwnerUSRs == [linked.usr, unlinked.usr, partial.usr])
    #expect(facts.encodingSensitiveOwnerUSRs == [partial.usr])
    #expect(
        facts.customDecodingImplementationOwnerUSRs == [
            linked.usr, unlinked.usr, partial.usr,
        ])
    #expect(facts.customEncodingImplementationOwnerUSRs.isEmpty)
    #expect(
        facts.customSerializationImplementationOwnerUSRs == [
            linked.usr, unlinked.usr, partial.usr,
        ])
}
