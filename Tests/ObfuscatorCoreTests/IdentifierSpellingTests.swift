import Foundation
import Testing

@testable import ObfuscatorCore

// MARK: - Identifier spellings

@Test func plannerRenamesCompilerAcceptedContextualIdentifiersAndPreservesSemanticSelf() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ContextualIdentifiers.swift")
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
            "-module-name", "ContextualIdentifiersFixture",
            "-index-store-path", store.path,
            file.path,
            "-o", beforeExecutable.path,
        ]
    )
    _ = try runner.run(executable: beforeExecutable.path, arguments: [])

    let snapshot = try IndexSnapshotReader().read(
        storePath: store,
        databasePath: database,
        sourceRoot: directory
    )
    let cache = try SourceFileCache(paths: [file.path])
    let boxGroup = try #require(
        snapshot.occurrenceGroups.first {
            $0.symbol.kind == "struct" && $0.symbol.name == "ContextualBox"
        })
    #expect(
        boxGroup.occurrences.contains { occurrence in
            guard let source = cache.file(for: occurrence.path),
                let token = source.identifierToken(
                    line: occurrence.line,
                    utf8Column: occurrence.utf8Column
                )
            else {
                return false
            }
            return token.name == "Self"
        })
    let accessorUSRs = Set(
        snapshot.occurrenceGroups.filter {
            RenameEligibilityAnalyzer.isAccessorOccurrenceGroup($0)
        }.map(\.usr))
    #expect(!accessorUSRs.isEmpty)
    let subscriptUSRs = Set(
        snapshot.occurrenceGroups.filter {
            $0.symbol.name.hasPrefix("subscript(")
        }.map(\.usr))
    #expect(!subscriptUSRs.isEmpty)

    var planner = RenamePlanner(
        analyzer: RenameEligibilityAnalyzer(sourceRoot: directory),
        generator: ObfuscatedNameGenerator(prefix: "Ctx")
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let boxEntry = try #require(plan.renames.first { $0.usr == boxGroup.usr })
    let getEntry = try #require(
        plan.renames.first {
            $0.kind == "instanceMethod" && $0.oldName == "get"
        })
    let setEntry = try #require(
        plan.renames.first {
            $0.kind == "instanceMethod" && $0.oldName == "set"
        })
    let prefixEntry = try #require(
        plan.renames.first {
            $0.kind == "instanceProperty" && $0.oldName == "prefix"
        })
    #expect(boxEntry.edits.allSatisfy { $0.oldName == "ContextualBox" })
    #expect(getEntry.edits.allSatisfy { $0.oldName == "get" })
    #expect(setEntry.edits.allSatisfy { $0.oldName == "set" })
    #expect(prefixEntry.edits.allSatisfy { $0.oldName == "prefix" })
    #expect(Set(plan.renames.map(\.usr)).isDisjoint(with: accessorUSRs))
    #expect(Set(plan.renames.map(\.usr)).isDisjoint(with: subscriptUSRs))
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("Self("))
    #expect(patched.contains("didSet"))
    #expect(patched.contains("subscript"))
    #expect(!patched.contains("ContextualBox"))
    #expect(!patched.contains("func get"))
    #expect(!patched.contains("func set"))

    let afterExecutable = directory.appendingPathComponent("After")
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", afterExecutable.path]
    )
    _ = try runner.run(executable: afterExecutable.path, arguments: [])
}

@Test func plannerRenamesCompilerAcceptedBacktickedDeclarationsAndReferences() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("BacktickedIdentifiers.swift")
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
            "-module-name", "BacktickedIdentifiersFixture",
            "-index-store-path", store.path,
            file.path,
            "-o", beforeExecutable.path,
        ]
    )
    _ = try runner.run(executable: beforeExecutable.path, arguments: [])

    let snapshot = try IndexSnapshotReader().read(
        storePath: store,
        databasePath: database,
        sourceRoot: directory
    )
    let cache = try SourceFileCache(paths: [file.path])
    var planner = RenamePlanner(
        analyzer: RenameEligibilityAnalyzer(sourceRoot: directory),
        generator: ObfuscatedNameGenerator(prefix: "Esc")
    )
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)
    let typeEntry = try #require(
        plan.renames.first {
            $0.kind == "struct" && $0.oldName == "Type"
        })
    let defaultEntry = try #require(
        plan.renames.first {
            $0.kind == "staticProperty" && $0.oldName == "default"
        })
    let doEntry = try #require(
        plan.renames.first {
            $0.kind == "instanceMethod" && $0.oldName == "do"
        })
    #expect(typeEntry.edits.count == 2)
    #expect(defaultEntry.edits.count == 2)
    #expect(doEntry.edits.count == 2)
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(patched.contains("struct `\(typeEntry.newName)`"))
    #expect(patched.contains("static let `\(defaultEntry.newName)`"))
    #expect(patched.contains("func `\(doEntry.newName)`"))
    #expect(!patched.contains("`Type`"))
    #expect(!patched.contains("`default`"))
    #expect(!patched.contains("`do`"))

    let afterExecutable = directory.appendingPathComponent("After")
    _ = try runner.run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", file.path, "-o", afterExecutable.path]
    )
    _ = try runner.run(executable: afterExecutable.path, arguments: [])
}

@Test func enumCasePlannerRenamesContextualAndBacktickedCaseTokens() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("ContextualEnum.swift")
    try copyFixture(to: file)

    let contextual = testSymbol("s:contextual", "ContextualToken", .enum)
    let open = testSymbol("s:contextual-open", "open", .enumConstant)
    let get = testSymbol("s:contextual-get", "get", .enumConstant)
    let left = testSymbol("s:contextual-left", "left", .enumConstant)
    let escaped = testSymbol("s:escaped", "EscapedToken", .enum)
    let publicCase = testSymbol("s:escaped-public", "public", .enumConstant)
    let snapshot = IndexSnapshot(
        sourceFiles: [file.path],
        symbols: [contextual, open, get, left, escaped, publicCase],
        occurrences: [
            testOccurrence(
                contextual,
                path: file.path,
                line: 1,
                token: "ContextualToken",
                roles: [.definition]
            ),
            testOccurrence(
                open,
                path: file.path,
                line: 2,
                token: "open",
                roles: [.definition],
                relations: [childOf(contextual)]
            ),
            testOccurrence(
                get,
                path: file.path,
                line: 3,
                token: "get",
                roles: [.definition],
                relations: [childOf(contextual)]
            ),
            testOccurrence(
                left,
                path: file.path,
                line: 4,
                token: "left",
                roles: [.definition],
                relations: [childOf(contextual)]
            ),
            testOccurrence(
                contextual,
                path: file.path,
                line: 6,
                token: "ContextualToken",
                roles: [.reference]
            ),
            testOccurrence(open, path: file.path, line: 6, token: "open", roles: [.reference]),
            testOccurrence(
                contextual,
                path: file.path,
                line: 7,
                token: "ContextualToken",
                roles: [.reference]
            ),
            testOccurrence(get, path: file.path, line: 7, token: "get", roles: [.reference]),
            testOccurrence(
                contextual,
                path: file.path,
                line: 8,
                token: "ContextualToken",
                roles: [.reference]
            ),
            testOccurrence(left, path: file.path, line: 8, token: "left", roles: [.reference]),
            testOccurrence(
                escaped,
                path: file.path,
                line: 9,
                token: "EscapedToken",
                roles: [.definition]
            ),
            testOccurrence(
                publicCase,
                path: file.path,
                line: 10,
                token: "public",
                roles: [.definition],
                relations: [childOf(escaped)]
            ),
            testOccurrence(
                escaped,
                path: file.path,
                line: 12,
                token: "EscapedToken",
                roles: [.reference]
            ),
            testOccurrence(
                publicCase,
                path: file.path,
                line: 12,
                token: "public",
                roles: [.reference]
            ),
        ]
    )
    let cache = try SourceFileCache(paths: [file.path])
    var planner = RenamePlanner(analyzer: RenameEligibilityAnalyzer(sourceRoot: directory))
    let plan = planner.makePlan(snapshot: snapshot, sourceCache: cache)

    let contextualMember = try #require(
        plan.enumCaseSyntaxReport.owners.first {
            $0.ownerUSR == contextual.usr
        })
    let escapedMember = try #require(
        plan.enumCaseSyntaxReport.owners.first {
            $0.ownerUSR == escaped.usr
        })
    #expect(contextualMember.blockers.isEmpty)
    #expect(escapedMember.blockers.isEmpty)
    let expectedUSRs = Set([open.usr, get.usr, left.usr, publicCase.usr])
    #expect(expectedUSRs.isSubset(of: Set(plan.renames.map(\.usr))))
    let escapedEntry = try #require(plan.renames.first { $0.usr == escaped.usr })
    let publicEntry = try #require(plan.renames.first { $0.usr == publicCase.usr })
    #expect(publicEntry.edits.count == 2)
    #expect(plan.editConflicts.isEmpty)

    try SourcePatcher().apply(plan.edits)
    let patched = try String(contentsOf: file, encoding: .utf8)
    #expect(!patched.contains("case open"))
    #expect(!patched.contains("case get"))
    #expect(!patched.contains("case left"))
    #expect(patched.contains("case `\(publicEntry.newName)`"))
    #expect(patched.contains("\(escapedEntry.newName).\(publicEntry.newName)"))
    #expect(!patched.contains("public"))
    _ = try CommandRunner().run(
        executable: "/usr/bin/xcrun",
        arguments: ["swiftc", "-typecheck", file.path]
    )
}
