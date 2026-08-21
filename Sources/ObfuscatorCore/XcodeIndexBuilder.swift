import Foundation

public final class XcodeIndexBuilder {
    public struct Options: Sendable {
        public var projectRoot: URL
        public var scheme: String?
        public var configuration: String?
        public var destination: String?
        public var derivedDataPath: URL
        public var extraXcodebuildArguments: [String]

        public init(
            projectRoot: URL,
            scheme: String? = nil,
            configuration: String? = nil,
            destination: String? = "platform=macOS",
            derivedDataPath: URL,
            extraXcodebuildArguments: [String] = []
        ) {
            self.projectRoot = projectRoot
            self.scheme = scheme
            self.configuration = configuration
            self.destination = destination
            self.derivedDataPath = derivedDataPath
            self.extraXcodebuildArguments = extraXcodebuildArguments
        }
    }

    public struct Result: Sendable {
        public let command: CommandRunner.Result
        public let projectRoot: URL
        public let scheme: String
        public let derivedDataPath: URL
        public let indexStorePath: URL
    }

    public enum Error: LocalizedError {
        case noSchemeFound(URL)
        case multipleContainers([String])

        public var errorDescription: String? {
            switch self {
            case .noSchemeFound(let url):
                return "No xcodebuild scheme found at \(url.path). Pass --scheme explicitly."
            case .multipleContainers(let containers):
                return
                    "Multiple Xcode project/workspace containers found: \(containers.joined(separator: ", ")). Pass extra xcodebuild arguments after --."
            }
        }
    }

    private let runner: CommandRunner
    private let fileManager: FileManager

    public init(runner: CommandRunner = CommandRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func build(_ options: XcodeIndexBuilder.Options) throws -> XcodeIndexBuilder.Result {
        let root = options.projectRoot.standardizedFileURL
        let scheme = try options.scheme ?? inferScheme(projectRoot: root)
        try fileManager.createDirectory(
            at: options.derivedDataPath, withIntermediateDirectories: true)

        var arguments: [String] = ["xcodebuild"]
        arguments.append(contentsOf: try containerArguments(projectRoot: root))
        arguments.append(contentsOf: ["-scheme", scheme])

        if let configuration = options.configuration {
            arguments.append(contentsOf: ["-configuration", configuration])
        }
        if let destination = options.destination, !destination.isEmpty {
            arguments.append(contentsOf: ["-destination", destination])
        }

        arguments.append(contentsOf: ["-derivedDataPath", options.derivedDataPath.path])
        arguments.append("COMPILER_INDEX_STORE_ENABLE=YES")
        arguments.append(contentsOf: options.extraXcodebuildArguments)
        arguments.append("build")

        let result = try runner.run(
            executable: "/usr/bin/xcrun",
            arguments: arguments,
            workingDirectory: root
        )

        return XcodeIndexBuilder.Result(
            command: result,
            projectRoot: root,
            scheme: scheme,
            derivedDataPath: options.derivedDataPath,
            indexStorePath: options.derivedDataPath.appendingPathComponent(
                "Index.noindex/DataStore", isDirectory: true)
        )
    }

    public func inferScheme(projectRoot: URL) throws -> String {
        var arguments: [String] = ["xcodebuild"]
        arguments.append(contentsOf: try containerArguments(projectRoot: projectRoot))
        arguments.append(contentsOf: ["-list", "-json"])

        let result = try runner.run(
            executable: "/usr/bin/xcrun",
            arguments: arguments,
            workingDirectory: projectRoot
        )

        let data = Data(result.stdout.utf8)
        let list = try JSONDecoder().decode(XcodeBuildList.self, from: data)
        let schemes = list.project?.schemes ?? list.workspace?.schemes ?? []
        guard let scheme = schemes.sorted().first else {
            throw XcodeIndexBuilder.Error.noSchemeFound(projectRoot)
        }
        return scheme
    }

    private func containerArguments(projectRoot: URL) throws -> [String] {
        let contents = try fileManager.contentsOfDirectory(
            at: projectRoot, includingPropertiesForKeys: nil)
        let workspaces = contents.filter { $0.pathExtension == "xcworkspace" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        let projects = contents.filter { $0.pathExtension == "xcodeproj" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }

        if workspaces.count == 1 {
            return ["-workspace", workspaces[0].path]
        }
        if workspaces.count > 1 {
            throw XcodeIndexBuilder.Error.multipleContainers(workspaces.map(\.lastPathComponent))
        }
        if projects.count == 1 {
            return ["-project", projects[0].path]
        }
        if projects.count > 1 {
            throw XcodeIndexBuilder.Error.multipleContainers(projects.map(\.lastPathComponent))
        }
        return []
    }
}

private struct XcodeBuildList: Decodable {
    var project: XcodeBuildContainer?
    var workspace: XcodeBuildContainer?
}

private struct XcodeBuildContainer: Decodable {
    var schemes: [String]?
}
