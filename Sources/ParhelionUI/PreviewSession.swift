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
@MainActor
final class PreviewSession {
    let host: ViewHost
    let channel: PreviewChannel
    let scale: Double
    let appName: String

    init(host: ViewHost, channel: PreviewChannel, scale: Double, appName: String) {
        self.host = host
        self.channel = channel
        self.scale = scale
        self.appName = appName
    }

    func run() throws {
        try channel.send(
            .hello(
                PreviewHello(
                    appName: appName,
                    screenWidth: Double(host.device.screenSize.width),
                    screenHeight: Double(host.device.screenSize.height),
                    scale: scale
                )
            )
        )
        try sendFrame()
        lastTick = ContinuousClock.now
        while true {
            // While something is moving, wake in time for the next frame at
            // 60 frames per second; otherwise sleep until the host sends
            // something. Drawing time counts toward the frame interval.
            var timeout: Double?
            if host.isAnimating {
                let sinceFrame = ContinuousClock.now - lastFrameTime
                let elapsed =
                    Double(sinceFrame.components.seconds)
                    + Double(sinceFrame.components.attoseconds) / 1e18
                timeout = max(1.0 / 60 - elapsed, 0)
            }
            let message: HostMessage?
            do {
                message = try channel.receiveHostMessage(timeout: timeout)
            } catch PreviewChannel.ChannelError.closed {
                return
            }
            tick()
            if let message {
                guard try handle(message) else { return }
            }
            if host.revision != sentRevision {
                try sendFrame()
            }
        }
    }

    private var lastTick = ContinuousClock.now
    private var lastFrameTime = ContinuousClock.now
    private var sentRevision = -1

    /// Advances the host's clock by the real time since the last tick.
    private func tick() {
        let now = ContinuousClock.now
        let elapsed = now - lastTick
        lastTick = now
        host.advanceTime(
            by: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        )
    }

    /// Applies one message. Returns `false` when the session should end.
    func handle(_ message: HostMessage) throws -> Bool {
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
        case .close:
            saveState()
            return false
        }
        return true
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

    private func sendFrame() throws {
        sentRevision = host.revision
        lastFrameTime = ContinuousClock.now
        let clock = ContinuousClock()
        let start = clock.now
        let frame = host.render(scale: scale)
        let rendered = clock.now
        try channel.send(
            .frame(
                PreviewFrame(
                    width: frame.pixelWidth,
                    height: frame.pixelHeight,
                    pixels: frame.pixels
                )
            )
        )
        debugLog("frame: render \(rendered - start), send \(clock.now - rendered)")
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
        do {
            let channel = try PreviewChannel.connect(to: socketPath)
            let savedState = stateFilePath.flatMap {
                FileManager.default.contents(atPath: $0)
            }
            let session = PreviewSession(
                host: ViewHost(anyRootView: content, restoring: savedState),
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
