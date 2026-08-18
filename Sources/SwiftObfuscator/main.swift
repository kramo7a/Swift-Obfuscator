import Foundation
import ObfuscatorCore

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
            let paths = try resolveRunPaths(for: options, fileManager: fileManager)
            try recordRunConfiguration(options: options, paths: paths, summary: &summary)

            output = try CLIOutput(
                outputDirectory: paths.outputDirectory,
                verbosity: options.verbosity,
                printsHumanOutput: !options.printSummaryJSON,
                fileManager: fileManager
            )
            guard let output else {
                throw CLIError.invalidArguments("Failed to initialize output writer.")
            }

            try writeRunConfiguration(options: options, paths: paths, output: output)
            let runner = CommandRunner(logDirectory: output.logsDirectory)
            let builder = ProjectBuilder(runner: runner)
            let indexedBuild = try prepareIndex(
                options: options,
                paths: paths,
                builder: builder,
                output: output,
                summary: &summary
            )

            let preparedPlan: PreparedPlan
            switch try preparePlan(
                options: options,
                paths: paths,
                indexedBuild: indexedBuild,
                runner: runner,
                output: output,
                fileManager: fileManager,
                summary: &summary
            ) {
            case .dumpOnly:
                summary.status = "success"
                summary.phase = "completed"
                finish(summary: summary, output: output, printSummaryJSON: printSummaryJSON)
                return
            case .ready(let result):
                preparedPlan = result
            }

            try recordPlanningResults(
                preparedPlan.plan,
                selectedSourceFiles: preparedPlan.selectedSourceFiles,
                compactReport: options.compactReport,
                output: output,
                summary: &summary
            )
            try writeCoverageReportIfRequested(
                plan: preparedPlan.plan,
                snapshot: preparedPlan.snapshotForCoverage,
                selectedSourceFiles: preparedPlan.selectedSourceFiles,
                existingCohortPath: paths.existingCoverageCohortPath,
                newCohortPath: paths.newCoverageCohortPath,
                cohortIdentifier: options.coverageCohortIdentifier,
                expectedCount: options.coverageExpectedCount,
                outputDirectory: paths.outputDirectory,
                output: output,
                fileManager: fileManager,
                summary: &summary
            )

            switch options.command {
            case .dump:
                break
            case .dryRun:
                if options.verifyBuild {
                    output.write("Verify build: initial indexed build succeeded; dry-run did not modify sources.")
                }
            case .apply:
                try applyPlan(
                    preparedPlan.plan,
                    to: paths.obfuscatedCodeOutputDirectory,
                    selectedSourceFiles: preparedPlan.selectedSourceFiles,
                    projectRoot: options.projectRoot,
                    mappingStore: preparedPlan.mappingStore,
                    mappingPath: paths.mappingPath,
                    output: output,
                    summary: &summary
                )
                try verifyAppliedBuildIfRequested(
                    options: options,
                    obfuscatedCodeOutputDirectory: paths.obfuscatedCodeOutputDirectory,
                    builder: builder,
                    scheme: indexedBuild.scheme,
                    derivedDataPath: paths.derivedDataPath,
                    output: output,
                    summary: &summary
                )
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

    // MARK: - Run preparation

    static func resolveRunPaths(
        for options: CLIOptions,
        fileManager: FileManager
    ) throws -> RunPaths {
        let outputDirectory =
            (options.outputDirectory
            ?? options.projectRoot.appendingPathComponent(".obfuscator", isDirectory: true)).standardizedFileURL
        let obfuscatedCodeOutputDirectory = try options.obfuscatedCodeOutputPath.map {
            try resolveObfuscatedCodeOutput($0, projectRoot: options.projectRoot)
        }
        var excludedSourceRoots = [outputDirectory]
        if let obfuscatedCodeOutputDirectory {
            excludedSourceRoots.append(obfuscatedCodeOutputDirectory)
        }

        let derivedData =
            (options.derivedDataPath
            ?? outputDirectory.appendingPathComponent("DerivedData", isDirectory: true)).standardizedFileURL
        let indexDatabase =
            (options.databasePath
            ?? outputDirectory.appendingPathComponent("IndexDatabase", isDirectory: true)).standardizedFileURL
        let mapping =
            (options.mappingPath
            ?? outputDirectory.appendingPathComponent("mapping.json")).standardizedFileURL
        let selectedSourceRoots = try resolveSourceRoots(
            options.sourceRootPaths,
            projectRoot: options.projectRoot,
            excludedRoots: excludedSourceRoots,
            fileManager: fileManager
        )

        if let obfuscatedCodeOutputDirectory {
            guard
                !isSameOrDescendant(
                    options.projectRoot,
                    of: obfuscatedCodeOutputDirectory
                )
            else {
                throw CLIError.invalidArguments(
                    "Obfuscated code output cannot be the project root or its ancestor: "
                        + obfuscatedCodeOutputDirectory.path
                )
            }
            try prepareOutputDirectory(obfuscatedCodeOutputDirectory, fileManager: fileManager)
        }

        return RunPaths(
            outputDirectory: outputDirectory,
            obfuscatedCodeOutputDirectory: obfuscatedCodeOutputDirectory,
            excludedSourceRoots: excludedSourceRoots,
            derivedDataPath: derivedData,
            indexDatabasePath: indexDatabase,
            mappingPath: mapping,
            existingCoverageCohortPath: options.coverageCohortPath?.standardizedFileURL,
            newCoverageCohortPath: options.createCoverageCohortPath?.standardizedFileURL,
            indexSourceManifestPath:
                outputDirectory
                .appendingPathComponent("index-source-manifest.json")
                .standardizedFileURL,
            indexSnapshotCachePath: indexDatabase.appendingPathExtension("snapshot.plist"),
            renamePlanCachePath: indexDatabase.appendingPathExtension("rename-plan.plist"),
            selectedSourceRoots: selectedSourceRoots
        )
    }

    static func recordRunConfiguration(
        options: CLIOptions,
        paths: RunPaths,
        summary: inout RunSummary
    ) throws {
        summary.projectRoot = options.projectRoot.path
        summary.outputDirectory = paths.outputDirectory.path
        summary.obfuscatedCodeOutput = paths.obfuscatedCodeOutputDirectory?.path
        summary.sourceRoots = try paths.selectedSourceRoots.map { sourceRoot in
            let outputPath = try paths.obfuscatedCodeOutputDirectory.map { outputDirectory in
                try mapProjectPath(
                    sourceRoot,
                    fromProjectRoot: options.projectRoot,
                    toOutputRoot: outputDirectory
                ).path
            }
            return SourceRootSummary(path: sourceRoot.path, outputPath: outputPath)
        }
        summary.counters.sourceRoots = paths.selectedSourceRoots.count
    }

    static func writeRunConfiguration(
        options: CLIOptions,
        paths: RunPaths,
        output: CLIOutput
    ) throws {
        output.write("Output directory: \(paths.outputDirectory.path)")
        if let obfuscatedCodeOutputDirectory = paths.obfuscatedCodeOutputDirectory {
            output.write("Obfuscated code output: \(obfuscatedCodeOutputDirectory.path)")
        } else {
            output.write("Obfuscated code output: in-place project sources")
        }

        output.write("Source paths selected for obfuscation:")
        for sourceRoot in paths.selectedSourceRoots {
            if let obfuscatedCodeOutputDirectory = paths.obfuscatedCodeOutputDirectory {
                let outputRoot = try mapProjectPath(
                    sourceRoot,
                    fromProjectRoot: options.projectRoot,
                    toOutputRoot: obfuscatedCodeOutputDirectory
                )
                output.write("  \(sourceRoot.path) -> \(outputRoot.path)")
            } else {
                output.write("  \(sourceRoot.path)")
            }
        }
    }

    static func prepareIndex(
        options: CLIOptions,
        paths: RunPaths,
        builder: ProjectBuilder,
        output: CLIOutput,
        summary: inout RunSummary
    ) throws -> IndexedBuild {
        let indexedBuild: IndexedBuild
        if options.reuseIndex {
            summary.phase = "validate-index-sources"
            output.write(
                "Reusing existing index database after validating all Swift sources...",
                visibility: .quiet
            )
            indexedBuild = IndexedBuild(
                scheme: try options.scheme ?? builder.inferScheme(projectRoot: options.projectRoot),
                indexStorePath: paths.derivedDataPath
                    .appendingPathComponent("Index.noindex/DataStore", isDirectory: true)
            )
        } else {
            summary.phase = "build-original"
            output.write(
                "Building original project with xcodebuild index store...",
                visibility: .quiet
            )
            let result = try builder.build(
                ProjectBuildOptions(
                    projectRoot: options.projectRoot,
                    scheme: options.scheme,
                    configuration: options.configuration,
                    destination: options.destination,
                    derivedDataPath: paths.derivedDataPath,
                    extraXcodebuildArguments: options.extraXcodebuildArguments
                ))
            indexedBuild = IndexedBuild(
                scheme: result.scheme,
                indexStorePath: result.indexStorePath
            )
            output.write("Build succeeded: scheme=\(result.scheme)", visibility: .quiet)
        }

        summary.build = BuildSummary(
            scheme: indexedBuild.scheme,
            derivedDataPath: paths.derivedDataPath.path,
            indexStorePath: indexedBuild.indexStorePath.path
        )
        output.write("Index store: \(indexedBuild.indexStorePath.path)")
        return indexedBuild
    }

    // MARK: - Plan preparation

    static func preparePlan(
        options: CLIOptions,
        paths: RunPaths,
        indexedBuild: IndexedBuild,
        runner: CommandRunner,
        output: CLIOutput,
        fileManager: FileManager,
        summary: inout RunSummary
    ) throws -> PlanPreparation {
        var sourceCache: SourceFileCache?
        var sourceManifest: IndexSourceManifest?
        if options.reuseIndex {
            let currentSourceFiles = try SourceFileFinder.swiftFiles(
                in: options.projectRoot,
                excluding: paths.excludedSourceRoots,
                fileManager: fileManager
            )
            let currentSourceCache = try SourceFileCache(paths: currentSourceFiles.map(\.path))
            let manifest = try IndexSourceManifest.load(from: paths.indexSourceManifestPath)
            try manifest.validate(sourceCache: currentSourceCache)
            sourceCache = currentSourceCache
            sourceManifest = manifest
            summary.artifacts.indexSourceManifest = paths.indexSourceManifestPath.path
            output.write(
                "Index source manifest validated: \(currentSourceFiles.count) files",
                visibility: .quiet
            )
        }

        let inputMappingStore = try MappingStore.load(from: paths.mappingPath)
        let executableURL = URL(
            fileURLWithPath: CommandLine.arguments[0],
            relativeTo: URL(
                fileURLWithPath: fileManager.currentDirectoryPath,
                isDirectory: true
            )
        ).standardizedFileURL
        let cachedPlan = try loadCachedPlanIfAvailable(
            options: options,
            paths: paths,
            executableURL: executableURL,
            sourceManifest: sourceManifest,
            mappingStore: inputMappingStore
        )

        if let cachedPlan {
            summary.phase = "load-rename-plan"
            summary.counters.indexedSymbols = cachedPlan.indexedSymbolCount
            summary.counters.indexedOccurrences = cachedPlan.indexedOccurrenceCount
            summary.artifacts.renamePlanCache = paths.renamePlanCachePath.path
            output.write(
                "Rename plan cache loaded: \(paths.renamePlanCachePath.path)",
                visibility: .quiet
            )
            return .ready(
                PreparedPlan(
                    plan: cachedPlan.plan,
                    mappingStore: MappingStore(entries: cachedPlan.outputMappingEntries),
                    selectedSourceFiles: selectedSourceFiles(
                        from: cachedPlan.sourceFiles,
                        under: paths.selectedSourceRoots
                    ),
                    snapshotForCoverage: nil
                ))
        }

        let snapshot: IndexSnapshot
        if options.reuseIndex, fileManager.fileExists(atPath: paths.indexSnapshotCachePath.path) {
            guard let sourceManifest else {
                throw CLIError.invalidArguments("Failed to validate indexed Swift sources.")
            }
            summary.phase = "load-index-snapshot"
            snapshot = try IndexSnapshotCache.load(
                from: paths.indexSnapshotCachePath,
                sourceManifest: sourceManifest
            )
            summary.artifacts.indexSnapshotCache = paths.indexSnapshotCachePath.path
            output.write(
                "Index snapshot cache loaded: \(paths.indexSnapshotCachePath.path)",
                visibility: .quiet
            )
        } else {
            summary.phase = "read-index"
            snapshot = try IndexReader(runner: runner).read(
                storePath: indexedBuild.indexStorePath,
                databasePath: paths.indexDatabasePath,
                sourceRoot: options.projectRoot,
                excludedSourceRoots: paths.excludedSourceRoots,
                reuseExistingDatabase: options.reuseIndex
            )
        }

        if let sourceCache {
            let indexedPaths = snapshot.sourceFiles
                .map(SourcePathNormalizer.canonicalPath)
                .sorted()
            guard sourceCache.allPaths == indexedPaths else {
                throw CLIError.invalidArguments(
                    "Index database source paths do not match the validated source manifest. "
                        + "Run again without --reuse-index."
                )
            }
        } else {
            let currentSourceCache = try SourceFileCache(paths: snapshot.sourceFiles)
            let manifest = try IndexSourceManifest.capture(sourceCache: currentSourceCache)
            try manifest.save(to: paths.indexSourceManifestPath)
            sourceCache = currentSourceCache
            sourceManifest = manifest
            summary.artifacts.indexSourceManifest = paths.indexSourceManifestPath.path
            output.write("Index source manifest saved: \(paths.indexSourceManifestPath.path)")
        }

        if !fileManager.fileExists(atPath: paths.indexSnapshotCachePath.path)
            || !options.reuseIndex
        {
            guard let sourceManifest else {
                throw CLIError.invalidArguments(
                    "Failed to capture indexed Swift source manifest."
                )
            }
            summary.phase = "save-index-snapshot"
            try IndexSnapshotCache.save(
                snapshot: snapshot,
                sourceManifest: sourceManifest,
                to: paths.indexSnapshotCachePath,
                fileManager: fileManager
            )
            summary.artifacts.indexSnapshotCache = paths.indexSnapshotCachePath.path
            output.write("Index snapshot cache saved: \(paths.indexSnapshotCachePath.path)")
        }

        summary.counters.indexedSymbols = snapshot.symbols.count
        summary.counters.indexedOccurrences = snapshot.occurrences.count
        output.write(
            "Indexed symbols=\(snapshot.symbols.count), occurrences=\(snapshot.occurrences.count)",
            visibility: .quiet
        )

        if options.command == .dump || options.dumpIndex {
            summary.phase = "dump-index"
            let dump = ReportRenderer.renderDump(snapshot: snapshot)
            let dumpPath = try output.writeArtifact(named: "index-dump.txt", contents: dump)
            summary.artifacts.indexDump = dumpPath.path
            let visibility: ConsoleVisibility = options.verbosity == .quiet ? .verbose : .normal
            output.write(dump, visibility: visibility)
            output.write("Index dump saved: \(dumpPath.path)", visibility: .quiet)
            if options.command == .dump {
                return .dumpOnly
            }
        }

        summary.phase = "plan-renames"
        guard let sourceCache, let sourceManifest else {
            throw CLIError.invalidArguments("Failed to load indexed Swift sources.")
        }
        var planner = RenamePlanner(
            analyzer: SafetyAnalyzer(
                sourceRoot: options.projectRoot,
                obfuscationRoots: paths.selectedSourceRoots
            ),
            mappingStore: inputMappingStore
        )
        let plan = planner.makePlan(snapshot: snapshot, sourceCache: sourceCache)
        let sourceFilesForPlan = selectedSourceFiles(
            from: snapshot.sourceFiles,
            under: paths.selectedSourceRoots
        )

        let planCacheKey = try RenamePlanCacheKey.make(
            toolURL: executableURL,
            sourceManifest: sourceManifest,
            obfuscationRoots: paths.selectedSourceRoots,
            mappingStore: inputMappingStore
        )
        try RenamePlanCache.save(
            CachedRenamePlan(
                plan: plan,
                outputMappingEntries: planner.mappingStore.allEntries(),
                sourceFiles: snapshot.sourceFiles,
                indexedSymbolCount: snapshot.symbols.count,
                indexedOccurrenceCount: snapshot.occurrences.count
            ),
            key: planCacheKey,
            to: paths.renamePlanCachePath,
            fileManager: fileManager
        )
        summary.artifacts.renamePlanCache = paths.renamePlanCachePath.path
        output.write("Rename plan cache saved: \(paths.renamePlanCachePath.path)")

        return .ready(
            PreparedPlan(
                plan: plan,
                mappingStore: planner.mappingStore,
                selectedSourceFiles: sourceFilesForPlan,
                snapshotForCoverage: snapshot
            ))
    }

    static func loadCachedPlanIfAvailable(
        options: CLIOptions,
        paths: RunPaths,
        executableURL: URL,
        sourceManifest: IndexSourceManifest?,
        mappingStore: MappingStore
    ) throws -> CachedRenamePlan? {
        guard options.reuseIndex,
            options.command != .dump,
            !options.dumpIndex,
            paths.existingCoverageCohortPath == nil,
            paths.newCoverageCohortPath == nil,
            let sourceManifest
        else {
            return nil
        }
        let key = try RenamePlanCacheKey.make(
            toolURL: executableURL,
            sourceManifest: sourceManifest,
            obfuscationRoots: paths.selectedSourceRoots,
            mappingStore: mappingStore
        )
        return try RenamePlanCache.load(from: paths.renamePlanCachePath, matching: key)
    }

    // MARK: - Plan execution and reporting

    static func applyPlan(
        _ plan: RenamePlan,
        to obfuscatedCodeOutputDirectory: URL?,
        selectedSourceFiles: [String],
        projectRoot: URL,
        mappingStore: MappingStore,
        mappingPath: URL,
        output: CLIOutput,
        summary: inout RunSummary
    ) throws {
        summary.phase = "apply"
        let replacements = plan.replacements

        if let obfuscatedCodeOutputDirectory {
            let writtenFiles = try SourcePatcher().writePatchedCopies(
                sourceFiles: selectedSourceFiles,
                replacements: replacements,
                sourceRoot: projectRoot,
                outputRoot: obfuscatedCodeOutputDirectory
            )
            summary.counters.writtenSourceFiles = writtenFiles.count
            output.write("Applied replacements: \(replacements.count)", visibility: .quiet)
            output.write("Written source files: \(writtenFiles.count)", visibility: .quiet)
        } else {
            try SourcePatcher().apply(replacements)
            output.write(
                "Applied replacements to project source files: \(replacements.count)",
                visibility: .quiet
            )
        }
        summary.counters.appliedReplacements = replacements.count

        guard !replacements.isEmpty else {
            return
        }
        try mappingStore.save(to: mappingPath)
        summary.artifacts.mapping = mappingPath.path
        output.write("Mapping saved: \(mappingPath.path)")
    }

    static func verifyAppliedBuildIfRequested(
        options: CLIOptions,
        obfuscatedCodeOutputDirectory: URL?,
        builder: ProjectBuilder,
        scheme: String,
        derivedDataPath: URL,
        output: CLIOutput,
        summary: inout RunSummary
    ) throws {
        guard options.verifyBuild else {
            return
        }
        guard obfuscatedCodeOutputDirectory == nil else {
            output.write(
                "Verify build: initial indexed build succeeded; source-only output was not rebuilt."
            )
            return
        }

        summary.phase = "verify-build"
        output.write("Verifying patched build...")
        _ = try builder.build(
            ProjectBuildOptions(
                projectRoot: options.projectRoot,
                scheme: scheme,
                configuration: options.configuration,
                destination: options.destination,
                derivedDataPath: derivedDataPath,
                extraXcodebuildArguments: options.extraXcodebuildArguments
            ))
        output.write("Verify build succeeded.")
    }

    static func recordPlanningResults(
        _ plan: RenamePlan,
        selectedSourceFiles: [String],
        compactReport: Bool,
        output: CLIOutput,
        summary: inout RunSummary
    ) throws {
        summary.counters.selectedSourceFiles = selectedSourceFiles.count
        output.write("Selected source files=\(selectedSourceFiles.count)", visibility: .quiet)

        let replacements = plan.replacements
        try SourcePatcher().validate(replacements)
        summary.counters.plannedSymbols = plan.entries.count
        summary.counters.plannedReplacements = replacements.count
        summary.counters.deniedSymbols = plan.denied.count
        summary.counters.conflicts = plan.conflicts.count
        summary.parameterFacts = plan.parameterFacts
        summary.parameterSyntaxFacts = plan.parameterSyntaxFacts
        summary.parameterCallSiteSyntaxFacts = plan.parameterCallSiteSyntaxFacts
        summary.parameterCallArgumentBindingFacts = plan.parameterCallArgumentBindingFacts
        summary.parameterCallableReferenceSyntaxFacts = plan.parameterCallableReferenceSyntaxFacts
        summary.parameterCallableReferenceBindingFacts = plan.parameterCallableReferenceBindingFacts
        summary.parameterExternalLabelComponentFacts = plan.parameterExternalLabelComponentFacts
        summary.parameterExternalLabelRenameOutcome = plan.parameterExternalLabelRenameOutcome
        summary.parameterLocalBindingOutcome = plan.parameterLocalBindingOutcome
        summary.enumCaseComponentFacts = plan.enumCaseComponentFacts
        summary.compilerRawValueFacts = plan.compilerRawValueFacts
        summary.enumCaseSyntaxFacts = plan.enumCaseSyntaxFacts
        summary.genericParameterSyntaxFacts = plan.genericParameterSyntaxFacts
        summary.typealiasSyntaxFacts = plan.typealiasSyntaxFacts

        let report = ReportRenderer.renderDryRun(plan: plan, compact: compactReport)
        let reportPath = try output.writeArtifact(
            named: "dry-run-report.txt",
            contents: report
        )
        summary.artifacts.dryRunReport = reportPath.path
        output.write(report, visibility: .verbose)
        output.write(
            "Dry-run summary: planned=\(plan.entries.count), replacements=\(replacements.count), "
                + "denied=\(plan.denied.count), conflicts=\(plan.conflicts.count)",
            visibility: .quiet
        )
        output.write("Dry-run report saved: \(reportPath.path)", visibility: .quiet)
    }

    static func writeCoverageReportIfRequested(
        plan: RenamePlan,
        snapshot: IndexSnapshot?,
        selectedSourceFiles: [String],
        existingCohortPath: URL?,
        newCohortPath: URL?,
        cohortIdentifier: String?,
        expectedCount: Int?,
        outputDirectory: URL,
        output: CLIOutput,
        fileManager: FileManager,
        summary: inout RunSummary
    ) throws {
        guard let cohortPath = existingCohortPath ?? newCohortPath else {
            return
        }
        guard let snapshot else {
            throw CLIError.invalidArguments(
                "Coverage reporting requires an index snapshot. Run without a cached rename plan."
            )
        }

        let cohort: CoverageCohort
        if let newCohortPath {
            guard let cohortIdentifier, let expectedCount else {
                throw CLIError.invalidArguments(
                    "Creating a coverage cohort requires --coverage-cohort-id "
                        + "and --coverage-expected-count."
                )
            }
            cohort = try CoverageAnalyzer.makeBaselineCohort(
                identifier: cohortIdentifier,
                expectedCount: expectedCount,
                snapshot: snapshot,
                plan: plan,
                selectedSourceFiles: selectedSourceFiles
            )
            try cohort.save(to: newCohortPath, fileManager: fileManager)
            output.write(
                "Immutable coverage cohort saved: \(newCohortPath.path)",
                visibility: .quiet
            )
        } else {
            cohort = try CoverageCohort.load(from: cohortPath)
            output.write("Coverage cohort loaded: \(cohortPath.path)", visibility: .quiet)
        }

        let report = try CoverageAnalyzer.makeReport(
            cohort: cohort,
            snapshot: snapshot,
            plan: plan
        )
        let reportPath = outputDirectory.appendingPathComponent("coverage-report.json")
        try report.save(to: reportPath, fileManager: fileManager)
        summary.artifacts.coverageCohort = cohortPath.path
        summary.artifacts.coverageReport = reportPath.path
        summary.counters.cohortDenominator = report.denominator
        summary.counters.cohortRenamed = report.renamed
        summary.counters.cohortDenied = report.denied
        summary.counters.cohortMissingFromIndex = report.missingFromIndex
        summary.counters.cohortUnclassified = report.unclassified
        summary.counters.cohortCoveragePercent = report.coveragePercent
        output.write(
            "Coverage cohort: renamed=\(report.renamed)/\(report.denominator) "
                + "(\(String(format: "%.2f", report.coveragePercent))%), "
                + "missing=\(report.missingFromIndex), unclassified=\(report.unclassified)",
            visibility: .quiet
        )
        output.write("Coverage report saved: \(reportPath.path)", visibility: .quiet)
    }

    // MARK: - Run reporting

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
            let json = String(data: data, encoding: .utf8)
        else {
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

    static func logPaths(in logsDirectory: URL, including runLogURL: URL, fileManager: FileManager = .default)
        -> [String]
    {
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

    // MARK: - Arguments

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
                options.coverageCohortPath = URL(
                    fileURLWithPath: try value(after: argument, in: arguments, index: &index))
            case "--create-coverage-cohort":
                options.createCoverageCohortPath = URL(
                    fileURLWithPath: try value(after: argument, in: arguments, index: &index))
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
                throw CLIError.invalidArguments(
                    "--create-coverage-cohort requires --coverage-expected-count so the denominator cannot drift silently."
                )
            }
        } else if options.coverageCohortIdentifier != nil || options.coverageExpectedCount != nil {
            throw CLIError.invalidArguments(
                "--coverage-cohort-id and --coverage-expected-count are only valid with --create-coverage-cohort.")
        }
        if options.command == .dump,
            options.coverageCohortPath != nil || options.createCoverageCohortPath != nil
        {
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

    // MARK: - Paths

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
                throw CLIError.invalidArguments(
                    "Source path cannot be inside generated output directory: \(root.path) (output: \(excludedRoot.path))"
                )
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

    static func mapProjectPath(_ url: URL, fromProjectRoot projectRoot: URL, toOutputRoot outputRoot: URL) throws -> URL
    {
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

extension String {
    fileprivate func tailLines(_ lineLimit: Int) -> String {
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
