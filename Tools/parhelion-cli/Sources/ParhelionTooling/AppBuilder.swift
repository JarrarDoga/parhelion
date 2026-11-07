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
    /// The most jobs `swift build` may run at once, or `nil` for SwiftPM's
    /// default of one per core. Many sessions on one machine pass a limit
    /// so that their builds do not compete; see ``Shell/buildJobs(option:environment:)``.
    public let jobs: Int?

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

    public init(
        plan: RunPlan, configuration: String = "debug", jobs: Int? = Shell.buildJobs()
    ) {
        self.plan = plan
        self.configuration = configuration
        self.jobs = jobs
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
        // The linker finds prebuilt libraries here and the app finds a
        // shared one here at launch.
        for directory in plan.libraryPaths {
            arguments += [
                "-Xlinker", "-L" + directory, "-Xlinker", "-rpath", "-Xlinker", directory,
            ]
        }
        return Command(arguments: arguments, environment: environment)
    }

    /// The command that builds the product.
    public func buildCommand() -> Command {
        var command = command(["build", "--product", plan.product])
        if let jobs { command.arguments += ["--jobs", String(jobs)] }
        return command
    }

    /// The command that prints the directory of the built products.
    public func binPathCommand() -> Command {
        command(["build", "--show-bin-path"])
    }

    /// What the first line of ``Outcome/output`` starts with when the
    /// pre-build command failed, so ``errorSummary(_:)`` can tell its output
    /// from the compiler's.
    static let preBuildFailureMarker = "The pre-build command failed"

    /// The environment variable that holds the build configuration for the
    /// pre-build command.
    public static let configurationVariable = "PARHELION_CONFIGURATION"

    /// Runs the pre-build command, if the plan has one. Returns the failure
    /// to report, or `nil` when there is nothing to report.
    func runPreBuild() throws -> String? {
        guard let preBuild = plan.preBuild else { return nil }
        let before = Self.staticLibraries(in: plan.libraryPaths)
        let result = try Shell.run(
            "sh", ["-c", preBuild], captureOutput: true, currentDirectory: plan.packageRoot,
            environment: [Self.configurationVariable: configuration])
        guard result.status == 0 else {
            return "\(Self.preBuildFailureMarker) (exit status \(result.status)): \(preBuild)\n"
                + result.output
        }
        // SwiftPM links a product again only when an object file changed,
        // not when a static library it links did. Without its product,
        // it links.
        if Self.staticLibraries(in: plan.libraryPaths) != before {
            try? FileManager.default.removeItem(atPath: executablePath())
        }
        return nil
    }

    /// The modification time of every static library in `directories`.
    static func staticLibraries(in directories: [String]) -> [String: Date] {
        var result: [String: Date] = [:]
        for directory in directories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for name in names where name.hasSuffix(".a") {
                let path = directory + "/" + name
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                result[path] = attributes?[.modificationDate] as? Date
            }
        }
        return result
    }

    /// Runs the pre-build command and then builds the product. Blocks until
    /// the build finishes.
    public func build() -> Outcome {
        let start = Date()
        do {
            if let failure = try runPreBuild() {
                return Outcome(
                    succeeded: false, output: failure,
                    duration: Date().timeIntervalSince(start))
            }
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
        // A failed pre-build command is not the compiler: its messages, such
        // as Cargo's "error[E0308]:", do not follow the compiler's format, so
        // all of its output is the summary.
        if output.hasPrefix(Self.preBuildFailureMarker) { return output }
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
