import Foundation
import ParhelionPreview
import ParhelionRender

#if canImport(Glibc)
import Glibc
#endif

/// What a preview shows about the app besides its frames: the window in
/// its title, a web page above the screen.
public enum PreviewStatus: Equatable, Sendable {
    /// The app is running.
    case running
    /// The app is being built, at the start or after its sources changed.
    case building
    /// The last build failed with these errors; the previous app, if any,
    /// keeps running.
    case buildFailed(String)
    /// No app is running, for the reason given.
    case stopped(String)
}

/// Shows an app on web pages and takes input from them: the web
/// counterpart of the preview window.
///
/// The host copies the damaged part of each frame from the app into a
/// ``FrameBuffer`` with ``update(width:height:damage:pixels:)`` and makes it
/// visible with ``publish()``, where the window would upload and present.
/// Each page has a thread that sends it the union of the damage it has not
/// seen yet, compressed, as soon as the page has acknowledged all but one
/// of the frames sent before. A page on a slow connection therefore gets
/// fewer, larger updates instead of a growing queue, and always the newest
/// pixels.
public final class WebPreview: @unchecked Sendable {
    /// One open page. Its properties are guarded by the preview's lock.
    private final class Page: @unchecked Sendable {
        let connection: WebSocketConnection
        /// The damage the page has not been sent yet.
        var pending: PixelRect?
        /// The last frame sequence number sent and acknowledged.
        var sent: UInt32 = 0
        var acknowledged: UInt32 = 0
        /// The hello, status, and appearance the page has, by revision.
        var helloRevision = -1
        var statusRevision = -1
        var appearanceRevision = -1
        var isOpen = true
        /// What the page shows. Only the page's sending thread uses it.
        var image = PageImage()

        init(connection: WebSocketConnection) {
            self.connection = connection
        }

        var framesInFlight: Int { Int(sent &- acknowledged) }
    }

    /// The token every request must carry.
    public let token: AccessToken
    private let server: WebServer
    private let showsBezel: Bool
    private let condition = NSCondition()
    private var frame = FrameBuffer()
    /// The damage since the last ``publish()``.
    private var unpublished: PixelRect?
    private var hello: PreviewHello?
    private var helloRevision = 0
    private var status = PreviewStatus.running
    private var statusRevision = 0
    private var appearance = PreviewAppearance()
    private var appearanceRevision = 0
    private var pages: [Page] = []
    private var input: [PageInput] = []
    private var woken = false
    private var bezelImage: (revision: Int, png: [UInt8])?
    private var inputWaker: (@Sendable () -> Void)?
    private let log: (@Sendable (String) -> Void)?

    /// How many frames a page may have unacknowledged. More than one keep
    /// frames on the way while the page draws; three keep a 20 Mbit/s link
    /// with a 40 ms round trip busy.
    static let maximumFramesInFlight = 3
    /// The path of the WebSocket that carries frames and input.
    static let socketPath = "/socket"

    /// Starts serving on `address` and `port`.
    ///
    /// - Parameters:
    ///   - showsBezel: Draw the phone around the screen.
    ///   - log: Receives a line for each frame sent, for tracing.
    public init(
        address: String, port: UInt16, showsBezel: Bool, token: AccessToken = .random(),
        log: (@Sendable (String) -> Void)? = nil
    ) throws {
        self.token = token
        self.showsBezel = showsBezel
        self.log = log
        let box = WeakBox<WebPreview>()
        server = try WebServer(
            address: address, port: port, token: token, webSocketPath: Self.socketPath,
            respond: { request in
                box.value?.respond(to: request) ?? .notFound
            },
            acceptWebSocket: { connection in
                box.value?.run(connection)
            })
        box.value = self
        server.start()
    }

    /// The port the server listens on.
    public var port: UInt16 { server.port }

    /// The URLs to open the page at: one for the address the server
    /// listens on, or one for each of the machine's IPv4 addresses when it
    /// listens on all of them.
    public var urls: [String] {
        Self.hosts(listeningOn: server.address).map {
            let host = $0.contains(":") ? "[\($0)]" : $0
            return "http://\(host):\(port)/?token=\(token.value)"
        }
    }

    /// Calls `wake` whenever a page sends input, in addition to waking
    /// ``waitForInput(timeout:)``. A host that waits for other events, such
    /// as a window's, uses it to wake that wait.
    public func setInputWaker(_ wake: @escaping @Sendable () -> Void) {
        condition.withLock { inputWaker = wake }
    }

    /// Stops serving and closes every page.
    public func stop() {
        server.stop()
        let open = condition.withLock {
            for page in pages { page.isOpen = false }
            condition.broadcast()
            return pages
        }
        for page in open { page.connection.shutDown() }
    }

    // MARK: - The app

    /// A new app connected: pages get its hello, with the screen's size and
    /// shape, before its frames.
    public func setApp(_ hello: PreviewHello) {
        condition.withLock {
            guard hello != self.hello else { return }
            self.hello = hello
            helloRevision += 1
            condition.broadcast()
        }
    }

    /// Copies the damaged rectangle of a frame, row-major RGBA of `width` ×
    /// `height` pixels, into the frame the pages are sent.
    public func update(
        width: Int, height: Int, damage: PixelRect, pixels: UnsafeRawBufferPointer
    ) {
        condition.withLock {
            let changed = frame.update(width: width, height: height, damage: damage, from: pixels)
            guard !changed.isEmpty else { return }
            if changed == frame.bounds {
                // A new size, or a whole frame: what came before no longer matters.
                unpublished = changed
            } else {
                unpublished = unpublished.map { $0.union(changed) } ?? changed
            }
        }
    }

    /// Sends what ``update(width:height:damage:pixels:)`` copied since the
    /// last call to every page.
    public func publish() {
        condition.withLock {
            guard let damage = unpublished else { return }
            unpublished = nil
            for page in pages {
                page.pending = page.pending.map { $0.union(damage) } ?? damage
            }
            condition.broadcast()
        }
    }

    /// Shows a status on every page.
    public func setStatus(_ status: PreviewStatus) {
        condition.withLock {
            guard status != self.status else { return }
            self.status = status
            statusRevision += 1
            condition.broadcast()
        }
    }

    /// Shows the simulated device's appearance and text size on every page,
    /// in its controls.
    public func setAppearance(_ appearance: PreviewAppearance) {
        condition.withLock {
            guard appearance != self.appearance else { return }
            self.appearance = appearance
            appearanceRevision += 1
            condition.broadcast()
        }
    }

    /// Waits up to `timeout` seconds for input from a page or a call to
    /// ``wake()``, then returns the input received so far.
    public func waitForInput(timeout: Double) -> [PageInput] {
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        return condition.withLock {
            while input.isEmpty, !woken, condition.wait(until: deadline) {}
            woken = false
            defer { input.removeAll() }
            return input
        }
    }

    /// Ends a wait in ``waitForInput(timeout:)`` early. Any thread can call
    /// it.
    public func wake() {
        condition.withLock {
            woken = true
            condition.broadcast()
        }
    }

    /// The number of pages connected.
    public var pageCount: Int {
        condition.withLock { pages.count }
    }

    // MARK: - Serving

    private func respond(to request: HTTPRequest) -> HTTPResponse {
        switch request.path {
        case "/":
            return HTTPResponse(
                status: 200, reason: "OK",
                headers: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Content-Security-Policy": WebPage.contentSecurityPolicy,
                ],
                body: Array(WebPage.html.utf8))
        case "/bezel.png":
            guard let png = bezelPNG() else { return .notFound }
            return HTTPResponse(
                status: 200, reason: "OK", headers: ["Content-Type": "image/png"], body: png)
        default:
            return .notFound
        }
    }

    /// The phone around the current app's screen, drawn once per app.
    private func bezelPNG() -> [UInt8]? {
        let (hello, revision) = condition.withLock { (self.hello, helloRevision) }
        guard showsBezel, let hello else { return nil }
        let bezel = Self.bezel(for: hello)
        if let image = condition.withLock({ bezelImage }), image.revision == revision {
            return image.png
        }
        let png = bezel.image(scale: hello.scale).pngData()
        condition.withLock { bezelImage = (revision, png) }
        return png
    }

    static func bezel(for hello: PreviewHello) -> DeviceBezel {
        DeviceBezel(
            screenWidth: hello.screenWidth, screenHeight: hello.screenHeight,
            screenCornerRadius: hello.displayCornerRadius ?? 0)
    }

    /// Runs one page's WebSocket: a thread sends it frames while this one
    /// reads its acknowledgements and input.
    private func run(_ connection: WebSocketConnection) {
        let page = Page(connection: connection)
        condition.withLock {
            if !frame.isEmpty { page.pending = frame.bounds }
            pages.append(page)
        }
        let sender = Thread { [self] in send(to: page) }
        sender.start()
        while let message = connection.receive() {
            guard case .text(let text) = message, let decoded = PageMessage(json: text) else {
                continue
            }
            switch decoded {
            case .acknowledge(let sequence):
                condition.withLock {
                    // Only a frame sent and not yet acknowledged counts.
                    if sequence &- page.acknowledged <= page.sent &- page.acknowledged {
                        page.acknowledged = sequence
                    }
                    condition.broadcast()
                }
            case .input(let message):
                receive(.host(message))
            case .appearance(let change):
                receive(.appearance(change))
            }
        }
        condition.withLock {
            page.isOpen = false
            pages.removeAll { $0 === page }
            condition.broadcast()
        }
    }

    /// Queues input from a page and wakes whoever waits for it.
    private func receive(_ received: PageInput) {
        let wake = condition.withLock {
            input.append(received)
            condition.broadcast()
            return inputWaker
        }
        wake?()
    }

    /// Sends a page its hello, status, appearance, and frames as they
    /// change, until it closes.
    private func send(to page: Page) {
        while true {
            var texts: [String] = []
            var work: (sequence: UInt32, width: Int, height: Int, rect: PixelRect, pixels: [UInt8])?
            condition.lock()
            while page.isOpen {
                if page.helloRevision != helloRevision, let hello {
                    page.helloRevision = helloRevision
                    texts.append(helloJSON(hello, revision: helloRevision))
                }
                if page.statusRevision != statusRevision {
                    page.statusRevision = statusRevision
                    texts.append(Self.statusJSON(status))
                }
                if page.appearanceRevision != appearanceRevision {
                    page.appearanceRevision = appearanceRevision
                    texts.append(Self.appearanceJSON(appearance))
                }
                if let pending = page.pending, !frame.isEmpty,
                    page.framesInFlight < Self.maximumFramesInFlight
                {
                    let rect = pending.clamped(width: frame.width, height: frame.height)
                    page.pending = nil
                    if !rect.isEmpty {
                        page.sent &+= 1
                        work = (page.sent, frame.width, frame.height, rect, frame.region(rect))
                    }
                }
                if !texts.isEmpty || work != nil { break }
                condition.wait()
            }
            let isOpen = page.isOpen
            condition.unlock()
            guard isOpen else { return }
            for text in texts { page.connection.send(text: text) }
            if let work {
                let start = PreviewClock.now()
                let parts = page.image.parts(
                    for: work.rect, new: work.pixels, frameWidth: work.width,
                    frameHeight: work.height)
                let message = FrameMessage.encode(
                    sequence: work.sequence, width: work.width, height: work.height, parts: parts)
                let encoded = PreviewClock.now()
                page.connection.send(binary: message)
                log?(
                    String(
                        format:
                            "page frame %u: %d × %d damaged, %@, %d bytes, encode %.3f ms, "
                            + "send %.3f ms",
                        work.sequence, work.rect.width, work.rect.height,
                        Self.describe(parts), message.count,
                        PreviewClock.milliseconds(encoded - start),
                        PreviewClock.milliseconds(PreviewClock.now() - encoded)))
            }
        }
    }

    /// The parts of a frame, for the trace: the rows copied and sent.
    static func describe(_ parts: [FrameMessage.Part]) -> String {
        let copied = parts.reduce(0) {
            if case .copy(let rect, _, _) = $1 { $0 + rect.height } else { $0 }
        }
        let sent = parts.reduce(0) {
            if case .pixels(let rect, _, _) = $1 { $0 + rect.height } else { $0 }
        }
        return "\(copied) rows copied, \(sent) sent in \(parts.count) parts"
    }

    private func helloJSON(_ hello: PreviewHello, revision: Int) -> String {
        var object: [String: Any] = [
            "type": "hello",
            "revision": revision,
            "appName": hello.appName,
            "screenWidth": hello.screenWidth,
            "screenHeight": hello.screenHeight,
            "cornerRadius": hello.displayCornerRadius ?? 0,
        ]
        object["deviceName"] = hello.deviceName
        if showsBezel {
            let bezel = Self.bezel(for: hello)
            object["bezel"] = [
                "margin": DeviceBezel.margin, "width": bezel.width, "height": bezel.height,
            ]
        }
        return Self.json(object)
    }

    static func statusJSON(_ status: PreviewStatus) -> String {
        switch status {
        case .running: json(["type": "status", "state": "running"])
        case .building: json(["type": "status", "state": "building"])
        case .buildFailed(let errors):
            json(["type": "status", "state": "buildFailed", "message": errors])
        case .stopped(let reason): json(["type": "status", "state": "stopped", "message": reason])
        }
    }

    static func appearanceJSON(_ appearance: PreviewAppearance) -> String {
        json([
            "type": "appearance", "colorScheme": appearance.colorScheme,
            "dynamicTypeSize": appearance.dynamicTypeSize,
            "dynamicTypeSizes": PreviewAppearance.dynamicTypeSizes,
        ])
    }

    static func json(_ object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// The hosts a page can reach the server at.
    static func hosts(listeningOn address: String) -> [String] {
        guard address == "0.0.0.0" || address == "::" else {
            return [address == "localhost" ? "127.0.0.1" : address]
        }
        var hosts: [String] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return ["127.0.0.1"] }
        defer { freeifaddrs(interfaces) }
        var cursor = interfaces
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            guard let socketAddress = interface.pointee.ifa_addr,
                socketAddress.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard
                getnameinfo(
                    socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size), &name,
                    socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let host = String(
                decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !hosts.contains(host) { hosts.append(host) }
        }
        // Loopback first: it works from this machine.
        return hosts.sorted { ($0 == "127.0.0.1" ? 0 : 1) < ($1 == "127.0.0.1" ? 0 : 1) }
    }
}

/// What a page asks for: input for the app, or a change to the simulated
/// device's appearance or text size, which the tool keeps and passes on.
public enum PageInput: Equatable, Sendable {
    case host(HostMessage)
    case appearance(PreviewAppearance.Change)
}

/// A message from the page.
enum PageMessage: Equatable {
    /// The page drew the frame with this sequence number.
    case acknowledge(UInt32)
    /// Input for the app.
    case input(HostMessage)
    /// A change to the appearance or the text size, from the page's
    /// controls.
    case appearance(PreviewAppearance.Change)

    /// The most text one message may type.
    static let maximumTextLength = 4096

    /// Keys the page may press, as `ViewHost.Key` names them.
    static let keys: Set<String> = [
        "backspace", "delete", "left", "right", "home", "end", "tab", "backTab", "return", "escape",
    ]

    /// The fields a message may have.
    private struct Fields: Decodable {
        var type: String
        var sequence: UInt32?
        var x: Double?
        var y: Double?
        var dx: Double?
        var dy: Double?
        var text: String?
        var key: String?
        var colorScheme: String?
        var dynamicTypeSize: String?
    }

    /// Decodes a message such as `{"type":"down","x":10,"y":20}`, or returns
    /// `nil` for anything the page should not send. Pages can only send
    /// input and appearance changes; commands, ticks, and the other host
    /// messages are refused.
    init?(json text: String) {
        guard let fields = try? JSONDecoder().decode(Fields.self, from: Data(text.utf8)) else {
            return nil
        }
        func coordinate(_ value: Double?) -> Double? {
            value.flatMap { abs($0) < 1e6 ? $0 : nil }
        }
        switch fields.type {
        case "ack":
            guard let sequence = fields.sequence else { return nil }
            self = .acknowledge(sequence)
        case "down", "move", "up":
            guard let x = coordinate(fields.x), let y = coordinate(fields.y) else { return nil }
            switch fields.type {
            case "down": self = .input(.pointerDown(x: x, y: y))
            case "move": self = .input(.pointerMoved(x: x, y: y))
            default: self = .input(.pointerUp(x: x, y: y))
            }
        case "scroll":
            guard let dx = coordinate(fields.dx), let dy = coordinate(fields.dy),
                let x = coordinate(fields.x), let y = coordinate(fields.y)
            else { return nil }
            self = .input(.scroll(dx: dx, dy: dy, x: x, y: y))
        case "text":
            guard let text = fields.text, !text.isEmpty, text.count <= Self.maximumTextLength
            else { return nil }
            self = .input(.text(text))
        case "key":
            guard let key = fields.key, Self.keys.contains(key) else { return nil }
            self = .input(.key(key))
        case "appearance":
            let change = PreviewAppearance.Change.set(
                colorScheme: fields.colorScheme, dynamicTypeSize: fields.dynamicTypeSize)
            guard fields.colorScheme != nil || fields.dynamicTypeSize != nil,
                PreviewAppearance().applying(change) != nil
            else { return nil }
            self = .appearance(change)
        default:
            return nil
        }
    }
}

/// A weak reference, for closures that must not keep their owner alive.
final class WeakBox<Value: AnyObject>: @unchecked Sendable {
    weak var value: Value?
}
