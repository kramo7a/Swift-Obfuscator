import Foundation

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
