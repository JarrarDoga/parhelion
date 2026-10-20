import ArgumentParser
import Foundation
import ParhelionPreview

struct Preview: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run a built Parhelion app in a preview window.",
        discussion: """
            Starts the app, connects to it over a local socket, and shows its \
            frames in a window. Click to tap. Close the window to quit.

            Options for parhelion go before the executable. Everything after \
            the executable is passed to the app.

            Example: parhelion preview --zoom 0.8 .build/debug/Counter
            """
    )

    @Option(help: "Pixels per point in the frames the app renders.")
    var scale: Double = 2

    @Option(help: "The size of the window relative to the screen size in points.")
    var zoom: Double = 1

    @Flag(help: "Exit after showing the first frame. For automated checks.")
    var exitAfterFirstFrame = false

    @Argument(help: "The app executable to run.")
    var executable: String

    @Argument(parsing: .captureForPassthrough, help: "Arguments for the app.")
    var arguments: [String] = []

    func validate() throws {
        guard scale > 0, zoom > 0 else {
            throw ValidationError("--scale and --zoom must be greater than zero.")
        }
    }

    func run() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("parhelion-\(ProcessInfo.processInfo.processIdentifier).sock")
            .path
        let listener = try PreviewListener(path: socketPath)
        let app = try AppProcess(
            executable: executable,
            arguments: arguments,
            environment: [
                previewSocketEnvironmentKey: socketPath,
                "PARHELION_PREVIEW_SCALE": String(scale),
            ]
        )
        defer { app.stop() }

        let channel = try app.waitForConnection(on: listener)
        guard case .hello(let hello) = try channel.receiveAppMessage(timeout: 10) else {
            throw CleanExit.message("error: the app did not introduce itself.")
        }

        let window = try WindowHost(
            title: "\(hello.appName) — Parhelion",
            width: Int((hello.screenWidth * zoom).rounded()),
            height: Int((hello.screenHeight * zoom).rounded())
        )
        print("Previewing \(hello.appName). Close the window to quit.")
        try window.run(channel: channel, zoom: zoom, exitAfterFirstFrame: exitAfterFirstFrame)
    }
}
