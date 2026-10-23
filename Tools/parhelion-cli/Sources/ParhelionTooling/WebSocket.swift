import Foundation

/// The WebSocket protocol (RFC 6455), as the web preview's server speaks
/// it: the opening handshake's accept value, frames the server sends, and
/// messages assembled from the frames a browser sends.
public enum WebSocket {
    /// The kind of a frame.
    public enum Opcode: UInt8, Sendable {
        case continuation = 0
        case text = 1
        case binary = 2
        case close = 8
        case ping = 9
        case pong = 10

        var isControl: Bool { rawValue >= 8 }
    }

    /// A complete message from the browser.
    public enum Message: Equatable, Sendable {
        case text(String)
        case binary([UInt8])
        case ping([UInt8])
        case pong([UInt8])
        /// The browser is closing the connection, with a status code if it
        /// gave one.
        case close(code: UInt16?)
    }

    /// Why a browser's frames were refused. Each maps to the status code the
    /// server closes the connection with.
    public enum ProtocolError: Error, Equatable {
        /// A frame broke the protocol: it was not masked, used reserved bits
        /// or an unknown opcode, or fragmented a control frame.
        case malformed
        /// A message was longer than the server accepts.
        case tooLarge
        /// A text message was not UTF-8.
        case invalidText

        /// The status code of the close frame that reports the error.
        public var closeCode: UInt16 {
            switch self {
            case .malformed: 1002
            case .tooLarge: 1009
            case .invalidText: 1007
            }
        }
    }

    /// The GUID that RFC 6455 appends to the client's key.
    static let acceptGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    /// The `Sec-WebSocket-Accept` value that answers a client's
    /// `Sec-WebSocket-Key`.
    public static func acceptValue(forKey key: String) -> String {
        Data(SHA1.hash(Array((key + acceptGUID).utf8))).base64EncodedString()
    }

    /// A frame from the server: final, unmasked, with the payload length in
    /// the shortest form.
    public static func frame(_ opcode: Opcode, payload: [UInt8]) -> [UInt8] {
        var bytes = frameHeader(opcode, payloadLength: payload.count)
        bytes += payload
        return bytes
    }

    /// The header of a frame from the server, for a payload written after it.
    public static func frameHeader(_ opcode: Opcode, payloadLength length: Int) -> [UInt8] {
        var bytes: [UInt8] = [0x80 | opcode.rawValue]
        switch length {
        case 0..<126:
            bytes.append(UInt8(length))
        case 126...0xFFFF:
            bytes.append(126)
            bytes.append(UInt8(length >> 8))
            bytes.append(UInt8(length & 0xFF))
        default:
            bytes.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: UInt64(length) >> UInt64(shift)))
            }
        }
        return bytes
    }

    /// A close frame with a status code.
    public static func closeFrame(code: UInt16) -> [UInt8] {
        frame(.close, payload: [UInt8(code >> 8), UInt8(code & 0xFF)])
    }

    /// Assembles messages from the bytes a browser sends.
    ///
    /// Feed it bytes as they arrive with ``append(_:)`` and take messages
    /// with ``next()``. Browsers mask every frame and may split a message
    /// into fragments, and may send control frames between the fragments.
    public struct Decoder: Sendable {
        /// The longest message accepted, in bytes.
        public let maximumMessageSize: Int
        private var buffer: [UInt8] = []
        private var start = 0
        /// The opcode and payload of a fragmented message in progress.
        private var fragments: (opcode: Opcode, payload: [UInt8])?

        public init(maximumMessageSize: Int) {
            self.maximumMessageSize = maximumMessageSize
        }

        public mutating func append(_ bytes: some Collection<UInt8>) {
            // Drop what earlier messages used; what is left is at most part
            // of one frame.
            if start > 0 {
                buffer.removeFirst(start)
                start = 0
            }
            buffer += bytes
        }

        /// The next complete message, or `nil` until more bytes arrive.
        public mutating func next() throws -> Message? {
            while let frame = try nextFrame() {
                if frame.opcode.isControl {
                    switch frame.opcode {
                    case .ping: return .ping(frame.payload)
                    case .pong: return .pong(frame.payload)
                    default:
                        let code =
                            frame.payload.count >= 2
                            ? UInt16(frame.payload[0]) << 8 | UInt16(frame.payload[1]) : nil
                        return .close(code: code)
                    }
                }
                var opcode = frame.opcode
                var payload = frame.payload
                if opcode == .continuation {
                    guard let started = fragments else { throw ProtocolError.malformed }
                    opcode = started.opcode
                    payload = started.payload + payload
                } else if fragments != nil {
                    throw ProtocolError.malformed
                }
                guard payload.count <= maximumMessageSize else { throw ProtocolError.tooLarge }
                guard frame.fin else {
                    fragments = (opcode, payload)
                    continue
                }
                fragments = nil
                if opcode == .text {
                    guard let text = String(validating: payload, as: UTF8.self) else {
                        throw ProtocolError.invalidText
                    }
                    return .text(text)
                }
                return .binary(payload)
            }
            return nil
        }

        /// The next complete frame, unmasked, or `nil` until more bytes
        /// arrive.
        private mutating func nextFrame() throws -> (fin: Bool, opcode: Opcode, payload: [UInt8])? {
            let available = buffer.count - start
            guard available >= 2 else { return nil }
            let first = buffer[start]
            let second = buffer[start + 1]
            guard first & 0x70 == 0, let opcode = Opcode(rawValue: first & 0x0F),
                second & 0x80 != 0
            else { throw ProtocolError.malformed }
            let fin = first & 0x80 != 0
            var length = Int(second & 0x7F)
            var offset = 2
            if length == 126 {
                guard available >= 4 else { return nil }
                length = Int(buffer[start + 2]) << 8 | Int(buffer[start + 3])
                offset = 4
            } else if length == 127 {
                guard available >= 10 else { return nil }
                var long: UInt64 = 0
                for index in 0..<8 { long = long << 8 | UInt64(buffer[start + 2 + index]) }
                guard long <= UInt64(maximumMessageSize) else { throw ProtocolError.tooLarge }
                length = Int(long)
                offset = 10
            }
            if opcode.isControl, !fin || length > 125 { throw ProtocolError.malformed }
            guard length <= maximumMessageSize else { throw ProtocolError.tooLarge }
            guard available >= offset + 4 + length else { return nil }
            let mask = Array(buffer[(start + offset)..<(start + offset + 4)])
            let payloadStart = start + offset + 4
            var payload = Array(buffer[payloadStart..<(payloadStart + length)])
            for index in payload.indices { payload[index] ^= mask[index & 3] }
            start = payloadStart + length
            return (fin, opcode, payload)
        }
    }
}

/// SHA-1, which the WebSocket handshake needs and nothing else here does.
/// It is not used for security: the accept value only shows that the server
/// understood the handshake.
enum SHA1 {
    static func hash(_ message: [UInt8]) -> [UInt8] {
        var state: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        var data = message
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        let bitLength = UInt64(message.count) * 8
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var words = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: data.count, by: 64) {
            for index in 0..<16 {
                let byte = chunk + index * 4
                words[index] =
                    UInt32(data[byte]) << 24 | UInt32(data[byte + 1]) << 16
                    | UInt32(data[byte + 2]) << 8 | UInt32(data[byte + 3])
            }
            for index in 16..<80 {
                let mixed =
                    words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16]
                words[index] = mixed << 1 | mixed >> 31
            }
            var (a, b, c, d, e) = (state[0], state[1], state[2], state[3], state[4])
            for index in 0..<80 {
                let (f, k): (UInt32, UInt32) =
                    switch index {
                    case 0..<20: ((b & c) | (~b & d), 0x5A82_7999)
                    case 20..<40: (b ^ c ^ d, 0x6ED9_EBA1)
                    case 40..<60: ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC)
                    default: (b ^ c ^ d, 0xCA62_C1D6)
                    }
                let temporary = (a << 5 | a >> 27) &+ f &+ e &+ k &+ words[index]
                e = d
                d = c
                c = b << 30 | b >> 2
                b = a
                a = temporary
            }
            state[0] &+= a
            state[1] &+= b
            state[2] &+= c
            state[3] &+= d
            state[4] &+= e
        }
        return state.flatMap { word in
            [
                UInt8(word >> 24), UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0xFF),
                UInt8(word & 0xFF),
            ]
        }
    }
}
