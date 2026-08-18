import Foundation
import ObfuscatorCore

enum CLIError: LocalizedError {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        }
    }
}

enum Command: String, Codable {
    case dump
    case dryRun = "dry-run"
    case apply
}

enum RunStatus: String, Codable {
    case running
    case success
    case failure
}

enum RunPhase: String, Codable {
    case parseArguments = "parse-arguments"
    case prepare
    case validateIndexSources = "validate-index-sources"
    case buildOriginal = "build-original"
    case loadRenamePlan = "load-rename-plan"
    case loadIndexSnapshot = "load-index-snapshot"
    case readIndex = "read-index"
    case saveIndexSnapshot = "save-index-snapshot"
    case dumpIndex = "dump-index"
    case planRenames = "plan-renames"
    case apply
    case verifyBuild = "verify-build"
    case completed
}

enum OutputVerbosity: Int {
    case quiet = 0
    case normal = 1
    case verbose = 2
}

struct CLIOptions {
    var command: Command = .dryRun
    var projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var sourceRootPaths: [String] = []
    var outputDirectory: URL?
    var obfuscatedCodeOutputPath: String?
    var scheme: String?
    var configuration: String?
    var destination: String? = "platform=macOS"
    var derivedDataPath: URL?
    var databasePath: URL?
    var mappingPath: URL?
    var coverageCohortPath: URL?
    var createCoverageCohortPath: URL?
    var coverageCohortIdentifier: String?
    var coverageExpectedCount: Int?
    var dumpIndex = false
    var verifyBuild = false
    var reuseIndex = false
    var compactReport = false
    var extraXcodebuildArguments: [String] = []
    var verbosity: OutputVerbosity = .normal
    var printSummaryJSON = false
}

struct RunSummary: Codable {
    var status: RunStatus = .running
    var command: Command
    var phase: RunPhase = .parseArguments
    var projectRoot: String?
    var outputDirectory: String?
    var obfuscatedCodeOutput: String?
    var sourceRoots: [SourceRootSummary] = []
    var build: BuildSummary?
    var counters = RunCounters()
    var parameterFacts: ParameterFactsSummary?
    var parameterSyntaxFacts: ParameterSyntaxFactsSummary?
    var parameterCallSiteSyntaxFacts: ParameterCallSiteSyntaxFactsSummary?
    var parameterCallArgumentBindingFacts: ParameterCallArgumentBindingFactsSummary?
    var parameterCallableReferenceSyntaxFacts: ParameterCallableReferenceSyntaxFactsSummary?
    var parameterCallableReferenceBindingFacts: ParameterCallableReferenceBindingFactsSummary?
    var parameterExternalLabelComponentFacts: ParameterExternalLabelComponentFactsSummary?
    var parameterExternalLabelRenameOutcome: ParameterExternalLabelRenameOutcomeSummary?
    var parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary?
    var enumCaseComponentFacts: EnumCaseComponentFactsSummary?
    var compilerRawValueFacts: CompilerRawValueFactsSummary?
    var enumCaseSyntaxFacts: EnumCaseSyntaxFactsSummary?
    var genericParameterSyntaxFacts: GenericParameterSyntaxFactsSummary?
    var typealiasSyntaxFacts: TypealiasSyntaxFactsSummary?
    var artifacts = RunArtifacts()
    var logs: [String] = []
    var error: RunErrorSummary?
}

struct SourceRootSummary: Codable {
    var path: String
    var outputPath: String?
}

struct BuildSummary: Codable {
    var scheme: String
    var derivedDataPath: String
    var indexStorePath: String
}

struct RunCounters: Codable {
    var sourceRoots: Int?
    var indexedSymbols: Int?
    var indexedOccurrences: Int?
    var selectedSourceFiles: Int?
    var plannedSymbols: Int?
    var plannedReplacements: Int?
    var deniedSymbols: Int?
    var conflicts: Int?
    var appliedReplacements: Int?
    var writtenSourceFiles: Int?
    var cohortDenominator: Int?
    var cohortRenamed: Int?
    var cohortDenied: Int?
    var cohortMissingFromIndex: Int?
    var cohortUnclassified: Int?
    var cohortCoveragePercent: Double?
}

struct RunArtifacts: Codable {
    var runSummary: String?
    var runLog: String?
    var indexDump: String?
    var dryRunReport: String?
    var mapping: String?
    var indexSourceManifest: String?
    var indexSnapshotCache: String?
    var renamePlanCache: String?
    var coverageCohort: String?
    var coverageReport: String?
}

struct RunErrorSummary: Codable {
    var message: String
    var commandLine: String?
    var exitCode: Int32?
    var stdoutLogPath: String?
    var stderrLogPath: String?
    var outputTail: String?
}

struct RunPaths {
    let outputDirectory: URL
    let obfuscatedCodeOutputDirectory: URL?
    let excludedSourceRoots: [URL]
    let derivedDataPath: URL
    let indexDatabasePath: URL
    let mappingPath: URL
    let existingCoverageCohortPath: URL?
    let newCoverageCohortPath: URL?
    let indexSourceManifestPath: URL
    let indexSnapshotCachePath: URL
    let renamePlanCachePath: URL
    let selectedSourceRoots: [URL]
}

struct IndexedBuild {
    let scheme: String
    let indexStorePath: URL
}

struct PreparedPlan {
    let plan: RenamePlan
    let mappingStore: MappingStore
    let selectedSourceFiles: [String]
    let snapshotForCoverage: IndexSnapshot?
}

enum PlanPreparation {
    case dumpOnly
    case ready(PreparedPlan)
}
