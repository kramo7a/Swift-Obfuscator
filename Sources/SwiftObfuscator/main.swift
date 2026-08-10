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

enum Command: String {
    case dump
    case dryRun = "dry-run"
    case apply
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
    var status = "running"
    var command: String
    var phase = "parse-arguments"
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
    var enumCaseSyntaxFacts: EnumCaseSyntaxFactsSummary?
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

@main
struct SwiftObfuscatorCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var summary = RunSummary(command: "dry-run")
        var printSummaryJSON = arguments.contains("--summary-json") || arguments.contains("--json")
        var output: CLIOutput?
        defer {
            output?.close()
        }

        do {
            let fileManager = FileManager.default
            var options = try parse(arguments)
            try validateCoverageOptions(options)
            printSummaryJSON = options.printSummaryJSON
            summary.command = options.command.rawValue
            summary.phase = "prepare"
            options.projectRoot = options.projectRoot.standardizedFileURL
            let outputDirectory = (options.outputDirectory ?? options.projectRoot.appendingPathComponent(".obfuscator", isDirectory: true)).standardizedFileURL
            let obfuscatedCodeOutputDirectory = try options.obfuscatedCodeOutputPath.map {
                try resolveObfuscatedCodeOutput($0, projectRoot: options.projectRoot)
            }
            var excludedRoots = [outputDirectory.standardizedFileURL]
            if let obfuscatedCodeOutputDirectory {
                excludedRoots.append(obfuscatedCodeOutputDirectory.standardizedFileURL)
            }
            let derivedDataPath = (options.derivedDataPath ?? outputDirectory.appendingPathComponent("DerivedData", isDirectory: true)).standardizedFileURL
            let databasePath = (options.databasePath ?? outputDirectory.appendingPathComponent("IndexDatabase", isDirectory: true)).standardizedFileURL
            let mappingPath = (options.mappingPath ?? outputDirectory.appendingPathComponent("mapping.json")).standardizedFileURL
            let coverageCohortPath = options.coverageCohortPath?.standardizedFileURL
            let createCoverageCohortPath = options.createCoverageCohortPath?.standardizedFileURL
            let indexSourceManifestPath = outputDirectory.appendingPathComponent("index-source-manifest.json").standardizedFileURL
            let indexSnapshotCachePath = databasePath.appendingPathExtension("snapshot.plist")
            let renamePlanCachePath = databasePath.appendingPathExtension("rename-plan.plist")
            let projectSourceRoots = try resolveSourceRoots(
                options.sourceRootPaths,
                projectRoot: options.projectRoot,
                excludedRoots: excludedRoots,
                fileManager: fileManager
            )

            summary.projectRoot = options.projectRoot.path
            summary.outputDirectory = outputDirectory.path
            summary.obfuscatedCodeOutput = obfuscatedCodeOutputDirectory?.path
            summary.sourceRoots = try projectSourceRoots.map { sourceRoot in
                if let obfuscatedCodeOutputDirectory {
                    return SourceRootSummary(
                        path: sourceRoot.path,
                        outputPath: try mapProjectPath(sourceRoot, fromProjectRoot: options.projectRoot, toOutputRoot: obfuscatedCodeOutputDirectory).path
                    )
                }
                return SourceRootSummary(path: sourceRoot.path, outputPath: nil)
            }
            summary.counters.sourceRoots = projectSourceRoots.count

            if let obfuscatedCodeOutputDirectory {
                guard !isSameOrDescendant(options.projectRoot, of: obfuscatedCodeOutputDirectory) else {
                    throw CLIError.invalidArguments("Obfuscated code output cannot be the project root or its ancestor: \(obfuscatedCodeOutputDirectory.path)")
                }
                try prepareOutputDirectory(obfuscatedCodeOutputDirectory, fileManager: fileManager)
            }

            output = try CLIOutput(
                outputDirectory: outputDirectory,
                verbosity: options.verbosity,
                printsHumanOutput: !options.printSummaryJSON,
                fileManager: fileManager
            )
            guard let output else {
                throw CLIError.invalidArguments("Failed to initialize output writer.")
            }

            output.write("Output directory: \(outputDirectory.path)")
            if let obfuscatedCodeOutputDirectory {
                output.write("Obfuscated code output: \(obfuscatedCodeOutputDirectory.path)")
            } else {
                output.write("Obfuscated code output: in-place project sources")
            }
            output.write("Source paths selected for obfuscation:")
            for sourceRoot in projectSourceRoots {
                if let obfuscatedCodeOutputDirectory {
                    let outputRoot = try mapProjectPath(sourceRoot, fromProjectRoot: options.projectRoot, toOutputRoot: obfuscatedCodeOutputDirectory)
                    output.write("  \(sourceRoot.path) -> \(outputRoot.path)")
                } else {
                    output.write("  \(sourceRoot.path)")
                }
            }
            let runner = CommandRunner(logDirectory: output.logsDirectory)
            let builder = ProjectBuilder(runner: runner)
            let buildScheme: String
            let indexStorePath: URL
            if options.reuseIndex {
                summary.phase = "validate-index-sources"
                output.write("Reusing existing index database after validating all Swift sources...", visibility: .quiet)
                buildScheme = try options.scheme ?? builder.inferScheme(projectRoot: options.projectRoot)
                indexStorePath = derivedDataPath.appendingPathComponent("Index.noindex/DataStore", isDirectory: true)
            } else {
                output.write("Building original project with xcodebuild index store...", visibility: .quiet)
                summary.phase = "build-original"
                let buildResult = try builder.build(ProjectBuildOptions(
                    projectRoot: options.projectRoot,
                    scheme: options.scheme,
                    configuration: options.configuration,
                    destination: options.destination,
                    derivedDataPath: derivedDataPath,
                    extraXcodebuildArguments: options.extraXcodebuildArguments
                ))
                buildScheme = buildResult.scheme
                indexStorePath = buildResult.indexStorePath
                output.write("Build succeeded: scheme=\(buildResult.scheme)", visibility: .quiet)
            }
            summary.build = BuildSummary(
                scheme: buildScheme,
                derivedDataPath: derivedDataPath.path,
                indexStorePath: indexStorePath.path
            )
            output.write("Index store: \(indexStorePath.path)")

            var sourceCache: SourceFileCache?
            var sourceManifest: IndexSourceManifest?
            if options.reuseIndex {
                let currentSourceFiles = try SourceFileFinder.swiftFiles(
                    in: options.projectRoot,
                    excluding: excludedRoots,
                    fileManager: fileManager
                )
                let currentSourceCache = try SourceFileCache(paths: currentSourceFiles.map(\.path))
                let manifest = try IndexSourceManifest.load(from: indexSourceManifestPath)
                try manifest.validate(sourceCache: currentSourceCache)
                sourceCache = currentSourceCache
                sourceManifest = manifest
                summary.artifacts.indexSourceManifest = indexSourceManifestPath.path
                output.write("Index source manifest validated: \(currentSourceFiles.count) files", visibility: .quiet)
            }

            let inputMappingStore = try MappingStore.load(from: mappingPath)
            let executableURL = URL(
                fileURLWithPath: CommandLine.arguments[0],
                relativeTo: URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            ).standardizedFileURL
            var cachedPlan: CachedRenamePlan?
            if options.reuseIndex,
               options.command != .dump,
               !options.dumpIndex,
               coverageCohortPath == nil,
               createCoverageCohortPath == nil,
               let sourceManifest {
                let key = try RenamePlanCacheKey.make(
                    toolURL: executableURL,
                    sourceManifest: sourceManifest,
                    obfuscationRoots: projectSourceRoots,
                    mappingStore: inputMappingStore
                )
                cachedPlan = try RenamePlanCache.load(from: renamePlanCachePath, matching: key)
            }

            let plan: RenamePlan
            let outputMappingStore: MappingStore
            let selectedSourceFiles: [String]
            var snapshotForCoverage: IndexSnapshot?
            if let cachedPlan {
                summary.phase = "load-rename-plan"
                plan = cachedPlan.plan
                outputMappingStore = MappingStore(entries: cachedPlan.outputMappingEntries)
                selectedSourceFiles = SwiftObfuscatorCLI.selectedSourceFiles(from: cachedPlan.sourceFiles, under: projectSourceRoots)
                summary.counters.indexedSymbols = cachedPlan.indexedSymbolCount
                summary.counters.indexedOccurrences = cachedPlan.indexedOccurrenceCount
                summary.artifacts.renamePlanCache = renamePlanCachePath.path
                output.write("Rename plan cache loaded: \(renamePlanCachePath.path)", visibility: .quiet)
            } else {
                let snapshot: IndexSnapshot
                if options.reuseIndex, fileManager.fileExists(atPath: indexSnapshotCachePath.path) {
                    guard let sourceManifest else {
                        throw CLIError.invalidArguments("Failed to validate indexed Swift sources.")
                    }
                    summary.phase = "load-index-snapshot"
                    snapshot = try IndexSnapshotCache.load(
                        from: indexSnapshotCachePath,
                        sourceManifest: sourceManifest
                    )
                    summary.artifacts.indexSnapshotCache = indexSnapshotCachePath.path
                    output.write("Index snapshot cache loaded: \(indexSnapshotCachePath.path)", visibility: .quiet)
                } else {
                    let reader = IndexReader(runner: runner)
                    summary.phase = "read-index"
                    snapshot = try reader.read(
                        storePath: indexStorePath,
                        databasePath: databasePath,
                        sourceRoot: options.projectRoot,
                        excludedSourceRoots: excludedRoots,
                        reuseExistingDatabase: options.reuseIndex
                    )
                }
                snapshotForCoverage = snapshot

                if let sourceCache {
                    guard sourceCache.allPaths == snapshot.sourceFiles.map(SourcePathNormalizer.canonicalPath).sorted() else {
                        throw CLIError.invalidArguments("Index database source paths do not match the validated source manifest. Run again without --reuse-index.")
                    }
                } else {
                    let currentSourceCache = try SourceFileCache(paths: snapshot.sourceFiles)
                    let manifest = try IndexSourceManifest.capture(sourceCache: currentSourceCache)
                    try manifest.save(to: indexSourceManifestPath)
                    sourceCache = currentSourceCache
                    sourceManifest = manifest
                    summary.artifacts.indexSourceManifest = indexSourceManifestPath.path
                    output.write("Index source manifest saved: \(indexSourceManifestPath.path)")
                }

                if !fileManager.fileExists(atPath: indexSnapshotCachePath.path) || !options.reuseIndex {
                    guard let sourceManifest else {
                        throw CLIError.invalidArguments("Failed to capture indexed Swift source manifest.")
                    }
                    summary.phase = "save-index-snapshot"
                    try IndexSnapshotCache.save(
                        snapshot: snapshot,
                        sourceManifest: sourceManifest,
                        to: indexSnapshotCachePath,
                        fileManager: fileManager
                    )
                    summary.artifacts.indexSnapshotCache = indexSnapshotCachePath.path
                    output.write("Index snapshot cache saved: \(indexSnapshotCachePath.path)")
                }

                summary.counters.indexedSymbols = snapshot.symbols.count
                summary.counters.indexedOccurrences = snapshot.occurrences.count
                output.write("Indexed symbols=\(snapshot.symbols.count), occurrences=\(snapshot.occurrences.count)", visibility: .quiet)

                if options.command == .dump || options.dumpIndex {
                    summary.phase = "dump-index"
                    let dump = ReportRenderer.renderDump(snapshot: snapshot)
                    let dumpPath = try output.writeArtifact(named: "index-dump.txt", contents: dump)
                    summary.artifacts.indexDump = dumpPath.path
                    let dumpVisibility: ConsoleVisibility = options.verbosity == .quiet ? .verbose : .normal
                    output.write(dump, visibility: dumpVisibility)
                    output.write("Index dump saved: \(dumpPath.path)", visibility: .quiet)
                    if options.command == .dump {
                        summary.status = "success"
                        summary.phase = "completed"
                        finish(summary: summary, output: output, printSummaryJSON: printSummaryJSON)
                        return
                    }
                }

                summary.phase = "plan-renames"
                guard let sourceCache, let sourceManifest else {
                    throw CLIError.invalidArguments("Failed to load indexed Swift sources.")
                }
                var planner = RenamePlanner(
                    analyzer: SafetyAnalyzer(
                        sourceRoot: options.projectRoot,
                        obfuscationRoots: projectSourceRoots
                    ),
                    mappingStore: inputMappingStore
                )
                plan = planner.makePlan(snapshot: snapshot, sourceCache: sourceCache)
                outputMappingStore = planner.mappingStore
                selectedSourceFiles = SwiftObfuscatorCLI.selectedSourceFiles(from: snapshot.sourceFiles, under: projectSourceRoots)

                let planCacheKey = try RenamePlanCacheKey.make(
                    toolURL: executableURL,
                    sourceManifest: sourceManifest,
                    obfuscationRoots: projectSourceRoots,
                    mappingStore: inputMappingStore
                )
                try RenamePlanCache.save(
                    CachedRenamePlan(
                        plan: plan,
                        outputMappingEntries: outputMappingStore.allEntries(),
                        sourceFiles: snapshot.sourceFiles,
                        indexedSymbolCount: snapshot.symbols.count,
                        indexedOccurrenceCount: snapshot.occurrences.count
                    ),
                    key: planCacheKey,
                    to: renamePlanCachePath,
                    fileManager: fileManager
                )
                summary.artifacts.renamePlanCache = renamePlanCachePath.path
                output.write("Rename plan cache saved: \(renamePlanCachePath.path)")
            }

            summary.counters.selectedSourceFiles = selectedSourceFiles.count
            output.write("Selected source files=\(selectedSourceFiles.count)", visibility: .quiet)
            try SourcePatcher().validate(plan.replacements)
            summary.counters.plannedSymbols = plan.entries.count
            summary.counters.plannedReplacements = plan.replacements.count
            summary.counters.deniedSymbols = plan.denied.count
            summary.counters.conflicts = plan.conflicts.count
            summary.parameterFacts = plan.parameterFacts
            summary.parameterSyntaxFacts = plan.parameterSyntaxFacts
            summary.parameterCallSiteSyntaxFacts = plan.parameterCallSiteSyntaxFacts
            summary.parameterCallArgumentBindingFacts = plan.parameterCallArgumentBindingFacts
            summary.parameterCallableReferenceSyntaxFacts =
                plan.parameterCallableReferenceSyntaxFacts
            summary.parameterCallableReferenceBindingFacts =
                plan.parameterCallableReferenceBindingFacts
            summary.parameterExternalLabelComponentFacts =
                plan.parameterExternalLabelComponentFacts
            summary.parameterExternalLabelRenameOutcome =
                plan.parameterExternalLabelRenameOutcome
            summary.parameterLocalBindingOutcome = plan.parameterLocalBindingOutcome
            summary.enumCaseComponentFacts = plan.enumCaseComponentFacts
            summary.enumCaseSyntaxFacts = plan.enumCaseSyntaxFacts
            let dryRunReport = ReportRenderer.renderDryRun(plan: plan, compact: options.compactReport)
            let dryRunReportPath = try output.writeArtifact(named: "dry-run-report.txt", contents: dryRunReport)
            summary.artifacts.dryRunReport = dryRunReportPath.path
            output.write(dryRunReport, visibility: .verbose)
            output.write("Dry-run summary: planned=\(plan.entries.count), replacements=\(plan.replacements.count), denied=\(plan.denied.count), conflicts=\(plan.conflicts.count)", visibility: .quiet)
            output.write("Dry-run report saved: \(dryRunReportPath.path)", visibility: .quiet)

            if let cohortPath = coverageCohortPath ?? createCoverageCohortPath {
                guard let snapshotForCoverage else {
                    throw CLIError.invalidArguments("Coverage reporting requires an index snapshot. Run without a cached rename plan.")
                }

                let cohort: CoverageCohort
                if let createCoverageCohortPath {
                    guard let identifier = options.coverageCohortIdentifier,
                          let expectedCount = options.coverageExpectedCount else {
                        throw CLIError.invalidArguments("Creating a coverage cohort requires --coverage-cohort-id and --coverage-expected-count.")
                    }
                    cohort = try CoverageAnalyzer.makeBaselineCohort(
                        identifier: identifier,
                        expectedCount: expectedCount,
                        snapshot: snapshotForCoverage,
                        plan: plan,
                        selectedSourceFiles: selectedSourceFiles
                    )
                    try cohort.save(to: createCoverageCohortPath, fileManager: fileManager)
                    output.write("Immutable coverage cohort saved: \(createCoverageCohortPath.path)", visibility: .quiet)
                } else {
                    cohort = try CoverageCohort.load(from: cohortPath)
                    output.write("Coverage cohort loaded: \(cohortPath.path)", visibility: .quiet)
                }

                let coverageReport = try CoverageAnalyzer.makeReport(
                    cohort: cohort,
                    snapshot: snapshotForCoverage,
                    plan: plan
                )
                let coverageReportPath = outputDirectory.appendingPathComponent("coverage-report.json")
                try coverageReport.save(to: coverageReportPath, fileManager: fileManager)
                summary.artifacts.coverageCohort = cohortPath.path
                summary.artifacts.coverageReport = coverageReportPath.path
                summary.counters.cohortDenominator = coverageReport.denominator
                summary.counters.cohortRenamed = coverageReport.renamed
                summary.counters.cohortDenied = coverageReport.denied
                summary.counters.cohortMissingFromIndex = coverageReport.missingFromIndex
                summary.counters.cohortUnclassified = coverageReport.unclassified
                summary.counters.cohortCoveragePercent = coverageReport.coveragePercent
                output.write(
                    "Coverage cohort: renamed=\(coverageReport.renamed)/\(coverageReport.denominator) "
                        + "(\(String(format: "%.2f", coverageReport.coveragePercent))%), "
                        + "missing=\(coverageReport.missingFromIndex), unclassified=\(coverageReport.unclassified)",
                    visibility: .quiet
                )
                output.write("Coverage report saved: \(coverageReportPath.path)", visibility: .quiet)
            }

            switch options.command {
            case .dump:
                break
            case .dryRun:
                if options.verifyBuild {
                    output.write("Verify build: initial indexed build succeeded; dry-run did not modify sources.")
                }
            case .apply:
                summary.phase = "apply"
                if let obfuscatedCodeOutputDirectory {
                    let writtenFiles = try SourcePatcher().writePatchedCopies(
                        sourceFiles: selectedSourceFiles,
                        replacements: plan.replacements,
                        sourceRoot: options.projectRoot,
                        outputRoot: obfuscatedCodeOutputDirectory
                    )
                    summary.counters.appliedReplacements = plan.replacements.count
                    summary.counters.writtenSourceFiles = writtenFiles.count
                    output.write("Applied replacements: \(plan.replacements.count)", visibility: .quiet)
                    output.write("Written source files: \(writtenFiles.count)", visibility: .quiet)
                } else {
                    try SourcePatcher().apply(plan.replacements)
                    summary.counters.appliedReplacements = plan.replacements.count
                    output.write("Applied replacements to project source files: \(plan.replacements.count)", visibility: .quiet)
                }
                if !plan.replacements.isEmpty {
                    try outputMappingStore.save(to: mappingPath)
                    summary.artifacts.mapping = mappingPath.path
                    output.write("Mapping saved: \(mappingPath.path)")
                }

                if options.verifyBuild {
                    if obfuscatedCodeOutputDirectory == nil {
                        summary.phase = "verify-build"
                        output.write("Verifying patched build...")
                        _ = try builder.build(ProjectBuildOptions(
                            projectRoot: options.projectRoot,
                            scheme: buildScheme,
                            configuration: options.configuration,
                            destination: options.destination,
                            derivedDataPath: derivedDataPath,
                            extraXcodebuildArguments: options.extraXcodebuildArguments
                        ))
                        output.write("Verify build succeeded.")
                    } else {
                        output.write("Verify build: initial indexed build succeeded; source-only output was not rebuilt.")
                    }
                }
            }
            summary.status = "success"
            summary.phase = "completed"
            finish(summary: summary, output: output, printSummaryJSON: printSummaryJSON)
        } catch let error as CLIError {
            summary.status = "failure"
            summary.error = RunErrorSummary(message: error.localizedDescription)
            writeError("error: \(error.localizedDescription)", output: output)
            writeError(helpText, output: output)
            finish(summary: summary, output: output, printSummaryJSON: printSummaryJSON)
            output?.close()
            exit(1)
        } catch {
            summary.status = "failure"
            summary.error = summarize(error)
            writeError("error: \(error.localizedDescription)", output: output)
            finish(summary: summary, output: output, printSummaryJSON: printSummaryJSON)
            output?.close()
            exit(1)
        }
    }

    static func finish(summary: RunSummary, output: CLIOutput?, printSummaryJSON: Bool) {
        var summary = summary
        if let output {
            summary.artifacts.runLog = output.runLogURL.path
            summary.logs = logPaths(in: output.logsDirectory, including: output.runLogURL)
            summary.artifacts.runSummary = output.outputDirectory.appendingPathComponent("run-summary.json").path
        }

        let json = renderSummaryJSON(summary)

        if let output {
            do {
                let summaryPath = try output.writeArtifact(named: "run-summary.json", contents: json)
                output.write("Run summary saved: \(summaryPath.path)", visibility: .quiet)
            } catch {
                output.writeError("warning: failed to write run summary: \(error.localizedDescription)")
            }
            if printSummaryJSON {
                output.writeJSONToStdout(json)
            }
        } else if printSummaryJSON {
            print(json)
        }
    }

    static func renderSummaryJSON(_ summary: RunSummary) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(summary),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"status":"failure","error":{"message":"Failed to encode run summary"}}"#
        }
        return json
    }

    static func summarize(_ error: Error) -> RunErrorSummary {
        if let commandError = error as? CommandRunnerError {
            switch commandError {
            case .launchFailed(let message):
                return RunErrorSummary(message: message)
            case .failed(let result):
                let outputTail = result.combinedOutput.tailLines(120)
                return RunErrorSummary(
                    message: "Command failed with exit code \(result.exitCode)",
                    commandLine: result.commandLine,
                    exitCode: result.exitCode,
                    stdoutLogPath: result.stdoutLogPath,
                    stderrLogPath: result.stderrLogPath,
                    outputTail: outputTail.isEmpty ? nil : outputTail
                )
            }
        }
        return RunErrorSummary(message: error.localizedDescription)
    }

    static func logPaths(in logsDirectory: URL, including runLogURL: URL, fileManager: FileManager = .default) -> [String] {
        var paths: [String] = []
        var seenCanonicalPaths: Set<String> = []
        func append(_ url: URL) {
            let canonicalPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seenCanonicalPaths.insert(canonicalPath).inserted else {
                return
            }
            paths.append(url.path)
        }

        append(runLogURL)
        if let contents = try? fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil) {
            for url in contents where url.pathExtension == "log" {
                append(url)
            }
        }
        return paths.sorted()
    }

    static func parse(_ arguments: [String]) throws -> CLIOptions {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(helpText)
            exit(0)
        }

        var options = CLIOptions()
        var index = 0
        if let first = arguments.first, let command = Command(rawValue: first) {
            options.command = command
            index = 1
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--":
                options.extraXcodebuildArguments.append(contentsOf: arguments[(index + 1)...])
                return options
            case "--project":
                options.projectRoot = URL(fileURLWithPath: try value(after: argument, in: arguments, index: &index))
            case "--source", "--source-root":
                options.sourceRootPaths.append(try value(after: argument, in: arguments, index: &index))
            case "--output":
                options.outputDirectory = URL(fileURLWithPath: try value(after: argument, in: arguments, index: &index))
            case "--obfuscated-code-output":
                options.obfuscatedCodeOutputPath = try value(after: argument, in: arguments, index: &index)
            case let inline where inline.hasPrefix("--obfuscated-code-output="):
                options.obfuscatedCodeOutputPath = try inlineValue(inline, option: "--obfuscated-code-output")
            case "--scheme":
                options.scheme = try value(after: argument, in: arguments, index: &index)
            case "--configuration":
                options.configuration = try value(after: argument, in: arguments, index: &index)
            case "--destination":
                options.destination = try value(after: argument, in: arguments, index: &index)
            case "--no-destination":
                options.destination = nil
            case "--derived-data":
                options.derivedDataPath = URL(fileURLWithPath: try value(after: argument, in: arguments, index: &index))
            case "--database":
                options.databasePath = URL(fileURLWithPath: try value(after: argument, in: arguments, index: &index))
            case "--mapping":
                options.mappingPath = URL(fileURLWithPath: try value(after: argument, in: arguments, index: &index))
            case "--coverage-cohort":
                options.coverageCohortPath = URL(fileURLWithPath: try value(after: argument, in: arguments, index: &index))
            case "--create-coverage-cohort":
                options.createCoverageCohortPath = URL(fileURLWithPath: try value(after: argument, in: arguments, index: &index))
            case "--coverage-cohort-id":
                options.coverageCohortIdentifier = try value(after: argument, in: arguments, index: &index)
            case "--coverage-expected-count":
                let value = try value(after: argument, in: arguments, index: &index)
                guard let count = Int(value), count > 0 else {
                    throw CLIError.invalidArguments("--coverage-expected-count must be a positive integer: \(value)")
                }
                options.coverageExpectedCount = count
            case "--dump":
                options.dumpIndex = true
            case "--verify-build":
                options.verifyBuild = true
            case "--reuse-index":
                options.reuseIndex = true
            case "--compact-report":
                options.compactReport = true
            case "--quiet":
                options.verbosity = .quiet
            case "--verbose":
                options.verbosity = .verbose
            case "--summary-json", "--json":
                options.printSummaryJSON = true
            case "--xcodebuild-arg":
                options.extraXcodebuildArguments.append(try value(after: argument, in: arguments, index: &index))
            default:
                throw CLIError.invalidArguments("Unknown argument: \(argument)")
            }
            index += 1
        }
        return options
    }

    static func validateCoverageOptions(_ options: CLIOptions) throws {
        if options.coverageCohortPath != nil, options.createCoverageCohortPath != nil {
            throw CLIError.invalidArguments("Use either --coverage-cohort or --create-coverage-cohort, not both.")
        }
        if options.createCoverageCohortPath != nil {
            guard let identifier = options.coverageCohortIdentifier, !identifier.isEmpty else {
                throw CLIError.invalidArguments("--create-coverage-cohort requires --coverage-cohort-id.")
            }
            guard options.coverageExpectedCount != nil else {
                throw CLIError.invalidArguments("--create-coverage-cohort requires --coverage-expected-count so the denominator cannot drift silently.")
            }
        } else if options.coverageCohortIdentifier != nil || options.coverageExpectedCount != nil {
            throw CLIError.invalidArguments("--coverage-cohort-id and --coverage-expected-count are only valid with --create-coverage-cohort.")
        }
        if options.command == .dump,
           options.coverageCohortPath != nil || options.createCoverageCohortPath != nil {
            throw CLIError.invalidArguments("Coverage reporting is available for dry-run and apply, not dump.")
        }
    }

    static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError.invalidArguments("Missing value after \(option)")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    static func inlineValue(_ argument: String, option: String) throws -> String {
        let prefix = option + "="
        guard argument.hasPrefix(prefix) else {
            throw CLIError.invalidArguments("Invalid argument: \(argument)")
        }
        let value = String(argument.dropFirst(prefix.count))
        guard !value.isEmpty else {
            throw CLIError.invalidArguments("Missing value after \(option)")
        }
        return value
    }

    static func resolveSourceRoots(
        _ paths: [String],
        projectRoot: URL,
        excludedRoots: [URL],
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let requestedPaths = paths.isEmpty ? [projectRoot.path] : paths
        var roots: [URL] = []
        var seen: Set<String> = []

        for requestedPath in requestedPaths {
            let root = resolvePath(requestedPath, relativeTo: projectRoot).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                throw CLIError.invalidArguments("Source path does not exist: \(root.path)")
            }
            guard isDirectory.boolValue || root.pathExtension == "swift" else {
                throw CLIError.invalidArguments("Source path must be a directory or Swift source file: \(root.path)")
            }
            guard isSameOrDescendant(root, of: projectRoot) else {
                throw CLIError.invalidArguments("Source path must be inside project root: \(root.path)")
            }
            if let excludedRoot = excludedRoots.first(where: { isSameOrDescendant(root, of: $0) }) {
                throw CLIError.invalidArguments("Source path cannot be inside generated output directory: \(root.path) (output: \(excludedRoot.path))")
            }

            let normalized = normalizedPath(root)
            if seen.insert(normalized).inserted {
                roots.append(root)
            }
        }

        return roots
    }

    static func resolveObfuscatedCodeOutput(_ path: String, projectRoot: URL) throws -> URL {
        let output = resolvePath(path, relativeTo: projectRoot).standardizedFileURL
        guard normalizedPath(output) != normalizedPath(projectRoot) else {
            throw CLIError.invalidArguments("Obfuscated code output cannot be the project root: \(output.path)")
        }
        return output
    }

    static func prepareOutputDirectory(
        _ outputDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.removeItem(at: outputDirectory)
        }
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    static func selectedSourceFiles(from sourceFiles: [String], under sourceRoots: [URL]) -> [String] {
        sourceFiles.filter { sourceFile in
            let sourceURL = URL(fileURLWithPath: sourceFile).standardizedFileURL
            return sourceRoots.contains { isSameOrDescendant(sourceURL, of: $0) }
        }
        .sorted()
    }

    static func resolvePath(_ path: String, relativeTo root: URL) -> URL {
        if (path as NSString).isAbsolutePath {
            return URL(fileURLWithPath: path)
        }
        return root.appendingPathComponent(path, isDirectory: true)
    }

    static func mapProjectPath(_ url: URL, fromProjectRoot projectRoot: URL, toOutputRoot outputRoot: URL) throws -> URL {
        guard isSameOrDescendant(url, of: projectRoot) else {
            throw CLIError.invalidArguments("Path must be inside project root: \(url.path)")
        }
        let projectPath = normalizedPath(projectRoot)
        let path = normalizedPath(url)
        if path == projectPath {
            return outputRoot.standardizedFileURL
        }

        let relativePath = String(path.dropFirst(projectPath.count + 1))
        return appendRelativePath(relativePath, to: outputRoot).standardizedFileURL
    }

    static func appendRelativePath(_ relativePath: String, to root: URL) -> URL {
        relativePath.split(separator: "/").reduce(root) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: true)
        }
    }

    static func isSameOrDescendant(_ url: URL, of root: URL) -> Bool {
        let path = normalizedPath(url)
        let rootPath = normalizedPath(root)
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    static func normalizedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path.count > 1, path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }

    static func writeError(_ message: String, output: CLIOutput?) {
        if let output {
            output.writeError(message)
        } else {
            fputs(message + "\n", stderr)
        }
    }
}

enum ConsoleVisibility: Int {
    case quiet = 0
    case normal = 1
    case verbose = 2
}

final class CLIOutput {
    let outputDirectory: URL
    let logsDirectory: URL
    let runLogURL: URL

    private let logHandle: FileHandle
    private let verbosity: OutputVerbosity
    private let printsHumanOutput: Bool
    private var isClosed = false

    init(
        outputDirectory: URL,
        verbosity: OutputVerbosity = .normal,
        printsHumanOutput: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        self.outputDirectory = outputDirectory.standardizedFileURL
        let runID = Self.sanitizedLogName(ProcessInfo.processInfo.globallyUniqueString)
        self.logsDirectory = self.outputDirectory
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        self.runLogURL = logsDirectory.appendingPathComponent("swift-obfuscator.log")
        self.verbosity = verbosity
        self.printsHumanOutput = printsHumanOutput

        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        fileManager.createFile(atPath: runLogURL.path, contents: nil)
        self.logHandle = try FileHandle(forWritingTo: runLogURL)
    }

    func write(_ message: String = "", visibility: ConsoleVisibility = .normal) {
        if printsHumanOutput, visibility.rawValue <= verbosity.rawValue {
            print(message)
        }
        writeToLog(message + "\n")
    }

    func writeError(_ message: String) {
        fputs(message + "\n", stderr)
        writeToLog(message + "\n")
    }

    func writeJSONToStdout(_ json: String) {
        print(json)
        writeToLog(json + "\n")
    }

    func writeArtifact(named fileName: String, contents: String) throws -> URL {
        let url = outputDirectory.appendingPathComponent(fileName)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func close() {
        guard !isClosed else {
            return
        }
        try? logHandle.synchronize()
        try? logHandle.close()
        isClosed = true
    }

    private func writeToLog(_ message: String) {
        guard !isClosed, let data = message.data(using: .utf8) else {
            return
        }
        logHandle.write(data)
    }

    private static func sanitizedLogName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(scalars)
        return name.isEmpty ? "run" : name
    }

    deinit {
        close()
    }
}

private extension String {
    func tailLines(_ lineLimit: Int) -> String {
        guard lineLimit > 0 else {
            return ""
        }
        let lines = split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(lineLimit).joined(separator: "\n")
    }
}

let helpText = """
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
