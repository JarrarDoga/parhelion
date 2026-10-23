import ArgumentParser
import Dispatch
import Foundation
import ParhelionPreview
import ParhelionTooling

/// Options for showing the app on a web page.
struct WebOptions: ParsableArguments {
    @Flag(help: "Serve the preview as a web page, and print its URL.")
    var web = false

    @Option(
        help: """
            The address to serve the web page on. (default: 127.0.0.1) Use a Tailscale \
            address, or 0.0.0.0 for every address, to open the page from other devices.
            """)
    var webAddress: String?

    @Option(help: "The port to serve the web page on, or 0 for any free port. (default: 8417)")
    var webPort: UInt16?

    /// Whether to serve the page: `--web`, or an address or port for it.
    var isEnabled: Bool { web || webAddress != nil || webPort != nil }

    static let defaultAddress = "127.0.0.1"
    static let defaultPort: UInt16 = 8417
    /// How many ports after the default to try when it is taken.
    static let fallbackPorts: UInt16 = 10
}

/// Shows the app on web pages, through a ``WebPreview``.
///
/// Browsers have no vsync, so the host presents on a timer at the
/// simulated screen's frame rate: the frame loop's pacing without vsync,
/// with a refresh period of one screen frame.
final class WebHost: PreviewSurface {
    let preview: WebPreview
    let hasVSync = false
    private(set) var refreshPeriod = FramePacer.defaultRefreshPeriod
    private let interruption = Interruption()

    /// Starts the server. Unless the options name a port, it tries the
    /// ports after the default when the default is taken.
    init(options: WebOptions, bezel: Bool) throws {
        let address = options.webAddress ?? WebOptions.defaultAddress
        let ports =
            options.webPort.map { [$0] }
            ?? Array(WebOptions.defaultPort...(WebOptions.defaultPort + WebOptions.fallbackPorts))
        let log: (@Sendable (String) -> Void)? =
            isDebugLogging ? { @Sendable message in debugLog(message) } : nil
        var lastError: Error?
        for port in ports {
            do {
                preview = try WebPreview(
                    address: address, port: port, showsBezel: bezel, log: log)
                interruption.onInterrupt = { [preview] in preview.wake() }
                return
            } catch let error as WebServer.ServerError where error.isAddressInUse {
                lastError = error
            }
        }
        throw lastError!
    }

    /// The lines that tell the user where to open the page.
    var announcement: String {
        var lines = ["Open the preview in a browser:"] + preview.urls.map { "  \($0)" }
        if !Self.isLoopback(preview.urls) {
            lines.append(
                "Anyone who can reach this address and has the URL can control the app.")
        }
        return lines.joined(separator: "\n")
    }

    private static func isLoopback(_ urls: [String]) -> Bool {
        urls.allSatisfy { $0.hasPrefix("http://127.") || $0.hasPrefix("http://[::1]") }
    }

    /// Whether Control-C or `SIGTERM` asked the tool to quit.
    var isInterrupted: Bool { interruption.happened }

    var waker: @Sendable () -> Void {
        let preview = preview
        return { preview.wake() }
    }

    func events(waitingUpTo timeout: Double) -> [SurfaceEvent] {
        var events = preview.waitForInput(timeout: timeout).map(SurfaceEvent.input)
        if interruption.happened { events.append(.close) }
        return events
    }

    /// Copies the frame's damaged rectangle for the pages.
    func upload(_ frame: ReceivedFrame) throws -> Bool {
        frame.withPixels { pixels in
            preview.update(
                width: frame.width, height: frame.height, damage: frame.clampedDamage,
                pixels: pixels)
        }
    }

    func present() {
        preview.publish()
    }

    func delay(nanoseconds: UInt64) {
        var remaining = timespec(
            tv_sec: Int(nanoseconds / 1_000_000_000), tv_nsec: Int(nanoseconds % 1_000_000_000))
        var left = timespec()
        while nanosleep(&remaining, &left) != 0, errno == EINTR { remaining = left }
    }

    /// Paces at the new app's screen rate, and sends the pages its size and
    /// shape.
    func show(_ hello: PreviewHello) {
        let rate = max(hello.maximumFramesPerSecond ?? 60, 1)
        refreshPeriod = 1_000_000_000 / UInt64(rate)
        preview.setApp(hello)
    }

    func setStatus(_ status: PreviewStatus) {
        preview.setStatus(status)
    }
}

/// The window and web pages at once: the window paces the frames, and the
/// pages get each frame the window shows. Input comes from both.
final class MirroredSurface: PreviewSurface {
    let window: WindowHost
    let web: WebHost

    init(window: WindowHost, web: WebHost) {
        self.window = window
        self.web = web
        web.preview.setInputWaker(window.waker)
    }

    var hasVSync: Bool { window.hasVSync }
    var refreshPeriod: UInt64 { window.refreshPeriod }
    var waker: @Sendable () -> Void { window.waker }

    func events(waitingUpTo timeout: Double) -> [SurfaceEvent] {
        window.events(waitingUpTo: timeout) + web.events(waitingUpTo: 0)
    }

    func upload(_ frame: ReceivedFrame) throws -> Bool {
        let shown = try window.upload(frame)
        _ = try web.upload(frame)
        return shown
    }

    func present() {
        window.present()
        web.present()
    }

    func delay(nanoseconds: UInt64) {
        window.delay(nanoseconds: nanoseconds)
    }

    func show(_ hello: PreviewHello) {
        window.show(hello)
        web.show(hello)
    }

    func setStatus(_ status: PreviewStatus) {
        window.setStatus(status)
        web.setStatus(status)
    }
}

/// Turns Control-C and `SIGTERM` into a request to close, so the tool
/// stops the app the way closing the window does. A window gets this from
/// SDL; a web host has no window. Dispatch catches the signals with a
/// handler of its own, which `exec` resets, so the app and builds still
/// get the default handling.
final class Interruption: @unchecked Sendable {
    private let lock = NSLock()
    private var interrupted = false
    private var sources: [DispatchSourceSignal] = []
    var onInterrupt: (@Sendable () -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }
    private var handler: (@Sendable () -> Void)?

    init() {
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [self] in
                let handler = lock.withLock {
                    interrupted = true
                    return self.handler
                }
                handler?()
            }
            source.resume()
            sources.append(source)
        }
    }

    /// Whether a signal arrived.
    var happened: Bool {
        lock.withLock { interrupted }
    }
}
