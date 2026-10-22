import ArgumentParser
import Foundation
import ParhelionPreview

/// One running app and the connection to it.
///
/// The app runs as a child process. A reader thread receives its messages:
/// it keeps the latest frame and hands each reply to the thread waiting for
/// it. Any thread can send; a lock keeps messages from interleaving on the
/// socket.
///
/// When the app lists capabilities in its hello, the connection welcomes
/// the ones it was asked to offer. With ``PreviewCapability/sharedFrames``,
/// it maps the app's shared memory and frames arrive as slot numbers; a
/// slot goes back to the app with ``release(_:)`` once the window has
/// copied it, or as soon as a newer frame replaces it.
final class AppConnection: @unchecked Sendable {
    let hello: PreviewHello
    /// The capabilities this connection welcomed.
    let capabilities: Set<String>
    private let process: Process
    private let channel: PreviewChannel
    private let lock = NSCondition()
    private let sendLock = NSLock()
    private var frame: ReceivedFrame?
    private var answer: (target: UInt64, arrival: UInt64)?
    private var animating = false
    private var sharedFrames: SharedFrameBuffer?
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
    ///   - capabilities: The ``PreviewCapability`` values to use if the app
    ///     supports them. A host that shows no window offers none.
    ///   - wake: Called on the reader thread after each message, to wake the
    ///     main thread.
    init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        listener: PreviewListener,
        captureOutput: Bool = false,
        capabilities offered: [String] = PreviewCapability.all,
        wake: @escaping @Sendable () -> Void
    ) throws {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ValidationError("No executable at \(executable). Build the app first.")
        }
        process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let buffer = captureOutput ? OutputBuffer() : nil
        if let buffer {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            buffer.drain(pipe.fileHandleForReading)
        }
        output = buffer
        try process.run()

        do {
            channel = try Self.waitForConnection(of: process, on: listener)
        } catch {
            // Captured output is the only place an agent can learn why the app
            // exited, so it goes into the error.
            guard let buffer else { throw error }
            Thread.sleep(forTimeInterval: 0.1)
            let lines = buffer.lines(last: 20)
            guard !lines.isEmpty else { throw error }
            throw ValidationError(
                "\(error)\nThe app's last output:\n\(lines.joined(separator: "\n"))")
        }
        guard case .hello(let hello) = try channel.receiveAppMessage(timeout: 10) else {
            process.terminate()
            throw ValidationError("The app connected but did not introduce itself.")
        }
        self.hello = hello
        // Only an app that lists capabilities understands a welcome.
        let agreed = offered.filter { hello.capabilities?.contains($0) == true }
        capabilities = Set(agreed)
        if !agreed.isEmpty {
            try channel.send(.welcome(PreviewWelcome(capabilities: agreed)))
        }
        debugLog("the app supports \(hello.capabilities ?? []); using \(agreed)")

        let reader = Thread { [self] in
            while true {
                do {
                    guard let message = try channel.receiveAppMessage() else { continue }
                    receive(message)
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

    /// Handles one message on the reader thread.
    private func receive(_ message: AppMessage) {
        let arrival = PreviewClock.now()
        switch message {
        case .frame(let plain):
            keep(
                ReceivedFrame(
                    width: plain.width, height: plain.height,
                    damage: PixelRect(x: 0, y: 0, width: plain.width, height: plain.height),
                    pixels: .array(plain.pixels)),
                animating: false, answering: 0, at: arrival)
        case .frameUpdate(let update):
            var pixels: ReceivedFrame.Pixels?
            switch update.pixels {
            case .slot(let slot):
                let buffer = lock.withLock { sharedFrames }
                if let buffer, slot < buffer.slotCount,
                    update.width * update.height * 4 <= buffer.slotSize
                {
                    pixels = .slot(buffer, slot)
                } else {
                    debugLog("a frame named slot \(slot) of shared memory the host does not have")
                }
            case .inline(let bytes):
                pixels = .array(bytes)
            case .unchanged:
                pixels = nil
            }
            keep(
                pixels.map {
                    ReceivedFrame(
                        width: update.width, height: update.height, damage: update.damage,
                        pixels: $0)
                },
                animating: update.isAnimating, answering: update.targetTime, at: arrival)
        case .sharedMemory(let memory):
            do {
                let buffer = try SharedFrameBuffer(mapping: memory)
                lock.withLock { sharedFrames = buffer }
                debugLog("mapped \(memory.slotCount) shared slots of \(memory.slotSize) bytes")
            } catch {
                debugLog("could not map the app's shared memory: \(error)")
            }
        case .reply(let id, let reply):
            lock.withLock {
                replies[id] = reply
                lock.broadcast()
            }
        case .hello:
            break
        }
    }

    /// Keeps the newest frame and records the app's animation state. A
    /// frame the window never took goes back to the app at once.
    private func keep(
        _ newFrame: ReceivedFrame?, animating isAnimating: Bool, answering target: UInt64,
        at arrival: UInt64
    ) {
        let replaced: ReceivedFrame? = lock.withLock {
            animating = isAnimating
            if target != 0 { answer = (target, arrival) }
            guard let newFrame else { return nil }
            defer { frame = newFrame }
            return frame
        }
        if let replaced { release(replaced) }
    }

    /// Whether a frame or a tick's answer is waiting for ``takeFrame()`` or
    /// ``takeAnswer()``.
    var hasNews: Bool {
        lock.withLock { frame != nil || answer != nil }
    }

    /// The newest frame since the last call, if any. Give it back with
    /// ``release(_:)`` after copying its pixels.
    func takeFrame() -> ReceivedFrame? {
        lock.withLock {
            defer { frame = nil }
            return frame
        }
    }

    /// The target time of the newest tick the app answered since the last
    /// call, and when the answer arrived.
    func takeAnswer() -> (target: UInt64, arrival: UInt64)? {
        lock.withLock {
            defer { answer = nil }
            return answer
        }
    }

    /// Whether the app's last frame said that something is still moving.
    var isAnimating: Bool {
        lock.withLock { animating }
    }

    /// Whether the app draws for the host's ticks.
    var usesHostClock: Bool {
        capabilities.contains(PreviewCapability.hostClock)
    }

    /// Gives a frame's shared-memory slot back to the app.
    func release(_ frame: ReceivedFrame) {
        if case .slot(_, let slot) = frame.pixels { send(.releaseSlot(slot)) }
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
            Thread.sleep(forTimeInterval: 0.005)
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

/// A frame from the app, as the window host receives it.
struct ReceivedFrame {
    /// Where the pixels are.
    enum Pixels {
        /// In an array that came over the socket.
        case array([UInt8])
        /// In a slot of the app's shared memory, until the slot is released.
        case slot(SharedFrameBuffer, Int)
    }

    let width: Int
    let height: Int
    /// The part of the frame that changed.
    let damage: PixelRect
    let pixels: Pixels

    /// The damaged rectangle, limited to the frame.
    var clampedDamage: PixelRect {
        let x = min(max(damage.x, 0), width)
        let y = min(max(damage.y, 0), height)
        return PixelRect(
            x: x, y: y, width: min(max(damage.width, 0), width - x),
            height: min(max(damage.height, 0), height - y))
    }

    /// Calls `body` with the frame's pixels, row-major RGBA. Returns
    /// `false`, without calling it, if there are fewer pixels than the size
    /// says.
    func withPixels(_ body: (UnsafeRawBufferPointer) throws -> Void) rethrows -> Bool {
        let count = width * height * 4
        switch pixels {
        case .array(let bytes):
            guard bytes.count >= count, count > 0 else { return false }
            try bytes.withUnsafeBytes(body)
        case .slot(let buffer, let slot):
            guard buffer.slotSize >= count, count > 0 else { return false }
            try body(UnsafeRawBufferPointer(buffer.slot(slot)))
        }
        return true
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
