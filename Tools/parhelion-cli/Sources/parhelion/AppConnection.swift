import ArgumentParser
import Foundation
import ParhelionPreview

/// One running app and the connection to it.
///
/// The app runs as a child process. A reader thread receives its messages:
/// it keeps the latest frame and hands each reply to the thread waiting for
/// it. Any thread can send; a lock keeps messages from interleaving on the
/// socket.
final class AppConnection: @unchecked Sendable {
    let hello: PreviewHello
    private let process: Process
    private let channel: PreviewChannel
    private let lock = NSCondition()
    private let sendLock = NSLock()
    private var frame: PreviewFrame?
    private var disconnected = false
    private var replies: [Int: PreviewReply] = [:]
    private var nextRequestID = 1
    private let output: OutputBuffer?

    /// Starts the app and waits for it to connect and introduce itself.
    ///
    /// - Parameters:
    ///   - captureOutput: Collect the app's standard output and error instead
    ///     of passing them through, for ``recentOutput(lines:)``. The MCP
    ///     server needs this, because its own standard output is the protocol.
    ///   - wake: Called on the reader thread after each message, to wake the
    ///     main thread.
    init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        listener: PreviewListener,
        captureOutput: Bool = false,
        wake: @escaping @Sendable () -> Void
    ) throws {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ValidationError("No executable at \(executable). Build the app first.")
        }
        process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        if captureOutput {
            let buffer = OutputBuffer()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            buffer.drain(pipe.fileHandleForReading)
            output = buffer
        } else {
            output = nil
        }
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
                    lock.withLock {
                        switch message {
                        case .frame(let frame): self.frame = frame
                        case .reply(let id, let reply): replies[id] = reply
                        case .hello: break
                        }
                        lock.broadcast()
                    }
                } catch {
                    lock.withLock {
                        disconnected = true
                        lock.broadcast()
                    }
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
        sendLock.withLock { _ = try? channel.send(message) }
    }

    /// Sends a command and waits for the app's reply.
    ///
    /// - Returns: The reply, or `nil` if the app disconnected or did not
    ///   answer within `timeout` seconds.
    func request(_ command: PreviewCommand, timeout: Double = 10) -> PreviewReply? {
        let id = lock.withLock {
            defer { nextRequestID += 1 }
            return nextRequestID
        }
        send(.command(id: id, command))
        let deadline = Date().addingTimeInterval(timeout)
        lock.lock()
        defer { lock.unlock() }
        while replies[id] == nil, !disconnected {
            guard lock.wait(until: deadline) else { break }
        }
        return replies.removeValue(forKey: id)
    }

    /// The last lines the app wrote to standard output or error, when they
    /// are captured.
    func recentOutput(lines: Int) -> [String] {
        output?.lines(last: lines) ?? []
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

/// The most recent lines of a child process's output. A thread drains the
/// pipe continuously, so the child never blocks on a full pipe.
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private var partial = ""
    private let capacity = 1000

    func drain(_ handle: FileHandle) {
        Thread { [self] in
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { return }
                append(String(decoding: data, as: UTF8.self))
            }
        }.start()
    }

    private func append(_ text: String) {
        lock.withLock {
            var pieces = (partial + text).split(separator: "\n", omittingEmptySubsequences: false)
            partial = String(pieces.removeLast())
            lines += pieces.map(String.init)
            if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        }
    }

    func lines(last count: Int) -> [String] {
        lock.withLock {
            let all = partial.isEmpty ? lines : lines + [partial]
            return Array(all.suffix(count))
        }
    }
}
