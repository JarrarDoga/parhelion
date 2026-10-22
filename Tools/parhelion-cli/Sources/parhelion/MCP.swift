import ArgumentParser
import CSDL3
import Foundation
import ParhelionPreview
import ParhelionTooling

struct MCP: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve an app to coding agents over the Model Context Protocol.",
        discussion: """
            Builds the app in the package, runs it without a window, and serves MCP \
            on standard input and output. Agents read the view tree, take \
            screenshots, tap, type, scroll, and rebuild after editing the code.

            With --window, the app also appears in a preview window, so you can \
            watch and use it alongside the agent.

            Register it with Claude Code:
              claude mcp add parhelion -- parhelion mcp --package-path /path/to/MyApp
            """
    )

    @Option(help: "The directory of the app's package.")
    var packagePath = "."

    @Option(help: "The product to run, if the package has more than one.")
    var product: String?

    @Option(name: [.customShort("c"), .long], help: "debug or release.")
    var configuration: Run.BuildConfiguration = .debug

    @Flag(help: "Also show the app in a preview window.")
    var window = false

    @Option(help: "The size of the preview window relative to the screen size in points.")
    var zoom: Double = 1

    @Option(help: "The device to simulate, such as \"iPhone 17 Pro\". (default: iPhone 16)")
    var device: String?

    @Flag(
        inversion: .prefixedNo,
        help: "Draw the phone around the screen in the preview window.")
    var bezel = true

    func run() throws {
        let package = try AppPackage.load(at: packagePath)
        let plan = try RunPlan.make(for: package, at: packagePath, product: product)
        let controller = try AgentController(
            plan: plan,
            builder: AppBuilder(plan: plan, configuration: configuration.rawValue),
            scale: window ? 2 : 1,
            device: device,
            // Without a window, nobody shows frames or keeps time.
            capabilities: window ? PreviewCapability.all : []
        )
        controller.start()

        let server = MCPServer(
            name: "parhelion",
            version: "0.1.0",
            instructions: AgentTools.instructions(product: plan.product, device: device),
            tools: AgentTools.definitions,
            handler: controller.handle
        )
        let serve: @Sendable () -> Void = {
            server.serve(readLine: { Swift.readLine(strippingNewline: true) }) { line in
                FileHandle.standardOutput.write(Data((line + "\n").utf8))
            }
        }

        guard window else {
            serve()
            controller.shutdown()
            return
        }

        // SDL must run on the main thread, so the protocol moves to a thread.
        Thread {
            serve()
            controller.shutdown()
        }.start()
        var loop: FrameLoop?
        while !controller.isFinished {
            guard let app = controller.currentApp else {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            if loop == nil {
                let host = try WindowOptions(scale: 2, zoom: zoom, bezel: bezel, device: device)
                    .openWindow(for: app.hello)
                controller.setWaker(host.waker)
                loop = FrameLoop(window: host)
            }
            if case .close = try loop?.step(app: app, idleTimeout: 0.05) {
                // Closing the window ends the session for the agent too.
                controller.shutdown()
                return
            }
        }
    }
}

extension WindowOptions {
    /// Options for a window that `parhelion mcp --window` opens. Every
    /// property is set, because reading an option that was neither parsed
    /// nor assigned stops the program.
    init(scale: Double, zoom: Double, bezel: Bool, device: String?) {
        self.init()
        self.scale = scale
        self.zoom = zoom
        self.bezel = bezel
        self.device = device
        self.exitAfterFirstFrame = false
    }
}

/// Owns the app on behalf of the agent: builds it, starts it, answers tool
/// calls, and rebuilds it when asked.
final class AgentController: @unchecked Sendable {
    private let plan: RunPlan
    private let builder: AppBuilder
    private let scale: Double
    private let device: String?
    private let capabilities: [String]
    private let lock = NSLock()
    private var app: AppConnection?
    private var lastFailure: String?
    private var finished = false
    private let waker = WakeBox()
    private let listener: PreviewListener
    private let socketPath = makeSocketPath()
    private let stateFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("parhelion-\(ProcessInfo.processInfo.processIdentifier).state.json")
        .path

    init(
        plan: RunPlan, builder: AppBuilder, scale: Double, device: String?,
        capabilities: [String]
    ) throws {
        self.plan = plan
        self.builder = builder
        self.scale = scale
        self.device = device
        self.capabilities = capabilities
        listener = try PreviewListener(path: socketPath)
    }

    var currentApp: AppConnection? { lock.withLock { app } }
    var isFinished: Bool { lock.withLock { finished } }

    func setWaker(_ wake: @escaping @Sendable () -> Void) {
        waker.set(wake)
    }

    /// Builds and starts the app. A failed build leaves the server running so
    /// that the agent can read the errors and fix them.
    func start() {
        log("Building \(plan.product): \(builder.modeDescription)...")
        _ = buildAndLaunch()
    }

    func shutdown() {
        let current = lock.withLock {
            finished = true
            defer { app = nil }
            return app
        }
        current?.close()
        try? FileManager.default.removeItem(atPath: stateFile)
    }

    /// Builds the app and, if that succeeds, replaces the running app with
    /// the new build, carrying its state over.
    private func buildAndLaunch() -> MCPToolResult {
        let outcome = builder.build()
        guard outcome.succeeded else {
            let summary = builder.errorSummary(outcome.output)
            lock.withLock { lastFailure = summary }
            log("Build failed:\n\(summary)")
            return .text(
                "The build failed. The previous version, if any, is still running.\n\(summary)",
                isError: true)
        }
        do {
            let executable = try builder.executablePath()
            currentApp?.close()
            var environment = [
                previewSocketEnvironmentKey: socketPath,
                "PARHELION_PREVIEW_SCALE": String(scale),
                previewStateEnvironmentKey: stateFile,
            ]
            environment[previewDeviceEnvironmentKey] = device
            let connection = try AppConnection(
                executable: executable,
                arguments: [],
                environment: environment,
                listener: listener,
                captureOutput: true,
                capabilities: capabilities,
                wake: { [waker] in waker.wake() }
            )
            lock.withLock {
                app = connection
                lastFailure = nil
            }
            log("Running \(connection.hello.appName).")
            if let warning = WindowOptions.deviceWarning(requested: device, hello: connection.hello)
            {
                log(warning)
            }
            return .text(
                String(
                    format: "Built and started %@ in %.1f s.", connection.hello.appName,
                    outcome.duration))
        } catch {
            lock.withLock {
                app = nil
                lastFailure = "\(error)"
            }
            return .text("The app was built but did not start: \(error)", isError: true)
        }
    }

    // MARK: - Tools

    func handle(_ name: String, _ arguments: MCPArguments) -> MCPToolResult {
        switch name {
        case "rebuild":
            log("Rebuilding \(plan.product)...")
            return buildAndLaunch()
        case "app_output":
            guard let app = currentApp else { return notRunning() }
            let lines = app.recentOutput(lines: min(max(arguments.int("lines") ?? 50, 1), 1000))
            return .text(
                lines.isEmpty
                    ? "The app has not written any output." : lines.joined(separator: "\n"))
        case "type_text" where arguments.string("field_id") != nil:
            let focused = run(.focus(id: arguments.string("field_id")), summaryOnly: false)
            guard !focused.isError else { return focused }
            return run(.typeText(arguments.string("text") ?? ""), summaryOnly: false)
        case "wait":
            let seconds = min(max(arguments.double("seconds") ?? 0.5, 0), 10)
            Thread.sleep(forTimeInterval: seconds)
            return run(.inspect(json: false), summaryOnly: true)
        default:
            guard let command = AgentTools.command(for: name, arguments) else {
                return .text(AgentTools.usage(of: name), isError: true)
            }
            return run(command, summaryOnly: false)
        }
    }

    private func run(_ command: PreviewCommand, summaryOnly: Bool) -> MCPToolResult {
        guard let app = currentApp, !app.isDisconnected else { return notRunning() }
        guard let reply = app.request(command) else {
            return .text(
                "The app did not answer. It may have crashed; see app_output, then rebuild.",
                isError: true)
        }
        let status = "revision \(reply.revision)\(reply.isAnimating ? ", still animating" : "")"
        if let png = reply.png {
            return MCPToolResult(content: [
                .image(png, mimeType: "image/png"), .text("\(reply.message) (\(status))"),
            ])
        }
        if summaryOnly {
            return .text(status)
        }
        if case .inspect = command { return .text(reply.message, isError: !reply.ok) }
        return .text("\(reply.message) (\(status))", isError: !reply.ok)
    }

    private func notRunning() -> MCPToolResult {
        let reason = lock.withLock { lastFailure } ?? "It exited."
        return .text(
            "The app is not running. \(reason)\nFix the problem and call rebuild.", isError: true)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("parhelion: \(message)\n".utf8))
    }
}
