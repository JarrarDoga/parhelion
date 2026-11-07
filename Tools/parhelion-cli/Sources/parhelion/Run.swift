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

            With --web, the app appears on a web page instead of a window, at the \
            URL that parhelion prints, and no display is needed. The page stays \
            connected across reloads and shows build errors. Press Control-C to \
            quit.

            In the window, Control-Shift-A switches between light and dark, and \
            Control-Alt-Plus and Control-Alt-Minus change the text size; the page \
            has a button and a menu for them. Set PARHELION_COLOR_SCHEME or \
            PARHELION_DYNAMIC_TYPE_SIZE to start with another setting. Control-Shift-M \
            switches Reduce Motion, which --reduce-motion or PARHELION_REDUCE_MOTION=1 \
            starts on.

            An app that links a Rust library, or builds anything else before Swift, \
            says how in parhelion.json in its package: "preBuild" is a shell command \
            that runs before every swift build, "watch" lists more files and \
            directories whose changes rebuild the app, and "libraryPaths" lists \
            directories with prebuilt .a and .so files for the linker. \
            The options --pre-build, --watch, and --library-path do the same.

            --record FLOW.json records what you do in the window as a flow: taps, \
            typing, scrolls, and the pauses between them, with a checkpoint of the \
            screen at the start, at the end, and whenever you press F2. Taps name the \
            control by its accessibility identifier, else its label, so the flow \
            survives layout changes. Closing the window ends the recording, and so \
            does a reload. Replay flows without a window with parhelion test.

            --overlay board.png draws a design board over the window, at \
            --overlay-opacity (0 to 1, default 0.5), to compare by eye. For a number \
            instead, use the compare_image tool of parhelion mcp.

            Example: parhelion run --package-path ~/Code/MyApp
            """
    )

    @OptionGroup var window: WindowOptions

    @OptionGroup var web: WebOptions

    @OptionGroup var overlay: OverlayOptions

    @Option(
        help: ArgumentHelp(
            "Record what you do in the window to this flow file.", valueName: "file"))
    var record: String?

    @Option(help: "The directory of the app's package.")
    var packagePath = "."

    @Option(help: "The product to run, if the package has more than one.")
    var product: String?

    @OptionGroup var build: BuildOptions

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

    func validate() throws {
        if record != nil, web.isEnabled {
            throw ValidationError("--record needs the window; the web page cannot record yet.")
        }
    }

    func run() throws {
        // Show progress as it happens, even when output goes to a file.
        parhelion_line_buffer_standard_output()
        let package = try AppPackage.load(at: packagePath)
        let plan = try RunPlan.make(
            for: package, at: packagePath, product: product,
            config: try build.config(packagePath: packagePath))
        let builder = AppBuilder(plan: plan, configuration: configuration.rawValue)
        let watcher = SourceWatcher(plan: plan)
        // The page is up before the first build, so it can show the build's errors.
        let webHost = web.isEnabled ? try WebHost(options: web, bezel: window.bezel) : nil
        if let webHost { print(webHost.announcement) }

        print("Building \(plan.product): \(builder.modeDescription)...")
        webHost?.setStatus(.building)
        var outcome = builder.build()
        while !outcome.succeeded {
            report(outcome, from: builder)
            webHost?.setStatus(.buildFailed(builder.errorSummary(outcome.output)))
            if window.exitAfterFirstFrame { throw ExitCode.failure }
            print("Fix the errors and save. Waiting for changes...")
            // A web host catches Control-C instead of exiting, so check between waits.
            while !watcher.waitForChanges(timeout: webHost == nil ? nil : 0.25) {
                if webHost?.isInterrupted == true { return }
            }
            print("Building \(plan.product)...")
            webHost?.setStatus(.building)
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
        if let webHost { wakeBox.set(webHost.waker) }
        var environment = window.environment(socketPath: socketPath)
        environment[previewStateEnvironmentKey] = stateFile
        // Only the first launch records: a reload starts the app over, and
        // the recording would not replay from there.
        var recording = record
        // Each launch starts with the appearance the window or a page set.
        let appearance = AppearanceState(reduceMotion: window.reduceMotion)
        func launch() throws -> AppConnection {
            var launchEnvironment = environment.merging(appearance.environment) { $1 }
            launchEnvironment[previewRecordFlowEnvironmentKey] = recording
            return try AppConnection(
                executable: executable,
                arguments: [],
                environment: launchEnvironment,
                listener: listener,
                wake: { wakeBox.wake() }
            )
        }

        var app: AppConnection? = try launch()
        let surface: PreviewSurface
        if let webHost {
            surface = webHost
            print("Running \(app!.hello.appName). Save a file to reload. Press Control-C to quit.")
        } else {
            let host = try window.openWindow(for: app!.hello)
            try overlay.apply(to: host, hello: app!.hello)
            if let record {
                host.recordsFlow = true
                print(
                    "Recording to \(record). Press F2 for a checkpoint. Closing the window "
                        + "ends the recording.")
            }
            wakeBox.set(host.waker)
            surface = host
            print(
                "Running \(app!.hello.appName). Save a file to reload. Close the window to quit.")
            print(WindowHost.appearanceShortcuts)
        }
        surface.setStatus(.running)

        let loop = FrameLoop(surface: surface, appearance: appearance)
        let rebuild = BackgroundBuild()
        let changes = ChangeMonitor(watcher: watcher, wake: surface.waker)
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
                let message = "The app exited. Save a file to rebuild and start it again."
                print(message)
                surface.setStatus(.stopped(message))
            }

            // Changes during a build start another build after it.
            if !rebuild.isRunning, let time = changes.take() {
                print("Change detected. Rebuilding...")
                surface.setStatus(.building)
                changedAt = time
                rebuild.start(builder, wake: surface.waker)
            }

            if let outcome = rebuild.takeResult() {
                guard outcome.succeeded else {
                    report(outcome, from: builder)
                    surface.setStatus(.buildFailed(builder.errorSummary(outcome.output)))
                    continue
                }
                let compiled = AppBuilder.compiledModules(in: outcome.output)
                if !compiled.isEmpty {
                    print("Compiled \(compiled.joined(separator: ", ")).")
                }
                let restartedAt = PreviewClock.now()
                app?.close()
                if let path = recording {
                    recording = nil
                    (surface as? WindowHost)?.recordsFlow = false
                    print("The recording in \(path) ended: a rebuild starts the app over.")
                }
                do {
                    app = try launch()
                    reportedExit = false
                    surface.setStatus(.running)
                    reload = (changedAt ?? restartedAt, outcome.duration, restartedAt)
                } catch {
                    app = nil
                    print("The rebuilt app did not start: \(error)")
                    surface.setStatus(.stopped("The rebuilt app did not start: \(error)"))
                }
            }
        }
    }

    private func report(_ outcome: AppBuilder.Outcome, from builder: AppBuilder) {
        print("Build failed:")
        print(builder.errorSummary(outcome.output))
    }
}

/// What the app needs built besides its Swift sources, on top of
/// `parhelion.json`; see ``AppConfig``.
struct BuildOptions: ParsableArguments {
    @Option(
        help: ArgumentHelp(
            "A shell command to run before every swift build.", valueName: "command"))
    var preBuild: String?

    @Option(
        name: .customLong("watch"),
        help: ArgumentHelp(
            "A file or directory besides the Swift sources whose changes rebuild the app. "
                + "Repeat it for more.", valueName: "path"))
    var watch: [String] = []

    @Option(
        name: .customLong("library-path"),
        help: ArgumentHelp(
            "A directory with prebuilt libraries to link and load. Repeat it for more.",
            valueName: "path"))
    var libraryPath: [String] = []

    /// The package's `parhelion.json` with these options on top. Relative
    /// paths are relative to the package.
    func config(packagePath: String) throws -> AppConfig {
        try AppConfig.load(at: packagePath).overriding(
            preBuild: preBuild, watch: watch, libraryPaths: libraryPath)
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
