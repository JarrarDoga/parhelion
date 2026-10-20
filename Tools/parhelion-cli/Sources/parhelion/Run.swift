import ArgumentParser
import CSDL3
import Foundation
import ParhelionPreview
import ParhelionTooling

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build an app, preview it, and reload it when its sources change.",
        discussion: """
            Builds the app in the package, runs it in a preview window, and watches \
            the package's Swift files. When a file changes, parhelion rebuilds the \
            app in the background and restarts it. @State values whose type is \
            Codable keep their values across the restart.

            Packages with one executable product run that product. Packages with \
            one library product, the shape xtool apps use, run the library's @main \
            type through a generated runner package in .build/parhelion-runner.

            Example: parhelion run --package-path ~/Code/MyApp
            """
    )

    @OptionGroup var window: WindowOptions

    @Option(help: "The directory of the app's package.")
    var packagePath = "."

    @Option(help: "The product to run, if the package has more than one.")
    var product: String?

    @Option(
        name: [.customShort("c"), .long],
        help: """
            debug builds faster after each change; release animates more smoothly.
            """
    )
    var configuration: BuildConfiguration = .debug

    enum BuildConfiguration: String, ExpressibleByArgument {
        case debug, release
    }

    func run() throws {
        // Show progress as it happens, even when output goes to a file.
        parhelion_line_buffer_standard_output()
        let package = try AppPackage.load(at: packagePath)
        let plan = try RunPlan.make(for: package, at: packagePath, product: product)
        let builder = AppBuilder(plan: plan, configuration: configuration.rawValue)
        var watcher = SourceWatcher(root: plan.watchRoot)

        print("Building \(plan.product)...")
        var outcome = builder.build()
        while !outcome.succeeded {
            report(outcome, from: builder)
            if window.exitAfterFirstFrame { throw ExitCode.failure }
            print("Fix the errors and save. Waiting for changes...")
            while !watcher.checkForChanges() { Thread.sleep(forTimeInterval: 0.5) }
            print("Building \(plan.product)...")
            outcome = builder.build()
        }
        let executable = try builder.executablePath()

        let stateFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "parhelion-\(ProcessInfo.processInfo.processIdentifier).state.json"
            )
            .path
        defer { try? FileManager.default.removeItem(atPath: stateFile) }
        let socketPath = makeSocketPath()
        let listener = try PreviewListener(path: socketPath)
        let wakeBox = WakeBox()
        var environment = window.environment(socketPath: socketPath)
        environment[previewStateEnvironmentKey] = stateFile
        func launch() throws -> AppConnection {
            try AppConnection(
                executable: executable,
                arguments: [],
                environment: environment,
                listener: listener,
                wake: { wakeBox.wake() }
            )
        }

        var app: AppConnection? = try launch()
        let host = try window.openWindow(for: app!.hello)
        wakeBox.set(host.waker)
        let title = "\(app!.hello.appName) — Parhelion"
        print("Running \(app!.hello.appName). Save a file to reload. Close the window to quit.")

        let rebuild = BackgroundBuild()
        var lastCheck = Date()
        var reportedExit = false
        while true {
            switch host.nextEvent(timeout: 0.25) {
            case .close?:
                app?.close()
                return
            case .input(let message)?:
                app?.send(message)
            case nil:
                break
            }

            if let frame = app?.takeFrame() {
                try host.present(frame)
                if window.exitAfterFirstFrame {
                    app?.close()
                    return
                }
            }
            if let current = app, current.isDisconnected, !reportedExit {
                reportedExit = true
                print("The app exited. Save a file to rebuild and start it again.")
            }

            if !rebuild.isRunning, Date().timeIntervalSince(lastCheck) > 0.5 {
                lastCheck = Date()
                if watcher.checkForChanges() {
                    print("Change detected. Rebuilding...")
                    host.setTitle("\(title) — Rebuilding…")
                    rebuild.start(builder, wake: host.waker)
                }
            }

            if let outcome = rebuild.takeResult() {
                guard outcome.succeeded else {
                    report(outcome, from: builder)
                    host.setTitle("\(title) — Build failed")
                    continue
                }
                app?.close()
                do {
                    app = try launch()
                    reportedExit = false
                    host.setTitle(title)
                    print(String(format: "Reloaded in %.1f s.", outcome.duration))
                } catch {
                    app = nil
                    print("The rebuilt app did not start: \(error)")
                    host.setTitle("\(title) — Not running")
                }
            }
        }
    }

    private func report(_ outcome: AppBuilder.Outcome, from builder: AppBuilder) {
        print("Build failed:")
        print(builder.errorSummary(outcome.output))
    }
}

/// Runs one build at a time on a background thread.
final class BackgroundBuild: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var result: AppBuilder.Outcome?

    var isRunning: Bool {
        lock.withLock { running }
    }

    func start(_ builder: AppBuilder, wake: @escaping @Sendable () -> Void) {
        lock.withLock { running = true }
        Thread { [self] in
            let outcome = builder.build()
            lock.withLock {
                result = outcome
                running = false
            }
            wake()
        }.start()
    }

    /// The result of the last finished build, once.
    func takeResult() -> AppBuilder.Outcome? {
        lock.withLock {
            defer { result = nil }
            return result
        }
    }
}
