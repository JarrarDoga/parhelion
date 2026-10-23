#if canImport(Foundation)
import Foundation
#endif

/// The name of the environment variable that tells an app to run as a
/// preview. Its value is the path of the window host's socket.
public let previewSocketEnvironmentKey = "PARHELION_PREVIEW_SOCKET"

/// The name of the environment variable that holds the path of a state
/// file. The app restores state from the file when it starts and saves state
/// to it when the host closes it, so hot reload keeps state across restarts.
public let previewStateEnvironmentKey = "PARHELION_PREVIEW_STATE"

/// The name of the environment variable that names the device an app
/// simulates, such as "iPhone 17 Pro". Without it, the app uses its default
/// device.
public let previewDeviceEnvironmentKey = "PARHELION_DEVICE"

/// Optional parts of the protocol. An app lists the ones it supports in its
/// ``PreviewHello``, and a window host that supports them too answers with
/// ``HostMessage/welcome(_:)``. A host sends the newer messages only after
/// that, so apps and hosts built before a capability existed keep working.
public enum PreviewCapability {
    /// The host paces animation: it sends ``HostMessage/tick(_:)`` after each
    /// display refresh, and the app draws for the tick's target time.
    public static let hostClock = "hostClock"
    /// Frames travel through shared memory: the app sends
    /// ``AppMessage/sharedMemory(_:)`` once, then small
    /// ``AppMessage/frameUpdate(_:)`` messages that name a slot.
    public static let sharedFrames = "sharedFrames"
    /// Every capability this version of Parhelion supports.
    public static let all = [hostClock, sharedFrames]
}

/// The first message an app sends after it connects.
public struct PreviewHello: Codable, Equatable, Sendable {
    /// The app's display name, for the window title.
    public var appName: String
    /// The screen size in points.
    public var screenWidth: Double
    public var screenHeight: Double
    /// Pixels per point in the frames the app sends.
    public var scale: Double
    /// The name of the device the app simulates. Apps built with Parhelion
    /// before device names were sent leave it out.
    public var deviceName: String?
    /// The radius of the screen's rounded corners in points, which the
    /// window host uses to draw the device around the screen.
    public var displayCornerRadius: Double?
    /// The most frames the simulated screen shows per second. The window
    /// host shows the app no faster. Apps built before devices had a frame
    /// rate leave it out, and the host then shows every refresh.
    public var maximumFramesPerSecond: Int?
    /// The ``PreviewCapability`` values the app supports. Apps built before
    /// capabilities existed leave it out.
    public var capabilities: [String]?

    public init(
        appName: String,
        screenWidth: Double,
        screenHeight: Double,
        scale: Double,
        deviceName: String? = nil,
        displayCornerRadius: Double? = nil,
        maximumFramesPerSecond: Int? = nil,
        capabilities: [String]? = nil
    ) {
        self.appName = appName
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.scale = scale
        self.deviceName = deviceName
        self.displayCornerRadius = displayCornerRadius
        self.maximumFramesPerSecond = maximumFramesPerSecond
        self.capabilities = capabilities
    }
}

/// The host's answer to a hello that lists capabilities: the ones the host
/// will use with this app.
public struct PreviewWelcome: Codable, Equatable, Sendable {
    /// The ``PreviewCapability`` values both sides support.
    public var capabilities: [String]

    public init(capabilities: [String]) {
        self.capabilities = capabilities
    }
}

/// One rendered frame: RGBA pixels, four bytes each, row-major from the
/// top-left corner.
public struct PreviewFrame: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// A rectangle of pixels in a frame.
public struct PixelRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A frame for a host that sent ``HostMessage/welcome(_:)``. Unlike
/// ``PreviewFrame``, it says whether the app is still animating and which
/// tick it answers, and its pixels can stay in shared memory.
public struct PreviewFrameUpdate: Equatable, Sendable {
    /// Where the pixels are.
    public enum Pixels: Equatable, Sendable {
        /// In a slot of the shared memory the app announced with
        /// ``AppMessage/sharedMemory(_:)``. The host answers with
        /// ``HostMessage/releaseSlot(_:)`` once it has copied them.
        case slot(Int)
        /// In the message itself, when shared memory is not available.
        case inline([UInt8])
        /// Nowhere: nothing changed since the last frame. The app sends this
        /// to answer a tick that moved nothing, so the host still learns
        /// whether the app is animating.
        case unchanged
    }

    public var width: Int
    public var height: Int
    /// The part of the frame that changed since the last frame.
    public var damage: PixelRect
    /// Whether anything is still moving, so the host should keep ticking.
    public var isAnimating: Bool
    /// The ``PreviewTick/targetTime`` of the tick this frame answers, or 0
    /// for a frame drawn because of input.
    public var targetTime: UInt64
    public var pixels: Pixels

    public init(
        width: Int, height: Int, damage: PixelRect? = nil, isAnimating: Bool,
        targetTime: UInt64 = 0, pixels: Pixels
    ) {
        self.width = width
        self.height = height
        self.damage = damage ?? PixelRect(x: 0, y: 0, width: width, height: height)
        self.isAnimating = isAnimating
        self.targetTime = targetTime
        self.pixels = pixels
    }
}

/// Shared memory that holds frames: `slotCount` slots of `slotSize` bytes
/// each, in a file whose descriptor travels with the message.
public struct PreviewSharedMemory: Equatable, Sendable {
    /// The file descriptor. On the sending side it is the sender's own; on
    /// the receiving side it is a new descriptor that the receiver owns.
    public var descriptor: Int32
    public var slotCount: Int
    public var slotSize: Int

    public init(descriptor: Int32, slotCount: Int, slotSize: Int) {
        self.descriptor = descriptor
        self.slotCount = slotCount
        self.slotSize = slotSize
    }
}

/// The host's clock signal after a display refresh. Times are nanoseconds
/// of the monotonic clock that every process on the machine shares; see
/// ``PreviewClock``.
public struct PreviewTick: Codable, Equatable, Sendable {
    /// When the next frame the app draws will be on screen. The app moves
    /// animations to this time before it draws.
    public var targetTime: UInt64
    /// The display's refresh period.
    public var refreshPeriod: UInt64

    public init(targetTime: UInt64, refreshPeriod: UInt64) {
        self.targetTime = targetTime
        self.refreshPeriod = refreshPeriod
    }
}

/// A message from the app to the window host.
public enum AppMessage: Equatable, Sendable {
    case hello(PreviewHello)
    /// A frame for a host that did not send ``HostMessage/welcome(_:)``.
    case frame(PreviewFrame)
    /// The answer to a ``HostMessage/command(id:_:)``.
    case reply(id: Int, PreviewReply)
    /// Announces the shared memory whose slots later frame updates name.
    case sharedMemory(PreviewSharedMemory)
    /// A frame for a host that sent ``HostMessage/welcome(_:)``.
    case frameUpdate(PreviewFrameUpdate)
}

/// A request from a tool, such as an agent server, that the app answers
/// with a ``PreviewReply``. Node identifiers are ``ViewNode`` IDs as text.
public enum PreviewCommand: Codable, Equatable, Sendable {
    /// The view tree, as an outline with identifiers and frames, or as JSON.
    case inspect(json: Bool)
    /// The screen as a PNG image at a number of pixels per point.
    case screenshot(scale: Double)
    /// Taps the node with an identifier.
    case tapNode(id: String)
    /// Taps the one button whose label is exactly `label`.
    case tapButton(label: String)
    /// Taps whatever is at a point on the screen.
    case tapPoint(x: Double, y: Double)
    /// Focuses a text field, or ends editing when `id` is `nil`.
    case focus(id: String?)
    /// Types text into the focused text field.
    case typeText(String)
    /// Presses an editing or focus key, by its `ViewHost.Key` name.
    case pressKey(String)
    /// Scrolls the scroll view at a point by `dx`, `dy` points.
    case scroll(dx: Double, dy: Double, x: Double, y: Double)
    /// Scrolls a scroll view to an offset.
    case scrollTo(id: String, x: Double, y: Double)
    /// Drags from one point to another over `duration` seconds, as a finger
    /// would. A fast drag over a scroll view leaves it moving.
    case drag(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double)
}

/// The app's answer to a ``PreviewCommand``.
public struct PreviewReply: Codable, Equatable, Sendable {
    /// Whether the command succeeded.
    public var ok: Bool
    /// What happened, or the error.
    public var message: String
    /// The image, for screenshots.
    public var png: Data?
    /// The app's revision after the command.
    public var revision: Int
    /// Whether anything is still moving, such as scroll momentum.
    public var isAnimating: Bool
    /// How many `task` actions of the views on screen have not finished, or
    /// `nil` from an app built before replies reported them.
    public var pendingTasks: Int?

    public init(
        ok: Bool, message: String, png: Data? = nil, revision: Int, isAnimating: Bool,
        pendingTasks: Int? = nil
    ) {
        self.ok = ok
        self.message = message
        self.png = png
        self.revision = revision
        self.isAnimating = isAnimating
        self.pendingTasks = pendingTasks
    }
}

/// A message from the window host to the app. Positions are in points,
/// relative to the top-left corner of the screen.
public enum HostMessage: Codable, Equatable, Sendable {
    /// A mouse button or finger went down.
    case pointerDown(x: Double, y: Double)
    /// The pointer moved while it was down.
    case pointerMoved(x: Double, y: Double)
    /// The mouse button or finger was released.
    case pointerUp(x: Double, y: Double)
    /// The mouse wheel or trackpad scrolled the content by `dx`, `dy` points
    /// at the pointer position `x`, `y`. A positive `dy` scrolls toward the
    /// end of the content.
    case scroll(dx: Double, dy: Double, x: Double, y: Double)
    /// Text typed on the keyboard, after keyboard layout and input methods.
    case text(String)
    /// An editing or focus key: `backspace`, `delete`, `left`, `right`,
    /// `home`, `end`, `tab`, `backTab`, `return`, or `escape`.
    case key(String)
    /// A request that the app answers with ``AppMessage/reply(id:_:)``.
    case command(id: Int, PreviewCommand)
    /// The host is closing; the app should exit.
    case close
    /// The capabilities the host will use, in answer to a hello that listed
    /// some. Only apps that list capabilities receive it.
    case welcome(PreviewWelcome)
    /// A display refresh happened; draw for the target time. Only apps
    /// welcomed with ``PreviewCapability/hostClock`` receive it.
    case tick(PreviewTick)
    /// The host has copied a shared-memory slot, so the app can draw into it
    /// again. Only apps welcomed with ``PreviewCapability/sharedFrames``
    /// receive it.
    case releaseSlot(Int)
}

/// The wire format: each message is a 4-byte big-endian length, a 1-byte
/// kind, and a payload of `length - 1` bytes.
///
/// Control messages are JSON. Frames, frame updates, ticks, and slot
/// releases are binary, with big-endian integers. Kinds after `reply` are
/// sent only to a peer that negotiated them, because older peers treat an
/// unknown kind as a broken connection.
enum WireKind: UInt8 {
    case hello = 1
    /// The width and height as 4-byte integers, then the pixels.
    case frame = 2
    case host = 3
    case reply = 4
    /// JSON slot count and size; the descriptor travels as `SCM_RIGHTS`.
    case sharedMemory = 5
    /// A ``FrameUpdateHeader``, then the pixels if they are inline.
    case frameUpdate = 6
    /// The target time and the refresh period, as 8-byte integers.
    case tick = 7
    /// The slot index as a 4-byte integer.
    case releaseSlot = 8
}

/// A message ready to write: the bytes up to the pixels, the pixels, which
/// are written from their own storage without copying, and a descriptor to
/// pass along with the first byte.
struct EncodedMessage {
    var head: [UInt8]
    var pixels: [UInt8]?
    var descriptor: Int32?
}

/// The envelope of a reply on the wire.
private struct EncodedReply: Codable {
    var id: Int
    var reply: PreviewReply
}

/// The JSON part of a shared-memory announcement.
private struct EncodedSharedMemory: Codable {
    var slotCount: Int
    var slotSize: Int
}

/// The fixed part of a frame update on the wire: flags (bit 0: animating),
/// where the pixels are (0: slot, 1: inline, 2: unchanged), the slot, the
/// width and height, the damage rectangle, and the target time.
enum FrameUpdateHeader {
    static let size = 1 + 1 + 4 + 4 + 4 + 16 + 8
}

enum MessageCoding {
    static func encode(_ message: AppMessage) throws -> EncodedMessage {
        switch message {
        case .hello(let hello):
            return EncodedMessage(head: envelope(.hello, try json(hello)))
        case .reply(let id, let reply):
            return EncodedMessage(
                head: envelope(.reply, try json(EncodedReply(id: id, reply: reply))))
        case .frame(let frame):
            var prefix: [UInt8] = []
            prefix.appendBigEndian(UInt32(frame.width))
            prefix.appendBigEndian(UInt32(frame.height))
            return EncodedMessage(
                head: envelope(.frame, prefix, extra: frame.pixels.count), pixels: frame.pixels)
        case .sharedMemory(let memory):
            let payload = try json(
                EncodedSharedMemory(slotCount: memory.slotCount, slotSize: memory.slotSize))
            return EncodedMessage(
                head: envelope(.sharedMemory, payload), descriptor: memory.descriptor)
        case .frameUpdate(let update):
            var prefix: [UInt8] = []
            prefix.reserveCapacity(FrameUpdateHeader.size)
            prefix.append(update.isAnimating ? 1 : 0)
            var slot: UInt32 = 0
            var pixels: [UInt8]?
            switch update.pixels {
            case .slot(let index):
                prefix.append(0)
                slot = UInt32(index)
            case .inline(let bytes):
                prefix.append(1)
                pixels = bytes
            case .unchanged:
                prefix.append(2)
            }
            prefix.appendBigEndian(slot)
            prefix.appendBigEndian(UInt32(update.width))
            prefix.appendBigEndian(UInt32(update.height))
            prefix.appendBigEndian(UInt32(update.damage.x))
            prefix.appendBigEndian(UInt32(update.damage.y))
            prefix.appendBigEndian(UInt32(update.damage.width))
            prefix.appendBigEndian(UInt32(update.damage.height))
            prefix.appendBigEndian(update.targetTime)
            return EncodedMessage(
                head: envelope(.frameUpdate, prefix, extra: pixels?.count ?? 0), pixels: pixels)
        }
    }

    static func encode(_ message: HostMessage) throws -> EncodedMessage {
        switch message {
        case .tick(let tick):
            var payload: [UInt8] = []
            payload.appendBigEndian(tick.targetTime)
            payload.appendBigEndian(tick.refreshPeriod)
            return EncodedMessage(head: envelope(.tick, payload))
        case .releaseSlot(let slot):
            var payload: [UInt8] = []
            payload.appendBigEndian(UInt32(slot))
            return EncodedMessage(head: envelope(.releaseSlot, payload))
        default:
            return EncodedMessage(head: envelope(.host, try json(message)))
        }
    }

    /// How many bytes of a message's payload to read before its pixels, for
    /// the kinds that carry pixels. The pixels are then read straight into
    /// their own array.
    static func prefixLength(of kind: UInt8) -> Int {
        switch WireKind(rawValue: kind) {
        case .frame: 8
        case .frameUpdate: FrameUpdateHeader.size
        default: 0
        }
    }

    /// Decodes a message from the app. `prefix` holds the bytes before the
    /// pixels (see ``prefixLength(of:)``) and `body` the rest. `descriptor`
    /// takes the next descriptor that arrived with the message.
    static func decodeAppMessage(
        kind: UInt8, prefix: [UInt8], body: [UInt8], descriptor: () -> Int32?
    ) throws -> AppMessage {
        switch WireKind(rawValue: kind) {
        case .hello:
            return .hello(try JSONDecoder().decode(PreviewHello.self, from: Data(body)))
        case .reply:
            let decoded = try JSONDecoder().decode(EncodedReply.self, from: Data(body))
            return .reply(id: decoded.id, decoded.reply)
        case .frame:
            guard prefix.count == 8 else { throw PreviewChannel.ChannelError.malformedMessage }
            let width = Int(prefix.readBigEndian(at: 0))
            let height = Int(prefix.readBigEndian(at: 4))
            guard body.count == width * height * 4 else {
                throw PreviewChannel.ChannelError.malformedMessage
            }
            return .frame(PreviewFrame(width: width, height: height, pixels: body))
        case .sharedMemory:
            let decoded = try JSONDecoder().decode(EncodedSharedMemory.self, from: Data(body))
            guard let received = descriptor() else {
                throw PreviewChannel.ChannelError.malformedMessage
            }
            return .sharedMemory(
                PreviewSharedMemory(
                    descriptor: received, slotCount: decoded.slotCount,
                    slotSize: decoded.slotSize))
        case .frameUpdate:
            guard prefix.count == FrameUpdateHeader.size else {
                throw PreviewChannel.ChannelError.malformedMessage
            }
            let width = Int(prefix.readBigEndian(at: 6))
            let height = Int(prefix.readBigEndian(at: 10))
            let pixels: PreviewFrameUpdate.Pixels
            switch prefix[1] {
            case 0: pixels = .slot(Int(prefix.readBigEndian(at: 2)))
            case 1:
                guard body.count == width * height * 4 else {
                    throw PreviewChannel.ChannelError.malformedMessage
                }
                pixels = .inline(body)
            case 2: pixels = .unchanged
            default: throw PreviewChannel.ChannelError.malformedMessage
            }
            return .frameUpdate(
                PreviewFrameUpdate(
                    width: width,
                    height: height,
                    damage: PixelRect(
                        x: Int(prefix.readBigEndian(at: 14)),
                        y: Int(prefix.readBigEndian(at: 18)),
                        width: Int(prefix.readBigEndian(at: 22)),
                        height: Int(prefix.readBigEndian(at: 26))),
                    isAnimating: prefix[0] & 1 != 0,
                    targetTime: prefix.readBigEndian64(at: 30),
                    pixels: pixels))
        default:
            throw PreviewChannel.ChannelError.malformedMessage
        }
    }

    static func decodeHostMessage(kind: UInt8, body: [UInt8]) throws -> HostMessage {
        switch WireKind(rawValue: kind) {
        case .host:
            return try JSONDecoder().decode(HostMessage.self, from: Data(body))
        case .tick:
            guard body.count == 16 else { throw PreviewChannel.ChannelError.malformedMessage }
            return .tick(
                PreviewTick(
                    targetTime: body.readBigEndian64(at: 0),
                    refreshPeriod: body.readBigEndian64(at: 8)))
        case .releaseSlot:
            guard body.count == 4 else { throw PreviewChannel.ChannelError.malformedMessage }
            return .releaseSlot(Int(body.readBigEndian(at: 0)))
        default:
            throw PreviewChannel.ChannelError.malformedMessage
        }
    }

    private static func json(_ value: some Encodable) throws -> [UInt8] {
        [UInt8](try JSONEncoder().encode(value))
    }

    /// The length, the kind, and `payload`. `extra` counts payload bytes that
    /// follow separately, such as pixels.
    private static func envelope(_ kind: WireKind, _ payload: [UInt8], extra: Int = 0) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(5 + payload.count)
        bytes.appendBigEndian(UInt32(payload.count + extra + 1))
        bytes.append(kind.rawValue)
        bytes += payload
        return bytes
    }
}

extension Array where Element == UInt8 {
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func appendBigEndian(_ value: UInt64) {
        appendBigEndian(UInt32(truncatingIfNeeded: value >> 32))
        appendBigEndian(UInt32(truncatingIfNeeded: value))
    }

    func readBigEndian(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
    }

    func readBigEndian64(at offset: Int) -> UInt64 {
        UInt64(readBigEndian(at: offset)) << 32 | UInt64(readBigEndian(at: offset + 4))
    }
}
