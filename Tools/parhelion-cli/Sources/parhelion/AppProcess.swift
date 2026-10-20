import ArgumentParser
import Foundation
import ParhelionPreview

/// The app being previewed, running as a child process.
final class AppProcess {
    private let process = Process()

    /// Starts `executable` with extra environment variables.
    init(executable: String, arguments: [String], environment: [String: String]) throws {
        let url = URL(fileURLWithPath: executable)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ValidationError("No executable at \(executable). Build the app first.")
        }
        process.executableURL = url
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        try process.run()
    }

    /// Waits for the app to connect. Fails if the app exits first or does not
    /// connect within `timeout` seconds.
    func waitForConnection(
        on listener: PreviewListener, timeout: Double = 30
    ) throws
        -> PreviewChannel
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let channel = try listener.accept(timeout: 0.25) { return channel }
            guard process.isRunning else {
                throw ValidationError(
                    """
                    The app exited with status \(process.terminationStatus) before it \
                    connected. Make sure it is a Parhelion app built for Linux.
                    """
                )
            }
        }
        throw ValidationError("The app did not connect within \(Int(timeout)) seconds.")
    }

    /// Asks the app to stop, and waits for it.
    func stop() {
        guard process.isRunning else { return }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
}
