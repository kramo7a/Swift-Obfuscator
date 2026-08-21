import Foundation
import Testing

@testable import SwiftObfuscator

@Test func helpTextKeepsItsExternalContract() {
    let expected = """
        Usage:
          swift-obfuscator dump [options]
          swift-obfuscator dry-run [options]
          swift-obfuscator apply [options] [--verify-build]

        Options:
          --project PATH             Project, workspace, or SwiftPM package root. Default: current directory.
          --source-root PATH         Source file or directory to obfuscate. Repeatable. Relative paths resolve under --project. Default: --project.
          --source PATH              Alias for --source-root.
          --obfuscated-code-output PATH
                                     Write obfuscated Swift files to PATH instead of patching project sources in-place. Relative paths resolve under --project.
          --output PATH              Artifact directory for logs, reports, DerivedData, IndexDatabase, and mapping. Default: <project>/.obfuscator.
          --scheme NAME              xcodebuild scheme. If omitted, the first listed scheme is used.
          --configuration NAME       xcodebuild configuration.
          --destination SPEC         xcodebuild destination. Default: platform=macOS.
          --no-destination           Do not pass -destination.
          --derived-data PATH        DerivedData path. Default: <output>/DerivedData.
          --database PATH            IndexStoreDB database path. Default: <output>/IndexDatabase.
          --mapping PATH             Mapping JSON path. Default: <output>/mapping.json.
          --coverage-cohort PATH     Compare the current plan with an immutable USR cohort and write coverage-report.json.
          --create-coverage-cohort PATH
                                     Create an immutable baseline cohort, refusing to overwrite an existing file.
          --coverage-cohort-id ID    Stable revision/configuration identifier required when creating a cohort.
          --coverage-expected-count N
                                     Required expected denominator when creating a cohort; generation fails on drift.
          --dump                     Print full symbol/USR/occurrence dump before planning.
          --verify-build             After in-place apply, run xcodebuild again. For external code output, report the initial indexed build status.
          --reuse-index              Skip the initial build/import and reuse the existing IndexStoreDB only after every Swift source matches the saved SHA-256 manifest.
          --compact-report           Omit per-occurrence and per-symbol denial details from dry-run-report.txt while preserving counters and planned rename entries.
          --quiet                    Print only phase-level progress, counters, and artifact paths.
          --verbose                  Print full dry-run and dump reports to stdout. Reports are always saved as artifacts.
          --summary-json, --json     Print only run-summary JSON to stdout. Human output still goes to logs.
          --xcodebuild-arg VALUE     Extra xcodebuild argument. Repeatable.
          --                         Pass the remaining arguments directly to xcodebuild before "build".
        """

    #expect(CLI.helpText == expected)
}

@Test func runSummaryKeepsItsLegacyJSONKeys() throws {
    var summary = RunSummary(command: .dryRun)
    summary.counters.rejectedSymbols = 1
    summary.counters.editConflicts = 2
    summary.counters.cohortRejected = 3
    summary.callableReport = .empty
    summary.parameterSyntaxReport = .empty
    summary.callSiteSyntaxReport = .empty
    summary.callArgumentBindingReport = .empty
    summary.callableReferenceSyntaxReport = .empty
    summary.callableReferenceBindingReport = .empty
    summary.externalLabelReport = .empty
    summary.externalLabelRenameReport = .empty
    summary.localBindingRenameReport = .empty
    summary.enumCaseSemanticsReport = .empty
    summary.enumRawValueReport = .empty
    summary.enumCaseSyntaxReport = .empty
    summary.genericParameterReport = .empty
    summary.typeAliasSyntaxReport = .empty
    summary.failure = RunSummary.Failure(message: "failure")

    let object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any]
    )
    #expect(Set(object.keys) == [
        "artifacts",
        "command",
        "compilerRawValueFacts",
        "counters",
        "enumCaseComponentFacts",
        "enumCaseSyntaxFacts",
        "error",
        "genericParameterSyntaxFacts",
        "logs",
        "parameterCallArgumentBindingFacts",
        "parameterCallSiteSyntaxFacts",
        "parameterCallableReferenceBindingFacts",
        "parameterCallableReferenceSyntaxFacts",
        "parameterExternalLabelComponentFacts",
        "parameterExternalLabelRenameOutcome",
        "parameterFacts",
        "parameterLocalBindingOutcome",
        "parameterSyntaxFacts",
        "phase",
        "sourceRoots",
        "status",
        "typealiasSyntaxFacts",
    ])

    let counters = try #require(object["counters"] as? [String: Any])
    #expect(Set(counters.keys) == ["cohortDenied", "conflicts", "deniedSymbols"])
}
