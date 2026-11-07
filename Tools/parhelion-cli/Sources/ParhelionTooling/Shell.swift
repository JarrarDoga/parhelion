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

    /// The environment variable that limits the jobs of `swift build`, like
    /// Cargo's `CARGO_BUILD_JOBS`.
    public static let buildJobsVariable = "PARHELION_BUILD_JOBS"

    /// The number of jobs `swift build` may run at once: `option` if given,
    /// otherwise the value of `PARHELION_BUILD_JOBS`. `nil` leaves SwiftPM's
    /// default, one job per core. Values that are not positive whole numbers
    /// are ignored.
    public static func buildJobs(
        option: Int? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int? {
        if let option { return option > 0 ? option : nil }
        guard let text = environment[buildJobsVariable],
            let value = Int(text.trimmingCharacters(in: .whitespaces)), value > 0
        else { return nil }
        return value
    }
}
