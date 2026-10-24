import ArgumentParser
import CSDL3
import Foundation
import ParhelionPreview
import ParhelionTooling

/// Options shared by the commands that open a preview window.
struct WindowOptions: ParsableArguments {
    @Option(help: "Pixels per point in the frames the app renders.")
    var scale: Double = 2

    @Option(help: "The size of the window relative to the screen size in points.")
    var zoom: Double = 1

    @Option(help: "The device to simulate, such as \"iPhone 17 Pro\". (default: iPhone 16)")
    var device: String?

    @Flag(
        inversion: .prefixedNo,
        help: "Draw the phone around the screen, like the Simulator's device bezel.")
    var bezel = true

    @Flag(help: "Exit after showing the first frame. For automated checks.")
    var exitAfterFirstFrame = false

    func validate() throws {
        guard scale > 0, zoom > 0 else {
            throw ValidationError("--scale and --zoom must be greater than zero.")
        }
    }

    /// The environment that tells an app to connect to `socketPath`.
    func environment(socketPath: String) -> [String: String] {
        var environment = [
            previewSocketEnvironmentKey: socketPath, "PARHELION_PREVIEW_SCALE": String(scale),
        ]
        environment[previewDeviceEnvironmentKey] = device
        return environment
    }

    func openWindow(for hello: PreviewHello) throws -> WindowHost {
        if let warning = Self.deviceWarning(requested: device, hello: hello) { print(warning) }
        return try WindowHost(
            title: Self.title(for: hello),
            screenWidth: hello.screenWidth,
            screenHeight: hello.screenHeight,
            zoom: zoom,
            bezel: bezel
                ? DeviceBezel(
                    screenWidth: hello.screenWidth,
                    screenHeight: hello.screenHeight,
                    screenCornerRadius: hello.displayCornerRadius ?? 0
                ) : nil,
            scale: hello.scale
        )
    }

    /// A warning when the app ignored `--device`, as apps built with an
    /// older Parhelion do, or `nil`.
    static func deviceWarning(requested: String?, hello: PreviewHello) -> String? {
        guard let requested, hello.deviceName == nil else { return nil }
        return """
            Warning: \(hello.appName) ignored --device "\(requested)" because it was built with \
            an older Parhelion. Update its Parhelion dependency to simulate other devices.
            """
    }

    /// The window's title: the app and the device it simulates.
    static func title(for hello: PreviewHello) -> String {
        [hello.appName, hello.deviceName, "Parhelion"].compactMap { $0 }.joined(separator: " — ")
    }
}

/// A socket path unique to this process.
func makeSocketPath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("parhelion-\(ProcessInfo.processInfo.processIdentifier).sock")
        .path
}

struct Preview: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run a built Parhelion app in a preview window.",
        discussion: """
            Starts the app, connects to it over a local socket, and shows its \
            frames in a window. Click to tap. Close the window to quit.

            With --web, the app appears on a web page instead, at the URL that \
            parhelion prints, and no display is needed. Press Control-C to quit.

            Options for parhelion go before the executable. Everything after \
            the executable is passed to the app. To rebuild and reload the app \
            when its sources change, use `parhelion run` instead.

            Example: parhelion preview --zoom 0.8 .build/debug/Counter
            """
    )

    @OptionGroup var window: WindowOptions

    @OptionGroup var web: WebOptions

    @Argument(help: "The app executable to run.")
    var executable: String

    @Argument(parsing: .captureForPassthrough, help: "Arguments for the app.")
    var arguments: [String] = []

    func run() throws {
        parhelion_line_buffer_standard_output()
        let socketPath = makeSocketPath()
        let listener = try PreviewListener(path: socketPath)
        let webHost = web.isEnabled ? try WebHost(options: web, bezel: window.bezel) : nil
        if let webHost { print(webHost.announcement) }
        // Frames that arrive before the window exists are kept until it does.
        let wakeBox = WakeBox()
        if let webHost { wakeBox.set(webHost.waker) }
        let appearance = AppearanceState()
        let app = try AppConnection(
            executable: URL(fileURLWithPath: executable).path,
            arguments: arguments,
            environment: window.environment(socketPath: socketPath).merging(
                appearance.environment
            ) { $1 },
            listener: listener,
            wake: { wakeBox.wake() }
        )
        let surface: PreviewSurface
        if let webHost {
            surface = webHost
            print("Previewing \(app.hello.appName). Press Control-C to quit.")
        } else {
            let host = try window.openWindow(for: app.hello)
            wakeBox.set(host.waker)
            surface = host
            print("Previewing \(app.hello.appName). Close the window to quit.")
            print(WindowHost.appearanceShortcuts)
        }

        let loop = FrameLoop(surface: surface, appearance: appearance)
        while true {
            switch try loop.step(app: app, idleTimeout: 0.25) {
            case .close:
                app.close()
                return
            case .running(let presentedFrame):
                if presentedFrame, window.exitAfterFirstFrame {
                    app.close()
                    return
                }
            }
            if app.isDisconnected {
                print("The app exited.")
                return
            }
        }
    }
}

/// Holds the window's wake function once the window exists, so that threads
/// started earlier can call it.
final class WakeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var waker: (@Sendable () -> Void)?

    func set(_ waker: @escaping @Sendable () -> Void) {
        lock.withLock { self.waker = waker }
    }

    func wake() {
        lock.withLock { waker }?()
    }
}
