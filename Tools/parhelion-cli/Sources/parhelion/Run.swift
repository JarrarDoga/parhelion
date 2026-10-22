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
        let watcher = SourceWatcher(root: plan.watchRoot)

        print("Building \(plan.product): \(builder.modeDescription)...")
        var outcome = builder.build()
        while !outcome.succeeded {
            report(outcome, from: builder)
            if window.exitAfterFirstFrame { throw ExitCode.failure }
            print("Fix the errors and save. Waiting for changes...")
            while !watcher.waitForChanges(timeout: nil) {}
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
        let title = WindowOptions.title(for: app!.hello)
        print("Running \(app!.hello.appName). Save a file to reload. Close the window to quit.")

        let loop = FrameLoop(window: host)
        let rebuild = BackgroundBuild()
        let changes = ChangeMonitor(watcher: watcher, wake: host.waker)
        var reportedExit = false
        // The reload in progress: when the change was seen, and how long
        // its build took, until the new app's first frame is on screen.
        var reload: (changedAt: UInt64, build: Double, restartedAt: UInt64)?
        var changedAt: UInt64?
        while true {
            switch try loop.step(app: app, idleTimeout: 1) {
            case .close:
                app?.close()
                return
            case .running(let presentedFrame):
                if presentedFrame, window.exitAfterFirstFrame {
                    app?.close()
                    return
                }
                if presentedFrame, let finished = reload {
                    reload = nil
                    let now = PreviewClock.now()
                    print(
                        String(
                            format: "Reloaded in %.2f s: build %.2f s, restart %.2f s.",
                            PreviewClock.seconds(now - finished.changedAt), finished.build,
                            PreviewClock.seconds(now - finished.restartedAt)))
                }
            }

            if let current = app, current.isDisconnected, !reportedExit {
                reportedExit = true
                print("The app exited. Save a file to rebuild and start it again.")
            }

            // Changes during a build start another build after it.
            if !rebuild.isRunning, let time = changes.take() {
                print("Change detected. Rebuilding...")
                host.setTitle("\(title) — Rebuilding…")
                changedAt = time
                rebuild.start(builder, wake: host.waker)
            }

            if let outcome = rebuild.takeResult() {
                guard outcome.succeeded else {
                    report(outcome, from: builder)
                    host.setTitle("\(title) — Build failed")
                    continue
                }
                let compiled = AppBuilder.compiledModules(in: outcome.output)
                if !compiled.isEmpty {
                    print("Compiled \(compiled.joined(separator: ", ")).")
                }
                let restartedAt = PreviewClock.now()
                app?.close()
                do {
                    app = try launch()
                    reportedExit = false
                    host.setTitle(title)
                    reload = (changedAt ?? restartedAt, outcome.duration, restartedAt)
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

/// Waits for source changes on a background thread and remembers when the
/// first one since the last ``take()`` happened.
final class ChangeMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var changedAt: UInt64?

    init(watcher: SourceWatcher, wake: @escaping @Sendable () -> Void) {
        Thread { [self] in
            while true {
                guard watcher.waitForChanges(timeout: nil) else { continue }
                let now = PreviewClock.now()
                lock.withLock {
                    if changedAt == nil { changedAt = now }
                }
                wake()
            }
        }.start()
    }

    /// When the sources changed, if they did since the last call.
    func take() -> UInt64? {
        lock.withLock {
            defer { changedAt = nil }
            return changedAt
        }
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
