import Foundation

/// Runs command-line programs.
public enum Shell {
    public struct Result: Sendable {
        public var status: Int32
        /// Standard output and standard error, combined, if captured.
        public var output: String
    }

    /// Runs a program found on `PATH` and waits for it to finish.
    /// `environment` adds to or replaces variables of this process's
    /// environment.
    public static func run(
        _ program: String,
        _ arguments: [String],
        captureOutput: Bool,
        currentDirectory: String? = nil,
        environment: [String: String] = [:]
    ) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [program] + arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        let pipe = Pipe()
        if captureOutput {
            process.standardOutput = pipe
            process.standardError = pipe
        }
        try process.run()
        // Read before waiting, so a full pipe cannot block the child.
        let data = captureOutput ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
