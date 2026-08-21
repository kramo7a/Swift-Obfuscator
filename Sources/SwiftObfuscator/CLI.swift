import Foundation
import ObfuscatorCore

enum CLI {}

extension CLI {
    enum Error: LocalizedError {
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

    enum Verbosity: Int {
        case quiet = 0
        case normal = 1
        case verbose = 2
    }

    struct Options {
        var command: CLI.Command = .dryRun
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
        var isIndexDumpEnabled = false
        var isBuildVerificationEnabled = false
        var isIndexReuseEnabled = false
        var isCompactReportEnabled = false
        var extraXcodebuildArguments: [String] = []
        var verbosity: CLI.Verbosity = .normal
        var isSummaryJSONEnabled = false
    }
}

struct RunSummary: Codable {
    enum Status: String, Codable {
        case running
        case success
        case failure
    }

    enum Phase: String, Codable {
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

    struct SourceRoot: Codable {
        var path: String
        var outputPath: String?
    }

    struct Build: Codable {
        var scheme: String
        var derivedDataPath: String
        var indexStorePath: String
    }

    struct Counters: Codable {
        var sourceRoots: Int?
        var indexedSymbols: Int?
        var indexedOccurrences: Int?
        var selectedSourceFiles: Int?
        var plannedSymbols: Int?
        var plannedReplacements: Int?
        var rejectedSymbols: Int?
        var editConflicts: Int?
        var appliedReplacements: Int?
        var writtenSourceFiles: Int?
        var cohortDenominator: Int?
        var cohortRenamed: Int?
        var cohortRejected: Int?
        var cohortMissingFromIndex: Int?
        var cohortUnclassified: Int?
        var cohortCoveragePercent: Double?

        private enum CodingKeys: String, CodingKey {
            case sourceRoots
            case indexedSymbols
            case indexedOccurrences
            case selectedSourceFiles
            case plannedSymbols
            case plannedReplacements
            case rejectedSymbols = "deniedSymbols"
            case editConflicts = "conflicts"
            case appliedReplacements
            case writtenSourceFiles
            case cohortDenominator
            case cohortRenamed
            case cohortRejected = "cohortDenied"
            case cohortMissingFromIndex
            case cohortUnclassified
            case cohortCoveragePercent
        }
    }

    struct Artifacts: Codable {
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

    struct Failure: Codable {
        var message: String
        var commandLine: String?
        var exitCode: Int32?
        var stdoutLogPath: String?
        var stderrLogPath: String?
        var outputTail: String?
    }

    var status: RunSummary.Status = .running
    var command: CLI.Command
    var phase: RunSummary.Phase = .parseArguments
    var projectRoot: String?
    var outputDirectory: String?
    var obfuscatedCodeOutput: String?
    var sourceRoots: [RunSummary.SourceRoot] = []
    var build: RunSummary.Build?
    var counters = RunSummary.Counters()
    var callableReport: CallableSignature.Report?
    var parameterSyntaxReport: ParameterSyntax.Report?
    var callSiteSyntaxReport: CallSiteSyntax.Report?
    var callArgumentBindingReport: CallArgumentBinding.Report?
    var callableReferenceSyntaxReport: CallableReferenceSyntax.Report?
    var callableReferenceBindingReport: CallableReferenceBinding.Report?
    var externalLabelReport: ExternalLabel.Report?
    var externalLabelRenameReport: ExternalLabel.RenameReport?
    var localBindingRenameReport: LocalBindingRename.Report?
    var enumCaseSemanticsReport: EnumCaseSemantics.Report?
    var enumRawValueReport: EnumRawValue.Report?
    var enumCaseSyntaxReport: EnumCaseSyntax.Report?
    var genericParameterReport: GenericParameterAnalysis.Report?
    var typeAliasSyntaxReport: TypeAliasSyntax.Report?
    var artifacts = RunSummary.Artifacts()
    var logs: [String] = []
    var failure: RunSummary.Failure?

    private enum CodingKeys: String, CodingKey {
        case status
        case command
        case phase
        case projectRoot
        case outputDirectory
        case obfuscatedCodeOutput
        case sourceRoots
        case build
        case counters
        case callableReport = "parameterFacts"
        case parameterSyntaxReport = "parameterSyntaxFacts"
        case callSiteSyntaxReport = "parameterCallSiteSyntaxFacts"
        case callArgumentBindingReport = "parameterCallArgumentBindingFacts"
        case callableReferenceSyntaxReport = "parameterCallableReferenceSyntaxFacts"
        case callableReferenceBindingReport = "parameterCallableReferenceBindingFacts"
        case externalLabelReport = "parameterExternalLabelComponentFacts"
        case externalLabelRenameReport = "parameterExternalLabelRenameOutcome"
        case localBindingRenameReport = "parameterLocalBindingOutcome"
        case enumCaseSemanticsReport = "enumCaseComponentFacts"
        case enumRawValueReport = "compilerRawValueFacts"
        case enumCaseSyntaxReport = "enumCaseSyntaxFacts"
        case genericParameterReport = "genericParameterSyntaxFacts"
        case typeAliasSyntaxReport = "typealiasSyntaxFacts"
        case artifacts
        case logs
        case failure = "error"
    }
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

struct PreparedIndex {
    let scheme: String
    let indexStorePath: URL
}

struct PreparedRenamePlan {
    let plan: RenamePlan
    let mappingStore: RenameMappingStore
    let selectedSourceFiles: [String]
    let snapshotForCoverage: IndexSnapshot?
}

enum PreparedPlanResult {
    case dumpCompleted
    case ready(PreparedRenamePlan)
}
