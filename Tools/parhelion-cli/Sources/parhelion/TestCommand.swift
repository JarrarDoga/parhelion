import ArgumentParser
import Foundation
import ParhelionPreview
import ParhelionTooling

struct TestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Replay recorded flows against an app, without a window.",
        discussion: """
            Builds the app in the package, then starts it once for each flow file, \
            headless and on a manual clock, so that waits and Task.sleep take no real \
            time. It plays the flow's taps, typing, and scrolls, and compares the \
            screen at each checkpoint with the recorded one. Exits with a nonzero \
            status when a step fails or a checkpoint differs, and prints the lines \
            that differ.

            Record a flow with parhelion run --record FLOW.json. Press F2 in the \
            window for a checkpoint; closing the window adds the last one. Flows are \
            JSON, so they can be reviewed in a diff and written by hand.

            --update rewrites the checkpoints of each flow to the screens the app \
            shows now, after an intended change. Commands that fail still fail.

            Example: parhelion test --package-path ~/Code/MyApp flows/*.json
            """
    )

    @Argument(help: "The flow files to replay.")
    var flows: [String]

    @Option(help: "The directory of the app's package.")
    var packagePath = "."

    @Option(help: "The product to run, if the package has more than one.")
    var product: String?

    @OptionGroup var build: BuildOptions

    @Option(name: [.customShort("c"), .long], help: "debug or release.")
    var configuration: Run.BuildConfiguration = .debug

    @Flag(help: "Rewrite the checkpoints of each flow to the screens the app shows now.")
    var update = false

    func validate() throws {
        guard !flows.isEmpty else { throw ValidationError("Name at least one flow file.") }
    }

    func run() throws {
        // Fail on an unreadable flow before the build.
        var loaded: [(path: String, flow: Flow)] = []
        for path in flows {
            do {
                loaded.append((path, try FlowFiles.load(path)))
            } catch {
                throw ValidationError("\(error)")
            }
        }
        let package = try AppPackage.load(at: packagePath)
        let plan = try RunPlan.make(
            for: package, at: packagePath, product: product,
            config: try build.config(packagePath: packagePath))
        let builder = AppBuilder(plan: plan, configuration: configuration.rawValue)
        print("Building \(plan.product): \(builder.modeDescription)...")
        let outcome = builder.build()
        guard outcome.succeeded else {
            print("Build failed:")
            print(builder.errorSummary(outcome.output))
            throw ExitCode.failure
        }
        let executable = try builder.executablePath()
        let listener = try PreviewListener(path: makeSocketPath())

        var failures = 0
        for (path, flow) in loaded {
            let (report, output) = replay(
                flow, executable: executable, listener: listener)
            var wrote = false
            if update, report.passed, let updated = report.updatedFlow {
                if updated != flow {
                    try FlowFiles.write(updated, to: path)
                    wrote = true
                }
            }
            for line in FlowFiles.describe(path: path, report: report, updated: wrote) {
                print(line)
            }
            if !report.passed {
                failures += 1
                if !output.isEmpty {
                    print("  the app's last output:")
                    output.forEach { print("    \($0)") }
                }
            }
        }
        print(
            failures == 0
                ? "\(loaded.count) flow\(loaded.count == 1 ? "" : "s") passed."
                : "\(failures) of \(loaded.count) flow\(loaded.count == 1 ? "" : "s") failed.")
        if failures > 0 { throw ExitCode.failure }
    }

    /// Starts a fresh app on the flow's device and replays the flow in it.
    /// Returns the app's last output too, for a failure that is not a step's.
    private func replay(
        _ flow: Flow, executable: String, listener: PreviewListener
    ) -> (FlowReport, [String]) {
        func failure(_ message: String) -> FlowReport {
            FlowReport(
                stepCount: flow.steps.count, stepsRun: 0,
                failure: .init(step: 0, message: message))
        }
        var environment = [
            previewSocketEnvironmentKey: listener.path,
            "PARHELION_PREVIEW_SCALE": "1",
            previewManualClockEnvironmentKey: "1",
        ]
        environment[previewDeviceEnvironmentKey] = flow.device
        let app: AppConnection
        do {
            app = try AppConnection(
                executable: executable, arguments: [], environment: environment,
                listener: listener, captureOutput: true,
                capabilities: [PreviewCapability.manualClock], wake: {})
        } catch {
            return (failure("The app did not start: \(error)"), [])
        }
        defer { app.close() }
        guard app.hello.capabilities?.contains(PreviewCapability.flowReplay) == true else {
            return (
                failure(
                    "\(app.hello.appName) was built with an older Parhelion, which cannot replay "
                        + "flows. Update its Parhelion dependency."), []
            )
        }
        // A flow can run for minutes of app time; on the manual clock that is
        // seconds of real time, but a task that waits for a socket takes real time.
        guard
            let reply = app.request(
                .replay(flow, updatingCheckpoints: update), timeout: 300)
        else {
            return (
                failure("The app did not answer. It may have crashed."),
                app.recentOutput(lines: 20)
            )
        }
        guard let report = reply.flowReport else {
            return (failure(reply.message), app.recentOutput(lines: 20))
        }
        return (report, [])
    }
}
