import Foundation

/// Builds the app for a run plan with `swift build`.
///
/// A debug build compiles the app at `-Onone`, so an edit rebuilds in about
/// a second, and Parhelion's modules with optimization, so frames render at
/// release speed; see ``RunPlan/FrameworkOptimization``. Builds go to their
/// own scratch directory, `.build/parhelion` in the package that is built,
/// so that switching the optimization on and off, and the user's own
/// `swift build`, never invalidate each other's build products.
public struct AppBuilder: Sendable {
    public let plan: RunPlan
    /// `debug` or `release`, as for `swift build --configuration`.
    public let configuration: String

    /// The variable Parhelion's manifest reads; see its `Package.swift`.
    public static let optimizeFrameworkVariable = "PARHELION_OPTIMIZE_FRAMEWORK"

    public struct Outcome: Sendable {
        public var succeeded: Bool
        /// The compiler's output, for showing errors.
        public var output: String
        public var duration: TimeInterval
    }

    /// The arguments and environment of one `swift` command.
    public struct Command: Equatable, Sendable {
        public var arguments: [String]
        /// Variables to set on top of this process's environment.
        public var environment: [String: String]
    }

    public init(plan: RunPlan, configuration: String = "debug") {
        self.plan = plan
        self.configuration = configuration
    }

    /// Where the build products go.
    public var scratchPath: String {
        plan.buildPackagePath + "/.build/parhelion"
    }

    /// What kind of build this is, for messages.
    public var modeDescription: String {
        if configuration != "debug" { return "\(configuration) build" }
        switch plan.optimization {
        case .frameworkOnly:
            return "debug build of the app, with Parhelion optimized"
        case .wholeBuild:
            return "debug build optimized with -O, because Parhelion is pinned to a version"
        }
    }

    /// The arguments and environment shared by every command for this
    /// build, so that they all agree on the products' location.
    private func command(_ arguments: [String]) -> Command {
        var arguments =
            arguments + [
                "--package-path", plan.buildPackagePath, "--scratch-path", scratchPath,
                "--configuration", configuration,
            ]
        var environment: [String: String] = [:]
        switch plan.optimization {
        case .frameworkOnly:
            // Set for release builds too, where the flag's condition turns it
            // off, so the manifest does not change between configurations.
            environment[Self.optimizeFrameworkVariable] = "1"
        case .wholeBuild:
            // An inherited value would add flags SwiftPM rejects here.
            environment[Self.optimizeFrameworkVariable] = "0"
            if configuration == "debug" { arguments += ["-Xswiftc", "-O"] }
        }
        return Command(arguments: arguments, environment: environment)
    }

    /// The command that builds the product.
    public func buildCommand() -> Command {
        command(["build", "--product", plan.product])
    }

    /// The command that prints the directory of the built products.
    public func binPathCommand() -> Command {
        command(["build", "--show-bin-path"])
    }

    /// Builds the product. Blocks until the build finishes.
    public func build() -> Outcome {
        let start = Date()
        do {
            try plan.prepare()
            let command = buildCommand()
            let result = try Shell.run(
                "swift", command.arguments, captureOutput: true,
                environment: command.environment)
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
        let command = binPathCommand()
        let result = try Shell.run(
            "swift", command.arguments, captureOutput: true, environment: command.environment)
        let directory = result.output.split(separator: "\n").last.map(String.init) ?? ""
        return directory.trimmingCharacters(in: .whitespacesAndNewlines) + "/" + plan.product
    }

    /// The modules the build worked on, from SwiftPM's progress lines, so a
    /// slow rebuild shows its cause, such as an edit to Parhelion itself.
    public static func compiledModules(in output: String) -> [String] {
        var modules: [String] = []
        for line in output.split(separator: "\n") {
            // Swift Build prints "[17 / 26] ParhelionUI"; the native build
            // system prints "[3/9] Compiling ParhelionUI File.swift".
            var words = line.split(separator: " ")
            guard words.first?.hasPrefix("[") == true else { continue }
            words.removeAll { $0.hasPrefix("[") || $0.hasSuffix("]") || $0 == "/" }
            let name: Substring
            if words.count == 1 {
                name = words[0]
            } else if words.count >= 2, words[0] == "Compiling" {
                name = words[1]
            } else {
                continue
            }
            guard !name.hasSuffix("-product"), !modules.contains(String(name)) else { continue }
            modules.append(String(name))
        }
        return modules
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
