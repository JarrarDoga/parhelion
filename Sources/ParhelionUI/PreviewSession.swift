#if canImport(Glibc)
#if canImport(Foundation)
import Foundation
#endif
import ParhelionPreview

/// Runs an app for a window host: sends rendered frames and applies the
/// input the host sends back.
///
/// The session draws a new frame after every message that changes what is
/// on screen, then waits for the next message. It ends when the host sends
/// ``HostMessage/close`` or the connection drops.
///
/// How it paces animation depends on the host:
///
/// - A host that welcomes ``PreviewCapability/hostClock`` sends a tick after
///   each display refresh. The session moves the clock to the tick's target
///   time, the moment the frame will be on screen, and draws once for it.
///   While the host ticks, input changes state but waits for the next tick
///   to be drawn, so each refresh gets exactly one frame.
/// - With an older host, or when ticks stop arriving, the session keeps its
///   own schedule of 60 frames per second on a fixed grid, and moves the
///   clock to the current time before each frame.
///
/// With ``PreviewCapability/sharedFrames``, frames go into slots of a
/// ``SharedFrameBuffer`` and only their slot numbers cross the socket.
@MainActor
final class PreviewSession {
    let host: ViewHost
    let channel: PreviewChannel
    let scale: Double
    let appName: String

    /// How many frames the shared memory holds: one the host is copying, one
    /// waiting for it, and one to draw the next frame into.
    static let slotCount = 3
    /// The interval of the session's own schedule, for hosts that do not
    /// tick.
    static let ownFrameInterval: UInt64 = 16_666_667
    /// How long the session waits for a tick while animating before it
    /// draws on its own schedule instead.
    static let tickTimeout: UInt64 = 100_000_000

    init(host: ViewHost, channel: PreviewChannel, scale: Double, appName: String) {
        self.host = host
        self.channel = channel
        self.scale = scale
        self.appName = appName
    }

    /// The moment the app's clock shows.
    private var timeline = PreviewTimeline(start: PreviewClock.now())
    /// The revision of the last frame sent, so unchanged screens are not
    /// sent again.
    private var sentRevision = -1
    /// Whether the last frame told the host that something is moving.
    private var sentAnimating = false
    /// When the last tick arrived, or when the session started expecting
    /// ticks.
    private var lastTickArrival: UInt64 = 0
    /// When the next frame of the session's own schedule is due.
    private var nextOwnFrame: UInt64 = 0
    /// The capabilities the host welcomed, or `nil` before a welcome.
    private var welcomed: Set<String>?
    private var sharedFrames: SharedFrameBuffer?
    private var sharedFramesFailed = false
    private var slots = SlotPool(count: 0)

    /// Whether the host is ticking: it welcomed the host clock, the last
    /// frame said something moves, and a tick arrived recently.
    private func hostIsTicking(at now: UInt64) -> Bool {
        welcomed?.contains(PreviewCapability.hostClock) == true && sentAnimating
            && now &- lastTickArrival < Self.tickTimeout
    }

    func run() throws {
        try channel.send(
            .hello(
                PreviewHello(
                    appName: appName,
                    screenWidth: Double(host.device.screenSize.width),
                    screenHeight: Double(host.device.screenSize.height),
                    scale: scale,
                    deviceName: host.device.name,
                    displayCornerRadius: Double(host.device.displayCornerRadius),
                    capabilities: PreviewCapability.all
                )
            )
        )
        try sendFrame(target: 0)
        while true {
            let message: HostMessage?
            do {
                message = try channel.receiveHostMessage(timeout: waitTimeout())
            } catch PreviewChannel.ChannelError.closed {
                return
            }
            let now = PreviewClock.now()
            guard let message else {
                // The session's own schedule: the host does not tick, or its
                // ticks stopped arriving.
                scheduleOwnFrame(after: now)
                host.advanceTime(by: timeline.advance(to: now))
                if host.revision != sentRevision || sentAnimating != host.isAnimating {
                    try sendFrame(target: 0)
                }
                continue
            }
            if case .tick = message {
                guard try handle(message) else { return }
                continue
            }
            // A change starts at the time it happens, unless the host is
            // ticking, in which case the clock already shows the next frame.
            let ticking = hostIsTicking(at: now)
            if !ticking { host.advanceTime(by: timeline.advance(to: now)) }
            guard try handle(message) else { return }
            if host.revision != sentRevision, !ticking {
                try sendFrame(target: 0)
            }
        }
    }

    /// How long to wait for the next message: until the next tick is
    /// overdue while the host ticks, until the next frame of the session's
    /// own schedule while something moves, and otherwise indefinitely.
    private func waitTimeout() -> Double? {
        let now = PreviewClock.now()
        if hostIsTicking(at: now) {
            return PreviewClock.seconds(lastTickArrival + Self.tickTimeout - now)
        }
        guard host.isAnimating || sentAnimating else { return nil }
        if nextOwnFrame <= now { scheduleOwnFrame(after: now) }
        return PreviewClock.seconds(nextOwnFrame - now)
    }

    /// Moves the session's own schedule one interval on, or restarts it
    /// from `now` if it fell behind.
    private func scheduleOwnFrame(after now: UInt64) {
        nextOwnFrame += Self.ownFrameInterval
        if nextOwnFrame <= now { nextOwnFrame = now + Self.ownFrameInterval }
    }

    /// Applies one message. Returns `false` when the session should end.
    func handle(_ message: HostMessage) throws -> Bool {
        switch message {
        case .tick(let tick):
            lastTickArrival = PreviewClock.now()
            host.advanceTime(by: timeline.advance(to: tick.targetTime))
            try answer(tick)
            return true
        case .releaseSlot(let slot):
            if !slots.release(slot) { debugLog("ignored a release of slot \(slot)") }
            return true
        default:
            break
        }
        debugLog("received \(message)")
        switch message {
        case .pointerDown(let x, let y):
            host.pointerDown(at: CGPoint(x: x, y: y))
        case .pointerMoved(let x, let y):
            host.pointerMoved(to: CGPoint(x: x, y: y))
        case .pointerUp(let x, let y):
            if let tapped = host.pointerUp(at: CGPoint(x: x, y: y)) {
                debugLog("tapped \(tapped)")
            }
            debugLog("released at time \(host.time); animating: \(host.isAnimating)")
        case .scroll(let dx, let dy, let x, let y):
            host.scroll(by: CGSize(width: dx, height: dy), at: CGPoint(x: x, y: y))
        case .text(let text):
            host.typeText(text)
        case .key(let name):
            if let key = ViewHost.Key(rawValue: name) { host.press(key) }
        case .command(let id, let command):
            try channel.send(.reply(id: id, host.execute(command)))
        case .welcome(let welcome):
            welcomed = Set(welcome.capabilities)
        case .close:
            saveState()
            return false
        case .tick, .releaseSlot:
            break
        }
        return true
    }

    /// Answers a tick with a frame drawn for its target time, or, if
    /// nothing changed, with a frame update that only reports whether the
    /// app is still animating, so the host knows whether to keep ticking.
    private func answer(_ tick: PreviewTick) throws {
        if host.revision != sentRevision {
            try sendFrame(target: tick.targetTime)
            return
        }
        let size = host.device.screenSize
        sentAnimating = host.isAnimating
        try channel.send(
            .frameUpdate(
                PreviewFrameUpdate(
                    width: Int((Double(size.width) * scale).rounded()),
                    height: Int((Double(size.height) * scale).rounded()),
                    isAnimating: sentAnimating,
                    targetTime: tick.targetTime,
                    pixels: .unchanged
                )
            )
        )
    }

    /// Where the session saves state when the host closes it, so that the
    /// next run of the app can restore it. Set by `parhelion run`.
    static var stateFilePath: String? {
        ProcessInfo.processInfo.environment[previewStateEnvironmentKey]
    }

    private func saveState() {
        guard let path = Self.stateFilePath else { return }
        try? host.stateSnapshot().write(to: URL(fileURLWithPath: path))
    }

    /// Draws the screen and sends it: as a plain frame to a host that did
    /// not welcome the app, and otherwise as a frame update, in a shared
    /// slot when one is free. `target` is the tick the frame answers, or 0.
    private func sendFrame(target: UInt64) throws {
        sentRevision = host.revision
        let start = PreviewClock.now()
        let frame = host.render(scale: scale, chrome: .screen)
        let rendered = PreviewClock.now()
        let animating = host.isAnimating
        var route = "copied"
        if let welcomed {
            let pixels: PreviewFrameUpdate.Pixels
            if welcomed.contains(PreviewCapability.sharedFrames),
                let buffer = try sharedBuffer(byteCount: frame.pixels.count),
                let slot = slots.acquire()
            {
                buffer.write(frame.pixels, toSlot: slot)
                pixels = .slot(slot)
                route = String(
                    format: "slot %d, copy %.3f ms", slot,
                    PreviewClock.milliseconds(PreviewClock.now() - rendered))
            } else {
                pixels = .inline(frame.pixels)
            }
            try channel.send(
                .frameUpdate(
                    PreviewFrameUpdate(
                        width: frame.pixelWidth,
                        height: frame.pixelHeight,
                        isAnimating: animating,
                        targetTime: target,
                        pixels: pixels
                    )
                )
            )
        } else {
            try channel.send(
                .frame(
                    PreviewFrame(
                        width: frame.pixelWidth,
                        height: frame.pixelHeight,
                        pixels: frame.pixels
                    )
                )
            )
        }
        let sent = PreviewClock.now()
        // The host starts ticking when it sees the first frame that moves.
        if animating, !sentAnimating { lastTickArrival = sent }
        sentAnimating = animating
        debugLog(
            String(
                format: "frame: render %.3f ms, transport %.3f ms (%@)%@",
                PreviewClock.milliseconds(rendered - start),
                PreviewClock.milliseconds(sent - rendered), route,
                animating ? ", animating" : ""))
    }

    /// The shared memory for frames of `byteCount` bytes, created and
    /// announced to the host the first time. Returns `nil`, and the frames
    /// travel inline, if the memory cannot be created or a frame does not
    /// fit.
    private func sharedBuffer(byteCount: Int) throws -> SharedFrameBuffer? {
        if let sharedFrames { return sharedFrames.slotSize >= byteCount ? sharedFrames : nil }
        guard !sharedFramesFailed else { return nil }
        do {
            let buffer = try SharedFrameBuffer.create(
                slotCount: Self.slotCount, slotSize: byteCount)
            try channel.send(.sharedMemory(buffer.announcement))
            sharedFrames = buffer
            slots = SlotPool(count: Self.slotCount)
            return buffer
        } catch let error as SharedFrameBuffer.SharedMemoryError {
            sharedFramesFailed = true
            debugLog("shared memory is not available (\(error)); copying frames instead")
            return nil
        }
    }
}

/// Prints a trace line to standard error when `PARHELION_DEBUG` is set.
private func debugLog(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["PARHELION_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data("parhelion app: \(message())\n".utf8))
}

extension PreviewSession {
    /// Runs a preview session if a window host launched this process.
    ///
    /// - Returns: `false` if the process was not launched by a window host.
    static func runIfRequested(content: any View, appName: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let socketPath = environment[previewSocketEnvironmentKey] else { return false }
        let scale = environment["PARHELION_PREVIEW_SCALE"].flatMap(Double.init) ?? 2
        // Before connecting, so that a window host sees an unknown device
        // name as the app exiting, with the message in its output.
        let device = simulatedDevice()
        do {
            let channel = try PreviewChannel.connect(to: socketPath)
            let savedState = stateFilePath.flatMap {
                FileManager.default.contents(atPath: $0)
            }
            let session = PreviewSession(
                host: ViewHost(anyRootView: content, device: device, restoring: savedState),
                channel: channel,
                scale: scale,
                appName: appName
            )
            try session.run()
            channel.close()
        } catch {
            FileHandle.standardError.write(Data("parhelion: preview failed: \(error)\n".utf8))
            exit(1)
        }
        return true
    }
}
#endif
