import ArgumentParser
import Foundation
import ParhelionPreview

/// One running app and the connection to it.
///
/// The app runs as a child process. A reader thread receives its frames and
/// keeps the latest one; the main thread takes frames and sends input. Each
/// direction of the channel is used by one thread only, which makes sharing
/// it safe.
final class AppConnection: @unchecked Sendable {
    let hello: PreviewHello
    private let process: Process
    private let channel: PreviewChannel
    private let lock = NSLock()
    private var frame: PreviewFrame?
    private var disconnected = false

    /// Starts the app and waits for it to connect and introduce itself.
    ///
    /// - Parameter wake: Called on the reader thread after each frame, to wake
    ///   the main thread.
    init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        listener: PreviewListener,
        wake: @escaping @Sendable () -> Void
    ) throws {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ValidationError("No executable at \(executable). Build the app first.")
        }
        process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        try process.run()

        channel = try Self.waitForConnection(of: process, on: listener)
        guard case .hello(let hello) = try channel.receiveAppMessage(timeout: 10) else {
            process.terminate()
            throw ValidationError("The app connected but did not introduce itself.")
        }
        self.hello = hello

        let reader = Thread { [self] in
            while true {
                do {
                    guard let message = try channel.receiveAppMessage() else { continue }
                    if case .frame(let frame) = message {
                        lock.withLock { self.frame = frame }
                    }
                } catch {
                    lock.withLock { disconnected = true }
                    wake()
                    return
                }
                wake()
            }
        }
        reader.start()
    }

    /// The newest frame since the last call, if any.
    func takeFrame() -> PreviewFrame? {
        lock.withLock {
            defer { frame = nil }
            return frame
        }
    }

    /// Whether the app has closed the connection or exited.
    var isDisconnected: Bool {
        lock.withLock { disconnected }
    }

    /// Sends input to the app. Errors are ignored: a closed connection shows
    /// up as ``isDisconnected``.
    func send(_ message: HostMessage) {
        try? channel.send(message)
    }

    /// Asks the app to exit, and waits up to two seconds before stopping it.
    /// The app saves its state on the way out.
    func close() {
        send(.close)
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }

    private static func waitForConnection(
        of process: Process, on listener: PreviewListener
    )
        throws -> PreviewChannel
    {
        let deadline = Date().addingTimeInterval(30)
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
        process.terminate()
        throw ValidationError("The app did not connect within 30 seconds.")
    }
}
