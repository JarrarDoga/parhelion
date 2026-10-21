import Foundation

/// Builds the app for a run plan with `swift build`.
public struct AppBuilder: Sendable {
    public let plan: RunPlan
    /// `debug` or `release`, as for `swift build --configuration`.
    public let configuration: String

    public struct Outcome: Sendable {
        public var succeeded: Bool
        /// The compiler's output, for showing errors.
        public var output: String
        public var duration: TimeInterval
    }

    public init(plan: RunPlan, configuration: String = "debug") {
        self.plan = plan
        self.configuration = configuration
    }

    /// Builds the product. Blocks until the build finishes.
    public func build() -> Outcome {
        let start = Date()
        do {
            try plan.prepare()
            let result = try Shell.run(
                "swift",
                [
                    "build", "--package-path", plan.buildPackagePath, "--product", plan.product,
                    "--configuration", configuration,
                ],
                captureOutput: true
            )
            return Outcome(
                succeeded: result.status == 0,
                output: result.output,
                duration: Date().timeIntervalSince(start)
            )
        } catch {
            return Outcome(
                succeeded: false,
                output: "\(error)",
                duration: Date().timeIntervalSince(start)
            )
        }
    }

    /// The path of the built executable.
    public func executablePath() throws -> String {
        let result = try Shell.run(
            "swift",
            [
                "build", "--package-path", plan.buildPackagePath, "--show-bin-path",
                "--configuration", configuration,
            ],
            captureOutput: true
        )
        let directory = result.output.split(separator: "\n").last.map(String.init) ?? ""
        return directory.trimmingCharacters(in: .whitespacesAndNewlines) + "/" + plan.product
    }

    /// The lines of build output that report errors, without the progress
    /// lines around them. Paths inside a runner package are replaced with
    /// the app's own source paths, so editors can open them.
    public func errorSummary(_ output: String) -> String {
        // The compiler colors its diagnostics even into a pipe. The summary
        // goes to agents and logs, so it is plain text.
        var output = output.replacing(/\x1B\[[0-9;]*[A-Za-z]/, with: "")
        if let runner = plan.runner {
            // Longest links first, so that no link is a prefix of a later one.
            for (link, destination) in runner.links.sorted(by: { $0.key.count > $1.key.count }) {
                output = output.replacingOccurrences(
                    of: runner.directory + "/" + link,
                    with: destination
                )
            }
        }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let relevant = lines.filter { line in
            line.contains("error:") || line.contains("warning:") || line.hasPrefix(" ")
                || line.hasPrefix("\t")
        }
        return (relevant.isEmpty ? lines : relevant).joined(separator: "\n")
    }
}
