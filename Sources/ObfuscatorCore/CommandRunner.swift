import Foundation

public struct CommandResult: Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let stdoutLogPath: String?
    public let stderrLogPath: String?

    public var succeeded: Bool {
        exitCode == 0
    }

    public var commandLine: String {
        ([executable] + arguments).map(Self.shellQuoted).joined(separator: " ")
    }

    public var combinedOutput: String {
        if stderr.isEmpty {
            return stdout
        }
        if stdout.isEmpty {
            return stderr
        }
        return stdout + "\n" + stderr
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'\\$"))) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum CommandRunnerError: LocalizedError {
    case launchFailed(String)
    case failed(CommandResult)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .failed(let result):
            var lines = ["Command failed with exit code \(result.exitCode): \(result.commandLine)"]
            if let stdoutLogPath = result.stdoutLogPath {
                lines.append("stdout log: \(stdoutLogPath)")
            }
            if let stderrLogPath = result.stderrLogPath {
                lines.append("stderr log: \(stderrLogPath)")
            }
            let outputTail = result.combinedOutput.tailLines(120)
            if !outputTail.isEmpty {
                lines.append("output tail:")
                lines.append(outputTail)
            }
            return lines.joined(separator: "\n")
        }
    }
}

public final class CommandRunner {
    private let fileManager: FileManager
    private let logDirectory: URL?

    public init(logDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.logDirectory = logDirectory
        self.fileManager = fileManager
    }

    @discardableResult
    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> CommandResult {
        let logDirectory = logDirectory?.standardizedFileURL
        let tempDirectory = logDirectory ?? fileManager.temporaryDirectory
        if let logDirectory {
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }

        let unique = ProcessInfo.processInfo.globallyUniqueString
        let commandName = Self.sanitizedLogName(URL(fileURLWithPath: executable).lastPathComponent)
        let stdoutURL = tempDirectory.appendingPathComponent("\(commandName)-\(unique)-stdout.log")
        let stderrURL = tempDirectory.appendingPathComponent("\(commandName)-\(unique)-stderr.log")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            if logDirectory == nil {
                try? fileManager.removeItem(at: stdoutURL)
                try? fileManager.removeItem(at: stderrURL)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.launchFailed("Failed to launch \(executable): \(error.localizedDescription)")
        }

        process.waitUntilExit()
        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()

        let stdout = String(data: try Data(contentsOf: stdoutURL), encoding: .utf8) ?? ""
        let stderr = String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""
        let result = CommandResult(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory?.path,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            stdoutLogPath: logDirectory == nil ? nil : stdoutURL.path,
            stderrLogPath: logDirectory == nil ? nil : stderrURL.path
        )

        guard result.succeeded else {
            throw CommandRunnerError.failed(result)
        }
        return result
    }

    private static func sanitizedLogName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(scalars)
        return name.isEmpty ? "command" : name
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
