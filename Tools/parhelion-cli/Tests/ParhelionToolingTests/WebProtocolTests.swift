import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionTooling

/// A frame as a browser sends it: masked, with the shortest length form.
func maskedFrame(
    _ opcode: WebSocket.Opcode, _ payload: [UInt8], fin: Bool = true,
    mask: [UInt8] = [0x37, 0xFA, 0x21, 0x3D]
) -> [UInt8] {
    var bytes: [UInt8] = [(fin ? 0x80 : 0) | opcode.rawValue]
    switch payload.count {
    case 0..<126: bytes.append(0x80 | UInt8(payload.count))
    case 126...0xFFFF:
        bytes += [0x80 | 126, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
    default:
        bytes.append(0x80 | 127)
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: UInt64(payload.count) >> UInt64(shift)))
        }
    }
    bytes += mask
    bytes += payload.enumerated().map { $0.element ^ mask[$0.offset & 3] }
    return bytes
}

@Suite("WebSocket framing")
struct WebSocketTests {
    @Test("SHA-1 matches the standard test vectors")
    func sha1() {
        func hex(_ text: String) -> String {
            SHA1.hash(Array(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        #expect(hex("") == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        #expect(hex("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(
            hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
                == "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    }

    @Test("The handshake answers RFC 6455's sample key")
    func acceptValue() {
        #expect(
            WebSocket.acceptValue(forKey: "dGhlIHNhbXBsZSBub25jZQ==")
                == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test("Server frames use the shortest length form and no mask")
    func frameHeaders() {
        #expect(WebSocket.frameHeader(.text, payloadLength: 0) == [0x81, 0])
        #expect(WebSocket.frameHeader(.binary, payloadLength: 125) == [0x82, 125])
        #expect(WebSocket.frameHeader(.binary, payloadLength: 126) == [0x82, 126, 0, 126])
        #expect(WebSocket.frameHeader(.binary, payloadLength: 65535) == [0x82, 126, 0xFF, 0xFF])
        #expect(
            WebSocket.frameHeader(.binary, payloadLength: 65536)
                == [0x82, 127, 0, 0, 0, 0, 0, 1, 0, 0])
        #expect(WebSocket.frame(.text, payload: Array("hi".utf8)) == [0x81, 2, 104, 105])
        #expect(WebSocket.closeFrame(code: 1009) == [0x88, 2, 0x03, 0xF1])
    }

    @Test("A masked frame decodes to its message: RFC 6455's sample")
    func maskedText() throws {
        var decoder = WebSocket.Decoder(maximumMessageSize: 1024)
        decoder.append([0x81, 0x85, 0x37, 0xFA, 0x21, 0x3D, 0x7F, 0x9F, 0x4D, 0x51, 0x58])
        #expect(try decoder.next() == .text("Hello"))
        #expect(try decoder.next() == nil)
    }

    @Test("Bytes that arrive one at a time make a message only when it is complete")
    func partialFrames() throws {
        let payload = [UInt8](repeating: 7, count: 300)
        let bytes = maskedFrame(.binary, payload) + maskedFrame(.text, Array("next".utf8))
        var decoder = WebSocket.Decoder(maximumMessageSize: 1024)
        var messages: [WebSocket.Message] = []
        for byte in bytes {
            decoder.append([byte])
            while let message = try decoder.next() { messages.append(message) }
        }
        #expect(messages == [.binary(payload), .text("next")])
    }

    @Test("Fragments join into one message, with control frames between them")
    func fragments() throws {
        var decoder = WebSocket.Decoder(maximumMessageSize: 1024)
        decoder.append(maskedFrame(.text, Array("Hel".utf8), fin: false))
        decoder.append(maskedFrame(.ping, [1, 2]))
        decoder.append(maskedFrame(.continuation, Array("lo".utf8)))
        #expect(try decoder.next() == .ping([1, 2]))
        #expect(try decoder.next() == .text("Hello"))
    }

    @Test("A close frame carries its status code")
    func close() throws {
        var decoder = WebSocket.Decoder(maximumMessageSize: 1024)
        decoder.append(maskedFrame(.close, [0x03, 0xE9]))
        decoder.append(maskedFrame(.close, []))
        #expect(try decoder.next() == .close(code: 1001))
        #expect(try decoder.next() == .close(code: nil))
    }

    @Test("Frames that break the protocol are refused")
    func malformed() {
        func error(_ bytes: [UInt8], limit: Int = 1024) -> WebSocket.ProtocolError? {
            var decoder = WebSocket.Decoder(maximumMessageSize: limit)
            decoder.append(bytes)
            do {
                _ = try decoder.next()
                return nil
            } catch {
                return error as? WebSocket.ProtocolError
            }
        }
        // Not masked.
        #expect(error([0x81, 0x02, 104, 105]) == .malformed)
        // Reserved bits.
        #expect(error([0xC1, 0x80, 0, 0, 0, 0]) == .malformed)
        // An unknown opcode.
        #expect(error([0x83, 0x80, 0, 0, 0, 0]) == .malformed)
        // A fragmented control frame.
        #expect(error(maskedFrame(.ping, [], fin: false)) == .malformed)
        // A continuation without a start.
        #expect(error(maskedFrame(.continuation, [1])) == .malformed)
        // Too long, both declared and assembled.
        #expect(
            error(maskedFrame(.binary, [UInt8](repeating: 0, count: 200)), limit: 100) == .tooLarge)
        #expect(error([0x82, 0xFF, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]) == .tooLarge)
        // Not UTF-8.
        #expect(error(maskedFrame(.text, [0xFF, 0xFE])) == .invalidText)
        #expect(WebSocket.ProtocolError.tooLarge.closeCode == 1009)
    }
}

@Suite("HTTP requests and the access token")
struct HTTPTests {
    static let head = Array(
        """
        GET /socket?token=abc%20d&v=2&v=3 HTTP/1.1\r
        Host: 127.0.0.1:8417\r
        Upgrade: websocket\r
        Connection: keep-alive, Upgrade\r
        Sec-WebSocket-Version: 13\r
        Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
        \r

        """.utf8)

    @Test("A request head parses into its path, query, and headers")
    func parse() throws {
        let request = try #require(HTTPRequest(head: Self.head))
        #expect(request.method == "GET")
        #expect(request.path == "/socket")
        #expect(request.query == ["token": "abc d", "v": "2"])
        #expect(request.headers["host"] == "127.0.0.1:8417")
        #expect(request.isWebSocketUpgrade)
    }

    @Test("The head ends at the first blank line")
    func headLength() {
        #expect(HTTPRequest.headLength(in: Self.head) == Self.head.count)
        #expect(HTTPRequest.headLength(in: Array(Self.head.dropLast(1))) == nil)
        #expect(HTTPRequest.headLength(in: Self.head + [1, 2, 3]) == Self.head.count)
    }

    @Test("Malformed request lines are refused")
    func malformed() {
        #expect(HTTPRequest(head: Array("GET / \r\n\r\n".utf8)) == nil)
        #expect(HTTPRequest(head: Array("GET index HTTP/1.1\r\n\r\n".utf8)) == nil)
        #expect(HTTPRequest(head: Array("GET / SPDY/3\r\n\r\n".utf8)) == nil)
        #expect(HTTPRequest(head: Array("GET / HTTP/1.1\r\nno colon\r\n\r\n".utf8)) == nil)
        #expect(HTTPRequest(head: [0xFF, 0xFE]) == nil)
    }

    @Test("Only a complete WebSocket handshake counts as one")
    func upgrade() throws {
        func request(_ change: (inout HTTPRequest) -> Void) throws -> HTTPRequest {
            var request = try #require(HTTPRequest(head: Self.head))
            change(&request)
            return request
        }
        #expect(try !request { $0.headers["upgrade"] = "h2c" }.isWebSocketUpgrade)
        #expect(try !request { $0.headers["connection"] = "keep-alive" }.isWebSocketUpgrade)
        #expect(try !request { $0.headers["sec-websocket-version"] = "8" }.isWebSocketUpgrade)
        #expect(try !request { $0.headers["sec-websocket-key"] = nil }.isWebSocketUpgrade)
        #expect(try !request { $0.method = "POST" }.isWebSocketUpgrade)
    }

    @Test("Responses close the connection and are never cached or sent as a referrer")
    func responses() {
        let text = String(decoding: HTTPResponse.forbidden.encoded(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 403 Forbidden\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.contains("Cache-Control: no-store\r\n"))
        #expect(text.contains("Referrer-Policy: no-referrer\r\n"))
        #expect(text.contains("Content-Length: \(HTTPResponse.forbidden.body.count)\r\n"))
        let switching = String(
            decoding: HTTPResponse.switchingToWebSocket(key: "dGhlIHNhbXBsZSBub25jZQ==").encoded(),
            as: UTF8.self)
        #expect(switching.hasPrefix("HTTP/1.1 101 Switching Protocols\r\n"))
        #expect(switching.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"))
        #expect(!switching.contains("Content-Length"))
    }

    @Test("Tokens are 128 random bits in hexadecimal")
    func randomTokens() {
        let first = AccessToken.random()
        #expect(first.value.count == 32)
        #expect(first.value.allSatisfy { $0.isHexDigit })
        #expect(first != AccessToken.random())
    }

    @Test("The token admits only requests that carry it exactly")
    func admits() throws {
        let token = AccessToken("0123456789abcdef0123456789abcdef")
        func request(_ target: String) throws -> HTTPRequest {
            try #require(HTTPRequest(head: Array("GET \(target) HTTP/1.1\r\n\r\n".utf8)))
        }
        #expect(try token.admits(request("/?token=0123456789abcdef0123456789abcdef")))
        #expect(try token.admits(request("/socket?v=1&token=0123456789abcdef0123456789abcdef")))
        #expect(try !token.admits(request("/")))
        #expect(try !token.admits(request("/?token=")))
        #expect(try !token.admits(request("/?token=0123456789abcdef0123456789abcdee")))
        #expect(try !token.admits(request("/?token=0123456789abcdef")))
        #expect(try !token.admits(request("/?token=0123456789abcdef0123456789abcdef0")))
        #expect(try !token.admits(request("/?Token=0123456789abcdef0123456789abcdef")))
        #expect(!AccessToken("").admits(try request("/?token=")))
    }
}

@Suite("Messages from the page")
struct PageMessageTests {
    @Test("Input becomes the host messages the window sends")
    func input() {
        #expect(
            PageMessage(json: #"{"type":"down","x":10,"y":20.5}"#)
                == .input(.pointerDown(x: 10, y: 20.5)))
        #expect(
            PageMessage(json: #"{"type":"move","x":0,"y":1}"#) == .input(.pointerMoved(x: 0, y: 1)))
        #expect(
            PageMessage(json: #"{"type":"up","x":-3,"y":4}"#) == .input(.pointerUp(x: -3, y: 4)))
        #expect(
            PageMessage(json: #"{"type":"scroll","dx":0,"dy":-40,"x":100,"y":200}"#)
                == .input(.scroll(dx: 0, dy: -40, x: 100, y: 200)))
        #expect(PageMessage(json: #"{"type":"text","text":"é✓"}"#) == .input(.text("é✓")))
        #expect(PageMessage(json: #"{"type":"key","key":"backTab"}"#) == .input(.key("backTab")))
        #expect(PageMessage(json: #"{"type":"ack","sequence":7}"#) == .acknowledge(7))
    }

    @Test("The page's controls ask for an appearance or a text size by name")
    func appearance() {
        #expect(
            PageMessage(json: #"{"type":"appearance","colorScheme":"dark"}"#)
                == .appearance(.set(colorScheme: "dark", dynamicTypeSize: nil)))
        #expect(
            PageMessage(json: #"{"type":"appearance","dynamicTypeSize":"accessibility5"}"#)
                == .appearance(.set(colorScheme: nil, dynamicTypeSize: "accessibility5")))
    }

    @Test("Anything else is refused, including the host's other messages")
    func refused() {
        let refused = [
            #"{"type":"close"}"#,
            #"{"type":"command","command":{"inspect":{"json":true}}}"#,
            #"{"close":{}}"#,
            #"{"type":"tick","targetTime":1}"#,
            #"{"type":"down","x":10}"#,
            #"{"type":"down","x":true,"y":1}"#,
            #"{"type":"down","x":"10","y":1}"#,
            #"{"type":"down","x":1e9,"y":1}"#,
            #"{"type":"key","key":"f5"}"#,
            #"{"type":"text","text":""}"#,
            #"{"type":"ack","sequence":-1}"#,
            #"{"type":"appearance"}"#,
            #"{"type":"appearance","colorScheme":"sepia"}"#,
            #"{"type":"appearance","colorScheme":"dark","dynamicTypeSize":"huge"}"#,
            "[]",
            "not json",
        ]
        for json in refused { #expect(PageMessage(json: json) == nil, "\(json)") }
        let long = String(repeating: "a", count: PageMessage.maximumTextLength + 1)
        #expect(PageMessage(json: #"{"type":"text","text":"\#(long)"}"#) == nil)
    }
}
