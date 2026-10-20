#if canImport(Foundation)
import Foundation
#endif

/// The name of the environment variable that tells an app to run as a
/// preview. Its value is the path of the window host's socket.
public let previewSocketEnvironmentKey = "PARHELION_PREVIEW_SOCKET"

/// The first message an app sends after it connects.
public struct PreviewHello: Codable, Equatable, Sendable {
    /// The app's display name, for the window title.
    public var appName: String
    /// The screen size in points.
    public var screenWidth: Double
    public var screenHeight: Double
    /// Pixels per point in the frames the app sends.
    public var scale: Double

    public init(appName: String, screenWidth: Double, screenHeight: Double, scale: Double) {
        self.appName = appName
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.scale = scale
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

/// A message from the app to the window host.
public enum AppMessage: Equatable, Sendable {
    case hello(PreviewHello)
    case frame(PreviewFrame)
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
    /// The host is closing; the app should exit.
    case close
}

/// The wire format: each message is a 4-byte big-endian length, a 1-byte
/// kind, and a payload of `length - 1` bytes.
///
/// Control messages are JSON. Frames are binary: the width and height as
/// 4-byte big-endian integers, then the pixels.
enum WireKind: UInt8 {
    case hello = 1
    case frame = 2
    case host = 3
}

enum MessageCoding {
    static func encode(_ message: AppMessage) throws -> [UInt8] {
        switch message {
        case .hello(let hello):
            return envelope(.hello, [UInt8](try JSONEncoder().encode(hello)))
        case .frame(let frame):
            var payload: [UInt8] = []
            payload.reserveCapacity(8 + frame.pixels.count)
            payload.appendBigEndian(UInt32(frame.width))
            payload.appendBigEndian(UInt32(frame.height))
            payload += frame.pixels
            return envelope(.frame, payload)
        }
    }

    static func encode(_ message: HostMessage) throws -> [UInt8] {
        envelope(.host, [UInt8](try JSONEncoder().encode(message)))
    }

    static func decodeAppMessage(kind: UInt8, payload: [UInt8]) throws -> AppMessage {
        switch WireKind(rawValue: kind) {
        case .hello:
            return .hello(try JSONDecoder().decode(PreviewHello.self, from: Data(payload)))
        case .frame:
            guard payload.count >= 8 else { throw PreviewChannel.ChannelError.malformedMessage }
            let width = Int(payload.readBigEndian(at: 0))
            let height = Int(payload.readBigEndian(at: 4))
            guard payload.count == 8 + width * height * 4 else {
                throw PreviewChannel.ChannelError.malformedMessage
            }
            return .frame(PreviewFrame(width: width, height: height, pixels: Array(payload[8...])))
        default:
            throw PreviewChannel.ChannelError.malformedMessage
        }
    }

    static func decodeHostMessage(kind: UInt8, payload: [UInt8]) throws -> HostMessage {
        guard WireKind(rawValue: kind) == .host else {
            throw PreviewChannel.ChannelError.malformedMessage
        }
        return try JSONDecoder().decode(HostMessage.self, from: Data(payload))
    }

    private static func envelope(_ kind: WireKind, _ payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(5 + payload.count)
        bytes.appendBigEndian(UInt32(payload.count + 1))
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

    func readBigEndian(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
    }
}
